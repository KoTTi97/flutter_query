// Override any of these to exaggerate a state you want to look at, e.g.
// `LIST_LATENCY=5000 npm run dev` to sit in the loading skeletons.

export const PORT = Number(process.env.PORT ?? 5174)

export const LIST_LATENCY = Number(process.env.LIST_LATENCY ?? 900) // slow on purpose, so the loading states are visible
export const DETAIL_LATENCY = Number(process.env.DETAIL_LATENCY ?? 350)
export const WRITE_LATENCY = Number(process.env.WRITE_LATENCY ?? 700)
export const CONFIRM_AFTER = Number(process.env.CONFIRM_AFTER ?? 3000) // how long the reminder scheduler takes to confirm

export const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms))
