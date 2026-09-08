# Initial Dart Port of TanStack query-core — plan

> **Superseded on 2026-09-08.** This was the plan of record for the previous
> attempt. The port is now re-planned as the wayfinder map on
> [GitHub issue #1](https://github.com/KoTTi97/flutter_query/issues/1); this
> file is kept as prior art and is no longer executed. M7–M9 will not happen
> under this plan.
>
> **Status at freeze:** M0–M6 complete. `query_core` is done: keys, managers, retryer,
> options, query, cache, observer, client, mutations — **372 tests**, with all
> six priority upstream suites ported (279 of 355 upstream cases; the rest are
> enumerated with reasons). M7 was next when the plan was frozen.
> The design decisions this plan refers to are in [DESIGN.md](DESIGN.md).
> Per-test fidelity is audited in
> [`packages/query_core/test/PORTING_NOTES.md`](packages/query_core/test/PORTING_NOTES.md).

---


## Context

Christian is porting TanStack Query to Dart/Flutter. The design doc ([DESIGN.md](DESIGN.md), decisions D1–D13) is settled; the MVP bar is a Flutter equivalent of the react-demo sensor app, which runs against the standalone Express gateway at `react-demo/server/` (port 5174, plain JSON REST under `/api`, scripted failures: rename "fail" → 500, every 2nd delete → 500, matter-forwarding confirms after ~3 s). `flutter-port/` is empty; Dart 3.11 + Flutter SDK installed.

User-confirmed scope: **full MVP path** (pure-Dart `query_core` → `flutter_query` binding → `sensor_demo` app) with **faithful per-module ports of the upstream test suites** (~340 tests across the six priority suites — the project's differentiator).

Reference implementations:
- Upstream core: `query/packages/query-core/src/` (query.ts, queryObserver.ts, queryClient.ts, retryer.ts, mutation*.ts, queryCache.ts, notifyManager.ts, utils.ts + `__tests__/`).
- Cache policy to reproduce exactly: `react-demo/react/src/queries.ts` + `api.ts` (list seeds per-sensor entries; select-derived header; functional initialData from cached lists; 500 ms poll while `matterForwardingPending`; 3 optimistic mutations with rollback).

## Corrections to the design doc discovered during planning (apply, and sync the artifact in M9)

1. **D4 refinement:** upstream reverts unconditionally on explicit `cancel({revert:true})` (e.g. `cancelQueries`); `#abortSignalConsumed` only decides, on last-observer-removal, between hard-cancel (`cancel({revert:true})`) and `cancelRetry()` (let the fetch land in cache). Port upstream semantics ([query.ts:362-383](../query/packages/query-core/src/query.ts)).
2. **Drop the `queryHash` string + `queryKeyHashFn`:** `QueryKey` with deep `==`/`hashCode` (DeepCollectionEquality — unordered for maps, matching upstream's sorted-key JSON hash) is directly usable as a `Map` key.
3. **Drop observer-level `throwOnError`** (feeds React error boundaries; no Flutter equivalent). Keep the `throwOnError` *parameter* on `refetchQueries`/`invalidateQueries`.
4. **`continue()` → `resume()`** (Dart reserved word) on Retryer/Mutation.
5. Mutation context generic named `TOnMutateResult` (avoids `BuildContext` confusion).

## Workspace layout (Dart pub workspace)

```
flutter-port/
  pubspec.yaml                  # workspace root (sdk ^3.11.0)
  analysis_options.yaml         # package:lints/recommended + strict-casts/strict-raw-types
  packages/
    query_core/                 # pure Dart; deps: collection, clock, meta; dev: test, fake_async
    flutter_query/              # deps: flutter, query_core; dev: flutter_test
  apps/
    sensor_demo/                # deps: flutter, flutter_query, dio; dev: flutter_test, integration_test
```

## Module map (upstream → `query_core/lib/src/`)

| Upstream | Dart | Note |
|---|---|---|
| types.ts | `option_values.dart`, `query_options.dart`, `query_result.dart`, `filters.dart` | sealed value types + options; sealed results (D7) |
| utils.ts | `utils.dart` + `query_key.dart` | partialMatchKey → `QueryKey.isPrefixOf`; hashKey/shallowEqualObjects/replaceData dropped (==, D5) |
| query.ts | `query.dart`, `query_state.dart` | reducer ported line-for-line |
| queryCache.ts | `query_cache.dart` | `Map<QueryKey, Query>` |
| queryObserver.ts | `query_observer.dart` | no trackResult/getOptimisticResult/notifyOnChangeProps |
| queryClient.ts | `query_client.dart` | MVP surface below |
| retryer.ts | `retryer.dart` + `cancel_token.dart` | class-based; `CancelledError{revert,silent}` |
| mutation*.ts | `mutation.dart`, `mutation_state.dart`, `mutation_cache.dart`, `mutation_observer.dart` | |
| notifyManager.ts | `notify_manager.dart` | microtask coalescing (D8) |
| focusManager.ts / onlineManager.ts | `focus_manager.dart`, `online_manager.dart` | settable singletons; online defaults true |
| subscribable.ts / removable.ts | same names | gcTime max-of-seen; `GcDuration.never` replaces Infinity |
| timeoutManager/environmentManager/hydration/infinite*/queriesObserver/streamedQuery | **dropped** | D10 + MVP exclusions; `Query` keeps the replaceable-`fetchFn` behavior seam for later infinite queries |

`flutter_query/lib/src/`: `query_scope.dart`, `query_client_provider.dart`, `query_builder.dart`, `mutation_builder.dart`, `notify_scheduler.dart`.

## Key designs (settled in planning — follow these)

### Options model (highest-risk piece)
- **Every JS union-typed option becomes a sealed value type**, so `null` on options always means "unset" and merging is plain `??` per field, no sentinels: `StaleDuration` (.zero default/.of/.infinity/.static_/.resolve(fn)), `GcDuration` (.of/.never), `Enabled` (bool or .resolve(fn)), `RetryOption` (.never/.forever/.count/.when — client default `.count(3)`, mutation default `.never`), `RetryDelay` (default min(1s·2ⁿ, 30s)), `RefetchOn` (.never/.ifStale default/.always/.resolve), `RefetchInterval` (.off/.every/.resolve(fn returning Duration?)), `NetworkMode` enum.
- Classes: `QueryOptions<TQueryData>` (cache-level, nullable fields), `QueryObserverOptions<TQueryData, TData>` (adds queryKey required, select, initialData/initialDataUpdatedAt **as functions only**, structuralSharing hook), `QueryDefaults` (untyped bag for client defaults + `setQueryDefaults`, incl. cast-adapted untyped queryFn), and **`DefaultedQueryObserverOptions` — a distinct type replacing the `_defaulted` runtime flag**: `defaultQueryOptions()` short-circuits on `is`-check; `Query`/observer internals accept only the Defaulted type.
- Merge: client defaults + all key-defaults whose key `isPrefixOf` the query key (insertion order, last wins) + per-observer options; then dependent defaults (`refetchOnReconnect` defaults `.never` iff networkMode == always).
- **No skipToken:** skip = `Enabled(false)`; fetch with no resolvable queryFn throws `MissingQueryFunctionError`.

### setQueryData / functionalUpdate
`TData? setQueryData<TData>(QueryKey key, TData? Function(TData? previous) updater, {DateTime? updatedAt})` — function-only updater; **returning null aborts the write** (JS `undefined` parity). Documented invariant: cache values are non-null (aligns with D2 `hasData`; fetch already throws on null data). Writes go through `Query.setData(manual: true)`.

### Test harness (fake_async)
`testFakeAsync(description, (FakeTime time) async {...})`: runs the async body inside a `fakeAsync` zone; `await time.advance(Duration)` posts a request the **outer driver** executes via `fa.elapse` (re-entrant elapse is illegal), interleaving microtask flushes — parity with `vi.advanceTimersByTimeAsync`. Deadlock detection: fail if the body neither completed nor requested an advance. Conventions: core uses `clock.now()` (never `DateTime.now()`), plain `Timer`/`Future.delayed`, no `Stopwatch`. Test utils mirror upstream: counter-based `queryKey()`, `sleep(Duration)`, `mockOnline(bool, body)` via `onlineManager.setOnline`, `executeMutation(client, options, variables)`.

### NotifyManager (D8)
`batch(fn)` with depth counter; `schedule(cb)` queues; flush deferred via overridable `deferFlush` (default `scheduleMicrotask`); flush drains re-entrant schedules in a `while` loop guarded by `_flushScheduled`. State mutations happen synchronously inside `batch`; only listener delivery is deferred. `flutter_query` installs a SchedulerBinding-aware `deferFlush` at `QueryScope` mount: mid-build/layout/paint → `addPostFrameCallback`, else `scheduleMicrotask`.

### Observer / binding
- `QueryObserver` is synchronously authoritative: constructor runs setOptions → updateResult, so `observer.result` is valid before subscribing (first build shows `fetching`). No getOptimisticResult. Notify on any result change (field-wise `==` on sealed results suppresses no-ops; `refetch` function member excluded from `==`).
- `QueryCancelToken` exposed via a **consuming getter** on `QueryFunctionContext` (ports `addSignalProperty`); dio's CancelToken bridges via `addListener`.
- `QueryScope` (root widget): `client.mount()`, AppLifecycleListener → `focusManager.setFocused` (resumed=true, inactive/paused=false), installs the scheduler-aware flush, `unmount()` on dispose. `QueryClientProvider.of(context)`.
- `QueryBuilder<TQueryData, TData>`: State creates observer in `didChangeDependencies` (first run) and subscribes; `didUpdateWidget` → `observer.setOptions`; dispose → unsubscribe → gcTime clock (D11). `MutationBuilder` exposes a `MutationController` (`mutate`, `mutateAsync`, `reset`) + sealed `MutationResult` (Idle/Pending/Success/Error).
- **No connectivity dependency in the binding**: `onlineManager` defaults online; the demo installs a `connectivity_plus` adapter.

### Sealed results (D7)
`QueryResult<TData>` base (status, fetchStatus, isFetching/isPaused/isStale/isRefetching/isEnabled/isFetched, failureCount/failureReason, timestamps, `dataOrNull`/`errorOrNull`, `refetch`); variants `QueryPending` (isLoading), `QuerySuccess` (data), `QueryError` (error, stackTrace, `staleData`/`hasStaleData`). Field-wise `==` excluding functions.

### QueryClient MVP surface
mount/unmount (ref-counted; focus/online: **await resumePausedMutations() then cache.onFocus/onOnline** — ordering is test-pinned), isFetching/isMutating, getQueryData/getQueryState (never create), getQueriesData, setQueryData/setQueriesData, invalidateQueries (batch-mark, then refetch type = refetchType ?? type ?? active; 'none' skips), refetchQueries (cancelRefetch default true; skips disabled/static; **paused queries contribute completed futures** — no offline hang; throwOnError controls rejection), cancelQueries (revert default true; never rejects), removeQueries, resetQueries (snapshot matched set → reset → refetch active over snapshot predicate), fetchQuery/prefetchQuery, `query()` (retry defaults `.never`; cached-if-fresh via isStaleByTime; applies select), resumePausedMutations, set/getQueryDefaults + set/getMutationDefaults (all prefix matches merged, insertion order), defaultQueryOptions/defaultMutationOptions, clear. Excluded: ensureQueryData (deprecated) and all infinite variants.

### Mutations
Every `mutate()` builds a **new** Mutation (no dedup). Scopes: `Map<String, List<Mutation>>`; `canRun` = first pending in scope is self-or-none; `runNext` resumes first paused other; `resumePausedMutations` resumes all paused (scope gating re-serializes). `MutationCache.remove` notifies even if absent (test-pinned); `find` defaults exact:true, `findAll` doesn't. MutationObserver: per-call callbacks fire only if `hasListeners`, **before** subscriber notification, each try/caught with rethrow via `Zone.current.handleUncaughtError` (ports `void Promise.reject`); mutationKey change → reset; pending mutation receives live setOptions. Callback signatures carry `StackTrace` (D1).

## Demo app (`apps/sensor_demo`)

- `models/sensor.dart` — Sensor/SensorType/SensorListResponse/SensorFilters with value `==` (required for D5 rebuild suppression during polls).
- `api/sensor_keys.dart` — mirrors react `api.ts`: `all=['sensors']`, `lists()`, `list(filters)` (filters as Map part), `details()`, `detail(id)`.
- `api/sensor_api.dart` — abstract `SensorApi` + `DioSensorApi` (base URL via `--dart-define`, default `http://localhost:5174/api`; Android emulator `10.0.2.2`); dio CancelToken wired to `ctx.cancelToken`.
- `queries/sensor_queries.dart` — 1:1 port of the react cache policy (shared list options with seeding loop, select header, functional initialData/UpdatedAt via getQueriesData+getQueryState, `RefetchInterval.resolve` poll + `refetchIntervalInBackground: true`, the three optimistic mutations incl. delete's setQueriesData rollback).
- Screens: overview (search/room via ValueNotifier, rows read detail queries), detail (rename form, matter switch rendering `target ?? matterForwarding`, pending badge), connected header.
- Tests: widget tests against a deterministic `FakeSensorApi` (same scripted failures); one `integration_test/live_gateway_test.dart` gated by `--dart-define=LIVE_GATEWAY=1` against the real Express server.

## Milestones (each = one commit/PR; gate: `dart analyze --fatal-infos`, `dart format --set-exit-if-changed`, tests green; skips recorded in `test/PORTING_NOTES.md` with rationale)

| # | Scope | Ported upstream tests |
|---|---|---|
| M0 | Workspace scaffolding (pubspecs, analysis options, empty libs); `dart pub get` resolves | — |
| M1 | query_key, subscribable, removable, focus/online managers, notify_manager, utils; **testFakeAsync harness + test_utils** | utils.test (key subset), notifyManager (adapted), focusManager, onlineManager; harness self-tests |
| M2 | option_values, query_options (+merge), cancel_token, retryer | new retryer_test (pause/resume/cancelRetry/networkMode), new query_options_test (merge chain, insertion-order defaults, Defaulted short-circuit) |
| M3 | query_state, query, query_cache | query.test (~50, skip persister/infinite/hydration), queryCache.test (~16) |
| M4 | query_result (sealed), query_observer | queryObserver.test (~73 minus placeholder/trackedProps/suspense ≈ 15–20 skips) |
| M5 | query_client | queryClient.test (~156 minus infinite/hydration/ensureQueryData ≈ 30 skips) — invalidate/refetch/cancel/reset matrices, defaults merging, focus/online ordering |
| M6 | mutation, mutation_cache, mutation_observer | mutation.test (~28), mutationCache.test (~16), mutationObserver.test (~16) incl. scope serialization |
| M7 | flutter_query: QueryScope, provider, QueryBuilder, MutationBuilder, scheduler-aware flush | new widget tests: first-frame fetching state; mid-build notification safety; dispose→gc; key-switch refetch; lifecycle focus refetch |
| M8 | sensor_demo + FakeSensorApi widget tests; manual run vs gateway | policy suite: seeding (rename shows through with zero detail fetches), select header single fetch, rename-fail rollback, alternating delete rollback, poll start/stop, poll survives unfocus |
| M9 | Polish: dartdoc, exports audit, per-package READMEs, PORTING_NOTES completeness; **sync design-doc artifact** with the corrections above | — |

## Verification (end-to-end)

1. Per milestone: `dart test` in `packages/query_core` (M1–M6), `flutter test` in `packages/flutter_query` (M7) and `apps/sensor_demo` (M8); analyze/format gates throughout.
2. MVP gate (M8): start the gateway (`cd react-demo/server && npm start`), `flutter run` sensor_demo on macOS; walk the react-demo README's demo script (open sensor renders instantly, rename→row updates with one detail refetch, rename "fail" rolls back, matter toggle polls ~3 s then settles, delete rolls back then succeeds, header count derives with no extra request). Compare side-by-side with the React demo on the same gateway.
3. Fidelity audit: `test/PORTING_NOTES.md` lists every skipped upstream test with a reason (excluded feature / JS-specific / behavior delta), zero unexplained skips.
