// The dummy gateway as a standalone express server — plain HTTP, plain JSON,
// no tRPC. It exists so more than one client can share it: the React demo
// proxies /api here through Vite, and the Flutter demo will call it directly.
//
// The API is the contract now, documented by the route table below; clients
// type it by hand. Errors are `{ message }` JSON with a meaningful status.
//
//   GET    /api/sensors?search=&room=          → SensorListResponse
//   GET    /api/sensors/:id                    → Sensor
//   POST   /api/sensors                        → Sensor        body: { name, room?, type? }
//   PUT    /api/sensors/:id/name               → Sensor        body: { name }
//   PUT    /api/sensors/:id/matter-forwarding  → Sensor        body: { value }
//   DELETE /api/sensors/:id                    → { id }

import express from 'express'
import { CONFIRM_AFTER, DETAIL_LATENCY, LIST_LATENCY, PORT, sleep, WRITE_LATENCY } from './config.ts'
import { db } from './db.ts'
import type { Sensor, SensorListResponse, SensorType } from './types.ts'

const app = express()
app.use(express.json())

// Open CORS, so the Flutter web build and any other host can talk to it
// without a proxy. The React dev server proxies same-origin anyway.
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*')
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, x-demo-client')
  if (req.method === 'OPTIONS') {
    res.sendStatus(204)
    return
  }
  next()
})

const SENSOR_TYPES: SensorType[] = ['contact', 'motion', 'temperature']

class HttpError extends Error {
  status: number
  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

const requireSensor = (id: string): Sensor => {
  const sensor = db.find(id)
  if (!sensor) throw new HttpError(404, 'Sensor nicht gefunden')
  return sensor
}

const requireName = (body: unknown): string => {
  const name = (body as { name?: unknown } | undefined)?.name
  if (typeof name !== 'string' || name.trim() === '') {
    throw new HttpError(400, 'Feld "name" fehlt oder ist leer')
  }
  return name
}

let removeAttempts = 0

app.get('/api/sensors', async (req, res) => {
  await sleep(LIST_LATENCY)
  const search = String(req.query.search ?? '')
    .trim()
    .toLowerCase()
  const room = String(req.query.room ?? 'all')
  const sensors = db
    .all()
    .filter(
      (sensor) =>
        (!search || sensor.name.toLowerCase().includes(search)) &&
        (room === 'all' || sensor.room === room),
    )
  const response: SensorListResponse = { sensors, fetchedAt: new Date().toISOString() }
  res.json(response)
})

app.get('/api/sensors/:id', async (req, res) => {
  await sleep(DETAIL_LATENCY)
  res.json(requireSensor(req.params.id))
})

app.post('/api/sensors', async (req, res) => {
  await sleep(WRITE_LATENCY)
  const name = requireName(req.body)
  const body = req.body as { room?: unknown; type?: unknown }
  const type = SENSOR_TYPES.includes(body.type as SensorType) ? (body.type as SensorType) : 'contact'
  const room = typeof body.room === 'string' ? body.room : undefined
  res.status(201).json(db.create(name, type, room))
})

// Name "fail" makes the write reject, so the optimistic-update rollback is
// demonstrable on demand.
app.put('/api/sensors/:id/name', async (req, res) => {
  await sleep(WRITE_LATENCY)
  const sensor = requireSensor(req.params.id)
  const name = requireName(req.body)
  if (name.trim().toLowerCase() === 'fail') {
    throw new HttpError(500, 'Gateway hat den Schreibvorgang abgelehnt')
  }
  sensor.name = name
  res.json(sensor)
})

// Accepted-pending write: responds immediately with the target recorded, but
// the confirmed value only flips once the device has applied it. The client
// polls the detail endpoint until pending clears.
app.put('/api/sensors/:id/matter-forwarding', async (req, res) => {
  await sleep(WRITE_LATENCY)
  const sensor = requireSensor(req.params.id)
  const value = (req.body as { value?: unknown } | undefined)?.value
  if (typeof value !== 'boolean') {
    throw new HttpError(400, 'Feld "value" fehlt oder ist kein Boolean')
  }

  sensor.matterForwardingPending = true
  sensor.matterForwardingTarget = value
  setTimeout(() => {
    sensor.matterForwarding = value
    sensor.matterForwardingTarget = null
    sensor.matterForwardingPending = false
  }, CONFIRM_AFTER)

  res.json(sensor)
})

// Every second delete fails, odd attempts first: the first click on any row
// shows the optimistic removal spring back with an error, and the retry on the
// same row goes through. Deterministic, so the demo needs no magic names.
app.delete('/api/sensors/:id', async (req, res) => {
  await sleep(WRITE_LATENCY)
  requireSensor(req.params.id)
  removeAttempts += 1
  if (removeAttempts % 2 === 1) {
    throw new HttpError(500, 'Gateway hat das Löschen abgelehnt — nochmal versuchen')
  }
  db.remove(req.params.id)
  res.json({ id: req.params.id })
})

// Express 5 routes rejected promises here; HttpError carries its status, and
// anything else is a genuine 500.
app.use(
  (error: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
    const status = error instanceof HttpError ? error.status : 500
    const message = error instanceof Error ? error.message : 'Unbekannter Fehler'
    res.status(status).json({ message })
  },
)

app.listen(PORT, () => {
  console.log(`Dummy gateway listening on http://localhost:${PORT}`)
})
