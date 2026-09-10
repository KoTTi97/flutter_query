import { expect, fact, holdRequest, strip, test } from './fixtures'

const post = (id: number) => new RegExp(`^/api/posts/${id}$`)
const comments = (id: number) => new RegExp(`^/api/posts/${id}/comments$`)
const anyPost = /^\/api\/posts\/\d+$/
const anyComments = /^\/api\/posts\/\d+\/comments$/

test('before a choice nothing is requested', async ({ page, open, scenario }) => {
  await open('/dependent-queries')

  await expect(page.getByText('Choose a post first.', { exact: true })).toBeVisible()
  await expect(strip(page, 'post-1')).toBeHidden()
  await expect(strip(page, 'comments-1')).toBeHidden()
  expect(await scenario.count('GET', anyPost)).toBe(0)
  expect(await scenario.count('GET', anyComments)).toBe(0)
})

test('the comments wait for the post and are fetched once after it', async ({ page, open, scenario }) => {
  await open('/dependent-queries')

  // Exactly the post: a glob without a trailing wildcard does not match
  // `/api/posts/2/comments`, so the comments request, if one went out, would
  // reach the backend and show in its log.
  const hold = holdRequest(page, '**/api/posts/2')
  await page.getByRole('button', { name: 'Choose post 2', exact: true }).click()

  // The post has provably not answered, and the comments have not started.
  await expect(fact(page, 'post-2', 'fetchStatus=fetching')).toBeVisible()
  await expect(fact(page, 'comments-2', 'status=pending')).toBeVisible()
  await expect(fact(page, 'comments-2', 'fetchStatus=idle')).toBeVisible()
  await expect(page.getByText('comments enabled=false', { exact: true })).toBeVisible()
  await expect.poll(() => hold.seen).toBe(1)
  expect(await scenario.count('GET', anyComments)).toBe(0)
  await hold.release()

  await expect(page.getByText('Continuous integration: setup guide', { exact: true })).toBeVisible()
  await expect(page.getByText('comments enabled=true', { exact: true })).toBeVisible()
  await expect(fact(page, 'comments-2', 'status=success')).toBeVisible()
  await expect(fact(page, 'comments-2', 'fetches=1')).toBeVisible()
  await expect(page.getByText('comments count=3', { exact: true })).toBeVisible()
  await expect(page.getByText('Clara', { exact: true })).toBeVisible()
  expect(await scenario.count('GET', post(2))).toBe(1)
  expect(await scenario.count('GET', comments(2))).toBe(1)
})

test('Pause comments keeps the comments idle despite the post; unticking fetches once', async ({
  page,
  open,
  scenario,
}) => {
  await open('/dependent-queries')

  const pause = page.getByRole('checkbox', { name: 'Pause comments' })
  await pause.click()
  await expect(pause).toBeChecked()

  await page.getByRole('button', { name: 'Choose post 3', exact: true }).click()
  await expect(page.getByText('Code review: setup guide', { exact: true })).toBeVisible()
  await expect(fact(page, 'post-3', 'status=success')).toBeVisible()
  await expect(fact(page, 'comments-3', 'status=pending')).toBeVisible()
  await expect(fact(page, 'comments-3', 'fetchStatus=idle')).toBeVisible()
  await expect(page.getByText('comments enabled=false', { exact: true })).toBeVisible()
  expect(await scenario.count('GET', comments(3))).toBe(0)

  await pause.click()
  await expect(pause).not.toBeChecked()
  await expect(page.getByText('comments enabled=true', { exact: true })).toBeVisible()
  await expect(fact(page, 'comments-3', 'status=success')).toBeVisible()
  await expect(fact(page, 'comments-3', 'fetches=1')).toBeVisible()
  await expect(page.getByText('comments count=3', { exact: true })).toBeVisible()
  expect(await scenario.count('GET', post(3))).toBe(1)
  expect(await scenario.count('GET', comments(3))).toBe(1)
})

test('switching posts re-keys both queries, and Clear choice releases them', async ({ page, open, scenario }) => {
  await open('/dependent-queries')

  await page.getByRole('button', { name: 'Choose post 2', exact: true }).click()
  await expect(fact(page, 'comments-2', 'status=success')).toBeVisible()

  await page.getByRole('button', { name: 'Choose post 3', exact: true }).click()
  await expect(page.getByText('Code review: setup guide', { exact: true })).toBeVisible()
  await expect(strip(page, 'post-2')).toBeHidden()
  await expect(strip(page, 'comments-2')).toBeHidden()
  await expect(fact(page, 'post-3', 'observers=1')).toBeVisible()
  await expect(fact(page, 'comments-3', 'status=success')).toBeVisible()
  await expect(fact(page, 'comments-3', 'observers=1')).toBeVisible()
  expect(await scenario.count('GET', post(2))).toBe(1)
  expect(await scenario.count('GET', comments(2))).toBe(1)
  expect(await scenario.count('GET', post(3))).toBe(1)
  expect(await scenario.count('GET', comments(3))).toBe(1)

  // Back to post 2: its entries were kept. With the post's request held,
  // the title on screen can only have come from the cache; the stale-time
  // refetch goes out once per entry on top, and the cumulative `fetches`
  // shows the strip reads the same entry as before.
  const hold = holdRequest(page, '**/api/posts/2')
  await page.getByRole('button', { name: 'Choose post 2', exact: true }).click()
  await expect(page.getByText('Continuous integration: setup guide', { exact: true })).toBeVisible()
  await expect(fact(page, 'post-2', 'status=success')).toBeVisible()
  await expect(fact(page, 'post-2', 'fetchStatus=fetching')).toBeVisible()
  await expect(fact(page, 'post-2', 'observers=1')).toBeVisible()
  await expect(fact(page, 'comments-2', 'observers=1')).toBeVisible()
  await hold.release()
  await expect(fact(page, 'post-2', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'post-2', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'comments-2', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'comments-2', 'fetchStatus=idle')).toBeVisible()

  await page.getByRole('button', { name: 'Clear choice', exact: true }).click()
  await expect(page.getByText('Choose a post first.', { exact: true })).toBeVisible()
  await expect(strip(page, 'post-2')).toBeHidden()
  await expect(strip(page, 'comments-2')).toBeHidden()
  expect(await scenario.count('GET', anyPost)).toBe(3)
  expect(await scenario.count('GET', anyComments)).toBe(3)
})
