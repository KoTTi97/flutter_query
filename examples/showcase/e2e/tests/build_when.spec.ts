// The `build-when` screen in a real browser, against the real backend.
//
// Every assertion here is a *delta* of a build counter, never an absolute:
// what the screen is about is the difference the predicate makes between the
// two halves of a pair, and a count from the moment the page opened would also
// be counting how many frames the first fetch happened to take. The requests
// are held in the browser (`holdRequest`) so the flip to fetching and the
// landing are two separate moments — a notification that reached the same
// frame as the one before it would be one rebuild, and then there would be
// nothing to filter.
import { expect, fact, factIn, group, holdRequest, test, type Page } from './fixtures'

// Five cards, two strips and sixteen readers: taller than the default 720,
// and the list that holds them is lazy — without this the mutation card is
// never built and nothing below the query card exists to assert on. The same
// reason the widget tests set a tall window (`tall(tester)`), and local to
// this file.
test.use({ viewport: { width: 1280, height: 2400 } })

const queryMembers = ['watchQuery', 'context.query', 'watchSelectQuery', 'context.selectQuery'] as const
const infiniteMembers = ['watchInfiniteQuery', 'context.infiniteQuery'] as const
const mutationMembers = ['watchMutation', 'context.mutation'] as const

type Member = (typeof queryMembers)[number] | (typeof infiniteMembers)[number] | (typeof mutationMembers)[number]

/// One reader's group: `reader watchQuery filtered`, the way a strip is
/// `debug posts`.
const readerName = (member: Member, filtered: boolean) => `reader ${member} ${filtered ? 'filtered' : 'plain'}`

const readerFact = (page: Page, member: Member, filtered: boolean, text: string) =>
  factIn(page, readerName(member, filtered), text)

/// One reader's build counter, off its exact `builds=<n>` text.
async function builds(page: Page, member: Member, filtered: boolean): Promise<number> {
  const text = await group(page, readerName(member, filtered))
    .getByText(/^builds=\d+$/)
    .textContent()
  return Number(text!.slice('builds='.length))
}

type Pair = { filtered: number; plain: number }

async function snapshot(page: Page, members: readonly Member[]): Promise<Record<string, Pair>> {
  const result: Record<string, Pair> = {}
  for (const member of members) {
    result[member] = { filtered: await builds(page, member, true), plain: await builds(page, member, false) }
  }
  return result
}

/// Both halves of every pair moved by exactly what the predicate allows.
///
/// Asserted as a *text* rather than as a number read once, so the assertion
/// waits for the frame instead of racing it — and a counter that goes one
/// further than expected can never satisfy it, which is the half that matters
/// when the expectation is that it did not move at all. The plain half is
/// asked first for the same reason: it moves for everything, so its number
/// arriving is the frame the filtered half would have rebuilt in too.
async function expectMoved(
  page: Page,
  members: readonly Member[],
  before: Record<string, Pair>,
  moved: Pair,
) {
  for (const member of members) {
    await expect(
      readerFact(page, member, false, `builds=${before[member].plain + moved.plain}`),
      `${member} plain`,
    ).toBeVisible()
    await expect(
      readerFact(page, member, true, `builds=${before[member].filtered + moved.filtered}`),
      `${member} filtered`,
    ).toBeVisible()
  }
}

const button = (page: Page, name: string) => page.getByRole('button', { name, exact: true })

/// Moves the knob, and waits for it to have reached the readers.
///
/// Every filtered row prints the knob's word beside its member, so that text
/// appearing *is* the rebuild the knob caused. Nothing may read a counter
/// before it: the snapshot a delta is measured from would otherwise be the one
/// taken a frame too early.
async function pickFilter(page: Page, label: string) {
  await group(page, 'predicate').getByRole('radio', { name: label, exact: true }).click()
  for (const member of queryMembers) {
    await expect(
      group(page, readerName(member, true)).getByText(`${member} \u00b7 buildWhen ${label}`, { exact: true }),
      member,
    ).toBeVisible()
  }
}

/// Both entries have landed: one fetch each, and every reader is showing it.
async function loaded(page: Page) {
  await expect(fact(page, 'posts', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'posts', 'fetches=1')).toBeVisible()
  await expect(fact(page, 'pages', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'pages', 'fetches=1')).toBeVisible()
  for (const filtered of [true, false]) {
    await expect(readerFact(page, 'context.query', filtered, 'posts=30')).toBeVisible()
    await expect(readerFact(page, 'context.infiniteQuery', filtered, 'pages=1')).toBeVisible()
  }
}

test('sixteen readers, one request per entry', async ({ page, open, scenario }) => {
  await open('/build-when')
  await loaded(page)

  await expect(fact(page, 'posts', 'observers=8')).toBeVisible()
  await expect(fact(page, 'pages', 'observers=4')).toBeVisible()

  // Every one of the eight members is on screen twice, and read something.
  for (const filtered of [true, false]) {
    for (const member of ['watchQuery', 'context.query'] as const) {
      await expect(readerFact(page, member, filtered, 'posts=30')).toBeVisible()
    }
    for (const member of ['watchSelectQuery', 'context.selectQuery'] as const) {
      await expect(readerFact(page, member, filtered, 'count=30')).toBeVisible()
    }
    for (const member of infiniteMembers) {
      await expect(readerFact(page, member, filtered, 'pages=1')).toBeVisible()
    }
    for (const member of mutationMembers) {
      await expect(readerFact(page, member, filtered, 'status=idle')).toBeVisible()
    }
  }

  expect(await scenario.count('GET', /^\/api\/posts$/)).toBe(1)
  expect(await scenario.count('GET', /^\/api\/projects$/)).toBe(1)
})

