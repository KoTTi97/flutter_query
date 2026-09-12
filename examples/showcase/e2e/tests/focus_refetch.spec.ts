import type { Page } from '@playwright/test'
import { expect, fact, factIn, group, test } from './fixtures'

// Three entries, two strips and five knobs on one screen; entry C sits at the
// bottom, and the scaffold's list only builds — and the semantics tree only
// carries — what is in view.
test.use({ viewport: { width: 1280, height: 3000 } })

// Each entry's own facts live in a semantics group of its own, because the
// other entry and both strips show an `isStale=` too.
const reader = (page: Page, group: string, text: string) => factIn(page, group, text)

const button = (page: Page, name: string) => page.getByRole('button', { name, exact: true })

// A segment of one knob: three of them have a `never`, so the knob's group
// comes first. Clicked, then asserted selected: the click is a DOM event and
// Flutter applies it a frame later, and a test that acts on the knob before
// that frame — a window blur, say — acts on the old setting.
async function pick(page: Page, knob: string, label: string) {
  const segment = group(page, knob).getByRole('radio', { name: label, exact: true })
  await segment.click()
  await expect(segment).toBeChecked()
}

// The app leaving the foreground and coming back. Headless Chromium raises no
// Flutter lifecycle transition of its own, so the screen's switch is the focus
// source: it calls `client.focusManager.setFocused(...)`, which is exactly
// what the `AppLifecycleListener` inside `QueryClientProvider` does in a real
// app. (A `blur` dispatched on the window *is* a transition — `inactive` —
// and the `isAppShown` test below uses one.)
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

// Entry C's own focus source. It runs on a client of its own, so the app
// switch above does not reach it: this one calls `setFocused` on entry C's
// focus manager, which is where the threshold is measured.
async function focusCycleC(page: Page) {
  const toggle = page.getByRole('switch', { name: 'Entry C focused', exact: true })
  await toggle.click()
  await expect(reader(page, 'reader-c', 'focused=false')).toBeVisible()
  await toggle.click()
  await expect(reader(page, 'reader-c', 'focused=true')).toBeVisible()
}

test('min background long: a short absence raises the event and refetches nothing', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await open('/focus-refetch')
  await pick(page, 'min-background', 'long')
  // A new threshold is a new manager, a new client and a new cache.
  await expect(reader(page, 'reader-c', 'fetches=1')).toBeVisible()

  await focusCycleC(page)

  // The event reached the manager — focus came back — carrying "no new
  // refetches", because the absence was far under the hour.
  await expect(reader(page, 'reader-c', 'shouldRefetchOnFocus=false')).toBeVisible()
  await expect(reader(page, 'reader-c', 'fetches=1')).toBeVisible()
  // Two on the server, one per client: the default client fetched once before
  // the knob replaced it, and the new one fetched once on mount. `fetches=1`
  // above is the new client's own counter, and it did not move on the return.
  expect(await scenario.count('GET', /^\/api\/counter$/)).toBe(2)
})

test('min background none: the same absence and return does refetch', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/focus-refetch')
  await expect(reader(page, 'reader-c', 'fetches=1')).toBeVisible()

  await focusCycleC(page)

  await expect(reader(page, 'reader-c', 'shouldRefetchOnFocus=true')).toBeVisible()
  await expect(reader(page, 'reader-c', 'fetches=2')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/counter$/)).toBe(2)
})

test('the threshold knob swaps the client entry C runs on', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/focus-refetch')
  await focusCycleC(page)
  await expect(reader(page, 'reader-c', 'fetches=2')).toBeVisible()

  await pick(page, 'min-background', 'long')
  await expect(reader(page, 'reader-c', 'fetches=1')).toBeVisible()
  await focusCycleC(page)
  await expect(reader(page, 'reader-c', 'shouldRefetchOnFocus=false')).toBeVisible()
  await expect(reader(page, 'reader-c', 'fetches=1')).toBeVisible()

  await pick(page, 'min-background', 'none')
  await expect(reader(page, 'reader-c', 'fetches=1')).toBeVisible()
  await focusCycleC(page)
  await expect(reader(page, 'reader-c', 'shouldRefetchOnFocus=true')).toBeVisible()
  await expect(reader(page, 'reader-c', 'fetches=2')).toBeVisible()

  // Entries A and B never left the app's own client, and the app switch was
  // never touched: nothing on `/api/time` moved.
  expect(await scenario.count('GET', /^\/api\/time$/)).toBe(2)
})

