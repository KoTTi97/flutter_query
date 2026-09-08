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
| `query.test.tsx` | `query_test.dart` | 43 / 51 | done |
| `queryCache.test.tsx` | `query_cache_test.dart` | 14 / 16 | done |
| `queryObserver.test.tsx` | `query_observer_test.dart` | 60 / 75 | done |
| `queryClient.test.tsx` | `query_client_test.dart` | 104 / 156 | done |
| `mutation.test.tsx` | `mutation_test.dart` | 28 / 28 | done |
| `mutationCache.test.tsx` | `mutation_cache_test.dart` | 16 / 16 | done |
| `mutationObserver.test.tsx` | `mutation_observer_test.dart` | 16 / 16 | done |
| `infiniteQueryBehavior.test.tsx` | `infinite_query_behavior_test.dart` | 7 / 9 | done |
| `infiniteQueryObserver.test.tsx` | `infinite_query_observer_test.dart` | 6 / 7 | done |
| `utils.test.tsx` | `utils_test.dart` | 24 / 78 | done |

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

104 ported and 36 omitted (the 25 infinite cases were deferred until
[#16](https://github.com/KoTTi97/flutter_query/issues/16) and are ported now —
see the infinite section below).

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

24 ported, 54 omitted (the 8 `addToEnd`/`addToStart` cases were deferred until
[#16](https://github.com/KoTTi97/flutter_query/issues/16) and are ported now).
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
- **omitted — replaceEqualDeep (21):** the whole block
  ([#12](https://github.com/KoTTi97/flutter_query/issues/12)).
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
are `tanstack_query_flutter/test/review_regressions_test.dart`.

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
| `MutationFunctionContext` (a mutation function's second argument) | not ported: `MutationFn` takes variables only |  [#14](https://github.com/KoTTi97/flutter_query/issues/14) |
| `skipToken` | `Enabled.no` | [#17](https://github.com/KoTTi97/flutter_query/issues/17) |
| module-level managers | instances the `QueryClient` owns | [#19](https://github.com/KoTTi97/flutter_query/issues/19) |
| `staleTime: Infinity` | `StaleTime.infinite` (never stale, still refetchable), distinct from `StaleTime.static` | [#10](https://github.com/KoTTi97/flutter_query/issues/10) |
| `persister`, `initialDataUpdatedAt` as a function | not ported | [#15](https://github.com/KoTTi97/flutter_query/issues/15) |
| `hasNextPage` / `fetchNextPage` on the query result | on `InfiniteQueryObserver`; the sealed result stays one shape | [#16](https://github.com/KoTTi97/flutter_query/issues/16) |
| an infinite query's `queryFn` returning one page | `pageFn`, with its own typed `InfinitePageContext` | [#16](https://github.com/KoTTi97/flutter_query/issues/16) |
| a blind cast in `getQueryData` | a type mismatch throws `QueryDataTypeError` | [#7](https://github.com/KoTTi97/flutter_query/issues/7) |
| `MutationCache.remove` leaves the mutation's gc timer running | the timer is cancelled, so a removed mutation cannot ask to be removed again | [#22](https://github.com/KoTTi97/flutter_query/issues/22) |
| a cancelled retry can still flip its query from `idle` to `paused` after its delay | the retryer checks `isResolved` after the delay | review, 2026-09-08 |
| a removed query or mutation re-arms its own gc timer from the fetch's `finally` | removal marks it, and a marked one schedules nothing | [#24](https://github.com/KoTTi97/flutter_query/issues/24) |
| `fetchQuery` / `prefetchQuery` / `ensureQueryData` (all deprecated upstream at this pin) | one `QueryClient.query`; prefetch is `.ignore()`, ensure is `staleTime: StaleTime.static` | [#17](https://github.com/KoTTi97/flutter_query/issues/17) |
| `query`'s `select` type slot | none: `await` the future and map it | [#7](https://github.com/KoTTi97/flutter_query/issues/7) |
| a `select` that threw keeps reporting its error after `select` is removed | the error goes with the selector; the raw data is reported | review, 2026-09-09 |
| a retained placeholder keeps its old selection after `select` changed | the new `select` runs over the placeholder | review, 2026-09-09 |
| an observer resubscribing after its query was collected rejoins the dead query | it re-resolves the key and joins the current entry (one adapted assertion in `query_test.dart`) | review, 2026-09-09 |
| `initialData: null` / `placeholderData: null` mean "none" | `.value(null)` is a value of `null`; `.compute` returning `null` means "none" | review, 2026-09-09 |
