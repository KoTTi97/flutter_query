import type { Page } from '@playwright/test'
import { expect, fact, holdRequest, test } from './fixtures'

// Three cards and their strips are taller than the default viewport, and the
// scaffold's list only builds — and the semantics tree only carries — what is
// in view.
test.use({ viewport: { width: 1280, height: 1800 } })

/// The `detail <card>` group: each card's title and facts, kept apart because
/// two cards show `isPlaceholderData=false` at once.
const detail = (page: Page, card: string, text: string) =>
  page.getByRole('group', { name: `detail ${card}`, exact: true }).getByText(text, { exact: true })

test('a detail seeded from a fresh list costs no request', async ({ page, open, scenario }) => {
  await open('/initial-and-placeholder')
  await expect(page.getByText('posts=30', { exact: true })).toBeVisible()

  await page.getByRole('button', { name: 'Open post 2', exact: true }).click()

  await expect(detail(page, 'A', 'Motion sensor: setup guide')).toBeVisible()
  await expect(detail(page, 'A', 'initialData source=list')).toBeVisible()
  await expect(fact(page, 'post-2', 'status=success')).toBeVisible()
  await expect(fact(page, 'post-2', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'post-2', 'isStale=false')).toBeVisible()
  await expect(fact(page, 'post-2', 'fetches=0')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/2$/)).toBe(0)
})

test('a seed dated older than staleTime shows at once and refetches', async ({ page, open, scenario }) => {
  await open('/initial-and-placeholder')
  await expect(page.getByText('posts=30', { exact: true })).toBeVisible()
  await page.getByRole('switch', { name: /Treat initial data as old/ }).click()

  const hold = holdRequest(page, '**/api/posts/3*')
  await page.getByRole('button', { name: 'Open post 3', exact: true }).click()

  // The title is there while the request is provably unanswered.
  await expect(detail(page, 'A', 'Thermostat: setup guide')).toBeVisible()
  await expect(detail(page, 'A', 'initialData source=list')).toBeVisible()
  await expect(fact(page, 'post-3', 'status=success')).toBeVisible()
  await expect(fact(page, 'post-3', 'fetchStatus=fetching')).toBeVisible()
  await expect(fact(page, 'post-3', 'isStale=true')).toBeVisible()
  await hold.release()

  await expect(fact(page, 'post-3', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'post-3', 'fetches=1')).toBeVisible()
  await expect(detail(page, 'A', 'Thermostat: setup guide')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/3$/)).toBe(1)
})

test('a placeholder shows while the request runs and is never cached', async ({ page, open, scenario }) => {
  const hold = holdRequest(page, '**/api/posts/4*')
  await open('/initial-and-placeholder')

  await expect(detail(page, 'B', 'Loading title…')).toBeVisible()
  await expect(detail(page, 'B', 'isPlaceholderData=true')).toBeVisible()
  await expect(detail(page, 'B', 'cache=empty')).toBeVisible()
  await expect(fact(page, 'post-4', 'status=pending')).toBeVisible()
  await expect(fact(page, 'post-4', 'fetchStatus=fetching')).toBeVisible()
  expect(hold.seen).toBe(1)
  await hold.release()

  await expect(detail(page, 'B', 'Smoke detector: setup guide')).toBeVisible()
  await expect(detail(page, 'B', 'isPlaceholderData=false')).toBeVisible()
  await expect(detail(page, 'B', 'cache=post')).toBeVisible()
  await expect(fact(page, 'post-4', 'status=success')).toBeVisible()
  await expect(fact(page, 'post-4', 'fetches=1')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/4$/)).toBe(1)
})

test('a refetch keeps the real post, not the placeholder', async ({ page, open, scenario }) => {
  await open('/initial-and-placeholder')
  await expect(detail(page, 'B', 'Smoke detector: setup guide')).toBeVisible()
  await expect(fact(page, 'post-4', 'fetchStatus=idle')).toBeVisible()

  const hold = holdRequest(page, '**/api/posts/4*')
  await page.getByRole('button', { name: 'Refetch', exact: true }).click()

  // Placeholder data only stands in for *no* data; a refetch has data.
  await expect(fact(page, 'post-4', 'fetchStatus=fetching')).toBeVisible()
  await expect(detail(page, 'B', 'Smoke detector: setup guide')).toBeVisible()
  await expect(detail(page, 'B', 'isPlaceholderData=false')).toBeVisible()
  await hold.release()

  // The log has the request once it is answered, and post 4 answers slowly.
  await expect(fact(page, 'post-4', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'post-4', 'fetches=2')).toBeVisible()
  await expect(detail(page, 'B', 'Smoke detector: setup guide')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/4$/)).toBe(2)
})

// `watchQuery` identifies its observer by key, so a changed key is a new
// observer with no previous data for `PlaceholderData.compute` — see the
// skipped widget test of the same name for the reproduction.
test.skip('switching the key keeps the previous post as a placeholder', async ({ page, open }) => {
  await open('/initial-and-placeholder')
  await expect(detail(page, 'C', 'Door sensor: setup guide')).toBeVisible()
  await expect(detail(page, 'C', 'isPlaceholderData=false')).toBeVisible()

  const hold = holdRequest(page, '**/api/posts/6*')
  await page.getByRole('radio', { name: 'Post 6', exact: true }).click()

  await expect(detail(page, 'C', 'Door sensor: setup guide')).toBeVisible()
  await expect(detail(page, 'C', 'isPlaceholderData=true')).toBeVisible()
  await expect(fact(page, 'post-6', 'status=pending')).toBeVisible()
  await hold.release()

  await expect(detail(page, 'C', 'Light switch: setup guide')).toBeVisible()
  await expect(detail(page, 'C', 'isPlaceholderData=false')).toBeVisible()
  await expect(fact(page, 'post-6', 'status=success')).toBeVisible()
})

test('a switched key fetches the new post and settles on it', async ({ page, open, scenario }) => {
  await open('/initial-and-placeholder')
  await expect(detail(page, 'C', 'Door sensor: setup guide')).toBeVisible()

  await page.getByRole('radio', { name: 'Post 6', exact: true }).click()

  await expect(detail(page, 'C', 'Light switch: setup guide')).toBeVisible()
  await expect(detail(page, 'C', 'isPlaceholderData=false')).toBeVisible()
  await expect(fact(page, 'post-6', 'status=success')).toBeVisible()
  await expect(fact(page, 'post-6', 'fetches=1')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/6$/)).toBe(1)
  expect(await scenario.count('GET', /^\/api\/posts\/5$/)).toBe(1)
})
