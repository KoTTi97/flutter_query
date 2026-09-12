import type { Page } from '@playwright/test'
import { expect, fact, group, holdRequest, test } from './fixtures'

// The five readers of the one entry, by the id of their semantics group.
const readers = ['context', 'builder', 'mixin', 'controller', 'raw'] as const
type Reader = (typeof readers)[number]

/// One reader's row: a semantics group named `reader <id>`, the way a debug
/// strip is `debug <label>`.
const reader = (page: Page, id: Reader) => group(page, `reader ${id}`)

type Counters = { builds: number; dataBuilds: number }

/// A reader's two counters, read off its exact `builds=<n>` and
/// `data builds=<n>` texts.
async function counters(page: Page, id: Reader): Promise<Counters> {
  const read = async (name: string) => {
    const text = await reader(page, id)
      .getByText(new RegExp(`^${name}=\\d+$`))
      .textContent()
    return Number(text!.slice(name.length + 1))
  }
  return { builds: await read('builds'), dataBuilds: await read('data builds') }
}

async function snapshot(page: Page): Promise<Record<Reader, Counters>> {
  const result = {} as Record<Reader, Counters>
  for (const id of readers) result[id] = await counters(page, id)
  return result
}

/// The first load has landed everywhere: the entry is idle after one fetch
/// and every reader has built its selection once.
async function loaded(page: Page) {
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'todos', 'fetches=1')).toBeVisible()
  for (const id of readers) {
    await expect(reader(page, id).getByText('data builds=1', { exact: true })).toBeVisible()
  }
}

const refetchButton = (page: Page) => page.getByRole('button', { name: 'Refetch', exact: true })

test('every reader shows its selection after one request', async ({ page, open, scenario }) => {
  await open('/select-and-sharing')
  await loaded(page)

  await expect(fact(page, 'todos', 'observers=5')).toBeVisible()
  await expect(reader(page, 'context').getByText('count=3', { exact: true })).toBeVisible()
  await expect(reader(page, 'builder').getByText('first=Update the deploy checklist', { exact: true })).toBeVisible()
  await expect(reader(page, 'mixin').getByText('done=1', { exact: true })).toBeVisible()
  await expect(reader(page, 'mixin').getByText('open=2', { exact: true })).toBeVisible()
  for (const text of [
    'Update the deploy checklist',
    'Rename the columns on the board',
    'Replace the expired API token',
  ]) {
    await expect(reader(page, 'controller').getByText(text, { exact: true })).toBeVisible()
  }
  await expect(reader(page, 'raw').getByText('length=3', { exact: true })).toBeVisible()
  // Pending, then the data: two builds each.
  for (const id of readers) {
    await expect(reader(page, id).getByText('builds=2', { exact: true })).toBeVisible()
  }
  expect(await scenario.count('GET', /^\/api\/todos$/)).toBe(1)
})

