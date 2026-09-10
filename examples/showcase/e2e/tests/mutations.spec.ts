import { expect, fact, holdRequest, test, type Page } from './fixtures'

// Four cards and a strip: taller than the default viewport, and a lazily
// built list only has what is in view.
test.use({ viewport: { width: 1280, height: 1800 } })

const INCREMENT = '**/api/counter/increment*'

/// A mutation's facts live in the group `mutation <label>`, because
/// `status=success` is also what the counter's strip says about the query.
const mutation = (page: Page, label: string, text: string) =>
  page.getByRole('group', { name: `mutation ${label}`, exact: true }).getByText(text, { exact: true })

const button = (page: Page, name: string) => page.getByRole('button', { name, exact: true })

test('mutate is pending while the request is out, then success, and the invalidated counter refetches', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await open('/mutations')
  await expect(page.getByText('counter=0', { exact: true })).toBeVisible()
  await expect(mutation(page, 'increment', 'status=idle')).toBeVisible()
  await expect(mutation(page, 'increment', 'submittedAt=none')).toBeVisible()

  const hold = holdRequest(page, INCREMENT)
  await button(page, 'Increment (mutate)').click()

  // The backend has provably not answered: the request is held in the browser.
  await expect(mutation(page, 'increment', 'status=pending')).toBeVisible()
  await expect(mutation(page, 'increment', 'isPending=true')).toBeVisible()
  await expect(mutation(page, 'increment', 'submittedAt=set')).toBeVisible()
  await expect(page.getByText('isMutating=1', { exact: true })).toBeVisible()
  await expect(page.getByText('counter=0', { exact: true })).toBeVisible()
  expect(await scenario.count('POST', /^\/api\/counter\/increment$/)).toBe(0)
  await hold.release()

  await expect(mutation(page, 'increment', 'status=success')).toBeVisible()
  await expect(mutation(page, 'increment', 'data=1')).toBeVisible()
  await expect(mutation(page, 'increment', 'failureCount=0')).toBeVisible()
  await expect(page.getByText('isMutating=0', { exact: true })).toBeVisible()
  // `onSuccess` invalidated the counter: one more GET, and the new value.
  await expect(page.getByText('counter=1', { exact: true })).toBeVisible()
  await expect(fact(page, 'counter', 'fetches=2')).toBeVisible()
  expect(await scenario.count('POST', /^\/api\/counter\/increment$/)).toBe(1)
  expect(await scenario.count('GET', /^\/api\/counter$/)).toBe(2)

  await button(page, 'Reset').click()
  await expect(mutation(page, 'increment', 'status=idle')).toBeVisible()
  await expect(mutation(page, 'increment', 'submittedAt=none')).toBeVisible()
  await expect(mutation(page, 'increment', 'data=1')).toBeHidden()
  await expect(page.getByText('counter=1', { exact: true })).toBeVisible()
})

test('mutateAsync hands its value to the caller', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/mutations')
  await expect(page.getByText('counter=0', { exact: true })).toBeVisible()

  await button(page, 'Increment (mutate)').click()
  await expect(mutation(page, 'increment', 'data=1')).toBeVisible()

  await button(page, 'Increment (mutateAsync)').click()
  await expect(page.getByText('mutateAsync result=2', { exact: true })).toBeVisible()
  await expect(mutation(page, 'increment', 'data=2')).toBeVisible()
  await expect(page.getByText('counter=2', { exact: true })).toBeVisible()
  expect(await scenario.count('POST', /^\/api\/counter\/increment$/)).toBe(2)
})

test('a refused request is the error at once: one POST, no retry, the counter stays', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await open('/mutations')
  await expect(page.getByText('counter=0', { exact: true })).toBeVisible()

  await page.getByRole('checkbox', { name: 'Fail next' }).click()
  await button(page, 'Increment (mutate)').click()

  await expect(mutation(page, 'increment', 'status=error')).toBeVisible()
  await expect(mutation(page, 'increment', 'error=Requested: 500')).toBeVisible()
  await expect(mutation(page, 'increment', 'failureCount=1')).toBeVisible()
  await expect(mutation(page, 'increment', 'isPending=false')).toBeVisible()
  await expect(page.getByText('counter=0', { exact: true })).toBeVisible()
  // Long enough for a retry to have shown up, had there been one (the
  // first retry delay would be one second).
  await page.waitForTimeout(1500)
  expect(await scenario.count('POST', /^\/api\/counter\/increment$/)).toBe(1)
  expect(await scenario.count('GET', /^\/api\/counter$/)).toBe(1)
  expect((await (await scenario.api('get', '/counter')).json()).value).toBe(0)

  // `Fail next` was spent: the next call goes through.
  await button(page, 'Increment (mutate)').click()
  await expect(mutation(page, 'increment', 'status=success')).toBeVisible()
  await expect(page.getByText('counter=1', { exact: true })).toBeVisible()
})

