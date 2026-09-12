import type { Page } from '@playwright/test'
import { expect, fact, factIn, group, test } from './fixtures'

// Four cards and a strip: taller than the default window, and a `ListView`
// only builds what is near the viewport.
test.use({ viewport: { width: 1280, height: 1800 } })

// The reader's own facts live in a semantics group of their own, because the
// strip carries a `status=` too.
const reader = (page: Page, text: string) => factIn(page, 'reader', text)

const button = (page: Page, name: string) => page.getByRole('button', { name, exact: true })

// A segment of one knob: `retry` and `fail-next` both have a `2`, so the
// knob's group comes first.
const pick = (page: Page, knob: 'retry' | 'delay' | 'fail-next' | 'status', label: string) =>
  group(page, knob).getByRole('radio', { name: label, exact: true }).click()

// Hands the script to the backend and waits for the screen to say it landed,
// so nothing races the fetch that is about to spend it.
async function arm(page: Page, armed: string) {
  await button(page, 'Arm').click()
  await expect(page.getByText(`armed=${armed}`, { exact: true })).toBeVisible()
}

const timeRequests = /^\/api\/time$/

test('never: one refused request is the error', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0, failNext: [{ method: 'GET', path: '/api/time', count: 1, status: 503 }] })
  await open('/retry')

  await expect(reader(page, 'status=error')).toBeVisible()
  await expect(reader(page, 'failureCount=1')).toBeVisible()
  await expect(reader(page, 'failureReason=Scripted failure 503')).toBeVisible()
  await expect(reader(page, 'isLoadingError=true')).toBeVisible()
  await expect(reader(page, 'isRefetchError=false')).toBeVisible()
  await expect(reader(page, 'hasStaleData=false')).toBeVisible()
  await expect(reader(page, 'serial=none')).toBeVisible()
  await expect(page.getByText('Scripted failure 503', { exact: true })).toBeVisible()
  await expect(fact(page, 'time', 'failures=1')).toBeVisible()
  expect(await scenario.count('GET', timeRequests)).toBe(1)
})

test('2 times: the count climbs and the third attempt succeeds', async ({ page, open, scenario }) => {
  // A latency wide enough that the intermediate failure count is on screen
  // for the best part of a second — no clock is asserted on, only the order.
  await scenario.config({ latency: 400 })
  await open('/retry')
  await expect(reader(page, 'serial=1')).toBeVisible()

  await pick(page, 'retry', '2 times')
  await pick(page, 'delay', '300 ms')
  await pick(page, 'fail-next', '2')
  await arm(page, '2@503')

  await scenario.clearRequests()
  await button(page, 'Refetch').click()

  // The first attempt has been refused and the retry is still waiting.
  await expect(reader(page, 'failureCount=1')).toBeVisible()
  await expect(reader(page, 'failureReason=Scripted failure 503')).toBeVisible()

  // The reader had data before the refetch, so `status` never left `success`
  // and waiting on it gates nothing. The new serial is what says the third
  // attempt landed — the same gate the `always` case uses.
  await expect(reader(page, 'serial=2')).toBeVisible({ timeout: 20_000 })
  await expect(reader(page, 'status=success')).toBeVisible()
  await expect(reader(page, 'failureCount=0')).toBeVisible()
  await expect(reader(page, 'failureReason=none')).toBeVisible()
  expect(await scenario.count('GET', timeRequests)).toBe(3)
})

test('always: past the third failure and past a 404, until it succeeds', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/retry')
  await expect(reader(page, 'serial=1')).toBeVisible()

  await pick(page, 'retry', 'always')
  await pick(page, 'delay', '300 ms')
  await pick(page, 'fail-next', '10')
  await pick(page, 'status', '404')
  await arm(page, '10@404')

  await scenario.clearRequests()
  await button(page, 'Refetch').click()

  // Ten refusals, one retry each — three seconds of them, so the success is
  // given time: `2 times` would have stopped at three attempts, `when 5xx`
  // would not have retried a 404 at all. `status` stays `success` through a
  // refetch's retries (the old serial is still on screen), so the new serial
  // is what says the eleventh attempt landed.
  await expect(reader(page, 'serial=2')).toBeVisible({ timeout: 20_000 })
  await expect(reader(page, 'failureCount=0')).toBeVisible()
  await expect(reader(page, 'status=success')).toBeVisible()
  expect(await scenario.count('GET', timeRequests)).toBe(11)
})

