// The resource routes, in the order the Flutter fake backend
// (`examples/showcase/test/fake_backend.dart`) lists them, so the two files
// diff by eye. Every handler reads its world from `res.locals.scenario`, which
// the fault middleware in `server.ts` has already resolved, delayed and
// possibly failed.

import type express from 'express'
import type { Scenario } from './scenarios.ts'
import type { Comment, Post, Todo } from './types.ts'

export class HttpError extends Error {
  status: number
  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

const world = (res: express.Response): Scenario => res.locals.scenario as Scenario

const intParam = (value: unknown, fallback: number): number => {
  const parsed = Number.parseInt(String(value ?? ''), 10)
  return Number.isFinite(parsed) ? parsed : fallback
}

const requirePost = (scenario: Scenario, id: string): Post => {
  const post = scenario.posts.find((candidate) => candidate.id === Number(id))
  if (!post) throw new HttpError(404, 'Post not found')
  return post
}

const requireTodo = (scenario: Scenario, id: string): Todo => {
  const todo = scenario.todos.find((candidate) => candidate.id === Number(id))
  if (!todo) throw new HttpError(404, 'Todo not found')
  return todo
}

const requireText = (body: unknown): string => {
  const text = (body as { text?: unknown } | undefined)?.text
  if (typeof text !== 'string' || text.trim() === '') {
    throw new HttpError(400, 'Field "text" is missing or empty')
  }
  return text.trim()
}

export const registerRoutes = (app: express.Express) => {
  // Posts and comments — read-only content for the reading screens.
  app.get('/api/posts', (_req, res) => {
    res.json(world(res).posts)
  })

  app.get('/api/posts/:id', (req, res) => {
    res.json(requirePost(world(res), req.params.id))
  })

  app.get('/api/posts/:id/comments', (req, res) => {
    const scenario = world(res)
    const post = requirePost(scenario, req.params.id)
    const comments: Comment[] = scenario.comments.filter((comment) => comment.postId === post.id)
    res.json(comments)
  })

  // Search over post titles; an empty query is an empty result, not everything.
  app.get('/api/search', (req, res) => {
    const needle = String(req.query.q ?? '')
      .trim()
      .toLowerCase()
    res.json(needle === '' ? [] : world(res).posts.filter((post) => post.title.toLowerCase().includes(needle)))
  })

  // Todos — the writable resource for mutations and optimistic updates.
  app.get('/api/todos', (_req, res) => {
    res.json(world(res).todos)
  })

  app.post('/api/todos', (req, res) => {
    const scenario = world(res)
    const todo: Todo = { id: scenario.nextTodoId++, text: requireText(req.body), done: false }
    scenario.todos.push(todo)
    res.status(201).json(todo)
  })

  app.patch('/api/todos/:id', (req, res) => {
    const todo = requireTodo(world(res), req.params.id)
    const body = (req.body ?? {}) as { text?: unknown; done?: unknown }
    if (body.text !== undefined) todo.text = requireText(body)
    if (body.done !== undefined) {
      if (typeof body.done !== 'boolean') throw new HttpError(400, 'Field "done" is not a boolean')
      todo.done = body.done
    }
    res.json(todo)
  })

  app.delete('/api/todos/:id', (req, res) => {
    const scenario = world(res)
    const todo = requireTodo(scenario, req.params.id)
    scenario.todos = scenario.todos.filter((candidate) => candidate.id !== todo.id)
    res.json({ id: todo.id })
  })

  // Projects, in two shapes: page-numbered (upstream's `pagination` example)
  // and cursor-based with ids in both directions (upstream's
  // `infinite-query-with-max-pages`). Ids run from 0 to projectCount - 1.
  app.get('/api/projects', (req, res) => {
    const scenario = world(res)
    const count = scenario.projectCount
    if (req.query.cursor !== undefined) {
      const cursor = Math.max(0, intParam(req.query.cursor, 0))
      const limit = Math.max(1, intParam(req.query.limit, 10))
      const ids = Array.from({ length: Math.min(limit, count - cursor) }, (_, i) => cursor + i)
      res.json({
        items: ids.map((id) => scenario.project(id)),
        nextId: cursor + limit < count ? cursor + limit : null,
        previousId: cursor > 0 ? Math.max(0, cursor - limit) : null,
      })
      return
    }
    const page = Math.max(0, intParam(req.query.page, 0))
    const size = Math.max(1, intParam(req.query.size, 10))
    const start = page * size
    const ids = Array.from({ length: Math.max(0, Math.min(size, count - start)) }, (_, i) => start + i)
    res.json({
      projects: ids.map((id) => scenario.project(id)),
      page,
      hasMore: start + size < count,
    })
  })

  // Ticks — a list that grows while a screen polls it (upstream's
  // `auto-refetching`).
  app.get('/api/ticks', (_req, res) => {
    res.json(world(res).ticks)
  })

  app.post('/api/ticks', (_req, res) => {
    const scenario = world(res)
    const tick = { id: scenario.nextTickId++, at: new Date().toISOString() }
    scenario.ticks.push(tick)
    res.status(201).json(tick)
  })

  app.delete('/api/ticks', (_req, res) => {
    const scenario = world(res)
    const cleared = scenario.ticks.length
    scenario.ticks = []
    res.json({ cleared })
  })

  // Time — every call answers a new serial, so a screen can show that a
  // refetch happened without anyone comparing timestamps.
  app.get('/api/time', (_req, res) => {
    const scenario = world(res)
    scenario.serial += 1
    res.json({ now: new Date().toISOString(), serial: scenario.serial })
  })

  // Counter — the smallest possible write, for mutation scopes and retries.
  app.get('/api/counter', (_req, res) => {
    res.json({ value: world(res).counter })
  })

  app.post('/api/counter/increment', (req, res) => {
    const scenario = world(res)
    const by = (req.body as { by?: unknown } | undefined)?.by
    scenario.counter += typeof by === 'number' ? by : 1
    res.json({ value: scenario.counter })
  })
}
