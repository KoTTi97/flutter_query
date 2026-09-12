import type { Page } from '@playwright/test'
import { expect, fact, group, test } from './fixtures'

// The connection card, the strip, the add card, the list and the three
// explanations are taller than the default viewport, and the scaffold's list
// builds only what is in view.
test.use({ viewport: { width: 1280, height: 1800 } })

const TODOS = /^\/api\/todos$/

/// The screen's own facts, the group next to the cache strip: `online=false`,
/// `query fetchStatus=paused`, `mutation isPaused=true`.
const facts = (page: Page) => group(page, 'facts offline')

const say = (page: Page, text: string) => facts(page).getByText(text, { exact: true })

const button = (page: Page, name: string) => page.getByRole('button', { name, exact: true })

/// Flips the one switch the whole screen hangs on. The library installs no
/// connectivity listener, so this is the only thing that moves the online
/// state.
async function setOnline(page: Page, online: boolean) {
  await page.getByRole('switch', { name: 'Online', exact: true }).click()
  await expect(say(page, `online=${online}`)).toBeVisible()
}

// A segment of one knob: the network mode and the reconnect knob both have
// an `always`, so the knob's group comes first.
const pick = (page: Page, knob: 'network-mode' | 'on-reconnect', label: string) =>
  group(page, knob).getByRole('radio', { name: label, exact: true }).click()

const pickMode = (page: Page, mode: string) => pick(page, 'network-mode', mode)

async function addTodo(page: Page, text: string) {
  const field = page.getByRole('textbox')
  await field.click()
  await field.fill(text)
  await button(page, 'Add todo').click()
}

test('offline, a refetch under online pauses and sends nothing; going online resumes it once', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await open('/offline')
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
  expect(await scenario.count('GET', TODOS)).toBe(1)

  await setOnline(page, false)
  await button(page, 'Refetch').click()

  await expect(say(page, 'query fetchStatus=paused')).toBeVisible()
  await expect(fact(page, 'todos', 'fetchStatus=paused')).toBeVisible()
  // Nothing was refused: nothing was sent.
  expect(await scenario.count('GET', TODOS)).toBe(1)

  await setOnline(page, true)
  await expect(say(page, 'query fetchStatus=idle')).toBeVisible()
  // The paused fetch continued; the reconnect refetch found it in flight and
  // returned it instead of starting a second one.
  expect(await scenario.count('GET', TODOS)).toBe(2)
})

test('offline, a write under online is paused, and the reconnect sends it without being asked', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await open('/offline')
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()

  await setOnline(page, false)
  await addTodo(page, 'Seal the loft hatch')

  await expect(say(page, 'mutation status=pending')).toBeVisible()
  await expect(say(page, 'mutation isPaused=true')).toBeVisible()
  expect(await scenario.count('POST', TODOS)).toBe(0)

  // Nobody presses `Resume paused mutations`: the client is mounted, and
  // `QueryClient.mount` resumes them on the online event itself.
  await setOnline(page, true)
  await expect(say(page, 'mutation status=success')).toBeVisible()
  await expect(page.getByText('#4 Seal the loft hatch', { exact: true })).toBeVisible()
  expect(await scenario.count('POST', TODOS)).toBe(1)
})

test('Resume paused mutations while still offline leaves an online mutation where it was', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await open('/offline')
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()

  await setOnline(page, false)
  await addTodo(page, 'Order a spare battery')
  await expect(say(page, 'mutations paused=1')).toBeVisible()

  await button(page, 'Resume paused mutations').click()
  // A negative needs a moment to be worth anything; the whole round trip to
  // this backend is milliseconds with latency 0.
  await page.waitForTimeout(1_000)

  // `MutationCache.resumePaused` gates per mutation: one under the online
  // mode is skipped while offline rather than parked on the same wait.
  expect(await scenario.count('POST', TODOS)).toBe(0)
  await expect(say(page, 'mutation isPaused=true')).toBeVisible()
  await expect(say(page, 'mutations paused=1')).toBeVisible()

  await setOnline(page, true)
  await expect(say(page, 'mutation status=success')).toBeVisible()
  expect(await scenario.count('POST', TODOS)).toBe(1)
})

test('always: the request goes out offline and fails like any other', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/offline')
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()

  await pickMode(page, 'always')
  await setOnline(page, false)

  // A real failure, not a scripted one: the browser refuses to make the
  // request at all, which is what being offline actually looks like.
  await page.route('**/api/todos', (route) => route.abort('connectionrefused'))
  await button(page, 'Refetch').click()

  // `always` never pauses — it fails and retries, twice, 400 ms apart.
  await expect(fact(page, 'todos', 'status=error')).toBeVisible()
  await expect(page.getByText('The backend is unreachable', { exact: true })).toBeVisible()
  await expect(say(page, 'query fetchStatus=paused')).toBeHidden()
})

test('offlineFirst: the first attempt goes out offline and the retry after it pauses', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0, failNext: [{ method: 'GET', path: '/api/todos', count: 4, status: 503 }] })
  await open('/offline')
  // The mount fetch spends the first scripted failure and retries into the
  // next; the screen ends up in error, with the entry settled.
  await expect(fact(page, 'todos', 'status=error')).toBeVisible()
  const attempts = await scenario.count('GET', TODOS)

  await pickMode(page, 'offlineFirst')
  await setOnline(page, false)
  await button(page, 'Refetch').click()

  // `canFetch` lets any mode but `online` start, so the attempt is really
  // made — and refused, since the scripted failures are not spent yet.
  await expect(async () => {
    expect(await scenario.count('GET', TODOS)).toBe(attempts + 1)
  }).toPass()
  // Then the retry waits out its delay and asks whether it may continue,
  // which offline it may not.
  await expect(say(page, 'query fetchStatus=paused')).toBeVisible()
  expect(await scenario.count('GET', TODOS)).toBe(attempts + 1)
})

test('refetchOnReconnect: never leaves the todos alone on reconnect, always refetches them', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await open('/offline')
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
  expect(await scenario.count('GET', TODOS)).toBe(1)

  // Nothing paused: the reconnect alone decides, and `never` says no.
  await pick(page, 'on-reconnect', 'never')
  await setOnline(page, false)
  await setOnline(page, true)
  // A negative needs a moment to be worth anything.
  await page.waitForTimeout(1_000)
  expect(await scenario.count('GET', TODOS)).toBe(1)
  await expect(fact(page, 'todos', 'fetches=1')).toBeVisible()

  await pick(page, 'on-reconnect', 'always')
  await setOnline(page, false)
  await setOnline(page, true)
  await expect(fact(page, 'todos', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
  expect(await scenario.count('GET', TODOS)).toBe(2)
})
