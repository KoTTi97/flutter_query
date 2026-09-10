// In-memory "database". Restarting the server resets everything.

import type { Priority, Task } from './types.ts'

let nextId = 1

const makeTask = (name: string, priority: Priority, extra: Partial<Task> = {}): Task => ({
  id: String(nextId++),
  name,
  priority,
  project: extra.project ?? 'Inbox',
  progress: extra.progress ?? 0,
  estimate: extra.estimate ?? 1,
  synced: extra.synced ?? true,
  reminder: extra.reminder ?? false,
  reminderTarget: null,
  reminderPending: false,
})

let tasks: Task[] = [
  makeTask('Write the release notes', 'high', { project: 'Website', progress: 60, estimate: 1.5 }),
  makeTask('Reply to the design review', 'normal', { project: 'Inbox', progress: 20, estimate: 0.5 }),
  makeTask('Renew the domain', 'low', { project: 'Admin', progress: 90, estimate: 0.25 }),
  makeTask('Pick up the parcel', 'low', { project: 'Errands', progress: 5, estimate: 0.75 }),
  // Deliberately unsynced, so the header's count is not just "all of them".
  makeTask('Archive last quarter', 'low', { project: 'Admin', progress: 40, synced: false }),
]

export const db = {
  all: () => tasks,
  find: (id: string) => tasks.find((task) => task.id === id),
  create: (name: string, priority: Priority, project?: string) => {
    const task = makeTask(name, priority, { project })
    tasks.push(task)
    return task
  },
  remove: (id: string) => {
    tasks = tasks.filter((task) => task.id !== id)
  },
}
