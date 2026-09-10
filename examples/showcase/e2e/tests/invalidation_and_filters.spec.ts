import type { Page } from '@playwright/test'
import { expect, fact, test } from './fixtures'

// Twelve buttons, four readers and five strips: taller than a default
// viewport, and a lazily built list only has what is in view.
test.use({ viewport: { width: 1280, height: 1800 } })

const labels = ['posts', 'post-1', 'post-2', 'post-3', 'todos'] as const

const button = (page: Page, name: string) => page.getByRole('button', { name, exact: true })

// Every entry settled after exactly one fetch.
async function openSettled(page: Page, open: (route: string) => Promise<void>) {
  await open('/invalidation-and-filters')
  for (const label of labels) {
    await expect(fact(page, label, 'status=success')).toBeVisible()
    await expect(fact(page, label, 'fetches=1')).toBeVisible()
  }
  await expect(fact(page, 'post-3', 'observers=0')).toBeVisible()
}

test('the posts prefix refetches the active entries and only marks post 3', async ({ page, open, scenario }) => {
  await openSettled(page, open)
  await expect(fact(page, 'post-3', 'isStale=false')).toBeVisible()

  await button(page, 'Invalidate posts prefix').click()

  await expect(fact(page, 'posts', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'post-1', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'post-2', 'fetches=2')).toBeVisible()
  // Marked, not fetched: nobody observes it.
  await expect(fact(page, 'post-3', 'isStale=true')).toBeVisible()
  await expect(fact(page, 'post-3', 'fetches=1')).toBeVisible()
  await expect(fact(page, 'todos', 'fetches=1')).toBeVisible()
  await expect(fact(page, 'todos', 'isStale=false')).toBeVisible()
  for (const label of labels) {
    await expect(fact(page, label, 'fetchStatus=idle')).toBeVisible()
  }
  expect(await scenario.count('GET', /^\/api\/posts$/)).toBe(2)
  expect(await scenario.count('GET', /^\/api\/posts\/1$/)).toBe(2)
  expect(await scenario.count('GET', /^\/api\/posts\/2$/)).toBe(2)
  expect(await scenario.count('GET', /^\/api\/posts\/3$/)).toBe(1)
  expect(await scenario.count('GET', /^\/api\/todos$/)).toBe(1)
})

test('exact: true refetches the list alone', async ({ page, open, scenario }) => {
  await openSettled(page, open)

  await button(page, 'Invalidate posts exactly').click()

  await expect(fact(page, 'posts', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'posts', 'fetchStatus=idle')).toBeVisible()
  for (const label of ['post-1', 'post-2', 'post-3', 'todos'] as const) {
    await expect(fact(page, label, 'fetches=1')).toBeVisible()
  }
  await expect(fact(page, 'post-3', 'isStale=false')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts$/)).toBe(2)
  expect(await scenario.count('GET', /^\/api\/posts\/\d+$/)).toBe(3)
})

test('RefetchType.all refetches the unobserved post 3 as well', async ({ page, open, scenario }) => {
  await openSettled(page, open)

  await button(page, 'Invalidate inactive too').click()

  for (const label of ['posts', 'post-1', 'post-2', 'post-3'] as const) {
    await expect(fact(page, label, 'fetches=2')).toBeVisible()
    await expect(fact(page, label, 'fetchStatus=idle')).toBeVisible()
  }
  await expect(fact(page, 'post-3', 'observers=0')).toBeVisible()
  await expect(fact(page, 'post-3', 'updates=2')).toBeVisible()
  await expect(fact(page, 'todos', 'fetches=1')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/3$/)).toBe(2)
})

test('stale: true refetches the posts and not the fresh todos', async ({ page, open, scenario }) => {
  await openSettled(page, open)

  await button(page, 'Refetch stale only').click()

  await expect(fact(page, 'posts', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'post-1', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'post-2', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'post-2', 'fetchStatus=idle')).toBeVisible()
  // Fresh for thirty seconds; and post 3, unobserved and never invalidated,
  // counts as fresh too.
  await expect(fact(page, 'todos', 'fetches=1')).toBeVisible()
  await expect(fact(page, 'todos', 'isStale=false')).toBeVisible()
  await expect(fact(page, 'post-3', 'fetches=1')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/todos$/)).toBe(1)
  expect(await scenario.count('GET', /^\/api\/posts\/3$/)).toBe(1)
})

test('resetting post 1 goes back to pending and refetches', async ({ page, open, scenario }) => {
  await openSettled(page, open)

  await button(page, 'Reset post 1').click()

  // Counted from zero again: a reset is the initial state, not stale data.
  await expect(fact(page, 'post-1', 'updates=1')).toBeVisible()
  await expect(fact(page, 'post-1', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'post-1', 'status=success')).toBeVisible()
  await expect(page.getByText('Local development: setup guide', { exact: true })).toBeVisible()
  await expect(fact(page, 'post-2', 'fetches=1')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/1$/)).toBe(2)
})

