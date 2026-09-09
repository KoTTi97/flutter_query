import type { Page } from '@playwright/test'

import { expect, fact, holdRequest, test } from './fixtures'

// The screen is read whole — the list card and both debug strips — and a
// 720-tall window cuts the second strip off. Only what is on screen is in
// Flutter's semantics tree, so the window is made taller instead of scrolled.
test.use({ viewport: { width: 1280, height: 960 } })

/// Post `id`'s row: a semantics group of its own, so the `prefetched` pill
/// can be tied to its post.
const row = (page: Page, id: number) => page.getByRole('group', { name: `post ${id}`, exact: true })

test('a prefetch is one request and marks the row while nobody observes the entry', async ({ page, open, scenario }) => {
  await open('/prefetching')
  await expect(fact(page, 'posts', 'status=success')).toBeVisible()
  await expect(row(page, 2).getByText('prefetched', { exact: true })).toHaveCount(0)

  await page.getByRole('button', { name: 'Prefetch post 2', exact: true }).click()

  await expect(fact(page, 'post-2', 'status=success')).toBeVisible()
  await expect(fact(page, 'post-2', 'observers=0')).toBeVisible()
  await expect(fact(page, 'post-2', 'fetches=1')).toBeVisible()
  await expect(row(page, 2).getByText('prefetched', { exact: true })).toBeVisible()
  await expect(row(page, 3).getByText('prefetched', { exact: true })).toHaveCount(0)
  expect(await scenario.count('GET', /^\/api\/posts\/2$/)).toBe(1)
  expect(await scenario.count('GET', /^\/api\/posts$/)).toBe(1)
})

test('opening a prefetched post costs no request and shows the title at once', async ({ page, open, scenario }) => {
  await open('/prefetching')
  await page.getByRole('button', { name: 'Prefetch post 2', exact: true }).click()
  await expect(fact(page, 'post-2', 'status=success')).toBeVisible()

  // Any request the open might make is held in the browser: a title that
  // appears while the hold has caught nothing came from the cache.
  const hold = holdRequest(page, '**/api/posts/2*')
  await page.getByRole('button', { name: 'Open post 2', exact: true }).click()

  await expect(page.getByText('Motion sensor: setup guide')).toBeVisible()
  await expect(fact(page, 'post-2', 'observers=1')).toBeVisible()
  await expect(fact(page, 'post-2', 'fetchStatus=idle')).toBeVisible()
  expect(hold.seen).toBe(0)
  await hold.release()

  await expect(fact(page, 'post-2', 'fetches=1')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/2$/)).toBe(1)
})

test('opening a post nobody prefetched costs one request', async ({ page, open, scenario }) => {
  await open('/prefetching')
  await expect(fact(page, 'posts', 'status=success')).toBeVisible()

  await page.getByRole('button', { name: 'Open post 3', exact: true }).click()

  await expect(page.getByText('Thermostat: setup guide')).toBeVisible()
  await expect(fact(page, 'post-3', 'status=success')).toBeVisible()
  await expect(fact(page, 'post-3', 'fetches=1')).toBeVisible()
  await expect(fact(page, 'post-3', 'observers=1')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/3$/)).toBe(1)

  // Back on the list the row is marked: the pill reads the cache, and an
  // open leaves the same entry behind as a prefetch would.
  await page.getByRole('button', { name: 'Back to list', exact: true }).click()
  await expect(row(page, 3).getByText('prefetched', { exact: true })).toBeVisible()
  await expect(fact(page, 'post-3', 'observers=0')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/3$/)).toBe(1)
})

test('a second prefetch within staleTime is a no-op', async ({ page, open, scenario }) => {
  await open('/prefetching')
  await page.getByRole('button', { name: 'Prefetch post 2', exact: true }).click()
  await expect(fact(page, 'post-2', 'fetches=1')).toBeVisible()

  await page.getByRole('button', { name: 'Prefetch post 2', exact: true }).click()

  // Nothing to wait for on a no-op: sample the count after a pause the
  // fetch would need, and the strip still says one.
  await page.waitForTimeout(500)
  await expect(fact(page, 'post-2', 'fetches=1')).toBeVisible()
  await expect(fact(page, 'post-2', 'isStale=false')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/2$/)).toBe(1)
})

test('a refused prefetch leaves the row unmarked and the post opens normally afterwards', async ({ page, open, scenario }) => {
  // One attempt only: the prefetch options say `retry: RetryPolicy.never`.
  await scenario.config({ latency: 0, failNext: [{ method: 'GET', path: '/api/posts/4', count: 1, status: 503 }] })
  await open('/prefetching')
  await expect(fact(page, 'posts', 'status=success')).toBeVisible()

  await page.getByRole('button', { name: 'Prefetch post 4', exact: true }).click()

  await expect(fact(page, 'post-4', 'status=error')).toBeVisible()
  await expect(fact(page, 'post-4', 'failures=1')).toBeVisible()
  await expect(fact(page, 'post-4', 'observers=0')).toBeVisible()
  await expect(row(page, 4).getByText('prefetched', { exact: true })).toHaveCount(0)
  await expect(page.getByText('Scripted failure 503')).toHaveCount(0)
  expect(await scenario.count('GET', /^\/api\/posts\/4$/)).toBe(1)

  // The scripted failure was spent on the prefetch; the open fetches
  // like any first open would.
  await page.getByRole('button', { name: 'Open post 4', exact: true }).click()
  await expect(page.getByText('Smoke detector: setup guide')).toBeVisible()
  await expect(fact(page, 'post-4', 'status=success')).toBeVisible()
  await expect(fact(page, 'post-4', 'failures=0')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/4$/)).toBe(2)
})
