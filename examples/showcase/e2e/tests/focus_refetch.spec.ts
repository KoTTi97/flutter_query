import type { Page } from '@playwright/test'
import { expect, fact, test } from './fixtures'

// Two entries, two strips and four knobs on one screen.
test.use({ viewport: { width: 1280, height: 1900 } })

// Each entry's own facts live in a semantics group of its own, because the
// other entry and both strips show an `isStale=` too.
const reader = (page: Page, group: string, text: string) =>
  page.getByRole('group', { name: group, exact: true }).getByText(text, { exact: true })

const button = (page: Page, name: string) => page.getByRole('button', { name, exact: true })

// A segment of one knob: three of them have a `never`, so the knob's group
// comes first.
const pick = (page: Page, knob: string, label: string) =>
  page.getByRole('group', { name: knob, exact: true }).getByRole('radio', { name: label, exact: true }).click()

// The app leaving the foreground and coming back. Headless Chromium reports no
// Flutter lifecycle transition, so the screen's switch is the focus source:
// it calls `client.focusManager.setFocused(...)`, which is exactly what the
// `AppLifecycleListener` inside `QueryClientProvider` does in a real app.
async function focusCycle(page: Page) {
  const toggle = page.getByRole('switch', { name: 'App focused', exact: true })
  await toggle.click()
  await expect(reader(page, 'focus-state', 'focused=false')).toBeVisible()
  await toggle.click()
  await expect(reader(page, 'focus-state', 'focused=true')).toBeVisible()
}

// Detaches entry B's reader and attaches a fresh one: a mount.
async function reattachB(page: Page) {
  await button(page, 'Detach entry B').click()
  await expect(reader(page, 'reader-b', 'reader=detached')).toBeVisible()
  await button(page, 'Attach entry B').click()
  await expect(reader(page, 'reader-b', 'reader=attached')).toBeVisible()
}

// The screen as it opens: both entries fetched once, thirty seconds of stale
// time, so the data is fresh and only `always` can move it.
async function openFresh(page: Page, open: (route: string) => Promise<void>) {
  await open('/focus-refetch')
  await expect(fact(page, 'focus-a', 'fetches=1')).toBeVisible()
  await expect(fact(page, 'focus-b', 'fetches=1')).toBeVisible()
  await expect(reader(page, 'reader-a', 'isStale=false')).toBeVisible()
  await expect(reader(page, 'reader-b', 'isStale=false')).toBeVisible()
}

test('always: a focus refetches although the data is fresh', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await openFresh(page, open)
  await pick(page, 'on-focus-a', 'always')

  await focusCycle(page)

  await expect(fact(page, 'focus-a', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'focus-a', 'updates=2')).toBeVisible()
  await expect(reader(page, 'reader-a', 'isStale=false')).toBeVisible()
  // Entry B kept the default `ifStale` and its data is fresh, so the same
  // event left it alone.
  await expect(fact(page, 'focus-b', 'fetches=1')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/time$/)).toBe(3)
})

test('never: no focus refetch, stale data included', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await openFresh(page, open)
  await pick(page, 'on-focus-a', 'never')
  await pick(page, 'stale-time', '0')
  await expect(reader(page, 'reader-a', 'isStale=true')).toBeVisible()

  await focusCycle(page)

  // Entry B held `ifStale` and is stale too, so it did fetch — which is what
  // proves the event reached the cache at all rather than being swallowed.
  await expect(fact(page, 'focus-b', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'focus-a', 'fetches=1')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/time$/)).toBe(3)
})

test('ifStale: nothing while fresh, a refetch once the stale time says so', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await openFresh(page, open)
  // `ifStale` is the default on both entries, so nothing is picked here.
  await pick(page, 'on-focus-b', 'never')

  await focusCycle(page)
  await expect(fact(page, 'focus-a', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'focus-a', 'fetches=1')).toBeVisible()

  // No clock in the assertion: the stale time is turned down instead of
  // waiting for thirty seconds to pass.
  await pick(page, 'stale-time', '0')
  await expect(reader(page, 'reader-a', 'isStale=true')).toBeVisible()
  await expect(fact(page, 'focus-a', 'fetches=1')).toBeVisible()

  await focusCycle(page)
  await expect(fact(page, 'focus-a', 'fetches=2')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/time$/)).toBe(3)
})

test('when: a focus while the data is young does nothing, one past ten seconds refetches', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await openFresh(page, open)
  await pick(page, 'on-focus-a', 'when')
  // Silenced, so every request below belongs to entry A.
  await pick(page, 'on-focus-b', 'never')

  // The rule is "older than ten seconds", so this branch cannot be shown with
  // the stale-time knob — the ten seconds are waited out. Both branches are
  // proven by the final count: two mounts and exactly one refetch.
  await focusCycle(page)
  await expect(fact(page, 'focus-a', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'focus-a', 'fetches=1')).toBeVisible()

  await page.waitForTimeout(11_000)
  await focusCycle(page)
  await expect(fact(page, 'focus-a', 'fetches=2')).toBeVisible()
  // Still fresh by the thirty-second stale time: only the `when` rule decided.
  await expect(reader(page, 'reader-a', 'isStale=false')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/time$/)).toBe(3)
})

test('on mount: never never fetches, always always does, ifStale only when stale', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await openFresh(page, open)

  await pick(page, 'on-mount-b', 'never')
  await reattachB(page)
  await expect(fact(page, 'focus-b', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'focus-b', 'fetches=1')).toBeVisible()

  await pick(page, 'on-mount-b', 'always')
  await reattachB(page)
  await expect(fact(page, 'focus-b', 'fetches=2')).toBeVisible()

  // Fresh data, so `ifStale` leaves it alone…
  await pick(page, 'on-mount-b', 'ifStale')
  await reattachB(page)
  await expect(reader(page, 'reader-b', 'isStale=false')).toBeVisible()
  await expect(fact(page, 'focus-b', 'fetches=2')).toBeVisible()

  // …and fetches once the stale time says the data is old.
  await pick(page, 'stale-time', '0')
  await reattachB(page)
  await expect(fact(page, 'focus-b', 'fetches=3')).toBeVisible()
  await expect(fact(page, 'focus-a', 'fetches=1')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/time$/)).toBe(4)
})

test('one focus event, two answers: A always, B never', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await openFresh(page, open)
  await pick(page, 'on-focus-a', 'always')
  await pick(page, 'on-focus-b', 'never')

  await focusCycle(page)

  await expect(fact(page, 'focus-a', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'focus-b', 'fetches=1')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/time$/)).toBe(3)
})