test('removing post 2 drops the entry while its reader keeps the last result', async ({ page, open, scenario }) => {
  await openSettled(page, open)

  await button(page, 'Remove post 2').click()

  // The entry is gone; the observer still reports what it last saw, and
  // nothing is fetched for it — not even by a prefix invalidation.
  await expect(fact(page, 'post-2', 'status=absent')).toBeVisible()
  await expect(page.getByText('Continuous integration: setup guide', { exact: true })).toBeVisible()
  await button(page, 'Invalidate posts prefix').click()
  await expect(fact(page, 'post-1', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'post-2', 'status=absent')).toBeVisible()
  await expect(fact(page, 'post-2', 'fetches=1')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/2$/)).toBe(1)

  // Given its options again, the observer resolves the key afresh and the
  // new entry fetches.
  await button(page, 'Re-attach post 2').click()
  await expect(fact(page, 'post-2', 'status=success')).toBeVisible()
  await expect(fact(page, 'post-2', 'observers=1')).toBeVisible()
  await expect(fact(page, 'post-2', 'fetches=2')).toBeVisible()
  await expect(page.getByText('Continuous integration: setup guide', { exact: true })).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/2$/)).toBe(2)
})

test('cancelling the slow refetch leaves the list idle with its old data', async ({ page, open }) => {
  await openSettled(page, open)

  // The request asks the backend for two seconds, so the cancel lands while
  // it is provably in flight.
  await button(page, 'Refetch posts slowly').click()
  await expect(fact(page, 'posts', 'fetchStatus=fetching')).toBeVisible()
  await expect(fact(page, 'posts', 'fetches=2')).toBeVisible()
  await expect(page.getByText('refreshing', { exact: true })).toBeVisible()

  await button(page, 'Cancel posts').click()

  // Reverted: idle, the old data, no failure counted, no new fetch.
  await expect(fact(page, 'posts', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'posts', 'status=success')).toBeVisible()
  await expect(fact(page, 'posts', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'posts', 'updates=1')).toBeVisible()
  await expect(fact(page, 'posts', 'failures=0')).toBeVisible()
  await expect(page.getByText('refreshing', { exact: true })).toBeHidden()
  await expect(page.getByText('30 posts', { exact: true })).toBeVisible()

  // Whatever the backend does with the request it was given — the client
  // has let go of it — the entry does not change once its delay has passed.
  await page.waitForTimeout(2_500)
  await expect(fact(page, 'posts', 'updates=1')).toBeVisible()
  await expect(fact(page, 'posts', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'posts', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'posts', 'failures=0')).toBeVisible()
})

test('the errored predicate refetches post 2 alone', async ({ page, open, scenario }) => {
  await openSettled(page, open)

  const fail = page.getByRole('checkbox', { name: 'Fail post 2 next' })
  await fail.click()
  await expect(fail).toBeChecked()

  // No retries on post 2: one refused answer is the error state, with the
  // stale data still next to it.
  await button(page, 'Refetch post 2').click()
  await expect(fact(page, 'post-2', 'status=error')).toBeVisible()
  await expect(fact(page, 'post-2', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'post-2', 'failures=1')).toBeVisible()
  await expect(page.getByText('Scripted failure 500', { exact: true })).toBeVisible()
  await expect(page.getByText('Continuous integration: setup guide', { exact: true })).toBeVisible()
  // The tick was spent by that fetch.
  await expect(fail).not.toBeChecked()
  const refused = (await scenario.requests()).filter((entry) => entry.path === '/api/posts/2' && entry.status === 500)
  expect(refused).toHaveLength(1)

  await button(page, 'Predicate: errored').click()

  await expect(fact(page, 'post-2', 'status=success')).toBeVisible()
  await expect(fact(page, 'post-2', 'fetches=3')).toBeVisible()
  await expect(fact(page, 'post-2', 'failures=0')).toBeVisible()
  await expect(page.getByText('Scripted failure 500', { exact: true })).toBeHidden()
  for (const label of ['posts', 'post-1', 'post-3', 'todos'] as const) {
    await expect(fact(page, label, 'fetches=1')).toBeVisible()
  }
  expect(await scenario.count('GET', /^\/api\/posts\/2$/)).toBe(3)
  expect(await scenario.count('GET', /^\/api\/posts\/1$/)).toBe(1)
})

test('uppercasing the titles is a cache write, not a fetch', async ({ page, open, scenario }) => {
  await openSettled(page, open)
  const requestsBefore = (await scenario.requests()).length

  await button(page, 'Uppercase all post titles').click()

  await expect(page.getByText('matched=2', { exact: true })).toBeVisible()
  await expect(page.getByText('LOCAL DEVELOPMENT: SETUP GUIDE', { exact: true })).toBeVisible()
  await expect(page.getByText('CONTINUOUS INTEGRATION: SETUP GUIDE', { exact: true })).toBeVisible()
  // A manual write counts as an update, never as a fetch; the unobserved
  // post 3 is left out by `type: active`.
  await expect(fact(page, 'post-1', 'updates=2')).toBeVisible()
  await expect(fact(page, 'post-2', 'updates=2')).toBeVisible()
  await expect(fact(page, 'post-1', 'fetches=1')).toBeVisible()
  await expect(fact(page, 'post-2', 'fetches=1')).toBeVisible()
  await expect(fact(page, 'post-3', 'updates=1')).toBeVisible()
  expect((await scenario.requests()).length).toBe(requestsBefore)
})
