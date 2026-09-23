# query_kit docs site: gap analysis against TanStack Query's React docs

Audited 2026-09-23 against `main` at `491ed27`. Nothing in the repository was edited.

Sources read: every page under `website/docs/` (21 pages, about 3,400 lines), `website/sidebars.ts`,
`website/docusaurus.config.ts` and `website/src/pages/index.tsx`. On the upstream side:
`query/docs/config.json`, which gives the React sidebar,
`query/docs/framework/react/{guides,reference}` and `query/examples/react/*`. For the
spot checks: the export barrels `packages/query_kit/lib/query_kit.dart` and
`packages/query_kit_flutter/lib/query_kit_flutter.dart`, every class name under
`packages/*/lib/src`, the headers of the 30 showcase features and `examples/task_manager`.

---

## 0. Headline findings

1. **The content is good, but it is organised by the port's internals.** Pages are named after
   mechanisms ("Reading a query", "Options", "The query client", "Collections and side effects").
   TanStack names its pages after what the reader wants to do ("Dependent queries", "Polling",
   "Optimistic updates"). About 20 upstream concepts are covered only inside a large mixed page,
   in a table row or in one paragraph. Examples: `options.md` is 360 lines holding eight
   upstream guides, and `the-query-client.md` holds five.
2. **No "Important defaults" page and no "Caching lifecycle" walkthrough.** On TanStack these are
   the two pages people read most. Here the defaults are spread over `options.md`,
   `the-query-client.md` and `lifecycle-and-connectivity.md`.
3. **No recipes.** Nothing covers auth or 401 handling, pull-to-refresh, forms and validation
   errors, a global error snackbar, go_router, dependency injection, or living alongside
   Riverpod or Bloc. `examples/task_manager` and the showcase already solve several of these;
   the docs never mention it.
4. **Review-log text runs through user docs and through the dartdoc that pub.dev will render.**
   It appears in 10 site pages and in about 300 dartdoc lines under `packages/*/lib`. The first
   public page, `query_kit.dart`'s library doc, cites "ninth review, 2026-09-10, C23".
5. **The numbers on the site are stale and disagree with each other.** Core tests are shown as
   783 (current: 826), binding tests as 144 (current: 287), and the bug count as 22 in one place
   and 23 in another. Details in §4.
6. **`reference/api.md` is only a pointer page.** There is no hand-written reference layer, the
   dartdoc has no `{@category}` grouping, and the page ends by sending readers to the test
   suite.
7. **The showcase could be embedded live, but not as it is today.** Its fake backend lives in
   `test/` and reads its seed with `dart:io`, so a static web build would need a real server. §2
   describes the change.

---

## 1. Mapping: upstream React docs → query_kit site

Legend. **Coverage:** Full / Partial / None. **Applies:** Yes / Adapted / No (N/A), with the
reason. The N/A rows follow `reference/feature-matrix.md` ("Deliberately not in 1.0") and the
divergence table in `packages/query_kit/test/PORTING_NOTES.md` (§"Deliberate divergences…",
line 3108 onward).

### Getting started

