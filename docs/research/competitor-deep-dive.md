# Deep dive: our port against the other query libraries for Flutter

- **Date:** 2026-09-09
- **Purpose:** what we do better, what the others do better, and what is worth
  adapting. This goes one level below
  [`dart-query-libraries-survey.md`](dart-query-libraries-survey.md) (2026-09-08,
  API surface and issue trackers, read from pub.dev and GitHub): here the
  *code* of each library was read, and where a defect mattered it was
  reproduced.
- **Subjects:** the four checkouts under `reference-projects/` (gitignored):
  - `reference-projects/query` — jezsung/query, `flutter_query` 0.11.1, HEAD
    `6718a1a` (2026-07-14). The serious TanStack port.
  - `reference-projects/cached_query` — D-James-GH/cached_query, `cached_query`
    3.7.0 + `cached_query_flutter` 3.4.0 + `cached_storage` 3.3.0 +
    `devtools_extension`, HEAD `101785d` (2026-05-17). Not a port, but the
    most-downloaded library in this space (13.5k downloads/30d per the survey)
    and the only one with persistence and DevTools.
  - `reference-projects/fquery` — 41y08h/fquery, `fquery` + `fquery_core`
    3.1.0, HEAD `7c385bc` (2026-07-13), ten commits past the 3.1.0 tags.
  - `reference-projects/flutter_query` — mislavlukach/flutter_query, published
    as `flutter_requery` 0.1.2, HEAD `e96a62b` (2021-10-17). A 390-line
    prototype; covered in one section.
- **Method:** four parallel code reads against the same checklist (options,
  state, infinite queries, mutations, client, caches, managers, persistence,
  Flutter layer, typing, tests, docs, maturity), each citing `file:line`. The
  reads of jezsung/query and cached_query ran probe tests from a scratch
  package (four and eight respectively) to confirm the defects marked
  **verified** below; cached_query's own core suite was also run (201 pass).
  Every claim about *our* port was then re-checked against our code before it
  went into this document. Defects in fquery were established by reading,
  not by running; they are marked as such.

## 1. Snapshot

| | ours (`tanstack_query_*`) | jezsung `flutter_query` | `cached_query` | `fquery` | `flutter_requery` |
|---|---|---|---|---|---|
| Live core | `packages/query_kit`, pure Dart, 9.5k lines | `lib/src/core` inside the Flutter package, ~5.9k lines (`packages/query_core` 0.2.1 is a dead 2023 design) | `packages/cached_query`, pure Dart, ~4.2k lines | `fquery_core`, ~2k lines | one file |
| Flutter layer | 1.9k lines; controller, builder, mixin, context extension | hooks only (`flutter_hooks` hard dep) | ~960 lines; `QueryBuilder`/`Listener`/`Consumer`, `MutationBuilder`/`Listener`/`Consumer` (bloc-family shape) | hooks **and** builders over one observer (`flutter_hooks` hard dep) | one `Query` widget over `StreamBuilder` |
| Runtime deps | core: `clock`, `meta`; binding: `flutter` | `clock`, `collection`, `flutter_hooks`, `meta` | core: `rxdart`, `meta`; Flutter: `connectivity_plus`; storage: `sqflite` | `collection`, `clock`, `freezed_annotation`, **`freezed` as a runtime dep**, `flutter_hooks` | none |
| Code generation | none | none (hand-written `==`) | none in the library (freezed + riverpod in the DevTools extension) | freezed, parts committed | none |
| Tests | 507 core + 56 binding + 15 demo widget + 9 e2e; **upstream suites ported case-for-case**, names kept | 819 cases, self-written ("SHOULD … WHEN …"), `flutter_hooks_test` | 201 core + 30 Flutter (two placeholders) + 2 storage; self-written | 18 core + 19 Flutter, self-written; 2k lines of generated tests deleted in 2026-06 | none |
| Test time model | `fake_async` + `clock`, `testFakeAsync` driver | `fake_async` + `clock`; widget tests drain GC timers with `binding.delayed(365 days)` | `fake_async` in 4 of 10 files, mostly real `Future.delayed`; **`DateTime.now()`** in the library (10 sites, no `clock`) | `fake_async` + `withClock` in core; real `Future.delayed` in Flutter tests | n/a |
| CI | VM + Chrome core tests, floors job on Flutter 3.27.4, publish dry-runs, `dart doc`, Playwright e2e | 5-version Flutter matrix (3.32 to 3.44), `analyze --no-fatal-*`, Codecov informational | melos bootstrap, format, `analyze --fatal-infos`, test; no coverage | **none** (publish workflows removed 2026-06) | none |
| Docs | READMEs, `coming-from-react-query.md`, dartdoc enforced by lint | fumadocs site (10 MDX pages), migration guide, dated CHANGELOG with before/after snippets | Docusaurus site (23 pages: 8 guides, v2→v3 migration, 5 example pages), nine example apps each with a bloc twin, melos-generated CHANGELOG | long README, partly stale | README |
| Published | no (`0.1.0-dev`) | yes, 160/160 points, 59 versions since 2020 | yes, 160/160, 101 likes, 13.5k downloads/30d, 77 core tags | yes, 155/160, 163 stars, 1.7k downloads/30d | yes, 2021, dormant |
| Maintainer | — | one, bimodal history (abandoned 2023 to 2025, restarted 2025-12) | one, steady since 2021-09, slowing in 2026 (2 to 6 commits/month) | one, health-related slowdown, AI-assisted commits | one, 7 commits |

