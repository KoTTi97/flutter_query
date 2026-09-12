# The showcase

Every feature of `query_kit_flutter` as its own screen, against a dummy
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

**`lib/shared/` is the deliberate exception to "self-contained".** Self-
contained means a feature never reaches into another feature's directory, not
that it re-types the app's own furniture: the backend client (`api.dart`), the
models, the scope, the theme and `SectionCard`/`Pill`/`Notice`, the debug
strip, `CacheListener` and its `PhaseSafeRebuild` mixin (`cache_listener.dart`),
and the `Toolbar`/`ActionButton`/`knob` controls with the `monoStyle` and
`hhmmss` formats (`controls.dart`). The rule for adding to it: **the third copy
moves.** Two screens that happen to look alike stay two screens — the fourth
knob is a `Wrap` cell rather than a row of a stretched `Column`, so it composes
`knobButton` itself and says why in its dartdoc, which is the shape to copy
when a shared thing nearly fits.

| Feature | Shows | Upstream example |
|---|---|---|
| `simple` | one query read in build, its states, a refetch with `isFetching` | `simple` |
| `basic` | list → detail, `getQueryData` marks what the cache holds, background refetch, `gcTime` | `basic` |
| `default-query-function` | `QueryDefaults.queryFn` deriving the path from the key; per-key defaults | `default-query-function` |
| `dependent-queries` | `Enabled.when`: a query that waits for another's data | — |
| `parallel-queries` | several queries in one widget; `client.isFetching` | — |
| `query-collections` | `QueriesBuilder` over a list that grows, shrinks and reorders; duplicate keys; partial failure; the same collection as a `QueriesController` | — |
| `prefetching` | `client.query(...).ignore()` before the screen that needs it, `revalidateIfStale`, and `client.infiniteQuery(...).ignore()` for the first page of an infinite one | `prefetching` |
| `select-and-sharing` | `select`, `QuerySelectBuilder`, `buildWhen`, `structuralSharing`, rebuild counts | — |
| `initial-and-placeholder` | `InitialData` with `initialDataUpdatedAt` and its lazy `initialDataUpdatedAtCompute`, versus `PlaceholderData`, `isPlaceholderData` | — |
| `stale-and-gc` | every `StaleTime` and `GcTime` value, watched in the inspector | — |
| `pagination` | `PlaceholderData.keepPrevious()` keeping the previous page, prefetching the next | `pagination` |
| `load-more` | an infinite query appending pages on scroll; cache survival across navigation, read back with `getInfiniteQueryData` | `load-more-infinite-scroll` |
| `max-pages` | pages in both directions with `maxPages: 3`; the page context's `direction` | `infinite-query-with-max-pages` |
| `mutations` | `mutate`, `mutateAsync`, `reset`, `isMutating`, per-call callbacks, `MutationScope` | — |
| `optimistic-updates` | the write shown before the answer, from `variables` and from the cache with rollback | `nextjs-app-optimistic-updates` |
| `mutation-state` | `MutationStateController`: every running mutation in the cache, read by a widget that owns none | — |
| `playground` | todos with live stale time, gc time, latency and error rate | `playground` |
| `invalidation-and-filters` | invalidate, refetch, reset, remove; prefix, exact, `type`, `predicate` | — |
| `auto-refetching` | `RefetchInterval`, in the foreground and not | `auto-refetching` |
| `retry` | every `RetryPolicy` (`never`, `times`, `always`, `when`) and `RetryDelay` (`fixed`, `exponential`, `dynamic`), `failureCount`, loading versus refetch errors | — |
| `cancellation` | `signal` to the transport, `cancelQueries`, search-as-you-type | — |
| `offline` | `NetworkMode`, paused mutations, `resumePausedMutations`, `OnlineStatus`, `refetchOnReconnect` | `offline` |
| `focus-refetch` | `RefetchOn` for focus and mount, `refetchMinBackgroundDuration`, and the provider's own knobs on a nested `QueryClientProvider.create`: `isAppShown`, `onlineStatus`, `maybeOf` | — |
| `four-call-styles` | the same query through `context.query`, `QueryBuilder`, `QueryMixin`, `QueryController`, plus `QueryListener` for a side effect and a batched write through `NotifyManager.shared`; the mutation and infinite counterparts — `MutationListener`, `context.infiniteQuery`, `watchInfiniteQuery`, `InfiniteQueryListener`, `client.observeInfinite` | — |
| `global-callbacks` | `QueryCache`/`MutationCache` callbacks, `meta` | — |
| `cache-inspector` | every entry and event of both caches, live | (devtools) |
| `diagnostics` | what the library throws, and when: `QueryDataTypeError` on a read or write of the wrong type, `MissingMutationFunctionError` and its cure `setMutationDefaults` | — |