test('the option callbacks run before the per-call ones', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/mutations')
  await expect(page.getByText('log=empty', { exact: true })).toBeVisible()

  await button(page, 'Run with callbacks').click()

  // The library's order: `onMutate`, the function, then the options'
  // `onSuccess` and `onSettled` (each awaited), and only then — once the
  // success has been dispatched — the callbacks passed to `mutate`.
  for (const line of [
    '1 onMutate',
    '2 mutationFn',
    '3 onSuccess (options)',
    '4 onSettled (options)',
    '5 onSuccess (call)',
    '6 onSettled (call)',
  ]) {
    await expect(page.getByText(line, { exact: true })).toBeVisible()
  }
  await expect(page.getByText('counter=1', { exact: true })).toBeVisible()
  expect(await scenario.count('POST', /^\/api\/counter\/increment$/)).toBe(1)
})

test('two scoped mutations send one request at a time', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/mutations')
  await expect(page.getByText('counter=0', { exact: true })).toBeVisible()

  const hold = holdRequest(page, INCREMENT)
  await button(page, 'Run two scoped').click()

  // Both are pending, but only the first has a request out; the second is
  // paused behind it and stays so while the first is held.
  await expect.poll(() => hold.seen).toBe(1)
  await expect(mutation(page, 'pairs', 'first=pending')).toBeVisible()
  await expect(mutation(page, 'pairs', 'second=pending')).toBeVisible()
  await expect(mutation(page, 'pairs', 'secondPaused=true')).toBeVisible()
  await expect(page.getByText('isMutating=2', { exact: true })).toBeVisible()
  await page.waitForTimeout(1000)
  expect(hold.seen).toBe(1)
  await hold.release()

  // Released, the first takes its second on the backend, then the second
  // goes out and takes its own.
  await expect(mutation(page, 'pairs', 'first=success')).toBeVisible()
  await expect(mutation(page, 'pairs', 'second=success')).toBeVisible()
  await expect(page.getByText('isMutating=0', { exact: true })).toBeVisible()
  await expect(page.getByText('counter=2', { exact: true })).toBeVisible()
  expect(hold.seen).toBe(2)
  expect(await scenario.count('POST', /^\/api\/counter\/increment$/)).toBe(2)
})

test('two unscoped mutations send both requests at once', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/mutations')
  await expect(page.getByText('counter=0', { exact: true })).toBeVisible()

  const hold = holdRequest(page, INCREMENT)
  await button(page, 'Run two unscoped').click()

  await expect.poll(() => hold.seen).toBe(2)
  await expect(mutation(page, 'pairs', 'third=pending')).toBeVisible()
  await expect(mutation(page, 'pairs', 'fourth=pending')).toBeVisible()
  expect(await scenario.count('POST', /^\/api\/counter\/increment$/)).toBe(0)
  await hold.release()

  await expect(mutation(page, 'pairs', 'third=success')).toBeVisible()
  await expect(mutation(page, 'pairs', 'fourth=success')).toBeVisible()
  await expect(page.getByText('counter=2', { exact: true })).toBeVisible()
  expect(await scenario.count('POST', /^\/api\/counter\/increment$/)).toBe(2)
})

test('a mutation fired just before its reader unmounts still lands', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/mutations')
  await expect(page.getByText('counter=0', { exact: true })).toBeVisible()

  const hold = holdRequest(page, INCREMENT)
  await button(page, 'Fire and leave').click()

  // The reader is gone before the backend has answered; the cache still
  // counts the run.
  await expect(page.getByText('view=away', { exact: true })).toBeVisible()
  await expect(page.getByText('counter=0', { exact: true })).toBeHidden()
  await expect(page.getByText('isMutating=1', { exact: true })).toBeVisible()
  expect(await scenario.count('POST', /^\/api\/counter\/increment$/)).toBe(0)
  await hold.release()

  await expect(page.getByText('isMutating=0', { exact: true })).toBeVisible()
  expect(await scenario.count('POST', /^\/api\/counter\/increment$/)).toBe(1)
  // Invalidated with nobody observing it: the counter is stale, not
  // refetched, until a reader comes back.
  expect(await scenario.count('GET', /^\/api\/counter$/)).toBe(1)
  // The backend really holds the increment. (A direct read is logged like
  // any other, which is why it comes after the count.)
  expect((await (await scenario.api('get', '/counter')).json()).value).toBe(1)

  await button(page, 'Back to reader').click()
  await expect(page.getByText('counter=1', { exact: true })).toBeVisible()
  await expect(mutation(page, 'increment', 'status=idle')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/counter$/)).toBe(3)
})