## 2. Per-project verdicts

### 2.1 jezsung/query — a thoughtful Dart redesign, not a behavioural port

**What it is.** A hooks-only package whose core was rewritten from 2025-12
onward to align with TanStack v5 after the author's earlier "Flutter-style"
attempt was abandoned (survey §3). The Dart surface is the best of the four:
sealed snapshots with non-null `data` on success, sealed option values
(`StaleDuration`, `GcDuration`, `Placeholder`, `Seed`) and `Duration`
arithmetic everywhere. The core has real `networkMode`, an `AbortSignal` with
upstream's consumed-tracking (`abort_signal.dart:147`, `query.dart:37-41`),
`cancelQueries(revert:, silent:)`, `fetchQuery`/`prefetchQuery`/
`ensureQueryData(revalidateIfStale:)`, `fetchInfiniteQuery(pages:)`,
`useMutationState`, and 819 tests.

**Where it diverges structurally.** `Query` stores no options and no
`queryFn`; `Query.refetch()` reads `observers.first` (`query.dart:159-165`),
so an observer-less query can never be refetched by `invalidateQueries` or
`refetchQueries` (`query_client.dart:399`), and `RefetchType.inactive` means
"has observers, all disabled". `setQueryDefaults`/`getQueryDefaults`/
`setMutationDefaults`, `mount`/`unmount`, cache events as public API,
cache-level `onError`/`onSuccess`, `select`, `enabled` as a function,
`refetchIntervalInBackground`, `setQueriesData`, mutation `scope`,
`resumePausedMutations`, `useQueries`, and the stale timeout are absent.
There is no `focusManager`/`onlineManager`: each hook instance installs its
own `AppLifecycleListener` (`use_query_options.dart:56`), and online state is
a `Stream<bool>` constructor argument on the client whose subscription is
never cancelled (`query_client.dart:80`).

**Defects found (four verified by probe):**

1. **Verified.** A thrown value that is not `TError` hangs the fetch forever:
   `RetryController._execute` rethrows inside an unawaited loop
   (`retry_controller.dart:178-180`), the completer never completes,
   `fetchStatus` stays `fetching`, and the error surfaces as an uncaught zone
   error. Mutations cast `error as TError` in the catch (`mutation.dart:180,
   204`). Any `StateError`, `TypeError` or assertion in a query function
   bricks that query.
2. **Verified.** `cancelRefetch: true` with an in-flight fetch corrupts the
   replacement: the cancelled fetch's `finally` unconditionally nulls
   `_abortController`, `_revertState`, `_currentNetworkMode`
   (`query.dart:301-305`) after the new fetch installed its own; the new
   fetch's first failure then self-cancels and crashes on a null
   `_delayCompleter` (`retry_controller.dart:195`). This is the default path of
   `refetch()` and `fetchNextPage()`.
3. **Verified.** `QueryState.isActive` is dropped after every fetch and
   `setData` (`query.dart:131-144, 246-258`): true after mount, false after the
   first success with the observer still mounted.
4. **Verified.** `null` data means "no data" (`query.dart:334`,
   `query_observer.dart:250`): a query whose function returns `null` is always
   stale and refetches on every mount even under `StaleDuration.infinity`.
5. `isFetchNextPageError`/`isFetchPreviousPageError` can never be true from the
   snapshot `fetchNextPage` returns (direction nulled in `finally` before the
   return, `infinite_query_observer.dart:286-290`; previous-page flag tests
   `FetchDirection.forward`, `:92-93`). Fetch direction lives on the observer,
   so a second observer on the same key never sees `isFetchingNextPage`.
6. Deep equality and `hashCode` over `data` on every state set and snapshot
   compare (`query_state.dart:103, 118`; `query_snapshot.dart:197, 213`):
   O(n) per notification per observer, and no reference preservation, so this
   is not `structuralSharing`.
7. `QueryObserver.result` iterates `_listeners` live
   (`query_observer.dart:128`); unsubscribing during notify throws.
8. The two example apps pin 0.5.1 and match on a type removed in 0.11.

The suite did not catch 1 to 5. That is the point about self-written tests:
they test the design the author had in mind, not the behaviours upstream has
accumulated regressions for.