// A real lifecycle transition in the browser: Flutter web maps the window's
// `blur` to `AppLifecycleState.inactive` and its `focus` back to `resumed`,
// and every provider on the page — the app's and entry C's — maps that state
// onto its client through its own `isAppShown`.
const blurWindow = (page: Page) => page.evaluate(() => window.dispatchEvent(new Event('blur')))
const focusWindow = (page: Page) => page.evaluate(() => window.dispatchEvent(new Event('focus')))

test('isAppShown: under hidden a window blur is an absence, under shown it is not', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await open('/focus-refetch')
  await expect(reader(page, 'reader-c', 'fetches=1')).toBeVisible()

  // `shown`: inactive is an interruption. The app's own provider runs the
  // built-in mapping, which reads a desktop browser's blur as unfocused —
  // that is what proves the transition reached Flutter at all — while entry
  // C, told outright, keeps its focus and fetches nothing on the return.
  await pick(page, 'inactive-is', 'shown')
  await blurWindow(page)
  await expect(reader(page, 'focus-state', 'focused=false')).toBeVisible()
  await expect(reader(page, 'reader-c', 'focused=true')).toBeVisible()
  await focusWindow(page)
  await expect(reader(page, 'focus-state', 'focused=true')).toBeVisible()
  await page.waitForTimeout(500)
  await expect(reader(page, 'reader-c', 'fetches=1')).toBeVisible()

  // `hidden`: the same blur is an absence, the return raises the event, and
  // the threshold is `none`, so it refetches. Same client throughout — the
  // mapping reached it as it stands.
  await pick(page, 'inactive-is', 'hidden')
  await expect(reader(page, 'reader-c', 'fetches=1')).toBeVisible()
  await blurWindow(page)
  await expect(reader(page, 'reader-c', 'focused=false')).toBeVisible()
  await focusWindow(page)
  await expect(reader(page, 'reader-c', 'focused=true')).toBeVisible()
  await expect(reader(page, 'reader-c', 'shouldRefetchOnFocus=true')).toBeVisible()
  await expect(reader(page, 'reader-c', 'fetches=2')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/counter$/)).toBe(2)
})

test('OnlineStatus.fixed(false): entry C mounts paused and fetches once its switch puts it online', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await open('/focus-refetch')
  await expect(reader(page, 'reader-c', 'online=true')).toBeVisible()
  await expect(reader(page, 'reader-c', 'fetches=1')).toBeVisible()

  // A new key, a new client, mounted believing it is offline: the fetch is
  // dispatched and pauses at once, and nothing leaves the browser.
  await pick(page, 'initial-online', 'offline')
  await expect(reader(page, 'reader-c', 'online=false')).toBeVisible()
  await expect(reader(page, 'reader-c', 'fetchStatus=paused')).toBeVisible()
  await expect(reader(page, 'reader-c', 'fetches=1')).toBeVisible()
  await page.waitForTimeout(500)
  expect(await scenario.count('GET', /^\/api\/counter$/)).toBe(1)

  await page.getByRole('switch', { name: 'Entry C online', exact: true }).click()
  await expect(reader(page, 'reader-c', 'online=true')).toBeVisible()
  await expect(reader(page, 'reader-c', 'fetchStatus=idle')).toBeVisible()
  await expect(page.getByText('Server counter 0', { exact: true })).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/counter$/)).toBe(2)
})

test('maybeOf names the nearest provider: the app above, entry C below', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/focus-refetch')

  await expect(reader(page, 'focus-state', 'nearest=app')).toBeVisible()
  await expect(reader(page, 'reader-c', 'nearest=entry C')).toBeVisible()
  // And still after the knob has swapped the nested client for another.
  await pick(page, 'min-background', 'long')
  await expect(reader(page, 'reader-c', 'fetches=1')).toBeVisible()
  await expect(reader(page, 'reader-c', 'nearest=entry C')).toBeVisible()
  await expect(reader(page, 'focus-state', 'nearest=app')).toBeVisible()
})
