import type { Page } from '@playwright/test'
import { expect, fact, test } from './fixtures'

// Knobs, the list, an editor and two strips are taller than the default
// viewport, and the scaffold's list only builds what is in view.
test.use({ viewport: { width: 1280, height: 1800 } })

// A reader's own facts live in a semantics group of their own (`todos-reader`,
// `editor`, `backend`, `add`), because the strips show an `isStale=` too.
const reader = (page: Page, group: string, text: string) =>
  page.getByRole('group', { name: group, exact: true }).getByText(text, { exact: true })

const button = (page: Page, name: string) => page.getByRole('button', { name, exact: true })

// A segment of one knob: three knobs have a `0`, so the knob's group first.
const pick = (page: Page, knob: 'stale-time' | 'gc-time' | 'latency' | 'error-rate', label: string) =>
  page.getByRole('group', { name: knob, exact: true }).getByRole('radio', { name: label, exact: true }).click()

const todos = /^\/api\/todos$/

// The list has arrived and the screen's own knobs have reached the backend.
async function openPlayground(page: Page, open: (route: string) => Promise<void>) {
  await open('/playground')
  await expect(button(page, 'Update the gateway firmware')).toBeVisible()
  await expect(reader(page, 'backend', 'latency=0ms')).toBeVisible()
  await expect(reader(page, 'backend', 'errorRate=0%')).toBeVisible()
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
}

// A row's button opens the editor on that todo.
async function openEditor(page: Page, id: number, text: string) {
  await button(page, text).click()
  await expect(reader(page, 'editor', `editing=${id}`)).toBeVisible()
  await expect(fact(page, `todo-${id}`, 'fetchStatus=idle')).toBeVisible()
}

test('error rate 100 %: a refetch fails through the retries, and the list comes back at 0', async ({
  page,
  open,
  scenario,
}) => {
  await openPlayground(page, open)
  expect(await scenario.count('GET', todos)).toBe(1)

  await pick(page, 'error-rate', '100 %')
  await expect(reader(page, 'backend', 'errorRate=100%')).toBeVisible()

  // One attempt and three retries 300 ms apart, every one refused: the
  // count of five requests is what proves the retries ran.
  await button(page, 'Refetch').click()
  await expect(page.getByText('Refetch failed: Failed at random (errorRate)', { exact: true })).toBeVisible()
  await expect(reader(page, 'todos-reader', 'status=error')).toBeVisible()
  await expect(reader(page, 'todos-reader', 'failureCount=4')).toBeVisible()
  await expect(button(page, 'Update the gateway firmware')).toBeVisible()
  await expect(fact(page, 'todos', 'status=error')).toBeVisible()
  expect(await scenario.count('GET', todos)).toBe(5)

  await pick(page, 'error-rate', '0')
  await expect(reader(page, 'backend', 'errorRate=0%')).toBeVisible()
  await button(page, 'Refetch').click()
  await expect(reader(page, 'todos-reader', 'status=success')).toBeVisible()
  await expect(reader(page, 'todos-reader', 'failureCount=0')).toBeVisible()
  await expect(page.getByText('Refetch failed: Failed at random (errorRate)', { exact: true })).toBeHidden()
  await expect(fact(page, 'todos', 'status=success')).toBeVisible()
  expect(await scenario.count('GET', todos)).toBe(6)
})

