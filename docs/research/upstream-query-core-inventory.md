# Upstream `query-core` inventory at `50680b98c`, and what moved since `5bb950be8`

- **Date:** 2026-09-08
- **Ticket:** https://github.com/KoTTi97/flutter_query/issues/2
- **Upstream:** https://github.com/TanStack/query, package `packages/query-core`
- **Target revision:** `50680b98c` — `release-2026-08-27-1607-69-g50680b98c`, committed 2026-09-08, `@tanstack/query-core` **5.102.8**
- **Baseline revision:** `5bb950be8` — `release-2026-08-24-1925-6-g5bb950be8`, committed 2026-08-25, `@tanstack/query-core` **5.102.3**
- **Distance:** 89 commits repo-wide, of which **15 touch `packages/query-core`**

All `path:line` citations are at `50680b98c` unless marked `(old)`. Paths are relative to
`packages/query-core/src/` unless they start with `packages/` or `docs/`.

Method: both revisions were exported with `git archive` from a mirror of the local upstream clone
(the clone itself was never checked out or modified), then compared with `git diff --stat`, the
full `git diff`, and a comment-stripped diff of every source module to separate documentation
churn from semantic change. Test case counts are `grep -c` of lines starting with `it(`/`test(`
(including `it.each(`), which is what the ticket asked for; the one `it.each` table
(`__tests__/queriesObserver.test.tsx:740`) is counted as a single case.

---

## 1. Source modules (`packages/query-core/src/*.ts`)

### 1.1 Overview table

Line counts are raw file lines (`wc -l`). "Δ" is the change from `5bb950be8`; the bulk of every
positive Δ is JSDoc added by #11438 (see §3), not behaviour. "Env" marks modules whose reason to
exist is a browser/SSR/Node concern: **B** = browser globals, **S** = SSR/server, **T** = timer
provider abstraction, **–** = pure runtime logic that a Dart port needs as-is.

| Module | Lines | Δ vs old | Env | Role (one line) | Public exports through `index.ts` |
|---|---:|---:|:-:|---|---|
| `types.ts` | 1541 | +142 | – | Every public option/result/context type | `export *` (`index.ts:62`) |
| `queryClient.ts` | 1087 | +363 | – | Facade over both caches; option defaulting; imperative API | `QueryClient` (`index.ts:23`) |
| `query.ts` | 973 | +189 | – | One cache entry: state machine, fetch/retry/cancel, GC | `Query`, `QueryState` (`index.ts:59-60`) |
| `queryObserver.ts` | 902 | +90 | – | Per-subscriber view of a `Query`: result derivation, timers, refetch triggers | `QueryObserver` (`index.ts:24`) |
| `utils.ts` | 616 | +97 | B (one const) | Key hashing/matching, structural sharing, small helpers | `hashKey`, `isServer`, `keepPreviousData`, `matchMutation`, `matchQuery`, `noop`, `partialMatchKey`, `replaceEqualDeep`, `shouldThrowError`, `skipToken`; types `MutationFilters`, `QueryFilters`, `SkipToken`, `Updater` (`index.ts:33-45`) |
| `mutation.ts` | 535 | +108 | – | One mutation: state machine, execute with callbacks, pause/continue | `Mutation`, `MutationState` (`index.ts:55-56`) |
| `queriesObserver.ts` | 402 | +67 | – | Observes N queries, combines results, tracks props | `QueriesObserver`, `QueriesObserverOptions` (`index.ts:20,58`) |
| `hydration.ts` | 394 | +66 | S | Serialise/deserialise cache state (SSR, persistence) | `dehydrate`, `dehydrateQuery`, `hydrate`, `defaultShouldDehydrateMutation`, `defaultShouldDehydrateQuery`; types `DehydratedState`, `DehydrateOptions`, `HydrateOptions` (`index.ts:6-12,50-54`) |
| `queryCache.ts` | 357 | +134 | – | Map of `queryHash → Query`; build/find/notify | `QueryCache`, `QueryCacheNotifyEvent`, `QueryCacheConfig` (`index.ts:21-22,61`) |
| `mutationCache.ts` | 335 | +91 | – | List of mutations + scope serialisation + resume | `MutationCache`, `MutationCacheNotifyEvent`, `MutationCacheConfig` (`index.ts:14-15,57`) |
| `mutationObserver.ts` | 306 | +71 | – | Per-subscriber view of a `Mutation`; `mutate()`/`reset()` | `MutationObserver` (`index.ts:16`) |
| `retryer.ts` | 255 | +18 | – | Retry/backoff/pause loop around one async fn | `CancelledError`, `isCancelledError` (`index.ts:25`) |
| `infiniteQueryObserver.ts` | 251 | +67 | – | `QueryObserver` subclass adding page navigation | `InfiniteQueryObserver` (`index.ts:13`) |
| `timeoutManager.ts` | 243 | +105 | T | Pluggable `setTimeout`/`setInterval` provider | `timeoutManager`; types `ManagedTimerId`, `TimeoutCallback`, `TimeoutManager`, `TimeoutProvider` (`index.ts:26-32`) |
| `infiniteQueryBehavior.ts` | 176 | 0 | – | The `behavior.onFetch` that turns a fetch into page fetches | (not exported; used via `InfiniteQueryObserver` and `QueryClient`) |
| `notifyManager.ts` | 144 | +45 | – | Batches listener notifications; pluggable scheduler | `notifyManager`, `defaultScheduler` (`index.ts:17`) |
| `streamedQuery.ts` | 144 | +24 | – | `queryFn` adapter for `AsyncIterable` streams | `experimental_streamedQuery` (`index.ts:47`) |
| `focusManager.ts` | 142 | +57 | B | Window-focus / visibility signal with overridable source | `focusManager`, type `FocusManager` (`index.ts:3-4`) |
| `onlineManager.ts` | 117 | +47 | B | Online/offline signal with overridable source | `onlineManager`, type `OnlineManager` (`index.ts:18-19`) |
| `index.ts` | 62 | +3 | – | Barrel | — |
| `removable.ts` | 40 | 0 | S (default) | Base class: gcTime bookkeeping + GC timer | (not exported) |
| `environmentManager.ts` | 37 | +12 | S | Overridable `isServer()` | `environmentManager` (`index.ts:5`) |
| `subscribable.ts` | 30 | 0 | – | Base class: listener set with `onSubscribe`/`onUnsubscribe` hooks | (not exported) |
| **Total** | **9089** | **+1796** | | | |

Old total at `5bb950be8`: 7293 lines. The three biggest modules (`types`, `queryClient`, `query`)
are 40% of the package.