| Upstream page | Covered by | Coverage | Applies? / notes |
|---|---|---|---|
| `overview.md` (motivation, what server state is, "enough talk") | `intro.md` | Partial | Yes. `intro.md` sells the port ("The bet", test counts). It never explains the server-state problem: caching, deduplication, stale data, background updates. The motivation section can be adapted almost 1:1. |
| `installation.md` | `getting-started/installation.md` | Full | Yes. Good. Two small issues: "no dependency beyond Flutter" overlooks `clock` and `meta` in `packages/query_kit/pubspec.yaml`, and the "From a checkout" section belongs in the contributor docs. |
| `quick-start.md` | `getting-started/first-query.md` | Full | Yes. A good page, but it teaches four concepts at once (type argument, `QueryKey`, `signal`, `StaleTime`) before the first read. |
| `devtools.md` | none. `feature-matrix.md` says "Devtools: none; the showcase's `cache-inspector` screen is the stand-in" | None | **Adapted.** There are no devtools, but a "Debugging and inspecting the cache" page belongs here: `queryCache.subscribe`, `QueryKey.debugString`, `client.isFetching()`, a copy of the `cache_inspector` pattern, and logging via `QueryCache(onError:)`. |
| `comparison.md` | none | None | Adapted. A comparison with Dart packages (`fquery`, `flutter_query`, `cached_query`, Riverpod `FutureProvider`/`AsyncNotifier`, Bloc) is what Flutter users will ask for. `docs/research/` already has a Dart library survey to draw on. |
| `typescript.md` | spread over `first-query.md` (type argument, `strict-inference`), `options.md#two-shapes`, `pure-dart.md` ("What is Dart rather than JavaScript") | Partial | Adapted as "Type safety in Dart": the sealed result, one key one exact type, `QueryDataTypeError`, two options shapes, `strict-inference`. The content exists but is split across three pages. |
| `graphql.md` | none | None | Adapted, low priority: one paragraph saying any `Future` works (e.g. `graphql`/`ferry` clients) and giving the key convention. |
| `react-native.md` (focus via AppState, online via NetInfo, refresh on screen focus) | `guides/lifecycle-and-connectivity.md` | Full | Yes, and it is the closest analogue. Missing: "refetch when a *route* regains focus", the RN `useFocusEffect` recipe. In Flutter that is `RouteAware` / go_router. |
| `community-resources.md` | none | None | Low priority; possibly a "Further reading" page (TkDodo's blog applies almost 1:1). |

### Guides & Concepts

| Upstream guide | Covered by | Coverage | Applies? / notes |
|---|---|---|---|
| `important-defaults.md` | nowhere as a page. Pieces: `options.md` (staleTime 0, gcTime 5 min, exponential retry), `lifecycle-and-connectivity.md` (focus), `options.md#structural-sharing` | **None as a page** | Yes. **Highest-value missing page.** Must also state the port's own defaults: connectivity assumed online (nothing installed), `refetchMinBackgroundDuration` of `Duration.zero`, a mutation retry default, and "`client.query` without retry makes one attempt". |
| `queries.md` (status × fetchStatus, isPending/isFetching) | `first-query.md` §3, `reading-a-query.md` | Partial | Yes. The sealed result is explained. `status` vs `fetchStatus`, the 3×3 combinations, `isLoading`/`isRefetching`/`isPaused` and `isLoadingError`/`isRefetchError` (all in `query_kit/lib/src/query_result.dart`) have no page. |
| `query-keys.md` (arrays, hierarchy, key factories, the key includes every variable) | `first-query.md` (one paragraph), `troubleshooting.md` ("Two keys that 'are' the same") | Partial | Yes. The key-factory pattern (`ShowcaseKeys` in `examples/showcase/lib/shared/api.dart`, `TaskKeys` in the task manager), `QueryKey.append`, the prefix hierarchy for invalidation, and the record-of-list trap need their own page. |
| `query-functions.md` (throw on error, the context, the key in the fn) | `first-query.md`, `the-query-client.md#cancellation` | Partial | Yes, **and more important in Dart**: `package:http` does **not** throw on a 4xx/5xx response, so a query fn built on it reports errors as successes. Nothing on the site says so. |
| `query-options.md` (`queryOptions()` helper) | `first-query.md` §2 ("Describe the query once"), `options.md#two-shapes`, `withSelect` | Partial | Adapted: the "options function" pattern plus `withSelect`. Needs its own short page. |
| `network-mode.md` | `lifecycle-and-connectivity.md#network-mode` | Full | Yes. |
| `parallel-queries.md` | `collections-and-side-effects.md` (`QueriesBuilder`, `combine`) | Partial | Yes. The "manual" case (several `context.query` calls in one `build`) is never stated. The `parallel_queries` showcase screen exists. |
| `dependent-queries.md` | `options.md#enabled` (one sample) | Partial | Yes. The `dependent_queries` screen exists. Also worth explaining: `Enabled.when`, and a waterfall caused by dependent queries. |
| `background-fetching-indicators.md` | coming-from table row, feature-matrix row (`IsFetchingController`) | **None** | Yes. `IsFetchingController` has no prose anywhere on the site, and neither does a global "is anything loading" bar. |
| `window-focus-refetching.md` | `lifecycle-and-connectivity.md` | Full | Adapted: the lifecycle mapping, platform notes, `refetchMinBackgroundDuration`. |
| `polling.md` | `options.md#refetch-triggers` | Partial | Yes. Table only, plus the "give up after five" sample. Missing: `refetchIntervalInBackground` explained, and the "poll until confirmed" pattern that the task manager actually uses. |
| `disabling-queries.md` (lazy queries, `skipToken`) | `options.md#enabled` | Partial | Yes. The lazy-query pattern (a search box enabled once text exists) is missing. |
| `query-retries.md` | `options.md#retries` | Partial | Yes. Mostly there, but mixed with option-capture internals. |
| `paginated-queries.md` | `infinite-queries.md` (one line), `options.md` (`keepPrevious`), `reading-a-query.md` (`id:`) | Partial | Yes. `keepPrevious` needs an `id:` in two call styles, which is a trap that deserves a page. The `pagination` screen exists. |
| `infinite-queries.md` | `guides/infinite-queries.md` | Full | Yes. Good; add the `ListView`/sliver recipe. |
| `initial-query-data.md` | `options.md#initial-and-placeholder-data` | Partial | Yes. Table only. "Initial data from the cache", i.e. seeding a detail from the list, is missing. The task manager's comment in `lib/src/queries.dart` about why `initialData` cannot do that job is useful material. |
| `placeholder-query-data.md` | same | Partial | Yes. |
| `mutations.md` | `guides/mutations.md` | Full | Yes. Long (335 lines) and mixed with identity and assertion rules. Split it. |
| `query-invalidation.md` | `the-query-client.md#filters` (sample only) | **Partial, weak** | Yes. What `invalidateQueries` does (marks stale, refetches active ones), `refetchType`, prefix matching and `exact` are never explained. |
| `invalidations-from-mutations.md` | `first-query.md` §4, `mutations.md` | Full | Yes. |
| `updates-from-mutation-responses.md` | none explicit (`setQueryData` is documented, not the pattern) | Partial | Yes. |
| `optimistic-updates.md` | `mutations.md#optimistic-updates` | Full | Yes. Both shapes, the `variables` UI and the cache with rollback, are covered. |
| `query-cancellation.md` | `the-query-client.md#cancellation`, `first-query.md` | Partial | Yes. The dio snippet is there. Missing: `package:http` (a closeable `Client`), and search-as-you-type, which the `cancellation` screen already does. |
| `scroll-restoration.md` | none | None | **Adapted.** In Flutter, a cached query renders synchronously, so `PageStorageKey` restores the offset. Worth a short page because the answer differs from web routers. |
| `filters.md` | `the-query-client.md#filters` | Partial | Yes. `QueryFilters` fields are listed in one sentence. `MutationFilters` gets one line. There are no `predicate` examples. |
| `request-waterfalls.md` | none | None | Yes, and very relevant to Flutter: nested widgets that each fetch in `build`, dependent queries, prefetching on tap or in the route. |
| `prefetching.md` (and router integration) | `the-query-client.md` (the `client.query(...).ignore()` row) | Partial | Yes. The `prefetching` screen exists. Missing: prefetch on tap/hover and go_router `redirect`/`onEnter` integration. |
| `ssr.md`, `advanced-ssr.md` | `feature-matrix.md` ("SSR: not ported") | N/A | **No.** No server rendering in Flutter; `isServer`, `environmentManager` and `timeoutManager` are not ported. |
| `caching.md` (the lifecycle walkthrough) | none | **None** | Yes. `stale_and_gc` and `cache_inspector` are the ideal live demos. |
| `render-optimizations.md` | `guides/rebuilds.md` | Full | Adapted: `select` and `buildWhen` instead of tracked props. Good page. |
| `default-query-function.md` | `the-query-client.md#defaults` (one paragraph) | Partial | Yes. The `default_query_function` screen exists. |
| `suspense.md` | `feature-matrix.md` | N/A | **No.** React-only. The sealed result is the answer; one line in "Coming from React Query" is enough. |
| `testing.md` | `guides/testing.md` | Partial | Yes. The teardown and pump rules are excellent. Missing, all of it upstream's advice: **turn retries off in tests** (`DefaultOptions(queries: QueryDefaults(retry: RetryPolicy.never))`), injecting a fake API/dio adapter, testing mutations and error states, and testing without widgets via `QueryController` (one paragraph only). The page also tells users about `testFakeAsync` from `test/test_utils.dart`, which is internal to the repo. |
| `does-this-replace-client-state.md` | none. `reading-a-query.md` mentions riverpod/bloc in one sentence | None | Yes. **Important for Flutter**, where every team already has Riverpod, Bloc or Provider. |
| `migrating-to-*` | none | N/A | No. There is no prior version. A future "Migrating from fquery / cached_query / Riverpod FutureProvider" page would be the analogue. |

### Plugins, reference, examples, ESLint

| Upstream | Covered by | Coverage | Applies? |
|---|---|---|---|
| `plugins/persistQueryClient`, `create*Persister`, `broadcastQueryClient`, `createPersister` | `feature-matrix.md` ("Persistence and hydration: not in 1.0") | N/A in 1.0 | Not ported. `Query.setState` is named as "the door a persister would use", but no page shows it. Offline-first users will ask; see recipe R12. |
| `reference/functions/*` (`useQuery`, `useQueries`, `useMutation`, `useIsFetching`, `useMutationState`, `QueryClientProvider`, `queryOptions`, `keepPreviousData`, `hashKey`, `matchQuery`, `replaceEqualDeep`, …) | `reference/api.md` → pub.dev dartdoc; the name map in `coming-from-react-query.md` | Partial | Adapted. `useSuspense*`, `HydrationBoundary`, `QueryErrorResetBoundary`, `dehydrate`/`hydrate`, `useIsRestoring`, `usePrefetch*` and `experimental_streamedQuery` are N/A. |
| `reference/classes/*` (`QueryClient`, `QueryCache`, `MutationCache`, `QueryObserver`, `InfiniteQueryObserver`, `QueriesObserver`, `Query`, `Mutation`, `CancelledError`) | dartdoc only | Partial | Yes, all exist in `query_kit`. The `QueryCache`/`MutationCache` config callbacks (`onError`/`onSuccess`/`onSettled`/`onMutate`, `query_cache.dart:173`, `mutation_cache.dart:100`) are **not mentioned anywhere in the site's prose**. Only the showcase's `global_callbacks` screen covers them. |
| `reference/interfaces`, `type-aliases`, `variables` | dartdoc | Partial | Mostly adapted into sealed option types. `focusManager`, `onlineManager` and `notifyManager` are per-client. |
| ESLint plugin (exhaustive-deps, stable-query-client, …) | none | N/A | Adapted, low priority: the `strict-inference` advice in `first-query.md` is the analogue. A "stable QueryClient" rule (never build the client in `build`) is worth a sentence in Important defaults. |
| Examples (simple, basic, auto-refetching, optimistic, pagination, load-more, max-pages, default-query-fn, playground, prefetching, offline, …) | `project/examples.md` → showcase | Partial | Yes. The showcase mirrors 14 upstream examples, but the site only lists screen ids. No example page shows code or a live demo. `star-wars`, `rick-morty` and `algolia` are app-shaped; the task manager plays that role. `suspense`, `nextjs*`, `react-router`, `shadow-dom`, `devtools-panel`, `chat` (streaming) and `batching` are N/A. |

**Count.** Of the 38 upstream React guides, 6 are N/A: ssr, advanced-ssr, suspense and the three
migrating guides. Of the 32 that apply, **7 are fully covered, 19 partially and 6 not at all**
(important-defaults, background-fetching-indicators, scroll-restoration, request-waterfalls,
caching, does-this-replace-client-state).

---

## 2. Proposed information architecture

Modelled on TanStack's sidebar. Principles:

- One concept per page, named in the reader's words.
- Every guide page carries a live demo from `examples/showcase/lib/features/*`, plus the
  JavaScript name in a small "In React Query" aside, so that `coming-from-react-query.md`
  becomes an index rather than the only place the mapping lives.
- Every Dart fence keeps the existing `snippet="…"` mechanism
  (`examples/doc_snippets/test/site_fences_test.dart`), so new pages cannot rot.

### Prerequisite for live demos

The showcase is a web-buildable app (`examples/showcase/web`, routes `/<id>` in `lib/routes.dart`
via `onGenerateRoute`, `initialRoute` parameter in `lib/main.dart:60`). To embed it on a static
site:

- Move `examples/showcase/test/fake_backend.dart` (532 lines; a dio `HttpClientAdapter`) into
  `lib/` behind `--dart-define=BACKEND=fake`. It currently imports `dart:io` for one `File` read
  of the seed (line 135), which must become an asset or a const.
- Build `flutter build web --dart-define=BACKEND=fake` into `website/static/showcase/`.
- Add an MDX component, `<LiveDemo feature="load-more" height={560} />`, rendering
  `<iframe src="/flutter_query/showcase/#/load-more">` with a "view source on GitHub" link to
  `lib/features/load_more/`.
- The contract test (`backend_contract_test.dart`) already proves the fake matches the server,
  so a fake-backed demo stays honest.
- Latency and failure knobs (`playground`) keep working because they are fake-side.
- Build one Flutter web bundle and deep-link by route. Do not build one bundle per page.

### Sidebar

**Getting started**

| Slug | Title | Content | Comes from | Live demo |
|---|---|---|---|---|
| `/docs/overview` | Overview | The server-state problem (upstream's `overview.md` adapted), what query_kit does, the 20-line example, a short honest "port, not affiliated, AI-written" callout linking to Credits. **No test counts.** | `intro.md` (trimmed) | `simple` |
| `/docs/installation` | Installation | As now, minus "From a checkout" (move to CONTRIBUTING) | `getting-started/installation.md` | none |
| `/docs/quick-start` | Quick start | Provider → query → read → mutate → invalidate; push the four "worth noticing" asides to the concept pages | `getting-started/first-query.md` | `basic` |
| `/docs/important-defaults` | Important defaults | **New.** staleTime zero; gcTime 5 min; `RetryPolicy.times(3)` with exponential backoff for queries, and what mutations default to; refetch on mount/focus/reconnect `ifStale`; structural sharing on; **nothing installed for connectivity**; `inactive` platform mapping; provider mounts but does not dispose; `client.query` without retry = one attempt; "create the client once, never in `build`". | scattered: `options.md`, `lifecycle-and-connectivity.md`, `the-query-client.md#the-mount-contract` | `stale-and-gc`, `playground` |
| `/docs/coming-from-react-query` | Coming from React Query | The name map (keep) + Suspense/SSR/devtools/persistence answers | `reference/coming-from-react-query.md` | none |
| `/docs/dart-type-safety` | Type safety in Dart | Sealed results, one key one exact type (`QueryDataTypeError`), two options shapes, `strict-inference` | `first-query.md`, `options.md#two-shapes`, `pure-dart.md#what-is-dart…`, `the-query-client.md` danger box | `diagnostics` |

**Guides & concepts** (one page per concept; upstream order)

| Slug | Title | Content | From | Live demo |
|---|---|---|---|---|
| `guides/queries` | Queries | Result states, `status` × `fetchStatus`, `isLoading`/`isRefetching`/`isPaused`, `staleData` in `QueryError` | `first-query.md` §3, `reading-a-query.md` intro | `simple` |
| `guides/reading-queries-in-widgets` | Four ways to read a query | The four equal call styles and the "picking one" table. The element-bound release rules move to an "Advanced: how reads are released" subsection or page. | `reading-a-query.md` | `four-call-styles` |
| `guides/query-keys` | Query keys | `QueryKey`, value equality, hierarchy and prefix, key factories, `append`, the record-of-list trap | `first-query.md`, `troubleshooting.md` (last entry) | `invalidation-and-filters` |
| `guides/query-functions` | Query functions | Must throw on failure (dio vs `package:http`), the context (`signal`, key, `meta`), cancellation wiring | `first-query.md`, `the-query-client.md#cancellation` | `cancellation` |
| `guides/query-options` | Describing a query once | Options functions, `QueryObserverOptions` vs `QuerySelectOptions`, `withSelect`, what `null` means | `options.md` intro and #two-shapes | `select-and-sharing` |
| `guides/network-mode` | Network mode and offline | `NetworkMode`, paused queries and mutations, `resumePausedMutations` | `lifecycle-and-connectivity.md#network-mode`, `mutations.md#offline` | `offline` |
| `guides/parallel-queries` | Parallel queries | Several reads in one build; `QueriesBuilder` for dynamic lists | `collections-and-side-effects.md` | `parallel-queries`, `query-collections` |
| `guides/combining-queries` | Combining queries | `combine`, `optional()`, `combineWith`, `CombineMemo` + `keys:` | `collections-and-side-effects.md#combining…` | `combine` |
| `guides/dependent-queries` | Dependent queries | `Enabled`, `Enabled.when`, waterfalls warning | `options.md#enabled` | `dependent-queries` |
| `guides/background-fetching-indicators` | Background fetching indicators | `isFetching`, `IsFetchingController`, a global progress bar | **new** (coming-from row only) | `parallel-queries` (global fetching count) |
| `guides/window-focus-refetching` | App focus and refetching | The lifecycle mapping, `isAppShown`, `observeAppLifecycle`, `refetchMinBackgroundDuration`, a custom focus source | `lifecycle-and-connectivity.md` | `focus-refetch` |
| `guides/connectivity` | Connectivity | `OnlineStatus`, the connectivity_plus sample, a link is not reachability | `lifecycle-and-connectivity.md#connectivity` | `offline` |
| `guides/polling` | Polling | `RefetchInterval`, background polling, giving up after N failures (`consecutiveErrorCount`), poll until confirmed | `options.md#refetch-triggers`, `troubleshooting.md` (first entry) | `auto-refetching` |
| `guides/disabling-queries` | Disabling and lazy queries | `Enabled.no`, lazy search, `skipToken` mapping, manual `refetch()` | `options.md#enabled` | `dependent-queries` |
| `guides/query-retries` | Retries | `RetryPolicy`, `RetryDelay`, `failureCount`/`failureReason` | `options.md#retries` | `retry` |
| `guides/paginated-queries` | Paginated queries | `PlaceholderData.keepPrevious()`, why `id:` is needed, prefetching the next page | `options.md`, `reading-a-query.md#querymixin`, `infinite-queries.md` | `pagination` |
| `guides/infinite-queries` | Infinite queries | As now + `ListView.builder`/sliver recipe | `guides/infinite-queries.md` | `load-more`, `max-pages` |
| `guides/initial-query-data` | Initial data | `InitialData`, `initialDataUpdatedAt`, seeding from another query's cache | `options.md#initial…` | `initial-and-placeholder` |
| `guides/placeholder-query-data` | Placeholder data | `PlaceholderData`, `isPlaceholderData` | same | `initial-and-placeholder` |
| `guides/mutations` | Mutations | `mutate`/`mutateAsync`, callbacks, `simple`, a mutation outlives its widget | `mutations.md` (first half) | `mutations` |
| `guides/query-invalidation` | Query invalidation | What invalidation does, `refetchType`, prefix vs `exact` | **new**, using `the-query-client.md#filters` | `invalidation-and-filters` |
| `guides/invalidations-from-mutations` | Invalidation from mutations | `onSuccess` invalidate, returning the future keeps `pending` | `first-query.md` §4, `mutations.md` tip | `mutations` |
| `guides/updates-from-mutation-responses` | Updating from mutation responses | `setQueryData`/`updateQueryData` in `onSuccess`, the one-type rule on writes | `the-query-client.md#reading-and-writing…` | `optimistic-updates` |
| `guides/optimistic-updates` | Optimistic updates | Both shapes, `cancelQueries` first, rollback | `mutations.md#optimistic-updates` | `optimistic-updates`, `playground` |
| `guides/mutation-scopes` | Serialising writes | `MutationScope`, the `onMutate`-at-enqueue trap, deadlocks | `mutations.md#serialising…`, troubleshooting (two entries) | `mutations` |
| `guides/cancelling-mutations` | Cancelling a mutation | `mutationFnWithContext`, `cancel()`, "cancelling is failing" | `mutations.md#what-the-function…` | `mutation-cancel` |
| `guides/mutation-state` | Mutation state across the app | `MutationStateController` (+`typed`), `isMutating` | `mutations.md`, `collections-and-side-effects.md` (these two currently **duplicate** each other) | `mutation-state` |
| `guides/query-cancellation` | Query cancellation | `QueryCancelToken`, dio and `http` bridges, `cancelQueries` semantics | `the-query-client.md#cancellation` | `cancellation` |
| `guides/scroll-restoration` | Scroll position | Cached data renders synchronously; `PageStorageKey` | **new** | `load-more` (navigate away and back) |
| `guides/filters` | Filters | `QueryFilters`/`MutationFilters` fields, `predicate`, `find` exact vs bulk prefix | `the-query-client.md#filters` | `invalidation-and-filters` |
| `guides/request-waterfalls` | Performance and request waterfalls | Nested fetching widgets, dependent chains, prefetch on tap and in routes | **new** | `prefetching` |
| `guides/prefetching` | Prefetching and router integration | `client.query(...).ignore()`, `revalidateIfStale`, go_router | `the-query-client.md#fetching` | `prefetching` |
| `guides/caching` | Caching, step by step | Upstream's lifecycle walkthrough over `StaleTime`/`GcTime` | **new** | `stale-and-gc`, `cache-inspector` |
| `guides/render-optimizations` | What rebuilds, and when | As now, minus the internal counts | `rebuilds.md` | `select-and-sharing`, `build-when` |
| `guides/structural-sharing` | Structural sharing | Currently half of `options.md`. `==`/`hashCode`, `StructurallyShareable`, lists/maps/sets, `noStructuralSharing()` | `options.md#structural-sharing` | `select-and-sharing` |
| `guides/default-query-function` | Default query function | `setQueryDefaults(queryFn:)` deriving from the key | `the-query-client.md#defaults` | `default-query-function` |
| `guides/global-callbacks` | Global callbacks and `meta` | `QueryCache(onError:)`, `MutationCache(...)`, `meta` (**new**, only in the showcase today) | none | `global-callbacks` |
| `guides/side-effects` | Side effects in widgets | `QueryListener`/`MutationListener`, `listenWhen` | `collections-and-side-effects.md#side-effects` | `four-call-styles` or `global-callbacks` |
| `guides/debugging` | Inspecting the cache (devtools stand-in) | `queryCache.subscribe`, `debugString`, build a small inspector | **new** | `cache-inspector`, `diagnostics` |
| `guides/testing` | Testing | As now + retries off, faking the transport, testing mutations and errors, `QueryController` tests | `guides/testing.md` | none |
| `guides/pure-dart` | Without Flutter | As now | `guides/pure-dart.md` | none |
| `guides/does-this-replace-state-management` | Does this replace Riverpod/Bloc? | **New.** Server state vs client state; living alongside the others | `reading-a-query.md` (one sentence) | none |

**Examples** (one page per showcase feature, TanStack-style: live demo on top, source below)

- `/examples/<feature>` for all 30 features in `examples/showcase/lib/features/`. Each page takes
  its prose from the feature's own `///` header, which already says "Upstream's `X` example" and
  what it shows. It embeds `<LiveDemo>` and links to the upstream React example it mirrors
  (`query/examples/react/<name>`).
- `/examples/task-manager`: the whole app, with the cache policy file (`lib/src/queries.dart`)
  walked through.
- `/examples/one-file-tour`: `packages/query_kit_flutter/example`.

**Cookbook / real-project recipes**: see §3; one page each under `/cookbook/…`.

**API reference**

- `/reference/api`: rebuilt as in §5.
- `/reference/query-client`, `/reference/options`, `/reference/result-types`,
  `/reference/widgets`, `/reference/controllers`: hand-written summary pages in upstream's
  reference style, each linking into dartdoc.
- `/reference/feature-matrix`: keep.
- `/reference/differences-from-tanstack`: **new**, a user-facing rewrite of the
  PORTING_NOTES divergence table, without ticket numbers.
- `/reference/troubleshooting`: keep, cleaned (see §4).

**Project**

- Credits (keep).
- How fidelity is proven (keep; move the numbers to one generated place).
- Releasing: **remove from the user site**; it belongs in `docs/releasing.md`.
- Changelog link, Contributing link.

---

## 3. Real-project recipes (the cookbook)

Neither the site nor TanStack spells these out for Flutter. "Exists" means the pattern is
already implemented somewhere in the repository.

| # | Recipe | Content | Exists today? |
|---|---|---|---|
| R1 | **Wiring dio (and `package:http`)** | Base client, `CancelToken` bridge via `signal.onCancel`, error unwrapping, `http` not throwing on non-2xx | **Yes, in code**: `examples/showcase/lib/shared/api.dart` and `examples/task_manager/lib/src/api.dart`. The file header says "'how do I wire dio to this?' is the part a reader most wants to lift out whole". Site: a 4-line fragment in `the-query-client.md#cancellation`. `http`: nowhere. |
| R2 | **Auth: 401, token refresh, sign-out** | A dio interceptor refreshes tokens; `RetryPolicy.when` excludes 401/403; on sign-out, `client.cancelQueries` + `client.clear()` (or a new client under a new provider key); per-user key prefixes | **No.** `first-query.md` mentions "`client.clear()` … at sign-out" only. `troubleshooting.md` has the related "removeQueries then readers refetch" disconnect entry. |
| R3 | **Pull-to-refresh** | `RefreshIndicator(onRefresh: () => controller.refetch())` or `client.refetchQueries(...)`; which future to await; not blanking the list (`staleData`) | **No** (no `RefreshIndicator` anywhere in the repo). |
| R4 | **Search as you type** | Key includes the needle, debounce, cancel the old fetch, `keepPrevious` placeholder, `Enabled.no` for the empty query | **Yes**: showcase `cancellation` screen (`lib/features/cancellation/cancellation_screen.dart`, "search-as-you-type as the everyday case"). The task manager also debounces its search (`lib/src/app_state.dart`). Site: none. |
| R5 | **List → detail cache seeding** | Seed per-item entries from the list fn with `setQueryData`; `InitialData.compute` from `getQueryData(listKey)`; why `initialData` alone is not enough | **Yes**: `examples/task_manager/lib/src/queries.dart` lines 40-60 (with the reasoning in comments) and the showcase `basic` screen (the `cached` badge). Site: none. |
| R6 | **Forms with mutations and server validation errors** | `mutateAsync` from a `Form`, mapping a 422 body to field errors, disabling Save while `isPending`, resetting on success, pop on success via per-call callbacks | **Partial**: `mutations.md` shows `Navigator.pop` in a per-call callback. There is no validation-error pattern anywhere. |
| R7 | **A global error snackbar / toast** | `QueryCache(onError:)` + `MutationCache(onError:)` with a `GlobalKey<ScaffoldMessengerState>`, `meta` to opt out per query, only for background refetch errors (`staleData != null`) | **Partial**: showcase `global_callbacks` screen. `QueryListener` snackbar sample in `collections-and-side-effects.md`. The site never mentions the cache-level callbacks. |
| R8 | **Infinite scrolling ListView / slivers** | `ListView.builder` with row widgets, the level-triggered scroll listener, loader row at the end, `SliverList`, pull-to-refresh on an infinite query | **Mostly**: `infinite-queries.md#scroll-triggered-loading` and the showcase `load_more` screen. Row-widget rule in `reading-a-query.md`. The pieces exist on three pages but are not joined into one recipe. |
| R9 | **App lifecycle and connectivity wiring** | `connectivity_plus` + `OnlineStatus.stream(initial:)`; desktop focus; a reachability probe | **Yes**: `lifecycle-and-connectivity.md`. Keep it, and cross-link it as a recipe. |
| R10 | **Testing a screen** | The harness, faking the API (a dio adapter or an injected API object), retries off, error and empty states, mutation success/failure, and time for `staleTime`/polling | **Partial**: `guides/testing.md` (teardown, pump rules). Fuller in `examples/showcase/test/harness.dart` + `fake_backend.dart` and `examples/task_manager/test/acceptance_test.dart`, which the site names only. |
| R11 | **Living alongside Riverpod / Bloc / Provider** | `QueryController` inside a Riverpod provider (`ref.onDispose(controller.dispose)`); a Cubit subscribing to a controller; which state belongs where | **No.** One sentence in `reading-a-query.md` ("drops into … `provider`, `riverpod` and `bloc` unchanged"). |
| R12 | **Offline-first** | `NetworkMode.offlineFirst`, paused mutations and resume, mutation defaults needing `networkMode` too, and a hand-rolled persistence via `queryCache.subscribe` + `setQueryData` on startup (`Query.setState` door) | **Partial**: `lifecycle-and-connectivity.md`, `mutations.md#offline`, `troubleshooting.md` ("My offline-tolerant app still pauses its writes"), showcase `offline`. Persistence: none. |
| R13 | **Dependency injection of the QueryClient** | `QueryClientProvider` vs `QueryClientProvider.create`, `QueryClientProvider.of/maybeOf/read`, get_it, per-test clients, per-user clients (key the provider), never create in `build` | **Partial**: `first-query.md` (`create`). `QueryClientProvider.read` (exists at `query_client_provider.dart:158`) is **undocumented on the site**. No get_it mention. |
| R14 | **Routing: go_router / Navigator integration** | Prefetch in `redirect`/on tap, reading route params into keys, refetch when a route becomes visible again (`RouteAware`), dialogs reading through their own context | **Partial**: the dialog rule is in `troubleshooting.md`. Nothing else. |
| R15 | **Real-time: WebSocket/SSE pushing into the cache** | `setQueryData`/`invalidateQueries` from a stream subscription; when to prefer polling | **No.** (`streamedQuery` is not ported, which makes this recipe more important.) |
| R16 | **Poll until a job/device confirms** | `RefetchInterval.dynamic` over the query's own state, a separate requested-value field, stop on confirmation, give up after N | **Yes**: task manager reminder switch (README "What to look at"), `options.md` give-up sample, `troubleshooting.md` first entry. |
| R17 | **Device / IoT disconnect** | Remove readers before `removeQueries`; a closed transport that refuses | **Yes**: `troubleshooting.md` ("I removed a device's queries…"). Better framed as a recipe. |
| R18 | **Multi-account / sign-out cache reset** | Per-user key prefix vs a new client; clearing pending mutations | **No.** |
| R19 | **Normalised cache vs per-entity keys** | Map-vs-list sharing trade-off, `StructurallyShareable` wrappers (freezed) | **Partial**: `options.md#structural-sharing`. |
| R20 | **Using freezed / json_serializable models** | `==`/`hashCode` needed; a wrapper class is a leaf; `StructurallyShareable` | **Partial**: `options.md` mentions "the shape freezed suggests". |

---

## 4. Quality problems in the existing pages

### 4.1 Stale or inconsistent facts

| Where | Problem |
|---|---|
| `website/docs/intro.md` §"The bet" | "**783** tests in the core … 779 JS", "**144** tests in the binding", "**279** … two examples", "**187** Playwright", "**23** bugs". Current per CLAUDE.md: core 826/822, binding 287. |
| `website/src/pages/index.tsx:27-41` | The same stale 783/144/279/187, **and "22 bugs"**, which contradicts intro.md and fidelity.md's "23". The comment says "run of every suite, 2026-09-12". |
| `website/docs/project/fidelity.md` §"The numbers" | 783/779, binding 144, showcase 222 + 177, task manager "9 Playwright" (CLAUDE.md: 10), "33 bounded confidence sequences" (CLAUDE.md: 32). The prose "re-measured on 2026-09-12 after the pre-release deep-dive review, its final review and the bounded confidence assessment…" is a log entry. **Recommendation:** keep numbers in one generated JSON (CI writes it) or drop them from user pages. They have been wrong in every round so far. |
| `project/fidelity.md` §"What review found", `project/credits.md` | "Nine rounds of external deep-dive review … roughly 100": outdated since the 2026-09-12 pre-release review and the 2026-09-23 release review with its five passes. |
| `project/examples.md` | Says "30 of them" but the table lists **28**: `combine` and `mutation-cancel` are missing. |
| `reference/coming-from-react-query.md` §"See it running" | Also lacks `combine`, `mutation-cancel` and `build-when`. |
| `getting-started/installation.md` | "No dependency beyond Flutter itself": true in spirit, but `query_kit` depends on `clock` and `meta`. Say "no third-party dependency". |
| `reference/api.md` | "`option_values.dart` for the sealed types": a source file name, not a dartdoc page; dartdoc has no per-file pages. |
| `mutations.md` and `collections-and-side-effects.md` | Both have a "Cache-wide mutation state" section that **duplicates** the same content, with a slightly different sample. |
| `options.md#initial-and-placeholder-data`, `reading-a-query.md#querymixin` | `keepPrevious` needs `id:` in two of four styles. Stated, but only as a side note; users will hit it (see the paginated-queries page proposal). |

**API name spot check.** I compared every identifier the site uses against `packages/*/lib`:
`QueryClientProvider.create`, `maybeOf`, `isAppShown`, `observeAppLifecycle`,
`OnlineStatus.fixed/stream`, `AppFocusManager(refetchMinBackgroundDuration:)`,
`revalidateIfStale`, `getInfiniteQueryData`, `updateQueriesData`, `CombineMemo`, `keys:`,
`combineWith`, `optional()`, `StructurallyShareable`, `replaceEqualDeep`, `noStructuralSharing`,
`withSelect`, `consecutiveErrorCount`, `IsFetchingController`, `MutationStateController.typed`,
`MutateCallbacks`, `mutationFnWithContext`, `onMutateResult`, `client.observe`,
`observeInfinite`, `flatten<T>()`, `setEventListener`, `QueryObserver(client, options)` and about
40 more. **All resolve.** No page names a removed API; the removed
`combineWith2`/`typedMutationSelection`/`canFetch` do not appear on the site.

Public API that the site's prose never mentions: `QueryCache({onSuccess,onError,onSettled})`,
`MutationCache({onMutate,…})`, `QueryClientProvider.read`, `client.getQueryState`,
`isLoading`/`isRefetching`/`isPaused`/`isLoadingError`/`isRefetchError`,
`FetchStatus`/`QueryStatus`, `QueryCacheEvent` subtypes, `NotifyManager` batching, and
`CancelledError` beyond one mention.

### 4.2 Review history, tickets and internal IDs in user-facing docs (flag every one)

**Site pages:**

| File | Text to remove or rewrite |
|---|---|
| `guides/mutations.md` (Narrowing rebuilds) | "since [#67](…/issues/67), the two keyless reads". A ticket link in a user guide. |
| `guides/infinite-queries.md` (Paging lives on the controller) | "which was not true of an earlier version and is now a regression test". |
| `guides/infinite-queries.md` (Scroll-triggered loading) | "Worth stating because the showcase got it wrong once and CI caught it". |
| `guides/rebuilds.md` (On a mutation) | "Across the binding, showcase and task manager suites that is 91 questions the mutation reads would be asked, against zero notifications…". Internal measurement. |
| `guides/rebuilds.md` (Why not upstream's trick) | "This is one of the recorded divergences; the reasoning is in the divergence table at the end of PORTING_NOTES.md". Points users into a 6,589-line review log. |
| `guides/options.md` (Two shapes) | "(ADR-0001)"; the paragraph "A single type with an optional `select` carried `TData` only in that one optional field…" is design history. |
| `guides/testing.md` | ADR-0002 link and its rationale ("so … the package page shows every platform"), and "tests use `testFakeAsync` from `test/test_utils.dart`": a repo-internal helper users cannot import. |
| `guides/reading-a-query.md` (intro) | "this was the maintainer's explicit ruling, and it holds for everything built on top". Governance, not guidance. The same applies to "which is what a `ValueListenable` is for… not a fourth exception" (also in `rebuilds.md`), which argues with a past review. |
| `reference/troubleshooting.md` intro | "The first entries come from the library's first integration into a real app (2026-09-19); each says where it was learned." |
| `reference/troubleshooting.md` | "*Learned in: the BR64 integration, where polling paused…*", "*Learned in: the BR64 integration's disconnect path.*", "*Learned in: the release review (2026-09-23).*". Also private app type names in an example: "`List<Ingress>` … `List<EnOceanDeviceDto>`". |
| `reference/troubleshooting.md` (list item entry) | "The trade is deliberate: an earlier rule that released per run dropped the subscriptions of data still on screen." History. |
| `reference/coming-from-react-query.md` intro | "each row there names the ticket that decided it". |
| `reference/feature-matrix.md` §"The divergences" | "names the ticket that decided each one"; ADR-0001 link. |
| `reference/api.md` §"The other reference" | Sends API readers to the ported test suite and PORTING_NOTES as "the more honest document". |
| `project/fidelity.md` | Review rounds, "the ninth", dates, "re-measured on 2026-09-12". Acceptable on a Project page but should be summarised, not logged. |
| `project/credits.md` | "every decision ticket is settled by the agent… resolution comment…", "Nine rounds…". Acceptable as project context; trim it. |
| `project/releasing.md` | The whole page (rename tool `tool/rename_packages.dart`, "It is decided now", tag procedure) is maintainer documentation. Remove it from the user sidebar. |
| `intro.md` | Test-count table and "23 bugs found by porting" as the first thing a user sees. Move to Fidelity. |

**Dartdoc that pub.dev will render** (outside the site but inside "the API reference"):

- `grep` finds **~202 dartdoc lines in `packages/query_kit/lib` and ~98 in
  `packages/query_kit_flutter/lib`** citing reviews, dates, C-IDs, issue URLs, BR64 or V-IDs. Some
  are on private members and will not render, but many are public.
- Examples: `query_kit.dart:12-14` (the **library landing page**: "ninth review, 2026-09-10,
  C23", "fourth review, 2026-09-09"); `cancel_token.dart:5` (issue URL); `cancel_token.dart:64`
  ("ninth review, … C16"); `retryer.dart:40,152,250`; `mutation.dart:47,89,237,248,478,553`
  ("release review, 2026-09-23, L4-6", "MU-03", "F5"); `hashing.dart:14` ("round-3 reviews,
  R3-1"); `infinite_query.dart:78` ("C20").
- `query_kit_flutter.dart:6` links issue #21 on the library page.
- Package READMEs (`packages/query_kit/README.md:30`, `packages/query_kit_flutter/README.md:29`):
  "nine external deep-dive reviews". Stale, and review-ish.

Recommendation: a mechanical pass that moves those parentheticals into `//` comments (kept for
maintainers) and keeps the `///` text purely behavioural. Then make it a CI grep gate, e.g. fail
on `///.*\b(review|C\d{1,2}|#\d+|20\d\d-\d\d-\d\d)\b` in `lib/` and `website/docs/guides`.

### 4.3 Pages that read as internal rather than user-facing

- `reading-a-query.md` spends about 60% of its length on element-bound release rules
  (`LayoutBuilder` own context, `InheritedWidget` signals, item builders). This is correct and
  needed, but it belongs on an "Advanced: how `context.query` subscriptions are released" page.
  The main page should state the two rules users need: read in `build`, and one widget per list
  row or dialog.
- `options.md#retries` paragraphs on "captured when a fetch … starts", "a mutation's function is
  read per attempt", and the options-equality/`setOptions` defaulting pass are implementation
  notes.
- `mutations.md#identity` is an assertion specification (which fields are compared by value or
  by variant). Move it to the reference or an advanced note.
- `rebuilds.md` "A controller has none, on purpose" and "QueriesBuilder has none either" argue
  design decisions rather than guide use.
- `the-query-client.md` opens with "Upstream has `fetchQuery`, `prefetchQuery` … all three now
  deprecated there". That is a comparison, and it belongs in Coming from React Query.

---

## 5. `website/docs/reference/api.md`: current state and target

**Current (52 lines).** It says the reference is generated. It links
`pub.dev/documentation/query_kit/latest` and `…/query_kit_flutter/latest`, which will 404 until
the first publish. It explains `dart doc` locally and gives a 7-row "where to start reading" table
that names a source file (`option_values.dart`). It ends by sending readers to the ported test
suite and PORTING_NOTES. There is no content of its own, no per-symbol pages, and no link from any
guide to a specific dartdoc symbol.

Dartdoc itself: **no `dartdoc_options.yaml` and zero `{@category}` tags** in either package, so
pub.dev renders two flat lists of about 200 classes each. The core list includes all the
`Query*Action`/`Mutation*Action`, `*ObserverRef` and `FetchContext` plumbing that
`query_kit.dart`'s own doc says is "read-only from outside". Only 27 `/// ```dart` examples
exist across both `lib/` trees.

**What the API reference section should look like** (upstream's reference is generated TypeDoc
grouped as Functions / Classes / Interfaces / Types / Variables; Dart's equivalent is dartdoc
categories plus a thin hand-written layer):

1. **Dartdoc categories.** Add `dartdoc_options.yaml` in each package with `categoryOrder` and
   `{@category}` on every public type:
   - Client: `QueryClient`, `DefaultOptions`, `QueryDefaults`, `MutationDefaults`, the managers
   - Query options: both shapes, the infinite shapes, every sealed option value
   - Results: `QueryResult` family, `MutationResult` family, `CombinedResult`, `InfiniteData`
   - Observers
   - Caches and events
   - Filters
   - Errors: `QueryDataTypeError`, `Missing*FunctionError`, `CancelledError`
   - Structural sharing
   - Advanced / internals: actions, refs, `FetchContext`
   - Binding: Provider · Reading (the four styles) · Controllers · Builders · Listeners ·
     Collections · Connectivity

   Also add `{@template}`/`{@macro}` so the four call styles share one doc block, and an example
   block on every entry point (`QueryClient.query`, `invalidateQueries`, `setQueryData`,
   `QueryBuilder`, `context.query`, `watchQuery`, `MutationOptions.simple`,
   `InfiniteQueryObserverOptions`).
2. **Hand-written reference pages on the site** (upstream's `QueryClient`, `useQuery` and
   `useMutation` reference pages are tables of every option and return field). For query_kit:
   - `reference/query-client`: every method, a one-line description and a link to dartdoc.
   - `reference/query-options`: every field of `QueryObserverOptions`/`QuerySelectOptions`/
     `InfiniteQuery*Options`, with default, type and JS name. This makes the name map a column,
     not a separate page.
   - `reference/query-result`: every field and getter, and which case it lives on.
   - `reference/mutation-options-and-result`.
   - `reference/widgets-and-controllers`: the 4×3 matrix (query / infinite / mutation × four
     styles) with signatures, plus the listeners, `QueriesBuilder`, `IsFetchingController`,
     `MutationStateController` and `QueryClientProvider` (`create`, `of`, `maybeOf`, `read`).
   - `reference/errors`: each thrown error, when and why, which is the content of the
     `diagnostics` screen.

   Every Dart fence stays under `snippet=` / `site_fences_test.dart`. A generated check that each
   reference table lists every public member (compare against the barrel's exports, e.g. with
   `dart doc --json` or the analyzer) keeps it from drifting, as C52 showed happens with options.
3. **`reference/api.md` becomes an index**: the category list with pub.dev deep links (versioned
   `/1.0.0/`, not `/latest/` until published), plus "Differences from TanStack Query", a
   user-facing extraction of the PORTING_NOTES divergence table. The "ported test suite is the
   more honest document" section goes to the Fidelity page.
4. **Scrub review-log text out of `///`** before 1.0.0 is published, because pub.dev keeps every
   version's docs (§4.2).