test('stale time: the client default changed under a live observer reaches it', async ({ page, open, scenario }) => {
  await openPlayground(page, open)
  await expect(reader(page, 'todos-reader', 'isStale=true')).toBeVisible()
  await expect(fact(page, 'todos', 'isStale=true')).toBeVisible()

  // No fetch: the observer re-resolved its options against the new
  // defaults, and the data, seconds old, is within the 30 s.
  await pick(page, 'stale-time', '30 s')
  await expect(reader(page, 'todos-reader', 'isStale=false')).toBeVisible()
  await expect(fact(page, 'todos', 'isStale=false')).toBeVisible()
  await expect(fact(page, 'todos', 'fetches=1')).toBeVisible()

  await button(page, 'Refetch').click()
  await expect(fact(page, 'todos', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
  await expect(reader(page, 'todos-reader', 'isStale=false')).toBeVisible()

  // The editor is a second live observer on another State. Seeded from the
  // fresh list and dated with it, so under 30 s opening it costs no request.
  await openEditor(page, 2, 'Rename the sensors in the hallway')
  await expect(reader(page, 'editor', 'isStale=false')).toBeVisible()
  await expect(fact(page, 'todo-2', 'fetches=0')).toBeVisible()

  await pick(page, 'stale-time', '0')
  await expect(reader(page, 'todos-reader', 'isStale=true')).toBeVisible()
  await expect(reader(page, 'editor', 'isStale=true')).toBeVisible()
  await expect(fact(page, 'todos', 'isStale=true')).toBeVisible()
  await expect(fact(page, 'todos', 'fetches=2')).toBeVisible()
  expect(await scenario.count('GET', todos)).toBe(2)
})

test("gc time 5 s: a closed editor's entry is collected; 5 min keeps it", async ({ page, open }) => {
  await openPlayground(page, open)
  await pick(page, 'gc-time', '5 s')

  await openEditor(page, 1, 'Update the gateway firmware')
  await expect(fact(page, 'todo-1', 'status=success')).toBeVisible()
  await expect(fact(page, 'todo-1', 'observers=1')).toBeVisible()

  // Closing the editor removes its State and with it the observer.
  await button(page, 'Close editor').click()
  await expect(reader(page, 'editor', 'editing=1')).toBeHidden()
  await expect(fact(page, 'todo-1', 'observers=0')).toBeVisible()
  await expect(fact(page, 'todo-1', 'status=absent')).toBeVisible({ timeout: 15_000 })
  await expect(fact(page, 'todos', 'status=success')).toBeVisible()

  // A fresh entry under 5 min: sampled, waited past the five seconds,
  // sampled again.
  await pick(page, 'gc-time', '5 min')
  await openEditor(page, 1, 'Update the gateway firmware')
  await expect(fact(page, 'todo-1', 'status=success')).toBeVisible()
  await button(page, 'Close editor').click()
  await expect(fact(page, 'todo-1', 'observers=0')).toBeVisible()
  await page.waitForTimeout(7_000)
  await expect(fact(page, 'todo-1', 'status=success')).toBeVisible()
  await expect(fact(page, 'todo-1', 'observers=0')).toBeVisible()
})

test("invalidate everything refetches the list and the open editor's entry", async ({ page, open, scenario }) => {
  await openPlayground(page, open)
  // Under stale time 0 the seeded editor refetches on mount: one fetch of
  // its own, and one more `GET /api/todos`.
  await openEditor(page, 3, 'Replace the battery in the window contact')
  await expect(fact(page, 'todos', 'fetches=1')).toBeVisible()
  await expect(fact(page, 'todo-3', 'fetches=1')).toBeVisible()
  expect(await scenario.count('GET', todos)).toBe(2)

  await button(page, 'Invalidate everything').click()
  await expect(fact(page, 'todos', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'todo-3', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'todo-3', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'todo-3', 'status=success')).toBeVisible()
  expect(await scenario.count('GET', todos)).toBe(4)
})

test('add, rename and complete a todo: the list reflects each', async ({ page, open, scenario }) => {
  await openPlayground(page, open)
  expect(await scenario.count('GET', todos)).toBe(1)

  const newTodo = page.getByRole('textbox', { name: 'New todo', exact: true })
  await newTodo.click()
  await newTodo.fill('Water the plants')
  await button(page, 'Add todo').click()
  await expect(reader(page, 'add', 'adding=success')).toBeVisible()
  await expect(button(page, 'Water the plants')).toBeVisible()
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
  expect(await scenario.count('POST', todos)).toBe(1)
  expect(await scenario.count('GET', todos)).toBe(2)

  // Opening the editor is one fetch of its own (stale time 0).
  await openEditor(page, 4, 'Water the plants')
  expect(await scenario.count('GET', todos)).toBe(3)

  const text = page.getByRole('textbox', { name: 'Text', exact: true })
  await text.click()
  await expect(text).toHaveValue('Water the plants')
  await text.fill('Water the plants twice')
  await button(page, 'Rename').click()
  await expect(reader(page, 'editor', 'saving=success')).toBeVisible()
  await expect(button(page, 'Water the plants twice')).toBeVisible()
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
  expect(await scenario.count('PATCH', /^\/api\/todos\/4$/)).toBe(1)
  expect(await scenario.count('GET', todos)).toBe(4)

  const done = page.getByRole('checkbox', { name: 'Done', exact: true })
  await expect(done).not.toBeChecked()
  await done.click()
  await expect(done).toBeChecked()
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
  expect(await scenario.count('PATCH', /^\/api\/todos\/4$/)).toBe(2)
  expect(await scenario.count('GET', todos)).toBe(5)
  // The PATCH's answer went straight into the editor's entry: no fetch.
  await expect(fact(page, 'todo-4', 'fetches=1')).toBeVisible()

  // What the backend really holds.
  const stored = (await (await scenario.api('get', '/todos')).json()) as { id: number; text: string; done: boolean }[]
  expect(stored.find((todo) => todo.id === 4)).toEqual({ id: 4, text: 'Water the plants twice', done: true })
})
