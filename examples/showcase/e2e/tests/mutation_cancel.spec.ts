import { expect, fact, factIn, test, type Page } from './fixtures'

// The rename card with its facts, the strip and the list: taller than the
// default viewport, and the scaffold's list builds only what is in view.
test.use({ viewport: { width: 1280, height: 1200 } })

const TODOS = /^\/api\/todos$/
const TODO = /^\/api\/todos\/1$/

const BEFORE = 'Update the deploy checklist'
const AFTER = 'Rewrite the deploy checklist'

/// The card's facts live in a group of their own, because `status=` is also
/// what the debug strip says about the list.
const renameFact = (page: Page, text: string) => factIn(page, 'rename facts', text)

const button = (page: Page, name: string) => page.getByRole('button', { name, exact: true })

/// `holdRequest` for the write only: `page.route` cannot filter by method, so
/// the handler lets everything but the PATCH through — the CORS preflight that
/// precedes it included. A request the app cancelled while it was held is gone
/// by the time it is released, and continuing it is then an error to swallow.
function holdPatch(page: Page) {
  let letGo: () => void = () => {}
  const held = new Promise<void>((resolve) => {
    letGo = resolve
  })
  let seen = 0
  const routed = page.route('**/api/todos/1*', async (route) => {
    if (route.request().method() !== 'PATCH') {
      await route.continue()
      return
    }
    seen += 1
    await held
    await route.continue().catch(() => {})
  })
  return {
    get seen() {
      return seen
    },
    async release() {
      await routed
      letGo()
    },
  }
}

/// Every request the browser gave up on, by URL fragment. An aborted XHR is
/// reported as `requestfailed`, which is the browser's own word for "the
/// signal reached the transport" — no clock involved.
function abortedRequests(page: Page, fragment: string) {
  const aborted: string[] = []
  page.on('requestfailed', (request) => {
    if (request.url().includes(fragment)) aborted.push(request.method())
  })
  return aborted
}

/// Types `text` into the field and presses `Rename`.
async function rename(page: Page, text: string) {
  const field = page.getByRole('textbox')
  await field.click()
  await field.fill(text)
  await button(page, 'Rename').click()
}

test('the write is sent with what onMutate kept, not what the cache says', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/mutation-cancel')
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
  await expect(renameFact(page, 'status=idle')).toBeVisible()
  await expect(renameFact(page, `text=${BEFORE}`)).toBeVisible()
  await expect(renameFact(page, 'from=none')).toBeVisible()
  await expect(button(page, 'Cancel')).toHaveAttribute('aria-disabled', 'true')

  const hold = holdPatch(page)
  await rename(page, AFTER)

  // The backend has provably not answered: the PATCH is held in the browser.
  // The cache already says the new text, so `from` can only have come from
  // `context.onMutateResult`.
  await expect(renameFact(page, 'status=pending')).toBeVisible()
  await expect(renameFact(page, `text=${AFTER}`)).toBeVisible()
  await expect(renameFact(page, `from=${BEFORE}`)).toBeVisible()
  await expect(page.getByText(AFTER, { exact: true })).toBeVisible()
  await expect(button(page, 'Cancel')).not.toHaveAttribute('aria-disabled', 'true')
  await expect.poll(() => hold.seen).toBe(1)
  expect(await scenario.count('PATCH', TODO)).toBe(0)
  await hold.release()

  await expect(renameFact(page, 'status=success')).toBeVisible()
  await expect(renameFact(page, 'error=none')).toBeVisible()
  await expect(renameFact(page, `text=${AFTER}`)).toBeVisible()
  await expect(renameFact(page, 'signalCancels=0')).toBeVisible()
  await expect(renameFact(page, 'rollbacks=0')).toBeVisible()
  await expect(renameFact(page, 'settles=1')).toBeVisible()
  // What the backend saw of the request: `from` in its query, and the text.
  const patches = (await scenario.requests()).filter((entry) => entry.method === 'PATCH')
  expect(patches).toHaveLength(1)
  expect(patches[0].query.from).toBe(BEFORE)
  expect(patches[0].status).toBe(200)
  expect(await scenario.count('GET', TODOS)).toBe(2)
  const todos = (await (await scenario.api('get', '/todos')).json()) as Array<{ id: number; text: string }>
  expect(todos.find((todo) => todo.id === 1)?.text).toBe(AFTER)
})

test('cancel fails the run: rolled back by onError, invalidated by onSettled', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  const aborted = abortedRequests(page, '/api/todos/1')
  await open('/mutation-cancel')
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
  await expect(renameFact(page, `text=${BEFORE}`)).toBeVisible()

  const hold = holdPatch(page)
  await rename(page, AFTER)
  await expect(renameFact(page, 'status=pending')).toBeVisible()
  await expect(renameFact(page, `text=${AFTER}`)).toBeVisible()
  await expect(page.getByText(AFTER, { exact: true })).toBeVisible()
  await expect.poll(() => hold.seen).toBe(1)

  await button(page, 'Cancel').click()

  await expect(renameFact(page, 'status=error')).toBeVisible()
  await expect(renameFact(page, 'error=cancelled')).toBeVisible()
  await expect(renameFact(page, 'signalCancels=1')).toBeVisible()
  // `onError` put the snapshot back …
  await expect(renameFact(page, 'rollbacks=1')).toBeVisible()
  await expect(renameFact(page, `text=${BEFORE}`)).toBeVisible()
  await expect(page.getByText(AFTER, { exact: true })).toBeHidden()
  // … and `onSettled` asked the backend what it really holds.
  await expect(renameFact(page, 'settles=1')).toBeVisible()
  await expect(fact(page, 'todos', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
  expect(await scenario.count('GET', TODOS)).toBe(2)
  await expect(button(page, 'Cancel')).toHaveAttribute('aria-disabled', 'true')

  // The signal reached the transport: the browser gave the PATCH up, and
  // releasing the hold has nothing left to send.
  await expect.poll(() => aborted).toEqual(['PATCH'])
  await hold.release()
  expect(await scenario.count('PATCH', TODO)).toBe(0)
  const todos = (await (await scenario.api('get', '/todos')).json()) as Array<{ id: number; text: string }>
  expect(todos.find((todo) => todo.id === 1)?.text).toBe(BEFORE)
})

test('a rename after a cancelled one goes through', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/mutation-cancel')
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()

  const hold = holdPatch(page)
  await rename(page, 'Never sent')
  await expect.poll(() => hold.seen).toBe(1)
  await button(page, 'Cancel').click()
  await expect(renameFact(page, 'error=cancelled')).toBeVisible()
  await expect(renameFact(page, `text=${BEFORE}`)).toBeVisible()
  // Released: from here on the handler is a passthrough.
  await hold.release()

  // A new run, a new signal: the old one's cancellation is not inherited.
  await rename(page, AFTER)
  await expect(renameFact(page, 'status=success')).toBeVisible()
  await expect(renameFact(page, 'error=none')).toBeVisible()
  await expect(renameFact(page, `text=${AFTER}`)).toBeVisible()
  await expect(renameFact(page, 'signalCancels=1')).toBeVisible()
  await expect(renameFact(page, 'rollbacks=1')).toBeVisible()
  await expect(renameFact(page, 'settles=2')).toBeVisible()
  const patches = (await scenario.requests()).filter((entry) => entry.method === 'PATCH')
  expect(patches.map((entry) => entry.query.from)).toEqual([BEFORE])
})
