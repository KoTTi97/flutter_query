import type { Page } from '@playwright/test'
import { expect, fact, group, snackBar, test } from './fixtures'

// Three strips, two cards and a growing log: taller than the default viewport,
// and a lazily built list only has the rows in view.
test.use({ viewport: { width: 1280, height: 1800 } })

/// The callback log: a semantics group whose lines are exact leaf texts.
const logGroup = (page: Page) => group(page, 'callback log')
const logLine = (page: Page, text: string) => logGroup(page).getByText(text, { exact: true })

/// Asserts the lines are on screen and stacked in this order, top to bottom —
/// the order the callbacks ran in.
async function expectLogOrder(page: Page, lines: string[]) {
  const tops: number[] = []
  for (const line of lines) {
    const locator = logLine(page, line)
    await expect(locator).toBeVisible()
    const box = await locator.boundingBox()
    expect(box, line).not.toBeNull()
    tops.push(box!.y)
  }
  expect(tops, lines.join(' → ')).toEqual([...tops].sort((a, b) => a - b))
}

test('loading the screen logs the posts query, success then settled', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/global-callbacks')

  await expect(page.getByText('posts=30', { exact: true })).toBeVisible()
  await expectLogOrder(page, ['query success posts', 'query settled posts'])
  await expect(page.getByText('log=2', { exact: true })).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts$/)).toBe(1)

  // The strips read the screen's own client: the posts entry has its one
  // observer, and the two on-demand queries sit idle.
  await expect(fact(page, 'posts', 'status=success')).toBeVisible()
  await expect(fact(page, 'posts', 'observers=1')).toBeVisible()
  await expect(fact(page, 'post-999', 'status=pending')).toBeVisible()
  await expect(fact(page, 'post-999', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'meta', 'status=pending')).toBeVisible()
})

test('the missing post logs an error with its meta and toasts a SnackBar', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/global-callbacks')
  await expect(logLine(page, 'query settled posts')).toBeVisible()

  await page.getByRole('button', { name: 'Fetch a missing post', exact: true }).click()

  await expectLogOrder(page, [
    'query success posts',
    'query settled posts',
    'query error post-999 (meta: toast)',
    'query settled post-999',
  ])
  await expect(page.getByText('missing=error: Post not found', { exact: true })).toBeVisible()
  // The SnackBar the cache's `onError` showed because `query.meta` said so.
  // Through `snackBar`: a live region is announced a second time outside the
  // semantics tree, and a bare `getByText` would match both while it is.
  await expect(snackBar(page, 'Post not found')).toBeVisible()
  await expect(fact(page, 'post-999', 'status=error')).toBeVisible()
  await expect(fact(page, 'post-999', 'fetchStatus=idle')).toBeVisible()
  // `retry: RetryPolicy.never`: one request, not four.
  expect(await scenario.count('GET', /^\/api\/posts\/999$/)).toBe(1)
})

test('the meta tag reaches the query function', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/global-callbacks')
  await expect(logLine(page, 'query settled posts')).toBeVisible()

  await page.getByRole('button', { name: 'Fetch with meta tag', exact: true }).click()

  await expect(page.getByText('meta seen=showcase', { exact: true })).toBeVisible()
  await expect(page.getByText('serial=1', { exact: true })).toBeVisible()
  await expectLogOrder(page, ['query success posts', 'query settled posts', 'query success meta', 'query settled meta'])
  await expect(fact(page, 'meta', 'status=success')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/time$/)).toBe(1)
})

test('a mutation runs the cache callbacks before its own, and logs a refusal', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/global-callbacks')
  await expect(logLine(page, 'query settled posts')).toBeVisible()
  await page.getByRole('button', { name: 'Clear log', exact: true }).click()
  await expect(page.getByText('log=0', { exact: true })).toBeVisible()

  await page.getByRole('button', { name: 'Create todo', exact: true }).click()

  // The core's order: the cache's `onSuccess`, then the options', then the
  // cache's `onSettled`, then the options'.
  await expectLogOrder(page, ['mutation mutate', 'mutation success', 'option onSuccess', 'mutation settled', 'option onSettled'])
  await expect(page.getByText('log=5', { exact: true })).toBeVisible()
  await expect(page.getByText(/^todo=#\d+ From the callbacks screen$/)).toBeVisible()
  expect(await scenario.count('POST', /^\/api\/todos$/)).toBe(1)
  const todos = (await (await scenario.api('get', '/todos')).json()) as { text: string }[]
  expect(todos.map((todo) => todo.text)).toContain('From the callbacks screen')

  await page.getByRole('button', { name: 'Clear log', exact: true }).click()
  await expect(page.getByText('log=0', { exact: true })).toBeVisible()
  await page.getByRole('button', { name: 'Create failing todo', exact: true }).click()

  await expectLogOrder(page, ['mutation mutate', 'mutation error (Requested: 500)', 'option onError', 'mutation settled', 'option onSettled'])
  await expect(page.getByText('todo=error: Requested: 500', { exact: true })).toBeVisible()
  expect(await scenario.count('POST', /^\/api\/todos$/)).toBe(2)
  const after = (await (await scenario.api('get', '/todos')).json()) as { text: string }[]
  expect(after.map((todo) => todo.text)).not.toContain('Refused by the backend')
})
