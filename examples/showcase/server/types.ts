// The wire types, documented on the producing side. Each client declares its
// own copy (the Flutter app in `lib/shared/models.dart`).

export type Post = { id: number; title: string; body: string }

export type Comment = { id: number; postId: number; author: string; text: string }

export type Todo = { id: number; text: string; done: boolean }

// `fetchedAt` is stamped per response, so a refetched page is visibly newer
// than the one it replaced (upstream's infinite-query-with-max-pages trick).
export type Project = { id: number; name: string; fetchedAt: string }

export type Tick = { id: number; at: string }

// One scripted failure: the next `count` requests matching `method` and `path`
// (exact, or a prefix when `path` ends in `*`) answer `status` instead.
export type FailNext = {
  method: string
  path: string
  count: number
  status: number
  message?: string
}

export type ScenarioConfig = {
  latency: number
  errorRate: number
  failNext: FailNext[]
}

export type LogEntry = {
  method: string
  path: string
  query: Record<string, string>
  at: string
  status: number
}

export type Seed = {
  posts: Post[]
  comments: Comment[]
  todos: Todo[]
  projectCount: number
}
