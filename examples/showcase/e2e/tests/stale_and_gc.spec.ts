import type { Page } from '@playwright/test'
import { expect, fact, factIn, group, holdRequest, test } from './fixtures'

// The reader's own facts live in a semantics group of their own, because the
// strip shows an `isStale=` too.
const reader = (page: Page, text: string) => factIn(page, 'reader', text)

const button = (page: Page, name: string) => page.getByRole('button', { name, exact: true })

// A segment of one knob: both knobs have a `5 s`, so the knob's group first.
const pick = (page: Page, knob: 'stale-time' | 'gc-time', label: string) =>
  group(page, knob).getByRole('radio', { name: label, exact: true }).click()

// Detaches and re-attaches the reader: a fresh observer, so a mount.
async function reattach(page: Page) {
  await button(page, 'Detach reader').click()
  await expect(reader(page, 'reader=detached')).toBeVisible()
  await button(page, 'Attach reader').click()
  await expect(reader(page, 'reader=attached')).toBeVisible()
}

test('zero: stale the moment it arrives, and a re-attach refetches', async ({ page, open, scenario }) => {
  await open('/stale-and-gc')
  await expect(reader(page, 'serial=1')).toBeVisible()
  await expect(reader(page, 'isStale=true')).toBeVisible()
  await expect(fact(page, 'time', 'fetches=1')).toBeVisible()

  await reattach(page)

  await expect(reader(page, 'serial=2')).toBeVisible()
  await expect(fact(page, 'time', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'time', 'observers=1')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/time$/)).toBe(2)
})

test('5 s: fresh, then stale, and a re-attach refetches only once stale', async ({ page, open, scenario }) => {
  await open('/stale-and-gc')
  await expect(reader(page, 'serial=1')).toBeVisible()
  await pick(page, 'stale-time', '5 s')
  await expect(reader(page, 'isStale=false')).toBeVisible()

  // Within the five seconds a mount finds fresh data and leaves it alone.
  await reattach(page)
  await expect(fact(page, 'time', 'fetchStatus=idle')).toBeVisible()
  await expect(reader(page, 'serial=1')).toBeVisible()
  await expect(fact(page, 'time', 'fetches=1')).toBeVisible()

  // Waiting for the flip, not timing it: the observer's stale timer.
  await expect(reader(page, 'isStale=true')).toBeVisible({ timeout: 15_000 })
  await expect(fact(page, 'time', 'fetches=1')).toBeVisible()

  await reattach(page)
  await expect(reader(page, 'serial=2')).toBeVisible()
  await expect(reader(page, 'isStale=false')).toBeVisible()
  await expect(fact(page, 'time', 'fetches=2')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/time$/)).toBe(2)
})

test('static: neither a re-attach nor an invalidation fetches; Refetch does', async ({ page, open, scenario }) => {
  await open('/stale-and-gc')
  await expect(reader(page, 'serial=1')).toBeVisible()
  await pick(page, 'stale-time', 'static')
  await expect(reader(page, 'isStale=false')).toBeVisible()

  await reattach(page)
  await expect(fact(page, 'time', 'fetchStatus=idle')).toBeVisible()
  await expect(reader(page, 'serial=1')).toBeVisible()

  // The invalidation is outranked: the data stays fresh and nothing fetches.
  await button(page, 'Invalidate').click()
  await expect(reader(page, 'isStale=false')).toBeVisible()
  await expect(fact(page, 'time', 'isStale=false')).toBeVisible()

  // The observer's own `refetch()` is a request, not a trigger — and its
  // count, two, is what proves the two steps before it fetched nothing.
  await button(page, 'Refetch').click()
  await expect(reader(page, 'serial=2')).toBeVisible()
  await expect(fact(page, 'time', 'fetches=2')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/time$/)).toBe(2)
})

test('infinite: a re-attach does not fetch; an invalidation does', async ({ page, open, scenario }) => {
  await open('/stale-and-gc')
  await expect(reader(page, 'serial=1')).toBeVisible()
  await pick(page, 'stale-time', 'infinite')
  await expect(reader(page, 'isStale=false')).toBeVisible()

  await reattach(page)
  await expect(fact(page, 'time', 'fetchStatus=idle')).toBeVisible()
  await expect(reader(page, 'serial=1')).toBeVisible()

  await button(page, 'Invalidate').click()
  await expect(reader(page, 'serial=2')).toBeVisible()
  await expect(reader(page, 'isStale=false')).toBeVisible()
  await expect(fact(page, 'time', 'fetches=2')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/time$/)).toBe(2)
})

test('gc 5 s: a detached entry is collected, and the next attach starts from scratch', async ({
  page,
  open,
  scenario,
}) => {
  await open('/stale-and-gc')
  await expect(reader(page, 'serial=1')).toBeVisible()

  await button(page, 'Detach reader').click()
  await expect(fact(page, 'time', 'observers=0')).toBeVisible()
  await expect(fact(page, 'time', 'status=absent')).toBeVisible({ timeout: 15_000 })

  // Held in the browser, so the entry is provably loading from nothing.
  const hold = holdRequest(page, '**/api/time*')
  await button(page, 'Attach reader').click()
  await expect(fact(page, 'time', 'status=pending')).toBeVisible()
  await expect(reader(page, 'reader=attached')).toBeVisible()
  await hold.release()

  await expect(fact(page, 'time', 'status=success')).toBeVisible()
  await expect(reader(page, 'serial=2')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/time$/)).toBe(2)
})

test('gc never: a detached entry outlives the five seconds', async ({ page, open }) => {
  await open('/stale-and-gc')
  await expect(reader(page, 'serial=1')).toBeVisible()
  await pick(page, 'gc-time', 'never')

  await button(page, 'Detach reader').click()
  await expect(fact(page, 'time', 'observers=0')).toBeVisible()

  // Sampled, waited past what `5 s` would have needed, sampled again.
  await page.waitForTimeout(7_000)
  await expect(fact(page, 'time', 'status=success')).toBeVisible()
  await expect(fact(page, 'time', 'observers=0')).toBeVisible()
})

test('dynamic: fresh after an odd serial, stale after an even one', async ({ page, open, scenario }) => {
  await open('/stale-and-gc')
  await expect(reader(page, 'serial=1')).toBeVisible()
  await pick(page, 'stale-time', 'dynamic')
  await expect(reader(page, 'isStale=false')).toBeVisible()

  await button(page, 'Refetch').click()
  await expect(reader(page, 'serial=2')).toBeVisible()
  await expect(reader(page, 'isStale=true')).toBeVisible()

  await button(page, 'Refetch').click()
  await expect(reader(page, 'serial=3')).toBeVisible()
  await expect(reader(page, 'isStale=false')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/time$/)).toBe(3)
})