### 2.2 cached_query — the incumbent: widest product, weakest core

**What it is.** A singleton-based library (`CachedQuery.instance`,
`asNewInstance()` for isolation) where a query is an *object*:
`Query<T>(key:, queryFn:, config:)` returns the cached instance for the key,
consumed through `query.stream` (an rxdart `BehaviorSubject`) or awaited
once. Per key there is one `QueryController` owning the state notifier, the
dedup future, the gc timer, storage IO and the retry loop
(`query_controller.dart:43`); `Query`/`InfiniteQuery` are views over it.
Sealed `QueryStatus<T>` = `QueryInitial | QueryLoading | QueryError |
QuerySuccess`, each carrying `data` so previous data survives loading and
error (`query_state.dart:36-269`). Around the core: `StorageInterface` with a
sqflite implementation, a DevTools extension, `connectivity_plus` wiring, app
resume with a 5 s minimum-background debounce, a global observer/logging hook,
a Docusaurus site with 23 pages, and nine example apps each with a bloc twin.
This is the product a Flutter team compares us against.

**Where it is not TanStack.** Keys are `jsonEncode`d
(`util/encode_key.dart:7-10`): **verified** that `{'a':1,'b':2}` and
`{'b':2,'a':1}` are different keys, `'x'` and `['x']` are different keys, and
a non-JSON key part such as `Duration.zero` throws. There is no `fetchStatus`
axis: a background refetch turns `QuerySuccess` into `QueryLoading(data:
old)`, so `isSuccess` is false while refetching. `staleDuration` defaults to
4 s, not 0. `enabled` is a `shouldFetch(key, data, createdAt)` callback
evaluated at fetch time over every registered query object
(`query_controller.dart:206-215`), not a reactive option. Absent: `select`,
`placeholderData`/`keepPreviousData`, cancellation of any kind (no signal,
unsubscribing does not cancel, the result is still stored), `networkMode`,
`meta`, `maxPages`, mutation retry/scope/offline queue, `useQueries`,
partial key matching (only `filterFn(key, encodedKey)`), a hydrate/dehydrate
snapshot API, `initialDataUpdatedAt`. Errors are `dynamic`. `getQuery<T>`
and `QueryBuilder(queryKey:)` are unchecked casts. `RetryConfig` (new in
3.7.0) defaults to zero retries with an uncapped `200ms << (attempt-1)`
backoff. Timestamps come from `DateTime.now()`; nothing uses `clock`.

**Defects found (all verified by probe unless noted):**

1. **Orphaned gc timer deletes an active query.** `scheduleDelete()` never
   cancels an existing timer (`query_controller.dart:371-377`); the
   future-style `fetch()` schedules twice and a later `stream.listen` cancels
   only the newest. After `cacheDuration` the cache drops the key while a
   listener is attached; the next `Query(key)` silently creates a second
   controller.
2. **Per-call instance leak.** `Query(...)` reuses the instance only when
   `config == existing.config` (`query.dart:96-99`); any fresh closure
   (`storageDeserializer`, `pollingInterval`) or a non-const `RetryConfig`
   (no `==`) fails that, so every call creates a new instance that registers
   another notifier listener and, with polling, another periodic timer. Three
   calls: one fetch fires `onSuccess` three times and leaves three timers.
   The bundled example calls its query factory on every scroll tick with
   fresh closures (`post_list_screen.dart:184`).
3. **Invalidation dropped while in flight.** `invalidate()` during a fetch
   sets a flag, joins the running future, and `whenComplete` clears the flag
   (`query_controller.dart:114-119`): one fetch, `stale == false` afterwards.
   Upstream cancels and refetches.
4. `config(observers: const [...])` throws in debug because an `assert`
   appends the DevTools observer to the caller's list
   (`cached_query.dart:113-116`).
5. A throw inside `onSuccess` (invoked synchronously inside the fetch's `try`,
   `query_controller.dart:268-270`) turns a successful fetch into
   `QueryError` and triggers retries.
6. `dispose()` never cancels the polling timer (`query.dart:239-243`).
7. Dedup ignores the second caller's options: `getNextPage()` during an
   in-flight refetch fetches nothing and returns after one page.
