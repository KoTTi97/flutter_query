import type { Page } from '@playwright/test'

import { expect, fact, holdRequest, test } from './fixtures'

// Seven cards and two strips: taller than the default viewport, and a lazily
// built list only has what is in view.
test.use({ viewport: { width: 1280, height: 3400 } })

const POSTS = '**/api/posts*'

/// The five reader names, in the order the screen lays them out.
const readers = ['context', 'builder', 'mixin', 'controller', 'observer'] as const

/// One reader's fact: `posts=30` and `status=success` are said by five cards
/// and by the strip, so nothing here can be found by text alone.
const reader = (page: Page, name: string, text: string) =>
  page.getByRole('group', { name: `reader ${name}`, exact: true }).getByText(text, { exact: true })

/// One fact of the listener card. `child-builds=1` is in the same group,
/// said by the child the listener hands back.
const listener = (page: Page, text: string) =>
  page.getByRole('group', { name: 'listener', exact: true }).getByText(text, { exact: true })

const mutation = (page: Page, name: string, text: string) =>
  page.getByRole('group', { name: `mutation ${name}`, exact: true }).getByText(text, { exact: true })

const button = (page: Page, name: string) => page.getByRole('button', { name, exact: true })

async function expectEveryReader(page: Page, text: string) {
  for (const name of readers) {
    await expect(reader(page, name, text), `reader ${name} should say ${text}`).toBeVisible()
  }
}

/// How many times the card called `name` has built, read off the card.
async function buildsOf(page: Page, name: string) {
  const text = await page
    .getByRole('group', { name: `reader ${name}`, exact: true })
    .getByText(/^builds=\d+$/)
    .textContent()
  return Number(/builds=(\d+)/.exec(text ?? '')![1])
}

async function buildsOfAll(page: Page) {
  const counts: Record<string, number> = {}
  for (const name of readers) counts[name] = await buildsOf(page, name)
  return counts
}

test('five readers share one request and one entry', async ({ page, open, scenario }) => {
  await open('/four-call-styles')

  await expectEveryReader(page, 'posts=30')
  await expectEveryReader(page, 'status=success')
  await expectEveryReader(page, 'fetching=false')
  // One build for the pending frame, one when the data landed. Card 4's
  // ListenableBuilder has no value to compare, so it can sit one ahead;
  // nothing else separates the five.
  for (const name of readers) {
    expect(await buildsOf(page, name), `reader ${name}`).toBeGreaterThanOrEqual(2)
  }

  // Five observers on one entry, and the core made one request for them.
  await expect(fact(page, 'posts', 'observers=5')).toBeVisible()
  await expect(fact(page, 'posts', 'fetches=1')).toBeVisible()
  await expect(fact(page, 'posts', 'fetchStatus=idle')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts$/)).toBe(1)
})

test('a refetch through the controller updates all five', async ({ page, open, scenario }) => {
  await open('/four-call-styles')
  await expectEveryReader(page, 'posts=30')
  const before = await buildsOfAll(page)

  const hold = holdRequest(page, POSTS)
  await button(page, 'Refetch').click()

  // The backend has provably not answered: the request is held in the
  // browser, and all five cards already show the fetch next to the old data.
  await expectEveryReader(page, 'fetching=true')
  await expectEveryReader(page, 'posts=30')
  for (const name of readers) {
    expect(await buildsOf(page, name), `reader ${name}`).toBe(before[name] + 1)
  }
  await expect(fact(page, 'posts', 'fetchStatus=fetching')).toBeVisible()
  await hold.release()

  await expectEveryReader(page, 'fetching=false')
  await expectEveryReader(page, 'posts=30')
  await expect(fact(page, 'posts', 'fetches=2')).toBeVisible()
  // Two builds for the refetch, the same two in every style: the fetch
  // starting, then the data landing.
  for (const name of readers) {
    expect(await buildsOf(page, name), `reader ${name}`).toBe(before[name] + 2)
  }
  expect(await scenario.count('GET', /^\/api\/posts$/)).toBe(2)
})

