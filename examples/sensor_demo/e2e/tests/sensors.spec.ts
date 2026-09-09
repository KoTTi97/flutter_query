// End-to-end: the real web build in a real Chromium, against the real express
// gateway. What the widget tests cannot see — the browser's HTTP stack, real
// timers, the wire — is exactly what these assert on.
//
// Flutter web paints to a canvas; the tests read the semantics tree the E2E
// build switches on (`--dart-define=E2E=true`), the same tree a screen reader
// gets: rows are groups named after the sensor, buttons carry their tooltips.
import { expect, test, type Page } from '@playwright/test'
import { createSensor, getSensor, requestCounter, sweepTestSensors, uniqueName } from './gateway'

// The list builds only the rows in view, and a created sensor lands at the
// end of it — so the leftovers of earlier runs are cleared away, and the
// viewport is tall enough for the seed rows plus a test's own.
test.beforeAll(async ({ request }) => sweepTestSensors(request))
test.afterAll(async ({ request }) => sweepTestSensors(request))
test.use({ viewport: { width: 1280, height: 1600 } })

const open = async (page: Page) => {
  await page.goto('/')
  // The toolbar is up as soon as the app has booted; the rows come after the
  // gateway's ~900 ms.
  await expect(page.getByRole('button', { name: 'Sensor anlegen', exact: true })).toBeVisible()
}

const row = (page: Page, name: string) => page.getByRole('group', { name })
const deleteButton = (page: Page, name: string) => page.getByRole('button', { name: `${name} löschen` })
const heroTitle = (page: Page) => page.getByText(/Kontakt · Flur/)

// Holds every rename write in the browser until `release()`, so an assertion
// between the click and the release runs while the gateway provably has not
// answered. After the release the handler is a passthrough, so the rest of the
// test talks to the gateway normally — unrouting it here would race the
// handler that is still letting the held request go.
function holdWrite(page: Page) {
  let letGo: () => void = () => {}
  const held = new Promise<void>((resolve) => {
    letGo = resolve
  })
  const routed = page.route('**/api/sensors/*/name', async (route) => {
    await held
    await route.continue()
  })
  return {
    async release() {
      await routed
      letGo()
    },
  }
}

test('loads the sensors from the gateway, one request for the whole screen', async ({ page, request }) => {
  const sensor = await createSensor(request, uniqueName('Erste Ladung'))
  const requests = requestCounter(page)

  await open(page)
  await expect(row(page, sensor.name)).toBeVisible()
  await expect(page.getByText(/\d+ von \d+ verbunden/)).toBeVisible()

  // Header badge, list and every row render from one list response: the
  // header selects from the same cache entry, and the list's query function
  // seeds each per-sensor entry, so no row fetches on its own.
  await page.waitForTimeout(1500)
  expect(requests.lists()).toBe(1)
  expect(requests.details()).toBe(0)
})

test('opening a sensor and coming back costs no request while the data is fresh', async ({ page, request }) => {
  const sensor = await createSensor(request, uniqueName('Frisch'))
  await open(page)
  await expect(row(page, sensor.name)).toBeVisible()
  const requests = requestCounter(page)

  await row(page, sensor.name).click()
  await expect(heroTitle(page)).toContainText(sensor.name)
  await page.getByRole('button', { name: 'Back', exact: true }).click()
  await expect(row(page, sensor.name)).toBeVisible()

  await page.waitForTimeout(1000)
  expect(requests.details()).toBe(0)
  expect(requests.lists()).toBe(0)
})

test('the refresh button refetches without dropping the rows', async ({ page, request }) => {
  const sensor = await createSensor(request, uniqueName('Aktualisiert'))
  await open(page)
  await expect(row(page, sensor.name)).toBeVisible()

  const refetch = page.waitForRequest((r) => r.method() === 'GET' && /\/api\/sensors$/.test(new URL(r.url()).pathname))
  await page.getByRole('button', { name: 'Neu laden', exact: true }).click()
  await refetch
  // Refetching, not loading: the rows stay while the request is out.
  await expect(row(page, sensor.name)).toBeVisible()
  await expect(page.getByRole('button', { name: 'Neu laden', exact: true })).not.toHaveAttribute('aria-disabled', 'true', { timeout: 10_000 })
})

