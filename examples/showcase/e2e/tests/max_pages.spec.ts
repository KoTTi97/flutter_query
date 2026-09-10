import type { Page } from '@playwright/test'

import { expect, fact, holdRequest, test, type Scenario } from './fixtures'

// The card, its rows and the strip fit a tall window; a lazily built screen
// only has what is in view.
test.use({ viewport: { width: 1280, height: 1000 } })

const button = (page: Page, name: string) => page.getByRole('button', { name, exact: true })
const text = (page: Page, value: string) => page.getByText(value, { exact: true })

/// The cursors the backend answered, in order — one entry per page request.
async function cursors(scenario: Scenario) {
  const log = await scenario.requests()
  return log.filter((entry) => entry.method === 'GET' && entry.path === '/api/projects').map((entry) => entry.query.cursor)
}

/// Presses a paging button and waits for the window it should produce.
async function page_(page: Page, name: 'Load previous' | 'Load next', pageParams: string) {
  await button(page, name).click()
  await expect(text(page, `pageParams=${pageParams}`)).toBeVisible()
}

test('starts on the page at cursor 30 with both directions open', async ({ page, open, scenario }) => {
  const hold = holdRequest(page, '**/api/projects*')
  await open('/max-pages')

  // Held in the browser: the first page has provably not arrived.
  await expect(text(page, 'loading')).toBeVisible()
  await expect(text(page, 'pages=0')).toBeVisible()
  await expect(text(page, 'hasNextPage=false')).toBeVisible()
  await expect(button(page, 'Load next')).toHaveAttribute('aria-disabled', 'true')
  await expect(fact(page, 'projects', 'status=pending')).toBeVisible()
  await expect(fact(page, 'projects', 'fetchStatus=fetching')).toBeVisible()
  await hold.release()

  await expect(text(page, 'pages=1')).toBeVisible()
  await expect(text(page, 'pageParams=30')).toBeVisible()
  await expect(text(page, 'hasPreviousPage=true')).toBeVisible()
  await expect(text(page, 'hasNextPage=true')).toBeVisible()
  await expect(text(page, 'isFetchingPreviousPage=false')).toBeVisible()
  await expect(text(page, 'isFetchingNextPage=false')).toBeVisible()
  await expect(text(page, 'Project 30')).toBeVisible()
  await expect(text(page, 'loading')).toBeHidden()
  await expect(fact(page, 'projects', 'status=success')).toBeVisible()
  await expect(fact(page, 'projects', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'projects', 'fetches=1')).toBeVisible()
  await expect(fact(page, 'projects', 'observers=1')).toBeVisible()
  expect(await cursors(scenario)).toEqual(['30'])
})

test('a fourth page slides the window: the first one is dropped', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/max-pages')
  await expect(text(page, 'pageParams=30')).toBeVisible()

  await page_(page, 'Load next', '30,40')
  await page_(page, 'Load next', '30,40,50')
  await expect(text(page, 'pages=3')).toBeVisible()
  await expect(text(page, 'Project 30')).toBeVisible()

  // Held back this time, so the direction shows while the page is fetched:
  // only the button in that direction is disabled.
  const hold = holdRequest(page, '**/api/projects*')
  await button(page, 'Load next').click()
  await expect(text(page, 'loading next')).toBeVisible()
  await expect(text(page, 'isFetchingNextPage=true')).toBeVisible()
  await expect(text(page, 'isFetchingPreviousPage=false')).toBeVisible()
  await expect(button(page, 'Load next')).toHaveAttribute('aria-disabled', 'true')
  await expect(button(page, 'Refetch')).toHaveAttribute('aria-disabled', 'true')
  await expect(button(page, 'Load previous')).not.toHaveAttribute('aria-disabled', 'true')
  await expect(fact(page, 'projects', 'fetchStatus=fetching')).toBeVisible()
  await hold.release()

  // Three pages still, one at each end different: 30 fell off the front.
  await expect(text(page, 'pageParams=40,50,60')).toBeVisible()
  await expect(text(page, 'pages=3')).toBeVisible()
  await expect(text(page, 'loading next')).toBeHidden()
  await expect(text(page, 'Project 40')).toBeVisible()
  await expect(text(page, 'Project 30')).toBeHidden()
  await expect(fact(page, 'projects', 'fetches=4')).toBeVisible()
  expect(await cursors(scenario)).toEqual(['30', '40', '50', '60'])

  // The far end of the window, scrolled into view inside the rows' own
  // scroller: the wheel lands on the row under the pointer.
  const box = (await text(page, 'Project 40').boundingBox())!
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2)
  await page.mouse.wheel(0, 2000)
  await expect(text(page, 'Project 69')).toBeVisible()
})

