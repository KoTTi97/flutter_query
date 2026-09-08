# Porting notes

Where the Dart tests diverge from the upstream suites in
`query/packages/query-core/src/__tests__/`, and why. The rule: every upstream
test is either ported, or listed here with a reason. No silent omissions.

## Coverage of the six priority suites

| Upstream file | Cases | Ported | Dart file |
|---|---:|---:|---|
| `query.test.tsx` | 50 | 44 | `query_test.dart` |
| `queryCache.test.tsx` | 16 | 14 | `query_cache_test.dart` |
| `queryObserver.test.tsx` | 73 | 52 | `query_observer_test.dart` |
| `queryClient.test.tsx` | 156 | 110 | `query_client_test.dart` |
| `mutation.test.tsx` | 28 | 27 | `mutation_test.dart` |
| `mutationCache.test.tsx` | 16 | 16 | `mutation_cache_test.dart` |
| `mutationObserver.test.tsx` | 16 | 16 | `mutation_observer_test.dart` |
| **Total** | **355** | **279** | |

The 76 unported cases are enumerated by category below. They fall into three
groups: features the port drops by design, JavaScript semantics with no Dart
analogue, and type-level tests.

## Test-by-test provenance

| Dart test file | Upstream source | Relationship |
|---|---|---|
| `query_key_test.dart` | `utils.test.tsx` (`hashKey`, `partialMatchKey`) | Ported in substance. Upstream asserts on hashed strings; we assert key equality, because the port drops string hashing (`QueryKey` is the map key directly). |
| `notify_manager_test.dart` | `notifyManager.test.tsx` | Adapted. Upstream schedules via `setTimeout(0)` and exposes `setNotifyFunction`/`setBatchNotifyFunction`; the port coalesces into a microtask with a single `deferFlush` seam (design decision D8), so the scheduling-hook tests became `deferFlush` tests. |
| `managers_test.dart` | `focusManager.test.tsx`, `onlineManager.test.tsx` | Ported minus DOM cases. |
| `removable_test.dart` | gc cases in `query.test.tsx` | Extracted. `Removable` is its own base class here, so its scheduling is tested directly; the query-level gc cases are also ported in `query_test.dart`. |
| `retryer_test.dart` | — | New. Upstream has no retryer suite; it covers the retryer indirectly through `query.test.tsx` and `mutation.test.tsx`. Written so retry/pause/resume was pinned before `Query` depended on it. |
| `query_options_test.dart` | `queryClient.test.tsx` (`defaultQueryOptions`) | Partial, and now largely superseded: the standalone merge function is tested standalone here, while the client-level defaulting cases are ported in `query_client_test.dart`. |
| `query_test.dart` | `query.test.tsx` | Faithful port, case for case. |
| `query_cache_test.dart` | `queryCache.test.tsx` | Faithful port, case for case. |
| `query_observer_test.dart` | `queryObserver.test.tsx` | Faithful port, case for case. |
| `query_client_test.dart` | `queryClient.test.tsx` | Faithful port of everything in MVP scope. |
| `mutation_test.dart` | `mutation.test.tsx` | Faithful port, case for case. |
| `mutation_cache_test.dart` | `mutationCache.test.tsx` | Faithful port, case for case. |
| `mutation_observer_test.dart` | `mutationObserver.test.tsx` | Faithful port, case for case. |
| `port_specifics_test.dart` | — | New. Behaviour the port introduces where a design decision replaced a JavaScript idiom: `null` in place of `undefined`, sealed option values in place of magic numbers/strings, typed cache entries in place of one hashed key. |

## Skipped upstream tests

### `query.test.tsx` — 6 of 50
- `should reset to default state when created from hydration`.
  **Reason:** hydration/dehydration is out of MVP scope.
- `fetch should dispatch an error if the queryFn returns undefined`.
  **Reason:** the port's `QueryFn<TQueryData>` returns a non-nullable
  `TQueryData`, so the compiler enforces what this test checks at runtime.
- `should not retry on the server`.
  **Reason:** no `environmentManager`; the port has no server/client split (D10).
- `should have an error log when queryFn data is not serializable`.
  **Reason:** structural sharing is off by default and never JSON-serializes
  (D5), so there is nothing to blow the stack.
- `should use persister if provided`.
  **Reason:** persister dropped.
- `should log error when queryKey is not an array`.
  **Reason:** `QueryKey` is a class, so this is a compile error, not a runtime
  warning.

### `queryCache.test.tsx` — 2 of 16
- `build: should compute queryHash from queryKey when queryHash is not provided`
- `build: should use provided queryHash instead of computing it`.
  **Reason:** the port has no `queryHash`. `QueryKey` has deep value equality
  and is used as the map key directly, so there is no hash to compute or
  override.

