// Talks to the express gateway directly — to set a test up (a sensor of its
// own, so tests do not depend on the seed data or on each other) and to check
// afterwards what the gateway really holds.
import type { APIRequestContext, Page, Request } from '@playwright/test'

export const GATEWAY = 'http://localhost:5174/api'

export type Sensor = {
  id: string
  name: string
  matterForwarding: boolean
  matterForwardingPending: boolean
  matterForwardingTarget: boolean | null
}

let counter = 0

/// A name no other test and no earlier run can have produced.
export const uniqueName = (prefix: string) =>
  `${prefix} ${Date.now().toString(36)}${(counter++).toString(36)}`

export async function createSensor(request: APIRequestContext, name: string): Promise<Sensor> {
  const response = await request.post(`${GATEWAY}/sensors`, { data: { name, room: 'Flur' } })
  if (!response.ok()) throw new Error(`create failed: ${response.status()}`)
  return (await response.json()) as Sensor
}

export async function getSensor(request: APIRequestContext, id: string): Promise<Sensor | null> {
  const response = await request.get(`${GATEWAY}/sensors/${id}`)
  return response.ok() ? ((await response.json()) as Sensor) : null
}

/// Counts the gateway requests the app makes, so a test can say "one list
/// fetch, no per-sensor fetch" — the cache policy, observed at the wire.
export function requestCounter(page: Page) {
  const seen: Request[] = []
  page.on('request', (request) => {
    if (request.url().startsWith(GATEWAY)) seen.push(request)
  })
  const count = (method: string, path: RegExp) =>
    seen.filter((request) => request.method() === method && path.test(new URL(request.url()).pathname)).length
  return {
    lists: () => count('GET', /^\/api\/sensors$/),
    details: () => count('GET', /^\/api\/sensors\/[^/]+$/),
    reset: () => seen.splice(0, seen.length),
  }
}

/// Deletes every sensor a test created — the names carry the `uniqueName`
/// suffix — so a reused local gateway does not fill up run after run. The
/// gateway refuses every second delete, so each is tried twice.
export async function sweepTestSensors(request: APIRequestContext) {
  const response = await request.get(`${GATEWAY}/sensors`)
  const { sensors } = (await response.json()) as { sensors: Sensor[] }
  for (const sensor of sensors.filter((s) => / [0-9a-z]{7,}$/.test(s.name))) {
    for (let attempt = 0; attempt < 2 && (await getSensor(request, sensor.id)); attempt++) {
      await request.delete(`${GATEWAY}/sensors/${sensor.id}`)
    }
  }
}