### 1.2 Module roles

**`types.ts` (1541 lines).** Pure type declarations; no runtime except three symbols
(`dataTagSymbol`, `dataTagErrorSymbol`, `unsetMarker`, `types.ts:61-65`). The load-bearing shapes
for a port are `QueryOptions` (`types.ts:231-347`: `retry`, `retryDelay`, `networkMode`, `gcTime`,
`queryFn`, `persister`, `queryHash`, `queryKey`, `queryKeyHashFn`, `initialData`,
`initialDataUpdatedAt`, `behavior`, `structuralSharing`, `_defaulted`, `_type`, `meta`,
`maxPages`), `QueryObserverOptions` (`types.ts:380-523`: `enabled`, `staleTime`, `refetchInterval`,
`refetchIntervalInBackground`, `refetchOnWindowFocus`, `refetchOnReconnect`, `refetchOnMount`,
`retryOnMount`, `notifyOnChangeProps`, `throwOnError`, `select`, `suspense`, `placeholderData`,
`_optimisticResults`), `MutationOptions` (`types.ts:1200-1266`: `mutationFn`, `mutationKey`,
`onMutate`/`onSuccess`/`onError`/`onSettled`, `retry`, `retryDelay`, `networkMode`, `gcTime`,
`meta`, `scope`), `QueryObserverBaseResult` (`types.ts:764-891`, 24 fields incl. `isEnabled` at
`:867` and the deprecated `isInitialLoading` at `:836`), `MutationObserverBaseResult`
(`types.ts:1335-1399`), `DefaultOptions`/`QueryClientConfig` (`types.ts:1495-1520`), and the
`Register` module-augmentation hook that lets users retype `DefaultError`, `QueryKey`,
`QueryMeta`, `MutationKey`, `MutationMeta` (`types.ts:37-60,215,1165,1181`). `StaleTime` is
`number | 'static'` (`types.ts:108`), and both `staleTime` and the boolean options accept a
`(query) => value` function (`types.ts:110-127`). `MutationFunctionContext` carries `client`,
`meta`, `mutationKey` (`types.ts:1189-1193`).

**`queryClient.ts` (1087 lines).** Owns a `QueryCache`, a `MutationCache`, default options and
per-key defaults (`queryClient.ts:79-104`), and subscribes both caches to `focusManager`/
`onlineManager` on `mount()`/`unmount()` with a mount counter (`:104-149`). Every read/write
helper goes through `defaultQueryOptions` (`:970-1055`), which merges client defaults → key
defaults → call options, computes `queryHash`, and applies the *derived defaults*:
`refetchOnReconnect = networkMode !== 'always'`, `throwOnError = !!suspense`,
`networkMode = 'offlineFirst'` when a `persister` is set, and `enabled = false` when
`queryFn === skipToken`. The imperative surface is `isFetching`/`isMutating` (`:150-182`),
`getQueryData`/`getQueriesData`/`setQueryData`/`setQueriesData`/`getQueryState` (`:183-375`),
`removeQueries`/`resetQueries`/`cancelQueries`/`invalidateQueries`/`refetchQueries` (`:376-553`),
the fetch family `query`/`fetchQuery`/`prefetchQuery`/`ensureQueryData` and their infinite
counterparts (`:554-766`), `resumePausedMutations` (`:767`), defaults getters/setters (`:818-969`)
and `clear` (`:1083`). `query()`/`infiniteQuery()` are the current API; `fetchQuery`,
`prefetchQuery`, `ensureQueryData`, `fetchInfiniteQuery`, `prefetchInfiniteQuery`,
`ensureInfiniteQueryData` all carry `@deprecated … will be removed in the next major version`
(`queryClient.ts:195,598,632,690,712,733`) — already so at `5bb950be8` (old `:141,390,424,461,483,504`).

**`query.ts` (973 lines).** `Query` extends `Removable` (`:225`) and holds `QueryState`
(`:52-114`: `data`, `dataUpdateCount`, `dataUpdatedAt`, `error`, `errorUpdateCount`,
`errorUpdatedAt`, `fetchFailureCount`, `fetchFailureReason`, `fetchMeta`, `isInvalidated`,
`status`, `fetchStatus`). State only changes through `#dispatch(action)` (`:822`) with the action
union at `:194`. `fetch()` (`:590-820`) dedups against an in-flight retryer, builds the
`QueryFunctionContext` with a consume-aware `AbortSignal` (`:634`, via
`utils.addConsumeAwareSignal`), runs an optional `behavior.onFetch` (infinite queries), wraps the
`queryFn` in `createRetryer` (`:726-754`), and on settle reports to the cache's
`onSuccess`/`onError`/`onSettled`. Observer bookkeeping lives in `addObserver`/`removeObserver`
(`:511-559`), where the last unsubscribe cancels with `revert: true` if the signal was consumed or
the fetch is a paused initial fetch, else only stops retries (`:531-540`). Staleness is
`isStale`/`isStaleByTime` (`:447-489`), `isStatic` (`:420`), `isActive`/`isDisabled` (`:386-411`).
`fetchState` (`:907`) decides `'fetching'` vs `'paused'` from `canFetch(networkMode)`.

**`queryObserver.ts` (902 lines).** `QueryObserver` extends `Subscribable` (`:57`), binds to a
`Query` in `setOptions` (`:182-271`), and derives a `QueryObserverResult` in `createResult`
(`:559-733`) — this is where `select`, `placeholderData`, `keepPreviousData`, structural sharing,
optimistic `isFetching`, and `isStale` are computed. `updateResult` (`:735-806`) compares the new
result with `shallowEqualObjects`, honours `notifyOnChangeProps`/tracked props, and always emits a
cache `observerResultsUpdated` event inside `notifyManager.batch` (`:792-805`). Timers: stale
timeout (`#updateStaleTimeout`, `:487`) and refetch interval (`#updateRefetchInterval`, `:518`),
both gated by `#shouldScheduleTimer` (`:479-485`: not on server, observer enabled, valid timeout).
Mount/focus/reconnect decisions are the free functions `shouldLoadOnMount`, `shouldFetchOnMount`,
`shouldFetchOn`, `shouldFetchOptionally`, `isStale` (`:837-900`). `fetchOptimistic` (`:395`)
serves suspense; `trackResult`/`trackProp` (`:331-355`) implement render-tracking.

