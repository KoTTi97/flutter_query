# The showcase

Every feature of `tanstack_query_flutter` as its own screen, against a dummy
backend built for the purpose, each screen with widget tests and a Playwright
end-to-end suite. The app is the catalogue; the tests are the proof.

## Running it

The backend first (Node 23.6 or later — it runs the TypeScript directly):

```bash
cd examples/showcase/server && npm install && npm run dev
```

Then the app, on any platform. Only `web/` is generated; `flutter create
--platforms=macos,android .` adds the others.

```bash
cd examples/showcase && flutter run -d chrome
```

```bash
flutter run --dart-define=BACKEND=http://192.168.1.5:5175/api   # a real device
```

The home screen lists the catalogue; each row opens a feature at `/#/<id>`.

## The catalogue

Each feature lives in `lib/features/<id>/`, imports only the package and
`lib/shared/`, and says at the top of its file what it shows, which upstream
example it mirrors, and how it is proven. Its widget tests are
`test/features/<id>_test.dart`, its end-to-end tests `e2e/tests/<id>.spec.ts`.

| Feature | Shows | Upstream example |
|---|---|---|
| `simple` | one query read in build, its states, a refetch with `isFetching` | `simple` |
| `basic` | list → detail, `getQueryData` marks what the cache holds, background refetch, `gcTime` | `basic` |
| `default-query-function` | `QueryDefaults.queryFn` deriving the path from the key; per-key defaults | `default-query-function` |
| `dependent-queries` | `Enabled.when`: a query that waits for another's data | — |
| `parallel-queries` | several queries in one widget; `client.isFetching` | — |
| `prefetching` | `client.query(...).ignore()` before the screen that needs it | `prefetching` |
| `select-and-sharing` | `select`, `QuerySelectBuilder`, `buildWhen`, `structuralSharing`, rebuild counts | — |
| `initial-and-placeholder` | `InitialData` with `initialDataUpdatedAt` versus `PlaceholderData`, `isPlaceholderData` | — |
| `stale-and-gc` | every `StaleTime` and `GcTime` value, watched in the inspector | — |
| `pagination` | `PlaceholderData.compute` keeping the previous page, prefetching the next | `pagination` |
| `load-more` | an infinite query appending pages on scroll; cache survival across navigation | `load-more-infinite-scroll` |
| `max-pages` | pages in both directions with `maxPages: 3` | `infinite-query-with-max-pages` |
| `mutations` | `mutate`, `mutateAsync`, `reset`, `isMutating`, per-call callbacks, `MutationScope` | — |
| `optimistic-updates` | the write shown before the answer, from `variables` and from the cache with rollback | `nextjs-app-optimistic-updates` |
| `playground` | todos with live stale time, gc time, latency and error rate | `playground` |
| `invalidation-and-filters` | invalidate, refetch, reset, remove; prefix, exact, `type`, `predicate` | — |
| `auto-refetching` | `RefetchInterval`, in the foreground and not | `auto-refetching` |
| `retry` | `RetryPolicy`, `RetryDelay`, `failureCount`, loading versus refetch errors | — |
| `cancellation` | `signal` to the transport, `cancelQueries`, search-as-you-type | — |
| `offline` | `NetworkMode`, paused mutations, `resumePausedMutations`, `onlineStatus` | `offline` |
| `focus-refetch` | `RefetchOn` for focus and mount | — |
| `four-call-styles` | the same query through `context.query`, `QueryBuilder`, `QueryMixin`, `QueryController` | — |
| `global-callbacks` | `QueryCache`/`MutationCache` callbacks, `meta` | — |
| `cache-inspector` | every entry and event of both caches, live | (devtools) |

Not here, because the port does not have them: hydration and persisters,
`useQueries`, `streamedQuery`, SSR. The reasons are in the core's
[PORTING_NOTES](https://github.com/KoTTi97/flutter_query/blob/main/packages/tanstack_query_core/test/PORTING_NOTES.md).

No screen presents one of the four call styles as the default; across the
catalogue each is used in its turn.

## The backend

[`server/`](server) is an express server with one in-memory world per
`x-scenario` header — see its [README](server/README.md). The app reads the
scenario from `?scenario=<id>` in the URL on the web (before the `#/route`, so
it survives navigation) or from `--dart-define=SCENARIO=<id>` elsewhere, and
shows it in every app bar. Without either it lives in `default`, like a human
in a browser.

## Tests

Three layers, nothing else:

```bash
cd examples/showcase && flutter test
```

**Widget tests** run the real app against `test/fake_backend.dart`, a dio
`HttpClientAdapter` that mirrors the server route for route, loads the same
`server/seed.json`, and scripts the same faults. `test/harness.dart` has
`showcaseTest`: a fresh backend and client per test, the app opened on one
route, and the teardown a `QueryClient` needs (tear the tree down, let the
frame after it run, then `client.clear()` — the test binding checks for
pending timers before any `tearDown`). Two rules learned the hard way: the
fake's latency is a timer, so step it with `tester.pump(duration)` —
`pumpAndSettle` only pumps while a frame is scheduled; and a screen that polls
or retries is stepped the same way, because `pumpAndSettle` never returns
while a `refetchInterval` runs.

**The contract test** (`test/backend_contract_test.dart`) runs one list of
cases against the fake and, with `SHOWCASE_SERVER=http://localhost:5175/api`
set and the server running, against the server. It is what makes the fake
trustworthy; CI runs both.

**End-to-end tests** (`e2e/`) drive the real web build in Chromium against the
real backend:

```bash
cd examples/showcase/e2e && npm ci && npx playwright install chromium
```

```bash
npm run build && npm test
```

Every test gets a scenario of its own (`tests/fixtures.ts`), so the suite runs
fully parallel and nothing a test does is visible to another. Flutter web
paints to a canvas, so the tests read the **semantics tree**, switched on by
`--dart-define=E2E=true`. What that means for writing one:

- A screen's **debug strip** is a semantics group `debug <label>` whose facts
  are exact leaf texts: `fact(page, 'post', 'fetchStatus=idle')`. That is how
  a test reads the cache — whether a fetch happened, whether an entry is stale,
  how many observers hold it — without a stopwatch.
- **Nothing asserts on a clock.** To prove something shows *before* the
  backend answers, `holdRequest(page, glob)` holds the request in the browser
  and releases it after the assertion. Counts are asserted through the
  scenario's request log; a poll is proven to stop by sampling the count,
  waiting, and sampling again.
- A `Card` that is a semantic container folds its texts into its accessible
  name; `SectionCard` opts out so every text stays findable. Buttons are their
  tooltips; a text field mirrors its text only once focused, so click before
  you read or `fill`; a lazily built list only has the rows in view.
- No `Slider` (only increment steps reach the DOM), no hover (it does not reach
  a `MouseRegion` through the semantics overlay), no `page.goBack()` (Flutter
  web keeps one history entry — use the app's back button).
- The build passes `--pwa-strategy=none --no-web-resources-cdn`: no service
  worker serving a stale bundle after a local rebuild, no CanvasKit fetched
  from a CDN in every fresh browser context.
