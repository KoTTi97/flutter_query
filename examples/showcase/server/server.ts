// The showcase's dummy backend: plain HTTP, plain JSON, one in-memory world
// per scenario. It exists so every feature screen has something to talk to
// and every end-to-end test can script the failures it wants to see.
//
// The API is the contract, documented by the route table below; the Flutter
// app types it by hand (`lib/shared/models.dart`) and its widget tests fake it
// route for route (`test/fake_backend.dart`). Errors are `{ message }` JSON
// with a meaningful status.
//
//   GET    /api/posts                   → Post[]
//   GET    /api/posts/:id               → Post
//   GET    /api/posts/:id/comments      → Comment[]
//   GET    /api/search?q=               → Post[]
//   GET    /api/todos                   → Todo[]
//   POST   /api/todos                   → Todo (201)      body: { text }
//   PATCH  /api/todos/:id               → Todo            body: { text?, done? }
//   DELETE /api/todos/:id               → { id }
//   GET    /api/projects?page=&size=    → { projects, page, hasMore }
//   GET    /api/projects?cursor=&limit= → { items, nextId, previousId }
//   GET    /api/ticks                   → Tick[]
//   POST   /api/ticks                   → Tick (201)
//   DELETE /api/ticks                   → { cleared }
//   GET    /api/time                    → { now, serial }
//   GET    /api/counter                 → { value }
//   POST   /api/counter/increment       → { value }       body: { by? }
//
// Scenarios. Every request carries `x-scenario: <id>` (or lands in `default`).
// Each id is its own world, seeded from seed.json on first contact:
//
//   POST   /api/__scenario/:id/reset    → { id }          reseed everything
//   POST   /api/__scenario/:id/config   → ScenarioConfig  body: { latency?, errorRate?, failNext? }
//   GET    /api/__scenario/:id/requests → LogEntry[]      every request answered so far
//   DELETE /api/__scenario/:id/requests → { cleared }
//
// Faults, applied to every resource route in this order: the scenario's
// `latency`, then `?delay=ms` on top, then `?fail=<status>` (the request asks
// to be refused), then the scenario's `failNext` scripts, then its `errorRate`.

import express from 'express'
import { PORT, sleep } from './config.ts'
import { HttpError, registerRoutes } from './routes.ts'
import { scenarioFor } from './scenarios.ts'
import type { FailNext, LogEntry, ScenarioConfig } from './types.ts'

const app = express()
app.use(express.json())

// Open CORS, so the Flutter web build can talk to it from any origin. The
// `x-scenario` header makes every request preflighted; the max-age keeps that
// to one OPTIONS per origin and route, not one per request.
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*')
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PATCH, PUT, DELETE, OPTIONS')
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, x-scenario')
  res.setHeader('Access-Control-Max-Age', '600')
  if (req.method === 'OPTIONS') {
    res.sendStatus(204)
    return
  }
  next()
})

// Control routes come first: they are never delayed, failed or logged.
app.post('/api/__scenario/:id/reset', (req, res) => {
  scenarioFor(req.params.id).reset()
  res.json({ id: req.params.id })
})

const isFailNext = (value: unknown): value is FailNext => {
  const candidate = value as Partial<FailNext> | null
  return (
    typeof candidate === 'object' &&
    candidate !== null &&
    typeof candidate.method === 'string' &&
    typeof candidate.path === 'string' &&
    typeof candidate.count === 'number' &&
    typeof candidate.status === 'number'
  )
}

app.post('/api/__scenario/:id/config', (req, res) => {
  const scenario = scenarioFor(req.params.id)
  const body = (req.body ?? {}) as Partial<ScenarioConfig>
  if (body.latency !== undefined) {
    if (typeof body.latency !== 'number' || body.latency < 0) throw new HttpError(400, 'latency: milliseconds ≥ 0')
    scenario.config.latency = body.latency
  }
  if (body.errorRate !== undefined) {
    if (typeof body.errorRate !== 'number' || body.errorRate < 0 || body.errorRate > 1) {
      throw new HttpError(400, 'errorRate: a number between 0 and 1')
    }
    scenario.config.errorRate = body.errorRate
  }
  if (body.failNext !== undefined) {
    if (!Array.isArray(body.failNext) || !body.failNext.every(isFailNext)) {
      throw new HttpError(400, 'failNext: a list of { method, path, count, status, message? }')
    }
    scenario.config.failNext = body.failNext.map((entry) => ({ ...entry, method: entry.method.toUpperCase() }))
  }
  res.json(scenario.config)
})

app.get('/api/__scenario/:id/requests', (req, res) => {
  res.json(scenarioFor(req.params.id).log)
})

app.delete('/api/__scenario/:id/requests', (req, res) => {
  const scenario = scenarioFor(req.params.id)
  const cleared = scenario.log.length
  scenario.log = []
  res.json({ cleared })
})

const matchesPath = (pattern: string, path: string) =>
  pattern.endsWith('*') ? path.startsWith(pattern.slice(0, -1)) : pattern === path

// Every resource request: resolve the world, log it when it is answered, then
// run the fault chain. Express 5 forwards a rejected promise from here to the
// error handler, which is what makes `throw` inside async middleware work.
app.use('/api', async (req, res, next) => {
  const scenario = scenarioFor(String(req.get('x-scenario') ?? 'default'))
  res.locals.scenario = scenario
  const path = req.baseUrl + req.path

  const query: Record<string, string> = {}
  for (const [key, value] of Object.entries(req.query)) {
    if (typeof value === 'string') query[key] = value
  }
  res.on('finish', () => {
    const entry: LogEntry = { method: req.method, path, query, at: new Date().toISOString(), status: res.statusCode }
    scenario.log.push(entry)
  })

  const delay = Number(req.query.delay ?? 0)
  const wait = scenario.config.latency + (Number.isFinite(delay) && delay > 0 ? delay : 0)
  if (wait > 0) await sleep(wait)

  if (req.query.fail !== undefined) {
    const status = Number(req.query.fail)
    throw new HttpError(Number.isFinite(status) && status >= 400 ? status : 500, `Requested: ${req.query.fail}`)
  }

  const scripted = scenario.config.failNext.find(
    (entry) => entry.count > 0 && entry.method === req.method && matchesPath(entry.path, path),
  )
  if (scripted) {
    scripted.count -= 1
    throw new HttpError(scripted.status, scripted.message ?? `Scripted failure ${scripted.status}`)
  }

  if (scenario.config.errorRate > 0 && scenario.random() < scenario.config.errorRate) {
    throw new HttpError(500, 'Failed at random (errorRate)')
  }

  next()
})

registerRoutes(app)

app.use('/api', (req, _res) => {
  throw new HttpError(404, `Unknown route ${req.method} ${req.baseUrl}${req.path}`)
})

// HttpError carries its status; anything else is a genuine 500.
app.use((error: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  const status = error instanceof HttpError ? error.status : 500
  const message = error instanceof Error ? error.message : 'Unknown error'
  res.status(status).json({ message })
})

app.listen(PORT, () => {
  console.log(`Showcase backend listening on http://localhost:${PORT}`)
})
