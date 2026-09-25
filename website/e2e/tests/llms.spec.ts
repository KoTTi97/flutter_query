// The site for AI agents (`plugins/llms-txt.ts`): llms.txt lists every doc
// page, each one's Markdown is served next to it with no MDX left in it, a
// `<DartSource>` arrives as the code it shows, and a page's "Copy page" puts
// that Markdown on the clipboard.
import { BASE, expect, test } from './fixtures'

/** llms.txt's links name the deployed site; the same paths are served here. */
const local = (url: string) => new URL(url).pathname

async function index(request: import('@playwright/test').APIRequestContext) {
  const response = await request.get(`${BASE}llms.txt`)
  expect(response.ok()).toBe(true)
  const text = await response.text()
  const links = [...text.matchAll(/^- \[[^\]]+\]\((https:[^)]+\.md)\)/gm)].map((match) => match[1])
  return { text, links }
}

test('llms.txt indexes every doc page, and every page is clean Markdown', async ({ request }) => {
  const { text, links } = await index(request)
  expect(text.startsWith('# query_kit\n\n> ')).toBe(true)
  expect(text).toContain('## Optional')
  expect(links.length).toBeGreaterThan(100)
  expect(new Set(links).size).toBe(links.length)

  for (const link of links) {
    const response = await request.get(local(link))
    expect(response.ok(), link).toBe(true)
    expect(response.headers()['content-type'], link).toContain('text/markdown')
    const page = await response.text()
    expect(page.startsWith('# '), link).toBe(true)
    // What only the site can run is gone: components, imports, admonition
    // fences, heading ids.
    expect(page, link).not.toMatch(/<(DartSource|LiveDemo|ExampleGrid|Tabs|TabItem)\b/)
    expect(page, link).not.toMatch(/^import \w+ from '/m)
    expect(page, link).not.toMatch(/^:::/m)
    expect(page, link).not.toMatch(/\\?\{#[\w-]+\\?\}$/m)
  }
})

test('llms-full.txt holds every page', async ({ request }) => {
  const response = await request.get(`${BASE}llms-full.txt`)
  expect(response.ok()).toBe(true)
  const full = await response.text()
  expect(full).toContain('\n# Optimistic updates\n')
  expect(full).toContain('\n# Credits, and what this is not\n')
})

test('a DartSource excerpt arrives as its code, linked to its lines', async ({ request }) => {
  const page = await (await request.get(`${BASE}docs/examples/offline.md`)).text()
  expect(page).toContain('QueryObserverOptions<List<Todo>> todosQuery(')
  expect(page).toMatch(
    /\[`examples\/showcase\/lib\/features\/offline\/offline_screen\.dart`, lines \d+–\d+\]\(https:\/\/github\.com\/dualmeta-gmbh\/query_kit\/blob\/\w+\/examples\/showcase\/lib\/features\/offline\/offline_screen\.dart#L\d+-L\d+\):\n\n```dart\n/,
  )
  // The live demo is a link to the running app.
  expect(page).toContain(`](https://dualmeta-gmbh.github.io${BASE}demo/showcase/#/offline)`)
})

test.describe('the Copy page button', () => {
  test.use({ permissions: ['clipboard-read', 'clipboard-write'] })

  test('copies the page as Markdown', async ({ page, request }) => {
    await page.goto(`${BASE}docs/guides/optimistic-updates`)
    await expect(page.locator('link[rel="alternate"][type="text/markdown"]')).toHaveAttribute(
      'href',
      `${BASE}docs/guides/optimistic-updates.md`,
    )

    await page.getByRole('button', { name: 'Copy page', exact: true }).click()
    await expect(page.getByRole('button', { name: 'Copied', exact: true })).toBeVisible()
    const copied = await page.evaluate(() => navigator.clipboard.readText())
    const markdown = await (await request.get(`${BASE}docs/guides/optimistic-updates.md`)).text()
    expect(copied).toBe(markdown)
  })

  test('its menu offers the Markdown, two chats and the indexes', async ({ page }) => {
    await page.goto(`${BASE}docs/quick-start`)
    await page.getByRole('button', { name: 'More ways to use this page' }).click()
    const menu = page.getByRole('menu')
    await expect(menu.getByRole('menuitem', { name: /View as Markdown/ })).toHaveAttribute(
      'href',
      `${BASE}docs/quick-start.md`,
    )
    await expect(menu.getByRole('menuitem', { name: /Open in Claude/ })).toHaveAttribute(
      'href',
      /^https:\/\/claude\.ai\/new\?q=.*quick-start\.md/,
    )
    await expect(menu.getByRole('menuitem', { name: /Open in ChatGPT/ })).toHaveAttribute(
      'href',
      /^https:\/\/chatgpt\.com\/\?hints=search&q=.*quick-start\.md/,
    )
    await expect(menu.getByRole('menuitem', { name: /^llms\.txt/ })).toHaveAttribute('href', `${BASE}llms.txt`)
    await expect(menu.getByRole('menuitem', { name: /^llms-full\.txt/ })).toHaveAttribute(
      'href',
      `${BASE}llms-full.txt`,
    )
    await page.keyboard.press('Escape')
    await expect(menu).toHaveCount(0)
  })
})
