// What every spec shares: a backend scenario of the test's own, a way to open
// a feature inside it, and the two selectors the debug strip is built for.
import { expect, test as base, type APIRequestContext, type Page } from '@playwright/test'

export const BACKEND = 'http://localhost:5175/api'

export type LogEntry = {
  method: string
  path: string
  query: Record<string, string>
  at: string
  status: number
}

export type FailNext = { method: string; path: string; count: number; status: number; message?: string }

export type ScenarioConfig = { latency?: number; errorRate?: number; failNext?: FailNext[] }

export class Scenario {
  constructor(
    readonly id: string,
    private readonly request: APIRequestContext,
  ) {}

  private url(tail: string) {
    return `${BACKEND}/__scenario/${this.id}/${tail}`
  }

  async reset() {
    await this.request.post(this.url('reset'))
  }

  async config(config: ScenarioConfig) {
    const response = await this.request.post(this.url('config'), { data: config })
    expect(response.ok(), await response.text()).toBe(true)
  }

  async requests(): Promise<LogEntry[]> {
    return (await this.request.get(this.url('requests'))).json()
  }

  async clearRequests() {
    await this.request.delete(this.url('requests'))
  }

  /// How many answered requests match `method` and `path` (a RegExp on the
  /// full path, `/api/posts/1`).
  async count(method: string, path: RegExp) {
    const log = await this.requests()
    return log.filter((entry) => entry.method === method && path.test(entry.path)).length
  }

  /// A direct call into this scenario, for setup and for checking what the
  /// backend really holds.
  async api(method: 'get' | 'post' | 'patch' | 'delete', path: string, data?: unknown) {
    return this.request[method](`${BACKEND}${path}`, { headers: { 'x-scenario': this.id }, data })
  }
}

export const test = base.extend<{ scenario: Scenario; open: (route: string) => Promise<void> }>({
  scenario: async ({ request }, use, testInfo) => {
    // Unique per test and per run, so a re-run never meets an old world.
    const scenario = new Scenario(`${testInfo.testId}-${Date.now().toString(36)}`, request)
    await scenario.reset()
    await use(scenario)
  },
  open: async ({ page, scenario }, use) => {
    await use(async (route: string) => {
      // The scenario rides in the query string, before the hash, so it
      // survives every in-app navigation.
      await page.goto(`/?scenario=${scenario.id}#${route}`)
      await expect(page.getByText(`scenario ${scenario.id}`, { exact: true })).toBeVisible()
    })
  },
})

export { expect }
export type { Page }

/// The debug strip labelled `label`: a semantics group whose facts are exact
/// leaf texts, `status=success`, `fetchStatus=idle`, `fetches=2`.
export const strip = (page: Page, label: string) => page.getByRole('group', { name: `debug ${label}`, exact: true })

export const fact = (page: Page, label: string, text: string) => strip(page, label).getByText(text, { exact: true })

/// A SnackBar's text, or any other live region's. Flutter web renders a
/// `liveRegion` twice: as its node in the semantics tree, and — for a few
/// hundred milliseconds after it appears — as a copy in the
/// `<flt-announcement-host>` that screen readers are told about, which sits
/// outside the tree. A bare `page.getByText(text)` then resolves to both and
/// strict mode refuses the locator, or to one, depending on when it runs
/// (ninth review, C44). Scoped to the semantics host, so only the tree's copy
/// is ever matched.
export const snackBar = (page: Page, text: string) => page.locator('flt-semantics-host').getByText(text, { exact: true })

/// Holds every request matching `glob` in the browser until `release()`, so
/// an assertion between the action and the release runs while the backend
/// provably has not answered. After the release the handler is a passthrough;
/// unrouting it would race the handler that is still letting the held request
/// go.
export function holdRequest(page: Page, glob: string) {
  let letGo: () => void = () => {}
  const held = new Promise<void>((resolve) => {
    letGo = resolve
  })
  let seen = 0
  const routed = page.route(glob, async (route) => {
    seen += 1
    await held
    await route.continue()
  })
  return {
    /// How many requests the hold has caught so far.
    get seen() {
      return seen
    },
    async release() {
      await routed
      letGo()
    },
  }
}
