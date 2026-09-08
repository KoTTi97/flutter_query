// axios is the transport. Interceptors are the one place where every request
// passes through, which is where cross-cutting concerns belong (auth headers,
// correlation ids, timing, error normalisation) — none of which TanStack Query
// wants to know about.

import axios, { type AxiosRequestHeaders } from 'axios'
import { useAppStore } from './store.ts'

/** Where the timing stamp rides between the two interceptors. */
type Timed = { startedAt?: number }

export const http = axios.create({
  // Vite proxies /api to the standalone gateway (see vite.config.ts), so the
  // browser talks same-origin and the gateway's port stays out of this file.
  baseURL: '/api',
})

http.interceptors.request.use((config) => {
  ;(config as typeof config & Timed).startedAt = performance.now()
  config.headers = config.headers ?? ({} as AxiosRequestHeaders)
  config.headers.set('x-demo-client', 'tq-demo')
  return config
})

http.interceptors.response.use(
  (response) => {
    record(response.config, true)
    return response
  },
  (error: unknown) => {
    if (axios.isAxiosError(error)) {
      if (error.config) record(error.config, false)
      // The gateway answers errors with `{ message }` JSON. Surface that text as
      // the Error the UI renders, instead of axios' generic status-code prose.
      const message = (error.response?.data as { message?: string } | undefined)?.message
      if (message) return Promise.reject(new Error(message))
    }
    return Promise.reject(error)
  },
)

const record = (config: { url?: string; method?: string } & Timed, ok: boolean) => {
  useAppStore.getState().recordRequest({
    path: describe(config),
    ms: Math.round(performance.now() - (config.startedAt ?? performance.now())),
    ok,
  })
}

/** `GET sensors/3/name` — the id kept in, because watching per-sensor requests
 *  (or their absence) is half the point of the demo. */
const describe = (config: { url?: string; method?: string }) => {
  const path = config.url?.split('?')[0]?.replace(/^\//, '') ?? ''
  return `${config.method?.toUpperCase() ?? 'GET'} ${path}`
}