test('a refetch with equal data changes no selection', async ({ page, open, scenario }) => {
  await open('/select-and-sharing')
  await loaded(page)
  const before = await snapshot(page)

  // Held in the browser, so the flip to fetching and the landing are two
  // separate moments, as they are on any real network.
  const hold = holdRequest(page, '**/api/todos*')
  await refetchButton(page).click()
  await expect(fact(page, 'todos', 'fetchStatus=fetching')).toBeVisible()
  const flipped = await snapshot(page)
  // The flip is a rebuild for every reader without a `buildWhen`, and not
  // for the one with it — nothing selected changed.
  for (const id of ['context', 'mixin', 'controller', 'raw'] as const) {
    expect(flipped[id].builds, `${id} builds`).toBe(before[id].builds + 1)
  }
  expect(flipped.builder.builds).toBe(before.builder.builds)
  await hold.release()

  await expect(fact(page, 'todos', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
  // The landing is the second rebuild for the same readers.
  await expect(reader(page, 'context').getByText(`builds=${before.context.builds + 2}`, { exact: true })).toBeVisible()
  const after = await snapshot(page)
  for (const id of readers) {
    expect(after[id].dataBuilds, `${id} data builds`).toBe(before[id].dataBuilds)
  }
  expect(after.builder.builds).toBe(before.builder.builds)
  for (const id of ['mixin', 'controller', 'raw'] as const) {
    expect(after[id].builds, `${id} builds`).toBe(before[id].builds + 2)
  }
  expect(await scenario.count('GET', /^\/api\/todos$/)).toBe(2)
})

test('toggling todo 1 moves only the done/open record', async ({ page, open, scenario }) => {
  await open('/select-and-sharing')
  await loaded(page)
  const before = await snapshot(page)

  await page.getByRole('button', { name: 'Toggle todo 1', exact: true }).click()
  // The mutation's `onSuccess` invalidated the entry, which refetched it.
  await expect(reader(page, 'mixin').getByText('done=2', { exact: true })).toBeVisible()
  await expect(reader(page, 'mixin').getByText('open=1', { exact: true })).toBeVisible()
  await expect(fact(page, 'todos', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()

  const after = await snapshot(page)
  // The record and the cache's own list changed; the count, the first text
  // and the texts did not.
  expect(after.mixin.dataBuilds).toBe(before.mixin.dataBuilds + 1)
  expect(after.raw.dataBuilds).toBe(before.raw.dataBuilds + 1)
  for (const id of ['context', 'builder', 'controller'] as const) {
    expect(after[id].dataBuilds, `${id} data builds`).toBe(before[id].dataBuilds)
  }
  expect(after.builder.builds).toBe(before.builder.builds)
  expect(await scenario.count('PATCH', /^\/api\/todos\/1$/)).toBe(1)
  expect(await scenario.count('GET', /^\/api\/todos$/)).toBe(2)
})

test('renaming todo 2 moves only the list of texts', async ({ page, open, scenario }) => {
  await open('/select-and-sharing')
  await loaded(page)
  const before = await snapshot(page)

  await page.getByRole('button', { name: 'Rename todo 2', exact: true }).click()
  await expect(reader(page, 'controller').getByText('Renamed todo 2 x1', { exact: true })).toBeVisible()
  await expect(reader(page, 'controller').getByText('Rename the columns on the board', { exact: true })).toBeHidden()
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()

  const after = await snapshot(page)
  expect(after.controller.dataBuilds).toBe(before.controller.dataBuilds + 1)
  expect(after.raw.dataBuilds).toBe(before.raw.dataBuilds + 1)
  for (const id of ['context', 'builder', 'mixin'] as const) {
    expect(after[id].dataBuilds, `${id} data builds`).toBe(before[id].dataBuilds)
  }
  expect(after.builder.builds).toBe(before.builder.builds)

  // Each rename is a new text, so the list of texts moves every time.
  await page.getByRole('button', { name: 'Rename todo 2', exact: true }).click()
  await expect(reader(page, 'controller').getByText('Renamed todo 2 x2', { exact: true })).toBeVisible()
  await expect(reader(page, 'controller').getByText(`data builds=${before.controller.dataBuilds + 2}`, { exact: true })).toBeVisible()
  expect(await scenario.count('PATCH', /^\/api\/todos\/2$/)).toBe(2)
})

test('with sharing off, an equal refetch still moves no selection', async ({ page, open, scenario }) => {
  await open('/select-and-sharing')
  await loaded(page)

  const sharingOff = page.getByRole('switch', { name: 'Structural sharing off', exact: true })
  await sharingOff.click()
  await expect(sharingOff).toBeChecked()
  // The toggle rebuilt every reader once, with nothing new selected.
  for (const id of readers) {
    await expect(reader(page, id).getByText('builds=3', { exact: true })).toBeVisible()
  }
  const before = await snapshot(page)

  const hold = holdRequest(page, '**/api/todos*')
  await refetchButton(page).click()
  await expect(fact(page, 'todos', 'fetchStatus=fetching')).toBeVisible()
  await hold.release()
  await expect(fact(page, 'todos', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
  await expect(reader(page, 'context').getByText(`builds=${before.context.builds + 2}`, { exact: true })).toBeVisible()

  // What `select` produces is shared whatever the option says: the four
  // `select` readers saw nothing new. The readers without a `buildWhen`
  // still rebuilt for the flip and the landing — the `ListenableBuilder`
  // among them, which has no equality guard at all.
  const after = await snapshot(page)
  for (const id of ['context', 'builder', 'mixin', 'controller'] as const) {
    expect(after[id].dataBuilds, `${id} data builds`).toBe(before[id].dataBuilds)
  }
  expect(after.builder.builds).toBe(before.builder.builds)
  for (const id of ['mixin', 'controller', 'raw'] as const) {
    expect(after[id].builds, `${id} builds`).toBe(before[id].builds + 2)
  }
  expect(await scenario.count('GET', /^\/api\/todos$/)).toBe(2)
})
