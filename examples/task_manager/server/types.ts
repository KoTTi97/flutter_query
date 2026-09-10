// The backend's domain model. There is no shared type program between server
// and client — the Flutter app declares its own copy of this contract, the
// same situation a real backend is in. Field-level docs live here, on the
// producing side.

export type Priority = 'low' | 'normal' | 'high'

export type Task = {
  id: string
  name: string
  priority: Priority
  project: string
  /** How far along the task is, 0–100. */
  progress: number
  /** Remaining work in hours. */
  estimate: number
  /** Present on the shared board. Server-owned; a client cannot set it. */
  synced: boolean
  /** Confirmed by the reminder scheduler. */
  reminder: boolean
  /**
   * The value a write is trying to reach, or null when nothing is outstanding.
   *
   * This exists so an in-flight write has somewhere to live that a poll response
   * cannot overwrite. Without it, the confirmed field is the only place to put
   * the optimistic value, and every poll during the confirmation window stomps
   * it back to the old state — the switch visibly flickers off→on→off→on.
   */
  reminderTarget: boolean | null
  /** The server accepted a write the scheduler has not confirmed yet. */
  reminderPending: boolean
}

export type TaskListResponse = {
  tasks: Task[]
  fetchedAt: string
}