### `queryObserver.test.tsx` — 21 of 73
- Seven `placeholderData` cases (`should use placeholderData as non-cache
  data…`, `should structurally share placeholder data`, the two
  `placeholderData` function-parameter cases, `should use cached selectResult
  when switching between queries…`, `should not have isPlaceholderData true
  when selector throws…`, `should not leak a stale select error through the
  memoized placeholderData path`).
  **Reason:** `placeholderData` is out of MVP scope — the demo's equivalent need
  is met by functional `initialData`.
- Three structural-sharing-of-select cases (`should structurally share the
  selector`, both `should not use replaceEqualDeep for select value…`).
  **Reason:** `replaceEqualDeep` is dropped (D5); result equality is `==`, so
  reference identity across fetches is not a promise the port makes.
- Two `notifyOnChangeProps` cases.
  **Reason:** dropped. The port notifies on any result change and relies on
  field-wise `==` to suppress no-ops.
- Three `throwOnError` / `trackResult` / `trackProp` cases.
  **Reason:** observer-level `throwOnError` feeds React error boundaries and
  `trackResult` is a `Proxy`; neither has a Flutter analogue.
- Four optimistic-result cases (`fetchOptimistic` ×2, `_optimisticResults` is
  `isRestoring`, `getOptimisticResult`).
  **Reason:** the observer is synchronously authoritative in the port, so there
  is no optimistic-result path to test.
- `should throw an error if enabled option type is not valid`.
  **Reason:** `Enabled` is a sealed type; invalid values do not compile.
- `should be able to fetch with a selector and object syntax`.
  **Reason:** duplicate — it differs from `should be able to fetch with a
  selector` only in JavaScript call syntax, which the Dart API does not have.

### `queryClient.test.tsx` — 46 of 156
- **Infinite queries, 26 cases:** the whole of `ensureInfiniteQueryData`,
  `infiniteQuery with static staleTime`, `fetchInfiniteQuery`, `infiniteQuery`,
  `prefetchInfiniteQuery`, and `infiniteQuery used for prefetching`.
  **Reason:** infinite queries are out of MVP scope. `Query` keeps a replaceable
  fetch seam so they can be added later.
- **`ensureQueryData`, 5 cases.**
  **Reason:** deprecated upstream in favour of `query({staleTime: 'static'})`,
  which *is* ported; the plan excludes it.
- **`skipToken`, 5 cases** (4 in `query`, 1 in `invalidateQueries`).
  **Reason:** no `skipToken` in the port — not running is expressed as
  `Enabled.off`. The `resetQueries` case that used `skipToken` incidentally is
  ported with a disabled observer instead.
- **Mutations: all ported.** `isMutating`, both `setMutationDefaults` cases and
  the six mutation-driven cases in `focusManager and onlineManager` landed with
  M6. The hydration-based one (`should resumePausedMutations when coming online
  after having restored cache`) is adapted: the port has no hydration, so the
  restored paused mutation is built directly on the new client's cache — which
  is exactly the state hydration would produce.
- **`defaultQueryOptions` persister cases, 3.**
  **Reason:** persister dropped, so there is no persister-driven `networkMode`
  default.
- **`should not type-error with strict query key`, 4 cases** (in `fetchQuery`,
  `query`, `prefetchQuery`, `query used for prefetching`; the infinite variants
  are counted above).
  **Reason:** type-level tests. Dart's type system checks this at compile time.
- **`setQueryData`, 4 cases:** `should use default options` (asserts on
  `queryKeyHashFn`); both `structuralSharing` cases; and one of the two
  `undefined` pairs.
  **Reason:** no `queryKeyHashFn` and no `queryHash`. `structuralSharing` is a
  typed, per-query option in the port and deliberately absent from the untyped
  `QueryDefaults` bag, so it cannot be set through client defaults as those
  tests do — it is covered directly in `port_specifics_test.dart`. Upstream
  distinguishes "data is `undefined`" from "the updater returned `undefined`";
  the port's updater is function-only, so both collapse into one case.

### `focusManager.test.tsx` / `onlineManager.test.tsx`
- Every case driving DOM events (`visibilitychange`, `window` `online`/`offline`,
  `addEventListener` presence checks, `setEventListener` replacement).
  **Reason:** the port's managers carry no event source at all — core defaults to
  focused/online and the Flutter binding drives them (D10). The equivalent
  coverage lands in `flutter_query`'s widget tests in M7.

### `utils.test.tsx`
- `hashKey` string-shape assertions, `queryKeyHashFn`, `replaceEqualDeep` /
  structural-sharing cases, `shallowEqualObjects`.
  **Reason:** dropped by design — no string hashing (see above), and structural
  sharing is off by default with result equality via `==` (D5).
