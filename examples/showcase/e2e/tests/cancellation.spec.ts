import { expect, fact, factIn, strip, test, type Page } from './fixtures'

// Two cards and up to three strips: taller than the default viewport, and a
// lazily built list only has what is in view.
test.use({ viewport: { width: 1280, height: 1800 } })

const POSTS = /^\/api\/posts$/
const SEARCH = /^\/api\/search$/

/// A card's facts live in a group of their own, because `status=` and
/// `fetchStatus=` are also what the debug strips say about the same entries.
const slow = (page: Page, text: string) => factIn(page, 'slow facts', text)

const searched = (page: Page, text: string) => factIn(page, 'search facts', text)

const button = (page: Page, name: string) => page.getByRole('button', { name, exact: true })

/// Every request the browser gave up on, by URL fragment. An aborted XHR is
/// reported as `requestfailed` with `net::ERR_ABORTED`, which is the browser's
/// own word for "the signal reached the transport" — no clock involved.
function abortedRequests(page: Page, fragment: string) {
  const aborted: string[] = []
  page.on('requestfailed', (request) => {
    if (request.url().includes(fragment)) aborted.push(request.failure()?.errorText ?? 'failed')
  })
  return aborted
}

async function typeNeedle(page: Page, needle: string) {
  const field = page.getByRole('textbox')
  await field.click()
  await field.fill(needle)
}

test('cancelling the slow fetch reverts it to idle and aborts the request', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  const aborted = abortedRequests(page, '/api/posts')
  await open('/cancellation')

  // The screen's own fetch is out, and three seconds from an answer.
  await expect(slow(page, 'fetchStatus=fetching')).toBeVisible()
  await expect(slow(page, 'posts=none')).toBeVisible()
  await expect(slow(page, 'cancels=0')).toBeVisible()

  await button(page, 'Cancel').click()

  await expect(slow(page, 'fetchStatus=idle')).toBeVisible()
  await expect(slow(page, 'cancels=1')).toBeVisible()
  // `revert` is the default: a cancelled first fetch is pending again, not an
  // error, and holds nothing.
  await expect(slow(page, 'status=pending')).toBeVisible()
  await expect(slow(page, 'posts=none')).toBeVisible()
  await expect(fact(page, 'slow', 'fetchStatus=idle')).toBeVisible()

  // The browser gave the request up, and the backend — still sleeping out the
  // three seconds — never answered it.
  await expect.poll(() => aborted.length).toBe(1)
  expect(await scenario.count('GET', POSTS)).toBe(0)
})

test('a silent cancel leaves the reader with no error', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  const aborted = abortedRequests(page, '/api/posts')
  await open('/cancellation')
  await expect(slow(page, 'fetchStatus=fetching')).toBeVisible()

  await button(page, 'Cancel silently').click()

  await expect(slow(page, 'fetchStatus=idle')).toBeVisible()
  await expect(slow(page, 'cancels=1')).toBeVisible()
  // The whole point of `silent`: nothing about the status changed.
  await expect(slow(page, 'status=pending')).toBeVisible()
  await expect(fact(page, 'slow', 'status=pending')).toBeVisible()
  await expect(fact(page, 'slow', 'failures=0')).toBeVisible()
  await expect.poll(() => aborted.length).toBe(1)
  expect(await scenario.count('GET', POSTS)).toBe(0)
})

test('a cancelled entry starts over and loads all thirty posts', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/cancellation')
  await expect(slow(page, 'fetchStatus=fetching')).toBeVisible()
  await button(page, 'Cancel').click()
  await expect(slow(page, 'status=pending')).toBeVisible()

  await button(page, 'Start slow fetch').click()
  await expect(slow(page, 'fetchStatus=fetching')).toBeVisible()

  await expect(slow(page, 'posts=30')).toBeVisible()
  await expect(slow(page, 'status=success')).toBeVisible()
  expect(await scenario.count('GET', POSTS)).toBe(1)
})

test('two keystrokes inside the debounce window send one request', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/cancellation')
  await expect(searched(page, 'needle=none')).toBeVisible()

  const field = page.getByRole('textbox')
  await field.click()
  await field.fill('met')
  await field.fill('metr')

  // Only the last needle ever became a key, so nothing was there to cancel.
  await expect(searched(page, 'needle=metr')).toBeVisible()
  await expect(searched(page, 'results=1')).toBeVisible()
  await expect(searched(page, 'searchCancels=0')).toBeVisible()
  await expect(page.getByText('Metrics dashboard: setup guide', { exact: true })).toBeVisible()
  await expect(strip(page, 'previous')).toBeHidden()
  expect(await scenario.count('GET', SEARCH)).toBe(1)
})

test('a needle typed while the last is in flight cancels it', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  const aborted = abortedRequests(page, '/api/search')
  await open('/cancellation')
  await expect(searched(page, 'needle=none')).toBeVisible()

  await typeNeedle(page, 'a')
  // The needle is committed after the debounce, well before the one-second
  // request can answer.
  await expect(searched(page, 'needle=a')).toBeVisible()
  await expect(searched(page, 'searching=true')).toBeVisible()

  await typeNeedle(page, 'az')

  await expect(searched(page, 'needle=az')).toBeVisible()
  await expect(searched(page, 'searchCancels=1')).toBeVisible()
  await expect.poll(() => aborted.length).toBe(1)
  // The abandoned needle keeps its entry, reverted to before the fetch.
  await expect(fact(page, 'previous', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'previous', 'status=pending')).toBeVisible()

  // `az` matches nothing and `a` matches most posts: neither arrives.
  await expect(searched(page, 'results=0')).toBeVisible()
  await expect(page.getByText('Local development: setup guide', { exact: true })).toBeHidden()
  expect(await scenario.count('GET', SEARCH)).toBe(1)
})

test('a query function that ignores the signal is cancelled, its request is not', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/cancellation')
  await expect(slow(page, 'fetchStatus=fetching')).toBeVisible()

  // Clear the fetch the screen started on mount; the switch governs the next.
  await button(page, 'Cancel').click()
  await expect(slow(page, 'fetchStatus=idle')).toBeVisible()
  await scenario.clearRequests()

  const ignore = page.getByRole('switch', { name: 'Ignore the signal', exact: true })
  await ignore.click()
  await expect(ignore).toBeChecked()

  await button(page, 'Start slow fetch').click()
  await expect(slow(page, 'fetchStatus=fetching')).toBeVisible()
  await button(page, 'Cancel').click()
  await expect(slow(page, 'fetchStatus=idle')).toBeVisible()
  // Nothing registered an `onCancel` this time, so the count is unchanged.
  await expect(slow(page, 'cancels=1')).toBeVisible()

  // The token never reached dio, so the backend answers the request in full —
  // and the query, cancelled and reverted, throws that answer away.
  await expect.poll(() => scenario.count('GET', POSTS), { timeout: 15_000 }).toBe(1)
  await expect(slow(page, 'status=pending')).toBeVisible()
  await expect(slow(page, 'posts=none')).toBeVisible()
})
