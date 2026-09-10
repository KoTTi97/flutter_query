// Talks to the express backend directly — to set a test up (a task of its
// own, so tests do not depend on the seed data or on each other) and to check
// afterwards what the backend really holds.
import type { APIRequestContext, Page, Request } from '@playwright/test'

export const BACKEND = 'http://localhost:5174/api'

export type Task = {
  id: string
  name: string
  reminder: boolean
  reminderPending: boolean
  reminderTarget: boolean | null
}

let counter = 0

/// A name no other test and no earlier run can have produced.
export const uniqueName = (prefix: string) =>
  `${prefix} ${Date.now().toString(36)}${(counter++).toString(36)}`

export async function createTask(request: APIRequestContext, name: string): Promise<Task> {
  const response = await request.post(`${BACKEND}/tasks`, { data: { name, project: 'Inbox' } })
  if (!response.ok()) throw new Error(`create failed: ${response.status()}`)
  return (await response.json()) as Task
}

export async function getTask(request: APIRequestContext, id: string): Promise<Task | null> {
  const response = await request.get(`${BACKEND}/tasks/${id}`)
  return response.ok() ? ((await response.json()) as Task) : null
}

/// Counts the backend requests the app makes, so a test can say "one list
/// fetch, no per-task fetch" — the cache policy, observed at the wire.
export function requestCounter(page: Page) {
  const seen: Request[] = []
  page.on('request', (request) => {
    if (request.url().startsWith(BACKEND)) seen.push(request)
  })
  const count = (method: string, path: RegExp) =>
    seen.filter((request) => request.method() === method && path.test(new URL(request.url()).pathname)).length
  return {
    lists: () => count('GET', /^\/api\/tasks$/),
    details: () => count('GET', /^\/api\/tasks\/[^/]+$/),
    reset: () => seen.splice(0, seen.length),
  }
}

/// Deletes every task a test created — the names carry the `uniqueName`
/// suffix — so a reused local backend does not fill up run after run. The
/// backend refuses every second delete, so each is tried twice.
export async function sweepTestTasks(request: APIRequestContext) {
  const response = await request.get(`${BACKEND}/tasks`)
  const { tasks } = (await response.json()) as { tasks: Task[] }
  for (const task of tasks.filter((s) => / [0-9a-z]{7,}$/.test(s.name))) {
    for (let attempt = 0; attempt < 2 && (await getTask(request, task.id)); attempt++) {
      await request.delete(`${BACKEND}/tasks/${task.id}`)
    }
  }
}
