import type { Page } from '@playwright/test'

import { expect, fact, holdRequest, test } from './fixtures'

const post3Title = 'Thermostat: setup guide'

// One row of the list is a semantics group `post <id>`: the title is a button
// inside it, and the `cached` mark, when the cache holds the post, a text of
// its own next to the button.
const row = (page: Page, id: number) => page.getByRole('group', { name: `post ${id}`, exact: true })
const cachedMarkOf = (page: Page, id: number) => row(page, id).getByText('cached', { exact: true })
const openPost = (page: Page, title: string) => page.getByRole('button', { name: title, exact: true }).click()
const backToList = (page: Page) => page.getByRole('button', { name: 'Back to list', exact: true }).click()

test('the list arrives after one request and no row is marked', async ({ page, open, scenario }) => {
  await open('/basic')

  await expect(page.getByText('Window contact: setup guide', { exact: true })).toBeVisible()
  await expect(page.getByText(post3Title, { exact: true })).toBeVisible()
  await expect(fact(page, 'posts', 'status=success')).toBeVisible()
  await expect(fact(page, 'posts', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'posts', 'fetches=1')).toBeVisible()
  await expect(page.getByText('cached', { exact: true })).toHaveCount(0)
  expect(await scenario.count('GET', /^\/api\/posts$/)).toBe(1)
  expect(await scenario.count('GET', /^\/api\/posts\/\d+$/)).toBe(0)
})

test('opening a post fetches it once and marks its row on the way back', async ({ page, open, scenario }) => {
  await open('/basic')
  await expect(fact(page, 'posts', 'fetchStatus=idle')).toBeVisible()

  await openPost(page, post3Title)
  await expect(page.getByText('Post #3', { exact: true })).toBeVisible()
  await expect(fact(page, 'post-3', 'status=success')).toBeVisible()
  await expect(fact(page, 'post-3', 'fetches=1')).toBeVisible()
  await expect(fact(page, 'post-3', 'observers=1')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/3$/)).toBe(1)

  await backToList(page)
  await expect(cachedMarkOf(page, 3)).toBeVisible()
  await expect(page.getByText('cached', { exact: true })).toHaveCount(1)
  await expect(cachedMarkOf(page, 2)).toHaveCount(0)
  expect(await scenario.count('GET', /^\/api\/posts\/3$/)).toBe(1)
})

test('reopening a post shows it from the cache while the refetch is in flight', async ({ page, open, scenario }) => {
  await open('/basic')
  await openPost(page, post3Title)
  await expect(fact(page, 'post-3', 'fetchStatus=idle')).toBeVisible()
  await backToList(page)
  await expect(cachedMarkOf(page, 3)).toBeVisible()

  const hold = holdRequest(page, '**/api/posts/3*')
  await openPost(page, post3Title)

  // The backend has provably not answered: the request is held in the
  // browser, and the title on screen is the cached one.
  await expect(page.getByText(post3Title, { exact: true })).toBeVisible()
  await expect(page.getByText('refreshing', { exact: true })).toBeVisible()
  await expect(fact(page, 'post-3', 'fetchStatus=fetching')).toBeVisible()
  // The entry turns `fetching` the moment the observer subscribes, before the
  // browser has even dispatched the request, so the hold's count is polled.
  await expect.poll(() => hold.seen).toBe(1)
  await hold.release()

  await expect(page.getByText('refreshing', { exact: true })).toBeHidden()
  await expect(fact(page, 'post-3', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'post-3', 'fetches=2')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/3$/)).toBe(2)
})

test('a post left alone is collected once gcTime passes', async ({ page, open }) => {
  await open('/basic')
  await openPost(page, post3Title)
  await expect(fact(page, 'post-3', 'fetchStatus=idle')).toBeVisible()
  await backToList(page)
  await expect(cachedMarkOf(page, 3)).toBeVisible()

  // Nobody reads post 3 now; its ten-second gcTime is running. This waits
  // for the cache's event, it does not measure it.
  await expect.poll(() => cachedMarkOf(page, 3).count(), { timeout: 15_000 }).toBe(0)
  await expect(page.getByText(post3Title, { exact: true })).toBeVisible()
  await expect(fact(page, 'posts', 'status=success')).toBeVisible()
})