test('renames optimistically and the gateway keeps the name', async ({ page, request }) => {
  const sensor = await createSensor(request, uniqueName('Vorher'))
  const newName = uniqueName('Nachher')
  await open(page)
  await row(page, sensor.name).click()

  // The semantic input mirrors the field's text once it has focus, and a
  // click is what focuses it — the same as for a user.
  const field = page.getByRole('textbox', { name: /^Name/ })
  await field.click()
  await expect(field).toHaveValue(sensor.name)
  await field.fill(newName)

  // Hold the write at the network layer, so "optimistic" is proven by
  // construction: the gateway has provably not answered while we assert. A
  // wall-clock budget instead would be a guess about how fast the browser
  // repaints and republishes its semantics tree, which is what a busy machine
  // makes flaky.
  const write = holdWrite(page)
  await page.getByRole('button', { name: 'Umbenennen', exact: true }).click()
  await expect(heroTitle(page)).toContainText(newName)
  await write.release()

  // And still there once the write has gone through.
  await expect(page.getByRole('button', { name: 'Umbenennen', exact: true })).not.toHaveAttribute('aria-disabled', 'true', { timeout: 10_000 })
  await expect(heroTitle(page)).toContainText(newName)
  expect((await getSensor(request, sensor.id))?.name).toBe(newName)

  // The overview row reads the same per-sensor query, so it agrees without a
  // list refetch; and a fresh page load agrees because the gateway does.
  await page.getByRole('button', { name: 'Back', exact: true }).click()
  await expect(row(page, newName)).toBeVisible()
  await page.reload()
  await expect(row(page, newName)).toBeVisible()
})

test('a refused rename rolls back on screen and in the field', async ({ page, request }) => {
  const sensor = await createSensor(request, uniqueName('Bleibt'))
  await open(page)
  await row(page, sensor.name).click()

  const field = page.getByRole('textbox', { name: /^Name/ })
  await field.click()
  await expect(field).toHaveValue(sensor.name)
  await field.fill('fail')

  // Same as the rename above: the rejected name has to be on screen while the
  // gateway still owes an answer, so the write is held until we have seen it.
  const write = holdWrite(page)
  await page.getByRole('button', { name: 'Umbenennen', exact: true }).click()
  await expect(heroTitle(page)).toContainText('fail')
  await write.release()

  await expect(page.getByText('Gateway hat den Schreibvorgang abgelehnt')).toBeVisible()
  await expect(heroTitle(page)).toContainText(sensor.name)
  await field.click()
  await expect(field).toHaveValue(sensor.name)
  expect((await getSensor(request, sensor.id))?.name).toBe(sensor.name)
})

test('the Matter switch flips at once, waits for the device, then settles', async ({ page, request }) => {
  const sensor = await createSensor(request, uniqueName('Matter'))
  await open(page)
  await row(page, sensor.name).click()
  const requests = requestCounter(page)

  const matter = page.getByRole('switch')
  await expect(matter).toHaveAttribute('aria-checked', 'false')
  await matter.click()
  // Optimistic: the requested value shows before the write is accepted.
  await expect(matter).toHaveAttribute('aria-checked', 'true', { timeout: 300 })

  // Accepted, not confirmed: the gateway answers with `pending`, the switch
  // is locked for the confirmation window, and the app polls the sensor.
  await expect(page.getByRole('switch', { name: /Wird vom Gerät bestätigt/ })).toBeVisible()
  await expect(matter).toHaveAttribute('aria-disabled', 'true')
  await expect.poll(() => requests.details(), { timeout: 3000 }).toBeGreaterThan(0)

  // The device confirms after ~3 s: the poll stops, the switch unlocks, and
  // the value it shows is the one the gateway now holds.
  await expect(page.getByRole('switch', { name: /Bestätigter Gerätezustand/ })).toBeVisible({ timeout: 10_000 })
  await expect(matter).toHaveAttribute('aria-checked', 'true')
  await expect(matter).not.toHaveAttribute('aria-disabled', 'true')
  const polls = requests.details()
  await page.waitForTimeout(1500)
  expect(requests.details()).toBe(polls)
  const confirmed = await getSensor(request, sensor.id)
  expect(confirmed?.matterForwarding).toBe(true)
  expect(confirmed?.matterForwardingPending).toBe(false)

  // The overview row shows the confirmed state from the same cache entry.
  await page.getByRole('button', { name: 'Back', exact: true }).click()
  await expect(row(page, sensor.name)).toContainText('Matter')
})

