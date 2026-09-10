import type { Page } from '@playwright/test'
import { expect, holdRequest, test } from './fixtures'

// Two tables, a growing log and the readers: taller than the default
// viewport, and `FeatureScaffold`'s lazy list never builds what is below the
// fold.
test.use({ viewport: { width: 1280, height: 2600 } })

const postsKey = '["posts"]'
const todosKey = '["todos"]'
const missingKey = '["posts",999]'

// One row of the entries table is a semantics group `entry <key>`: two rows
// carry the same fact names, so nothing is read unscoped.
const entry = (page: Page, key: string) => page.getByRole('group', { name: `entry ${key}`, exact: true })
const entryFact = (page: Page, key: string, text: string) => entry(page, key).getByText(text, { exact: true })

const mutationFact = (page: Page, id: number, text: string) =>
  page.getByRole('group', { name: `mutation #${id}`, exact: true }).getByText(text, { exact: true })

const logGroup = (page: Page) => page.getByRole('group', { name: 'event log', exact: true })
// The same line appears again on every later fetch, so which occurrence is
// meant has to be said: the first one for events a test triggered from an
// empty cache, the last for a round that follows earlier ones.
const logLine = (page: Page, text: string, pick: 'first' | 'last' = 'first') =>
  logGroup(page).getByText(text, { exact: true })[pick]()

const button = (page: Page, name: string) => page.getByRole('button', { name, exact: true })
const readers = (page: Page) => page.getByRole('switch', { name: 'Keep readers', exact: true })

/// Asserts the lines are on screen and stacked in this order, top to bottom —
/// the order the cache emitted them in.
async function expectLogOrder(page: Page, lines: string[], pick: 'first' | 'last' = 'first') {
  const tops: number[] = []
  for (const line of lines) {
    const locator = logLine(page, line, pick)
    await expect(locator).toBeVisible()
    const box = await locator.boundingBox()
    expect(box, line).not.toBeNull()
    tops.push(box!.y)
  }
  expect(tops, lines.join(' → ')).toEqual([...tops].sort((a, b) => a - b))
}

/// Mounts the three readers and waits for the switch to have flipped —
/// clicking it and asserting afterwards, because a check races Flutter's next
/// semantics update.
async function keepReaders(page: Page, on: boolean) {
  await readers(page).click()
  if (on) {
    await expect(readers(page)).toBeChecked()
  } else {
    await expect(readers(page)).not.toBeChecked()
  }
}

test('loading posts with the readers mounted logs the entry, its observer and the fetch pair', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await open('/cache-inspector')
  await expect(page.getByText('entries=0', { exact: true })).toBeVisible()

  await keepReaders(page, true)
  await button(page, 'Load posts').click()

  await expectLogOrder(page, [
    `QueryAdded ${postsKey}`,
    `QueryObserverAdded ${postsKey}`,
    `QueryUpdated(QueryFetchAction) ${postsKey}`,
    `QueryUpdated(QuerySuccessAction) ${postsKey}`,
  ])

  await expect(entryFact(page, postsKey, 'status=success')).toBeVisible()
  await expect(entryFact(page, postsKey, 'observers=1')).toBeVisible()
  await expect(entryFact(page, postsKey, 'fetchStatus=idle')).toBeVisible()
  // The readers ask for a one-minute stale time, so fresh data is not stale.
  await expect(entryFact(page, postsKey, 'isStale=false')).toBeVisible()
  await expect(page.getByText('entries=3', { exact: true })).toBeVisible()
  await expect(page.getByText('reader ["posts"]=30 posts', { exact: true })).toBeVisible()
})

