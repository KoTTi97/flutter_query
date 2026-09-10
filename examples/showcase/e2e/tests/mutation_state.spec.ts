import { expect, fact, holdRequest, test } from './fixtures'

test('the badge starts empty', async ({ page, open }) => {
  await open('/mutation-state')

  await expect(page.getByText('saving=0', { exact: true })).toBeVisible()
  await expect(page.getByText('failed=0', { exact: true })).toBeVisible()
  await expect(page.getByText('tracked=0', { exact: true })).toBeVisible()
})

test('two concurrent runs under one key count as two', async ({ page, open, scenario }) => {
  await open('/mutation-state')
  await expect(page.getByText('saving=0', { exact: true })).toBeVisible()

  // Hold both writes open in the browser, so "concurrent" is a fact about
  // the requests rather than about how fast the clicks were.
  const hold = holdRequest(page, '**/api/todos*')
  const add = page.getByRole('button', { name: 'Add todo', exact: true })
  await add.click()
  await add.click()

  await expect.poll(() => hold.seen).toBe(2)
  // The badge owns neither mutation; it reads them from the cache.
  await expect(page.getByText('saving=2', { exact: true })).toBeVisible()
  await expect(page.getByText('tracked=2', { exact: true })).toBeVisible()
  await hold.release()

  await expect(page.getByText('saving=0', { exact: true })).toBeVisible()
  await expect(page.getByText('failed=0', { exact: true })).toBeVisible()
  expect(await scenario.count('POST', /^\/api\/todos$/)).toBe(2)
})

test('a failing run is an error, not a pending one', async ({ page, open }) => {
  await open('/mutation-state')
  await expect(page.getByText('saving=0', { exact: true })).toBeVisible()

  await page.getByRole('button', { name: 'Add, failing', exact: true }).click()

  await expect(page.getByText('saving=1', { exact: true })).toBeVisible()
  await expect(page.getByText('failed=1', { exact: true })).toBeVisible()
  await expect(page.getByText('saving=0', { exact: true })).toBeVisible()
})

test('a settled run leaves the todos entry refreshed', async ({ page, open }) => {
  await open('/mutation-state')
  await expect(page.getByText('saving=0', { exact: true })).toBeVisible()

  await page.getByRole('button', { name: 'Add todo', exact: true }).click()

  // onSuccess invalidates the list, so the strip shows a second fetch.
  await expect(page.getByText('saving=0', { exact: true })).toBeVisible()
  await expect(fact(page, 'todos', 'status=success')).toBeVisible()
})
