import type { Page } from '@playwright/test'

import { expect, fact, holdRequest, test, type LogEntry } from './fixtures'

// The screen is read whole — the strip, the facts, the 360-pixel list and
// the button below it — and a 720-tall window cuts the button off. Only what
// is on screen is in Flutter's semantics tree, so the window is made taller.
test.use({ viewport: { width: 1280, height: 1100 } })

// The list's own facts live in a semantics group of their own, because the
// strip's facts sit in the same screen.
const listFact = (page: Page, text: string) =>
  page.getByRole('group', { name: 'projects facts', exact: true }).getByText(text, { exact: true })

const button = (page: Page, name: string) => page.getByRole('button', { name, exact: true })

/// How many project requests asked for `cursor` — the path is the same for
/// every page, only the query string tells them apart.
const requestsAt = (log: LogEntry[], cursor: number) =>
  log.filter((entry) => entry.method === 'GET' && entry.path === '/api/projects' && entry.query.cursor === `${cursor}`)
    .length

test('the first page arrives after one request at cursor 0', async ({ page, open, scenario }) => {
  await open('/load-more')

  await expect(page.getByText('Project 0', { exact: true })).toBeVisible()
  await expect(listFact(page, 'pages=1')).toBeVisible()
  await expect(listFact(page, 'rows=10')).toBeVisible()
  await expect(listFact(page, 'hasNextPage=true')).toBeVisible()
  await expect(listFact(page, 'isFetchingNextPage=false')).toBeVisible()
  await expect(fact(page, 'projects', 'status=success')).toBeVisible()
  await expect(fact(page, 'projects', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'projects', 'fetches=1')).toBeVisible()
  await expect(fact(page, 'projects', 'observers=1')).toBeVisible()
  const log = await scenario.requests()
  expect(requestsAt(log, 0)).toBe(1)
  expect(await scenario.count('GET', /^\/api\/projects$/)).toBe(1)
})

test('Load more appends the next page and is disabled while it loads', async ({ page, open, scenario }) => {
  await open('/load-more')
  await expect(listFact(page, 'pages=1')).toBeVisible()

  const hold = holdRequest(page, '**/api/projects?cursor=10&*')
  await button(page, 'Load more').click()

  // The backend has provably not answered: the request is held in the
  // browser, the first page is still on screen, and the fetch in flight is
  // a forward one.
  await expect(listFact(page, 'isFetchingNextPage=true')).toBeVisible()
  await expect(listFact(page, 'pages=1')).toBeVisible()
  await expect(page.getByText('loading', { exact: true })).toBeVisible()
  await expect(button(page, 'Load more')).toHaveAttribute('aria-disabled', 'true')
  await expect(fact(page, 'projects', 'fetchStatus=fetching')).toBeVisible()
  await expect.poll(() => hold.seen).toBe(1)
  await hold.release()

  await expect(listFact(page, 'pages=2')).toBeVisible()
  await expect(listFact(page, 'rows=20')).toBeVisible()
  await expect(listFact(page, 'isFetchingNextPage=false')).toBeVisible()
  await expect(listFact(page, 'hasNextPage=true')).toBeVisible()
  await expect(button(page, 'Load more')).not.toHaveAttribute('aria-disabled', 'true')
  await expect(fact(page, 'projects', 'fetches=2')).toBeVisible()
  const log = await scenario.requests()
  expect(requestsAt(log, 10)).toBe(1)
  expect(await scenario.count('GET', /^\/api\/projects$/)).toBe(2)
})

test('scrolling to the bottom loads the next page without the button', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/load-more')
  await expect(listFact(page, 'pages=1')).toBeVisible()

  // Ten rows of 48 in a 360-tall viewport: the last one is built but out of
  // sight. Scrolling it into view is a DOM scroll on the list's semantics
  // node, which Flutter web turns into a scroll of the list itself — and
  // that is what reaches the end and makes the listener ask for the next
  // page. (A wheel would need the mouse over the list, and the semantics
  // overlay intercepts the hover that would put it there.)
  await page.getByText('Project 9', { exact: true }).scrollIntoViewIfNeeded()

  await expect(listFact(page, 'pages=2')).toBeVisible()
  await expect(listFact(page, 'rows=20')).toBeVisible()
  const log = await scenario.requests()
  expect(requestsAt(log, 10)).toBe(1)
  expect(await scenario.count('GET', /^\/api\/projects$/)).toBe(2)

  // The page that landed made the list longer, so the next one waits for
  // the next scroll rather than following on its own.
  await page.waitForTimeout(500)
  expect(await scenario.count('GET', /^\/api\/projects$/)).toBe(2)
})

test('after the tenth page there is no next one and nothing asks for more', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/load-more')
  await expect(listFact(page, 'pages=1')).toBeVisible()

  for (let pages = 2; pages <= 10; pages++) {
    await button(page, 'Load more').click()
    await expect(listFact(page, `pages=${pages}`)).toBeVisible()
  }

  await expect(listFact(page, 'rows=100')).toBeVisible()
  await expect(listFact(page, 'hasNextPage=false')).toBeVisible()
  await expect(page.getByText('Nothing more to load', { exact: true })).toBeVisible()
  await expect(button(page, 'Load more')).toHaveAttribute('aria-disabled', 'true')
  const log = await scenario.requests()
  expect(requestsAt(log, 90)).toBe(1)
  expect(requestsAt(log, 100)).toBe(0)
  expect(await scenario.count('GET', /^\/api\/projects$/)).toBe(10)
})

test('going to About and back shows the pages from the cache, no request', async ({ page, open, scenario }) => {
  await open('/load-more')
  await expect(listFact(page, 'pages=1')).toBeVisible()
  await button(page, 'Load more').click()
  await expect(listFact(page, 'pages=2')).toBeVisible()
  await expect(fact(page, 'projects', 'observers=1')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/projects$/)).toBe(2)

  await button(page, 'Go to about').click()

  // The list is gone and with it the entry's only observer; the pages are
  // still in the cache.
  await expect(page.getByText('About', { exact: true })).toBeVisible()
  await expect(page.getByText('Project 0', { exact: true })).toHaveCount(0)
  await expect(fact(page, 'projects', 'observers=0')).toBeVisible()
  await expect(fact(page, 'projects', 'status=success')).toBeVisible()
  await expect(fact(page, 'projects', 'isStale=false')).toBeVisible()

  // Any request the return might make is held in the browser: rows that
  // appear while the hold has caught nothing came from the cache.
  const hold = holdRequest(page, '**/api/projects*')
  await button(page, 'Back to list').click()

  await expect(page.getByText('Project 0', { exact: true })).toBeVisible()
  await expect(listFact(page, 'pages=2')).toBeVisible()
  await expect(listFact(page, 'rows=20')).toBeVisible()
  await expect(fact(page, 'projects', 'observers=1')).toBeVisible()
  await expect(fact(page, 'projects', 'fetchStatus=idle')).toBeVisible()
  expect(hold.seen).toBe(0)
  await hold.release()

  await expect(fact(page, 'projects', 'fetches=2')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/projects$/)).toBe(2)
})
