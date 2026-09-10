import { expect, fact, holdRequest, test } from './fixtures'

const initial = [1, 2, 3]

test('the collection fetches every member once, in parallel', async ({ page, open, scenario }) => {
  // Held before the screen opens: a sequential collection would show one.
  const hold = holdRequest(page, '**/api/posts/*')
  await open('/query-collections')

  await expect.poll(() => hold.seen).toBe(3)
  await expect(page.getByText('ids=1,2,3', { exact: true })).toBeVisible()
  for (const id of initial) {
    await expect(fact(page, `post-${id}`, 'fetchStatus=fetching')).toBeVisible()
  }
  await hold.release()

  for (const id of initial) {
    await expect(fact(page, `post-${id}`, 'status=success')).toBeVisible()
    await expect(fact(page, `post-${id}`, 'observers=1')).toBeVisible()
    await expect(fact(page, `post-${id}`, 'fetches=1')).toBeVisible()
    expect(await scenario.count('GET', new RegExp(`^/api/posts/${id}$`))).toBe(1)
  }
  // `select` narrowed each post to its title.
  await expect(page.getByText('Window contact: setup guide')).toBeVisible()
})

test('reversing reuses every observer and sends nothing', async ({ page, open, scenario }) => {
  await open('/query-collections')
  await expect(fact(page, 'post-3', 'status=success')).toBeVisible()

  await page.getByRole('button', { name: 'Reverse', exact: true }).click()

  await expect(page.getByText('ids=3,2,1', { exact: true })).toBeVisible()
  await expect(page.getByText('#1 — post 3')).toBeVisible()
  await expect(page.getByText('#3 — post 1')).toBeVisible()
  for (const id of initial) {
    await expect(fact(page, `post-${id}`, 'fetches=1')).toBeVisible()
    expect(await scenario.count('GET', new RegExp(`^/api/posts/${id}$`))).toBe(1)
  }
})

test('growing fetches only the newcomer', async ({ page, open, scenario }) => {
  await open('/query-collections')
  await expect(fact(page, 'post-3', 'status=success')).toBeVisible()

  await page.getByRole('button', { name: 'Add post', exact: true }).click()

  await expect(page.getByText('ids=1,2,3,4', { exact: true })).toBeVisible()
  await expect(fact(page, 'post-4', 'status=success')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/4$/)).toBe(1)
  for (const id of initial) {
    expect(await scenario.count('GET', new RegExp(`^/api/posts/${id}$`))).toBe(1)
  }
})

test('shrinking releases the observer that left', async ({ page, open }) => {
  await open('/query-collections')
  await expect(fact(page, 'post-3', 'status=success')).toBeVisible()

  await page.getByRole('button', { name: 'Remove last', exact: true }).click()

  await expect(page.getByText('ids=1,2', { exact: true })).toBeVisible()
  await expect(fact(page, 'post-3', 'observers=0')).toBeVisible()
  await expect(fact(page, 'post-1', 'observers=1')).toBeVisible()
})

test('a duplicate id shares one cache entry', async ({ page, open, scenario }) => {
  await open('/query-collections')
  await expect(fact(page, 'post-1', 'status=success')).toBeVisible()

  await page.getByRole('button', { name: 'Duplicate first', exact: true }).click()

  await expect(page.getByText('ids=1,2,3,1', { exact: true })).toBeVisible()
  // Two observers, one entry. The newcomer found it stale and refetched it
  // once — shared, not once per observer.
  await expect(fact(page, 'post-1', 'observers=2')).toBeVisible()
  await expect(fact(page, 'post-1', 'fetches=2')).toBeVisible()
  // The strip counts a fetch when it starts, the server when it arrives, so
  // the totals are polled rather than read once.
  await expect.poll(() => scenario.count('GET', /^\/api\/posts\/1$/)).toBe(2)
  expect(await scenario.count('GET', /^\/api\/posts\/2$/)).toBe(1)
})

test('a missing id fails without disturbing its neighbours', async ({ page, open }) => {
  await open('/query-collections')
  await expect(fact(page, 'post-1', 'status=success')).toBeVisible()

  await page.getByRole('button', { name: 'Add missing id', exact: true }).click()

  await expect(page.getByText('ids=1,2,3,999', { exact: true })).toBeVisible()
  await expect(fact(page, 'post-999', 'status=error')).toBeVisible()
  for (const id of initial) {
    await expect(fact(page, `post-${id}`, 'status=success')).toBeVisible()
  }
  await expect(page.getByText('Window contact: setup guide')).toBeVisible()
})