- `isPlainObject`, `isPlainArray`, `sleep`, `addToEnd`/`addToStart`.
  **Reason:** JS-specific helpers with no port, or (addToEnd/addToStart) used
  only by infinite queries, which are out of MVP scope.

### `notifyManager.test.tsx`
- `setNotifyFunction`, `setBatchNotifyFunction`, `setScheduler` cases.
  **Reason:** replaced by the single `deferFlush` seam (D8); the replacement is
  tested.

### `mutation.test.tsx` — 1 of 28
- `mutate update the mutation state even without an active subscription 2`.
  **Reason:** duplicate — upstream's cases 1 and 2 are byte-identical, and the
  port has the single copy.

### `mutationCache.test.tsx` / `mutationObserver.test.tsx` — all ported
The context assertions drop one field: upstream's `MutationFunctionContext`
also carries the `QueryClient`, which the port leaves out so `Mutation` does
not depend on the client. A mutation function that needs the client closes over
it, as the demo does.

### Whole files not ported
- `hydration.test.tsx`, `infiniteQueryBehavior.test.tsx`,
  `infiniteQueryObserver.test.tsx`, `queriesObserver.test.tsx`,
  `streamedQuery.test.tsx`, `timeoutManager.test.tsx`,
  `environmentManager.test.tsx`, all `*.test-d.tsx` (type-level tests).
  **Reason:** the corresponding features are out of MVP scope or dropped by
  design (see the plan's scope table). Type-level tests have no Dart analogue —
  the type system checks these at compile time.

## Port bugs the ported suites caught

Recorded because they are the argument for porting the suites rather than
writing fresh tests:

1. **`Removable.gcTime` could never go below five minutes.** The field was
   initialised to the default before `max()` was applied; upstream starts from
   zero (`Math.max(this.gcTime || 0, …)`), so the first value applies as given.
   Every `gcTime: 0` test would have silently kept entries alive.
2. **The fetch reducer cleared `error` on a background refetch.** Upstream only
   resets `status`/`error` when there is no data.
3. **`Query.setOptions` replaced the whole state when applying `initialData`.**
   Upstream merges a partial state, so an in-flight fetch keeps its
   `fetchStatus` and `dataUpdateCount` stays put. The full replacement made
   seeding look like a completed fetch and started a duplicate request.
4. **The silent-cancel path recorded an error.** Upstream returns the
   replacement retryer's promise without dispatching; the port dispatched an
   error action, so `reset()` during a pending fetch left an error behind.
5. **The silent cancel was awaited.** Upstream does not await it, which matters:
   the cancelled fetch's own handler runs on a microtask and reads `_retryer` to
   find the fetch to piggyback on. Awaiting let it run first and adopt the
   retryer that had just failed.
6. **Cache-level `onSuccess`/`onError`/`onSettled` fired on manual writes.** They
   were wired to the state change; upstream fires them from the fetch, so
   `setQueryData` does not look like a request that succeeded.
7. **A query with no query function adopted only the function from its first
   observer**, where upstream adopts that observer's whole options object.
8. **`Query.isDisabled()` used AND where upstream uses OR.** A never-fetched
   query with no observers was treated as enabled, so `refetchQueries` fetched
   queries it should have skipped.
9. **The cache-level `onMutate` hook made the mutation's own `onMutate` async.**
   Upstream only awaits the cache hook when one is registered; the port awaited
   an `async` wrapper unconditionally, which pushed every optimistic update a
   microtask past `mutate()` — long enough for a frame to render the old value.

## Deliberate divergences from upstream

Behaviour where the port does *not* match upstream, and why:

1. **A pending mutation's collection clock.** Upstream re-arms the gc timer
   every time it fires while a mutation is still pending, effectively polling.
   That is safe in a browser, which clamps `setTimeout(0)` to a few
   milliseconds; Dart does not clamp `Timer(Duration.zero)`, so with
   `gcTime: 0` the same code spins the event loop (and hangs `fake_async`
   outright). The port instead restarts the clock when the mutation settles, in
   `Mutation.execute`'s `finally` — the same place `Query.fetch` already does
   it. Same observable outcome, no busy loop; the four upstream gc tests pass
   unchanged.
2. **Mutation callbacks are `FutureOr<void>`, not `Promise<unknown> | unknown`.**
   Upstream lets a callback *return* a promise, which it then awaits. Dart
   cannot type "returns anything, and the value is ignored" without warning on
   every non-returning `async` body, so a callback that needs to wait says so
   with `await` inside its body. The three upstream "callback return types"
   cases are ported in that form; what they actually pin — that the mutation
   waits for the callback before settling — is unchanged.