test('dynamic: the delay is computed from the error', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/retry')
  await expect(reader(page, 'serial=1')).toBeVisible()

  await pick(page, 'retry', 'always')
  await pick(page, 'delay', 'dynamic')
  await pick(page, 'fail-next', '2')
  await pick(page, 'status', '404')
  await arm(page, '2@404')

  await scenario.clearRequests()
  await button(page, 'Refetch').click()
  await expect(reader(page, 'failureCount=1')).toBeVisible()

  // A 404 waits four seconds: sampled two seconds in, the retry has not been
  // spent. Not a stopwatch — the count is read once, and read again later.
  await page.waitForTimeout(2_000)
  expect(await scenario.count('GET', timeRequests)).toBe(1)
  await expect(reader(page, 'failureCount=1')).toBeVisible()

  // The new serial says the third attempt landed; `status` was `success`
  // all along, over the old one.
  await expect(reader(page, 'serial=2')).toBeVisible({ timeout: 20_000 })
  await expect(reader(page, 'failureCount=0')).toBeVisible()
  expect(await scenario.count('GET', timeRequests)).toBe(3)

  // The same knob over a 503 waits 200 ms between its attempts.
  await pick(page, 'status', '503')
  await arm(page, '2@503')
  await scenario.clearRequests()
  await button(page, 'Refetch').click()

  await expect(reader(page, 'serial=3')).toBeVisible()
  await expect(reader(page, 'failureCount=0')).toBeVisible()
  expect(await scenario.count('GET', timeRequests)).toBe(3)
})

test('a refused refetch keeps the serial next to the error', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/retry')
  await expect(reader(page, 'serial=1')).toBeVisible()

  await pick(page, 'fail-next', '2')
  await arm(page, '2@503')

  await scenario.clearRequests()
  await button(page, 'Refetch').click()

  await expect(reader(page, 'status=error')).toBeVisible()
  await expect(reader(page, 'hasStaleData=true')).toBeVisible()
  await expect(reader(page, 'isRefetchError=true')).toBeVisible()
  await expect(reader(page, 'isLoadingError=false')).toBeVisible()
  await expect(reader(page, 'serial=1')).toBeVisible()
  await expect(page.getByText('Server time #1', { exact: true })).toBeVisible()
  await expect(page.getByText('Refetch failed: Scripted failure 503', { exact: true })).toBeVisible()
  // `never` is still the policy, so one refused attempt is the whole fetch.
  expect(await scenario.count('GET', timeRequests)).toBe(1)
})

test('when 5xx: a 404 is not retried, a 503 is', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/retry')
  await expect(reader(page, 'serial=1')).toBeVisible()

  await pick(page, 'retry', 'when 5xx')
  await pick(page, 'delay', '300 ms')
  await pick(page, 'fail-next', '10')
  await pick(page, 'status', '404')
  await arm(page, '10@404')

  await scenario.clearRequests()
  await button(page, 'Refetch').click()
  await expect(reader(page, 'status=error')).toBeVisible()
  await expect(reader(page, 'failureCount=1')).toBeVisible()

  // Proven by sampling the count again after a wait, not by a stopwatch: a
  // policy that had scheduled a retry would have spent it by now.
  await page.waitForTimeout(2_000)
  expect(await scenario.count('GET', timeRequests)).toBe(1)

  // The same policy over a 503 retries until the count it is asked about
  // reaches three, so four attempts in all.
  await pick(page, 'status', '503')
  await arm(page, '10@503')
  await scenario.clearRequests()
  await button(page, 'Refetch').click()

  await expect(reader(page, 'failureCount=4')).toBeVisible({ timeout: 20_000 })
  await expect(reader(page, 'status=error')).toBeVisible()
  expect(await scenario.count('GET', timeRequests)).toBe(4)
})

test('retryOnMount decides whether a fresh reader retries an error', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0, failNext: [{ method: 'GET', path: '/api/time', count: 1, status: 503 }] })
  await open('/retry')
  await expect(reader(page, 'status=error')).toBeVisible()
  expect(await scenario.count('GET', timeRequests)).toBe(1)

  const retryOnMount = page.getByRole('switch', { name: /Retry on mount/ })

  // Off: the entry has no data and ended in an error, so a mount leaves it.
  await retryOnMount.click()
  await expect(retryOnMount).not.toBeChecked()
  await button(page, 'Detach reader').click()
  await expect(reader(page, 'reader=detached')).toBeVisible()
  await button(page, 'Attach reader').click()
  await expect(reader(page, 'status=error')).toBeVisible()

  await page.waitForTimeout(2_000)
  expect(await scenario.count('GET', timeRequests)).toBe(1)

  // On: the same mount fetches, and the script is spent, so it succeeds.
  await retryOnMount.click()
  await expect(retryOnMount).toBeChecked()
  await button(page, 'Detach reader').click()
  await expect(reader(page, 'reader=detached')).toBeVisible()
  await button(page, 'Attach reader').click()

  await expect(reader(page, 'status=success')).toBeVisible()
  await expect(reader(page, 'serial=1')).toBeVisible()
  expect(await scenario.count('GET', timeRequests)).toBe(2)
})
