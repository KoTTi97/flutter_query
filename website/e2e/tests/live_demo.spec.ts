// `<LiveDemo>` on a real doc page: nothing loads before the click, the click
// boots the showcase's `simple` screen in a frame, and that screen runs —
// against the in-memory backend, in this tab — as it does against the server.
import { BASE, expect, factIn, test } from './fixtures'

const page_ = `${BASE}docs/quick-start`

test('the demo loads on the click, fetches, and refetches', async ({ page }) => {
  await page.goto(page_)
  await expect(page.locator('iframe')).toHaveCount(0)

  const run = page.getByRole('button', { name: 'Run live demo' })
  await run.scrollIntoViewIfNeeded()
  await run.click()

  const frame = page.frameLocator('iframe[title="Live demo: Simple"]')
  await expect(frame.getByText('Local development: setup guide')).toBeVisible()
  await expect(factIn(frame, 'debug post', 'status=success')).toBeVisible()
  await expect(factIn(frame, 'debug post', 'fetches=1')).toBeVisible()
  // The overlay waits for Flutter's first frame, not the frame's `load`.
  await expect(page.getByRole('status').filter({ hasText: 'Starting Flutter' })).toHaveCount(0)
  await expect(frame.getByText('in-memory backend', { exact: true })).toBeVisible()
  // Embedded: one feature, and no way back into the catalogue.
  await expect(frame.getByRole('button', { name: 'Back', exact: true })).toHaveCount(0)

  await frame.getByRole('button', { name: 'Refetch', exact: true }).click()
  await expect(factIn(frame, 'debug post', 'fetches=2')).toBeVisible()
  await expect(frame.getByText('Local development: setup guide')).toBeVisible()
})

test('its links go to the whole app and to the feature source', async ({ page }) => {
  await page.goto(page_)
  await expect(page.getByRole('link', { name: 'Open full screen ↗' })).toHaveAttribute(
    'href',
    `${BASE}demo/showcase/?theme=light#/simple`,
  )
  await expect(page.getByRole('link', { name: 'View source ↗' })).toHaveAttribute(
    'href',
    'https://github.com/KoTTi97/flutter_query/tree/main/examples/showcase/lib/features/simple',
  )
})

test('without the demo build the placeholder says how to make one', async ({ page }) => {
  await page.route('**/demo/showcase/version.json', (route) => route.fulfill({ status: 404, body: 'Not found' }))
  await page.goto(page_)
  await page.getByRole('button', { name: 'Run live demo' }).click()
  await expect(page.getByText('npm run demos', { exact: true })).toBeVisible()
  await expect(page.locator('iframe')).toHaveCount(0)
})

test('full screen is the whole catalogue, the feature on top of it', async ({ page }) => {
  // The link itself carries no `semantics=1`; the test adds it to read the tree.
  await page.goto(`${BASE}demo/showcase/?semantics=1#/simple`)
  await expect(page.getByText('Local development: setup guide')).toBeVisible()
  await page.getByRole('button', { name: 'Back', exact: true }).click()
  await expect(page.getByText('query_kit showcase', { exact: true })).toBeVisible()
})

test('the demo follows the site into dark mode, and back out of it', async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'dark' })
  await page.goto(page_)
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark')
  await expect(page.getByRole('link', { name: 'Open full screen ↗' })).toHaveAttribute(
    'href',
    `${BASE}demo/showcase/?theme=dark#/simple`,
  )

  await page.getByRole('button', { name: 'Run live demo' }).click()
  const iframe = page.locator('iframe[title="Live demo: Simple"]')
  await expect(iframe).toHaveAttribute('src', /[?&]theme=dark#\/simple$/)
  const frame = page.frameLocator('iframe[title="Live demo: Simple"]')
  await expect(frame.getByText('Local development: setup guide')).toBeVisible()

  // The navbar's toggle: the frame restarts in the site's new mode.
  await page.getByRole('button', { name: /Switch between dark and light mode/ }).click()
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light')
  await expect(iframe).toHaveAttribute('src', /[?&]theme=light#\/simple$/)
  await expect(frame.getByText('Local development: setup guide')).toBeVisible()
})
