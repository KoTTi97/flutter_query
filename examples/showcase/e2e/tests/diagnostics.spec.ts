import type { Page } from '@playwright/test'
import { expect, fact, test } from './fixtures'

// One fact of a card, by its group and exact text — `status=error` is said by
// the mutation's facts and by the strip alike.
const factOf = (page: Page, label: string, text: string) =>
  page.getByRole('group', { name: `facts ${label}`, exact: true }).getByText(text, { exact: true })

const button = (page: Page, name: string) => page.getByRole('button', { name, exact: true })

const INCREMENT = /^\/api\/counter\/increment$/

test('a read as the entry\'s type answers, a read as another type throws QueryDataTypeError', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await open('/diagnostics')
  await expect(page.getByText('counter=0', { exact: true })).toBeVisible()
  await expect(factOf(page, 'typed', 'read=none')).toBeVisible()

  await button(page, 'Read as int').click()
  await expect(factOf(page, 'typed', 'read=int 0')).toBeVisible()

  await button(page, 'Read as String').click()
  await expect(factOf(page, 'typed', 'read=QueryDataTypeError')).toBeVisible()
  await expect(factOf(page, 'typed', 'expected=String')).toBeVisible()
  await expect(factOf(page, 'typed', 'actual=int')).toBeVisible()
})

test('a write of another type throws too and leaves the entry alone', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/diagnostics')
  await expect(fact(page, 'counter', 'updates=1')).toBeVisible()

  await button(page, 'Write a String').click()

  await expect(factOf(page, 'typed', 'write=QueryDataTypeError')).toBeVisible()
  await expect(factOf(page, 'typed', 'expected=String')).toBeVisible()
  await expect(factOf(page, 'typed', 'actual=int')).toBeVisible()
  // Nothing was written: the entry still holds its one int.
  await expect(fact(page, 'counter', 'updates=1')).toBeVisible()
  await expect(fact(page, 'counter', 'status=success')).toBeVisible()
  await expect(page.getByText('counter=0', { exact: true })).toBeVisible()
})

test('a mutation without a function fails with MissingMutationFunctionError and sends nothing', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await open('/diagnostics')
  await expect(factOf(page, 'no-function', 'status=idle')).toBeVisible()
  await expect(factOf(page, 'no-function', 'default=none')).toBeVisible()

  await button(page, 'Mutate without a function').click()

  await expect(factOf(page, 'no-function', 'status=error')).toBeVisible()
  await expect(factOf(page, 'no-function', 'error=MissingMutationFunctionError')).toBeVisible()
  await expect(page.getByText(/No mutationFn was provided/)).toBeVisible()
  await page.waitForTimeout(500)
  expect(await scenario.count('POST', INCREMENT)).toBe(0)
  expect((await (await scenario.api('get', '/counter')).json()).value).toBe(0)
})

test('a default mutationFn registered for the key is the cure', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/diagnostics')
  await button(page, 'Mutate without a function').click()
  await expect(factOf(page, 'no-function', 'status=error')).toBeVisible()

  await button(page, 'Register a default mutationFn').click()
  await expect(factOf(page, 'no-function', 'default=registered')).toBeVisible()

  await button(page, 'Mutate without a function').click()

  await expect(factOf(page, 'no-function', 'status=success')).toBeVisible()
  await expect(factOf(page, 'no-function', 'data=1')).toBeVisible()
  expect(await scenario.count('POST', INCREMENT)).toBe(1)
  expect((await (await scenario.api('get', '/counter')).json()).value).toBe(1)
})