Not here, because the port does not have them: hydration and persisters,
`useQueries`' `combine` step (the homogeneous list is `query-collections`
above), `streamedQuery`, SSR. The reasons are in the core's
[PORTING_NOTES](https://github.com/KoTTi97/flutter_query/blob/main/packages/query_kit/test/PORTING_NOTES.md).

No screen presents one of the four call styles as the default; across the
catalogue each is used in its turn.

**What the catalogue found.** Building it turned up two bugs in the library
that no ported upstream test could reach, because neither is visible without a
real widget: a read whose key changed lost `keepPreviousData` in `QueryMixin`
and `context.query`, and `structuralSharing` was invisible to every reader
because the observer re-shared the cache's data against its own last result.
Both were reproduced in the library's own suite before anything was changed;
the "Found by the showcase" section of PORTING_NOTES has the details.

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
frame after it run, `client.clear()`, then one more pump and clear for what a
dropped mutation's callbacks wrote — the test binding checks for pending
timers before any `tearDown`; the site's testing guide has the snippet). Two rules learned the hard way: the
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
  waiting, and sampling again. The one deliberate exception is
  `test/backend_contract_test.dart`'s `?delay` case, which times the real
  server with a `Stopwatch`: there the delay *is* the contract under test,
  nothing can be held or counted instead, and the bound is loose (280 ms for
  a 300 ms delay) so a slow CI runner cannot fail it.
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

## Writing a screen: what the catalogue learned

Rules that cost someone a debugging session, in the order they bite:

- **`FeatureScaffold` lays its children out in a lazy `ListView`.** A debug
  strip below a long list is never built, and neither a widget finder nor the
  browser can see it. Keep strips near the top, bound tall content in its own
  scroller, and widen the test window (`tester.view.physicalSize`,
  `test.use({ viewport })`) when a screen is taller than the default.
- **A lazy `ListView.builder` with a fixed `itemExtent` does not relayout when
  only the item count grows**, so rows appended by a "load more" can be
  unreachable in a widget test. An eager bounded `Column` is the honest fix.
- **`IconButton(tooltip:)` is named by its tooltip; a `Tooltip` wrapped around
  a text button is not** — there the visible label is the name, and
  `Tooltip(message: …, excludeFromSemantics: true)` keeps the hover text
  without touching the tree. Several controls in one row can fold into the
  row's node: wrap a toolbar in `Semantics(container: true,
  explicitChildNodes: true)`.
- **Two facts named `status=` collide.** Put a card's facts in a named
  semantics group and read them inside it, the way the strips do. A
  `SectionCard` title must not repeat a control's label either.
- **A subscription to a cache for rebuilds must filter to state-changing
  events.** Every build re-applies a reader's options, an inline `queryFn`
  closure is never equal, and `QueryObserverOptionsUpdated` then fires once
  per build — a screen that rebuilds on it feeds itself. The same holds for
  the mutation cache. `ShowcaseScope.of(context).stats` already filters.
- **An event does not know which scheduler phase it arrives in**, and inside a
  frame's build phase `setState` is not allowed. Never write that dance out
  again: mix in `PhaseSafeRebuild` and call `scheduleRebuild()`, or — when the
  whole subtree just follows the cache — wrap it in `CacheListener`, which does
  the subscription too. Twelve screens had written their own before C55.
- **A read whose key the screen switches needs an `id:`** — with one, the
  observer follows the key (and `PlaceholderData.compute` gets the previous
  data); without one, a new key is a new read.
- **`SegmentedButton` segments are `getByRole('radio')`**, a `SwitchListTile`
  is `getByRole('switch')` and its subtitle is part of its name; Playwright's
  `check()` races Flutter's next-frame semantics update, so click and then
  assert `toBeChecked()`. The AppBar's back button is already named `Back`.
- **Scrolling in the browser** is `locator.scrollIntoViewIfNeeded()` on a row;
  `mouse.wheel` does not reach the canvas through the semantics overlay.
- **A `SnackBar` is a live region, and Flutter web announces one twice**: as
  its node in the semantics tree and, for a few hundred milliseconds, as a
  copy in `<flt-announcement-host>` outside it. A bare `getByText` on its text
  matches two elements or one depending on when it runs, and strict mode
  refuses two. `snackBar(page, text)` in `tests/fixtures.ts` scopes to the
  semantics host; use it for any live-region text.
- **`page.route` cannot filter by method** — hold a POST with a handler that
  checks `route.request().method()` and continues everything else, the CORS
  preflight included.
- **`tester.pump()` with no duration does not let a fake-backend response
  resolve**: dio hangs its pipeline off zero-duration timers and `FakeAsync`
  runs those only when the clock moves. Step with a real duration.
