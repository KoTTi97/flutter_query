// The `pagination` screen in a real browser: one cache entry per page, the
// previous page kept on screen as a placeholder while the next loads, the
// next page prefetched as soon as the current one has data.
import type { Page } from '@playwright/test'

import { expect, fact, holdRequest, test, type Scenario } from './fixtures'

// The toolbar card, both strips and ten rows are taller than the default
// viewport, and a strip below the fold is never built.
test.use({ viewport: { width: 1280, height: 1100 } })

const nextButton = (page: Page) => page.getByRole('button', { name: 'Next page', exact: true })
const previousButton = (page: Page) => page.getByRole('button', { name: 'Previous page', exact: true })

/// The backend logs `/api/projects` without its query string, so a page's
/// requests are counted by the `page` parameter logged alongside.
async function pageRequests(scenario: Scenario, page: number) {
  const log = await scenario.requests()
  return log.filter((entry) => entry.method === 'GET' && entry.path === '/api/projects' && entry.query.page === String(page))
    .length
}

test('page 0 costs one request and page 1 is prefetched with nobody observing it', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/pagination')

  await expect(page.getByText('page=0', { exact: true })).toBeVisible()
  await expect(page.getByText('Project 0', { exact: true })).toBeVisible()
  await expect(page.getByText('Project 9', { exact: true })).toBeVisible()
  await expect(page.getByText('isPlaceholderData=false', { exact: true })).toBeVisible()
  await expect(previousButton(page)).toHaveAttribute('aria-disabled', 'true')
  await expect(fact(page, 'page-0', 'status=success')).toBeVisible()
  await expect(fact(page, 'page-0', 'observers=1')).toBeVisible()

  // The prefetch: page 1 lands in the cache with nobody reading it.
  await expect(fact(page, 'page-1', 'status=success')).toBeVisible()
  await expect(fact(page, 'page-1', 'observers=0')).toBeVisible()
  await expect(fact(page, 'page-1', 'fetches=1')).toBeVisible()
  expect(await pageRequests(scenario, 0)).toBe(1)
  expect(await pageRequests(scenario, 1)).toBe(1)
  expect(await pageRequests(scenario, 2)).toBe(0)
})

test('Next page onto the prefetched page costs no request and prefetches the page after', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/pagination')
  await expect(fact(page, 'page-1', 'status=success')).toBeVisible()

  await nextButton(page).click()

  await expect(page.getByText('page=1', { exact: true })).toBeVisible()
  await expect(page.getByText('Project 10', { exact: true })).toBeVisible()
  await expect(page.getByText('Project 19', { exact: true })).toBeVisible()
  await expect(page.getByText('Project 0', { exact: true })).toHaveCount(0)
  await expect(page.getByText('isPlaceholderData=false', { exact: true })).toBeVisible()
  await expect(fact(page, 'page-1', 'observers=1')).toBeVisible()
  await expect(fact(page, 'page-2', 'status=success')).toBeVisible()
  await expect(fact(page, 'page-2', 'observers=0')).toBeVisible()
  expect(await pageRequests(scenario, 1)).toBe(1)
  expect(await pageRequests(scenario, 2)).toBe(1)
})

