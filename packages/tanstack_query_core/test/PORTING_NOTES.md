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
- Port-only tests (no upstream counterpart) live in `smoke_test.dart` and, as
  the suite grows, `port_specifics_test.dart`.

## Status

| Upstream suite | Dart file | Cases | State |
|---|---|---|---|
| `subscribable.test.tsx` | `subscribable_test.dart` | 9 / 9 | done |
| `notifyManager.test.tsx` | `notify_manager_test.dart` | 6 / 7 | done |
| `focusManager.test.tsx` | `focus_manager_test.dart` | 6 / 9 | done |
| `onlineManager.test.tsx` | `online_manager_test.dart` | 6 / 11 | done |
| `removable.test.tsx` | `removable_test.dart` | 11 / 12 | done |
| `retryer.test.tsx` | `retryer_test.dart` | 13 / 13 | done |
| `query.test.tsx` | `query_test.dart` | 43 / 51 | done |
| `queryCache.test.tsx` | `query_cache_test.dart` | 14 / 16 | done |
| `queryObserver.test.tsx` | `query_observer_test.dart` | 60 / 75 | done |
| `queryClient.test.tsx` | `query_client_test.dart` | 95 / 156 | done bar the infinite blocks |
| `mutation.test.tsx` | — | 0 / 28 | not started |
| `mutationCache.test.tsx` | — | 0 / 16 | not started |
| `mutationObserver.test.tsx` | — | 0 / 16 | not started |
| `infiniteQueryBehavior.test.tsx` | — | 0 / 9 | not started |
| `infiniteQueryObserver.test.tsx` | — | 0 / 7 | not started |
| `utils.test.tsx` | — | 0 / 78 | not started |

Suites not ported at all, each for one recorded reason:
`hydration.test.tsx` (hydration is out of v1 scope, #17),
`timeoutManager.test.tsx` (the module is not ported, #9),
`environmentManager.test.tsx` (no SSR),
`queriesObserver.test.tsx` (`useQueries` is fog, not v1),
`streamedQuery.test.tsx` (experimental upstream; the Dart `Stream` mapping is
fog).

## Omissions and adaptations, by suite

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
- **omitted — option not ported (1):** `constructor should call
  initialDataUpdatedAt if defined as a function`. `initialDataUpdatedAt` is a
  plain `DateTime?` here: the callback form exists upstream to defer work, and
  the expensive half — producing the data — is already deferred by
  `InitialData.compute`.
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
- **omitted — replaceEqualDeep (4):** `should structurally share the selector`,
  `should structurally share placeholder data`, and the two
  `should not use replaceEqualDeep for select value ...` cases. All four assert
  *reference* identity across two runs that produce equal values, which is what
  `replaceEqualDeep` buys React and what
  [#12](https://github.com/KoTTi97/flutter_query/issues/12) replaced with value
  equality: here the results compare equal, so the observer does not notify —
  the outcome those cases exist to protect.
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

95 ported, **25 deferred** and 36 omitted.

- **deferred — infinite queries (25):** the `ensureInfiniteQueryData`,
  `infiniteQuery with static staleTime`, `fetchInfiniteQuery`, `infiniteQuery`,
  `prefetchInfiniteQuery` and `infiniteQuery used for prefetching` blocks. These
  are not omissions: they land with
  [#16](https://github.com/KoTTi97/flutter_query/issues/16), which builds
  infinite queries, and this file's status line stays "done bar the infinite
  blocks" until they do.
- **omitted — deprecated upstream API (17):** the whole `fetchQuery` (9),
  `ensureQueryData` (5) and `prefetchQuery` (3) blocks. Upstream deprecated all
  three at this pin in favour of `queryClient.query`, and pairs each block with
  a modern equivalent — `query with static staleTime`, `query`, `query used for
  prefetching` — which *are* ported
  ([#17](https://github.com/KoTTi97/flutter_query/issues/17)). The one case with
  no modern counterpart is `ensureQueryData`'s `revalidateIfStale`, an option
  that went away with the method.
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
  is set to false` → `... is not set`. There is no `structuralSharing: false`
  here; not configuring it *is* "no comparison"
  ([#12](https://github.com/KoTTi97/flutter_query/issues/12)).
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

## Deliberate divergences that will show up in later suites

These are decided, not accidental; each is listed here so a reader of a ported
suite does not have to go looking:

| Upstream behaviour | Here | Decided in |
|---|---|---|
| `data === undefined` runtime guard in `Query.fetch` | impossible: `Future<T>` with non-nullable `T` | [#7](https://github.com/KoTTi97/flutter_query/issues/7) |
| `hashKey` string identity, `queryKeyHashFn` | `QueryKey` is a value type; the string is a debug view | [#8](https://github.com/KoTTi97/flutter_query/issues/8) |
| `replaceEqualDeep` structural sharing | value equality plus an optional `structuralSharing` hook | [#12](https://github.com/KoTTi97/flutter_query/issues/12) |
| `trackResult`, `notifyOnChangeProps` | dropped; `select` plus the binding's `buildWhen` | [#15](https://github.com/KoTTi97/flutter_query/issues/15) |
| `throwOnError` | dropped; errors live in the sealed result | [#15](https://github.com/KoTTi97/flutter_query/issues/15) |
| `skipToken` | `Enabled.no` | [#17](https://github.com/KoTTi97/flutter_query/issues/17) |
| module-level managers | instances the `QueryClient` owns | [#19](https://github.com/KoTTi97/flutter_query/issues/19) |
| `staleTime: Infinity` | `StaleTime.infinite` (never stale, still refetchable), distinct from `StaleTime.static` | [#10](https://github.com/KoTTi97/flutter_query/issues/10) |
| `persister`, `initialDataUpdatedAt` as a function | not ported | [#15](https://github.com/KoTTi97/flutter_query/issues/15) |
| a blind cast in `getQueryData` | a type mismatch throws `QueryDataTypeError` | [#7](https://github.com/KoTTi97/flutter_query/issues/7) |
| `fetchQuery` / `prefetchQuery` / `ensureQueryData` (all deprecated upstream at this pin) | one `QueryClient.query`; prefetch is `.ignore()`, ensure is `staleTime: StaleTime.static` | [#17](https://github.com/KoTTi97/flutter_query/issues/17) |
| `query`'s `select` type slot | none: `await` the future and map it | [#7](https://github.com/KoTTi97/flutter_query/issues/7) |
