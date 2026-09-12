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

**A feature therefore exists five times** — that directory, a row of
`featureEntries` in `lib/routes.dart`, the widget-test file, the spec, and a
row of the table below — and `test/catalogue_test.dart` compares the five,
plus which screen each route actually reaches. Adding a feature means adding
it everywhere; the test says where you stopped.

**`lib/shared/` is the deliberate exception to "self-contained".** Self-
contained means a feature never reaches into another feature's directory, not
that it re-types the app's own furniture. Each file there is one subject, and
these are the sentences:

| Module | What it holds |
|---|---|
| `api.dart` | the one way to the backend: dio, the scenario header, every endpoint |
| `models.dart` | what comes back over it |
| `feature.dart` | what a screen says about itself — the catalogue's row |
| `feature_scaffold.dart` | the frame around a screen: title, back, scenario, the intro |
| `scope.dart` | how a screen is handed the api and the cache counters |
| `cache_stats.dart` | what the cache has done since the app started, which a screen built later cannot have watched |
| `cache_listener.dart` | *an event arrived and I do not know the scheduler phase*: `PhaseSafeRebuild`, and `CacheListener` for the eight sites whose event is the cache's |
| `debug_strip.dart` | the facts of **one cache entry**, the only named group that is about the cache rather than about the screen |
| `fact_group.dart` | how a screen tells a test what happened: `SemanticsGroup`/`FactList`/`FactGroup`, the one name they publish, the styles and `hhmmss` a fact is printed in |
| `controls.dart` | how a screen is driven: `Toolbar`, `ActionButton`, `knob`/`knobButton` |
| `chrome.dart` | what a screen is made of and what none of it means to a test: `SectionCard`, `Pill`, `Notice`, `SkeletonBox` |

The last three are the three widget modules, and they are split by **what a
test does with the widget** — it reads a fact group, it presses a control, it
does neither to chrome — not by which ticket happened to need it.

**What earns a file, or a member, a place here.** The standard is
`cache_listener.dart`: a seam with a name, behind which sits more than any
caller wants to know.

1. **One subject, sayable in one sentence without "and".** An "and" that is a
   *layering* is still one subject — `CacheListener` is built on
   `PhaseSafeRebuild`. An "and" that is a *list* is two files.
2. **Shared in fact: more than one feature calls it.** The app's `ThemeData`
   has one caller and lives beside its `MaterialApp` in `main.dart`; a
   label–value row had one caller and went home to it (#69).
3. **The third copy of the same *lines* moves — the third *composition* of the
   same vocabulary does not.** Three screens now build "a named group with a
   heading and some facts" and no two of them share a line beyond
   `SemanticsGroup` + `FactList`, which is already the module; a widget taking
   every way they differ would have a wider interface than the three call
   sites together. Two screens that merely look alike stay two screens — the
   fourth knob is a `Wrap` cell rather than a row of a stretched `Column`, so
   it composes `knobButton` itself and says why in its dartdoc, which is the
   shape to copy when a shared thing nearly fits.

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
| `build-when` | `buildWhen` on all eight keyless reads, each beside an unfiltered twin; a knob for the predicate, and the build counts either half of a pair reaches | — |
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

- **A group is named once, and the name is what both test layers use.** A
  screen publishes facts through `SemanticsGroup` / `FactGroup`
  (`lib/shared/fact_group.dart`): the one `name` it is given becomes the
  semantics label *and* the widget key, so `group(page, 'reader alpha')` here
  and `groupNamed('reader alpha')` in `test/harness.dart` address the same
  thing. Every locator goes through `group` / `factIn` in `tests/fixtures.ts`
  and every finder through `groupNamed` / `factIn` in the harness — nothing
  writes `getByRole('group', …)` or `find.byKey` for a group of its own.
- **A delta is read with `factNumber(page, name, key)`**, not by slicing the
  text yourself. Prefer `factIn` wherever the expected text is known: an exact
  text retries into the frame, while a number read once races it — so read a
  number only to compute the text you then assert.
- A screen's **debug strip** is such a group, named `debug <label>`, whose
  facts are exact leaf texts: `fact(page, 'post', 'fetchStatus=idle')`. That is
  how a test reads the cache — whether a fetch happened, whether an entry is
  stale, how many observers hold it — without a stopwatch. **One per cache
  entry a test reads**, and it is the only named group that is about the cache
  rather than about the screen.
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
  `test.use({ viewport })`) when a screen is taller than the default. **That
  size is a fact about the screen and stays in its own test file** — there is
  deliberately no shared `tall()`: twenty-three widget-test files set the
  window, sixteen of them behind a local function of that name, over
  twenty-one different sizes from 800×900 to 2400×8400; nineteen specs set a
  viewport of their own over eleven heights. A helper taking the size would be
  the size with an import in front of it, and a helper *not* taking it would
  be twenty-three wrong windows (#69).
- **A lazy `ListView.builder` with a fixed `itemExtent` does not relayout when
  only the item count grows**, so rows appended by a "load more" can be
  unreachable in a widget test. An eager bounded `Column` is the honest fix.
- **`IconButton(tooltip:)` is named by its tooltip; a `Tooltip` wrapped around
  a text button is not** — there the visible label is the name, and
  `Tooltip(message: …, excludeFromSemantics: true)` keeps the hover text
  without touching the tree. Several controls in one row can fold into the
  row's node: wrap a toolbar in `SemanticsGroup(child: …)` — or in `Toolbar`,
  which is that plus the `Wrap`.
- **Two facts named `status=` collide.** Put a card's facts in a `FactGroup`
  and read them inside it, the way the strips do. Never write
  `Semantics(container: true, explicitChildNodes: true)` out again — `grep -r
  'container: true' lib` has exactly one hit, in `fact_group.dart`, and that is
  the invariant. A `SectionCard` title must not repeat a control's label
  either.
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
