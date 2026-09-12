import type { Page } from '@playwright/test'

import { expect, fact, factIn, group, holdRequest, test } from './fixtures'

// The screen is read whole — the list card and both debug strips — and a
// 720-tall window cuts the second strip off. Only what is on screen is in
// Flutter's semantics tree, so the window is made taller instead of scrolled.
test.use({ viewport: { width: 1280, height: 960 } })

/// Post `id`'s row: a semantics group of its own, so the `prefetched` pill
/// can be tied to its post.
const row = (page: Page, id: number) => group(page, `post ${id}`)

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

  await expect(page.getByText('Continuous integration: setup guide')).toBeVisible()
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

  await expect(page.getByText('Code review: setup guide')).toBeVisible()
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
  await expect(page.getByText('Release notes: setup guide')).toBeVisible()
  await expect(fact(page, 'post-4', 'status=success')).toBeVisible()
  await expect(fact(page, 'post-4', 'failures=0')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/4$/)).toBe(2)
})

// The imperative-read card and its own strip sit below everything else, and
// only what is on screen is in the semantics tree, so these tests get a taller
// window of their own.
test.describe('imperative reads', () => {
  test.use({ viewport: { width: 1280, height: 1400 } })

  /// The imperative-read card: a semantics group of its own, so `returned=0`
  /// cannot be confused with a fact of a debug strip.
  const reads = (page: Page) => group(page, 'reads')
  const readFact = (page: Page, text: string) => reads(page).getByText(text, { exact: true })

  /// Puts a value in the counter's cache entry and moves the server's counter
  /// past it: from here a read's answer says whether it came from the cache
  /// (`0`) or from the backend (`1`).
  async function seedThenMoveTheServer(page: Page) {
    await page.getByRole('button', { name: 'Read (await)', exact: true }).click()
    await expect(readFact(page, 'returned=0')).toBeVisible()
    await expect(readFact(page, 'cached=0')).toBeVisible()

    await page.getByRole('button', { name: 'Increment on the server', exact: true }).click()
    await expect(readFact(page, 'increments=1')).toBeVisible()
    // The increment went nowhere near the cache: it still holds the old value.
    await expect(readFact(page, 'cached=0')).toBeVisible()
  }

  test('revalidateIfStale returns the cached value at once and refreshes behind it', async ({ page, open, scenario }) => {
    await scenario.config({ latency: 0 })
    await open('/prefetching')
    await expect(fact(page, 'posts', 'status=success')).toBeVisible()
    await seedThenMoveTheServer(page)

    // The refresh is held in the browser: a value that shows while the hold
    // has caught it and not let it go came from the cache.
    const hold = holdRequest(page, '**/api/counter')
    await page.getByRole('button', { name: 'Read (revalidateIfStale)', exact: true }).click()

    await expect(readFact(page, 'read=revalidate')).toBeVisible()
    await expect(readFact(page, 'returned=0')).toBeVisible()
    await expect(readFact(page, 'cached=0')).toBeVisible()
    await expect(fact(page, 'counter', 'fetchStatus=fetching')).toBeVisible()
    await hold.release()

    // The refresh landed behind the answer: the cache holds the server's
    // value, and what the call returned is still the old one.
    await expect(readFact(page, 'cached=1')).toBeVisible()
    await expect(readFact(page, 'returned=0')).toBeVisible()
    await expect(readFact(page, 'requests=2')).toBeVisible()
    await expect(fact(page, 'counter', 'fetchStatus=idle')).toBeVisible()
    expect(await scenario.count('GET', /^\/api\/counter$/)).toBe(2)
  })

  test('the plain read awaits the fetch and returns the new value', async ({ page, open, scenario }) => {
    await scenario.config({ latency: 0 })
    await open('/prefetching')
    await expect(fact(page, 'posts', 'status=success')).toBeVisible()
    await seedThenMoveTheServer(page)

    await page.getByRole('button', { name: 'Read (await)', exact: true }).click()

    await expect(readFact(page, 'returned=1')).toBeVisible()
    await expect(readFact(page, 'cached=1')).toBeVisible()
    await expect(readFact(page, 'requests=2')).toBeVisible()
    expect(await scenario.count('GET', /^\/api\/counter$/)).toBe(2)
  })

  test('a static read hands back the cached value and makes no request', async ({ page, open, scenario }) => {
    await scenario.config({ latency: 0 })
    await open('/prefetching')
    await expect(fact(page, 'posts', 'status=success')).toBeVisible()
    await seedThenMoveTheServer(page)

    await page.getByRole('button', { name: 'Read (static)', exact: true }).click()

    await expect(readFact(page, 'read=static')).toBeVisible()
    await expect(readFact(page, 'returned=0')).toBeVisible()
    // Nothing to wait for on a read that fetches nothing: sample after a
    // pause a fetch would have needed, and the counts still say one.
    await page.waitForTimeout(500)
    await expect(readFact(page, 'cached=0')).toBeVisible()
    await expect(readFact(page, 'requests=1')).toBeVisible()
    await expect(fact(page, 'counter', 'fetchStatus=idle')).toBeVisible()
    await expect(fact(page, 'counter', 'updates=1')).toBeVisible()
    expect(await scenario.count('GET', /^\/api\/counter$/)).toBe(1)
  })
})

// The fourth card and its strip sit under everything else.
test.describe('the infinite twin', () => {
  test.use({ viewport: { width: 1280, height: 2000 } })

  const infinite = (page: Page, text: string) => factIn(page, 'infinite prefetch', text)

  test('an infinite prefetch is one request for the first page, held by nobody; a second is a no-op', async ({
    page,
    open,
    scenario,
  }) => {
    await scenario.config({ latency: 0 })
    await open('/prefetching')
    await expect(infinite(page, 'pages=0')).toBeVisible()
    await expect(fact(page, 'projects', 'status=absent')).toBeVisible()

    await page.getByRole('button', { name: 'Prefetch the first page', exact: true }).click()

    await expect(infinite(page, 'pages=1')).toBeVisible()
    await expect(infinite(page, 'rows=10')).toBeVisible()
    await expect(fact(page, 'projects', 'status=success')).toBeVisible()
    await expect(fact(page, 'projects', 'observers=0')).toBeVisible()
    await expect(fact(page, 'projects', 'fetches=1')).toBeVisible()
    expect(await scenario.count('GET', /^\/api\/projects$/)).toBe(1)

    // Fresh for five minutes: the same call hands back the cached page.
    await page.getByRole('button', { name: 'Prefetch the first page', exact: true }).click()
    await page.waitForTimeout(500)
    await expect(fact(page, 'projects', 'fetches=1')).toBeVisible()
    expect(await scenario.count('GET', /^\/api\/projects$/)).toBe(1)
  })
})
