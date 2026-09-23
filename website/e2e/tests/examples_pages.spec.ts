// The Examples section: one page per showcase feature, driven from the
// catalogue, so a feature without a page fails here the day it is added.
// Each page must carry exactly one live demo, of its own feature, and show the
// screen's source. Nothing is started: the placeholder is static, and its
// "Open full screen" link names the route the frame would load.
import { BASE, expect, showcaseFeatures, test } from './fixtures'

for (const feature of showcaseFeatures) {
  test(`examples/${feature.id} frames its own feature`, async ({ page }) => {
    await page.goto(`${BASE}docs/examples/${feature.id}`)
    await expect(page.getByRole('heading', { level: 1, name: feature.title, exact: true })).toBeVisible()

    const demo = page.locator('figure').filter({ hasText: 'Live demo' })
    await expect(demo).toHaveCount(1)
    await expect(demo.getByRole('button', { name: 'Run live demo' })).toBeVisible()
    await expect(demo.getByText(feature.title, { exact: true })).toBeVisible()
    await expect(demo.getByRole('link', { name: 'Open full screen ↗' })).toHaveAttribute(
      'href',
      `${BASE}demo/showcase/#/${feature.id}`,
    )
    // Nothing loads before the click.
    await expect(page.locator('iframe')).toHaveCount(0)

    // The screen's source, from the compiled file.
    const screenFile = `${feature.id.replaceAll('-', '_')}_screen.dart`
    await expect(page.locator('pre code').first()).toBeVisible()
    await expect(page.getByText(new RegExp(`${screenFile}`)).first()).toBeAttached()
  })
}

test('the examples index links every feature page', async ({ page }) => {
  await page.goto(`${BASE}docs/examples`)
  const article = page.locator('article')
  for (const feature of showcaseFeatures) {
    await expect(
      article.locator(`a[href="${BASE}docs/examples/${feature.id}"]`),
      feature.id,
    ).toHaveCount(1)
  }
  await expect(article.locator(`a[href="${BASE}docs/examples/task-manager"]`)).not.toHaveCount(0)
  await expect(article.locator(`a[href="${BASE}docs/examples/one-file-tour"]`)).not.toHaveCount(0)
})

test('the task manager page frames the whole app', async ({ page }) => {
  await page.goto(`${BASE}docs/examples/task-manager`)
  const demo = page.locator('figure').filter({ hasText: 'Live demo' })
  await expect(demo).toHaveCount(1)
  await expect(demo.getByText('Task manager', { exact: true })).toBeVisible()
  await expect(demo.getByRole('link', { name: 'Open full screen ↗' })).toHaveAttribute(
    'href',
    `${BASE}demo/task_manager/`,
  )
})