8. By reading: `Query._setState` assigns the new state *before* calling
   `observer.onChange` although the interface documents the opposite, so the
   logging observer prints the next state as "Prev State"; `deleteCache`
   removes entries without disposing them; `QueryConfig.==` omits
   `shouldFetch` and `storageDuration`, so the first config wins silently
   (plausibly survey issue #87); `CachedStorage.put` is `void … async` and
   rethrows inside itself; `InternetAddress.lookup('example.com')` cannot run
   on web, and the catch path never updates the status, so
   `refetchOnConnection` likely never fires there (not probed).

Its 201 core tests are real, but none of 1 to 7 is covered: the suite
characterises the library from its own side.

### 2.3 fquery — v4-shaped, popular, and less correct than its README

**What it is.** The most-adopted TanStack-branded port (163 stars). Hooks and
`QueryBuilder`/`MutationBuilder`/`InfiniteQueryBuilder`/`QueriesBuilder`
widgets share one set of core observers, which is the right layering. Keys
compare with `DeepCollectionEquality`. A `QueryCache` reducer driven by a
`DispatchAction` enum mirrors upstream's shape.

**What is missing.** No `fetchStatus` (a bare `isFetching`), no `select`,
`placeholderData`, `initialData`, `structuralSharing`, `networkMode`,
`refetchOnWindowFocus`/`OnReconnect` (no lifecycle code at all in `lib/`),
no exponential backoff (fixed `retryDelay`, `retry_resolver.dart:56-86`),
no signal to the query function, no `QueryClient` (folded into `QueryCache` in
3.0), no `refetchQueries`/`cancelQueries`/`resetQueries`/`fetchQuery`/
`prefetchQuery`, no mutation cache, keys, retry or scopes, no cache events
with payloads. `invalidateQueries` takes `(key, {exact})` only and compares
`jsonEncode` strings for `exact`, which throws on non-JSON key parts
(`query_cache.dart:323`).

**Defects found (by reading, not executed):**

1. **Global cache listeners never fire at HEAD.** `dispatch` always notifies
   with `scope: queryKey` (`query_cache.dart:222`) and scoped notification
   only walks `_scopedListeners[scope]` (`observer.dart:82-88`), so
   `useIsFetching`, `IsFetchingBuilder` and `useQuery`'s own rebuild selector
   are dead since `3b1e1f1` (2026-06-28, unreleased).
2. **Observer leak and zombie refetch.** Observers subscribe scoped
   (`observer.dart:320, 552`) but `dispose()` unsubscribes unscoped
   (`:450, :808`); a later `invalidateQueries` calls the dead observer's
   `fetch()`, whose `query` getter rebuilds the cache entry (`:273-275`).
3. **Non-`Exception` throws hang the query**: `on TError catch`
   (`retry_resolver.dart:77`) lets `Error`s escape an unawaited `fetch()`;
   `isFetching` stays true. Mutations: `err as TError` inside `catch`
   (`mutation_observer.dart:85`) rethrows a `TypeError` and leaves the
   mutation `pending` with no `finally`.
4. **Infinite refetch corrupts data.** `refetch()` fires every page in
   parallel (`observer.dart:678-733`) despite the "sequentially" comment,
   and each result is patched into a snapshot of the *pre-refetch* pages, so
   only the last page is actually refreshed. The one test for it uses
   `queryFn: (page) => page`, where stale and fresh are indistinguishable.
5. `observer.query` has side effects on every read: `cache.build()` copies
   the `CacheMap`, recomputes the gc max and runs the gc routine
   (`query_cache.dart:141-180`); `use_query.dart:131-142` reads it eleven
   times per build.
6. Default `cacheDuration` is 5 min on `QueryCache()` but 5 s on
   `DefaultQueryOptions()` (`query_cache.dart:58` vs `query.dart:313`);
   passing any defaults silently drops gc to 5 s.
7. `useQuery` defers `initialize()` to `addPostFrameCallback`, so the first
   frame renders `isLoading: true, isFetching: false` and the request starts a
   frame late. Listener ids are `hashCode` (collisions overwrite).
   `useQueries` is a likely infinite-rebuild (fresh `QueryOptions` without
   `==` as the `useEffect` key).

### 2.4 flutter_requery (2021) — a prototype, useful only as a baseline

A global `internalCache`, keys restricted to `String`/`int`/lists of them
joined by `_` (so an underscore in a key throws, `utils.dart`), hierarchical
invalidation by string prefix, a `Query` widget that swaps a `Stream` and
rebuilds through `StreamBuilder`, and a response of `data`/`loading`/`error`.
No staleness, no gc, no retry, no dedup, subscribers keyed by `widget.hashCode`.
Its one idea, prefix invalidation, is upstream's `partialMatchKey`, which we
have. Nothing to adopt.

## 3. Feature matrix

`✓` present and faithful, `~` present with a difference, `✗` absent, `(d)`
absent by a recorded decision of ours.

| Feature | ours | jezsung | cached_query | fquery |
|---|---|---|---|---|
| `staleTime` value / `static` / function | ✓ sealed, incl. `.dynamic(fn)` | ~ sealed, no function form | ~ `staleDuration`, default 4 s | ~ `staleDuration`, only read on mount |
| Stale timeout (observer flips `isStale` on time) | ✓ `query_observer.dart:301` | ✗ | ✗ | ✗ |
| `gcTime` | ✓ | ✓ | ~ timer never cancelled on reschedule (verified bug) | ~ two conflicting defaults |
| `enabled` bool / function | ✓ | ~ bool | ~ `shouldFetch` callback at fetch time | ~ bool |
| `retry` / `retryDelay`, exponential | ✓ | ~ merged into one resolver | ~ default 0, uncapped backoff | ~ count + fixed delay |
| `refetchOnMount` / focus / reconnect | ✓ + `.when(fn)` | ~ enums | ~ implicit / `refetchOnResume` + 5 s debounce / `refetchOnConnection` | ~ mount only |
| `refetchInterval` (+ in background) | ✓ | ~ no background flag | ✓ `pollingInterval(state)` + `pollInactive` | ~ cannot be switched off |
| `select` | ✓ | ✗ | ✗ | ✗ |
| `placeholderData` / keepPrevious | ✓ `.compute(prev, prevQuery)` | ✓ `Placeholder.keepPrevious` const | ✗ | ✗ |
| `initialData` (+UpdatedAt) | ~ `initialDataUpdatedAt` value only | ✓ `Seed`, `SeedUpdatedAt.lazy` | ~ counted as fresh | ✗ |
| `structuralSharing` | ✓ typed hook, `replaceEqualDeep` | ~ deep `==` only | ✗ (`timeCreated` in `==`, lists by identity) | ✗ |
| `networkMode` | ✓ | ✓ | ✗ | ✗ |
| Cancellation to the query function | ✓ `QueryCancelToken`, consumed-aware | ✓ `AbortSignal`, consumed-aware | ✗ | ~ result dropped, fn keeps running |
| Dedup (shared in-flight future) | ✓ | ✓ | ~ second caller's options dropped (verified) | ~ second refetch resolves immediately |
| Invalidate during a fetch | ✓ cancel + refetch | ✓ | ✗ dropped (verified) | ✗ |
| `notifyOnChangeProps` | (d) `select` + `buildWhen` | ~ `shouldRebuild` predicate | ~ `buildWhen`/`listenWhen` | ✗ |
| `throwOnError` | (d) sealed error | ~ `refetch(throwOnError:)` | ✗ | ✗ |
| `meta`, `queryKeyHashFn` | ✓ / (d) value-type key | ~ merged across observers / ✗ | ✗ / ✗ (`jsonEncode`, order-sensitive) | ✗ / ✗ |
| `status` + `fetchStatus` | ✓ | ✓ | ✗ loading replaces success | ✗ v4 `status` only |
| Nullable `TData` handled | ✓ `hasData` | ✗ (verified bug) | ✓ `Option<T>` | ✗ |
| Infinite: page params, `maxPages`, sequential refetch | ✓ | ✓ | ~ sequential, `onPageRefetched` early exit, no `maxPages` | ~ parallel refetch, corrupt |
| Infinite: `isFetchingNextPage` on the query | ✓ `fetchMeta` | ~ on the observer | ✓ (no previous-page flag) | ✓ `fetchMeta` |
| Mutation callbacks on options + per call | ✓ | ~ options only | ~ options only; keyed mutation ignores new callbacks | ~ options only, not awaited |
| Mutation retry / cache / key / `scope` / offline resume | ✓ / ✓ / ✓ / ✓ / ✓ | ✓ / ✓ / ✓ / ✗ / ~ in-flight only | ✗ / ~ separate singleton / ✓ / ✗ / ✗ | ✗ / ✗ / ✗ / ✗ / ✗ |
| Mutation-state observer (`useMutationState`) | ✗ | ✓ | ~ keyed mutation stream | ✗ |
| `invalidateQueries` filters + `refetchType` | ✓ all filters, partial keys | ~ no `type`/`stale`/`fetchStatus` | ~ `filterFn` only, `refetchActive`/`refetchInactive` | ~ key + `exact` |
| Refetch of observer-less queries | ✓ | ✗ (structural) | ✓ `refetchInactive` | ✗ |
| `refetch`/`cancel`/`remove`/`resetQueries` | ✓ | ✓ | ~ no cancel | ~ remove only |
| `fetchQuery`/`prefetch`/`ensureQueryData` | ~ one `query()`; no `revalidateIfStale` | ✓ incl. `revalidateIfStale` | ~ `await query.result`, `prefetchPages` | ✗ |
| `setQueryData` / `setQueriesData` | ✓ (`update*` split) | ~ updater only, no `setQueriesData` | ~ creates an upgradeable empty query; `updateQuery` is `dynamic` | ~ updater only |
| `set/getQueryDefaults`, `setMutationDefaults` | ✓ | ✗ | ~ `GlobalQueryConfig` only | ✗ |
| Cache events public + typed | ✓ sealed families, observer events | ✗ `@internal` | ~ global `QueryObserver` hooks (`dynamic`) | ~ zero-arg listeners |
| Cache-level `onError/onSuccess/onSettled` | ✓ | ✗ | ~ global observer `onError`/`onChange` | ✗ |
| `focusManager` / `onlineManager` | ✓ per client, fed by the provider | ✗ per-hook listener / ctor stream | ~ resume/connection controllers in core fed by injectable streams | ✗ |
| Connectivity out of the box | (d) app supplies a `Stream<bool>` | ~ ctor stream | ✓ `connectivity_plus` + `example.com` DNS probe | ✗ |
| Queries observer (`useQueries`) | ✗ (fog, not v1) | ✗ | ✗ | ~ homogeneous list |
| Persistence | ✗ (door: `QueryCache.build(state:)`) | ✗ | ✓ `StorageInterface`, sqflite package, per-query (de)serializer | ✗ |
| Hydrate/dehydrate snapshot | ✗ | ✗ | ✗ | ✗ |
| DevTools | ✗ | ✗ | ✓ extension (query list + JSON tree, singleton only) | ✗ |
| Errors other than `Exception` caught | ✓ `catch (error, stackTrace)` | ✗ (verified hang) | ✓ (`dynamic`) | ✗ (hang, by reading) |
| `clock.now()` only | ✓ | ✓ | ✗ `DateTime.now()` | ✓ |
| Every held future `.ignore()`d | ✓ | ✓ (one rethrow site excepted) | ~ `void async` in storage | ✗ |

## 4. What we do better

1. **Fidelity is proven, not asserted.** 507 core cases carry upstream's names
   and can be diffed against `query/packages/query-core/src/__tests__`;
   `PORTING_NOTES.md` records every omission with a reason. All three living
   competitors test their own design. The concrete payoff: the hangs, the
   cancel-refetch corruption, the `isActive` drop and the nullable-data bug in
   jezsung; the orphaned gc timer, the instance leak and the dropped
   invalidation in cached_query; the parallel infinite refetch in fquery. All
   are behaviours upstream's suite exercises. We hit and fixed the same class
   of bug 22 times while porting, and six reviews found 70 more, each
   reproduced first.
2. **Robustness to non-`Exception` throws.** jezsung and fquery bound errors
   to `TError` and let anything else escape an unawaited loop, leaving the
   query stuck in `fetching`. We catch everything and carry a `StackTrace`
   (`retryer.dart:238`, `QueryError.stackTrace`). cached_query also catches
   everything, but as `dynamic`.
3. **The whole client API.** Defaults per key, cache-level callbacks, typed
   sealed cache events, all filters with partial key matching, `refetchType`,
   `cancelQueries(revert:, silent:)`, mutation scopes and
   `resumePausedMutations`, refetch of observer-less queries. jezsung's query
   object cannot exist without an observer; cached_query has no cancellation
   and no partial matching.
4. **Two-axis state.** `status` plus `fetchStatus` means a background refetch
   never demotes `isSuccess`. cached_query and fquery collapse the two axes;
   cached_query's own issue tracker shows the cost (survey §2).
5. **Keys are value types.** Structural `==`, map order irrelevant, any
   `==`-bearing object allowed, partial matching built in. cached_query's
   `jsonEncode` keys are order-sensitive and throw on non-JSON parts
   (verified); fquery's `exact` path has the same throw.
6. **No hard dependency, four equal call styles.** A `ValueListenable`
   controller underneath, builders, a `State` mixin and a context extension,
   all on `flutter` alone. Every competitor with real adoption has been asked
   for a non-hooks path (survey §7); cached_query's Flutter package pulls in
   `connectivity_plus` for everyone.
7. **One lifecycle listener per app, per-client managers.** Focus and online
   state flow through `client.focusManager`/`client.onlineManager` fed once by
   `QueryClientProvider` (`query_client_provider.dart:139-194`). jezsung
   installs an `AppLifecycleListener` per hook; cached_query's are process-wide
   singletons.
8. **Rebuild economics.** `Defaulted*Options` value equality, resolved-value
   comparison for inline closures, `select` with reference-preserving
   structural sharing, and a debug assertion for conflicting reads in one
   build. jezsung deep-compares the whole `data` payload on every
   notification; cached_query creates a new `Query` instance and listener for
   every call whose config holds a closure; fquery rebuilds on every dispatch.
9. **Instances, not singletons.** Every client is independent, including its
   mutation cache and managers. cached_query's `MutationCache.instance` is
   shared across `asNewInstance()` clients, and its DevTools panel only sees
   the singleton.
10. **Hygiene the reviews enforced:** `clock.now()` only, `.ignore()` on every
    held future, `--fatal-infos`, dartdoc on every public member, a
    JS-compiled test run, a Flutter floor job, an e2e suite against the real
    gateway. cached_query uses `DateTime.now()` throughout; fquery ships
    `freezed` as a runtime dependency.

## 5. What the others do better

1. **cached_query is a product; we are a core.** Persistence with a shipped
   sqflite backend, a DevTools extension, connectivity out of the box, resume
   debounce, a logging observer, 23 doc pages and nine example apps with bloc
   twins. Every one of those is on our not-in-v1 list. A team choosing today
   gets all of it from cached_query and none of it from us.
2. **Docs sites and migration guides.** jezsung: fumadocs, a real "coming from
   TanStack" page, a CHANGELOG with before/after snippets and **Breaking**
   markers. cached_query: Docusaurus, a v2→v3 migration section, deprecations
   kept for a major instead of removed. We have READMEs, one markdown name
   map and dartdoc.
3. **jezsung's ergonomic sugar.** `const StaleDuration(minutes: 5)` because
   the value variant *extends* `Duration` (`query_options.dart:224, 333`);
   `Placeholder.keepPrevious` as a `const Placeholder<Never>`; `Seed.lazy`
   and `SeedUpdatedAt.lazy`; `ensureQueryData(revalidateIfStale:)`;
   `getInfiniteQueryData`; `fetchInfiniteQuery(pages:)` on the imperative
   path; `useMutationState`; a `QueryClientProvider.create` form that owns
   and clears the client on dispose.
4. **cached_query's small ideas.** `refetchOnResumeMinBackgroundDuration`
   (a 5 s debounce so a notification shade does not refetch everything);
   `onPageRefetched` as an early-exit hook when the first page of an infinite
   refetch is unchanged; `QueryListener`/`QueryConsumer` with `listenWhen`
   for side effects without a rebuild; `setQueryData` on an unknown key
   creating an empty query that a later real `Query` upgrades; lifecycle and
   connectivity as plain injected streams so the core tests can drive resume
   without Flutter.
5. **jezsung's CI matrix** runs five stable Flutter versions; we run the
   floor and one current version. Their pre-commit hook runs the same gates
   locally.
6. **Hooks and bloc integration.** jezsung and fquery ship `useQuery`;
   cached_query documents `emit.forEach(query.stream, …)` for bloc and ships a
   bloc twin of every example. Our ruling defers hooks to an opt-in package;
   we have no bloc recipe at all, and `stream` is not on our controller
   (`ValueListenable` is).
7. **fquery has `useQueries`/`QueriesBuilder`**, homogeneous but present; we
   have no `QueriesObserver`.
8. **All three are published, with users and issue trackers.** Until we
   publish, every claim in §4 is unfalsified by strangers.

## 6. What to adapt

Ordered by value over cost. Nothing here contradicts a closed decision unless
marked.

| # | Adapt | From | Cost | Note |
|---|---|---|---|---|
| 1 | A **docs site** with a "coming from React Query" page as the first entry, built from `docs/coming-from-react-query.md` and the two READMEs. | jezsung, cached_query | medium | The single largest DX gap. A static generator that reads our markdown is enough; `dart doc` alone is not a site. |
| 2 | **Persistence as the next ticket**, with cached_query's `StorageInterface` as the input: `get/put/delete/deleteAll/close`, a `StoredQuery{key, data, createdAt, expiry}` row, per-query (de)serializers, staleness judged against the stored time, and a shipped `sqflite` or `shared_preferences` backend as a separate package. Our door is `QueryCache.build(state:)`; upstream's `persistQueryClient` is the shape to port. | cached_query, upstream | large | On the not-in-v1 list. It is the first thing a team asks for after caching (survey §2 and cached_query's download count). Ship it as its own package to keep the main package dependency-free. |
| 3 | **Resume debounce**: a minimum background duration before a focus regain counts as a refocus, on `AppFocusManager` or the provider. | cached_query | small | We have none (`query_client_provider.dart`). Upstream has none either, but Flutter's `inactive`/`resumed` churn on a notification shade makes it worth a divergence note. |
| 4 | **`PlaceholderData.keepPrevious`** as a named const (today `.compute((prev, _) => prev)`). | jezsung | tiny | Pure sugar over `query_options.dart:181-258`. |
| 5 | **`revalidateIfStale` on the imperative path**: return cached data immediately and kick a background refetch if stale. Today `client.query` either awaits the fetch or, with `StaleTime.static`, never refetches. | jezsung, upstream | small | Fits `client.query` as a named parameter; #17 chose one method, this stays inside it. |
| 6 | **`InitialData.updatedAt` function form** (`SeedUpdatedAt.lazy`). Recorded as unported; costs one sealed variant. | jezsung | tiny | Closes a row of the divergence table. |
| 7 | **`QueryClientProvider.create`** (or `owns: true`): the provider builds and `clear()`s the client on dispose. Today the app must remember `client.clear()`; every binding widget test ends with it by hand. | jezsung | small | Keep the current `client:` form as-is. |
| 8 | **`QueryListener` / `listenWhen`** for side effects (snackbar on error, navigation on success) without a rebuild, and a bloc recipe in the README (`ValueListenable` to `Stream` is three lines). | cached_query | small | The builders have `buildWhen`; a listener is the missing sibling. |
| 9 | **Mutation-state observer** (`useMutationState` equivalent, a `ValueListenable<List<MutationState>>` with filters and `select`). | jezsung, upstream | medium | `MutationCache.findAll` + `subscribe` is the raw door; the observer is what a "pending mutations" badge wants. |
| 10 | **DevTools extension** using `developer.postEvent` from a cache listener plus VM-service eval on the extension side; zero protocol surface in the library. | cached_query | medium | Our typed cache events make the app side trivial; the extension is a separate unpublished package, as cached_query does it. Note their panel only sees the singleton; ours would need a registry of live clients. |
| 11 | **Duration-literal constructors** for the sealed time types, e.g. `StaleTime(minutes: 5)` alongside `StaleTime.duration(...)`. | jezsung | small | Ergonomics only; do not make the type extend `Duration` (§7). |
| 12 | **CI matrix**: one or two intermediate Flutter stables between the floor and current. | jezsung | small | Cheap insurance; the floor job already caught three pins. |
| 13 | **`QueriesObserver`** (`useQueries`). Heterogeneous typing is the hard part in Dart; fquery's homogeneous list is the honest v1. | fquery, upstream | medium-large | Currently "fog, not v1". Worth a ticket now that a port ships something. |
| 14 | **Hooks as the opt-in package** the ruling allows, thin over `QueryController`. | jezsung, fquery | small | `useValueListenable` already works; a package with `useQuery`/`useMutation` names removes the last reason to pick fquery. Does not touch the main package. |
| 15 | `getInfiniteQueryData` typed read; a `.githooks/pre-commit` running the module gate. | jezsung | tiny | |

## 7. What not to adopt, and why

- **A singleton cache.** cached_query's `CachedQuery.instance` is why its
  mutation cache leaks across instances, its DevTools sees one client, and
  its tests need `asNewInstance()` everywhere. Our per-client managers and
  caches are the better shape.
- **`jsonEncode`d keys.** Order-sensitive, throw on non-JSON parts, and make
  `'x'` and `['x']` different queries (verified in cached_query). Our
  `QueryKey` value type is what upstream's `hashKey` means.
- **Collapsing `fetchStatus` into `status`.** cached_query and fquery both
  demote `isSuccess` during a refetch; the two-axis state is the point of v5.
- **`TError` generics.** jezsung and fquery bound the error type and both
  hang on anything outside the bound. Our `Object error` + `StackTrace` is
  the reason we cannot. `dynamic` errors (cached_query) are the other extreme.
- **A connectivity dependency in the main package.** cached_query pulls
  `connectivity_plus` plus a DNS probe to `example.com` into every app, and it
  cannot work on web. The ruling stands: the app supplies the stream; a
  recipe is in the binding README.
- **Sealed time types that extend `Duration`.** Reads well for values, but
  `static`/`infinity` then *are* `Duration`s with sentinel values, which is the
  magic-number problem #10 removed.
- **`meta` deep-merged across observers** (jezsung). Upstream's last-writer
  semantics are what the ported tests assert.
- **`refetchOnWindowFocus` renamed `refetchOnResume`.** Tempting for Flutter,
  but the name is what a React reader greps for, and `RefetchOn.when(fn)`
  already covers the semantics. A dartdoc alias is enough.
- **Post-frame deferral of `initialize()`** (fquery). It costs a frame and a
  wrong first result; our provider defers *notifications* during build
  (`query_client_provider.dart:207-228`) and starts the fetch immediately.
- **Deep `==` on `data` as a substitute for structural sharing** (jezsung),
  or `timeCreated` inside state equality (cached_query), which makes every
  fetch a new state even when nothing changed.
- **`onPageRefetched` early exit** as a public option. Nice for one use case,
  but it is not upstream behaviour; `select` plus structural sharing gives the
  same "nothing changed, no rebuild" result without a new option.

## 8. Follow-ups

- The pub.dev name `flutter_query` belongs to jezsung; our repo is named
  `flutter_query` but the packages are `tanstack_query_*`. The README should
  say so once, so a search for either lands on the right thing (see
  `package-naming-and-affiliation.md`).
- Items 4, 6, 7, 8 and 15 in §6 are a day's work together and each closes a
  visible gap. Items 1 and 2 are what a first pub.dev reader will compare
  against cached_query; item 3 is the one behaviour cached_query got right
  that neither upstream nor we have.
- cached_query's issue tracker (survey §2: `refetchOnResume` refetching
  inactive queries, resume while offline, stuck infinite query) is a
  ready-made checklist for our managers and infinite observer; each item
  should have a ported or port-specific case, and most already do.
