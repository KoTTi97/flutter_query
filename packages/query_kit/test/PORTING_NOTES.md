# Porting notes

What this file is: the audit trail behind the port's central claim — *upstream's
behaviour, proven by upstream's own tests*. Every upstream case in a ported
suite is accounted for here as **ported**, **adapted** (with why), or
**omitted** (with which allowed category it falls in). A gap that is not listed
is a bug in this file.

- **Upstream revision:** `50680b98c` (`main`, 2026-09-08).
- **The policy that governs this file:**
  [#18](https://github.com/KoTTi97/flutter_query/issues/18).
- One Dart file per upstream file; upstream test names kept verbatim; a failing
  ported test means the port is wrong until proven otherwise.
- Port-only tests (no upstream counterpart) live in `smoke_test.dart`, and
  regressions found by review rather than by a ported case live in
  `port_specifics_test.dart`.

## Status

| Upstream suite | Dart file | Cases | State |
|---|---|---|---|
| `subscribable.test.tsx` | `subscribable_test.dart` | 9 / 9 | done |
| `notifyManager.test.tsx` | `notify_manager_test.dart` | 6 / 7 | done |
| `focusManager.test.tsx` | `focus_manager_test.dart` | 6 / 9 | done |
| `onlineManager.test.tsx` | `online_manager_test.dart` | 6 / 11 | done |
| `removable.test.tsx` | `removable_test.dart` | 11 / 12 | done |
| `retryer.test.tsx` | `retryer_test.dart` | 13 / 13 | done |
| `query.test.tsx` | `query_test.dart` | 44 / 51 | done |
| `queryCache.test.tsx` | `query_cache_test.dart` | 14 / 16 | done |
| `queryObserver.test.tsx` | `query_observer_test.dart` | 62 / 75 | done |
| `queryClient.test.tsx` | `query_client_test.dart` | 106 / 156 | done |
| `queriesObserver.test.tsx` | `queries_observer_test.dart` | 12 / 22 | applicable cases done; combine/suspense/property tracking excluded |
| `mutation.test.tsx` | `mutation_test.dart` | 28 / 28 | done |
| `mutationCache.test.tsx` | `mutation_cache_test.dart` | 16 / 16 | done |
| `mutationObserver.test.tsx` | `mutation_observer_test.dart` | 16 / 16 | done |
| `infiniteQueryBehavior.test.tsx` | `infinite_query_behavior_test.dart` | 7 / 9 | done |
| `infiniteQueryObserver.test.tsx` | `infinite_query_observer_test.dart` | 6 / 7 | done |
| `utils.test.tsx` | `utils_test.dart` | 47 / 78 | done |

**What "Cases" counts:** upstream cases ported out of the upstream cases in
that suite — nothing else. A ported file may also hold port-only cases (a Dart
behaviour upstream has no case for, or an upstream case split in two because
Dart separates what TypeScript ran in one body), and those count in neither
column: `subscribable_test.dart`, for one, runs 11 cases for its 9 / 9 row. The
rule about where port-only tests live holds for whole *files* with no upstream
counterpart; a case that belongs beside its ported neighbours stays there,
named so it reads as the addition it is.

Suites not ported at all, each for one recorded reason:
`hydration.test.tsx` (hydration is out of v1 scope, #17),
`timeoutManager.test.tsx` (the module is not ported, #9),
`environmentManager.test.tsx` (no SSR),
`streamedQuery.test.tsx` (experimental upstream; the Dart `Stream` mapping is
fog).

The totals at the 0.1.0 tag: 17 suites, 409 of their 535 upstream cases
ported, and `dart test` runs 586 tests — the port-only cases
(`smoke_test.dart`, `functional_improvements_test.dart`, `barrel_test.dart`)
and the review regressions (`port_specifics_test.dart`,
`port_lifecycle_test.dart`) included — on the VM and compiled to JavaScript.

## Omissions and adaptations, by suite

### `queriesObserver.test.tsx`

- **ported/adapted (12):** the first eleven cases and `should subscribe to
  new observers when a query is added while subscribed`. The list is
  homogeneous; `currentResult` and `observers` are Dart getters, and queries
  are available through each observer's `currentQuery`.
- **adapted:** duplicate keys retain distinct observers by occurrence while
  sharing a cache entry. All occurrences report their actual fetching state;
  the upstream test's transient idle duplicate is not reproduced. The case
  asserts final data, independent observers and a single fetch per key.
- **omitted (10):** the eight cases between `should update combined result
  when queries are added with stable combine reference` and `should return
  cached combined result when nothing has changed` concerning combine,
  suspense and fallback results; plus `should return observer result directly
  when notifyOnChangeProps is set` and `should track properties on all
  observers when trackResult is called`. These APIs are outside the adopted
  homogeneous collection surface.

### Functional additions from the competitor analysis

The accepted implementation plan is
[`functional-improvements.md`](../../../docs/plans/functional-improvements.md).
`functional_improvements_test.dart` covers Dart-specific revalidation,
nullable data, typed infinite reads, const keep-previous placeholders,
cache-wide mutation selection, lazy seed timestamps and focus thresholds.
The binding's same-named suite covers owned providers, borrowed-controller
listeners, mutation-state controllers and query collections.

- A focus threshold defaults to zero. Short absences suppress only new focus
  refetches; paused work still resumes. The threshold decision is captured
  before awaiting paused mutations, so another focus event cannot alter it.
- Mutation selection uses structural sharing over an immutable outer list.
  It subscribes to the cache only while observed and retains concurrent runs
  sharing a mutation key.
- Both collection observers isolate throwing listeners, matching the existing
  observers. Query collection subscriptions are guarded while their initial
  synchronous notification runs, so a reentrant `setQueries` cannot install
  an extra listener and lose its unsubscribe handle. Both regressions were
  reproduced before fixing and are in `functional_improvements_test.dart`.
- `initialDataUpdatedAtCompute` is optional and evaluated only for actual
  seeding. `copyWith` supplying one timestamp form replaces the previous
  alternative. Supplying both is rejected during option defaulting.
- `PlaceholderData.keepPrevious()` deliberately keeps `.compute`'s existing
  nullable-data semantics: a previous null means no placeholder.

### `notifyManager.test.tsx`

- **omitted — type-level:** `typeDefs should catch proper signatures`.
  `expectTypeOf`/`assertType` have no Dart equivalent, and the inference it
  guards does not exist as a question here (#7, #18 §4).
- **adapted:** `should batch calls correctly`. Upstream's `batchCalls` is
  variadic; Dart has no variadics, so the two arguments travel as one record
  and the assertion is on the record. Same behaviour, one call shape.

### `focusManager.test.tsx`

- **omitted — browser environment (3):**
  `cleanup (removeEventListener) should not be called if window is not defined`,
  `... if window.addEventListener is not defined`, and the `addEventListener`
  spy half of `should call removeEventListener when last listener unsubscribes`.
  There is no `window` in Dart and no default DOM adapter to install; the
  Flutter binding's `AppLifecycleListener` adapter is covered by that package's
  own tests.
- **adapted:** `should return true for isFocused if document is undefined` —
  upstream deletes `globalThis.document` to show the manager defaults to
  focused. Pure Dart has nothing to ask in the first place, so the assertion is
  made against the default.
- **adapted:** `should call removeEventListener when last listener
  unsubscribes` — asserts the *installed adapter's cleanup* runs on the last
  unsubscribe, which is the behaviour the DOM spy was standing in for.

### `onlineManager.test.tsx`

- **omitted — browser environment (5):** the two `navigator.onLine` spies, the
  two `window`-undefined cleanup cases, and
  `should update online status from window online and offline events`. The
  Flutter binding's `connectivity_plus` adapter is tested in that package.
- **adapted:** `isOnline should return true if navigator is undefined` and
  `should call removeEventListener when last listener unsubscribes`, for the
  same reasons as the focus manager.

### `removable.test.tsx`

- **omitted — SSR:** `should default to Infinity on the server` (#9: no server
  environment).
- **adapted — all remaining cases:** upstream asserts against a mock
  `timeoutManager` provider (`setTimeout` called with `123`, `clearTimeout`
  called with that id). `timeoutManager` is not ported (#9), so each case
  asserts the *effect* under virtual time instead: that `optionalRemove` runs
  when the gc time elapses and not before, that no timer is scheduled for
  `GcTime.never`, and that rescheduling or clearing leaves the expected number
  of pending timers. This is a stronger test of the same behaviour — it would
  catch a provider that was called correctly but wired to nothing.

### `retryer.test.tsx`

- **adapted:** `should use the default exponential backoff capped at 30
  seconds`. Upstream reads the delay sequence off a `setTimeout` spy; here the
  delay is a pure function (`RetryDelay.resolve`), so the sequence
  `[1s, 2s, 4s, 8s, 16s, 30s]` is asserted directly *and* the retry loop is run
  to success, which proves the same schedule actually drives it.
- **adapted:** the module-level `focusManager`/`onlineManager` that upstream
  resets in `beforeEach` are per-test instances here (#19), so the suite needs
  no global reset and cannot leak into another test.
- **note:** `canFetch` is exported from `retryer.dart` exactly as upstream
  exports it, so `should reflect network availability in canFetch and canStart`
  ports unchanged apart from taking the manager as an argument.

**One adapted assertion (2026-09-09):** `queries with gcTime 0 should be
removed immediately after unsubscribing` expects the query function to have run
once; here it runs twice. Upstream's observer rejoins the query it last watched
even after the cache has collected it, and shows that dead query's data without
fetching; this port re-resolves the key on resubscribe (see "resubscribe after
gc" in the second review below), and a collected query has no data left to
show, so the second subscription fetches. The rest of the case — removal
immediately after unsubscribe, both times — is unchanged.

### `queryCache.test.tsx`

- **omitted — hashKey identity (2):**
  `build > should compute queryHash from queryKey when queryHash is not
  provided` and `build > should use provided queryHash instead of computing
  it`. There is no `queryHash` here: the cache is keyed by the [QueryKey] value
  itself and `queryKeyHashFn` was dropped, so a per-query hash override has
  nothing to override
  ([#8](https://github.com/KoTTi97/flutter_query/issues/8)). What the two cases
  actually guard — one key, one query — is covered by `QueryCache.add` below
  and by `smoke_test.dart`'s key-equality cases.
- **adapted:** `QueryCache.remove > should only delete the instance currently
  stored under its queryHash` → `... under its key`, same reason.
- **adapted:** `QueryCache.add > should not try to add a query already added to
  the cache`. Upstream shallow-clones the query with `Object.assign({}, query)`,
  which Dart cannot do to a class instance; the port builds a second `Query`
  under the same key instead. Same assertion, and it additionally checks the
  original instance is the one that stayed.
- **adapted:** the two `QueryCacheConfig` callback suites. Upstream's callbacks
  take `(data, query)` / `(error, query)`; here `onError` and `onSettled` also
  carry the `StackTrace`
  ([#7](https://github.com/KoTTi97/flutter_query/issues/7)), and the payload is
  asserted field by field because Dart records compare with `==` and two equal
  `Map`s are not `==`.
- **adapted:** every `queryClient.query({...})` call site — upstream's
  `void queryClient.query(...).catch(noop)` is `queryClient.query(...).ignore()`.

### `query.test.tsx`

- **omitted — SSR (2):** `should not retry on the server`,
  `should use an infinite garbage collection time on the server`. There is no
  `isServer` here; `environmentManager` is not ported
  ([#9](https://github.com/KoTTi97/flutter_query/issues/9)).
- **omitted — hydration (1):** `should reset to default state when created from
  hydration`. Hydration is out of the v1 scope
  ([#17](https://github.com/KoTTi97/flutter_query/issues/17)); the state door it
  would use (`QueryCache.build(..., state:)`) exists and is covered by
  `smoke_test.dart`.
- **omitted — undefined guards (1):** `fetch should dispatch an error if the
  queryFn returns undefined`. `Future<T>` with a non-nullable `T` cannot produce
  it, and with a nullable one `null` is a legitimate value
  ([#7](https://github.com/KoTTi97/flutter_query/issues/7)).
- **omitted — type-level (1):** `should log error when queryKey is not an
  array`. `QueryKey` is a value type; a `String` does not typecheck
  ([#8](https://github.com/KoTTi97/flutter_query/issues/8)).
- **omitted — replaceEqualDeep (1):** `should have an error log when queryFn
  data is not serializable`. Nothing here requires data to be JSON
  serializable ([#12](https://github.com/KoTTi97/flutter_query/issues/12)); the
  case it guards — a throwing structural-sharing step ending in an error state
  — is the *next* upstream case, which is ported.
- **omitted — option not ported (1):** `should use persister if provided`. The
  `persister` option belongs to upstream's experimental persister package and
  is not part of the v1 surface
  ([#15](https://github.com/KoTTi97/flutter_query/issues/15)).
- **adapted:** `constructor should call initialDataUpdatedAt if defined as a
  function` uses the additive `initialDataUpdatedAtCompute` callback. The
  existing `DateTime?` field remains supported. Providing both is rejected
  when options are defaulted, preserving const option constructors. The
  callback runs only when seed data exists; null falls back to `clock.now()`.
- **adapted:** `should work with initialDataUpdatedAt set to zero` → `... set to
  the epoch`. The case guards a JS falsy-zero hazard; `DateTime` has no such
  hazard, so it asserts the epoch survives as a timestamp.
- **adapted (4):** upstream's page-visibility and `navigator.onLine` mocks are
  `client.focusManager.setFocused(...)` and `client.onlineManager.setOnline(...)`
  on the client's own managers
  ([#19](https://github.com/KoTTi97/flutter_query/issues/19)).
- **adapted (3):** the three `vi.spyOn` cases. There is no spy here, so each
  asserts the effect instead: `should refetch the observer when online method is
  called` lets the first fetch settle and counts query-function calls (asserting
  mid-flight would prove nothing — a refetch with `cancelRefetch: false`
  piggybacks on the running fetch, upstream too); `should not try to remove an
  observer that does not exist` subscribes to the cache and asserts no event;
  the `AbortSignal` listener case uses `QueryCancelToken.onCancel`.
- **adapted (2):** `should use queryFn from observer if not provided in options`
  and `should call initialData function when it is a function` construct a
  `Query` directly upstream. A `Query` here is always born into a cache, so both
  build through `QueryCache.build`.
- **adapted (1):** `should provide context to queryFn` no longer asserts
  `args.pageParam` is undefined. `QueryFunctionContext` has no `pageParam` (or
  `direction`): nothing ever set them, because an infinite query's page
  function is handed its own typed `InfinitePageContext` (A5, below).
- **note:** the suite's name `should not throw a CancelledError when fetchQuery
  is in progress ...` is kept verbatim even though the method is now
  `QueryClient.query`.

**Four port bugs this suite caught** — all four invisible to a test written
from the Dart side:

1. `#abortSignalConsumed` was set *after* the query function returned, so
   `removeObserver` could not tell a cancellable fetch from an uncancellable
   one. It is now set by the `signal` getter itself, and reset per attempt
   exactly where upstream resets it.
2. The silent-cancel branch of `Query.fetch` only piggybacked on a *different*
   retryer, so a silent cancel with no successor dispatched an error into the
   query's state. Upstream returns `this.#retryer.promise` unconditionally.
3. `Query.fetch` awaited its own `cancel(silent: true)`, which let the
   cancelled fetch's `catch` run before the replacement retryer was installed.
   Upstream does not await it.
4. `QueryObserver`'s constructor never called `query.setOptions(...)`, so a
   late `initialData` never reached a query created by a bare prefetch — and
   the seeding itself replaced the whole state instead of merging the success
   fields, which would have wiped a fetch in flight.

Two smaller ones came with them: `_executeFetch` defaulted `cancelRefetch` to
`true` where upstream's unset value is falsy, and `invalidateQueries` refetched
with `cancelRefetch: false` where upstream's default is `true`.

### `queryObserver.test.tsx`

- **omitted — dropped observer feature (5):** the two `notifyOnChangeProps`
  cases and the three `throwOnError` / `trackResult` / `trackProp` cases. Both
  features are React-render-scheduling machinery that
  [#15](https://github.com/KoTTi97/flutter_query/issues/15) replaced with
  `select` plus the binding's own rebuild filter, and with errors living in the
  sealed result.
- **omitted — React-only (3):** the two `fetchOptimistic` cases (suspense's
  primitive, and suspense is dropped) and
  `should set fetchStatus to idle when _optimisticResults is isRestoring`
  (`isRestoring` belongs to the React persist/restore boundary).
- **ported since the third review (2):** `should structurally share the
  selector` and `should structurally share placeholder data`. Both assert
  reference identity across two runs that produce equal values, which
  `replaceEqualDeep` now provides here too (see the third review below).
- **omitted — no off switch for select output (2):** the two `should not use
  replaceEqualDeep for select value when structuralSharing option is ...`
  cases. `structuralSharing: false` has no counterpart for what `select`
  produces: the typed hook governs the cache write and the placeholder, and a
  selector's output always goes through `replaceEqualDeep` (in the table
  below).
- **omitted — SSR (1):** `should not schedule timers on the server`.
- **omitted — type-level (2):** `should throw an error if enabled option type is
  not valid` (`Enabled` is a sealed type; an invalid value does not typecheck)
  and `should be able to fetch with a selector and object syntax`, which is the
  previous case again in TypeScript's other call syntax.
- **adapted:** `should not schedule timers for disabled observers` counts the
  zone's pending timers through the harness (`time.pendingTimers`) instead of
  spying on `timeoutManager` — and asserts *zero*, since adding an observer
  cancels the query's gc timer and a disabled observer must schedule nothing in
  its place.
- **adapted (3):** the `refetchInterval`/`refetchOnWindowFocus` callback cases
  collect the query they were handed instead of asserting on a spy's arguments.
- **adapted:** `should resolve with data when signal was consumed` drops
  upstream's `'data' + String(signal)` — that string is JS's `[object
  AbortSignal]`. The case's point, that the second subscribe re-runs the query
  function and still resolves, is asserted directly.
- **adapted:** `staleTime: Infinity` reads as `StaleTime.infinite`, and the
  `enabled` / `staleTime` / `refetchInterval` / `refetchOnWindowFocus` callback
  forms as their sealed `.when` / `.dynamic` constructors
  ([#10](https://github.com/KoTTi97/flutter_query/issues/10)).

**One port bug this suite caught:** `_createResult` selected placeholder data
inside the placeholder branch instead of leaving it for the shared `select`
step, so a successful selection over a placeholder never cleared a *stale*
select error from a previous query — and the select-error branch dropped the
last good select result instead of keeping it behind the error. Both are now
upstream's shape: one `select` step over "query data or placeholder", and
`data = selectResult` when a selector throws.

### `queryClient.test.tsx`

106 ported and 34 omitted (the 25 infinite cases were deferred until
[#16](https://github.com/KoTTi97/flutter_query/issues/16) and are ported now —
see the infinite section below).

- **omitted — deprecated upstream API (16):** `fetchQuery` (9),
  `ensureQueryData` (4) and `prefetchQuery` (3) cases. Upstream deprecated all
  three at this pin in favour of `queryClient.query`, and pairs each block with
  a modern equivalent — `query with static staleTime`, `query`, `query used for
  prefetching` — which *are* ported
  ([#17](https://github.com/KoTTi97/flutter_query/issues/17)). The ordinary and
  infinite `revalidateIfStale` cases are now adapted to named parameters on
  `query` and `infiniteQuery`, retaining their upstream test names.
- **omitted — option not ported (3):** the three `defaultQueryOptions` cases,
  all about `persister` defaulting `networkMode` to `offlineFirst`.
- **omitted — hashKey identity (1):** `setQueryData > should use default
  options`, which sets a `queryKeyHashFn`
  ([#8](https://github.com/KoTTi97/flutter_query/issues/8)).
- **omitted — undefined/falsy guards (3):** the two `setQueryData` cases that
  pass `undefined` as data, and `query with static staleTime`'s "cached query
  data is falsy". `setQueryData` takes a non-nullable value here and
  `updateQueryData` returning `null` means "leave it alone" — both of which are
  ported; and `null` is a value like any other in Dart, not a falsy hole.
- **omitted — skipToken (6):** four in `query`, one in `invalidateQueries`, and
  the third observer of `resetQueries > should refetch all active queries`
  (adapted by dropping it). `skipToken` is `Enabled.no` here
  ([#17](https://github.com/KoTTi97/flutter_query/issues/17)), and the
  imperative path has no equivalent — it fetches by definition.
- **omitted — no `select` on the imperative path (3):** `should fetch when
  disabled and apply select`, `should apply select when data is fresh in cache`,
  `should apply select to freshly fetched data`. `query()` keeps one type
  parameter and the transform is a `.then` at the call site
  ([#7](https://github.com/KoTTi97/flutter_query/issues/7)), so these would
  assert Dart's `await`, not the library's.
- **omitted — type-level (2):** the two surviving `should not type-error with
  strict query key` cases.
- **omitted — dropped observer feature (1):** `refetchQueries > should throw an
  error if throwOnError option is set to true`
  ([#15](https://github.com/KoTTi97/flutter_query/issues/15)).
- **omitted — hydration (1):** `should resumePausedMutations when coming online
  after having restored cache (and resumed) while offline`.
- **adapted:** `setQueriesData` reads as `updateQueriesData`, and
  `setQueryData(key, updaterFn)` as `updateQueryData` — Dart cannot overload on
  "a value or a function"
  ([#17](https://github.com/KoTTi97/flutter_query/issues/17)).
- **adapted:** `setQueryDefaults > should merge defaultOptions` uses `retry`
  where upstream uses `suspense`, which is dropped.
- **adapted:** `should set the new data without comparison if structuralSharing
  is set to false` turns sharing off with the identity function,
  `(_, next) => next`, which is the port's `false`
  ([#12](https://github.com/KoTTi97/flutter_query/issues/12), revised by the
  third review: sharing is now on by default, as upstream).
- **adapted (4):** the `focusManager`/`onlineManager` spy cases. Without
  `vi.spyOn` there is nothing to count, so each asserts the effect: a refetch
  happens (or does not) after the event, and the mount/unmount balance is read
  the same way. The "resumePausedMutations was called" half of the first two is
  unobservable when nothing is paused, and is covered by the online cases that
  watch a real resumption.
- **adapted:** `should throw an error if throwOnError option is set to true`'s
  neighbours use `expectLater(..., throwsA(...))` where upstream uses
  `rejects.toEqual`.

**Four port bugs this suite caught:**

1. `QueryClient.cancelQueries` defaulted `silent: true`. Upstream defaults only
   `revert: true` — a silent cancel means "a new fetch is taking over", which an
   explicit cancel is not, so the cancelled fetch neither reverted nor
   dispatched its error.
2. `Mutation.execute` created its retryer *after* `onMutate` and the cache's
   `onMutationStarting`, so a mutation that paused before that point had nothing
   for `continueMutation` to continue — it was resumed only by accident, when a
   later `canStart()` happened to be true.
3. `MutationCache.resumePaused` resumed paused mutations one after another,
   making each wait for the slowest one before it. Upstream resumes them all at
   once; what serialises mutations is the scope rule, not the resume order.
4. `QueryClient.mount`'s focus and online listeners fired `queryCache.onFocus` /
   `onOnline` without waiting for the paused mutations to finish, so a refetch
   could overtake the mutation it was meant to reflect and show the server's
   pre-mutation state. Fixing it needed the guard upstream has too:
   `resumePausedMutations` is a no-op while still offline, or the listener would
   await a future that cannot complete.

**One design gap it exposed:** neither `QueryDefaults` nor `MutationDefaults`
could carry a `queryFn` / `mutationFn`, so `setQueryDefaults(key, {queryFn})` —
a shared fetcher per key prefix, and upstream's own idiom in these tests — was
not expressible. Both now carry an *erased* one (`QueryFn<Object?>`), adapted to
the call site's type by `defaultQueryOptions` and throwing `QueryDataTypeError`
on a mismatch: the same bargain [#7](https://github.com/KoTTi97/flutter_query/issues/7)
already struck for the cache's typed reads. `structuralSharing` joined them for
the same reason. A debug assert that fired when several key prefixes matched one
query also had to go: upstream merges them deliberately, and
`['todos']` + `['todos', 'detail']` is the intended shape.

### `mutation.test.tsx`

All 28 ported — the first suite with no omissions at all.

- **adapted:** `setMutationDefaults should be able to set defaults` drops the
  assertion on the mutation function's second argument. Upstream passes a
  `MutationFunctionContext` (`client`, `meta`, `mutationKey`) alongside the
  variables; `MutationFn` here takes variables only (see the divergence table).
- **adapted:** `mutate should throw an error if no mutationFn found` expects
  `MissingMutationFunctionError` rather than upstream's string-matched
  `Error('No mutationFn found')` — the query side has the same named error.
- **adapted (3):** the three "return value is ignored" callback cases.
  `FutureOr<void>` callbacks cannot return a value in Dart, so the type system
  makes the point the assertion was making; the *timing* those cases pin down is
  ported unchanged.
- **adapted:** `should handle Promise.all() and Promise.allSettled() patterns` →
  `should handle Future.wait() patterns`.
- **adapted (3):** the cases that assert on `process.on('unhandledRejection')`
  use `testFakeAsyncGuarded`, which collects what the zone reports — the same
  thing, spelled in Dart. `Zone.current.handleUncaughtError` is this port's
  `void Promise.reject(e)`.
- **adapted (2):** the mutation-state assertions compare the fields that exist
  here rather than a whole object literal: `context` is `onMutateResult`,
  `submittedAt` is a `DateTime`, and errors carry a `StackTrace` beside them.

**Six port bugs this suite caught,** all of them in how a mutation's callbacks
and its retryer are sequenced:

1. `Mutation.execute` ran `onMutate` and the cache's `onMutate` *outside* its
   `try`, so a failing `onMutate` skipped the whole error path — no `onError`,
   no `onSettled`, no error state.
2. The error path let a failing callback replace the error the caller was
   waiting for. Each callback is now isolated, reporting its own failure to the
   zone exactly as upstream re-throws it into a fresh execution context.
3. The cache's `onSuccess`/`onSettled` ran back-to-back, so a global `onSettled`
   preceded the *local* `onSuccess`. They now interleave: cache hook, then
   per-mutation hook, for each of success and settled.
4. A restored (persisted, paused) mutation was never unpaused, because nothing
   dispatched `continue` on the restart path.
5. `MutationObserver`'s per-call `onSuccess`/`onSettled` fired even with no
   subscription. They belong to a live subscription — a `mutate` whose widget is
   gone must still update the cache, but must not call back into it.
6. `Mutation.continueMutation` did nothing when there was no retryer, which is
   exactly the state a mutation restored from persistence is in. It now runs the
   mutation, which is how an offline mutation survives a restart — while a
   *settled* one still refuses to run twice.

The suite also needed two things the port did not have: mutation-observer cache
events (`observerAdded` / `observerRemoved`, mirroring the query cache) and a
named `MissingMutationFunctionError`.

### `mutationCache.test.tsx`

All 16 ported.

- **adapted (3):** the callback cases drop the assertion on the
  `MutationFunctionContext` argument, which is not ported (see the divergence
  table), and compare the payload field by field — two equal Dart `Map`s are
  not `==`.
- **adapted:** `should be garbage collected later ...` and its neighbours read
  `MutationCache.mutations` where upstream calls `getAll()`.

**Three port bugs this suite caught:**

1. `Mutation.removeObserver` removed a settled mutation from the cache *on the
   spot* instead of scheduling its collection, so unmounting a widget could cut
   a mutation's own callbacks short. The pending-vs-settled decision belongs in
   `optionalRemove`, where the gc timer lands — and while pending it now does
   nothing at all, because `execute` schedules the next collection when it
   settles. Re-arming there would spin forever on `gcTime: Duration.zero`.
2. The cache-level `onMutate` hook was always awaited, even when nothing was
   registered, which pushed a *synchronous* per-mutation `onMutate` behind a
   microtask — long enough for a caller to read the pre-optimistic state. Both
   are now awaited only when they actually return a future.
3. `MutationCache.remove` notified only when the mutation was still in the
   cache. Upstream notifies either way: a caller that asked for a removal is
   told it happened.

### `mutationObserver.test.tsx`

All 16 ported.

- **adapted (2):** the callback-argument cases drop the
  `MutationFunctionContext` argument (see the divergence table) and use
  `MutationObserver<…, Object?>` so the `onMutateResult` slot is a value rather
  than `void`.
- **adapted (2):** the two "transferred to a different execution context"
  cases collect what the zone reports, through `testFakeAsyncGuarded`.
- **adapted:** `should not notify cache when setOptions is called with same
  options` reads the events the cache emitted instead of spying on `notify`.

**Four port bugs this suite caught:**

1. `MutationObserver.setOptions` pushed the new options onto the observed
   mutation whatever its state, so changing `meta` rewrote the record of a
   mutation that had already finished. Only a *pending* mutation takes new
   options.
2. Changing the `mutationKey` did not reset the observer. A different key means
   a different mutation, and there is no way back to the old one.
3. Re-subscribing never re-attached the observer to its mutation, so an
   observer that lost its last listener stopped seeing the mutation it had
   started — including the result it settled with while nobody was watching.
4. A per-call `onSuccess`/`onError`/`onSettled` that threw took the caller's
   future down with it. Those failures now go to the zone, like the mutation's
   own callbacks.

The observer also needed `observerOptionsUpdated` and value equality on
`DefaultedMutationOptions` — the analogue of upstream's `shallowEqualObjects`,
without which every rebuild would report an options change.

### `utils.test.tsx`

47 ported, 31 omitted (the 8 `addToEnd`/`addToStart` cases were deferred until
[#16](https://github.com/KoTTi97/flutter_query/issues/16), the 23
`replaceEqualDeep` cases until the third review; both are ported now).
This is the one upstream file that is mostly *not* applicable: it tests
JavaScript helpers, and the ones that survive the port are already methods on a
value type here.

- **ported:** `partialMatchKey` (8) as `QueryKey.matches`, `hashKey` (4) as
  `QueryKey.debugString`, `matchMutation` (1), and the three
  `addConsumeAwareSignal` cases as the query function context's `signal` getter
  plus `QueryCancelToken.onCancel`.
- **omitted — no counterpart (26):** `isPlainObject` (7), `isPlainArray` (2),
  `shallowEqualObjects` (4), `isValidTimeout` (6), `hashQueryKeyByOptions` (2),
  `keepPreviousData` (1), `ensureQueryFn` (3), `shouldThrowError` (2). Dart has
  no plain-object introspection, `Duration` cannot be `NaN` or a string, and
  the rest belong to features this port dropped (`queryKeyHashFn`, `skipToken`,
  `throwOnError`) or expresses differently (`keepPreviousData` is
  `PlaceholderData.compute((previous, _) => previous)`, shallow equality is
  `==` on the defaulted options).
- **ported since the third review — replaceEqualDeep (23 of 24):** the
  block, against `replaceEqualDeep` in `structural_sharing.dart`. JS objects
  become maps, `undefined` becomes `null`, and the "not arrays or objects"
  stand-in is a class without `==`. **Adapted (4):** `should replace different
  values in objects`, `... in arrays` (at index 2), and the two `should replace
  all parent ...` cases — a map is shared whole here, not entry by entry, so a
  changed map is `next` itself rather than a copy with equal entries shared;
  the assertions say so. The depth-limit case nests lists instead of objects,
  so the walk is what it exercises. **Omitted (1):** `should support objects
  which are not plain arrays` — an array with extra properties is JavaScript.
- **omitted — undefined guards (1):** `hashKey > should hash undefined object
  properties the same as missing properties`. Dropping `null` entries from the
  debug rendering would misrepresent a key: `null` is a value here, and two
  keys that differ by one would print the same.
- **adapted:** `partialMatchKey > should treat undefined object properties as
  matching missing properties` becomes `should not treat a null object property
  as a missing property`, and asserts the asymmetry. Upstream reads both
  directions as `undefined === undefined`; here a filter that names
  `filters: null` is asking for an entry the other key does not have — which is
  also what `==` says about the two keys, so partial matching agrees with exact
  matching rather than contradicting it.

### `infiniteQueryBehavior.test.tsx` and `infiniteQueryObserver.test.tsx`

7 of 9 and 6 of 7.

- **omitted — type-level (2):** `should throw an error if the queryFn is not
  defined` (an `InfiniteQueryOptions` cannot be built without a `pageFn`) and
  `should stop refetching if undefined is returned from getNextPageParam`,
  which is the `null` case again in a language that has both.
- **omitted — option not ported (1):** `should use persister when provided`.
- **adapted:** `should surface the abort reason when cancellation happens
  between refetched pages` drives a real observer instead of hand-building a
  `FetchContext`, and asserts the same thing: the page loop stops rather than
  fetching the next page.
- **adapted:** the page function's arguments are asserted directly rather than
  through a spy's recorded call objects, and `queryFn` reads as `pageFn`
  throughout — it returns one page, not the whole `InfiniteData`.
- **adapted:** `should make getNextPageParam and getPreviousPageParam receive
  current pageParams` records a shorter sequence. Upstream recomputes
  `hasNextPage`/`hasPreviousPage` while building *every* result, so its expected
  sequence counts those calls; here they are lazy getters on the observer, so
  the sequence is what the paging itself asked for plus the explicit reads the
  test makes.
- **adapted:** `getOptimisticResult` becomes `getOptimisticInfiniteResult`, and
  the paging fields it asserts on (`hasNextPage` and friends) are read from the
  observer rather than from the result.

**One port bug this suite caught:** `QueryCancelToken.onCancel` ran its
callbacks a microtask after `cancel()`, which was long enough for an in-flight
page loop to start one more page. They now run synchronously inside `cancel`,
the way a browser's `AbortController` dispatches its abort event.

The nine infinite cases deferred from `queryClient.test.tsx` and the eight
`addToEnd`/`addToStart` cases deferred from `utils.test.tsx` are ported with
them; both files' status lines are now plain "done". `addToEnd`/`addToStart`
drop exactly *one* item when `max` would be exceeded, not "down to max" —
upstream's `slice(1)` arithmetic, which is right because pages arrive one at a
time.

## Regressions found by review

`port_specifics_test.dart` pins five bugs an external review of `c69a3ca` found.
None was caught by a ported upstream case, and it is worth recording why:

1. **A nullable query could not resolve to `null`.** `QueryState.copyWith` read
   `data ?? this.data`, so a successful fetch returning `null` kept the previous
   value. Upstream cannot hit this — `undefined` there means "no data" and a
   `null` result is a distinct value — so no ported case covers it. `data` and
   `hasData` now travel as one unit.
2. **`StaleTime.infinite` ignored invalidations.** Both `infinite` and `static`
   resolved to a `null` duration, and `isStaleByTime` returned early on `null`
   before looking at `isInvalidated`. This is a divergence the port introduced
   when it split upstream's `number | 'static'` into three sealed values, and it
   made an invalidated query look fresh forever. `isStaleByTime` now takes the
   `StaleTime` and resolves it once, keeping the three apart.
3. **An infinite-query retry restarted from the first page.** `result` and
   `currentPage` were declared inside `fetchFn`, so every retry attempt began
   again: `[0, 1, 0, 1, 2]` instead of `[0, 1, 1, 2]`. Upstream declares both in
   `onFetch`, outside the retried function. Ported faithfully now.
4. **Infinite queries always marked the fetch cancellable.** The behaviour read
   `context.signal` eagerly to build the page context, which is exactly the
   thing that marks a fetch as cancellable — so a page that never asked for the
   token still lost its result when the last observer went away. The token is
   now read on first access by `pageFn`, which is what upstream's
   `addConsumeAwareSignal` getter does.
5. **A cancelled retry could still pause its query.** After the retry delay the
   retryer paused without checking whether it had been resolved meanwhile, so a
   `cancelQueries` followed by going offline flipped an idle query to `paused`.
   Upstream has the same hole; this one is a deliberate divergence rather than a
   port bug, and it is in the table above.

The pattern is worth naming: four of the five sit exactly where this port
*differs* from upstream — nullable data, the three-way stale time, a page loop
written as Dart closures, a lazily-consumed cancellation token. Ported tests
prove the ported behaviour; they cannot prove the seams the port itself
introduced. Those need tests of their own.

### Second review (2026-09-09, of `35fe71b`)

A deeper review reported 17 findings — eight in the core, eight in the binding,
one on the demo's build setup — plus three upstream-inherited behaviours and
two null conventions to decide. Every finding was reproduced against the
checkout before anything was changed; the review's own reproduction cases
were re-run and all reproduced, with two exceptions noted below. The core's
regressions are the second block of `port_specifics_test.dart`; the binding's
are `query_kit_flutter/test/review_regressions_test.dart`.

Core, fixed:

6. **An `async onMutate` that could return `null` failed with a `TypeError`.**
   The runtime check was `is Future<TOnMutateResult>`; a callback declared as
   `FutureOr<TOnMutateResult?>` produces `Future<TOnMutateResult?>`, which is
   not a subtype of that, fell through to the synchronous branch, and was cast
   as a value. JavaScript has no such distinction, so no ported case could see
   it. The check is `is Future<TOnMutateResult?>` now.
7. **A listener starting the next mutation stole the previous call's
   callbacks.** `_updateResult` notified listeners *before* the per-call
   callbacks read `_callCallbacks`, which a reentrant `mutate` had already
   replaced: `['second:1', 'second:2']` instead of `['first:1', 'second:2']`.
   Upstream runs the per-call callbacks first, inside the same batch. Ported
   faithfully now.
8. **Explicit mutation scopes collided with unscoped mutations.** `_scopeOf`
   fell back to the numeric `mutationId`, in the same namespace as user-chosen
   scope ids; `MutationScope(1)` queued behind whichever unscoped mutation was
   created first. Upstream never serialises unscoped mutations. Neither does
   this port now.
9. **A retry called the mutation function the mutation started with.**
   `execute` captured `mutationFn` once; `setOptions` on a running mutation
   updated the options but not the closure the retryer held. Upstream reads
   `this.options.mutationFn` per attempt. So does the port now — and, with it,
10. **a missing `mutationFn` now fails inside the attempt**, reaching the error
    state and the `onError`/`onSettled` callbacks like any other failure, rather
    than throwing before the `pending` transition and leaving the observer
    idle. `MissingMutationFunctionError` is still what the future rejects with.
11. **Exponential backoff overflowed.** `base * (1 << failureCount)` wraps a
    64-bit int at 44 and a JavaScript int at 32, and the wrapped product was
    clamped to *zero* — a `RetryPolicy.always` that had failed for long enough
    retried in a tight loop. The delay is now doubled up to the cap without ever
    computing the power; the regression covers attempts up to `1 << 40`.
12. **Nested sets broke the `==`/`hashCode` contract.** Set equality was
    "every element has *a* match", which called `{[1], [1], [2]}` and
    `{[1], [2], [2]}` equal while `hashAllUnordered` told them apart. Sets in
    keys are a port extension (JSON has none); they compare as multisets now.
13. **`networkMode: always` refetched on reconnect.** Upstream's one dependent
    default — `refetchOnReconnect = networkMode !== 'always'` — was missing.
    `defaultQueryObserverOptions` derives it from the resolved network mode now.

Two of the review's binding reproductions did not reproduce what they claimed,
and are worth recording because the findings behind them were still real: the
"listener removes itself on first notification" case never received a
notification at all (an observer whose first result equals its optimistic one
does not notify on subscribe), and the "provider mounted while hidden" case
never mounted anything, because Flutter produces no frames while the app is
hidden. Both regressions were rewritten to exercise the actual path.

Upstream-inherited behaviour, changed here on purpose (in the table below):
a removed failing `select` no longer keeps reporting its error; a changed
`select` is applied to a retained placeholder; an observer that resubscribes
after its query was collected re-resolves the key. And the null convention is
decided: `InitialData.value(null)` and `PlaceholderData.value(null)` are values
— the wrapper is the presence — while `.compute` returning `null` keeps
upstream's "return `undefined` to skip" meaning, because that is the one place
where Dart's single null has to carry both.

What the binding half of the review found is recorded with its regressions;
the short version is that notifications now actually go through the scheduler
the provider installs, observers belong to reading widgets rather than to keys,
every call style follows a replaced provider client, an inline mutation keeps
its state across its own rebuild, and disposing a controller detaches its
observer whether or not anyone ever listened.

### Third review (2026-09-09, of `c96921f`)

A release-readiness review: three behavioural blockers, eight majors, some
thirty minors, an API pass and the pub.dev mechanics. Every blocker and major
was reproduced against the checkout before anything changed — one of the
review's own binding reproductions (the inline `select` rebuild loop) needed a
parent rebuild as the first kick, which the review's numbers had implied but
its description had not said. The core's regressions are the third block of
`port_specifics_test.dart` (`thirdReview()`); the binding's are the third
section of `query_kit_flutter/test/review_regressions_test.dart`.

Core, fixed:

14. **An `Enabled.when` (or `StaleTime.dynamic`) built per rebuild restarted
    the timers.** `setOptions` compared the option *wrappers*, and a closure
    built in `build` is a new wrapper every time, so the refetch interval was
    cancelled and re-armed on every rebuild — a widget rebuilding faster than
    its interval never polled (1 fetch in a second instead of 11). Upstream
    compares the *resolved* values; so does the port now.
15. **A throwing `RetryPolicy.when` or `RetryDelay.dynamic` (then `.custom`) hung the fetch
    forever.** The throw escaped the retryer's catch block into an `.ignore()`d
    future, and the completer was never settled: `pending`/`fetching` after a
    minute, no error anywhere. Upstream has the same hole (an unhandled
    rejection there). Here the throw becomes the fetch's error — a fetch that
    can never settle is worse than one that fails.
16. **A retry backoff outlived `cancel()` and `clear()`.** The delay was a bare
    `Future.delayed`; the post-delay `isResolved` check kept it *correct*, but
    the timer stood for up to 30 seconds, which is exactly what a widget test
    asserts against. Worse for mutations: nothing cancelled a removed
    mutation's retryer, so `RetryPolicy.always` kept hitting the server after
    `clear()` — 41 attempts in 40 seconds in the reproduction. The delay is a
    timer the retryer owns and drops when it resolves; `Mutation.destroy` cuts
    the retries short. The retryer's recursion became a loop on the way.
17. **A `select` returning a fresh but equal list notified on every
    `setOptions` — and, through the binding, rebuilt on every frame.**
    Upstream runs `replaceData` over the selector's output and placeholder
    data; the port applied its hook only in `Query.setData`, and a Dart
    `List` is equal only to itself. `replaceEqualDeep` is ported now
    (`structural_sharing.dart`) and is the default everywhere upstream applies
    it: the cache write, the selector's output, placeholder data. Lists are
    shared element by element; a map or set is shared whole when deep-equal,
    because a generic function cannot build a map of the caller's runtime
    type; everything else by `==`. The 23 upstream cases are ported.
18. **`errorUpdatedAt` was cleared when a refetch started or succeeded.**
    `copyWith(clearError: true)` took the timestamp with the error; upstream's
    `fetchState`/`successState` null only `error`. Kept now.
19. **`updateQueriesData` wrote half the prefix before throwing** on a type
    mismatch. Checked before anything is written.
20. **`InitialData.value`/`PlaceholderData.value` had identity equality**,
    unlike every other option value, so one built inline made every
    `setOptions` a change. Value equality now.
21. **A map keyed by a collection passed the key assertion** but could never
    match, because map entries are compared through a hash lookup. Map keys
    must be value-equal scalars; the assertion says so.
22. **`find` matched by prefix.** Upstream's `find` defaults `exact: true`
    (`queryCache.ts:302`, `mutationCache.ts:286`); the ported test had lost its
    `exact: false` argument. `QueryFilters.exact` is nullable now — prefix for
    the bulk operations, exact for `find` — and the test has its argument back.
23. **`canRunMutation` stopped at the mutation's own position** rather than at
    the first pending mutation in the scope, so a mutation built earlier could
    start while one built later was running. Upstream's rule now.
24. **A plain `setOptions` on an `InfiniteQueryObserver` stripped the paging
    behaviour** from the shared query; its next refetch failed with
    `MissingQueryFunctionError`. Refused with `UnsupportedError`. And
    `InfiniteQueryBehavior` had identity equality, so defaulted infinite
    options were never equal; it compares the six fields it reads.
25. **`pages` on `InfiniteQueryObserverOptions` trimmed pages the user had
    paged to** on the next refetch. It is `QueryClient.infiniteQuery`'s "fetch
    this many up front" and is gone from the observer options, as upstream.
26. **A mutation's error state kept the previous success's data**
    (`data ?? this.data`, the same latent pattern the first review fixed on
    the query side, masked by the `pending` action). Upstream's `data:
    undefined`; `hasData`/`data` travel together now, as on `QueryState`.
27. **`Mutation.reset()` was public, port-only, and corrupted a running
    mutation.** Removed; `MutationObserver.reset` is the API.

Decided divergences (in the table): a throwing observer listener is reported
to the zone rather than recorded as the query's error, the way mutation
callbacks already are; a throwing cancel-token callback likewise, without
skipping the rest; `Query.reset()` re-arms collection for an unobserved query
(upstream leaves it in the cache for good); a removed mutation stops retrying;
the corrected `isRefetching`/`isRefetchError` for infinite queries live on the
observer, next to the other paging flags, because the sealed result has one
shape; and the `NotifyManager` is per client by default, like the other
managers — the binding installs its scheduler on the client's manager, and two
clients sharing one handed it back and forth.

Not changed, recorded here: `QueryCache.notify`/`clear` are not wrapped in a
notify batch, because the cache has no manager to batch on (it is built before
the client; the manager is the client's); `MutationDefaults` carries no
callbacks (they are typed per mutation, and the defaults are not); the
`MutationObserver.subscribe` notifies the new listener synchronously.

Binding, in short: the app's first build — which `runApp` runs outside any
frame — is now recognised as a build (`BuildOwner.debugBuilding`) and its
notifications go into a microtask, so a sibling's `initialData` no longer
trips the "setState during build" assertion at startup; the mixin releases a
key it stopped reading after the frame, like `context.query` (its retained
observer used to refetch with a `queryFn` that had closed over the *new*
widget, writing "Task b" into a's cache entry); every lifecycle transition
maps onto focus (`detached → resumed` fired neither `onShow` nor `onHide`); a
new `onlineStatus` stream rebinds the subscription without unmounting the
client; two reads of one key in one build with options that yield different
results, or two mutations of one shape without `id`, are caught by an
assertion instead of flipping the observer forever; `buildWhen` is on every
builder; a missing provider throws a `FlutterError` in every build mode; and
the barrel exports are trimmed to upstream's `index.ts` surface, with tests of
the internals importing them directly.

### Fourth review (2026-09-09, of `65a1da6`)

A fourth external review of the core: six majors, seven minors, three nits.
Every finding was reproduced against the checkout before anything changed,
and all fourteen behavioural ones reproduced as described — the web timer for
real: a `Timer(Duration(days: 30), …)` compiled with `dart compile js` and run
under node fires after 4 ms, with a `TimeoutOverflowWarning`, ahead of a
200 ms control timer. One claim in the review did not hold: upstream at this
pin has *no* 2^31 clamp (see 29). The regressions are the fourth block of
`port_specifics_test.dart` (`fourthReview()`), one per finding, named by the
review's number.

Core, fixed:

28. **Subtype-related data types on one key crashed with a raw `TypeError`.**
    `QueryCache.get<T>` asked `query is Query<T>`, and Dart generics are
    covariant: a `Query<int>` passed as a `Query<int?>` or a `Query<num>`, and
    the observer's first `setOptions(DefaultedQueryOptions<int?>)` then failed
    inside the query with a `_TypeError` nobody could catch by name. Upstream
    casts blindly and cannot tell. The cache now compares the query's
    `dataType` (the reified `TQueryData`) exactly, throws `QueryDataTypeError`
    for a subtype too, and `updateQueriesData` makes the same exact check
    before writing anything. The rule is *one key, one exact type* (in the
    table).
29. **Timers over 24.8 days fired at once on the web.** `Removable`'s gc
    timer, the observer's stale timer and refetch interval, and the retryer's
    backoff handed the `Duration` straight to `Timer`; dart2js and dart2wasm
    pass the milliseconds to `setTimeout`, which treats anything above
    2^31 − 1 as an overflow and fires after 1 ms. So
    `GcTime.duration(Duration(days: 30))` collected a millisecond after the
    last observer left, and `RefetchInterval.every(Duration(days: 30))` polled
    every millisecond. The dartdoc in `removable.dart` said upstream's clamp
    was not ported because Dart's timer is 64-bit — true on the VM, false on
    the web — and upstream at this pin has no clamp either (`isValidTimeout`
    only rejects `Infinity`; the review's "upstream does the same" was
    mistaken, so this is the port's own). `timers.dart` is the one helper
    (`clampTimerDuration`, to `maxTimerDuration`), applied at the four sites: a
    clamp rather than "never", because a 30-day gc that runs on day 24.8 is
    harmless while one that never runs would change what the option means.
    Not a divergence — a runtime fact the VM hides. The helper has a unit
    test and the three sites are driven past the clamp under virtual time;
    the real reproduction needs `dart compile js`.
30. **A throwing cache listener left the fetch pending forever.** The retryer
    called `onFail`/`onPause`/`onContinue` outside every `try`; `Query` and
    `Mutation` wire all three to `_dispatch`, whose cache listeners ran
    unisolated. A devtools or logging subscriber throwing on a `failed` action
    blew up `_attempt`, whose `.ignore()`d future swallowed it, and the
    completer was never settled: `pending`/`fetching` after a minute, nothing
    reported anywhere. The third review had isolated *observer* listeners;
    cache listeners, and the mutation observer's own listeners, were still on
    the same path. Both caches now isolate every listener (reported to the
    zone, the rest still run), so does `MutationObserver`, and the retryer
    guards its three hooks: a throw there is the fetch's error, the policy #15
    set for a throwing retry callback — the last line of defence once the
    listeners are isolated.
31. **A standing `select` error was a new result on every build.**
    `createResult` stamped `errorUpdatedAt = clock.now()` on every pass while
    the selector's error stood; `errorUpdatedAt` is part of the result's
    identity, so two results a millisecond apart were never equal and every
    `setOptions` notified — through the binding, a rebuild loop. Upstream
    reads `Date.now()` there too, but its render tracking hides the churn,
    and this port has no such filter (#15). The timestamp is captured once,
    when the selector throws, and reused until the error clears.
32. **Infinite queries never shared their pages.** `replaceEqualDeep` walked
    lists, maps and sets and fell back to `==` for everything else;
    `InfiniteData` was "else", and its `==` compares pages by `==` — a page is
    usually a `List`, equal only to itself — so every refetch that brought
    back the same pages was a new `InfiniteData` for every consumer.
    Upstream runs `{ pages, pageParams }` through `replaceEqualDeep` as a
    plain object. `InfiniteData` is walked the same way now: each list shared
    on its own, the whole `previous` when both come back unchanged, else
    `next` carrying the shared lists. (An import cycle, `structural_sharing →
    infinite_query → query → structural_sharing`, which Dart allows; a public
    sharing interface would avoid it, and nobody has asked for one.)
33. **An `InfiniteQueryOptions` could not be fetched as the `QueryOptions` it
    is.** It extends `QueryOptions<InfiniteData>`, so `client.query(options)`
    typechecked, but the paging behaviour was attached only by
    `infiniteQuery`/`infiniteObserverOptions`, and the fetch failed with
    `MissingQueryFunctionError` — pointing at the wrong fix. `behavior` is a
    getter on `InfiniteQueryOptions` now, deriving the `InfiniteQueryBehavior`
    from the options themselves (value-equal, so a fresh instance per read is
    harmless); `infiniteQuery` is `query` with the type spelled out, and
    `infiniteObserverOptions` no longer builds the behaviour by hand.
34. **`hasNextPage` went stale after a direct `setOptions`.** The infinite
    observer kept its paging options beside the defaulted ones; a `setOptions`
    with behaviour-carrying options updated the fetch but not the copy, so
    `hasNextPage` asked the old `getNextPageParam` while `fetchNextPage` used
    the new one. The paging half is read off `options.behavior` now, and with
    that the precondition is honest: `setOptions`/`getOptimisticResult` accept
    *any* options carrying an `InfiniteQueryBehavior` — what
    `setInfiniteOptions`, `infiniteObserverOptions` and an
    `InfiniteQueryOptions`'s own `behavior` produce — and refuse only options
    without one. The third review's "plain setOptions is refused" case still
    holds as written (plain options have no behaviour); #24's typed-options-
    only wording is superseded. `infiniteOptions` is the
    `InfiniteQueryOptions` the behaviour holds, no longer the observer options
    the observer was built with.
35. **Subscribing to a fetch already running left `currentResult` idle.**
    `onSubscribe`'s fetch branch relied on the `fetch` dispatch to recompute
    the result, and a fetch that joins one already running dispatches nothing
    — so an observer built while the query was idle and subscribed
    mid-refetch reported `idle` while the query was `fetching`. Upstream's
    `onSubscribe` has the same gap and its React adapter re-reads; the
    Flutter controller reads `currentResult` right after subscribing. The
    result is refreshed on subscribe when the query's state moved on since it
    was last computed — and only then, because recomputing it unconditionally
    ran a placeholder callback once more than upstream, which
    `queryObserver.test.tsx` counts.
36. **`cancelRetry(immediately: true)` paused offline instead of rejecting.**
    A port-only path (the third review's). It woke the backoff, but
    `_attempt` then reached `if (!canContinue) await pause()` before checking
    the cancellation, so a removed mutation that went offline during its
    backoff parked until the network came back. The immediate flag is checked
    right after the delay, before the pause; a plain `cancelRetry()` keeps
    upstream's order (wait out the delay, pause if offline, then reject).
37. **`replaceEqualDeep` threw when a shared element did not fit the incoming
    list.** The copy is `next.toList()`, which keeps `next`'s element type,
    and the recursion runs as `Object?`, so the `is T` guard does not apply
    one level down: `replaceEqualDeep<List<num>>(<int>[1], <double>[1.0])`
    found `1 == 1.0` and stored an `int` into a `List<double>` — through
    `Query.setData`, the query's error state. Sharing is best effort now: a
    part that does not fit stays `next`'s and does not count as equal.
38. **`QueryCache.find` iterated the live map.** A predicate that removed the
    query it was shown threw `ConcurrentModificationError`; `findAll` already
    iterated a copy. So does `find`.
39. **`clear()` of a network-paused mutation hung `mutateAsync` forever.**
    `Mutation.destroy` cut a backoff *delay* short (third review) but not a
    *pause*: a mutation waiting for connectivity, focus or its scope kept its
    pause completer after leaving the cache, and `resumePausedMutations` only
    sees cached mutations. Ten minutes offline, ten minutes online: still
    pending. An immediate cancel rejects a paused fetch on the spot with
    `CancelledError` now — nothing is in flight to wait for — so the mutation
    fails, its callbacks run, and no timer is left. The table's row is
    corrected: the last error from a backoff, a `CancelledError` from a pause.
40. **A cancel-refetch did not reset `fetchFailureCount`.** `Query.fetch`
    dispatched the `fetch` action only when `fetchStatus` was idle or
    `fetchMeta != meta`. Upstream's `!==` never holds there — a `null`
    `fetchMeta` is not an unset `undefined`, and a page fetch builds a fresh
    meta object per call — so upstream dispatches on every fetch that gets
    past the piggyback check, which is what zeroes the failure count when a
    `refetch()` cancels a retrying fetch. Dart's value-equal `FetchMore`s and
    two `null`s compared equal here and skipped it: `failureCount: 1` where
    upstream reports 0. The action is dispatched unconditionally, which is
    what upstream's condition amounts to.
41. **A default `queryFn`/`mutationFn` made defaulted options never equal.**
    `_adoptQueryFn`, `_adoptMutationFn` and `_adoptStructuralSharing` wrapped
    the erased default in a new closure per call, and defaulted options
    compare functions by identity — so with `setQueryDefaults(key,
    QueryDefaults(queryFn: …))` every `setOptions` was an options change and
    every rebuild an `observerOptionsUpdated`. The wrappers are memoised per
    (erased function, data type) in an `Expando` on the function itself, so
    the memo lives exactly as long as the default does. They close over
    nothing else: the query wrapper names the key from the context it is
    handed, and the sharing and mutation wrappers have no key to name, so
    `QueryDataTypeError.queryKey` is nullable now and the message says which
    case it is.
42. **A settled mutation with a live observer armed a gc timer.** `execute`'s
    `finally` scheduled collection unconditionally — upstream never schedules
    from `execute`; this port does because its `optionalRemove` leaves a
    pending mutation alone rather than re-arming (the `mutationCache` section
    above). With an observer attached the timer only fired into
    `optionalRemove`, which returned; but a timer pending while a mutation
    widget is mounted is exactly what Flutter's widget tests assert against.
    It is armed only when no observer is attached; an observer leaving arms
    it in `removeObserver`, as before.

The three nits: `QueryClient.mount`'s listeners were `async` closures whose
futures nobody held, so a throw would have surfaced as the unhandled
rejection of an anonymous future; they report to the zone explicitly now,
through one `_resumeThen`, and nothing `.ignore()`s the error into silence.
`resetQueries` matched its refetch predicate against a `List` (O(n²)); an
identity `Set` now. `defaultQueryObserverOptions` resolved the merged
defaults twice per build — `defaultQueryOptions` plus its own scan, each over
every registered default with deep key matching; resolved once and shared.

#### API decisions (fourth review)

The review's API findings were decided together, after the behavioural fixes
above; the decisions are numbered A1–A27, and this is the record of each.
Their tests are the `A<n> …` cases at the end of `fourthReview()` in
`port_specifics_test.dart` and of the fourth-review section of the binding's
`review_regressions_test.dart`.

- **A1 — done.** `queryKey` is `required` and non-nullable on `QueryOptions`,
  `QueryObserverOptions` and the infinite pair; the runtime `ArgumentError`
  in `QueryClient` and the `!`s in the binding are gone. `copyWith`'s
  parameter stays optional.
- **A2 — decided against.** `MutationResult` does not gain a
  `TOnMutateResult` type parameter: the `onMutate` result's job is the
  rollback, which `onError`/`onSettled` receive, and a third type parameter
  on a sealed result would tax every `switch` for a value widgets almost
  never read. A divergence row below.
- **A3 — done.** `InfiniteQueryController.setOptions` forwards any options
  that carry the paging behaviour to the observer, which accepts them since
  finding 41; plain options are still refused with `UnsupportedError`.
- **A4 — done.** `InfiniteQueryOptions.copyWith` and
  `InfiniteQueryObserverOptions.copyWith` return their own type and keep the
  paging half, with the paging fields as optional parameters; `queryFn` and
  `behavior` are rejected (an infinite query's function is `pageFn`), and so
  is `pages` on the observer options, whose field doc says why it is read
  only through `QueryClient.infiniteQuery`.
- **A5 — done.** `QueryFunctionContext.pageParam` and `.direction` removed;
  nothing set them. One ported assertion adapted (`query.test.tsx`, above).
- **A6 — done.** `Mutation.continueMutation()` rejects with the error the
  mutation settled on, as upstream's `continue()` does; the swallow lives in
  `MutationCache.resumePaused` (`.catch(noop)` upstream), and the one other
  caller `.ignore()`s.
- **A7 — done.** The class docs of `QueryOptions`, `QueryObserverOptions` and
  `MutationOptions` say there is no value equality on purpose: inline options
  are re-applied every build and the observer compares resolved values.
- **A8 — done.** The core README states the rule — one key, one exact type,
  related types included — and `website/docs/reference/coming-from-react-query.md` has a row.
- **A10 — done.** `QueryCache.build(state: …)` refuses a `success` state that
  carries no data, naming the persistence door in the message — an `assert`
  until the ninth review (C8) made it an `ArgumentError` in every build mode.
- **A11 — done.** An infinite refetch whose first held page param is `null`
  starts from `initialPageParam`, as upstream's
  `oldPageParams[0] ?? options.initialPageParam`; `initialPageParam`'s doc
  says a nullable `TPageParam` cannot tell "none" from `null`.
- **A12 — done.** The barrel exports what the public cache events name: the
  `QueryAction` and `MutationAction` families and the `QueryObserverRef` /
  `MutationObserverRef` interfaces, documented as read-only from outside.
  `*CacheRef`, `FetchContext` and `FetchBehavior` stay hidden — no event
  names them.
- **A13 — done, one kept.** `FetchOptions.initialFuture`,
  `FetchContext.signalConsumed` and `QueryFunctionContext.signalConsumed`
  removed (unused; the query tracks consumption through `onSignalRead`).
  `Retryer.initialFuture` stays: the ported `retryer.test.tsx` case `should
  reuse the initialPromise on the first run …` exercises it, and `Retryer`
  is not exported.
- **A14 — done.** Observer listeners are private (`hasListeners` is the
  read); `Query.observers` and `Mutation.observers` are unmodifiable views,
  with `addObserver`/`removeObserver` the only way in; `Removable.gcTime` is
  a getter and only the `@protected` `updateGcTime` moves it (no setter was
  needed); `Query.destroy` and `Mutation.destroy` are `@internal`.
- **A15 — done.** `InitialDataCompute` and `PlaceholderDataCompute` compare
  by their function: equal tear-offs are equal, two inline closures are not.
- **A16 — done.** `getQueriesData` throws `QueryDataTypeError` on a
  mismatch like `getQueryData`; no ported `queryClient.test.tsx` case relied
  on the silent `null`.
- **A17 — done.** `DefaultedMutationOptions` and
  `DefaultedQueryObserverOptions` are `final`; `DefaultedQueryOptions` is
  `sealed` (the observer options extend it) with a private final subclass
  its constructor redirects to, so nothing outside the library can extend
  or implement any of the three.
- **A18 — done.** `QueryError.==` includes `hasStaleData`; `QueryDefaults`,
  `MutationDefaults` and `DefaultOptions` have `==`/`hashCode` (functions by
  identity); `StructuralSharing`'s doc says a nullable type cannot tell "no
  previous" from a previous `null`.
- **A19 — recorded.** The observer diffs against the last *notified* result;
  a divergence row below, worded after reading both implementations.
- **A20 — done.** A `MissingQueryFunctionError` is never retried, decided in
  `Query.fetch` where the retryer is built; a divergence row below.
- **A21 — done.** `MutationOptions.simple<TData, TVariables>(…)` returns a
  `MutationOptions<TData, TVariables, void>` with every parameter but
  `onMutate`, so a mutation without an optimistic step infers its types from
  `mutationFn`. Used by the binding's example and the demo's
  `createTaskMutation`; the binding README and the JS-to-Dart map mention
  it, and a binding test compiles it with no type arguments under
  strict inference.
- **A26 / A27 — done.** The binding README's "What rebuilds, and when" says
  `buildWhen`'s `previous` is the last *built* result (the opposite of
  `bloc`), and that Dart records already have value equality, which makes
  them the easy pick for a `select` output.

### Fifth review (2026-09-09, of `98443be`)

Two external reviews of the core arrived together, with an executable
reproduction suite of seventeen cases (their `R` numbers below). Sixteen of
the seventeen failed against `98443be` as claimed; the seventeenth (R07) was
the reviewers' own counter-check and passed. Every finding was reproduced —
by its `R` case or a throwaway — before anything changed. The work was split
by file: the fetch and mutation *lifecycle* half (43–52, regressions in
`port_lifecycle_test.dart`) and the observer, structural-sharing and timer
half (53–59, regressions in `fifthReviewObserver()` of
`port_specifics_test.dart`). Since this review the whole core suite also runs
compiled to JavaScript in CI (`dart test --platform chrome`), because two of
the findings — and the fourth review's timer clamp — are only visible there.

Core, fixed:

43. **`clear()` during an async `onMutate` of an offline mutation hung
    `mutateAsync` forever** (D7 / F03). Number 39 cut a *pause* short, but a
    retryer that exists and has not started yet has no pause to cut: the
    mutation's `destroy` called `cancelRetry(immediately: true)` while
    `onMutate` was still awaiting, and when `execute` then called
    `retryer.start()` offline, the loop entered `_pause()` on a mutation that
    was no longer in any cache — `resumePausedMutations` never sees it, and a
    virtual day online later it was still pending (R04). `Retryer.start()`
    now honours a prior immediate cancel: a loop that cannot start rejects
    with `CancelledError` on the spot, so the mutation fails, its
    `onError`/`onSettled` run, and `mutateAsync` settles. A loop that *can*
    start still runs its one attempt — an in-flight request is left to
    settle, as before. The same holds for an async cache-level `onMutate` and
    for a mutation removed while queued behind its scope (its scope stays
    busy, so it could never start). There is no "focus wait" at start:
    `canStart` is network and scope only, and the focus check after a failed
    attempt was already covered by 39.
44. **The `fetch` action was dispatched before the retryer was installed**
    (F04 / D19; upstream-identical). During the synchronous `QueryFetchAction`
    notification the state said `fetching` but `_retryer` was still the
    previous fetch's or `null`: a cache listener calling `client.query` for
    the same key from the first fetch event found nothing to join and started
    a second request (R13, two calls); an observer reacting to `isFetching`
    with `cancelQueries` found nothing to cancel and the function ran anyway
    (R09). `Retryer`'s constructor runs nothing (it only `ignore()`s its own
    future), so `Query.fetch` now builds the retryer, assigns it, dispatches,
    then `start()`s. `clear()` from a fetch listener now rejects the caller
    with `CancelledError` and runs nothing; unsubscribe and `refetch()` from
    the fetching notification make one request each. In the table.
45. **Deduplicated callers shared only the transport future** (F05;
    upstream-identical). A caller that joined a running fetch got
    `retryer.future`, while the first caller additionally ran `setData`,
    structural sharing and the cache hooks: with a throwing
    `structuralSharing` hook the first caller got the error, the second got
    `42` as a success, and the query ended in error (R05). `Query.fetch` now
    returns one operation future per fetch — a `Completer` settled after the
    cache write and the hooks, or after the error dispatch — and every
    joiner gets that; the retryer's future stays the transport, used only
    inside `_settle` and by `cancel`'s wait. Silent-cancel succession keeps
    working the same way (the cancelled fetch's completer is completed with
    the replacement's future; no self-chaining, since the replacement never
    waits on its predecessor). `Query.future` is now the operation future,
    which is also what upstream's `promise` is (its retryer resolves after
    `onSuccess`, i.e. after `setData`). The ported `query_test.dart` and
    `query_client_test.dart` cases did not resist, so no divergence-candidate
    to record; the one ordering change is the intended one and is in the
    table.
46. **A scope change on a running mutation stranded its queue** (F06).
    `setOptions` on a pending mutation replaced its options wholesale, scope
    included; `onMutationSettled` then woke the next mutation in the *new*
    scope, and the one waiting in the old scope stayed `pending`/paused for
    good (R08). The scope is now captured when `execute` starts
    (`Mutation.schedulingScope`) and used for both `canRunMutation` and the
    settle-time wake-up; changing `scope` while running moves nothing in
    either direction (tested to-unscoped and from-unscoped). Documented at
    `MutationOptions.scope`.
47. **`resumePausedMutations` was a global no-op while offline** (D5). The
    `onlineManager.isOnline()` gate was on the whole call, so a
    `networkMode: always` mutation paused in the background was not resumed
    by a refocus while offline (review A's R40: refocus → 1 attempt,
    `setOnline(true)` → 2). The gate is per mutation now, inside
    `MutationCache.resumePaused`. Upstream has the *global* gate in
    `QueryClient.resumePausedMutations` (its per-mutation `canContinue` is in
    the retryer, which only runs once resumed), so this is a divergence
    rather than a port bug; the table's row from 4 is corrected.
    *Corrected by the ninth review (C4, 2026-09-10):* the gate written here
    was `canFetch(networkMode, onlineManager)`, called "the same test the
    retryer applies" — but that is the retryer's *start* rule, and a paused
    mutation is continued, under `networkMode == always || isOnline()`. For
    `offlineFirst` the two differ, so an `offlineFirst` mutation paused
    mid-retry *was* awaited offline and `mount`'s listeners *did* hang on it.
    The gate is `Mutation.canResume` now: the continuation's network rule
    (`canContinue` in `retryer.dart`) when a retryer exists, the start rule
    for a restored mutation that has none.
48. **`QueryClient.query()` wrote `retry: never` into the shared query for
    good** (D6; upstream-identical). The imperative default went into the
    query's options through `setOptions` and stayed: an observer with
    `retry: times(3)`, then a `client.query`, then `invalidateQueries` —
    the refetch ran with a single attempt (R6b). The override now rides on
    `FetchOptions.retry`, which `Query.fetch` prefers over the options'
    when building the retryer, and the query's options keep the observer's
    `retry`. Note what did *not* change, because upstream does the same and
    it is the documented "last options win": the call's other resolved
    options (`retryDelay`, `staleTime`, `queryFn`, …) do land on the query;
    only `retry` was special, because only `retry` is something upstream's
    `fetchQuery` writes explicitly. `withRetry` stays, `@internal`, for the
    fourth review's regression. In the table.
49. **`invalidateQueries` re-evaluated a state-dependent filter after
    invalidating** (D8 / F07; upstream-identical). `QueryFilters(stale:
    false)` or a predicate over `query.state.isInvalidated` matched the
    fresh query, `invalidate()` marked it, `refetchQueries` re-ran the same
    filter, and the query — now stale — dropped out: 1 fetch instead of 2
    (R06). The match set is frozen before invalidating, exactly as
    `resetQueries` already did, and the refetch is by identity set plus the
    `type` (which `refetchType` may narrow); disabled and static queries are
    excluded by `refetchQueries` as before. In the table.
50. **`MutationCache.findAll` and `find` iterated the live list** (D9 /
    F11). A predicate that removed the mutation it was shown threw
    `ConcurrentModificationError` (R11). Both iterate the `mutations` copy,
    as `QueryCache`'s have since 38.
51. **`cancelQueries` did not batch** (D16). Every other bulk operation —
    and upstream's `cancelQueries` — runs inside `notifyManager.batch`; this
    one cancelled outside it, so two reverts were two scheduler rounds
    for a `batchCalls` listener. Wrapped like the others; one round now.
52. **`Query.fetch`'s `finally` armed a gc timer with observers attached**
    (N3). The mutation side was decided the other way in 42 — no timer while
    observed, because a timer pending while a widget is mounted is what
    Flutter's widget tests assert against. One rule for both now: the
    fetch's `finally` schedules collection only when `observers.isEmpty`;
    an observer leaving arms it in `removeObserver`, as before. The ported
    suites did not notice.

Smaller items from the same reviews, fixed without a numbered entry:

- **`MutationState` has `==`/`hashCode`** (N7), field by field like
  `QueryState`'s, so a persistence layer can compare both.
- **`QueryClient.observeInfinite`** (N2), the twin of `observe` as
  `infiniteQuery` is of `query`.
- **`_executeQueryOptions` scanned the defaults twice** (N4): `query()`
  resolves the merged defaults once and builds the options from them.
  `DefaultedQueryObserverOptions.queryOptions` is a `late final` built once
  per instance rather than a getter allocating on every `setOptions` and
  `executeFetch`; the constructor is no longer `const` (nothing used it as
  one).
- **`@internal` on the constructors of `QueryFunctionContext`,
  `InfinitePageContext` and `FetchContext`** (N6): the library builds them;
  a query function receives one. `QueryOptions.behavior` already was.
- **Twelve `this as Mutation<Object?, Object?, Object?>`** in
  `mutation.dart` are one private `_erased` getter (N8).
- **Docs** (D13, D14, D15, D17, D18, and review B's precision notes):
  `mount()` says that focus/reconnect wait for *all* paused mutations (scope
  queues included) and that a never-ending one blocks the query side;
  `clear()` says observers are not stopped and the binding's controllers
  destroy theirs first; the README's first-query section and
  `example/example.dart` now `mount()`/`unmount()` (the example still exits
  cleanly); `removeQueries` explains the stranded-observer case and points
  at `resetQueries`; `Query.cancel` says `silent` is only meaningful with a
  successor; `NotifyManager` no longer claims the shared instance is the
  default and states what `batch` actually defers (scheduled callbacks only
  — cache listeners and `onQueryUpdate` are synchronous per dispatch);
  `updateQueriesData` says the same instead of promising one listener round;
  `resumePausedMutations` and `continueMutation` say an async
  `onSuccess`/`onSettled` may still be running when the future completes.

53. **The stale timer could fire before its deadline and never re-arm, so
   `isStale` never flipped by timer.** `_updateStaleTimeout` armed a `Timer`
   for `staleTime − (now − dataUpdatedAt)`, and the callback recomputed the
   result only `if (!_currentResult.isStale)`. Two ways for the timer to run
   early: a `Timer` is armed in whole milliseconds — the VM takes
   `duration.inMilliseconds` (and adds one, on a clock that is itself floored
   to the millisecond, so its guarantee is "not before `trunc(d)`", not "not
   before `d`"), dart2js and dart2wasm hand `inMilliseconds` to `setTimeout`
   with no extra millisecond at all — while `dataUpdatedAt` is
   microsecond-precise on the VM; and the fourth review's 2^31 ms clamp cuts a
   30-day stale time to 24.8 days. Either way the callback found the data
   still fresh, did nothing, and nothing armed the timer again: after 31
   virtual days `isStaleByTime` said `true` and `result.isStale` said `false`
   (R03); a 900 µs stale time under a zone that truncates timer durations to
   milliseconds never went stale (R16). The old comment said Dart's timers do
   not fire early — true only of `fake_async`. Upstream adds a millisecond in
   `#updateStaleTimeout` for exactly this and has no clamp. Now the deadline
   (`dataUpdatedAt + staleTime`) is the truth: the duration is rounded *up*
   to whole milliseconds (`ceilToMilliseconds` in `timers.dart`, never less
   than one, so a re-arm can never be a zero timer that `fake_async` would
   loop on) and then clamped, and the callback asks `_isStale` — stale means
   `updateResult()`, still fresh means `_updateStaleTimeout()` again for what
   is left. The gc timer, the refetch interval and the retry backoff keep
   their truncated durations: running a fraction of a millisecond early is
   harmless there. Reproduced by R03 and R16 (both ported) — *not* by the
   review's real-time suggestion: `staleTime: 30 ms`, 85 ms of wall-clock
   wait, 20 runs, 0 misses on this machine, because the VM's extra millisecond
   and event-loop latency cover the truncation in practice; the SDK source
   (`timer_impl.dart` and dart2js's `async_patch.dart`) is what says the
   guarantee is not there.
54. **`TypedData` broke structural sharing, and an equal-but-wider list was
   returned as the caller's type.** The list branch copied with
   `next.toList()` and cast the copy to `T`; `Uint8List.toList()` is a plain
   `List<int>`, so a second `setQueryData<Uint8List>` threw synchronously and
   a second fetch of typed bytes — or a `select` returning them — became the
   query's (or the selector's) error (R01, and a throwaway with a
   `Float32List`). And `return previous as T` for the all-equal case was
   unguarded: `replaceEqualDeep<List<double>>(<num>[], <double>[])` threw
   (R14). A `TypedData` is a leaf now — compared with `==`, never walked —
   as a `Uint8Array` is for upstream, which walks only plain arrays and
   objects; a byte-by-byte walk of an image would cost more than the rebuild
   it saves. Every return of `previous` is guarded by `previous is T` (the
   list, `InfiniteData`, map and set branches, on top of the leaf's), and the
   list copy is handed back only if it is a `T`, else `next`. Sharing is best
   effort and never a type error. (In the table.)
55. **Set comparison in `replaceEqualDeep` was an existence check.** "Every
   element of `next` has *a* deep-equal partner in `previous`" called
   `{[1], [1], [2]}` and `{[1], [2], [2]}` equal, and the cache kept the old
   value — data loss (R02). The second review had fixed the same hole in
   `QueryKey` (entry 12); the sharing walk had its own copy of it. Both sides
   are multisets now: each partner is consumed once. Symmetry, different
   multiplicities and sets nested in maps and lists are pinned. Only a set of
   structurally equal members can reach this — a set of value-equal members
   has no duplicates to miscount.
56. **An observer with `TData != TQueryData` and no `select` corrupted the
   shared query.** The check was an `assert` inside `createResult`, which runs
   inside `Query._dispatch` during the *fetch*: the `AssertionError` became
   the query's error state (`status: error`, `hasData: true`), the mistyped
   observer stayed `QueryPending(fetching)`, and a correctly typed observer on
   the same key saw the query in error (R15). The constructor, `setOptions`
   and `getOptimisticResult` now refuse such options with an `ArgumentError`
   before touching anything — a runtime check, not an assert. It is a subtype
   test, not exact equality: on every platform `<TQueryData>[] is List<TData>`
   holds exactly when every `TQueryData` is a `TData`, so
   `QueryObserver<int, num>` without a `select` is accepted (it is sound) and
   `QueryObserver<int, String>` is not. R15 is ported with the new contract:
   the mistyped observer throws, the query reaches `success`, the good
   observer reports it. The isolation half is 59.
57. **The paging flags of `InfiniteQueryObserver` changed without a
   notification.** `hasNextPage`, `isFetchingNextPage` and the rest are
   getters on the observer, not fields of the result (#16), and
   `updateResult` notified only when the result changed: a
   `fetchPreviousPage()` cancelling a running `fetchNextPage()` flipped
   `isFetchingPreviousPage` with 0 notifications (R17), and a
   `setInfiniteOptions` whose new `getNextPageParam` said "no more" flipped
   `hasNextPage` with 0 notifications (R12) — through the binding's
   controller, which passes the getters through and notifies on result
   change, a stuck "load more" button. The #16 shape stays; the notification
   decision is now a `@protected shouldNotify(previous, next)` on
   `QueryObserver` (the base rule: first result, then any not value-equal to
   the last), which `InfiniteQueryObserver` overrides. Exact, but lazy about
   user code: the six flags that follow from the result and the fetch
   direction are snapshotted as a record at every notification and compared
   as values; `hasNextPage`/`hasPreviousPage` — each a call into the user's
   paging function — are re-asked only when the paging functions differ from
   the ones the last notification was answered with (old against new, over
   the same data). Equal results carry `==`-equal data, so with the same
   functions the answer cannot have changed, and the ported
   `infiniteQueryObserver` case that counts `getNextPageParam` calls still
   records its documented, shorter sequence. A `setInfiniteOptions` with the
   same paging outcome does not notify (pinned, so this cannot become the
   third review's rebuild loop).

Doc-only, behaviour stays upstream's:

58. **`StaleTime.static` polls with an explicit `refetchInterval`.** The
   review read the `StaleTimeStatic` dartdoc — "never refetched … on mount,
   focus, reconnect, interval, invalidation or `refetchQueries`" — and R10
   showed the interval polling. Upstream (`50680b98c`) polls too: only
   `refetchQueries` filters `static` out; an interval is a request, not a
   trigger. The behaviour is kept and the dartdoc (on `StaleTimeStatic` and
   on `StaleTime.static`) now says so. R10 documents the old, wrong contract
   and is not ported.

Test hygiene (F14): two `port_specifics_test.dart` cases failed under
`dart test --platform node` for platform reasons: the backoff test's
`1 << 40` is `0` under dart2js (now the literal `1000000000000`), and C-Q7
assumed an `int` cannot be stored in a `List<double>`, which is not so where
`1` and `1.0` are one value (now a nested `List<Object>` element stored into
a `List<List<int>>` copy, a mismatch on both platforms). The core suite is
green under `--platform node`; `--platform chrome` — see the report.

Nit N5, taken: `_mapsEqualDeep`/`_setsEqualDeep` compared through
`replaceEqualDeep`, which allocated a copy of every nested list just to
compare it. `_equalDeep` is its own walk now — same depth limit, same
`TypedData` and `InfiniteData` rules, same leaf `==` — with no copies. One
difference from the sharing walk, deliberately not mirrored: the list branch
of `replaceEqualDeep` does not count an element that "does not fit" the
incoming list's element type as equal (it cannot store it), whereas
`_equalDeep` compares `1` and `1.0` as the leaf rule always has. The `is T`
guard at the return is what keeps that from handing back the wrong type.

59. **A throwing per-observer computation became the shared fetch's error.**
    With 56 the type mismatch can no longer reach the dispatch, but the path
    was still open to any user code that `createResult` runs — a
    `StaleTime.dynamic`, an `Enabled.when`, a `PlaceholderData.compute` (the
    selector was already caught): a `StaleTime.dynamic` throwing from the
    fetch's own dispatch onward left the query `status: error, hasData: true`,
    the good observer on the same key a `QueryError`, the throwing one
    `QueryPending(fetching)` for good. Each `observer.onQueryUpdate()` in
    `Query._dispatch` is now isolated exactly like the cache listeners (30):
    the throw is reported to the zone, the observers after it and the cache
    listener still run, and the query keeps its state. Upstream propagates,
    but its observers cannot throw user code there. In the table.

Decisions taken on the way, with the alternatives:

- **D6:** the retry override goes to the retryer only, through a new
  `FetchOptions.retry`; the query's options are untouched. Alternatives
  considered: leaving upstream's write (rejected — it silently changes an
  observer's retry policy for the rest of the session) and restoring the
  previous `retry` after the fetch (rejected — racy with an observer's
  `setOptions` during the fetch). `retryDelay` and the other call-site
  options still land on the query, as upstream's do; documented in 48.
- **F05 outcome:** done as decided — one operation future per fetch,
  transport future kept apart internally. No ported case resisted, so no
  divergence-candidate to record; `Query.future` is now the operation
  future, which matches upstream's `promise` more closely than the
  transport did. `Query.cancel` still waits on the transport future, so
  `await cancelQueries()` completes exactly when it did before (a cancel
  with a silent successor would otherwise wait for the successor).
- **N1:** every filter parameter on `QueryClient`, `QueryCache` and
  `MutationCache` is a named `filters:` — optional with the empty default
  where it was optional (`isFetching`, `isMutating`, `findAll`,
  `removeQueries`, and the four that already were), `required` where it
  was required (`getQueriesData`, `find`). `find` was not in the review's
  list but has a filter parameter, and `find(filters)` positional next to
  `findAll(filters:)` named would be the inconsistency being fixed.
  `updateQueriesData` keeps the updater positional (its only positional
  argument) and takes `filters:` named. Call sites fixed: every core test
  file except `port_specifics_test.dart` (the other half's file — the exact
  rewrite it needs is in the report), the binding's `binding_test.dart`,
  the demo's `queries.dart` and `acceptance_test.dart`, and two rows of
  `website/docs/reference/coming-from-react-query.md`. Ported test names unchanged.
- **D7 scope:** `Retryer.start()` rejects only when it *cannot* start;
  a removed mutation that can start runs its one attempt. The narrower
  reading of the finding, and consistent with "an in-flight attempt still
  settles" from 39.
- **D5:** implemented per mutation although upstream's client-level gate
  is global too — the finding's reasoning (the retryer's `canContinue` is
  per mutation) holds, and the global gate made `mount`'s refocus path
  useless for `always` mutations. Recorded as a divergence, not a port bug.
- **N9 (record only):** the import cycle
  `structural_sharing → infinite_query → query → structural_sharing` is
  accepted; Dart allows it, and splitting `InfiniteData` out would move a
  public type for the sake of a graph nobody navigates. Not restructured.

### Eighth review (2026-09-10, of `56950db`)

A review of the core, arriving with the two of the binding. Each finding was
reproduced before anything changed; the regressions are `E1`–`E5` in
`port_specifics_test.dart`.

1. **`Query.setState` accepted a `success` state with no data.**
   `QueryCache.build` has always asserted that invariant — it is the same
   persistence door, and `setState` is the other half of it. What an
   inconsistent state does is not subtle: the next `QueryObserver` casts
   `null` to the data type and throws *in its constructor*, into whatever
   zone happens to be running, and the reader never recovers. Rejected now
   with an `ArgumentError` in every build mode; an `assert` would let a
   release build take the state and fail somewhere that says nothing about
   where it came from.

2. **`Subscribable` kept its listeners in a `Set`, and Dart tear-offs are
   equal.** See the divergence table below: two independent subscribers that
   both passed `watcher.onEvent` collapsed into one entry, and the first to
   unsubscribe silenced the second. `QueryCache`, `MutationCache`,
   `FocusManager` and `OnlineManager` all inherit it. Now a list, one entry
   per `subscribe`, each handle removing its own — and calling a handle twice
   removes nothing the second time.

3. **`cancelQueries(revert: false, silent: true)` wedged the query in
   `fetching` for good.** A silent cancel dispatches no error because the
   fetch that replaces it announces itself instead; with no replacement,
   nothing ever ends the status and the query never loads again. `Query.cancel`
   documented the hazard, but `cancelQueries` is public, takes the flag, and
   said nothing. Upstream has the same hole. `cancel` now puts the status back
   to `idle` itself when nothing replaced the fetch — told apart by whether
   `_retryer` is a *different* retryer, since `fetch()` installs a successor
   synchronously before the cancel's await resumes.

4. **`unmount()` before `mount()` disabled focus and reconnect refetching for
   the life of the client.** The count went to -1, and the next `mount()`
   took it to 0 — never to 1, so nothing was ever subscribed. Silent, and
   permanent. `unmount()` now ignores a call that would take the count below
   zero. The README's claim that `unmount()` was the reader's to call beside
   `clear()` was the likeliest way to reach it, and is corrected too.

5. **A missing `mutationFn` was retried with the full backoff.** The query
   side has answered at once since the fourth review — a missing function is
   a configuration error, and retrying only delays the message — while the
   mutation twin took the whole backoff to say the same thing (30 seconds at
   the default policy). Now decided by what the options hold when the attempt
   starts: `RetryPolicy.never` when there is no function. The check stays
   *inside* the attempt so the error still reaches the state and the
   callbacks like any other failure.

6. **Documentation that described something unreachable.**
   `hasNextPageOf`/`hasPreviousPageOf` were documented "for callers holding
   only options and data (a binding rendering from a cache snapshot, say)"
   and hidden from the barrel, so no such caller could have them; they are
   exported now. `QueryClient.infiniteObserverOptions` was `@internal` while
   being the only legal input to `InfiniteQueryObserver.setOptions` and
   `InfiniteQueryController.setOptions` — every public call to those threw —
   so it is public. Four `DefaultedMutationOptions` fields claimed "with the
   key's registered default applied" for callbacks `MutationDefaults` does
   not carry. And `Enabled.when` is asked seven times for a single
   subscribe-and-fetch, `StaleTime.dynamic` four; both now say that they must
   be cheap and free of side effects, and that the number is not one to rely
   on.

**Two more that are not changed.** The mutation's notification loop was read
as missing the isolation `Query._dispatch` has. It is not missing anything a
test can show: a throwing listener there is already isolated below the loop,
the cache event still fires and the observer's own state is still correct
(`E6` pins all three). The query isolates its observers because recomputing a
*query* result runs user code — `StaleTime.dynamic`, `Enabled.when`,
`PlaceholderData.compute` — and a mutation result runs none, so the asymmetry
is the reason, not an oversight.

And **a throwing cache-wide `onSuccess` turns a successful fetch into an error**
is *not* changed. It is faithful to upstream — `query.ts`
runs the cache callback inside the same `try`, so a throw there becomes the
fetch's failure — and the data stays cached, so the next read is correct. It
is a real sharp edge in an otherwise complete user-code isolation policy, but
changing it would diverge from upstream on an error path the ported suite
pins, and no reproduction showed harm beyond the status. Recorded here so the
decision can be reopened rather than rediscovered.

### Found by the showcase (2026-09-09, from `24eae03` on)

The showcase (`examples/showcase/`, #25) exercises every feature through real
screens; what its widget and end-to-end tests find in the library is recorded
here, reproduced in the library's own suite before anything is changed, as
with the reviews.

1. **A read whose key changes lost `keepPreviousData` in the mixin and
   `context.query`** (binding). Upstream's `useQuery` is one observer per call
   site, so a new key is applied to the observer it already has, and
   `placeholderData: (previous) => previous` shows the old key's data while
   the new one loads. The mixin and the context extension identified a read
   by `(key, types, id)`, so a changed key was a *new* observer with nothing
   previous — the `initial-and-placeholder` screen switched a `watchQuery`
   from post 5 to post 6 and got a skeleton, while `QueryBuilder` (which
   applies the new key in `didUpdateWidget`) kept post 5. Decision: an `id`
   is the read's identity — `(#query, types, id)` — so a read that carries one
   keeps its observer across a key change; without an `id` a new key stays a
   new read, because two reads of one type in one widget cannot be told apart
   by call position (no rules of hooks here). Regression:
   `query_kit_flutter/test/key_change_test.dart`, all three styles plus
   the without-`id` case; the README's mixin and context sections say the
   rule.

2. **`structuralSharing` was invisible to every reader** (core). The
   `select == null` branch of `QueryObserver.createResult` ran
   `replaceEqualDeep(prevResult?.data, candidate)`, where upstream's is
   `data = state.data`. The cache write had already applied the query's
   `structuralSharing` hook, so an opt-out (`(_, next) => next`) put a fresh
   instance in the cache — and the observer then re-shared it against its own
   last result and handed back the old one. The `select-and-sharing` screen
   found it: the cache visibly held a new list while no reader ever saw one.
   Fixed by passing cached data through as upstream does; the placeholder
   case, which is *not* in the cache, is now shared here through the query's
   own hook, matching upstream's `replaceData(prevResult?.data,
   placeholderData, options)`. Regression: `showcaseFindings()` in
   `port_specifics_test.dart`.

### Sixth and seventh reviews (2026-09-10, of `56950db`)

Two reviews of the Flutter binding arrived together, one a summary and one
with ten numbered findings. Every claim was reproduced against `HEAD` before
anything changed; three did not hold, and what disproved them is recorded with
the rest. The regressions are the six behavioural ones, in
`query_kit_flutter/test/review_regressions_test.dart` under `R01`–`R07`.

1. **A `QueryMixin` State never noticed an overridden `queryClient`
   changing.** The client was resolved once in `didChangeDependencies`, which
   Flutter does not call for a plain widget update — and the documented
   override is `QueryClient get queryClient => widget.client`. Switching that
   widget field from one client to another left every controller, query and
   mutation on the old one: reproduced with two clients holding different data
   under one key, where the State kept showing the first client's after the
   second arrived. Per-tenant or per-user clients would keep operating in the
   context the app had just left. Fixed by reconciling at the start of every
   read (`_reconcileClient` from `_startEpoch`) rather than in a lifecycle
   callback, which also releases what the old client owned before the new
   reads are recorded.

2. **The same lazy lookup fixed a second finding**: mixing `QueryMixin` into a
   `State` threw `No QueryClientProvider found` even when the build read no
   query at all, because `didChangeDependencies` resolved the client eagerly.
   Only a read needs a provider now.

3. **A direction switch on an infinite query never reached the widget.** All
   three implicit reading styles, and the builders, skip a notification whose
   `QueryResult` equals the one last built — sound for a plain query, where the
   result is the whole of what a reader sees. An infinite query keeps its
   paging state on the controller: `fetchPreviousPage()` replacing an
   in-flight `fetchNextPage()` leaves the pages, the status and the fetch
   status untouched, so the widget went on showing `isFetchingNextPage`. The
   controller itself was right — the core notified, the binding discarded it.
   Fixed by naming what a reader can see: `ObservedState.observedState`, the
   result for a plain controller and `(result, the six paging flags)` for an
   infinite one, compared everywhere the result used to be. When only the
   paging half moved there is nothing for `buildWhen` to compare, so that case
   rebuilds without asking it.

4. **A `GlobalKey` subtree that moved lost its `context.mutation`.**
   `removeDependent` disposed the reader's controllers on the spot, but
   Flutter also calls it when an element is merely *deactivated*, and a
   deactivated element can be reactivated elsewhere in the same frame — which
   is what moving a `GlobalKey` subtree is. A widget that had started a
   mutation and never left the tree stopped observing it: the result never
   arrived. Fixed by making deactivation provisional — the reader is marked,
   a read clears the mark, and the post-frame sweep releases only what did not
   come back.

5. **Two providers on one client restored the notification scheduler in the
   wrong order.** Each provider saved whatever scheduler it found and put it
   back on dispose, which is only correct for lifetimes that nest. Siblings —
   or an old and a new provider overlapping for a frame — left the adapter
   uninstalled while a provider was still running, and installed after the
   last one had gone. Fixed by counting the installation per `NotifyManager`:
   the first provider saves the original, the last restores it.

6. **A connectivity stream that was taken away still drove the next client.**
   The last value the stream reported outlived it and was copied onto every
   client that arrived afterwards, so a client with no connectivity source at
   all could be pinned offline with nothing able to put it back — queries and
   mutations paused for good. Fixed by binding the remembered value to the
   stream that produced it: dropped when the stream is replaced, and carried
   across a client switch only while that same stream is still running.

7. **A `Stream` has no current value, and nothing filled the gap.** A provider
   given `onlineStatus` believed the default — online — until the first event,
   so an app launched in airplane mode fetched once against a network that was
   not there, and the README pushed the fix (`checkConnectivity()`) into user
   code where it is forgotten. Added `QueryClientProvider.initialOnlineStatus`,
   applied at mount and on a client switch.

**Not reproduced, and why.** These three were reported and are recorded
because the record is what makes a decision reopenable:

- *"A client passed via `client:` is never mounted, so no focus refetch, no
  reconnect, no paused mutations."* It is mounted:
  `_QueryClientProviderState.initState` calls `_mountClient`, which calls
  `client.mount()`, at the reviewed commit as much as at `HEAD`. A probe
  driving a focus round-trip on a `client:`-passed client refetched, 1 → 2.
- *"Duplicate-read detection confuses frames with builds, so the bootstrap
  build throws `read two mutations … in one build`."* The mechanism is real —
  the epoch advances once per frame, not once per build — but four attempts
  found no legal Flutter path that builds one element twice inside a frame
  without deactivating it first (which resets the reader anyway): cache
  notifications are deferred past the frame by the provider's own scheduler,
  and Flutter's own assertion forbids the artificial route. Left alone rather
  than changed on an unreproduced report.
- *"A reentrant `addListener` leaves an observer subscribed."* The window is
  real in the code — `_unsubscribe` is assigned only after `subscribe()`
  returns — but `QueryObserver.subscribe` does not notify synchronously, so no
  public path reaches it; the reproduction offered turned out to add the same
  listener repeatedly (a `ChangeNotifier` permits duplicates) and remove it
  once. The two-line guard was kept as hardening, not as a fix for an observed
  defect, and it changes no behaviour the suites can see.

### Ninth review (2026-09-10, of `f6a9ddd`)

Four reviews of `f6a9ddd` — a release review, a deep-dive, an architecture
review and a design pass — were consolidated on 2026-09-11; their findings are
numbered C1–C59, and this section holds the rows the tickets of map #33
landed, one per finding or group of findings, complete at the 0.1.0 release
commit (#47). Every finding was reproduced with the review's own probe before
anything changed, and the regression keeps the probe's name next to the
consolidated id — deep-dive `F`/`P` numbers, release-review `R` numbers — in
`port_specifics_test.dart` (`ninthReview()`) or `port_lifecycle_test.dart`.

- **C3 — a throwing cache `onError`/`onSettled` hung every caller of the
  fetch** (release R1, deep-dive F1; #37). `Query._settle` ran
  `_cache.onQueryFetchError` *before* `operation.completeError`, unprotected,
  and `_settle`'s own future is nobody's (`.ignore()`d in `fetch`): the hook's
  exception vanished and the operation stayed open. The `client.query` that
  started the fetch, the callers deduplicated onto it, and every
  `invalidateQueries` / `refetchQueries` / `resetQueries` awaiting it waited
  forever, while the query's state already said `error`. On the success path a
  throwing `onSettled` fell into the same `catch` and rethrew from there —
  also unheard. Probes: F1 ×3 and R1 ×2, `['pending', 'pending']` where
  `['error', 'error']` was expected, `invalidateQueries` never completing.
  Fixed in `_settle` by completing the operation *first* and running the hooks
  through `_runCacheHook`, which reports a throw to the zone — the isolation
  cache listeners and observer updates already have. Upstream's `fetch` *is*
  the operation, so a throwing hook rejects it there and, on the success path,
  dispatches an error over the data it just wrote; here the state is what the
  hook was told about, the caller sees that state, and the hook's failure is
  its own. Alternative not taken: completing the operation with the hook's
  error, upstream-like — it would make callers disagree with the query's
  state, and a telemetry hook's throw is not a transport failure.
  Regressions: `C3 / F1 (R1) a throwing cache onError|onSettled still settles
  every client.query caller of a failed fetch`, `… on the SUCCESS path still
  settles the caller with the data the cache holds`, `… await
  client.invalidateQueries() completes when the cache onError throws`.

- **C4 — `resumePausedMutations()` hung offline on an `offlineFirst` retry,
  and `mount()`'s focus refetches behind it** (release R4, deep-dive F3,
  P3a/P3b; #37). The fifth review's per-mutation gate (47) was `canFetch` —
  the retryer's *start* rule, `networkMode != online || isOnline()` — but a
  paused mutation is not started, it is continued, and the retryer continues
  under `networkMode == always || isOnline()`. The two differ for
  `offlineFirst`, which may make its first attempt offline but cannot retry
  offline: paused mid-retry, it passed the gate, `continueFetch` parked on the
  pause completer, and `resumePaused` awaited a network that was not coming
  back inside the call. `mount()` runs `resumePausedMutations` before every
  focus and reconnect refetch, so while offline *every* focus event's refetch
  — a `networkMode: always` query's included — was blocked behind the one
  mutation. Item 47 below and the divergence table's row were wrong to call
  `canFetch` "the same test the retryer applies"; both are corrected. Probes:
  F3 ×2, P3a, P3b, R4 ×2 — `resumePausedMutations` completes `false` after a
  day offline; focus-refetch count `1` (deep-dive) or `2` (with a control
  round) where one more was expected. Fixed by gating on the continuation's
  network rule: `Mutation.canResume` is `canContinue(networkMode,
  onlineManager)` (new in `retryer.dart`, next to `canFetch`) when a retryer
  exists, and the start rule for a restored mutation that has none yet.
  Only the network is asked, deliberately: a pause for focus or for the
  scope's turn is awaited, as upstream awaits it, because its own event
  releases it — and the ported `should notify queryCache after
  resumePausedMutations has finished when coming online` proved the scope
  half, going red when the first cut of the gate included `canRun`
  (`data2` overtook the scope-queued `mutation3`). Alternatives not taken:
  making `mount()`'s focus path not await the resume at all — upstream orders
  a mutation before the refetch that should reflect it, and with the gate
  right nothing that cannot go on is awaited; and making `resumePaused`
  resolve when a continued mutation re-pauses — a new contract for
  `continueMutation`, for a case (a restored `offlineFirst` mutation whose
  retry pauses offline inside the resume) that only stalls the one
  `_resumeThen` in flight, since the next focus event's gate skips it.
  Regressions, in `port_lifecycle_test.dart`: `C4 / F3 / P3 (R4)` — `F3 /
  P3a (R4) resumePausedMutations completes while offline when the only paused
  mutation is an offlineFirst retry that needs the network`, `F3 / P3b (R4) an
  offlineFirst mutation paused offline does not suppress the focus refetch of
  an independent networkMode.always query`.

- **C5 — a mutation removed inside the `MutationAdded` event kept retrying
  with its full policy; offline, its `mutateAsync` parked forever** (release
  R7, deep-dive P5/P5b/P5c; #37). `MutationCache.build` emits `MutationAdded`
  before the observer calls `execute`, so a listener removing the mutation
  there ran `destroy` while `_retryer` was still `null`: the cancel hit
  nothing, and the retryer `execute` built a moment later ran unaware —
  `RetryPolicy.times(2)` made 3 attempts, `RetryPolicy.always` 31 in thirty
  seconds, and offline the run paused for good with nobody left to resume it
  (the mutation was no longer in any cache). The divergence table's "`Mutation.destroy`
  stops the retries" row was false on this path; corrected. Probes: P5 `3`
  attempts, P5b `31`, P5c `mutateAsync` still pending a day after
  reconnecting. Fixed in `execute`, right after `_retryer = retryer`: `if
  (_removed) retryer.cancelRetry(immediately: true)` — the cancel `destroy`
  would have applied, now that there is something to apply it to. The one
  attempt still runs if it can start (an in-flight request is left to
  settle, as everywhere else); a run that cannot start rejects with a
  `CancelledError` on the spot, the fifth review's rule for a mutation
  removed during an async `onMutate`, so `mutateAsync` settles. Alternative
  not taken: refusing to `execute` a removed mutation at all — it would skip
  `onMutate`, the pending dispatch and the error callbacks, leaving the
  observer at `idle` with a `mutateAsync` that never settled, the very shape
  of the finding. Regressions: `C5 / P5 (R7) a mutation removed from the
  cache inside the MutationAdded event does not retry after removal`, `C5 /
  P5b (R7) the same through build() + remove() + execute(), with
  RetryPolicy.always`, `C5 / P5c (R7) removed from MutationAdded while
  offline, mutateAsync still settles`.

- **C6 — an observer's unsubscribe handle was not idempotent** (release R2,
  deep-dive F2 ×2 / P1; #38). `QueryObserver.subscribe` and
  `MutationObserver.subscribe` returned a closure that removed the listener
  and ran the last-listener teardown on *every* call. Called twice — a
  `dispose` after a manual unsubscribe, say — the second call took *another*
  registration of the same listener (`List.remove` finds the first `==`
  entry, and a tear-off is `==` to itself) and, with the list now empty, ran
  `destroy()` / `removeObserver` under a subscriber still present: no more
  notifications, and the gc timer armed. `Subscribable`, `QueriesObserver`
  and `MutationStateObserver` already guarded with a `removed` flag. Probes:
  F2 ×2, P1, R2 ×2 — `hasListeners` `false` with one registration left,
  `0` notifications where `1` was expected. Fixed with the same `removed`
  flag in both observers. Upstream's closure deletes from a `Set`, where a
  second delete finds nothing, so idempotence is upstream's behaviour
  regained, not a divergence. Regressions: `C6 / F2 (R2) a QueryObserver
  unsubscribe handle called twice does not remove another registration of
  the same listener`, `C6 / P1 (R2) a MutationObserver unsubscribe handle
  called twice removes nothing the second time`.

- **C7 — the adapted default wrappers of one function collided** (release
  R6, deep-dive F4 / P4a; #38). `QueryClient._memoised` kept one `Expando`
  keyed on the erased function, then on the data type — and the query
  wrapper and the mutation wrapper of the *same* function went into the same
  slot. A function registered as both `QueryDefaults.queryFn` and
  `MutationDefaults.mutationFn` (a stub, a logger, a fake backend) handed the
  mutation side a `(QueryFunctionContext) => FutureOr<int>`: `_TypeError` in
  the `MutationObserver` constructor when the query side was resolved
  first, and the other way round the query called the mutation wrapper
  (which happens to accept the context). Probes: F4, P4a, R6 — the
  `_TypeError`. Fixed with one memo per adapted default: three `Expando`s
  (`_adaptedQueryFns`, `_adaptedMutationFns`, `_adaptedSharing`), the memo
  passed into `_memoised`. Alternative not taken: keying the inner map on a
  `(kind, Type)` record — the same fix with a less visible shape.
  Regressions: `C7 / F4 / P4a (R6) one function as query default and
  mutation default: the adapted wrappers do not collide (either order)`,
  `C7 / P4b (R6) mutation default first, then query default: the query calls
  the query wrapper with its context`.

- **C8 — `QueryCache.build(state:)` only asserted "success ⇒ hasData"**
  (release R11, deep-dive F5; #38). `Query.setState` throws `ArgumentError`
  for a `success` state without data (eighth review, A10), but the
  persistence door next to it, `build(state:)`, checked the same rule with
  an `assert`. A release build accepted the state and the next observer's
  constructor died on `type 'Null' is not a subtype of type 'int'`, far
  from the write that caused it. Probes: F5 (an `_AssertionError` where an
  `ArgumentError` was expected) and the release probe under
  `dart run --no-enable-asserts`: `accepted=true error=_TypeError`; after
  the fix `accepted=false error=ArgumentError`. Fixed by throwing the
  `ArgumentError` `setState` throws, in every build mode. The A10 case is
  renamed `A10: build refuses a success state that carries no data` and
  asserts the `ArgumentError`. Regression: `C8 / F5 (R11) build(state:)
  rejects a success state without data the way setState does: an
  ArgumentError, not an assert`.

- **C9 — a query removed mid-fetch dispatched after its `QueryRemoved`**
  (deep-dive F6 ×2; #38). The eighth review's idle reset in `Query.cancel`
  — a silent cancel with no successor puts `fetchStatus` back to `idle`, so
  `cancelQueries(silent: true)` cannot wedge a query — ran on *every* silent
  cancel, `destroy`'s included. A query removed while fetching (`clear()`,
  `removeQueries`) therefore emitted `QueryUpdated(QuerySetStateAction)`
  after the cache's `QueryRemoved`, and an observer still attached to it
  received a result from a query outside any cache. Probe F6 ×2: `events
  after removal: [added, updated:QueryFetchAction, removed,
  updated:QuerySetStateAction<int>]`. Fixed by skipping the reset when
  `_removed` is set: a removed query dispatches nothing after its silent
  cancel, which is what upstream does after every silent cancel. The
  observer left behind is not told — upstream's behaviour too; its next
  `setOptions` or `refetch` re-resolves the key and joins the live entry.
  Regressions: `C9 / F6 clear() during a fetch: no QueryUpdated after
  QueryRemoved`, `C9 / F6 removeQueries() during a fetch: a subscribed
  observer is not notified from a query that already left the cache`.

- **C10 — `resumePausedMutations()` promised the settled state but returned
  the transport future** (release R3, deep-dive P2a/P2b; #38).
  `Mutation.continueMutation` returned `retryer.continueFetch()` — the
  retryer's future, which completes when the request does, *before* the
  first callback runs — while its own dartdoc, `MutationCache.resumePaused`'s
  and `QueryClient.resumePausedMutations`'s all said "settled". The visible
  cost: `mount()` awaits the resume before the reconnect refetch precisely so
  the refetch reflects the mutation, and the refetch ran before the
  `onSuccess` cache write. Probes: P2a (`[]` where `['onSuccess',
  'onSettled']` was expected), P2b (`[refetch, onSuccess]`), R3 (`resumed`
  already `true` under a pending async `onSuccess`). **Decision** — the
  options were (a) return the run's own future, `execute()`'s, which settles
  after the callbacks and the settled dispatch, or (b) leave the future and
  correct the three doc sites to say "transport". (a), as the reviews
  recommend: the ordering `mount()` relies on is the point of awaiting at
  all, and upstream's `continue()` for a restored mutation *is* `execute()`,
  so (a) makes the two paths agree. Upstream's `continue()` with a live
  retryer does return the retryer's promise — so upstream has P2b's race
  too; recorded in the divergence table. Fixed by `execute` recording its
  future (`_execution`, set with `_retryer`, cleared with it) and
  `continueMutation` releasing the pause with `continueFetch().ignore()`
  and handing `_execution` on. A hanging user callback now hangs the resume,
  as it hangs `mutateAsync` and upstream's `execute()`. Regressions, in
  `port_lifecycle_test.dart`: `C10 / P2 (R3)` — `P2a (R3)
  resumePausedMutations completes after the synchronous callbacks ran and
  the state settled`, `P2b (R3) a mounted client refetches on reconnect after
  the resumed mutation's onSuccess wrote to the cache`, `R3 resuming
  mutations awaits an async onSuccess and the settled state`.

- **C11 — `clear()` with an offline-paused optimistic mutation: the `onError`
  rollback re-creates the query, gc timer included, a few microtasks after
  `clear()` returned** (deep-dive P6; #38). Reproduced as described: `the
  rollback re-created the query after clear(); 1 timer(s) pending`, which is
  exactly what `queryWidgetTest`'s teardown sees. The cause is a decided
  rule, not an accident: a paused mutation the cache drops fails with a
  `CancelledError` (third/fourth review, pinned by C-M3 and D7/F03), so its
  `onError` runs, and the canonical rollback `setQueryData(key, previous)`
  writes into the cache `clear()` just emptied. Upstream never runs that
  rollback because it abandons the paused mutation — `mutateAsync` never
  settles there, the observer stays `pending`, and an in-flight mutation's
  late `onError` produces the very same write. **Decision** — the options:
  (a) skip the callbacks of a dropped paused mutation (silent, like
  `Query.destroy`): rejected, it un-decides the rule the two regressions
  pin, and the rollback is *wanted* when a single mutation is removed at
  runtime; (b) make the write not create, or not arm gc, when it comes from
  a removed mutation's callback: a zone-scoped flag changing what
  `setQueryData` means depending on who calls it — rejected as magic, and an
  entry without gc is a leak; (c) have `clear()` clear again once the dropped
  runs settle: rejected, it would wipe whatever the app wrote in between
  (logout, then the login screen's prefetch); (d) keep the core rule —
  `clear()` empties the caches, it does not seal them, and a write after it
  is a write like any other — state it on `QueryClient.clear` and
  `Mutation.destroy`, and make the teardown that must leave nothing pending
  let the callbacks run and clear once more. (d): the only shape that is
  honest about what happens without inventing a second meaning for a
  write. The teardown a widget test writes therefore pumps once after
  `clear()` and clears again — the fourth and fifth of its five steps. That
  teardown is a documented snippet, not an export: C2 (#42) removed
  `lib/testing.dart` and ADR-0002 records why, so the five steps live in the
  site's testing guide and the binding README, are compiled and run in
  `examples/doc_snippets/test/teardown_snippet_test.dart`, and are
  reimplemented by the binding's own harness (`test/harness.dart`,
  `queryWidgetTest`) and by both examples (`showcaseTest`, `demoTest`).
  Regressions: `C11 / P6 the onError rollback re-creates the query after
  clear(); a second clear once the callbacks ran leaves nothing pending`
  (`port_lifecycle_test.dart`, the decided behaviour) and, in the binding's
  `harness_test.dart`, `C11 an offline optimistic mutation left paused: its
  rollback runs after clear(), and the teardown still leaves nothing
  pending` — red on a teardown that stops at the first `clear()`, with `A
  Timer is still pending even after the widget tree was disposed`.

- **C12 — a restored `pending` mutation with `hasVariables: false` was
  never continued** (deep-dive P7; #38). `continueMutation` ran a restored
  mutation only `if (… && _state.hasVariables)`, but a `void`-variables
  mutation is naturally restored without variables, and
  `resumePausedMutations` then reported success having run nothing. Probe
  P7: `0` executions where `1` was expected. Upstream's `continue()` calls
  `execute(this.state.variables!)` regardless. Fixed by running when
  `hasVariables || null is TVariables`: `null` is a real value for a
  nullable or `void` `TVariables`. A non-nullable `TVariables` restored with
  no variables at all is still left alone by `continueMutation` — there is
  nothing to run it with, and the dartdoc says so. **Follow-up, 2026-09-12:**
  that state is now refused where it enters. `MutationCache.build(state:)`
  throws an `ArgumentError` for a `pending` state with `hasVariables: false`
  when `null is! TVariables`, the mutation twin of the door C8 put on
  `QueryCache.build` — the alternative was what the map left: a mutation that
  sits in the cache forever while `resumePausedMutations` reports success
  having run nothing, with the loudest symptom arriving nowhere near the
  restore that caused it. Nothing inside the port passes `state:` to
  `MutationCache.build`; it is the persistence door and nothing else, so the
  check costs a restore that was already broken and no working caller.
  `continueMutation` keeps its own guard for a mutation built by hand and
  `add`ed past the door. Regressions, in `port_lifecycle_test.dart`:
  `C12 / P7` — `P7 a restored pending mutation with hasVariables false and
  void variables is continued`, `P7 a restored pending mutation with
  non-nullable variables and none restored is refused by the persistence
  door` (the "is left alone" case, rewritten onto the door).

- **C13 — `hasNextPage`/`hasPreviousPage` flipped without a notification when
  `select` collapsed the change** (release R5, deep-dive P1/P11; #38). The
  fifth review made `InfiniteQueryObserver.shouldNotify` re-ask the two
  paging flags only when the paging functions changed, on the argument that
  equal results carry `==`-equal data. Equal *results* do not mean equal
  *data* under a `select`: `pages.length` over a page whose cursor turned
  `null` is the same result, and when the write kept `dataUpdatedAt` too
  (a manual write or restore with the same timestamp) nothing else differed,
  so the flags flipped in silence. A real refetch is not affected — its
  `isFetching` transitions notify (the deep-dive's refetch variant was green
  at `f6a9ddd`). Probes: P1 (R5), P11, R5 — `0` notifications where `1` was
  expected. Fixed by making the data part of the memo key: `_notifiedData`
  is recorded with the paging options at each notification, and the flags
  are re-asked when the functions *or* the data (by identity — structural
  sharing hands an equal write back as the same instance) differ from what
  the last notification was answered over, old over old against new over
  new. Still lazy about user code: when the result changed, `||`
  short-circuits before the paging functions are called, so the ported
  suite's call counts hold. Regressions: `C13 / P1 (R5) hasNextPage flips on
  a same-timestamp write whose selected result is unchanged: the listener is
  told`, `C13 / P11 (R5) hasPreviousPage flips the same way`.

- **C14 — the `select` memo compared with `identical`, the options with
  `==`** (deep-dive P12; #38). `createResult` reused the last selection only
  when `identical(select, _selectFn)`, while `DefaultedQueryObserverOptions`
  compares `select` with `==`. An instance-method tear-off is `==` to the
  next tear-off of the same method but never `identical`, so a widget
  passing `select: model.pick` re-ran the selector on every `setOptions`
  that the options said changed nothing — work only, no wrong notification.
  Probe P12: `5` runs where `0` were expected. Fixed with `==` at both memo
  sites (the placeholder path's `select` check too). Upstream memoises on
  `===`, where a bound method is a fresh function object each render and
  the re-run is the price paid; Dart's `==` on tear-offs is exactly the
  distinction worth keeping. Regression: `C14 / P12 an instance-method
  tear-off select is not re-run per setOptions (== but not identical)`.

- **C16 — `QueryCancelToken.onCancel` on an already-cancelled token ran the
  callback unisolated** (deep-dive probe O3; #38). `cancel()`'s loop wraps
  every callback in a `try`/`catch` that reports to the zone (third review),
  but the "already cancelled, run it now" branch called the callback bare, so
  a throwing late registration threw into the query function registering
  it. Probe O3: `threw StateError: Bad state: late`. **Decision** — the
  options were the same isolation, or one dartdoc sentence saying the late
  path throws into the caller. Isolation: a callback's throw is the
  callback's own whichever path runs it, and a query function should not
  have to know which path it got. Fixed by routing both paths through one
  `_run`. Regression: `C16 / O3 onCancel on an already-cancelled token
  isolates a throwing callback like the loop path does`.

- **C15 — not reproduced: `MutationStateController.addListener` has no
  `_subscribing` guard, and needs none** (architecture review; #39). The
  guard the third review put into `QueryController`, `MutationController`
  and `QueriesController` closes a window their observers open: `subscribe`
  on a `QueryObserver` can notify *synchronously* — the result moved on
  while nobody listened, and `onSubscribe` reports the difference on the
  spot — so a listener called from inside the first subscription could add
  a second listener, whose `addListener` still saw no handle and subscribed
  again. `MutationStateObserver.subscribe` has no such notification:
  `_update(notify: false)` refreshes the result silently *before* the
  listener is added, and `MutationCache.subscribe` (a `Subscribable`) never
  notifies on subscribe either. There is no first notification to re-enter
  from, so the guard's condition cannot arise. The probe drove the same
  shape as the third review's regression — attach, detach, run a mutation
  behind the detached observer, re-attach with a listener that adds a
  listener — and counted `0` listener calls inside `addListener`; after
  every listener left, `mutationCache.hasListeners` was `false`, one
  subscription released once. No regression kept: the case would pin an
  absence, and the third review's `a listener that leaves inside its first
  notification unsubscribes` already pins the mechanism for the observers
  that have it. The architecture review's C50 (one `ListenerRegistry` for
  all six hand-written registries) is where a shared guard would belong,
  and is out of this map's scope.

- **C17 — a changed `isAppShown` was ignored until remount** (release R8,
  deep-dive P1(R8); #39). `_observeLifecycle` captured
  `widget.isAppShown ?? _isShown` into the `AppLifecycleListener` it
  installed, and `didUpdateWidget` re-wired the listener only for a new
  client or a toggled `observeAppLifecycle`; a provider rebuilt with a
  different mapping kept mapping with the old one. Probes P1(R8) and R8:
  `isFocused()` stayed `false` after `inactive → resumed` under a mapping
  that says `true`. **Decision** — two options. (a) Read the mapping at
  delivery time, so the latest build's decides the next transition; a
  closure new on every build costs nothing, as the deep-dive's P15 asks.
  (b) The same, and when the mapping's identity changes, re-apply it to the
  state the app is already in. Taken: (b). The class doc promises the
  current state is mapped, not only the transitions after it, and a mapping
  switched from "never shown" to "shown" while the app sits resumed would
  otherwise leave the client unfocused until the platform happens to send
  something; `setFocused` with an unchanged value is a no-op, so an inline
  closure costs one call of a pure function per provider rebuild — P15
  stays green (the test binding reports no lifecycle state until one is
  set, and the closure is not called for `null`). Rejected: re-wiring the
  whole listener on a mapping change (a dispose and re-register of a
  `WidgetsBindingObserver` per rebuild for an inline closure, for nothing
  a delivery-time read does not give). Regressions: `C17 (P1, R8) a
  changed isAppShown on the same client decides the next transition without
  a remount`, `… is applied to the state the app is already in`.

- **C18 — `mutate()` on a disposed `MutationController` re-attached the
  destroyed observer, and the mutation was never collected** (deep-dive
  P3a/P3b; #39). `dispose` destroys the observer — detaches it from its
  mutation and drops its listeners — but `MutationObserver.mutateAsync`
  builds a mutation and `addObserver(this)` unconditionally, so a `mutate`
  after `dispose` put the dead observer back on a fresh mutation, and
  `optionalRemove` (observers non-empty) never removed it. The scenario is
  ordinary Flutter: a handler awaits a dialog, the widget is gone when it
  continues, `context.mutation`'s controller is disposed, `mutate` runs.
  Probes P3a and P3b: `[Mutation(1, MutationStatus.success)]` still in the
  cache two seconds past a one-second `gcTime`, with one observer attached.
  Upstream leaks identically (a forgotten `useMutation` observer re-attaches
  the same way and nothing ever removes it). **Decision — diverge; four
  options.** (1) Keep upstream's behaviour: rejected, the ticket's premise.
  (2) Throw `StateError` from `mutate` and `mutateAsync` after `dispose`.
  (3) `mutate` a no-op reported once through `FlutterError.reportError`,
  `mutateAsync` a failed future. (4) Run the mutation without attaching:
  `mutationCache.build(client, observer.options).execute(variables)`, the
  path a mutation nobody observes already takes — the options' callbacks
  run in the `Mutation`, the settled mutation arms its own collection
  (fourth review), and `value` stays idle. Taken: (4). Under (2) and (3) the
  user's save is *lost* — the dialog-then-mutate handler that works under
  upstream stops working, and a throw after an `await` is an unhandled
  async error that nobody's `try` sees; a leaked cache entry is the lesser
  harm, and (4) removes even that. Per-call `callbacks` are dropped, which
  is the existing rule for a run whose observer has no listener ("a
  `mutate` whose widget has since gone must not call back") and what
  upstream does for an unmounted component. `ChangeNotifier`'s
  after-dispose assert is the Flutter precedent for (2), but it guards a
  *listener* registration, which after dispose can only be a bug; a
  mutation after dispose is the tap handler doing its job. Binding-only:
  the core's `MutationObserver.destroy()` still says "for good" and its
  `mutateAsync` still re-attaches — noted for the core, not changed here.
  Regressions: `C18 (P3a, P3b) mutate() on a disposed MutationController
  runs the mutation, attaches nothing, and lets it be collected`, `… 
  mutateAsync still completes with the data`, `… P3b a tap handler
  outliving its context.mutation widget leaks nothing`.

- **C19 — `QueryListener`'s dartdoc promised every transition; R9 as a
  behaviour bug is refuted** (release R9, deep-dive §4; #39). The release
  review's R9 expected a listener to see `[1, 2]` for two `setQueryData`
  writes inside one `notifyManager.batch`; it sees `[2]`. That is what a
  `ValueListenable` is: a notification says "the value changed", the value
  is read when it arrives, and a batch is precisely the request to coalesce
  — the controller drops the observer's snapshot in `batchCalls((_) =>
  _notify())` on purpose, and `_ResultListenerState._onResult` compares the
  value it reads against the last one it saw. Probe R9: `[2]` where `[1,
  2]` was expected; the deep-dive's P2 pins `[2]` and two raw notifications
  as the intended behaviour. What was wrong was the sentence "sees every
  subsequent transition", which a reader takes as "every write". Rewritten
  on `QueryListener` to say what is delivered: each notification whose
  value differs from the last one seen is a transition, `listenWhen` sees
  each of those, a rejected one still advances the comparison, and a batch
  of writes is one transition to the last value. Doc only; no regression.
  The widget side of the same rule was wrong the other way (C32, #45): the
  rebuilds guide, the binding README and the package example said a refetch
  returning equal data produces "no new result, so nothing rebuilds", but
  `QueryResult ==` includes `fetchStatus` and `dataUpdatedAt`, so that
  refetch *is* a new result and the widget does rebuild, with an unchanged
  `data` — which is what the showcase's `select-and-sharing` counters have
  shown all along. Rewritten to say so; `buildWhen` is named as the tool for
  a reader who wants no rebuild.

- **C1 — an options literal without `select` inferred its data type to
  `dynamic`** (deep-dive B1/B3/B6, api-design probe; #35, #41; ADR-0001).
  `QueryObserverOptions<TQueryData, TData>` carried `TData` only in its
  optional `select`, so an inline literal without one — through any of the
  four plain call styles — became `QueryObserverOptions<int, dynamic>`, the
  controller a `QueryController<int, dynamic>`, and the cache entry a
  `Query<dynamic>` that every typed reader of the key then threw on
  (`QueryDataTypeError`). Reproduced with the deep-dive's probe on `f6a9ddd`:
  `QueryController.create`, `QueryBuilder`, `context.query` and `watchQuery`
  all put `Query<dynamic>` in the cache. The research
  (`docs/research/dynamic-inference-guards.md`) found no library-side guard:
  the one analyzer diagnostic needs `strict-inference` in the *consumer's*
  options, a bound silences it, an `assert` is compiled out. The fix is
  structural: the observer options are two shapes over a sealed
  `QueryObserverOptionsBase<TQueryData, TData>` — `QueryObserverOptions<TData>`
  with no `select` and one slot, anchored by `queryFn`, and
  `QuerySelectOptions<TQueryData, TData>` with `select` **required**
  (`SelectFn<TQueryData, TData>`), so a literal without one is a compile
  error. Mirrored for infinite queries
  (`InfiniteQueryObserverOptions<TPageData, TPageParam>` /
  `InfiniteQuerySelectOptions<TPageData, TPageParam, TData>` over
  `InfiniteQueryObserverOptionsBase`). `QueryObserver`, `QueriesObserver`,
  `InfiniteQueryObserver`, `QueryClient.defaultQueryObserverOptions` /
  `infiniteObserverOptions` / `observe` / `observeInfinite` take the base;
  `DefaultedQueryObserverOptions` is unchanged. In the binding the plain entry
  points take the one-slot shape, the select entry points the two-slot one,
  the general `QueryController(client, options)` and the infinite entry
  points the base (inference reads every slot off either shape, so
  `InfiniteQueryBuilder(options: feedQuery(), …)` names no type argument).
  The residue — a key-only literal with neither `queryFn` nor a type
  argument — is caught by a debug backstop in `QueryController`'s and
  `InfiniteQueryController`'s generative constructors, `assert(<Object?>[]
  is! List<TData>, …)`, a top-type test that names the cure; it is
  **compiled out of release**, which is why it is a backstop and not the
  answer, and why the docs recommend `strict-inference` to consumers. Not in
  the core: the ported suites build key-only observers on purpose, and
  `QueriesObserver` may legitimately be `<dynamic, dynamic>`. The observer's
  own `_checkDataType` stays as defence in depth; after the split it is
  reachable only through covariance (`QueryObserverOptions<Never>` is a
  `QueryObserverOptionsBase<int, String>`), which is how D3/F10 now reach
  it. The sweep touched every options literal and every explicit type
  argument in core, binding, both examples, the snippets and the site
  (`<X, X>` → `<X>`; a literal with `select:` → the select shape; three
  `copyWith(select: …)` test sites became select literals, since a plain
  `copyWith` cannot change shape; the showcase's `todosQuery` split into a
  select helper and `rawTodosQuery`). Regressions: `C1: a plain literal makes
  a QueryObserver<int, int>` and `C1: a select literal makes a
  QueryObserver<int, String>` here; in the binding's
  `review_regressions_test.dart`, `C1 (B1, B3, B6) one type slot` — an inline
  literal without `select` or type argument through each plain style yields
  a `Query<int>`, the infinite builder and an inline infinite literal infer
  every slot, and the backstop's message for a key-only literal.

- **C2 — `flutter_test` was a regular dependency of the binding, for
  `lib/testing.dart`** (release review, §1; #36, #42; ADR-0002). Reproduced
  with `flutter pub deps --style=compact` in `examples/showcase`:
  `query_kit_flutter 0.1.0 [flutter flutter_test meta query_kit]`, with
  `test_api`, `matcher` and `leak_tracker_*` in every consumer's regular
  graph — the pubspec comment "nothing is pulled from pub.dev" and the
  README's "No dependency beyond Flutter itself" were both false, and pana's
  platform tagger would have followed `flutter_test` to `dart:io` and marked
  the binding not-Web on its package page. **Decision** (#36, the research
  in `docs/research/test-helper-packaging.md`) — the options: (1) a companion
  `query_kit_flutter_test` package: the honest place for the dependency, but
  the helper *is* `testWidgets` plus `WidgetTester`, so it could not stay off
  `flutter_test` the way `bloc_test` does, and it costs a permanent pub.dev
  name, a seventh workspace member, a third publish stage with its own wait
  and a third leg in every CI job, for two functions with one caller in the
  repository (their own test); (2) a documented snippet: `flutter_test`
  moves to `dev_dependencies`, `lib/testing.dart` goes, and the teardown is
  the first section of the testing guide and the README, compiled and run
  in `examples/doc_snippets/test/teardown_snippet_test.dart`; (3) keep the
  regular dependency: no points lost, but a visible contradiction between
  what the package says and what its page shows, and a floor bump every time
  `flutter_test` changes its API. (2), as provider, go_router and dio do.
  After: `query_kit_flutter 0.1.0 [flutter meta query_kit]`, and
  `dart pub publish --dry-run` passes. No regression: a dependency graph
  is checked by the deps line, not a test.

- **C41 — the testing guide claimed "Both example apps wrap the same
  helper"** (§6; #42). False as written: `queryWidgetTest` had one caller,
  its own test, and the showcase and task_manager each re-implemented the
  teardown — the showcase and task_manager with `pumpAndSettle` before
  `clear()`, the binding's own `widgetTest`s without it, none with the
  second pump and clear C11 added. Both examples (`showcaseTest`,
  `demoTest`) now take the snippet's five steps in its order, and the page
  says what is true: they wrap one *shape*, shown on the page as the
  fifteen-line `queryWidgetTest` a suite writes once.

- **C45 — `queryWidgetTest` was shallow and unused; the binding's tests
  rolled `widgetTest` ×3 and `withClient` (33 calls) themselves, with an
  inconsistent teardown order** (§7; #42). Not deepened as API — with C2
  there is no API to deepen. The binding's suite got one harness instead,
  `packages/query_kit_flutter/test/harness.dart`: a client per case
  (`createClient` for defaults), a second client adopted for the teardown
  (`tester.adopt`), the provider wired with lifecycle observation off
  (`app`, `tester.pumpApp`), the app lifecycle put back to `resumed` when a
  case faked it, and the teardown once, in the documented order. The three
  local `widgetTest`s, `withClient` and the inline `try`/`finally` copies of
  tree-pumping cases are gone; the cases that pump no tree keep their
  `client.clear()`. Pure plumbing: every case kept its name and its
  assertions (the JSON reporter's name list before and after was diffed),
  `testing_helper_test.dart`'s three cases became `harness_test.dart`'s,
  plus one for `adopt` — 96 cases became 97.

- **C29 — plausible, not reproduced: `then((_) {}, onError: (Object e) =>
  error = e)` in `query_test.dart`** (release R17; #44). The release review
  reported `invalid_return_type_for_then` from Dart 3.13 at the three sites
  (`should not continue when last observer unsubscribed if the signal was
  consumed`, `should not continue if explicitly cancelled`, `should not
  override fetching state when revert happens after new observer subscribes`).
  On 3.10.7, locally and in CI, `dart analyze --fatal-infos` and the test
  runner both accept the form: `onError` is typed `Function`, so only that
  diagnostic looks at its return type, and here it lets an `Object`-valued
  expression body stand in for the `void` the `then` closure returns. A
  stricter check would be a plausible tightening on a later SDK, and the
  three sites are the only expression-bodied `onError` callbacks in the ported
  suites, so they are block bodies now (`onError: (Object e) { error = e; }`);
  the 44 cases of the file pass unchanged. No regression: nothing behavioural
  moved.

- **C25–C28, C30 — release hygiene, no behaviour** (deep-dive 3.16, 3.17,
  3.28; release R13, R15, R16, R18; #44). C25: the three example pubspecs
  depended on `query_kit_flutter: ^0.1.0-dev`, which `0.1.0` does not satisfy
  once the package is hosted; now `^0.1.0`, like `doc_snippets` already was.
  C26: the installation page's "Before the first publish" git dependency could
  not resolve, because the binding's pubspec needs a hosted `query_kit`; the
  section and the admonition's link to it are gone. C27: `scripts/release.sh`
  took any `git tag -a` failure for "already exists" and pushed whatever the
  tag pointed at; `ensure_tag` now reuses a tag only when its target is
  `head_sha` and aborts naming both SHAs otherwise, and the preflight checks
  for `flutter` as well as `dart`, `gh` and `curl`. C28:
  `tool/rename_packages.dart` applied its renames as sequential `replaceAll`s,
  so the shorter name hit the longer one's output (`query_kit_next_flutter` →
  `query_kit_next_next_flutter`, 27 such moves in a dry-run); one
  `replaceAllMapped` over a longest-first alternation now, and the dry-run is
  the test — two runs, identical, zero `next_next`. C30: `npm audit` in
  `website/` reports 26 advisories (18 high, 8 moderate) before and after
  `npm audit fix`, every one behind a major bump npm will not take without
  `--force` (`webpack-dev-server` 6 for `sockjs`/`uuid`/`express`/`qs`,
  `serialize-javascript` and `image-size` with no fix at all), all in the
  build tooling of the documentation site; both example backends audit clean.

- **C20 — the `InfiniteData` a fetch wrote held two growable lists, and
  `flatten<T>()` cast each page blindly** (deep-dive api-design P5; #40,
  #43). Reproduced with the probe: `getInfiniteQueryData(key)!.pages.add(…)`
  threw nothing and the cache read back two pages after one fetch — a
  mutation behind every observer's back, which #16's "an infinite query is
  an ordinary `Query<InfiniteData>`" had promised could not happen; and
  `InfiniteData<int, int>(pages: [1, 2]).flatten<int>()` failed on `_TypeError:
  type 'int' is not a subtype of type 'Iterable<int>' in type cast`, naming
  neither the page nor a way out. **Decision** (#40): every `InfiniteData`
  the library writes seals its lists — `addToEnd`/`addToStart` return
  `List.unmodifiable` (that covers the fetch result and the `maxPages`
  drop), `copyWith` copies a *replacement* list into an unmodifiable one and
  keeps a list the instance already holds as it is, identity included, and
  the structural-sharing walk builds its result on `previous.copyWith`
  rather than `next.copyWith`, so an unchanged list keeps its identity (the
  fourth review's `C-M1 … shared structurally on refetch` went red when the
  first cut wrapped unconditionally — `same(before.pageParams)` — and is
  what pinned that rule). The `const` constructor is untouched and wraps
  nothing: a `const [...]` literal is already unmodifiable, and a growable
  list handed in through `initialData`/`setQueryData` is the caller's own,
  one sentence in the class doc says so. `flatten<TItem>()` checks every
  page `is Iterable<TItem>` up front and throws an `ArgumentError` naming
  the page's runtime type and the two cures (a type argument, or a `select`
  over the pages). Value equality is unchanged — over the two lists'
  contents — so the ported suites' `const InfiniteData(...)` expectations
  still match a sealed result; a page that is itself a `List` compares by
  `==` as it always did. Alternative not taken: dropping `const` to wrap in
  the constructor, which would break every literal in tests and docs for a
  guarantee the cache boundary gives anyway. Regressions: `C20 / P5 the
  pages and pageParams a fetch writes are unmodifiable`, `C20 / P5 a
  structurally shared refetch result is unmodifiable too, and an unchanged
  list keeps its identity`, `C20 / P5 flatten<T>() over pages that are not
  Iterable<T> throws an ArgumentError naming the page type and the cure`.

- **C21 — the `*ObserverRef` interfaces were implementable and the cache
  plumbing callable from any package** (deep-dive api-design; #40, #43). The
  probe implemented `QueryObserverRef` from a consumer package and it
  compiled. **Decision** (#40): the two refs stay `abstract interface class`
  and exported — a cache event names its observer through them, and Dart
  cannot say "implementable inside the package only" across libraries
  without `part` files — and their *members* are `@internal`: the eight of
  `QueryObserverRef` (`onQueryUpdate`, `isEnabledForQuery`,
  `isStaticForQuery`, `currentResultIsStale`, `shouldFetchOnWindowFocus`,
  `shouldFetchOnReconnect`, `refetchOnEvent`, `observerQueryOptions`),
  `MutationObserverRef.onMutationUpdate`, the same members' overrides on
  `QueryObserver` and `MutationObserver` — the analyzer flags a call through
  the override only when the override itself carries the annotation, which
  a throwaway consumer file confirmed — and the cache-side overrides
  `QueryCache.onQueryStateUpdated` / `onQueryRemovalRequested` /
  `onQueryFetchSuccess` / `onQueryFetchError` and `MutationCache`'s
  `canRunMutation`, `onMutationSettled`, `onMutationStateUpdated`,
  `onMutationObserverAdded`, `onMutationObserverRemoved`,
  `onMutationRemovalRequested`, `onMutationStarting`, `onMutationSuccess`,
  `onMutationSettledCallback`, `onMutationError`. `Query`/`Mutation`'s own
  plumbing (`addObserver`, `removeObserver`, `setOptions`, `setData`,
  `destroy`, `markRemoved`, `onFocus`, `onOnline`) was `@internal` already;
  `Mutation.execute` stays public because the binding's disposed-controller
  path (C18) runs a mutation through it. `dart analyze --fatal-infos` over
  the binding, both examples and the snippets is clean, so nothing outside
  the core called any of them. No runtime regression is possible for an
  analyzer diagnostic; the barrel's `hide` lists are asserted by
  `barrel_test.dart` (VM only — it reads the source, since the Flutter-bundled
  SDK ships no `dart:mirrors` and the binding has none either).

- **C23 — the shape nits, decided one by one** (deep-dive api-design P4/P6,
  release review; #40, #43). Changed: (1) `toString` on every sealed option
  value (`StaleTime`, `GcTime`, `Enabled`, `RetryPolicy`, `RetryDelay`,
  `RefetchOn`, `RefetchInterval`, `InitialData`, `PlaceholderData`) reads as
  the source form — `StaleTime.duration(0:00:05.000000)`,
  `RetryPolicy.times(3)` — and `QueryOptions`, both observer shapes and the
  three infinite shapes print the key plus the fields that are set, through
  a `@protected` `toStringFields` map each subclass extends (the infinite
  shapes drop the derived `behavior` and `queryFn` for the paging fields);
  `QueryFilters`/`MutationFilters` the same through a hidden
  `describeFilters`; a `MutationResult` prints its variant, the variables
  once set, the data or the error, and `paused`. (2) `MutationState`'s
  `==`/`hashCode` no longer include `errorStackTrace`, aligned on
  `QueryState`, whose traces were never compared: a trace never compares
  equal by value, so every rebuilt error state was unequal to the one it
  copied. No ported mutation case depended on it — the suite passed
  unchanged. (6) `FetchBehavior` and `FetchContext` are exported: the type
  of `QueryOptions.behavior` was in a public signature but not nameable,
  which broke `dart doc` links and forced `dynamic` on anyone holding one;
  `QueryCacheRef`/`MutationCacheRef` stay hidden, and building a
  `FetchContext` stays `@internal`. (7) The binding hides `ObservedState`
  and `observedStateOf`, the seam between its builders and controllers,
  as it already hid `QueryScope`/`QueryScopeElement`. (9) `setQueryData(key,
  'x')` against a query holding `String?` infers `String` and throws
  `QueryDataTypeError`; the error now names the cure when the two types
  differ only in nullability — `setQueryData<String?>(key, value)` — and
  the method's doc says so. (10) The mutation callback types are typedefs
  — `OnMutate`, `OnMutationSuccess`, `OnMutationError`,
  `OnMutationSettled` — used by `MutationOptions`, `MutationOptions.simple`,
  `MutateCallbacks` and `DefaultedMutationOptions`; the binding repeated
  none. (11) `RetryDelay.custom` is `RetryDelay.dynamic`
  (`RetryDelayCustom` → `RetryDelayDynamic`), the one outlier among three
  consistent families — `.when(predicate)` decides, `.dynamic(fn)` computes
  the value from the query or the attempt, `.compute(fn)` produces data —
  named in the options guide. Doc only: (3) `RetryTimes(0)` "behaves like"
  `RetryPolicy.never`, the two being distinct values of a sealed type; (4)
  `retryOnMount` defaults to `true`, on the field and on `QueryDefaults`;
  (5) `QueryKey` parts compare with `==`, so `QueryKey([1]) ==
  QueryKey([1.0])` on every platform; (8) `MutationResult.mutate` has no
  per-call callbacks — a divergence row below, and the field's doc points
  at `MutationObserver.mutate(variables, callbacks)` /
  `MutationController.mutate`. Kept: `QueryClient.infiniteObserverOptions`,
  `QueriesObserver`'s eager validation, the refs as `abstract interface
  class` (C21). Regressions: `C23.2 two MutationStates differing only in
  errorStackTrace are equal`, `C23.9 setQueryData against a nullable query
  names the type argument to write`, `C23.1 toString reads as the source
  form, unset fields skipped`; `barrel_test.dart`'s `C23.6 …`; the
  binding's `C23.7 the barrel hides the seam between builders and
  controllers`.

- **C24 — vestigial surface** (deep-dive api-design A9; #40, #43).
  `QueryFilters.withType` is gone: zero callers, a one-field copy of a
  `const`-constructible type. `hasNextPageOf`/`hasPreviousPageOf` are
  hidden from the barrel: they exist so `InfiniteQueryObserver` can reach
  the top-level `hasNextPage`/`hasPreviousPage` from inside a class whose
  own getters shadow the names, and a grep of the binding, both examples
  and the site found no caller outside `lib/`. `infiniteObserverOptions`
  and `QueriesObserver`'s discarded `defaultQueryObserverOptions` call stay
  as their docs describe. Regression: `barrel_test.dart`'s `C24 the
  observer-internal paging aliases are hidden`.

- **C22 — moot: what `testing.dart` should export** (deep-dive 3.14; #40).
  The question assumed the export; ADR-0002 (#36, #42) removed the library
  and the helper with it, so there is nothing left to shape. Nothing changed
  for this id.

- **C43 — `maxPages` is upstream-faithful; release R10 refuted, doc added**
  (release R10; #45). The release review lowered `maxPages` on a query
  already holding more pages and expected the next fetch to trim the excess
  at once; it trimmed one page. That is upstream's arithmetic
  (`infiniteQueryBehavior.ts`, `addToEnd`/`addToStart` in `utils.ts`): a
  page added past the limit drops exactly one page from the other end
  (`slice(1)` / `slice(0, -1)`), never more, and the port's `addToEnd` /
  `addToStart` in `infinite_query.dart` do the same — a directional fetch
  swaps one page for one, and the count comes down to the new limit at the
  next refetch, whose loop rebuilds the pages from the first under
  `maxPages`. Behaviour kept; the `maxPages` dartdoc now says so, so the
  next reader is not surprised. Doc only; no regression. (Not to be
  confused with the fifth review's item 58, whose "R10" is that review's
  own numbering and concerns `StaleTime.static` polling.)

- **C31–C38, C42, C46 — documentation and example corrections** (deep-dive
  3.18–3.25, architecture review; #45). Every claim was checked against the
  code before the text moved, and the code was right each time. C31: the
  binding README and the showcase's `focus-refetch` screen said `inactive`
  "counts as focused on purpose"; `QueryClientProvider` reads it per
  platform (focused on iOS, Android and Fuchsia, unfocused on macOS, Windows
  and Linux) and the class doc and site already said so — README, screen and
  the showcase test's comments now agree, naming Android as the test
  binding's platform. C33: the root README listed `QueriesObserver` as "not
  ported" and `initialDataUpdatedAt` as "`DateTime?` only" — both exist
  (`queries_observer.dart`, `initialDataUpdatedAtCompute`); the showcase
  README said `useQueries` was absent two rows below the `query-collections`
  screen that shows it; the feature matrix called the compute form "a
  `DateTime?`". C34: the `select-and-sharing` screen and test described the
  no-select sharing pass as an open bug with a skipped test; it was fixed on
  2026-09-09 ("Found by the showcase", item 2) and the test runs green — the
  comments now say what was found and that it is fixed. C35: the site said a
  cancel is "silent by default"; `cancelQueries` is `revert: true, silent:
  false`. C36: the options page said `StaleTime.static` is "skipped by every
  refetch trigger"; an explicit `refetchInterval` polls it (item 58 above),
  and the page now says so beside the dartdoc. C37: the core changelog's
  bullet written relative to unpublished revisions ("used to fire a fraction
  early", "no longer rewrites") is gone; what stays is absolute, and the
  test count is not repeated there. The binding changelog had no relative
  bullet. C38: "three ways" is "two" in `examples.md`, `first-query.md` and
  the package example (the file has two styles); the `cancelQueries`
  dartdoc described `silent` twice; `QueryDataTypeError` now says it is
  thrown synchronously from the call (`QueryClient.query` is not `async`),
  the erased-default case excepted; the options page says a computed form
  is equal when its function is, so an inline closure never reads as
  unchanged, and that the observer compares resolved values before touching
  a timer (third review). The binding README's `app(client, …)` was already
  gone — #42 rewrote that section. Not done, on purpose: the deep-dive's
  "effective period = interval + fetch duration" for `RefetchInterval.every`
  — the timer is `Timer.periodic`, the correction would be wrong. C42: the
  `AppFocusManager` doc said the binding installs a `setEventListener`
  adapter; it calls `setFocused` directly — reworded like
  `OnlineManager`'s. C46: the showcase README names
  `backend_contract_test.dart`'s `Stopwatch` as the one exception to "no
  clock in any assertion" and why. Doc only; no regression.

- **C40 — the task manager removed a task's detail entry after a *refused*
  delete** (deep-dive 3.27; #45). `deleteTaskMutation.onSettled` called
  `removeQueries` on `TaskKeys.detail(id)` whether or not the server agreed,
  so a rejected delete rolled the row back into the list and dropped the
  entry the detail screen behind it renders from. Moved to `onSuccess`; the
  list invalidation stays in `onSettled`. Behaviour change in the demo, not
  the library. Regression: `examples/task_manager/test/acceptance_test.dart`'s
  `a refused delete keeps the per-task entry` — it reads the cache's
  `QueryRemoved` events, because the list refetch that follows any settled
  delete re-seeds every entry and would mask the removal; against the old
  code it fails with the detail key in the removed list.

- **C39 — the showcase's catalogue had gaps: fourteen public members with no
  screen and no knob** (deep-dive 3.26, architecture review; #46). Re-measured
  first against the surface the API-shape ticket (#43) left, by `grep` over
  `examples/showcase/lib/`: two of the list are moot — `RetryDelay.custom` is
  `RetryDelay.dynamic` now (C23.11) and `queryWidgetTest` is no export any
  more (ADR-0002, `541ab44`), so it cannot be "used by no example test" —
  and every other member still exists and still had zero hits. Each got a
  knob on the screen it is a variant of, with one widget test and one
  end-to-end test, or, where no screen fit, a screen: `RetryPolicy.always`
  and `RetryDelay.dynamic` are segments of the `retry` screen's two knobs (a
  404 waits four seconds, anything else 200 ms, so the delay is provably
  computed from the error); `refetchOnReconnect` is an `On reconnect` knob on
  `offline`, whose two segmented buttons now sit in named semantics groups
  because both have an `always`; `QueryClientProvider.create`, `isAppShown`,
  `initialOnlineStatus` and `maybeOf` all live on `focus-refetch`'s entry C,
  which now runs under `QueryClientProvider.create` (the provider builds,
  owns and clears the client; a new key is a new client — which retired the
  screen's hand-rolled clear-after-the-frame dance), with an `Inactive is`
  knob (`platform` / `shown` / `hidden`), an `Initial online status` knob, an
  `Entry C online` switch and `nearest=` facts at both levels;
  `InfinitePageContext.direction` is the `lastPage=<cursor> <direction>` fact
  on `max-pages` (`forward` for the first page, `Load next` and every page of
  a refetch, `backward` for `Load previous`); `getInfiniteQueryData` is what
  `load-more`'s About view reads its `cached pages=` from, with no observer;
  `client.infiniteQuery` is a fourth card on `prefetching` (the first page,
  held by nobody, a second press a no-op); `watchInfiniteQuery`,
  `context.infiniteQuery`, `client.observeInfinite` and
  `InfiniteQueryListener` are `four-call-styles`' eighth card, and
  `MutationListener` its seventh card's third panel over a
  `MutationController`; `NotifyManager.shared` is the `Drop two posts,
  batched` button on the same screen's listener card — the app's client and
  the widget-test harness's are now built on the shared manager, and the
  batched pair reaches the listener as one transition to the second value
  where the plain pair is two, which is C19's promise made visible;
  `QueriesController` is `query-collections`' `Summary reader` switch, a
  second collection over the same ids (`observers=2` per entry, `setQueries`
  following the buttons); and `QueryDataTypeError` with
  `MissingMutationFunctionError` got the one new screen, `diagnostics` (four
  widget tests, four end-to-end specs, its own strip, no backend scenario:
  the counter route serves it, so the contract test is unchanged). Two
  things the work turned up beyond the list: Flutter web maps a `blur`
  dispatched on the window to `AppLifecycleState.inactive` and a `focus` to
  `resumed`, so headless Chromium *can* stage a lifecycle transition — the
  `isAppShown` end-to-end test uses one, and the focus screen's "reports no
  transition" wording is softened accordingly; and `InfiniteData.flatten<T>`
  on a raw cache read throws C20's `ArgumentError` when the pages are not
  iterables, which the About view and the prefetch card hit before counting
  `page.items` instead — the guard did its job. Catalogue: 27 screens, 217
  widget tests (183 `showcaseTest`s plus the 17 fake-side contract cases, the
  figure the docs count), 163 end-to-end specs.

- **C44 — the showcase's one flaky end-to-end test was a Playwright
  strict-mode double match, not the SnackBar's duration** (release R14
  confirmed; the deep-dive's "30 s SnackBar" explanation refuted; #46).
  `global_callbacks.spec.ts` asserted the toast with a bare
  `page.getByText('Post not found', { exact: true })`, and the evidence log
  (`e2e-showcase.log:165–177`) shows it resolving to *two* elements: the
  SnackBar's node in Flutter's semantics tree (`<span>` under
  `flt-semantic-node-74`) and a `<div>Post not found </div>`. Reproduced by
  walking the DOM right after the click: a `SnackBar` is a `liveRegion`, and
  Flutter web announces a live region a second time by copying its text into
  `<flt-announcement-polite aria-live="polite">` under
  `<flt-announcement-host>` — outside the semantics tree — and removing the
  copy a few hundred milliseconds later. Whether the locator sees one node or
  two therefore depends on when the assertion runs against the frame that
  showed the toast, which is the whole flake; the SnackBar's 30 s duration
  plays no part (the deep-dive's guess) and stays as it is. Fixed by scoping
  the locator to the semantics host — `snackBar(page, text)` in the showcase's
  `tests/fixtures.ts`, `page.locator('flt-semantics-host').getByText(text,
  { exact: true })` — never `.first()`, which would hide the same race behind
  whichever copy the DOM listed first. The helper decision, which is the
  map's "Shared Playwright helpers" fog entry: the shape occurs once (the
  task manager shows no SnackBar and no other live region), so it is one
  helper in the one suite's fixtures, next to `strip`, `fact` and
  `holdRequest`, plus a rule in the showcase README's "Writing a screen" list;
  nothing is shared *across* the two suites, which are separate npm projects
  with no repeated shape between them. Verified: the spec six times over
  (24/24), the whole suite 146/146 on that build.

**Checked and not valid — §9 of the consolidated list.** Each of these was
looked at once, on the record, and is closed; none is to be reinvestigated:

- `maxPages` lowered on a query holding more pages must trim to the new limit
  at once (release R10) — the port is upstream's arithmetic, one page per
  directional fetch; a doc sentence (C43).
- `QueryListener` must see every transition inside a `batch` (release R9) — a
  `ValueListenable` carries no history, and a batch is the request to
  coalesce; a doc sentence (C19).
- the showcase's end-to-end flake is the SnackBar's 30 s duration (deep-dive
  §5) — the evidence log shows a Playwright strict-mode double match on the
  live region's announcement copy (C44).
- the `testing.dart` dartdoc's `GcTime.never` example does not compile
  (deep-dive 3.14) — no such snippet was there; folded into C22, itself moot.
- `RefetchInterval.every`'s effective period is the interval plus the fetch
  duration (deep-dive 3.25) — the timer is `Timer.periodic`; the proposed
  correction would have been wrong.
- an unchecked cache downcast at `query.dart:710–717` (architecture A11) — it
  is an options cast; `client.queryCache` is already a `QueryCache`.
- the reviews' own miscounts (A11, A4, the design pass) — `MutationCacheRef`
  has ten members, not nine; sixteen widget-test files use the group finder,
  not twenty-five; the duplicated lines are some 94–105, not 120–130. The
  findings behind the numbers (C54, C56, C47) stand, for the next map.
- `invalid_return_type_for_then` in `query_test.dart` (release R17) — no
  diagnostic on Dart 3.10.7; carried as plausible (C29), not reproduced.
- the deep-dive's own not-reproduced items — a silent drop in the notify
  scheduler, leaks after a provider unmount, `QueryKey([double.nan])`, the
  `_reject`/`_resolve` order, `cancelQueries(revert: false)` beside a
  synchronous `query` (O1), R5 over a real refetch — checked by the deep-dive
  itself and either not reproduced or upstream-identical; O1 was confirmed
  upstream-identical here once more.
- R12, the formatter gate — fixed in `9ac9010`, before the map.

The round in numbers: C1–C46 landed, of which seventeen changed the library's
behaviour (C1, C3–C10, C12–C14, C16–C18, C20, C23) and three its surface or
dependency graph (C2, C21, C24); two could not be reproduced (C15, and C29 as
plausible on a later SDK); two were moot by the time their ticket ran (C22,
C45); one moved the demo (C40), two the showcase (C39, C44); C11 kept the
core's rule and moved the teardown; the rest moved documentation or the
release tooling. C47–C59, the structural findings, are out of this map's
scope and the seed of the next one.

## Structural work after the ninth review (C47–C59)

The thirteen structural findings of the 2026-09-10 reviews are worked off by
[map #49](https://github.com/KoTTi97/flutter_query/issues/49), one ticket at a
time, and this is where each landing ticket writes its row: **what moved, what
it replaced, and what proves the behaviour did not change.** None of these
findings is a bug — they are duplicates, unused seams and surfaces whose
sameness is unargued — so the entry to look for is not a regression test but
the suite that was already covering the code and stayed green *unrewritten*.
Where a ticket re-measured the finding and the numbers had drifted, the row
says what was actually counted; where the right answer turned out to be "two
things that merely look alike", the row says that too, because a refusal to
extract is a resolution and the next reader should not re-open it.

### C55 — the showcase's copied cache listener ([#50](https://github.com/KoTTi97/flutter_query/issues/50))

**Measured**, not taken from §8: the phase-aware rebuild is **12 sites in 11
files**, of which **11 are md5-identical** 18-line `_rebuild()` bodies (10
feature screens plus `lib/shared/debug_strip.dart`; `focus_refetch` has two)
and one is `cancellation`'s `_bumpDuringAnyPhase`, the same dance without the
coalescing flag. Two of the eleven are not just an identical method but an
identical *widget*: `_OnCacheEvent`, copied whole between `basic` and
`prefetching`. Beside them: `_Toolbar` ×4 (all identical, §8 said ×3),
`_Action` ×6 (four identical, §8 said ×5, plus two variants), `_knob<T>` ×4
(three identical + one variant, exactly as §8 said), `_mono` ×5 (four at
`fontSize: 13`, one at 12) and `_clock` ×5 (three identical, two nullable
variants whose null word differs and is asserted on).

**What moved.** Two new modules under `examples/showcase/lib/shared/`:

- `cache_listener.dart` — `mixin PhaseSafeRebuild<T> on State<T>` with
  `scheduleRebuild()`, now the single copy of the dance for all twelve sites;
  and `CacheListener`, the builder widget that adds the `CacheStats`
  subscription, replacing both copies of `_OnCacheEvent`. `QueryDebugStrip` —
  which both test layers read — went onto it and became a `StatelessWidget`
  wrapping a `CacheListener`.
- `controls.dart` — `Toolbar`, `ActionButton` (the four identical copies, with
  `filled` and `dense` reproducing the two variants exactly), `knobButton` and
  `knob`, `monoStyle`/`monoStyleSmall`, and `hhmmss`.

**What was deliberately left.** `playground`'s knob: its four knobs are cells
of a `Wrap`, so it must shrink-wrap and cannot carry the shared `knob`'s
sideways scroller, which would be unbounded there. It composes the identical
part, `knobButton`, and its dartdoc says why — the flag that would have made
one function serve both layouts is the shared abstraction that fits neither
caller. The two nullable clock formatters keep their own null word (`never`,
`–`) over the shared `hhmmss`, because a test asserts on each.

**What proves the behaviour did not change.** The showcase's 217 widget tests
and 163 Playwright end-to-end specs, both green and **both untouched** — the
commit changes no file under `test/` or `e2e/`. That is the point of running
the end-to-end leg here rather than reasoning about it: the extraction moves
`Semantics` containers, `Tooltip(excludeFromSemantics:)` and `SegmentedButton`
keys, which is exactly the tree the browser suite reads. Net −892/+238 lines
across sixteen feature screens, plus ~250 lines of shared module.
`examples/showcase/README.md` gained the rule the move implies: `lib/shared/`
is the deliberate exception to "one self-contained directory per feature", and
the third copy moves.

## Deliberate divergences that will show up in later suites

These are decided, not accidental; each is listed here so a reader of a ported
suite does not have to go looking:

| Upstream behaviour | Here | Decided in |
|---|---|---|
| `data === undefined` runtime guard in `Query.fetch` | impossible: `Future<T>` with non-nullable `T` | [#7](https://github.com/KoTTi97/flutter_query/issues/7) |
| `hashKey` string identity, `queryKeyHashFn` | `QueryKey` is a value type; the string is a debug view | [#8](https://github.com/KoTTi97/flutter_query/issues/8) |
| `replaceEqualDeep` structural sharing | `replaceEqualDeep` by default: lists (and `InfiniteData`'s two) element by element, maps and sets whole, `==` otherwise; the typed hook replaces it for the cache write, and `(_, next) => next` is `false`; `select` and placeholder output always go through `replaceEqualDeep` | [#12](https://github.com/KoTTi97/flutter_query/issues/12), review 2026-09-09 |
| `trackResult`, `notifyOnChangeProps` | dropped; `select` plus the binding's `buildWhen` | [#15](https://github.com/KoTTi97/flutter_query/issues/15) |
| `throwOnError` | dropped; errors live in the sealed result | [#15](https://github.com/KoTTi97/flutter_query/issues/15) |
| `MutationFunctionContext` (a mutation function's second argument) | not ported: `MutationFn` takes variables only |  [#14](https://github.com/KoTTi97/flutter_query/issues/14) |
| `skipToken` | `Enabled.no` | [#17](https://github.com/KoTTi97/flutter_query/issues/17) |
| a `Set` of listeners in `Subscribable` | a `List`: Dart tear-offs are `==`, so a Set let one subscriber's unsubscribe silence another's | eighth review 2026-09-10 |
| module-level managers | instances the `QueryClient` owns — the `NotifyManager` too since the third review (`NotifyManager.shared` opts back in) | [#19](https://github.com/KoTTi97/flutter_query/issues/19), review 2026-09-09 |
| `staleTime: Infinity` | `StaleTime.infinite` (never stale, still refetchable), distinct from `StaleTime.static` | [#10](https://github.com/KoTTi97/flutter_query/issues/10) |
| `persister` | not ported | [#15](https://github.com/KoTTi97/flutter_query/issues/15) |
| `initialDataUpdatedAt` as a function | additive `initialDataUpdatedAtCompute`, exclusive with the existing timestamp value | functional improvements plan |
| `hasNextPage` / `fetchNextPage` on the query result | on `InfiniteQueryObserver`; the sealed result stays one shape | [#16](https://github.com/KoTTi97/flutter_query/issues/16) |
| an infinite query's `queryFn` returning one page | `pageFn`, with its own typed `InfinitePageContext` | [#16](https://github.com/KoTTi97/flutter_query/issues/16) |
| a blind cast in `getQueryData` | a type mismatch throws `QueryDataTypeError` — and a *subtype* is a mismatch: one key, one exact type | [#7](https://github.com/KoTTi97/flutter_query/issues/7), fourth review 2026-09-09 |
| one observer options object with an optional `select` | two shapes over a sealed base: `QueryObserverOptions<TData>` without `select`, `QuerySelectOptions<TQueryData, TData>` with `select` required (infinite: `InfiniteQueryObserverOptions` / `InfiniteQuerySelectOptions`); the binding's controllers refuse a top-typed `TData` in debug builds only — the backstop is compiled out of release | [ADR-0001](../../../docs/adr/0001-one-type-slot-for-plain-queries.md), ninth review 2026-09-11 |

### A `Set` of listeners does not port

`subscribable.ts` keeps `listeners` in a `Set`, and one ported case —
"should deduplicate the same listener reference" — pins that: subscribing the
same function three times and unsubscribing once leaves nothing.

In JavaScript that is nearly unobservable, because two function objects are
never equal; the `Set` is an insertion-ordered list that merely cannot hold
one closure twice. In Dart a tear-off of a method on an object is `==` to
itself, so `cache.subscribe(logger.onEvent)` called from two unrelated places
produced **one** registration — and the first unsubscribe took the other
subscriber's listener with it. The port keeps a `List`: one entry per
`subscribe`, each returned handle removing its own, and a handle called twice
removing nothing more. The ported case is renamed "registers the same listener
reference once per subscribe" and asserts the port's answer, with two
port-specific cases beside it (eighth review, 2026-09-10).
| `MutationCache.remove` leaves the mutation's gc timer running | the timer is cancelled, so a removed mutation cannot ask to be removed again | [#22](https://github.com/KoTTi97/flutter_query/issues/22) |
| a cancelled retry can still flip its query from `idle` to `paused` after its delay | the retryer checks `isResolved` after the delay | review, 2026-09-08 |
| a removed query or mutation re-arms its own gc timer from the fetch's `finally` | removal marks it, and a marked one schedules nothing | [#24](https://github.com/KoTTi97/flutter_query/issues/24) |
| `fetchQuery` / `prefetchQuery` / `ensureQueryData` (all deprecated upstream at this pin) | one `QueryClient.query`; prefetch is `.ignore()`, ensure is `staleTime: StaleTime.static`, stale-while-revalidate is `revalidateIfStale: true` | [#17](https://github.com/KoTTi97/flutter_query/issues/17), functional improvements plan |
| `query`'s `select` type slot | none: `await` the future and map it | [#7](https://github.com/KoTTi97/flutter_query/issues/7) |
| a `select` that threw keeps reporting its error after `select` is removed | the error goes with the selector; the raw data is reported | review, 2026-09-09 |
| a retained placeholder keeps its old selection after `select` changed | the new `select` runs over the placeholder | review, 2026-09-09 |
| an observer resubscribing after its query was collected rejoins the dead query | it re-resolves the key and joins the current entry (one adapted assertion in `query_test.dart`) | review, 2026-09-09 |
| `initialData: null` / `placeholderData: null` mean "none" | `.value(null)` is a value of `null`; `.compute` returning `null` means "none" | review, 2026-09-09 |
| a throwing `retry` / `retryDelay` callback leaves the fetch pending forever | the throw is the fetch's error | third review, 2026-09-09 |
| a retry backoff runs to its end after the fetch was cancelled | the delay is a timer the retryer drops on resolve | third review, 2026-09-09 |
| a mutation removed from the cache keeps retrying; a paused one is abandoned for good (its callbacks never run, its promise never settles) | `Mutation.destroy` stops the retries; the mutation fails with its last error (from a backoff) or a `CancelledError` (from a pause), and failing runs its error callbacks a few microtasks after the removal — so `clear()` is followed by a dropped optimistic mutation's rollback, writing into the cache it emptied (a teardown lets the callbacks run and clears again). Removed before its run began — from inside `MutationAdded` — `destroy` has no retryer to stop yet, so `execute` applies the same cancel to the one it builds | third and fourth review, 2026-09-09; ninth review, 2026-09-10 (C5, C11) |
| a throwing observer listener becomes the query's error (via `Query.fetch`) | reported to the zone; the query keeps its state | third review, 2026-09-09 |
| a throwing cancel callback skips the rest and escapes into the canceller; an abort listener added after the abort never fires | each is isolated and reported to the zone, on the loop path and on the already-cancelled path alike, where the callback runs at once | third review, 2026-09-09; ninth review, 2026-09-10 (C16) |
| `Query.reset()` on an unobserved query leaves it in the cache for good | it re-arms collection | third review, 2026-09-09 |
| `isRefetching`/`isRefetchError` corrected for page fetches on the infinite *result* | on `InfiniteQueryObserver` / `InfiniteQueryController`, next to the other paging flags | third review, 2026-09-09 |
| `{ pages, pageParams }` is walked by `replaceEqualDeep` as a plain object | `InfiniteData` is special-cased: each list shared on its own, the whole kept when both are | fourth review, 2026-09-09 |
| a cache listener that throws during a dispatch escapes into the retryer, and the fetch never settles | cache and mutation-observer listeners are isolated and reported to the zone; a throw reaching a retryer hook is the fetch's error | fourth review, 2026-09-09 |
| `onSubscribe` leaves the result stale after joining a running fetch (the React adapter re-reads) | refreshed on subscribe when the query's state moved on | fourth review, 2026-09-09 |
| a standing `select` error is stamped `Date.now()` on every result | stamped once, when the selector threw | fourth review, 2026-09-09 |
| `MutationResult.context` (what `onMutate` returned) | not on `MutationResult`: the rollback handle goes to `onError`/`onSettled`, and a third type parameter on the sealed result would tax every `switch` for it | A2, fourth review 2026-09-09 |
| `updateResult` diffs the next result against `#currentResult` — the last one *assigned*, which `getOptimisticResult` also assigns, so a real result equal to an optimistic read is not reported (the React adapter re-reads on render) | diffed against `_previousResult`, the last result listeners were *told*; `currentResult` still follows an optimistic read, but a result that differs from the last notification is reported even when it equals the optimistic one. A listener's baseline is what it was told, and the binding's readers swallow an equal notification by `==` | A19, fourth review 2026-09-09 |
| a fetch with no query function is retried like any failure, `retry` and backoff included | `MissingQueryFunctionError` is never retried: a configuration error, so the one attempt is the answer and the message is seen at once | A20, fourth review 2026-09-09 |
| the `fetch` action is dispatched before the retryer is installed, so a listener reacting to it finds nothing to cancel or join | the retryer is installed first: `cancelQueries` from the fetching notification stops the request, and a `client.query` of the same key from the fetch event joins it | fifth review, 2026-09-09 (44) |
| a caller joining a running fetch gets the retryer's promise; the first caller's `setData` and cache hooks run after it | every caller gets one operation future, settled after the cache write and the hooks (or the error dispatch), so all callers agree with the query's state | fifth review, 2026-09-09 (45) |
| `resumePausedMutations` is gated on `onlineManager.isOnline()` as a whole | gated per mutation, with the retryer's network rule for *continuing* (`networkMode == always \|\| isOnline()`; the start rule for a restored mutation that has no retryer yet), so an `always` mutation paused for focus or its scope resumes offline and an `offlineFirst` retry is left alone offline. A pause for focus or the scope's turn is awaited, as upstream awaits it | fifth review, 2026-09-09 (47) — replaces the "no-op while offline" wording of 4; the gate was the *start* rule until the ninth review, 2026-09-10 (C4) |
| `fetchQuery` writes `retry: 0` into the shared query's options when the caller configured none | the imperative retry rule rides on `FetchOptions.retry` for that fetch alone; the query's options keep the observer's `retry` | fifth review, 2026-09-09 (48) |
| `invalidateQueries` re-runs its filter for the refetch, so a state-dependent filter (`stale: false`, a predicate over `isInvalidated`) refetches none of what it invalidated | the match set is frozen before invalidating, like `resetQueries`; only `type` is re-evaluated | fifth review, 2026-09-09 (49) |
| a `setOptions` on a running mutation moves it to the new `scope`'s queue | the scope is fixed per run; a change while pending moves nothing | fifth review, 2026-09-09 (46) |
| `Query.fetch`'s success path schedules gc unconditionally (via the retryer's `onSuccess`) | only when no observer is attached; the leaving observer arms it | fifth review, 2026-09-09 (52) — one rule with 42 |
| `replaceEqualDeep` walks any array; a `Uint8Array` is compared by identity | `TypedData` is a leaf (`==`, never walked); every `previous` returned is first checked `is T`, a list copy likewise, else `next` — sharing is best effort and never a type error | fifth review, 2026-09-09 |
| `#updateStaleTimeout` adds 1 ms to the timeout | the stale timer rounds its duration up to whole milliseconds and, if it still runs before the deadline (truncation, or the 2^31 ms clamp), re-arms for the remainder | fifth review, 2026-09-09 |
| `hasNextPage` and friends are fields of the infinite result, compared with it | getters on `InfiniteQueryObserver` (#16); `shouldNotify` compares the direction flags at every notification and re-asks `hasNextPage`/`hasPreviousPage` only when the paging functions or the data (by identity) differ from what the last notification was answered over | #16, fifth review, 2026-09-09; ninth review, 2026-09-10 (C13) |
| a silent cancel with no successor leaves `fetchStatus: 'fetching'` for good (`cancelQueries({ silent: true })` wedges the query) | the query puts itself back to `idle` — unless the cache has dropped it, in which case it dispatches nothing after the cancel, as upstream never does | eighth review, 2026-09-10; ninth review, 2026-09-10 (C9) |
| `Mutation.continue()` with a live retryer returns the retryer's promise, which resolves before the callbacks run; `resumePausedMutations` resolves with it, and `mount()`'s reconnect refetch can overtake an `onSuccess` cache write | `continueMutation` releases the pause and hands on `execute()`'s own future, settled after the callbacks and the settled dispatch — the restored-mutation path upstream already takes | ninth review, 2026-09-10 (C10) |
| the `select` memo keeps the last selection while the selector is `===` the last one | `==`: an instance-method tear-off is `==` to the next tear-off of the same method, as the options already treat it | ninth review, 2026-09-10 (C14) |
| observer `TData` defaults to the query's type; nothing checks a mismatch | a `QueryObserver` with no `select` whose `TQueryData` is not a `TData` is refused with `ArgumentError` at construction, `setOptions` and `getOptimisticResult` | fifth review, 2026-09-09 |
| an observer's `onQueryUpdate` throwing inside a dispatch propagates into the fetch | isolated per observer and reported to the zone, like the cache listeners; the query keeps its state | fifth review, 2026-09-09 (59) |
| `useQueries` with a heterogeneous tuple and a `combine` step | a homogeneous `QueriesObserver` (`QueriesController`/`QueriesBuilder` in the binding); mixed data types need a `select`, and there is no `combine` — map the returned list | functional improvements plan, `competitor-deep-dive.md` §6 #13 |
| `useMutationState` reads the cache through a React hook | `MutationStateObserver` (`MutationStateController` in the binding): `MutationFilters` plus a required `select`, structural sharing over the outer list, subscribed only while observed | functional improvements plan, `competitor-deep-dive.md` §6 #9 |
| no minimum background duration before a focus refetch — every foreground event refetches | `AppFocusManager(refetchMinBackgroundDuration:)`, default `Duration.zero` (upstream's behaviour); a shorter absence suppresses **new** focus refetches only, paused work still resumes | functional improvements plan, `competitor-deep-dive.md` §6 #3 |
| `keepPreviousData` / `placeholderData: (prev) => prev` | `const PlaceholderData.keepPrevious()` — identical to `.compute((previous, _) => previous)` including its "a previous `null` means no placeholder" rule, but `const`, so it survives the observer's placeholder memoisation | functional improvements plan, `competitor-deep-dive.md` §6 #4 |
| the binding: a provider always borrows its client | `QueryClientProvider.create` owns the client it builds and `clear()`s it once, after the inner provider unmounted; the `client:` form still borrows and never clears | functional improvements plan, `competitor-deep-dive.md` §6 #7 |
| the binding: side effects need a builder that also rebuilds | `QueryListener` / `InfiniteQueryListener` / `MutationListener` borrow a controller, deliver each accepted transition off the build phase and never rebuild their `child`; a rejected `listenWhen` still advances the comparison state | functional improvements plan, `competitor-deep-dive.md` §6 #8 |
| `mutate(variables, { onSuccess, onError, onSettled })` on the result: per-call callbacks ride on the result's own `mutate` | `MutationResult.mutate` takes the variables only; per-call callbacks are `MutationObserver.mutate(variables, MutateCallbacks(…))` — `MutationController.mutate(variables, callbacks)` in the binding | ninth review, 2026-09-10 (C23.8) |
| `mutate` on a forgotten `useMutation` observer re-attaches it to the new mutation, which is then never collected | the binding: `mutate`/`mutateAsync` on a disposed `MutationController` run the mutation through the cache without attaching anything — the options' callbacks run, the per-call ones are dropped as for any unlistened run, `value` stays idle, and the settled mutation is collected after its `gcTime` | ninth review, 2026-09-10 (C18) |

### C52 — option-field transcription: explored, kept ([#62](https://github.com/KoTTi97/flutter_query/issues/62))

**Measured**, and higher than §8 said: `refetchIntervalInBackground` is **42**
lines in `lib/` (§8: 27), `initialDataUpdatedAtCompute` **52** (§8: 36),
`staleTime` 77. The reason the numbers grew is a decision, not a regression —
ADR-0001 split the observer options into a plain and a select shape over a
sealed base, and mirrored it on the infinite side, which raised the class count
the transcription multiplies against. One observer-level field costs ~40 lines
across four files, in eight roles (the list is now in `CLAUDE.md`'s
conventions, because the cost being *invisible* is the real problem: a missed
`==` entry is a rebuild that never happens).

**Kept.** Composition (`options.core.staleTime`) makes every read site in the
core, the binding, both examples and every doc sample worse to shorten one
declaration; dropping the option classes' `copyWith` would save ~390 of the
2 100 lines of the two files and is used by nothing but tests, but `copyWith`
on a value class is what a Flutter user reaches for and public API is not
deleted to shorten a file nobody reads; a map-backed object loses `const`,
`==` and the analyzer; code generation needs a package neither published
package may require, and Dart's macros were cancelled. Nothing changed in
`lib/` but one dartdoc.

**The one construct §8 called waste is not waste.**
`DefaultedQueryObserverOptions.queryOptions` does not "strip nine fields off
again" — it is a **projection to the fourteen fields a `Query` runs on**, and
it is load-bearing: `Query.setOptions` compares by value, so handing a query
the observer's full options would make two observers differing only in
`select` or their refetch triggers look like two different query
configurations and churn the query they share. Its dartdoc now says so, because
it has been read as dead weight once and will be again.

**What proves nothing changed:** `dart test` 586, unchanged and unrewritten —
the edit is one dartdoc.

### C54 — the `*Ref` seams, and `Query`'s two ways to the cache ([#64](https://github.com/KoTTi97/flutter_query/issues/64), [#65](https://github.com/KoTTi97/flutter_query/issues/65))

**The seams stay.** The row is not an unearned abstraction, it is one
**incomplete interface**, and its twin proves it: `MutationCacheRef` has ten
members (§8 is right, not nine) including `onMutationObserverAdded` /
`onMutationObserverRemoved`, and `Mutation` therefore needs no second
reference to its cache. `QueryCacheRef` had four, was missing exactly that
pair, and `Query` reached through `client.queryCache` for exactly those two
calls (`query.dart:645`, `:677`) while sending state, removal and fetch events
to `_cache`. Same design, one side unfinished.

**What moved.** `QueryCacheRef` gains `onQueryObserverAdded` and
`onQueryObserverRemoved`; `QueryCache`'s `notifyObserverAdded` /
`notifyObserverRemoved` are those members now (renamed, `@internal` and
`@override` like their neighbours — they were `@internal`, so no public
surface changes); `Query` names `_cache` for all six and `client.queryCache`
nowhere. `client` stays: it is still how a query reaches
`defaultQueryOptions`, `focusManager`, `onlineManager`, `notifyManager` and
`client.query`, and none of those is a cache.

**Why it is a bug and not a tidy-up.** The two references are the same object
on every path the port takes — the ported `should be able to limit cache size`
(`query_cache_test.dart:141`) builds a `QueryCache()` and *then* hands it to
the client, which keeps them equal — but `QueryCache.build` is public, so
`otherCache.build(client, options)` is expressible and would have split one
query's events across two caches: its state to the cache that built it, its
observers to the client's. Nothing would have noticed.

**Refuted, and recorded so nobody re-finds it:** the "unchecked downcast" at
`query.dart:710-717` casts *options*, not a cache.

**What proves the behaviour did not change:** `dart test` 586 → 587, the one
new case being the regression `C54 a query built by a foreign cache sends its
observer events there too, not to its client's cache` in
`port_specifics_test.dart` — red before the change with
`Actual: WhereTypeIterable<QueryObserverAdded>:[]`, green after. No ported case
was touched, and the binding's 98 and the showcase's 217 are unchanged.

### C53 — where the staleness decision lives ([#63](https://github.com/KoTTi97/flutter_query/issues/63))

**What moved, and nothing else.** The five refetch rules were free functions
over `Query<Object?>` at the end of `query_observer.dart` — `_isStale`,
`_shouldLoadOnMount`, `_shouldFetchOnMount`, `_shouldFetchOn`,
`_shouldFetchOptionally` — each taking the options as a second argument. They
are now a private extension `_RefetchRules` on
`DefaultedQueryObserverOptions`, because that is whose rules they are: the
query supplies the state, the options supply `enabled`, `staleTime` and the
three `refetchOn*` fields. Every call site reads `options.<rule>(query)`, and
the two `QueryObserverRef` members that used to spell out
`_shouldFetchOn(_currentQuery, _options, _options.refetchOnWindowFocus)` are
now `_options.shouldFetchOnWindowFocus(_currentQuery)` — one name where there
were two levels.

**The "round trip" is four different questions, not one asked four times**,
and the extension's dartdoc says which is which: `Query.isStale()` (the
query's view — it asks its observers, or applies the unobserved rule),
`currentResultIsStale` (one observer's **cached** answer, which is why there
is no runtime cycle), `isStaleFor` (the rule that produced that field) and
`Query.isStaleByTime` (the time half, where `StaleTime.static` outranks an
invalidation and `StaleTime.infinite` does not). `Query.isStale()` now points
at that block, since a reader arriving there is one step into the chain.

**The three public names §8 required to survive did:** `Query.isStale()`,
`Query.isStaleByTime`, `QueryFilters.stale`. Nothing else about the module is
public.

**What proves the behaviour did not change:** `dart test` 587, unchanged and
unrewritten — including the 62 ported `queryObserver` cases, which cover these
rules more densely than anything else in the port. The change is a move and a
rename of private members; no call gained or lost a condition.

### C47 — the reader registry, once instead of twice ([#56](https://github.com/KoTTi97/flutter_query/issues/56))

**Measured.** §8 already corrected itself once here — the deep-dive's
"120/130 shared lines" became "~94 shared, ~105 in the four parallel blocks" —
and the re-measurement lands between the two. Counting *code* lines (comments
and blanks dropped) across the five parallel regions, normalising only the
three names that genuinely differ (the `state.` receiver, `_currentClient` vs
`client`, `'This State'` vs `'This widget'`): **122 lines on the mixin side,
131 on the context side, 110 of them identical** — the entry class 18, the
query read 18, the infinite read 26, the mutation read 39, `_entryFor` 9. So
§8's "~105 in the four parallel blocks" was right (101 by this count, 110 with
`_entryFor`) and its "~94 shared" was the low one. The cross-reference the
mixin carried was indeed at `query_mixin.dart:85-86`.

**What moved.** One new module, `packages/query_kit_flutter/lib/src/read_set.dart`:
`ReadSet`, the reads one reader holds. It owns the entry class, the three
identity tuples, `_entryFor`, the generation rotation (`beginBuild`), the
release (`sweep`, `releaseAll`), `debugCheckRepeatRead`'s call sites and the
mutation-ambiguity assertion. Its interface is seven members, and the two
things the callers actually differ in are its two constructor arguments:
`rebuild` (a `State`'s `setState`, an `Element`'s `markNeedsBuild`) and `who`
(the name in the two debug messages). `QueryMixin` holds one `ReadSet`;
`QueryScopeElement` holds a `Map<Element, ReadSet>` and exposes `readsFor`,
which replaced its three generic forwarders — `context.query` and its two
siblings now read through the set directly. 491 code lines became 389.

**What was deliberately left.** Three things, and the first is the interesting
one:

- **`detached` did not generalise, and it did not have to.** It is a fact
  about *which readers are still here* — a question only something holding
  many read sets can ask, and a `State` gets no such signal at all. It stayed
  on `QueryScopeElement`, now as `Set<Element> _detached` rather than a field
  on a per-reader wrapper, which made the asymmetry visible instead of
  looking like a field one caller forgot to use. `_Reader` is gone entirely.
- **Scheduling the post-frame sweep** stays on each owner (~9 lines each):
  `ReadSet.sweep()` releases, but *when* it runs differs — one set behind a
  `mounted` check versus every reader's plus dropping the ones that left. A
  `FrameSweeper` holding a flag and a callback would have been a shallow
  module; deleting it would make nine trivial lines reappear, not complexity.
- **The client** is a parameter of each read, not a field: the mixin re-reads
  an overridable `queryClient` on every read (third review, 2026-09-10), the
  scope takes its `InheritedWidget`'s.

**Coverage came first.** The binding has no ported suite, so three regions of
the registry were reached by nothing before they could be moved: the mixin's
mutation-ambiguity assertion and its `debugCheckRepeatRead` (only
`context`'s were exercised, by `M7`), and the `(#infinite, …, id)` identity
tuple, which nothing in either package or either example read. Six cases —
`C47 the registry regions the suite did not reach` in
`query_kit_flutter/test/review_regressions_test.dart` — were written and run
**green against the two copies first**, so they say the extraction changed
nothing rather than describing the extraction. Two of them were checked
against a deliberately broken mixin (identity tuple flattened, assertion
disabled) and failed, so they bite.

**What proves the behaviour did not change:** the binding's 98 widget tests,
the showcase's 217 and the task manager's 16, all green and **none rewritten**
— the commit touches no existing test, only appends the six new ones. The core
is untouched (587).

**What #58 does here.** `buildWhen:` on the two keyless reads goes on
`_Entry._onChanged` in this module — one further condition on the branch that
already asks "did `observedStateOf` move?", passed down through
`ReadSet.readQuery` / `readInfiniteQuery` and stored on the entry beside
`built` and `builtState`. Written once now, for both call styles; the comment
marking the spot is in the code. The rebuild-decision copies in
`query_builder.dart` are [#57](https://github.com/KoTTi97/flutter_query/issues/57)
and were not touched.

### C48, C59 — the rebuild decision, once instead of six times ([#57](https://github.com/KoTTi97/flutter_query/issues/57))

**Measured** on `78ad692`, after [#56](https://github.com/KoTTi97/flutter_query/issues/56)
had already turned two of C48's three sites into one. §8's line numbers had
drifted; the ticket's restatement had not. The `_built` / `_builtState` /
`_record()` trio is at `query_builder.dart:83-94`, `:197-208`, `:323-334` and
`:429-440`, each with a `shouldRebuild()` override at `:112-114`, `:228-230`,
`:336-338` and `:442-444` calling the shared compare at `:120-149` (its
`observedStateOf` test on `:137`). Counting *code* lines: the trio is **6 lines
× 4 copies, four of the six byte-identical across all four and all six
identical once the result type name is normalised**; the override is **3 lines
× 4, byte-identical in all four** — 36 lines saying one thing. Beside them,
`explicitClient` / `clientChanged` / `optionsChanged` are another **36 lines
across the four** that say `widget.client`, `old.client != widget.client` and
`old.options != widget.options` and nothing else. C59 is exact: with the state
name, the widget type and the controller type substituted,
`_QueryBuilderState` and `_QuerySelectBuilderState` differ **in one line
wrap** and in nothing else.

**One claim of the ticket did not survive the measurement.** "Two of the four
call `_record()` from `build`, the other two from a notification" is not so:
all four record in `build` and all four decide in the notification. What
differs is what `build` does with the recorded value — two hand it to the
`builder`, two hand over the controller and drop it — which is a line of each
`build`, not a difference in the decision. The keyless entry is the same
shape (`read` from a build, `_onChanged` from a notification). That uniformity
is why one class fits all five readers.

**What moved.** One new module,
`packages/query_kit_flutter/lib/src/read_entry.dart`: `ReadEntry<T>`, *one
controller a reader watches and what its last build read from it* — four
members (`controller`, `read`, `dispose`, the `rebuild` callback), and behind
them the listener registration, `built`/`builtState`/`buildWhen`, the decision
and the disposal. `ReadSet`'s `_Entry` **is** it now (`typedef _Entry =
ReadEntry<Object?>`, its only remaining trace in that file), and
`_ControllerBuilderState` watches its one controller through it. The decision
each side had written separately turned out to be the same decision: with no
predicate, the builders' four-branch `_shouldRebuild` reduces to the entry's
one-line `observedStateOf(controller) != builtState`, so the merged version is
the builders' and the keyless readers are unchanged by construction.

Two private mixins on the widget side carry the rest: `_BuilderWidget<T>`
(`options`, `buildWhen`, `client`) and `_QueryBuilderWidget<TQueryData, TData>`
(the options narrowed, plus `builder`). Mixins rather than a shared superclass
because a superclass would have to *hold* the fields and would widen
`QueryBuilder.options` to a base type and `MutationBuilder.options` to
`Object`; abstract getters let every widget keep its own field types, so the
public surface is byte-for-byte what it was. `_ControllerBuilderState` gained
the value type and lost four of its six abstract members — a subclass now says
only `createController`, `applyOptions` and what its `build` does with
`record()`. `_QuerySelectBuilderState` is gone: both query builders are
`_QueryBuilderState<W, TQueryData, TData>`, which is what keeps each
`createState`'s return type its own widget's.

Across the three files: **443 code lines became 397**, with the four state
classes falling from 133 to 51 and `read_set.dart` from 157 to 137. The
typedef `BuildWhen` moved to the new module and is re-exported from
`query_builder.dart`, so the barrel's public surface is unchanged.

**What was deliberately left.** `QueriesBuilder` keeps its own state class and
rebuilds on every notification: its value is a `List<QueryResult>`, which has
no value equality, so the decision would never fire, and it takes no
`buildWhen` (a list of queries has no one result to filter on). Bringing it in
would have meant a fifth shape and a branch for it.

**Coverage came first.** Probing the four copies — the equality branch
disabled, then the predicate ignored — named exactly which of them the suite
was counting: the equality branch by `B3` (`QueryBuilder`) and by
`buildWhen on every builder` (the infinite one); the predicate by that same
case (infinite and mutation). **`QuerySelectBuilder`'s copy was reached by
nothing at all, and `buildWhen` was reached on neither plain-query builder.**
The existing `buildWhen` case passes with the predicate disabled and its
comment says why it should not: a disabled query with `StaleTime.infinite`
invalidated with `RefetchType.none` does not move its result, so the equality
above answers first and the predicate is never asked. A refetch returning the
same data is what moves the result (`dataUpdatedAt`) and leaves the data
alone. Three cases — `C48 the rebuild decision in the builders the suite did
not count` in `query_kit_flutter/test/review_regressions_test.dart` — were
written and run **green against the four copies first**, then each was checked
against the branch it names, disabled: all three failed, so they bite.

**What proves the behaviour did not change:** the binding's 104 widget tests
(107 with the three new ones), the showcase's 217, the task manager's 16 and
the doc snippets' 2, all green and **none rewritten** — the commit touches no
existing test, only appends. `dart doc` is 0 warnings, 0 errors, and the
generated page for every builder shows the same inheritance it did (dartdoc
elides the private mixins). The core is untouched (587).

**What #58 does here.** Nothing new: `buildWhen:` for the two keyless reads is
`ReadEntry.read`'s existing named argument, threaded through `ReadSet`'s three
`read*` methods. The predicate, the equality that answers before it and the
paging-flags exception are now one implementation for all four call styles, so
#58 writes the wiring rather than the decision.