**`utils.ts` (616 lines).** `QueryFilters`/`MutationFilters` (`:31-104`) and their matchers
`matchQuery`/`matchMutation` (`:175-265`), key hashing `hashQueryKeyByOptions`/`hashKey` (a
deterministic JSON with sorted object keys, `:266-299`), `partialMatchKey` (`:300`),
`replaceEqualDeep` structural sharing with a recursion-depth cap (`:339`), `shallowEqualObjects`
(`:391`), `isPlainObject`/`isPlainArray` (`:408-447`), `sleep` (`:448`), `replaceData` (`:454`,
applies `structuralSharing`), `keepPreviousData` (`:493`), `addToEnd`/`addToStart` (`:499-520`),
`skipToken` (`:522`), `ensureQueryFn` (`:528`, throws the "Missing queryFn" error, resolves an
`initialPromise` from hydration), `shouldThrowError` (`:576`), `addConsumeAwareSignal` (`:588`,
lazily exposes `signal` on the context and flags consumption), and the generic option resolver
`resolveQueryValue` (`:140`). The only environment-specific item is the deprecated top-level
`isServer` constant (`:111-114`, `typeof window === 'undefined' || 'Deno' in globalThis`), which
`environmentManager` now wraps.

**`mutation.ts` (535 lines).** `Mutation` extends `Removable` (`:135`) with `MutationState`
(`:30-76`: `context`, `data`, `error`, `failureCount`, `failureReason`, `isPaused`, `status`,
`variables`, `submittedAt`). `execute(variables)` (`:284-445`) runs the cache-level then
option-level `onMutate` → `mutationFn` (through `createRetryer`, with the `canRun` gate from the
cache's scope logic) → `onSuccess`/`onError` → `onSettled`, with callback errors routed as
documented in the tests; `continue()` (`:243`) resumes a paused mutation, re-using the retryer or
re-executing a restored one. State flows through `#dispatch` (`:447`) and observers are
notified via `MutationObserver.onMutationUpdate`. `getDefaultState` is exported (`:518`).

**`queriesObserver.ts` (402 lines).** Holds an array of `QueryObserver`s matched to an array of
options in `setQueries` (`:127-208`, `#findMatchingObservers` `:333`), forwards each observer's
result into a positional array (`#onUpdate`, `:368-375`), and memoises a `combine` function
(`#combineResult`, `:287`; `#shouldSkipCombine`, `:322` handles suspense-without-data).
`getOptimisticResult` (`:238`) returns `[results, getCombinedResult, trackResult]`.

**`hydration.ts` (394 lines). SSR/persistence only.** `dehydrate` (`:207-262`) turns the
mutation and query caches into a plain `DehydratedState` (`:94-99`), including *pending
promises* (`dehydratePromise`, `:110`) so a server can stream them; `dehydrateQuery` (`:148-175`)
stamps `dehydratedAt: Date.now()` (`:154`) and applies `serializeData`; `hydrate` (`:264-393`)
rebuilds queries via `queryCache.build`, resolves synchronously-settled thenables
(`tryResolveSync`, `:19`), restores `queryType: 'infinite'` with its behavior, only overwrites
an existing query when the incoming `dataUpdatedAt`/`dehydratedAt` is newer (`:313-320,380`),
and re-fetches pending queries whose promise was dehydrated. `defaultShouldDehydrateQuery`
only keeps `status === 'success'` (`:185`); `defaultShouldDehydrateMutation` only keeps paused
mutations (`:177`). Error redaction (`shouldRedactErrors`) logs in non-production (`:121`).

**`queryCache.ts` (357 lines).** `QueryCache` extends `Subscribable` (`:123`) over a `QueryStore`
(`Map`-like, `:96`), with `build(client, options, state?)` (`:147`) as the single constructor
path (computes `queryHash` when absent, applies the client's `getQueryDefaults`), `add`/`remove`
(`:181-231`; `remove` only deletes if the stored instance is the same object), `clear`, `get`,
`getAll`, `find`, `findAll` (`:232-331`), `notify` batched through `notifyManager` (`:332`), and
`onFocus`/`onOnline` fan-out to every query (`:341-356`). Seven event kinds are typed at
`:41-92`. `QueryCacheConfig` (`:25`) carries `onError`/`onSuccess`/`onSettled`.

**`mutationCache.ts` (335 lines).** Same shape as `QueryCache` (`:124`) but stores mutations in an
insertion-ordered list plus a `#scopes: Map<scopeId, Mutation[]>`. `build` (`:137`),
`add`/`remove` (`:156-194`; `remove` prunes the scope map), `canRun` (`:195`: a scoped mutation
may start only if it is the first pending one in its scope), `runNext` (`:213`: continue the next
paused mutation in the scope), `clear`, `getAll`, `find`, `findAll`, `notify` (`:236-321`),
`resumePausedMutations` (`:322`, resumes paused mutations in parallel across scopes, serially
within one). Six event kinds at `:60-105`; config callbacks incl. `onMutate` at `:26`.

**`mutationObserver.ts` (306 lines).** `MutationObserver` extends `Subscribable` (`:38`);
`setOptions` (`:96`) rebinds and resets when `mutationKey` changes, `mutate()` (`:207`) builds a
fresh `Mutation` through the cache and executes it, `reset()` (`:180`) detaches; `#updateResult`
(`:224`) folds `MutationState` into `MutationObserverResult` (adds `mutate`, `reset`, `isIdle`…),
and `#notify` (`:240`) fires per-`mutate` `onSuccess`/`onError`/`onSettled` callbacks before
listeners, batched.

**`retryer.ts` (255 lines).** `createRetryer(config)` (`:94-253`) returns
`{ promise, cancel, continue, cancelRetry, continueRetry, canStart, start, status }` (`:22-31`).
Default retry count is `3` on the client and `0` on the server (`:196`); default delay is
`min(1000 * 2^failureCount, 30000)` (`:49-51`); `retry` may be `boolean | number | fn` and
`retryDelay` `number | fn` (`:35-47`). `canFetch(networkMode)` (`:53-57`) consults
`onlineManager` only for `'online'` mode; a fetch that cannot start pauses and waits for
`onlineManager`/`focusManager` to continue it. `CancelledError` (`:77-86`) carries `revert` and
`silent`; `isCancelledError` is deprecated in favour of `instanceof` (`:88`).

**`infiniteQueryObserver.ts` (251 lines).** Subclass of `QueryObserver` (`:41`) that injects
`infiniteQueryBehavior` into options (`:108-125`), adds `fetchNextPage`/`fetchPreviousPage`
(`:161-200`), and extends `createResult` (`:201-246`) with `hasNextPage`, `hasPreviousPage`,
`isFetchingNextPage`, `isFetchingPreviousPage`, `isFetchNextPageError`, `isFetchPreviousPageError`.

**`infiniteQueryBehavior.ts` (176 lines).** `infiniteQueryBehavior(pages?)` (`:16-130`) returns a
`QueryBehavior` whose `onFetch` replaces `fetchFn` with a loop that fetches one page in a
direction (`fetchMeta.fetchMore.direction`), or refetches all existing pages (up to `maxPages`)
when no direction is set, honouring cancellation between pages. `hasNextPage`/`hasPreviousPage`
(`:159-175`) are shared with the observer.

**`timeoutManager.ts` (243 lines). Timer-provider abstraction.** `TimeoutManager` (`:70`) proxies
`setTimeout`/`clearTimeout`/`setInterval`/`clearInterval` (`:155-230`) to a `TimeoutProvider`
(`:28`), defaulting to the global timers (`:39-58`); `setTimeoutProvider` (`:106`) swaps it and
warns (non-production) if timers were already created. Exists so hosts can bypass the ~24-day
`setTimeout` cap or drive timers from a test clock (`docs/framework/react/plugins/persistQueryClient.md`).
`systemSetTimeoutZero` (`:241`) is the notify scheduler primitive. In Dart this maps to
`package:clock`/`Timer` and fake_async (DESIGN D10), so the module is infrastructure, not behaviour.

**`notifyManager.ts` (144 lines).** `createNotifyManager()` (`:21-142`) exposes `batch` (`:62`,
runs a callback with notifications queued, flushing once the outermost batch exits), `batchCalls`
(`:78`), `schedule` (`:91`), and the three injection points `setNotifyFunction`,
`setBatchNotifyFunction`, `setScheduler` (`:96-141`). `defaultScheduler` is `setTimeout(…, 0)`
(`:19`). This is the seam the Flutter binding's "scheduler-aware flush" (PLAN M7) plugs into.

**`streamedQuery.ts` (144 lines).** `streamedQuery({ streamFn, refetchMode, reducer, initialValue })`
(`:75-143`) returns a `QueryFunction` that iterates an `AsyncIterable`, folding each chunk into
the cached data via `setQueryData` as it arrives; `refetchMode` is `'reset' | 'append' | 'replace'`
and on `'reset'` the query is put back to its `resetState` while `fetchStatus: 'fetching'`.
Exported as `experimental_streamedQuery`.

**`focusManager.ts` (142 lines). Browser-only.** `FocusManager extends Subscribable` (`:14`); the
default setup subscribes to `window.visibilitychange` when `window.addEventListener` exists
(`:20-38`), `setEventListener` (`:77`) replaces that source, `setFocused` (`:107`) forces a value,
`isFocused` (`:128-136`) returns the forced value or `document.visibilityState !== 'hidden'`.
Consumers only ever call `subscribe`, `isFocused`, `setFocused`; a Flutter port replaces the setup
with `AppLifecycleListener`.

**`onlineManager.ts` (117 lines). Browser-only.** Same pattern (`:15`): default setup listens to
`window` `online`/`offline` (`:21-40`), `setEventListener` (`:75`), `setOnline` (`:95`), `isOnline`
(`:109`, starts `true`). The retryer pauses on `false` and the client resumes paused mutations on
the `false → true` edge.

**`removable.ts` (40 lines).** Abstract base for `Query` and `Mutation`: `gcTime`, `scheduleGc`
(only when `isValidTimeout(gcTime)`), `clearGcTimeout`, `destroy`, and `updateGcTime`, which never
lowers an already-seen value and defaults to **5 minutes on the client, `Infinity` on the server**
(`removable.ts:24-29`).

**`environmentManager.ts` (37 lines). SSR-only.** A module-level `isServerFn` defaulting to the
`utils.isServer` constant, exposed as the standalone `isServer()` (`:10`) and as
`environmentManager.{isServer, setIsServer}` (`:29-35`). Read by `removable` (gcTime default),
`retryer` (retry default), `queryObserver` (`#shouldScheduleTimer`). For Flutter it is a constant
`false` — but the *decisions* it feeds (gc default, retry default, timer suppression) are real.

**`subscribable.ts` (30 lines).** `Subscribable<TListener>` with a `Set` of listeners,
`subscribe(listener) → unsubscribe` (`:8`, deduplicates identical references), `hasListeners`
(`:19`), and protected `onSubscribe`/`onUnsubscribe` hooks.

**`index.ts` (62 lines).** Barrel; the full export list is in the table above. Everything in
`types.ts` is re-exported wholesale (`:62`).

### 1.3 Environment-only concerns, summarised

| Concern | Where | Port relevance |
|---|---|---|
| `window`/`document` globals | `focusManager.ts:25-35,135`, `onlineManager.ts:26-36` | Replace the *setup* function; keep the `Subscribable` + `setEventListener`/`isX`/`setX` contract |
| `isServer` detection | `utils.ts:114`, `environmentManager.ts:10` | Constant `false`, but its three consumers (`removable.ts:28`, `retryer.ts:196`, `queryObserver.ts:481`) must keep the client branch |
| Timer provider | `timeoutManager.ts` (whole file) | `package:clock`/`Timer`; nothing else to port |
| `process.env.NODE_ENV` dev warnings | `hydration.ts:121`, `query.ts:626,760`, `queriesObserver.ts:134`, `timeoutManager.ts:109-201`, `utils.ts:461,538` | `assert()`/`kDebugMode` |
| SSR hydration | `hydration.ts` (whole file) | Out of MVP scope; persistence later may reuse `DehydratedState` |
| `AbortController`/`AbortSignal` | `query.ts:634`, `utils.ts:588-610` | Needs a Dart cancellation token with "consumed" tracking |

---

## 2. Test inventory (`packages/query-core/src/__tests__/`)

### 2.1 Runtime test files (`*.test.tsx`)

Case counts are `it(`/`test(` occurrences at `50680b98c`; "old" is the same count at `5bb950be8`.
Runtime total: **605 cases in 21 files** (old: 568 in 18 files).

| File | Lines | Cases | Old | Behaviours pinned (with representative case line) |
|---|---:|---:|---:|---|
| `queryClient.test.tsx` | 3133 | 156 | 156 | Option merging and per-key defaults (`:41-155`); derived `networkMode` with persister (`:156`); `setQueryData`/`setQueriesData` semantics incl. `undefined` no-ops and custom `structuralSharing` (`:195-405`); `getQueryData` exact-match default (`:460`); `ensureQueryData`/`query({staleTime:'static'})` cache-hit vs fetch vs `revalidateIfStale` (`:468-636`); infinite variants (`:637-735`); `fetchQuery`/`query` retry-off-by-default, gcTime 0/Infinity, staleTime function, `select`, disabled/skipToken behaviour (`:768-1369`); infinite prefetch page loops (`:1642-1826`); `prefetchQuery` swallows errors (`:1848`) and is GC'd (`:1862`); `cancelQueries` revert/no-revert and `CancelledError` for imperative callers (`:1949-2018`); `refetchQueries` filter matrix (`type`, `stale`, disabled observers, static, paused → resolves immediately, `throwOnError`) (`:2019-2328`); `invalidateQueries` `refetchType` matrix and `cancelRefetch` default (`:2329-2561`); `resetQueries` (`:2562-2698`); focus/online fan-out, paused-mutation resume ordering and scopes, mount/unmount counting (`:2699-3104`); mutation defaults (`:3105`) |
| `queryObserver.test.tsx` | 1997 | 75 | 73 | Fetch on subscribe and pending state even for sync `queryFn` (`:35-73`); `enabled` as callback across resubscribe cycles (`:92-264`); `select` memoisation, error handling, structural sharing, no cross-query error leak (`:325-770`); disabled/unsubscribed observers never fetch (`:771-812`); retry stops and interval clears on unsubscribe (`:884-926`); `refetchInterval` as function (`:927-960`); `notifyOnChangeProps` function form (`:961-1006`); `placeholderData` incl. previousData/previousQuery with `select` (`:1007-1379`); `setOptions` cache notification (`:1380`); disabled observers are not stale and schedule no timers; no timers on server (`:1403-1463`, **new**); `staleTime` function and `'static'` (`:1464-1515`); `shouldFetchOnWindowFocus` truth table incl. `'always'` and function forms (`:1516-1617`); `fetchOptimistic` (`:1618-1668`); tracked `error` prop under `throwOnError` (`:1669-1741`); `retryOnMount:false`, static + `refetchOnMount:'always'`, background-error focus refetch (`:1742-1874`); `isRestoring` → `fetchStatus:'idle'` (`:1875`); `isEnabled` (`:1887-1909`); StrictMode dedup and signal consumption (`:1936-1996`) |
| `query.test.tsx` | 1473 | 51 | 50 | Longest-gcTime-wins (`:37`); retry continues after focus/reconnect and all waiters resolve (`:64-158`); paused-query cancel throws `CancelledError` (`:159`); last-observer-unsubscribe cancels a paused initial fetch but not a consumed-signal `fetchQuery` (`:194-269`); `QueryFunctionContext` contents and `AbortSignal` semantics (`:270-437`); reset while pending; hydration reset state (`:438-504`); refetch after cancel; cancel of settled queries is a no-op (`:505-558`); retryer released after settle (`:559`); previous status kept across refetch (`:590`); gcTime 0 immediate removal, GC deferred while fetching, no GC with subscribers, GC of never-fetched queries (`:621-699,1058`); `meta` storage/updates/defaults and visibility in `queryFn` (`:725-800`); `onOnline` refetch (`:801`); observer add/remove idempotence and notify-during-update (`:820-880`); `invalidate` idempotence (`:881`); no duplicate `fetch` dispatch (`:899`); missing `queryFn` error and `undefined` result error (`:932-984`); no retry and infinite gcTime on the server (`:985-1020`, latter **new**); `initialDataUpdatedAt` function/zero (`:1021-1057`); always revert to `idle` (#5968) and silent background cancel (`:1078-1171`); non-serialisable data log, `setData` error status (`:1172-1243`); `persister` (`:1244`); observer-supplied `queryFn` (`:1259`); array-key check (`:1281`); `initialData` function and late `initialData` (`:1299-1377`); revert must not clobber a newer observer's fetching state (`:1378`); `dataUpdateCount` unchanged by `initialData` on prefetched query (`:1429`) |
| `hydration.test.tsx` | 2078 | 46 | 46 | `dehydrateQuery` direct use with `serializeData`/`shouldRedactErrors` (`:20-83`); serialisable values, `dehydrateQueries:false`, gcTime carried over, default options for hydrated queries/mutations (`:84-356`); complex keys; only successful queries by default; filter callbacks (`:357-495`); newer-wins overwrite rules incl. with transformation/promise (`:496-573,1165-1304`); mutation dehydrate/continue, `dehydrateMutations:false`, paused-only default, scopes (`:574-733,953`); `fetchStatus` handling on create/update (`:745,916`); `meta` round-trip (`:793-915`); pending-promise dehydration, hydration without observers, promise transforms, streamed overwrite (`:988-1379`); error redaction default/off/dev log (`:1380-1492`); synchronous thenables (`:1493`); infinite `queryType`/behavior restoration and multi-page refetch after hydrate (`:1534-1806`); resolved-promise hydration must not enter fetching/pending and must set `dataUpdatedAt` (`:1807-2077`) |
| `queriesObserver.test.tsx` | 854 | 23 | 23 | Positional result array, `getQueries`/`getObservers`, updates on change/removal/reorder, no update when unchanged (`:20-277`); fetch on subscribe; observer not destroyed while subscribed (`:278-323`); duplicate keys at different positions (`:324`); early-return notify (`:394`); `combine` memoisation with stable reference across add/remove/replace, suspense skip rules, function-identity recalculation, fallback without raw argument (`:441-739`); `it.each` table (`:740`); `trackResult` fan-out (`:775`); late-added observers get subscribed (`:815`) |
| `utils.test.tsx` | 739 | 78 | 78 | `hashQueryKeyByOptions` custom/default (`:26-47`); `shallowEqualObjects` (`:48`); `isPlainObject`/`isPlainArray` prototype edge cases (`:65-127`); `partialMatchKey` incl. null and undefined-vs-missing (`:128-183`); `replaceEqualDeep` sharing matrix incl. depth limit (`:184-461`); `matchMutation` (`:462`); `keepPreviousData` (`:476`); `addToEnd`/`addToStart` with `max` (`:483-543`); `hashKey` determinism (`:544-583`); `isValidTimeout` (`:584-610`); `ensureQueryFn` with `initialPromise`/`skipToken` (`:611-659`); `shouldThrowError` (`:660`); `addConsumeAwareSignal` (`:678-738`) |
| `mutation.test.tsx` | 1271 | 28 | 28 | Null variables; `setMutationDefaults`; full success and error state sequences (`:22-253`); restore a mutation (`:254`); observer dedup; missing `mutationFn` error; state updates without subscribers; callbacks see updated options (`:334-429`); **scopes**: serial within scope, parallel without, parallel across scopes (`:430-620`); callback return-type matrix sync/async/`Promise.all` (`:621-839`); erroneous callbacks: global/local `onSuccess`/`onSettled` errors route to `onError`, double `onSettled` calls, rethrow to a separate execution context (`:840-1168`); GC only after the last observer (`:1169`); retryer released on settle (`:1195-1226`); settled mutation not re-executed on `continue`; restored paused mutation without retryer still continues (`:1227-1270`) |
| `mutationObserver.test.tsx` | 544 | 16 | 16 | Unsubscribe keeps observer while another subscription exists; unsubscribe/reset trigger GC (`:19-129`); resubscribe reattaches to in-flight or settled mutation (`:65-106`); `mutationKey` change resets observer but not existing mutations (`:130-200`); `meta` changes affect only pending mutations (`:201-345`); callback order and arguments for success/error (`:346-428`); erroneous callbacks reported in a separate context (`:429-521`); no cache notify on same-options `setOptions` (`:522`) |
| `mutationCache.test.tsx` | 511 | 16 | 16 | Cache-level `onError`/`onSuccess`/`onSettled`/`onMutate` called and awaited; `options.onMutate` synchronous when cache `onMutate` absent (`:15-277`); `find`/`findAll` filters (`:278-352`); GC after gcTime, not with observers, deferred while pending, callbacks fire with gcTime 0 (`:353-448`); scope map pruning on `remove`, removal notify for unknown mutation (`:449-510`) |
| `queryCache.test.tsx` | 456 | 16 | 16 | Subscribe events: added, stale-notify, includes cache+query, `initialData` add (`:20-116`); cache size limiting via subscriber (`:117`); `find` exact/non-exact; `findAll` filter matrix incl. `type`, `stale`, `fetchStatus`, `predicate` (`:168-346`); config error/success callbacks (`:347-395`); `build` hash from key vs provided `queryHash` (`:396-420`); `remove` only deletes the stored instance; `add` idempotent (`:421-455`) |
| `streamedQuery.test.tsx` | 745 | 15 | 15 | Stream chunks into data, arrays, empty streams (`:32-159`); `refetchMode` reset/append/replace (`:160-326`); abort on refetch/unsubscribe, not when signal unconsumed (`:327-463`); custom `reducer`/`initialValue` (`:464-541`); error + `initialData` interactions on reset (`:542-707`); reducer not called twice in replace mode (`:708`) |
| `retryer.test.tsx` | 315 | 13 | new | Resolve/reject and status; failure reporting per attempt; sync throw retried; default backoff capped at 30 s (`:19-104`); `CancelledError` carries cancel options and calls `onCancel`; cancel after resolve ignored (`:105-148`); `cancelRetry`/`continueRetry` (`:149-195`); offline pause and resume, `networkMode` `'always'` and `'offlineFirst'` (`:196-273`); `canFetch`/`canStart` (`:274`); `initialPromise` reuse (`:299`) |
| `removable.test.tsx` | 182 | 12 | new | `updateGcTime`: 5 min client default, larger wins, explicit smaller honoured when first, never decreases, `Infinity` on server (`:50-97`); `scheduleGc` validity and re-scheduling (`:98-139`); `clearGcTimeout` idempotence (`:140-170`); `destroy` clears timer (`:171`) |
| `onlineManager.test.tsx` | 190 | 11 | 11 | `isOnline` defaults with/without `navigator` (`:16-35`); `setEventListener` replaces and cleans up previous handler, window-less cleanup safety (`:36-159`); `online`/`offline` events update state; listeners on `setOnline` (`:160-189`) |
| `focusManager.test.tsx` | 175 | 9 | 9 | Same shape as onlineManager for `visibilitychange`; `isFocused` true without `document` (`:45`); setup retained after last unsubscribe (`:134`); listeners on `setFocused` (`:152`) |
| `infiniteQueryBehavior.test.tsx` | 533 | 9 | 9 | Missing `queryFn` error (`:23`); `maxPages` trimming (`:51`); cancellation mid-page and no refetch of remaining pages, abort reason surfaced (`:199-375`); no infinite loop on page error with retry (#8046, `:376`); `initialPageParam: null` (`:450`); `getNextPageParam` → `null` stops (`:477`); `persister` (`:511`) |
| `subscribable.test.tsx` | 109 | 9 | new | `onSubscribe`/`onUnsubscribe` hook calls, `hasListeners` transitions, listener dedup, `subscribe` stable when destructured (`:20-108`) |
| `notifyManager.test.tsx` | 133 | 7 | 7 | Default notify/batch functions; custom scheduler; errors inside a batch still notify; custom batch function; batch coalescing (`:23-132`) |
| `infiniteQueryObserver.test.tsx` | 252 | 7 | 7 | `select` on infinite data (`:23`); `meta` to `queryFn` (`:46`); page-param callbacks receive `pageParams`, skipped on empty pages (`:76-145`); `undefined`/`null` stop fetching (`:146-209`); `getOptimisticResult` installs behavior (`:210`) |
| `timeoutManager.test.tsx` | 136 | 5 | 5 | Global timer proxying; provider swap; warning when swapping after use; singleton type; `systemSetTimeoutZero` (`:38-135`) |
| `environmentManager.test.tsx` | 29 | 3 | 3 | Default detection; global override; function override (`:9-28`) |

Support file: `__tests__/utils.ts` (28 lines, 0 cases) provides `mockOnlineManagerIsOnline`,
`executeMutation` and `setIsServer` (`__tests__/utils.ts:6-28`); unchanged between revisions.

### 2.2 Type-level test files (`*.test-d.ts[x]`)

These run under `vitest --typecheck` only; they pin TypeScript inference, not runtime behaviour,
and have no Dart counterpart. Total: **68 cases in 6 files**, identical at both revisions.

| File | Lines | Cases | What it pins |
|---|---:|---:|---|
| `queryClient.test-d.tsx` | 786 | 38 | `DataTag` inference for `getQueryData`/`setQueryData`/`getQueryState`, filters' `predicate` typing, `select` allowed on `query` but not `fetchQuery`, `pages` requires `getNextPageParam`, typed `QueryFunctionContext` in defaults, arrow-function inference |
| `mutation.test-d.tsx` | 334 | 16 | `onMutate` result inference, `MutateFunction` variable-arity rules for `void`/optional/`unknown`/`any`/union/required variables, spread-argument compatibility |
| `utils.test-d.tsx` | 95 | 6 | `QueryFilters` key typing incl. partial keys, readonly unions, invalid keys |
| `queryObserver.test-d.tsx` | 153 | 4 | Discriminated result type; `placeholderData` `previousQuery`/`previousData` typing |
| `OmitKeyof.test-d.ts` | 175 | 3 | `OmitKeyof` for string/number/symbol keys |
| `infiniteQueryObserver.test-d.tsx` | 75 | 1 | Infinite result type inference |

### 2.3 Totals

| | `5bb950be8` | `50680b98c` |
|---|---:|---:|
| Runtime files / cases | 18 / 568 | 21 / **605** |
| Type-level files / cases | 6 / 68 | 6 / 68 |
| All | 24 / 636 | 27 / **673** |
| Skipped/todo cases | 0 | 0 |

The previous port's fidelity audit (`flutter-port/packages/query_core/test/PORTING_NOTES.md`)
counted 355 upstream cases across the six suites it ported at `5bb950be8`; those six files are
unchanged in case count here except `query.test.tsx` (+1) and `queryObserver.test.tsx` (+2).

---

## 3. What changed between `5bb950be8` and `50680b98c`

### 3.1 Numbers

`git diff --stat 5bb950be8..50680b98c -- packages/query-core`: **31 files changed, 3452
insertions, 739 deletions**. Package version `5.102.3 → 5.102.8`
(`packages/query-core/package.json`). Of the ~3,300 inserted source and test lines, ~1,860 are JSDoc comment lines
from a single commit and ~600 are the three new test files; the comment-stripped semantic diff of `src/*.ts` is 584 lines across
12 modules (`environmentManager`, `hydration`, `index`, `notifyManager`, `queriesObserver`,
`query`, `queryClient`, `queryObserver`, `removable`, `retryer`, `types`, `utils`). The other 11
source modules are byte-identical once comments are removed.

Commits touching `packages/query-core`, newest first:

| Commit | Date | Subject |
|---|---|---|
| `e57f8163b` | 2026-09-07 | docs(query-core): add JSDoc across the package and expose it in generated reference docs (#11438) |
| `a1119e5a3` | 2026-09-06 | ref(hydration): remove outdated dehydratedAt fallback (#11436) |
| `799a33cda` | 2026-09-04 | test(query-core/retryer): add unit tests for 'createRetryer' (#11383) |
| `b4daab265` | 2026-09-03 | test(query-core/removable): add unit tests for 'Removable' base class (#11365) |
| `645e4ac4a` | 2026-09-03 | test(query-core/subscribable): add unit tests for 'Subscribable' base class (#11364) |
| `1566c16de` | 2026-08-31 | chore: use infiniteQuery instead of fetchInfiniteQuery et al (#11344) |
| `6f31ef6c8` | 2026-08-31 | test: replace 'prefetchQuery'/'fetchQuery'/'ensureQueryData' with 'query' (#11340) |
| `fdae2ce4e` | 2026-08-30 | ref(query-core): Reuse refetch interval resolver (#11332) |
| `2969edf32`, `2eb3c7c76`, `714df67ab`, `1836e61b8`, `51f12db91` | 2026-08-25..28 | ci: Version Packages (5.102.4 → 5.102.8) |
| `578e5c26e` | 2026-08-26 | ref: bundle-size improvements (#11302) |
| `a05df6aef` | 2026-08-25 | fix(query-core): Avoid scheduling stale timeouts for disabled query observers (#11293) |

`packages/query-core/CHANGELOG.md` records only two of these as user-facing: **5.102.4** —
"Avoid scheduling stale timeouts for disabled query observers" (#11293); **5.102.5** — "Reduce
the Query Core bundle size by removing unused symbol descriptions and simplifying internal
helpers" (#11302). 5.102.6–5.102.8 have empty entries (bumps driven by other packages).

### 3.2 Behaviour changes (port-relevant)

1. **Disabled observers schedule no timers** (#11293, 5.102.4). `QueryObserver` gained
   `#shouldScheduleTimer(timeout)` (`queryObserver.ts:479-485`) — `!isServer() && enabled !== false
   && isValidTimeout(timeout)` — and both `#updateStaleTimeout` (`:487-509`) and
   `#updateRefetchInterval` (`:518-538`) now go through it. Previously the stale timeout checked
   only `isServer || isStale || !isValidTimeout` (old `queryObserver.ts:380-382`), so a disabled
   observer with `staleTime` still armed a stale timer. Pinned by the two new cases
   `__tests__/queryObserver.test.tsx:1415,1438`. **The Dart `QueryObserver` needs this gate.**

2. **Hydration: `dehydratedAt` is now required and has no `Date.now()` fallback** (#11436).
   `DehydratedQuery.dehydratedAt` moved from optional to required (`hydration.ts:83`), and the three
   sites that used `dehydratedAt ?? Date.now()` / `dehydratedAt === undefined ||` now use the field
   directly (`hydration.ts:313,331,365,380`). Payloads produced before `dehydratedAt` existed will
   no longer be treated as "newer" on hydrate. Only matters if the port reuses upstream's
   `DehydratedState` for persistence.

3. **`removeObserver` paused-fetch cancel is inlined, not changed.** `#isInitialPausedFetch()`
   (old `query.ts:389-393`) was folded into the condition at `query.ts:531-540`; semantics are
   identical (`fetchStatus === 'paused' && status === 'pending'`).

4. **`QueryObserver.#notify` inlined into `updateResult`** (`queryObserver.ts:792-805`); the
   `shouldAssignObserverCurrentProperties` helper (old `queryObserver.ts:794`) became an inline
   `!shallowEqualObjects(this.getCurrentResult(), result)` (`queryObserver.ts:285`). No behaviour
   change.

No option was renamed, added or removed at the public level in this range, and **no default value
changed**: `retry` 3/0 (`retryer.ts:196`), backoff `min(1000·2^n, 30000)` (`retryer.ts:50`), gcTime
5 min/`Infinity` (`removable.ts:28`), `staleTime` 0 (`query.ts:473`), `refetchOnReconnect` derived
from `networkMode` (`queryClient.ts:1026-1028`), `throwOnError` from `suspense` (`:1030-1031`), and
`networkMode: 'offlineFirst'` with a persister (`:1035`) are all as at `5bb950be8`.

### 3.3 Internal refactors (no behaviour change, but they affect line references)

- **`resolveStaleTime` + `resolveQueryBoolean` → one generic `resolveQueryValue`**
  (`utils.ts:140-173`; #11332). Call sites in `query.ts:388,424`, `queryClient.ts:215,581,625`,
  `queryObserver.ts` (13 sites) updated; `#computeRefetchInterval` (`queryObserver.ts:511-516`) and
  `shouldFetchOn` (`:873`) now use it instead of hand-rolled `typeof === 'function'` checks. The
  types `StaleTimeFunction`/`QueryBooleanOption` still exist (`types.ts:110-127`); only `utils.ts`
  stopped importing them.
- **`environmentManager`** is now a plain object with a module-level `isServerFn` and a standalone
  `isServer()` export (`environmentManager.ts:10,29-35`), imported directly by `removable.ts:2`,
  `retryer.ts:3`, `queryObserver.ts:2` as `isServerEnvironment`. `index.ts` still exports only the
  `environmentManager` object (`index.ts:5`).
- **Bundle-size pass** (#11302): `Symbol('…')` descriptions dropped from `dataTagSymbol`,
  `dataTagErrorSymbol`, `unsetMarker` (`types.ts:61-65`); `queriesObserver.replaceAt` helper
  removed in favour of `slice()` + index assignment (`queriesObserver.ts:368-375`).
- **`index.ts`**: three additions, all `export type` re-exports of classes that were already
  exported from their modules at the old revision — `FocusManager` (`index.ts:4`), `OnlineManager`
  (`:19`), `TimeoutManager` (`:30`).
- **JSDoc** (#11438): every public class, method, option and result field now carries a doc
  comment; this is what turned into the generated `docs/framework/*/reference/` pages (§3.5).
  Deprecation markers on `fetchQuery`/`prefetchQuery`/`ensureQueryData`/infinite variants,
  `isCancelledError`, `isInitialLoading`, and the `*QueryOptions` aliases at `types.ts:594-674`
  **pre-date this range** (present at old `queryClient.ts:141-504`, `retryer.ts:70`,
  `types.ts:512-736`).

### 3.4 Test changes

- **Three new suites** for previously untested primitives: `retryer.test.tsx` (13 cases),
  `removable.test.tsx` (12), `subscribable.test.tsx` (9) — 34 cases, 606 lines. These are the
  cleanest specifications of retry/backoff/pause, GC-time bookkeeping and subscription semantics
  in the package and are directly portable.
- **Three new cases in existing suites:** `query.test.tsx:1006` (`gcTime` is `Infinity` on the
  server), `queryObserver.test.tsx:1415,1438` (no timers for disabled observers / on the server).
- **Mechanical rewrites** (#11340, #11344) replaced deprecated calls with `query`/`infiniteQuery`
  across `hydration.test.tsx` (55× `prefetchQuery`, 6× `prefetchInfiniteQuery`, 3×
  `fetchInfiniteQuery` → `void client.query(...).catch(noop)` etc.; +419/−306 lines),
  `query.test.tsx` (31× `prefetchQuery`, 8× `fetchQuery`), `queryCache.test.tsx` (18×),
  `queryClient.test.tsx` (37× `fetchQuery`, 10× `prefetchQuery`), `queryObserver.test.tsx` (5×).
  Case names and assertions are otherwise unchanged (the test-name diff between revisions is
  exactly the additions listed above). `queryClient.test.tsx` keeps dedicated `fetchQuery` /
  `prefetchQuery` / `fetchInfiniteQuery` / `prefetchInfiniteQuery` describe blocks
  (`:768,1370,1642,1827`) alongside the `query` / `infiniteQuery` ones, so the deprecated API stays
  covered.
- No case was removed, skipped or renamed.

### 3.5 `docs/` in the range

There is no release-notes file under `docs/`; release notes live in each package's
`CHANGELOG.md` (§3.1). Docs changes touching query-core concepts:

- **Generated reference docs** (from #11438): new `docs/framework/{angular,react,preact,solid,
  svelte,vue}/reference/classes/{QueryClient,QueryCache,Query,QueryObserver,InfiniteQueryObserver,
  QueriesObserver,Mutation,MutationCache,MutationObserver,CancelledError}.md`, `functions/
  {dehydrate,dehydrateQuery,hydrate,defaultShouldDehydrate*,hashKey,matchQuery,matchMutation,
  partialMatchKey,replaceEqualDeep,shouldThrowError,keepPreviousData,noop,isCancelledError,
  experimental_streamedQuery}.md`, `interfaces/{TimeoutManager,OnlineManager,FocusManager,…}.md`,
  and a very large `docs/config.json` navigation update (~5.6k changed lines).
- **Hand-written core reference removed:** `docs/reference/{QueryClient,QueryCache,QueryObserver,
  InfiniteQueryObserver,QueriesObserver,MutationCache,focusManager,onlineManager,notifyManager,
  timeoutManager,environmentManager,streamedQuery}.md` deleted (−1262 lines); guides' links were
  rewritten to the generated pages (e.g. `docs/framework/react/guides/ssr.md`,
  `network-mode.md`, `prefetching.md`, `plugins/persistQueryClient.md`).
- **New prose:** `docs/framework/vue/guides/ssr.md` gained a "`dehydrate`/`hydrate` options"
  section documenting `shouldDehydrateMutation`, `shouldDehydrateQuery`, `serializeData`,
  `shouldRedactErrors`, `HydrateOptions.defaultOptions.{queries,mutations,deserializeData}` and the
  newer-wins rule; `docs/framework/preact/guides/{ssr,suspense,testing}.md` were added (Preact
  adapter, not core).
- No migration guide or behaviour note was added for #11293/#11436 beyond the CHANGELOG line.

---

## 4. Pointers for the design tickets

- **Modules a Flutter port must implement faithfully** (all Env `–` above): `types`, `queryClient`,
  `query`, `queryCache`, `queryObserver`, `queriesObserver`, `infiniteQueryObserver`,
  `infiniteQueryBehavior`, `mutation`, `mutationCache`, `mutationObserver`, `retryer`,
  `notifyManager`, `removable`, `subscribable`, `utils`, `streamedQuery` (optional). That is
  8,094 of 9,089 lines (everything except the barrel and the five environment modules).
- **Modules to replace with platform shims:** `focusManager` and `onlineManager` (keep the
  contract, swap the setup), `timeoutManager` (→ `Timer` under `package:clock`),
  `environmentManager` (→ `false`). `hydration` is out of MVP scope.
- **Spec-grade tests to port first** for the shims' consumers: `retryer.test.tsx`,
  `removable.test.tsx`, `subscribable.test.tsx` (new, self-contained), then the six big suites.
- **Line references in `PORTING_NOTES.md` and `DESIGN.md` need re-basing** if the port moves to
  `50680b98c`: `query.ts` shifted by up to +189 lines, `queryObserver.ts` by +90,
  `queryClient.ts` by +363, mostly from JSDoc insertions above each member.
