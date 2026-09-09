// Override any of these to exaggerate a state you want to look at, e.g.
// `LATENCY=3000 npm run dev` to sit in the loading states.

export const PORT = Number(process.env.PORT ?? 5175)

// Every scenario starts with this latency on every request; tests lower it
// through the scenario's config endpoint, humans keep it so loading states
// are visible.
export const DEFAULT_LATENCY = Number(process.env.LATENCY ?? 300)

// A scenario nobody has touched for this long is dropped. Idle time only —
// never during a run, or a test's counts would silently reset.
export const SCENARIO_TTL = Number(process.env.SCENARIO_TTL ?? 15 * 60_000)

export const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms))