test('a refused delete springs back with a notice; the retry goes through', async ({ page, request }) => {
  // The gateway refuses every second delete, counting across the whole run.
  // Whatever the count stands at, deleting `first` until it is gone ends on
  // a success — so `second`'s first attempt is the refused one, on purpose.
  const first = await createSensor(request, uniqueName('Erster'))
  const second = await createSensor(request, uniqueName('Zweiter'))
  await open(page)
  await expect(row(page, second.name)).toBeVisible()

  for (let attempt = 0; attempt < 2 && (await getSensor(request, first.id)); attempt++) {
    await deleteButton(page, first.name).click()
    await expect(row(page, first.name)).toBeHidden({ timeout: 300 })
    await expect
      .poll(async () => (await getSensor(request, first.id)) === null || (await row(page, first.name).isVisible()), {
        timeout: 5000,
      })
      .toBe(true)
  }
  expect(await getSensor(request, first.id)).toBeNull()

  await deleteButton(page, second.name).click()
  // Optimistically gone …
  await expect(row(page, second.name)).toBeHidden({ timeout: 300 })
  // … and back, with the gateway's own words.
  await expect(page.getByText('Gateway hat das Löschen abgelehnt — nochmal versuchen')).toBeVisible()
  await expect(row(page, second.name)).toBeVisible()
  expect(await getSensor(request, second.id)).not.toBeNull()

  await deleteButton(page, second.name).click()
  await expect(row(page, second.name)).toBeHidden()
  await expect.poll(() => getSensor(request, second.id)).toBeNull()
  await page.reload()
  await expect(row(page, second.name)).toBeHidden()
})

test('searching narrows the list through the gateway, once per pause in typing', async ({ page, request }) => {
  const needle = uniqueName('Nadel')
  const sensor = await createSensor(request, needle)
  await open(page)
  await expect(row(page, sensor.name)).toBeVisible()
  const requests = requestCounter(page)

  const searched = page.waitForRequest((r) => new URL(r.url()).searchParams.get('search') === needle)
  const search = page.getByRole('textbox', { name: 'Sensoren durchsuchen…' })
  await search.click()
  await search.fill(needle)
  await searched
  await expect(row(page, sensor.name)).toBeVisible()
  await expect(page.getByRole('button', { name: /löschen$/ })).toHaveCount(1)
  // Debounced: one request for the whole word, not one per keystroke.
  expect(requests.lists()).toBe(1)
})

test('an unreachable gateway shows the error panel after one retry, and recovers', async ({ page, request }) => {
  const sensor = await createSensor(request, uniqueName('Wieder da'))
  let attempts = 0
  await page.route('**/api/sensors?*', (route) => {
    attempts++
    return route.abort('connectionrefused')
  })

  await open(page)
  // The panel's texts merge into its group's accessible name.
  await expect(page.getByRole('group', { name: /Läuft das Gateway auf Port 5174\?/ })).toBeVisible({ timeout: 15_000 })
  await expect(page.getByText('Gateway offline')).toBeVisible()
  // `retry: 1` in the demo's client defaults: the first attempt and one
  // retry, not upstream's three.
  expect(attempts).toBe(2)

  await page.unroute('**/api/sensors?*')
  await page.getByRole('button', { name: 'Nochmal versuchen', exact: true }).click()
  await expect(row(page, sensor.name)).toBeVisible()
  await expect(page.getByText(/\d+ von \d+ verbunden/)).toBeVisible()
})
