import { expect, fact, holdRequest, test } from './fixtures'

const posts = [1, 2, 3]

test('opening the screen sends all three requests before any is answered', async ({ page, open, scenario }) => {
  // Held in the browser before the screen opens: if the three requests were
  // sequential, the hold would only ever see the first one.
  const hold = holdRequest(page, '**/api/posts/*')
  await open('/parallel-queries')

  await expect.poll(() => hold.seen).toBe(3)
  await expect(page.getByText('fetching=3', { exact: true })).toBeVisible()
  for (const id of posts) {
    await expect(fact(page, `post-${id}`, 'status=pending')).toBeVisible()
    await expect(fact(page, `post-${id}`, 'fetchStatus=fetching')).toBeVisible()
  }
  expect(await scenario.count('GET', /^\/api\/posts\/\d+$/)).toBe(0)
  await hold.release()

  await expect(page.getByText('fetching=0', { exact: true })).toBeVisible()
  await expect(page.getByText('Window contact: setup guide')).toBeVisible()
  await expect(page.getByText('Motion sensor: setup guide')).toBeVisible()
  await expect(page.getByText('Thermostat: setup guide')).toBeVisible()
  for (const id of posts) {
    await expect(fact(page, `post-${id}`, 'status=success')).toBeVisible()
    await expect(fact(page, `post-${id}`, 'fetchStatus=idle')).toBeVisible()
    await expect(fact(page, `post-${id}`, 'fetches=1')).toBeVisible()
    await expect(fact(page, `post-${id}`, 'observers=1')).toBeVisible()
    expect(await scenario.count('GET', new RegExp(`^/api/posts/${id}$`))).toBe(1)
  }
})

test('refetch all bumps every entry and the count comes back to 0', async ({ page, open, scenario }) => {
  await open('/parallel-queries')
  await expect(page.getByText('fetching=0', { exact: true })).toBeVisible()

  await page.getByRole('button', { name: 'Refetch all', exact: true }).click()

  for (const id of posts) {
    await expect(fact(page, `post-${id}`, 'fetches=2')).toBeVisible()
  }
  await expect(page.getByText('fetching=0', { exact: true })).toBeVisible()
  for (const id of posts) {
    await expect(fact(page, `post-${id}`, 'fetchStatus=idle')).toBeVisible()
    expect(await scenario.count('GET', new RegExp(`^/api/posts/${id}$`))).toBe(2)
  }
})

test('refetch post 2 bumps only post-2', async ({ page, open, scenario }) => {
  await open('/parallel-queries')
  await expect(page.getByText('fetching=0', { exact: true })).toBeVisible()

  const hold = holdRequest(page, '**/api/posts/2*')
  await page.getByRole('button', { name: 'Refetch post 2', exact: true }).click()

  await expect(page.getByText('fetching=1', { exact: true })).toBeVisible()
  await expect(fact(page, 'post-2', 'fetchStatus=fetching')).toBeVisible()
  await expect(page.getByText('refreshing', { exact: true })).toHaveCount(1)
  await expect(fact(page, 'post-1', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'post-3', 'fetchStatus=idle')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Refetch all', exact: true })).toHaveAttribute('aria-disabled', 'true')
  await hold.release()

  await expect(fact(page, 'post-2', 'fetches=2')).toBeVisible()
  await expect(page.getByText('fetching=0', { exact: true })).toBeVisible()
  await expect(fact(page, 'post-1', 'fetches=1')).toBeVisible()
  await expect(fact(page, 'post-3', 'fetches=1')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/1$/)).toBe(1)
  expect(await scenario.count('GET', /^\/api\/posts\/2$/)).toBe(2)
  expect(await scenario.count('GET', /^\/api\/posts\/3$/)).toBe(1)
})

test('with post 3 held back the other two settle while it still fetches', async ({ page, open, scenario }) => {
  await open('/parallel-queries')
  await expect(page.getByText('fetching=0', { exact: true })).toBeVisible()

  // The hold stands in for the "Slow post 3" switch: it makes "later" exact
  // rather than two seconds on a clock.
  const hold = holdRequest(page, '**/api/posts/3*')
  await page.getByRole('button', { name: 'Refetch all', exact: true }).click()

  await expect(fact(page, 'post-1', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'post-2', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'post-1', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'post-2', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'post-3', 'fetchStatus=fetching')).toBeVisible()
  await expect(page.getByText('fetching=1', { exact: true })).toBeVisible()
  await expect(page.getByText('refreshing', { exact: true })).toHaveCount(1)
  expect(await scenario.count('GET', /^\/api\/posts\/3$/)).toBe(1)
  await hold.release()

  await expect(fact(page, 'post-3', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'post-3', 'fetchStatus=idle')).toBeVisible()
  await expect(page.getByText('fetching=0', { exact: true })).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/3$/)).toBe(2)
})

test('the slow switch asks the backend for a delay on post 3 only', async ({ page, open, scenario }) => {
  await open('/parallel-queries')
  await expect(page.getByText('fetching=0', { exact: true })).toBeVisible()

  await page.getByLabel('Slow post 3', { exact: true }).or(page.getByText('Slow post 3', { exact: true })).click()
  await page.getByRole('button', { name: 'Refetch all', exact: true }).click()

  for (const id of posts) {
    await expect(fact(page, `post-${id}`, 'fetches=2')).toBeVisible()
  }
  await expect(page.getByText('fetching=0', { exact: true })).toBeVisible()
  const log = await scenario.requests()
  const delayed = log.filter((entry) => entry.method === 'GET' && entry.query.delay !== undefined)
  expect(delayed.map((entry) => entry.path)).toEqual(['/api/posts/3'])
  expect(delayed[0].query.delay).toBe('2000')
})

test('leaving the screen releases every observer', async ({ page, open }) => {
  await open('/parallel-queries')
  for (const id of posts) {
    await expect(fact(page, `post-${id}`, 'observers=1')).toBeVisible()
  }

  await page.getByRole('button', { name: 'Back', exact: true }).click()
  await expect(page.getByText('TanStack Query Showcase')).toBeVisible()

  // The entries outlive the screen. Back on it, each is held by the new
  // observer alone — a leaked one would make it 2 — and the stale data
  // refetches on mount.
  await page.getByRole('button', { name: /^Parallel queries/ }).click()
  for (const id of posts) {
    await expect(fact(page, `post-${id}`, 'observers=1')).toBeVisible()
    await expect(fact(page, `post-${id}`, 'updates=2')).toBeVisible()
  }
})
