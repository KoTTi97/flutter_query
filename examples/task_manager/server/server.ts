// The dummy backend as a standalone express server — plain HTTP, plain JSON.
// The API is the contract, documented by the route table below; the client
// types it by hand. Errors are `{ message }` JSON with a meaningful status.
//
//   GET    /api/tasks?search=&project=  → TaskListResponse
//   GET    /api/tasks/:id               → Task
//   POST   /api/tasks                   → Task   body: { name, project?, priority? }
//   PUT    /api/tasks/:id/name          → Task   body: { name }
//   PUT    /api/tasks/:id/reminder      → Task   body: { value }
//   DELETE /api/tasks/:id               → { id }

import express from 'express'
import { CONFIRM_AFTER, DETAIL_LATENCY, LIST_LATENCY, PORT, sleep, WRITE_LATENCY } from './config.ts'
import { db } from './db.ts'
import type { Priority, Task, TaskListResponse } from './types.ts'

const app = express()
app.use(express.json())

// Open CORS, so the Flutter web build and any other host can talk to it
// without a proxy. A Flutter web build has no dev server to proxy through.
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

const PRIORITIES: Priority[] = ['low', 'normal', 'high']

class HttpError extends Error {
  status: number
  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

const requireTask = (id: string): Task => {
  const task = db.find(id)
  if (!task) throw new HttpError(404, 'Task not found')
  return task
}

const requireName = (body: unknown): string => {
  const name = (body as { name?: unknown } | undefined)?.name
  if (typeof name !== 'string' || name.trim() === '') {
    throw new HttpError(400, 'Field "name" is missing or empty')
  }
  return name
}

let removeAttempts = 0

app.get('/api/tasks', async (req, res) => {
  await sleep(LIST_LATENCY)
  const search = String(req.query.search ?? '')
    .trim()
    .toLowerCase()
  const project = String(req.query.project ?? 'all')
  const tasks = db
    .all()
    .filter(
      (task) =>
        (!search || task.name.toLowerCase().includes(search)) &&
        (project === 'all' || task.project === project),
    )
  const response: TaskListResponse = { tasks, fetchedAt: new Date().toISOString() }
  res.json(response)
})

app.get('/api/tasks/:id', async (req, res) => {
  await sleep(DETAIL_LATENCY)
  res.json(requireTask(req.params.id))
})

app.post('/api/tasks', async (req, res) => {
  await sleep(WRITE_LATENCY)
  const name = requireName(req.body)
  const body = req.body as { project?: unknown; priority?: unknown }
  const priority = PRIORITIES.includes(body.priority as Priority)
    ? (body.priority as Priority)
    : 'normal'
  const project = typeof body.project === 'string' ? body.project : undefined
  res.status(201).json(db.create(name, priority, project))
})

// Name "fail" makes the write reject, so the optimistic-update rollback is
// demonstrable on demand.
app.put('/api/tasks/:id/name', async (req, res) => {
  await sleep(WRITE_LATENCY)
  const task = requireTask(req.params.id)
  const name = requireName(req.body)
  if (name.trim().toLowerCase() === 'fail') {
    throw new HttpError(500, 'The server refused the write')
  }
  task.name = name
  res.json(task)
})

// Accepted-pending write: responds immediately with the target recorded, but
// the confirmed value only flips once the reminder scheduler has taken it. The
// client polls the detail endpoint until pending clears.
app.put('/api/tasks/:id/reminder', async (req, res) => {
  await sleep(WRITE_LATENCY)
  const task = requireTask(req.params.id)
  const value = (req.body as { value?: unknown } | undefined)?.value
  if (typeof value !== 'boolean') {
    throw new HttpError(400, 'Field "value" is missing or not a boolean')
  }

  task.reminderPending = true
  task.reminderTarget = value
  setTimeout(() => {
    task.reminder = value
    task.reminderTarget = null
    task.reminderPending = false
  }, CONFIRM_AFTER)

  res.json(task)
})

// Every second delete fails, odd attempts first: the first click on any row
// shows the optimistic removal spring back with an error, and the retry on the
// same row goes through. Deterministic, so the demo needs no magic names.
app.delete('/api/tasks/:id', async (req, res) => {
  await sleep(WRITE_LATENCY)
  requireTask(req.params.id)
  removeAttempts += 1
  if (removeAttempts % 2 === 1) {
    throw new HttpError(500, 'The server refused the delete — try again')
  }
  db.remove(req.params.id)
  res.json({ id: req.params.id })
})

// Express 5 routes rejected promises here; HttpError carries its status, and
// anything else is a genuine 500.
app.use(
  (error: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
    const status = error instanceof HttpError ? error.status : 500
    const message = error instanceof Error ? error.message : 'Unknown error'
    res.status(status).json({ message })
  },
)

app.listen(PORT, () => {
  console.log(`Dummy backend listening on http://localhost:${PORT}`)
})