test('invalidating a row makes it stale and refetches it, and so does Refetch', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/cache-inspector')

  // The readers hold the entry, so nothing is collected under the test.
  await keepReaders(page, true)
  await expect(entryFact(page, postsKey, 'updates=1')).toBeVisible()
  await expect(entryFact(page, postsKey, 'isStale=false')).toBeVisible()

  // Held in the browser, so the invalidated state is read before the refetch
  // that follows it can clear the flag again.
  const hold = holdRequest(page, '**/api/posts')
  await button(page, `Invalidate ${postsKey}`).click()
  await expect(entryFact(page, postsKey, 'isStale=true')).toBeVisible()
  await expect(entryFact(page, postsKey, 'fetchStatus=fetching')).toBeVisible()
  await hold.release()

  await expect(entryFact(page, postsKey, 'updates=2')).toBeVisible()
  // The readers' own mount fetch logged a pair before this one, so it is the
  // last of each line that belongs to the invalidation.
  await expectLogOrder(
    page,
    [
      `QueryUpdated(QueryInvalidateAction) ${postsKey}`,
      `QueryUpdated(QueryFetchAction) ${postsKey}`,
      `QueryUpdated(QuerySuccessAction) ${postsKey}`,
    ],
    'last',
  )

  await button(page, `Refetch ${postsKey}`).click()
  await expect(entryFact(page, postsKey, 'updates=3')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts$/)).toBe(3)
})

test('Remove drops the row and logs QueryRemoved', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/cache-inspector')

  await button(page, 'Load todos').click()
  await expect(entryFact(page, todosKey, 'status=success')).toBeVisible()

  await button(page, `Remove ${todosKey}`).click()

  await expect(entry(page, todosKey)).toBeHidden()
  await expect(page.getByText('entries=0', { exact: true })).toBeVisible()
  await expect(logLine(page, `QueryRemoved ${todosKey}`)).toBeVisible()
})

test('dropping the readers takes observers to zero and the entry is collected', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/cache-inspector')

  await keepReaders(page, true)
  await expect(entryFact(page, postsKey, 'observers=1')).toBeVisible()

  await keepReaders(page, false)
  await expect(entryFact(page, postsKey, 'observers=0')).toBeVisible()
  await expect(logLine(page, `QueryObserverRemoved ${postsKey}`)).toBeVisible()

  // gcTime is five seconds on everything this screen makes; waiting for the
  // row to go, not timing it.
  await expect(entry(page, postsKey)).toBeHidden({ timeout: 15_000 })
  await expect(logLine(page, `QueryRemoved ${postsKey}`)).toBeVisible()
  await expect(page.getByText('entries=0', { exact: true })).toBeVisible()
})

test('the missing post lands in the cache as an error', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/cache-inspector')

  await button(page, 'Load a missing post').click()

  await expect(entryFact(page, missingKey, 'status=error')).toBeVisible()
  await expect(entryFact(page, missingKey, 'fetchStatus=idle')).toBeVisible()
  await expect(entryFact(page, missingKey, 'updates=0')).toBeVisible()
  await expect(entryFact(page, missingKey, 'dataUpdatedAt=never')).toBeVisible()
  await expect(logLine(page, `QueryUpdated(QueryErrorAction) ${missingKey}`)).toBeVisible()
  // `retry: RetryPolicy.never`: one attempt, not four.
  expect(await scenario.count('GET', /^\/api\/posts\/999$/)).toBe(1)
})

test('a todo shows up in the mutations table, pending then success', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/cache-inspector')
  await expect(page.getByText('The mutation cache is empty.', { exact: true })).toBeVisible()

  // `page.route` cannot filter by method, so the handler does: the POST waits,
  // everything else (the CORS preflight included) goes straight through.
  let letGo: () => void = () => {}
  const held = new Promise<void>((resolve) => {
    letGo = resolve
  })
  await page.route('**/api/todos*', async (route) => {
    if (route.request().method() === 'POST') {
      await held
    }
    await route.continue()
  })

  await button(page, 'Add a todo').click()

  await expect(page.getByText('mutations=1', { exact: true })).toBeVisible()
  await expect(mutationFact(page, 1, 'status=pending')).toBeVisible()
  await expect(mutationFact(page, 1, 'isPaused=false')).toBeVisible()
  await expect(mutationFact(page, 1, 'failureCount=0')).toBeVisible()

  letGo()

  await expect(mutationFact(page, 1, 'status=success')).toBeVisible()
  await expectLogOrder(page, [
    'MutationAdded ["todos","create"]',
    'MutationObserverAdded ["todos","create"]',
    'MutationUpdated(MutationPendingAction) ["todos","create"]',
    'MutationUpdated(MutationSuccessAction) ["todos","create"]',
  ])
  expect(await scenario.count('POST', /^\/api\/todos$/)).toBe(1)
})
