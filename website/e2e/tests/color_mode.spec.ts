// A page is drawn in the reader's colour mode from its first paint, code
// blocks included. Docusaurus renders a block's prism theme as inline styles
// chosen by the React colour mode, which is light in the pre-rendered HTML,
// so a dark page used to show its code light until hydration. The frame
// before hydration is the HTML with its inline scripts and no bundles.
import { BASE, expect, test } from './fixtures'

for (const scheme of ['dark', 'light'] as const) {
  test.describe(`before hydration, in ${scheme} mode`, () => {
    test.use({ colorScheme: scheme })

    test('code blocks are already in that mode', async ({ page }) => {
      await page.route('**/assets/js/**', (route) => route.abort())
      await page.goto(`${BASE}docs/quick-start`)
      await expect(page.locator('html')).toHaveAttribute('data-theme', scheme)
      const background = await page
        .locator('pre')
        .first()
        .evaluate((pre) => getComputedStyle(pre).backgroundColor)
      expect(background).toBe(scheme === 'dark' ? 'rgb(13, 16, 22)' : 'rgb(248, 249, 251)')
    })
  })
}