test('a refetch with equal data moves only the plain half', async ({ page, open, scenario }) => {
  await open('/build-when')
  await loaded(page)
  const before = await snapshot(page, queryMembers)

  const hold = holdRequest(page, '**/api/posts*')
  await button(page, 'Refetch the posts').click()
  await expect(fact(page, 'posts', 'fetchStatus=fetching')).toBeVisible()
  // The flip is a changed result — `fetchStatus` is inside `==` — with
  // unchanged data, so the filtered half refuses it.
  await expectMoved(page, queryMembers, before, { filtered: 0, plain: 1 })
  await hold.release()

  await expect(fact(page, 'posts', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'posts', 'fetchStatus=idle')).toBeVisible()
  // And the landing, with a newer `dataUpdatedAt`, is the second.
  await expectMoved(page, queryMembers, before, { filtered: 0, plain: 2 })
  expect(await scenario.count('GET', /^\/api\/posts$/)).toBe(2)
})

test('dropping a post reaches every reader of the entry', async ({ page, open, scenario }) => {
  await open('/build-when')
  await loaded(page)
  const before = await snapshot(page, queryMembers)

  await button(page, 'Drop a post').click()
  await expect(readerFact(page, 'context.query', true, 'posts=29')).toBeVisible()
  await expect(readerFact(page, 'watchSelectQuery', true, 'count=29')).toBeVisible()

  // A write, not a fetch: the data moved, so the predicate says yes.
  await expectMoved(page, queryMembers, before, { filtered: 1, plain: 1 })
  expect(await scenario.count('GET', /^\/api\/posts$/)).toBe(1)
})

test('Load next is one build filtered and two plain', async ({ page, open, scenario }) => {
  await open('/build-when')
  await loaded(page)
  const before = await snapshot(page, infiniteMembers)

  const hold = holdRequest(page, '**/api/projects*')
  await button(page, 'Load next').click()
  await expect(fact(page, 'pages', 'fetchStatus=fetching')).toBeVisible()
  // The page fetch starting moves `fetchStatus` while the pages on screen are
  // still the pages the reader is showing.
  await expectMoved(page, infiniteMembers, before, { filtered: 0, plain: 1 })
  await hold.release()

  for (const member of infiniteMembers) {
    for (const filtered of [true, false]) {
      await expect(readerFact(page, member, filtered, 'pages=2')).toBeVisible()
    }
  }
  await expectMoved(page, infiniteMembers, before, { filtered: 1, plain: 2 })
  // One reader pages; the other three joined the same fetch.
  await expect(fact(page, 'pages', 'observers=4')).toBeVisible()
  expect(await scenario.count('GET', /^\/api\/projects$/)).toBe(2)
})

test('a mutation run is two builds filtered and three plain', async ({ page, open, scenario }) => {
  await open('/build-when')
  await loaded(page)
  const before = await snapshot(page, mutationMembers)

  const hold = holdRequest(page, '**/api/counter/increment*')
  await button(page, 'Run the mutation').click()
  for (const member of mutationMembers) {
    await expect(readerFact(page, member, false, 'status=pending')).toBeVisible()
    // `idle` to `pending` carries no data, and a mutation has no `select` to
    // filter with: the predicate is the only filter this reader has.
    await expect(readerFact(page, member, true, 'status=idle')).toBeVisible()
  }
  await expectMoved(page, mutationMembers, before, { filtered: 0, plain: 1 })
  await hold.release()

  for (const member of mutationMembers) {
    for (const filtered of [true, false]) {
      await expect(readerFact(page, member, filtered, 'status=success')).toBeVisible()
    }
  }
  await expectMoved(page, mutationMembers, before, { filtered: 1, plain: 2 })
  // Four readers, four mutations: one is never shared.
  expect(await scenario.count('POST', /^\/api\/counter\/increment$/)).toBe(4)
})

test('never freezes the filtered half, always makes it its twin', async ({ page, open, scenario }) => {
  await open('/build-when')
  await loaded(page)
  const opened = await snapshot(page, queryMembers)

  // The knob is a rebuild from above, which no predicate can refuse.
  await pickFilter(page, 'never')
  await expectMoved(page, queryMembers, opened, { filtered: 1, plain: 1 })
  const frozen = await snapshot(page, queryMembers)

  let hold = holdRequest(page, '**/api/posts*')
  await button(page, 'Refetch the posts').click()
  await expect(fact(page, 'posts', 'fetchStatus=fetching')).toBeVisible()
  await hold.release()
  await expect(fact(page, 'posts', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'posts', 'fetchStatus=idle')).toBeVisible()
  await expectMoved(page, queryMembers, frozen, { filtered: 0, plain: 2 })

  // `always` is no filter at all: from here the pair moves together.
  await pickFilter(page, 'always')
  const twinned = await snapshot(page, queryMembers)
  hold = holdRequest(page, '**/api/posts*')
  await button(page, 'Refetch the posts').click()
  await expect(fact(page, 'posts', 'fetchStatus=fetching')).toBeVisible()
  await hold.release()
  await expect(fact(page, 'posts', 'fetches=3')).toBeVisible()
  await expect(fact(page, 'posts', 'fetchStatus=idle')).toBeVisible()
  await expectMoved(page, queryMembers, twinned, { filtered: 2, plain: 2 })
  expect(await scenario.count('GET', /^\/api\/posts$/)).toBe(3)
})
