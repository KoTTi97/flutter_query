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

Suites not ported at all, each for one recorded reason:
`hydration.test.tsx` (hydration is out of v1 scope, #17),
`timeoutManager.test.tsx` (the module is not ported, #9),
`environmentManager.test.tsx` (no SSR),
`streamedQuery.test.tsx` (experimental upstream; the Dart `Stream` mapping is
fog).

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
15. **A throwing `RetryPolicy.when` or `RetryDelay.custom` hung the fetch
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
- **A10 — done.** `QueryCache.build(state: …)` asserts that a `success` state
  carries data, naming the persistence door in the message.
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
    `MutationCache.resumePaused`: `canFetch(networkMode, onlineManager)`, the
    same test the retryer applies. An `online` mutation is still left alone
    offline, so `mount`'s listeners cannot hang on it. Upstream has the
    *global* gate in `QueryClient.resumePausedMutations` (its per-mutation
    `canContinue` is in the retryer, which only runs once resumed), so this
    is a divergence rather than a port bug; the table's row from 4 is
    corrected.
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
| a mutation removed from the cache keeps retrying | `Mutation.destroy` stops the retries; the mutation fails with its last error (from a backoff) or a `CancelledError` (from a pause) | third and fourth review, 2026-09-09 |
| a throwing observer listener becomes the query's error (via `Query.fetch`) | reported to the zone; the query keeps its state | third review, 2026-09-09 |
| a throwing cancel callback skips the rest and escapes into the canceller | each is isolated and reported to the zone | third review, 2026-09-09 |
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
| `resumePausedMutations` is gated on `onlineManager.isOnline()` as a whole | gated per mutation, with the retryer's own rule (`networkMode != online \|\| isOnline()`), so an `always` mutation paused for focus or its scope resumes offline | fifth review, 2026-09-09 (47) — replaces the "no-op while offline" wording of 4 |
| `fetchQuery` writes `retry: 0` into the shared query's options when the caller configured none | the imperative retry rule rides on `FetchOptions.retry` for that fetch alone; the query's options keep the observer's `retry` | fifth review, 2026-09-09 (48) |
| `invalidateQueries` re-runs its filter for the refetch, so a state-dependent filter (`stale: false`, a predicate over `isInvalidated`) refetches none of what it invalidated | the match set is frozen before invalidating, like `resetQueries`; only `type` is re-evaluated | fifth review, 2026-09-09 (49) |
| a `setOptions` on a running mutation moves it to the new `scope`'s queue | the scope is fixed per run; a change while pending moves nothing | fifth review, 2026-09-09 (46) |
| `Query.fetch`'s success path schedules gc unconditionally (via the retryer's `onSuccess`) | only when no observer is attached; the leaving observer arms it | fifth review, 2026-09-09 (52) — one rule with 42 |
| `replaceEqualDeep` walks any array; a `Uint8Array` is compared by identity | `TypedData` is a leaf (`==`, never walked); every `previous` returned is first checked `is T`, a list copy likewise, else `next` — sharing is best effort and never a type error | fifth review, 2026-09-09 |
| `#updateStaleTimeout` adds 1 ms to the timeout | the stale timer rounds its duration up to whole milliseconds and, if it still runs before the deadline (truncation, or the 2^31 ms clamp), re-arms for the remainder | fifth review, 2026-09-09 |
| `hasNextPage` and friends are fields of the infinite result, compared with it | getters on `InfiniteQueryObserver` (#16); `shouldNotify` compares the direction flags at every notification and re-asks `hasNextPage`/`hasPreviousPage` only when the paging functions changed | #16, fifth review, 2026-09-09 |
| observer `TData` defaults to the query's type; nothing checks a mismatch | a `QueryObserver` with no `select` whose `TQueryData` is not a `TData` is refused with `ArgumentError` at construction, `setOptions` and `getOptimisticResult` | fifth review, 2026-09-09 |
| an observer's `onQueryUpdate` throwing inside a dispatch propagates into the fetch | isolated per observer and reported to the zone, like the cache listeners; the query keeps its state | fifth review, 2026-09-09 (59) |
| `useQueries` with a heterogeneous tuple and a `combine` step | a homogeneous `QueriesObserver` (`QueriesController`/`QueriesBuilder` in the binding); mixed data types need a `select`, and there is no `combine` — map the returned list | functional improvements plan, `competitor-deep-dive.md` §6 #13 |
| `useMutationState` reads the cache through a React hook | `MutationStateObserver` (`MutationStateController` in the binding): `MutationFilters` plus a required `select`, structural sharing over the outer list, subscribed only while observed | functional improvements plan, `competitor-deep-dive.md` §6 #9 |
| no minimum background duration before a focus refetch — every foreground event refetches | `AppFocusManager(refetchMinBackgroundDuration:)`, default `Duration.zero` (upstream's behaviour); a shorter absence suppresses **new** focus refetches only, paused work still resumes | functional improvements plan, `competitor-deep-dive.md` §6 #3 |
| `keepPreviousData` / `placeholderData: (prev) => prev` | `const PlaceholderData.keepPrevious()` — identical to `.compute((previous, _) => previous)` including its "a previous `null` means no placeholder" rule, but `const`, so it survives the observer's placeholder memoisation | functional improvements plan, `competitor-deep-dive.md` §6 #4 |
| the binding: a provider always borrows its client | `QueryClientProvider.create` owns the client it builds and `clear()`s it once, after the inner provider unmounted; the `client:` form still borrows and never clears | functional improvements plan, `competitor-deep-dive.md` §6 #7 |
| the binding: side effects need a builder that also rebuilds | `QueryListener` / `InfiniteQueryListener` / `MutationListener` borrow a controller, deliver each accepted transition off the build phase and never rebuild their `child`; a rejected `listenWhen` still advances the comparison state | functional improvements plan, `competitor-deep-dive.md` §6 #8 |