test('Invalidate refetches the one entry the five share', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/four-call-styles')
  await expect(fact(page, 'posts', 'fetches=1')).toBeVisible()

  await button(page, 'Invalidate').click()

  // Five observers, still one request: invalidateQueries refetches the query,
  // not each reader.
  await expect(fact(page, 'posts', 'fetches=2')).toBeVisible()
  await expectEveryReader(page, 'posts=30')
  await expectEveryReader(page, 'status=success')
  expect(await scenario.count('GET', /^\/api\/posts$/)).toBe(2)
})

test('either mutation button increments the counter and the invalidation refetches it', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await open('/four-call-styles')
  await expect(page.getByText('counter=0', { exact: true })).toBeVisible()
  await expect(mutation(page, 'builder', 'status=idle')).toBeVisible()
  await expect(mutation(page, 'context', 'status=idle')).toBeVisible()

  const hold = holdRequest(page, '**/api/counter/increment*')
  await button(page, 'Increment (builder)').click()

  await expect(mutation(page, 'builder', 'status=pending')).toBeVisible()
  await expect(page.getByText('counter=0', { exact: true })).toBeVisible()
  await expect(mutation(page, 'context', 'status=idle')).toBeVisible()
  await hold.release()

  await expect(mutation(page, 'builder', 'status=success')).toBeVisible()
  await expect(mutation(page, 'builder', 'data=1')).toBeVisible()
  // `onSuccess` returned the invalidation's future, so by the time the
  // mutation says success the counter has already refetched.
  await expect(page.getByText('counter=1', { exact: true })).toBeVisible()
  await expect(fact(page, 'counter', 'fetches=2')).toBeVisible()

  // The other style runs the same options through a controller of its own.
  await button(page, 'Increment (context)').click()
  await expect(mutation(page, 'context', 'status=success')).toBeVisible()
  await expect(mutation(page, 'context', 'data=2')).toBeVisible()
  await expect(mutation(page, 'builder', 'status=success')).toBeVisible()
  await expect(page.getByText('counter=2', { exact: true })).toBeVisible()
  expect(await scenario.count('POST', /^\/api\/counter\/increment$/)).toBe(2)
  expect(await scenario.count('GET', /^\/api\/counter$/)).toBe(3)
})

test('the listener reacts to a change of the data and never rebuilds its child', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await open('/four-call-styles')
  await expectEveryReader(page, 'posts=30')

  // Nothing is delivered on mount, so the one call is the first fetch
  // landing — the transition after it. The listener borrowed card 4's
  // controller, so there is still no sixth observer.
  await expect(listener(page, 'listener-calls=1')).toBeVisible()
  await expect(listener(page, 'last=pending/fetching:none->success/idle:30')).toBeVisible()
  await expect(listener(page, 'child-builds=1')).toBeVisible()
  await expect(fact(page, 'posts', 'observers=5')).toBeVisible()

  // A refetch returns the same 30 posts: dataUpdatedAt and fetchStatus moved,
  // the data did not, and listenWhen refused both transitions.
  await button(page, 'Refetch').click()
  await expect(fact(page, 'posts', 'fetches=2')).toBeVisible()
  await expectEveryReader(page, 'fetching=false')
  await expect(listener(page, 'listener-calls=1')).toBeVisible()
  await expect(listener(page, 'last=pending/fetching:none->success/idle:30')).toBeVisible()

  // A cache write is a change of the data like any other, and one call.
  await button(page, 'Drop a post').click()
  await expectEveryReader(page, 'posts=29')
  await expect(listener(page, 'listener-calls=2')).toBeVisible()
  await expect(listener(page, 'last=success/idle:30->success/idle:29')).toBeVisible()
  await expect(listener(page, '#2 success/idle:30->success/idle:29')).toBeVisible()

  // Two calls, four refusals, and every one of them rebuilt the card around
  // the listener — the child it was handed built once, on mount.
  await expect(listener(page, 'child-builds=1')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts$/)).toBe(2)
})
