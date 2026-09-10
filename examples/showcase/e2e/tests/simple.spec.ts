import { expect, fact, holdRequest, test } from './fixtures'

test('the post arrives after one request and the entry settles', async ({ page, open, scenario }) => {
  await open('/simple')

  await expect(page.getByText('Local development: setup guide')).toBeVisible()
  await expect(fact(page, 'post', 'status=success')).toBeVisible()
  await expect(fact(page, 'post', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'post', 'fetches=1')).toBeVisible()
  await expect(fact(page, 'post', 'observers=1')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/1$/)).toBe(1)
})

test('a refetch keeps the post on screen while it is refreshing', async ({ page, open, scenario }) => {
  await open('/simple')
  await expect(fact(page, 'post', 'fetchStatus=idle')).toBeVisible()

  const hold = holdRequest(page, '**/api/posts/1*')
  await page.getByRole('button', { name: 'Refetch', exact: true }).click()

  // The backend has provably not answered: the request is held in the browser.
  await expect(page.getByText('refreshing', { exact: true })).toBeVisible()
  await expect(page.getByText('Local development: setup guide')).toBeVisible()
  await expect(fact(page, 'post', 'fetchStatus=fetching')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Refetch', exact: true })).toHaveAttribute('aria-disabled', 'true')
  await hold.release()

  await expect(page.getByText('refreshing', { exact: true })).toBeHidden()
  await expect(fact(page, 'post', 'fetches=2')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/1$/)).toBe(2)
})

test('a refused first fetch ends in the error state after the default retries', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0, failNext: [{ method: 'GET', path: '/api/posts/1', count: 4, status: 503 }] })
  await open('/simple')

  // One attempt plus three retries, one, two and four seconds apart.
  await expect(page.getByText('Scripted failure 503')).toBeVisible({ timeout: 20_000 })
  await expect(fact(page, 'post', 'status=error')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/1$/)).toBe(4)
})

test('a refused refetch keeps the stale post next to the error', async ({ page, open, scenario }) => {
  await open('/simple')
  await expect(fact(page, 'post', 'fetchStatus=idle')).toBeVisible()

  await scenario.config({ latency: 0, failNext: [{ method: 'GET', path: '/api/posts/1', count: 4, status: 500 }] })
  await page.getByRole('button', { name: 'Refetch', exact: true }).click()

  await expect(page.getByText('Refetch failed: Scripted failure 500')).toBeVisible({ timeout: 20_000 })
  await expect(page.getByText('Local development: setup guide')).toBeVisible()
  await expect(fact(page, 'post', 'status=error')).toBeVisible()
  await expect(fact(page, 'post', 'fetchStatus=idle')).toBeVisible()
})