test('load previous slides the window back and drops the far end', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/max-pages')
  await expect(text(page, 'pageParams=30')).toBeVisible()
  await page_(page, 'Load next', '30,40')
  await page_(page, 'Load next', '30,40,50')
  await page_(page, 'Load next', '40,50,60')

  const hold = holdRequest(page, '**/api/projects*')
  await button(page, 'Load previous').click()
  await expect(text(page, 'loading previous')).toBeVisible()
  await expect(text(page, 'isFetchingPreviousPage=true')).toBeVisible()
  await expect(text(page, 'isFetchingNextPage=false')).toBeVisible()
  await expect(button(page, 'Load previous')).toHaveAttribute('aria-disabled', 'true')
  await expect(button(page, 'Load next')).not.toHaveAttribute('aria-disabled', 'true')
  await hold.release()

  await expect(text(page, 'pageParams=30,40,50')).toBeVisible()
  await expect(text(page, 'pages=3')).toBeVisible()
  await expect(text(page, 'Project 30')).toBeVisible()
  await expect(fact(page, 'projects', 'fetchStatus=idle')).toBeVisible()
  // One new request, for the page that came back; 60 was simply dropped.
  expect(await cursors(scenario)).toEqual(['30', '40', '50', '60', '30'])
})

test('a refetch re-requests exactly the pages in the window', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/max-pages')
  await expect(text(page, 'pageParams=30')).toBeVisible()
  await page_(page, 'Load next', '30,40')
  await page_(page, 'Load next', '30,40,50')
  await expect(fact(page, 'projects', 'fetches=3')).toBeVisible()

  const stamp = page.getByText(/^fetched \d\d:\d\d:\d\d$/).first()
  const before = await stamp.textContent()
  expect(before).toMatch(/^fetched /)
  // The stamp is the backend's clock to the second; a refetch inside the
  // same second would carry the same one. Not an assertion on a clock — only
  // the distance the next stamp needs.
  await page.waitForTimeout(1100)
  await scenario.clearRequests()

  const hold = holdRequest(page, '**/api/projects*')
  await button(page, 'Refetch').click()
  await expect(text(page, 'refreshing')).toBeVisible()
  await expect(text(page, 'isFetchingNextPage=false')).toBeVisible()
  await expect(text(page, 'isFetchingPreviousPage=false')).toBeVisible()
  await expect(button(page, 'Refetch')).toHaveAttribute('aria-disabled', 'true')
  // The rows stay on screen while the pages are refetched.
  await expect(text(page, 'Project 30')).toBeVisible()
  await expect(fact(page, 'projects', 'fetchStatus=fetching')).toBeVisible()
  await hold.release()

  // One fetch, three requests: the strip counts fetches, not pages.
  await expect(fact(page, 'projects', 'fetches=4')).toBeVisible()
  await expect(fact(page, 'projects', 'fetchStatus=idle')).toBeVisible()
  await expect(text(page, 'refreshing')).toBeHidden()
  await expect(text(page, 'pageParams=30,40,50')).toBeVisible()
  expect(await cursors(scenario)).toEqual(['30', '40', '50'])
  await expect(stamp).not.toHaveText(before!)
  await expect(page.getByText(/^fetched \d\d:\d\d:\d\d$/).last()).not.toHaveText(before!)
})

test('cursor 0 ends the backward direction and cursor 90 the forward', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/max-pages')
  await expect(text(page, 'pageParams=30')).toBeVisible()

  await page_(page, 'Load previous', '20,30')
  await page_(page, 'Load previous', '10,20,30')
  await page_(page, 'Load previous', '0,10,20')
  await expect(text(page, 'hasPreviousPage=false')).toBeVisible()
  await expect(text(page, 'hasNextPage=true')).toBeVisible()
  await expect(button(page, 'Load previous')).toHaveAttribute('aria-disabled', 'true')
  await expect(button(page, 'Load next')).not.toHaveAttribute('aria-disabled', 'true')
  await expect(text(page, 'Project 0')).toBeVisible()

  let cursor = 30
  for (; cursor <= 90; cursor += 10) {
    await page_(page, 'Load next', `${cursor - 20},${cursor - 10},${cursor}`)
  }
  await expect(text(page, 'pageParams=70,80,90')).toBeVisible()
  await expect(text(page, 'hasNextPage=false')).toBeVisible()
  await expect(text(page, 'hasPreviousPage=true')).toBeVisible()
  await expect(button(page, 'Load next')).toHaveAttribute('aria-disabled', 'true')
  await expect(button(page, 'Load previous')).not.toHaveAttribute('aria-disabled', 'true')
  await expect(text(page, 'Project 70')).toBeVisible()
  expect(await cursors(scenario)).toEqual(['30', '20', '10', '0', '30', '40', '50', '60', '70', '80', '90'])
})
