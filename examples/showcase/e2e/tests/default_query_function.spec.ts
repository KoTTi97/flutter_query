import type { Locator, Page } from '@playwright/test'
import { expect, fact, test } from './fixtures'

// The screen is longer than the browser window, and the scaffold's list
// builds only what is in view — so a section below the fold is not in the
// semantics tree until the list has been scrolled to it. The wheel goes to
// Flutter's own scrolling, like a user's would.
async function reveal(page: Page, target: Locator) {
  await page.mouse.move(640, 400)
  for (let step = 0; step < 20 && (await target.count()) === 0; step += 1) {
    await page.mouse.wheel(0, 300)
    await page.waitForTimeout(150)
  }
  await expect(target).toBeVisible()
}

const text = (page: Page, value: string) => page.getByText(value, { exact: true })

test('three keyed queries fetch through the default queryFn, one request each', async ({ page, open, scenario }) => {
  await open('/default-query-function')

  await expect(text(page, '#1 Local development: setup guide')).toBeVisible()
  await expect(text(page, 'posts=30')).toBeVisible()
  await expect(fact(page, 'posts', 'fetches=1')).toBeVisible()

  await reveal(page, fact(page, 'comments-1', 'status=success'))
  await expect(text(page, 'Local development: setup guide')).toBeVisible()
  await expect(text(page, 'Anna on "Local development: setup guide": Worked on the first try.')).toBeVisible()
  await expect(text(page, 'Ben on "Local development: setup guide": Connected on the second attempt.')).toBeVisible()
  await expect(text(page, 'Clara on "Local development: setup guide": Needs a rebuild.')).toBeVisible()
  await expect(fact(page, 'post-1', 'fetches=1')).toBeVisible()
  await expect(fact(page, 'comments-1', 'fetches=1')).toBeVisible()

  expect(await scenario.count('GET', /^\/api\/posts$/)).toBe(1)
  expect(await scenario.count('GET', /^\/api\/posts\/1$/)).toBe(1)
  expect(await scenario.count('GET', /^\/api\/posts\/1\/comments$/)).toBe(1)
})

test('the panel reports the defaults registered for the screen', async ({ page, open }) => {
  await open('/default-query-function')

  await expect(text(page, 'default queryFn=set')).toBeVisible()
  await expect(text(page, 'default mutationFn=set')).toBeVisible()
})

test('a mutation with only a key runs the default mutationFn', async ({ page, open, scenario }) => {
  await open('/default-query-function')
  await expect(fact(page, 'posts', 'fetchStatus=idle')).toBeVisible()

  await reveal(page, text(page, 'Create a todo'))
  await page.getByRole('button', { name: 'Create a todo', exact: true }).click()

  // The scenario was reseeded with three todos; the backend numbers the next one 4.
  await expect(text(page, 'new todo id=4')).toBeVisible()
  await expect(text(page, 'Written by the default mutationFn')).toBeVisible()
  expect(await scenario.count('POST', /^\/api\/todos$/)).toBe(1)
  const todos = (await (await scenario.api('get', '/todos')).json()) as Array<{ id: number; text: string }>
  expect(todos.at(-1)).toMatchObject({ id: 4, text: 'Written by the default mutationFn' })
})

test("a key with no post behind it shows the backend's 404", async ({ page, open, scenario }) => {
  await open('/default-query-function')
  await expect(fact(page, 'posts', 'fetchStatus=idle')).toBeVisible()

  // The strip sits under the card, so revealing it keeps the button in view too.
  await reveal(page, fact(page, 'post-999', 'status=absent'))
  await page.getByRole('button', { name: 'Fetch a missing post', exact: true }).click()

  await expect(text(page, 'Post not found')).toBeVisible()
  await expect(fact(page, 'post-999', 'status=error')).toBeVisible()
  await expect(fact(page, 'post-999', 'fetchStatus=idle')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/posts\/999$/)).toBe(1)
})