test('a page whose prefetch has not answered shows the previous page as a placeholder, with Next page disabled', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await open('/pagination')
  await expect(fact(page, 'page-1', 'status=success')).toBeVisible()

  // Page 2's prefetch fires on arriving at page 1; held in the browser, it
  // provably has not answered when page 2 is opened.
  const hold = holdRequest(page, '**/api/projects?page=2*')
  await nextButton(page).click()
  await expect(page.getByText('Project 10', { exact: true })).toBeVisible()
  await expect(fact(page, 'page-2', 'fetchStatus=fetching')).toBeVisible()
  expect(hold.seen).toBe(1)

  await nextButton(page).click()

  // The tap joined the held prefetch: page 1's rows stand in for page 2.
  await expect(page.getByText('page=2', { exact: true })).toBeVisible()
  await expect(page.getByText('isPlaceholderData=true', { exact: true })).toBeVisible()
  await expect(page.getByText('Project 10', { exact: true })).toBeVisible()
  await expect(page.getByText('Project 20', { exact: true })).toHaveCount(0)
  await expect(page.getByText('loading', { exact: true })).toBeVisible()
  await expect(nextButton(page)).toHaveAttribute('aria-disabled', 'true')
  await expect(fact(page, 'page-2', 'status=pending')).toBeVisible()
  await expect(fact(page, 'page-2', 'observers=1')).toBeVisible()
  await hold.release()

  await expect(page.getByText('Project 20', { exact: true })).toBeVisible()
  await expect(page.getByText('Project 29', { exact: true })).toBeVisible()
  await expect(page.getByText('Project 10', { exact: true })).toHaveCount(0)
  await expect(page.getByText('isPlaceholderData=false', { exact: true })).toBeVisible()
  await expect(nextButton(page)).not.toHaveAttribute('aria-disabled', 'true')
  await expect(fact(page, 'page-2', 'status=success')).toBeVisible()
  expect(await pageRequests(scenario, 2)).toBe(1)
})

test('Previous page returns to a cached page with no request', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/pagination')
  await expect(fact(page, 'page-1', 'status=success')).toBeVisible()
  await nextButton(page).click()
  await expect(page.getByText('page=1', { exact: true })).toBeVisible()
  await expect(fact(page, 'page-2', 'status=success')).toBeVisible()

  await previousButton(page).click()

  await expect(page.getByText('page=0', { exact: true })).toBeVisible()
  await expect(page.getByText('Project 0', { exact: true })).toBeVisible()
  await expect(page.getByText('Project 10', { exact: true })).toHaveCount(0)
  await expect(page.getByText('isPlaceholderData=false', { exact: true })).toBeVisible()
  await expect(previousButton(page)).toHaveAttribute('aria-disabled', 'true')
  // Page 1 is cached and fresh, so the way forward is open at once.
  await expect(nextButton(page)).not.toHaveAttribute('aria-disabled', 'true')
  await expect(fact(page, 'page-0', 'observers=1')).toBeVisible()
  await expect(fact(page, 'page-1', 'observers=0')).toBeVisible()
  expect(await pageRequests(scenario, 0)).toBe(1)
  expect(await pageRequests(scenario, 1)).toBe(1)

  // And forward again, still on the cache.
  await nextButton(page).click()
  await expect(page.getByText('Project 10', { exact: true })).toBeVisible()
  await expect(page.getByText('isPlaceholderData=false', { exact: true })).toBeVisible()
  expect(await pageRequests(scenario, 1)).toBe(1)
})

test('on the last page Next page is disabled and nothing beyond it is prefetched', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/pagination')

  // 100 projects, ten a page: page 9 is the last.
  for (let current = 0; current < 9; current++) {
    await expect(page.getByText(`page=${current}`, { exact: true })).toBeVisible()
    await expect(fact(page, `page-${current + 1}`, 'status=success')).toBeVisible()
    await nextButton(page).click()
  }

  await expect(page.getByText('page=9', { exact: true })).toBeVisible()
  await expect(page.getByText('Project 90', { exact: true })).toBeVisible()
  await expect(page.getByText('Project 99', { exact: true })).toBeVisible()
  await expect(page.getByText('hasMore=false', { exact: true })).toBeVisible()
  await expect(page.getByText('isPlaceholderData=false', { exact: true })).toBeVisible()
  await expect(nextButton(page)).toHaveAttribute('aria-disabled', 'true')
  await expect(previousButton(page)).not.toHaveAttribute('aria-disabled', 'true')
  await expect(fact(page, 'page-9', 'status=success')).toBeVisible()
  await expect(fact(page, 'page-10', 'status=absent')).toBeVisible()
  await expect(fact(page, 'page-10', 'fetches=0')).toBeVisible()
  expect(await pageRequests(scenario, 10)).toBe(0)
  // Every page fetched exactly once, nine of them by the prefetch.
  expect(await scenario.count('GET', /^\/api\/projects$/)).toBe(10)
})
