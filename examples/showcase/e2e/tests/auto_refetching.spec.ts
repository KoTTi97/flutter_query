import type { Page } from '@playwright/test'

import { expect, fact, test } from './fixtures'

// Two cards, a bounded list and the strip are taller than the default
// viewport, and a strip below the fold is never built.
test.use({ viewport: { width: 1280, height: 1800 } })

const TICKS = /^\/api\/ticks$/

// No clock in any assertion: a poll is proven to run by sampling the request
// log, waiting, and sampling again — and proven to have stopped the same way.
const settle = 400
const pollWindow = 1600

const interval = (page: Page, name: string) => page.getByRole('radio', { name, exact: true })
const button = (page: Page, name: string) => page.getByRole('button', { name, exact: true })

test('with the interval off the list is fetched once and stays', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/auto-refetching')

  await expect(fact(page, 'ticks', 'status=success')).toBeVisible()
  await expect(page.getByText('ticks=0', { exact: true })).toBeVisible()
  await expect(page.getByText('interval=off', { exact: true })).toBeVisible()
  expect(await scenario.count('GET', TICKS)).toBe(1)

  await page.waitForTimeout(2000)

  expect(await scenario.count('GET', TICKS)).toBe(1)
  await expect(fact(page, 'ticks', 'fetches=1')).toBeVisible()
})

test('500 ms polls, and going back to off freezes it', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/auto-refetching')
  await expect(fact(page, 'ticks', 'fetches=1')).toBeVisible()

  await interval(page, '500 ms').click()
  await expect(page.getByText('interval=500 ms', { exact: true })).toBeVisible()

  const before = await scenario.count('GET', TICKS)
  await page.waitForTimeout(pollWindow)
  const polled = await scenario.count('GET', TICKS)
  expect(polled).toBeGreaterThan(before)

  await interval(page, 'off').click()
  await expect(page.getByText('interval=off', { exact: true })).toBeVisible()
  // Whatever the last window started has landed by now.
  await page.waitForTimeout(settle)

  const frozen = await scenario.count('GET', TICKS)
  await page.waitForTimeout(pollWindow)
  expect(await scenario.count('GET', TICKS)).toBe(frozen)
})

test('a tick added while polling shows up, and clearing empties the list', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/auto-refetching')
  await expect(page.getByText('ticks=0', { exact: true })).toBeVisible()

  await interval(page, '500 ms').click()
  await button(page, 'Add tick').click()

  await expect(page.getByText('tick 1', { exact: true })).toBeVisible()
  await expect(page.getByText('ticks=1', { exact: true })).toBeVisible()

  await button(page, 'Add tick').click()
  await expect(page.getByText('tick 2', { exact: true })).toBeVisible()
  await expect(page.getByText('ticks=2', { exact: true })).toBeVisible()

  // The polls in between keep showing the same two rows.
  await page.waitForTimeout(pollWindow)
  await expect(page.getByText('ticks=2', { exact: true })).toBeVisible()

  await button(page, 'Clear ticks').click()
  await expect(page.getByText('ticks=0', { exact: true })).toBeVisible()
  await expect(page.getByText('No ticks yet.', { exact: true })).toBeVisible()
  await expect(page.getByText('tick 1', { exact: true })).toBeHidden()
})

test('unfocused, the interval only fetches with the background flag on', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/auto-refetching')
  await expect(fact(page, 'ticks', 'fetches=1')).toBeVisible()

  await interval(page, '500 ms').click()
  await button(page, 'Unfocus').click()
  await expect(page.getByText('focused=false', { exact: true })).toBeVisible()
  await expect(page.getByText('background=false', { exact: true })).toBeVisible()
  await page.waitForTimeout(settle)

  // The periodic timer keeps firing; every tick of it finds the app
  // unfocused and the flag off, and fetches nothing.
  const asleep = await scenario.count('GET', TICKS)
  await page.waitForTimeout(pollWindow)
  expect(await scenario.count('GET', TICKS)).toBe(asleep)

  const backgroundSwitch = page.getByRole('switch', { name: /Poll in the background/ })
  await backgroundSwitch.click()
  await expect(backgroundSwitch).toBeChecked()
  await expect(page.getByText('background=true', { exact: true })).toBeVisible()
  await expect(page.getByText('focused=false', { exact: true })).toBeVisible()

  const awake = await scenario.count('GET', TICKS)
  await page.waitForTimeout(pollWindow)
  expect(await scenario.count('GET', TICKS)).toBeGreaterThan(awake)
})

test('the dynamic interval stops itself at the third tick and starts again on clear', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await open('/auto-refetching')
  await expect(page.getByText('ticks=0', { exact: true })).toBeVisible()

  await interval(page, 'dynamic').click()
  await expect(page.getByText('interval=dynamic', { exact: true })).toBeVisible()

  const short = await scenario.count('GET', TICKS)
  await page.waitForTimeout(pollWindow)
  expect(await scenario.count('GET', TICKS)).toBeGreaterThan(short)

  await button(page, 'Add tick').click()
  await button(page, 'Add tick').click()
  await button(page, 'Add tick').click()
  await expect(page.getByText('ticks=3', { exact: true })).toBeVisible()
  await page.waitForTimeout(settle)

  // The rule returned null when the third tick landed, so no timer is armed.
  const stopped = await scenario.count('GET', TICKS)
  await page.waitForTimeout(pollWindow)
  expect(await scenario.count('GET', TICKS)).toBe(stopped)

  await button(page, 'Clear ticks').click()
  await expect(page.getByText('ticks=0', { exact: true })).toBeVisible()

  const restarted = await scenario.count('GET', TICKS)
  await page.waitForTimeout(pollWindow)
  expect(await scenario.count('GET', TICKS)).toBeGreaterThan(restarted)
})
