# Changelog

## 0.1.0

First release. `query_kit` is a Dart port of TanStack Query's `query-core`,
pinned at upstream `50680b98c`: queries, mutations, infinite queries, their
observers, the client and both caches, with no Flutter dependency.

The claim it makes is fidelity. Upstream's own test suite is ported case for
case — 17 suites, **414 of their 536** cases, every omitted case accounted for
in `test/PORTING_NOTES.md` by name or by the upstream block it belongs to,
with its category and its reason. The complete core suite has **741** VM tests;
**737** also run compiled to JavaScript (four barrel checks are VM-only),
including pre-release ownership regressions, the cases found by the example
apps and 32 bounded confidence sequences over the public API. Closeness to
upstream is a tiebreaker, not a goal: where a Dart idiom is better the port
diverges, and every divergence is a row of the notes' table. The ones a user
meets first:

**Pre-release correctness fixes**

- Canceled or reset query operations cannot overwrite a successor; late signal
  reads stay with their own fetch, and reentrant retry teardown leaves no timer.
- Mutation scopes remain exclusive through completion callbacks, including
  reentrant submission and removal. Per-call callbacks retain matching
  variables and results; reset and resubscription preserve observer ownership.
- Observer key changes retain the correct refetch targets. Optimistic selector
  previews cannot poison committed selection/placeholder state, and disposed
  observers cannot reattach or restart polling from an older callback frame.
- Subscription handles identify individual registrations; reentrant state
  notifications cannot end with an obsolete snapshot.
- Restored payloads are validated at every state-entry boundary. Removed cache
  objects cannot be re-added; adding an existing mutation again is a no-op.
- Lifecycle policy errors are isolated so unrelated paused work can continue.
  Retry/network option lifetimes, placeholder sharing and synchronous direct
  subscriptions are now documented explicitly (ADR-0003).
- Clearing or removing mutations never starts one: `clear()` empties the
  cache before destroying anything, and only the removal of a scope's
  never-started head releases its waiters, one microtask later (MU-01).
- A cancel delivered from the `fetch` notification while offline no longer
  leaves the query paused with nothing running (QE-01).
- A `select` that throws after a key change reports a loading error, not the
  previous key's selection as stale data (OB-01).
- Structural sharing and key equality compare sets in linear time, for
  every member type: a 10 000-member set of `int`s, `double`s, strings,
  records or `DateTime`s costs about 1–1.5 ms per cache write on the VM
  instead of a tenth of a second, and a 100 000-member one about 20–25 ms —
  roughly a frame, which is the documented limit (AR-01, R3-1). Sets of
  fractional `double`s had stayed quadratic on the VM, 1.6 s at 50 000
  members, until their hashes were spread across the walk's buckets.
- Query keys and data that hold a fractional `double` hash evenly. On the
  VM such a value varies only in its high hash bits, which Dart's composite
  hashes mask away: 10 000 keys `['price', i + 0.5]` shared 396 hash codes,
  so writing and reading them took 140 ms instead of 15 ms, and 1.7 s at
  50 000. Leaf hashes are now spread before they are combined, in the key
  and in structural sharing alike; a set of maps or lists holding such a
  value compares in linear time too (R3-1 follow-up).
- A set with its own equality policy — a `SplayTreeSet` with a comparator, a
  `LinkedHashSet` with `equals:`/`hashCode:` — is compared member by member
  under deep equality, not under its policy, so a refetch that changes a
  member only in a way the policy ignores (`'Alpha'` → `'alpha'`) is written
  and reported. The comparison asks a set only for its length and members,
  never for `lookup`, `contains` or `containsAll`, so a set whose own methods
  throw (`package:collection`'s `MapKeySet`) or return their argument
  (dart2js's default set, for numbers) is compared correctly too. Two faster
  shortcuts through the set's own methods had kept the old value, the second
  only on the web (F1, R2-1, R2-2, R2-4). A map is still looked up by its own
  keys; give a map with a custom key equality its own hook or
  `noStructuralSharing()` when the key representation matters.
- `subscribe` and `setOptions` are atomic when a dynamic option throws, and
  every bulk query operation reports a throwing predicate through its future
  (AR-02, AR-05, AR-12).
- `refetchQueries(type: all)` and `invalidateQueries(refetchType: all)`
  refetch an unobserved query that has fetched before, whatever its last
  observer's `enabled` said — as upstream does for `enabled: false`, which
  `Enabled.no` is — and evaluate no `Enabled.when` predicate for a query
  nobody observes. Upstream's `skipToken`, which would skip such a query, has
  no separate spelling here (F2, F3).
- `noStructuralSharing()` is the opt-out for `structuralSharing` — upstream's
  `false` — and turns sharing off for the cache write, placeholder data and
  what `select` returns. A hook of your own, `(_, next) => next` included,
  governs the cache write and leaves `select` output shared by the default
  comparison, because the hook is typed for the query's data and cannot be
  handed a selection (FI-05, F4).
- A successful query state must hold data whatever its type: a query that
  resolved to nothing is restored with `hasData: true, data: null`, and a
  data-less `success` is refused with an `ArgumentError`, because an observer
  selecting into a non-nullable type crashed on it (R2-3). A successful
  mutation whose data type admits null (`void`, a nullable type) restores
  without `hasData`; a non-nullable one is still refused (F5).
- Removing a restored scope head releases the queue it was blocking even if
  its options change before the release runs (F6).

**Types and options**

- Two options shapes, not one (ADR-0001): `QueryObserverOptions<TData>` has
  no `select` and one type slot, anchored by `queryFn`;
  `QuerySelectOptions<TQueryData, TData>` has a *required* `select`. Mirrored
  for infinite queries. Without a query function or an expected type, an
  options literal still needs an explicit type argument; Dart can otherwise
  infer `dynamic`. Consumer strict-inference lints provide an additional check.
- Every option union is a sealed value type — `StaleTime`, `GcTime`,
  `Enabled`, `RetryPolicy`, `RetryDelay`, `RefetchOn`, `RefetchInterval`,
  `InitialData`, `PlaceholderData` — printing as its source form. `null` means
  "not configured" on every field; "off" is a value, never a magic number.
  `skipToken` is `Enabled.no`, which keeps `enabled: false`'s meaning where
  the two differ; `staleTime: Infinity` is `StaleTime.infinite`,
  distinct from `StaleTime.static`.
- `Defaulted*Options` are distinct types with value equality, and only
  `QueryClient` produces them.
- `QueryKey` is a value type with structural equality. One key, one exact
  type: a covariant read (`int` under `int?`, `List<Task>` under
  `List<Object?>`) throws `QueryDataTypeError` at the call, naming the cure.
- No `TError` (an error is `Object` plus a `StackTrace`) and no `TQueryKey`.
  `throwOnError`, `notifyOnChangeProps` and `trackResult` have no counterpart:
  errors live in the sealed `QueryResult`, narrowing is `select`.

**Client and cache**

- One `QueryClient.query` in place of `fetchQuery`, `prefetchQuery` and
  `ensureQueryData`: prefetch is `.ignore()`, ensure is
  `staleTime: StaleTime.static`, stale-while-revalidate is
  `revalidateIfStale: true`. It has no `select`; map the future.
- Every filter parameter is a named `filters:`; `invalidateQueries` freezes
  its match set before invalidating.
- The focus, online and notify managers are instances the client owns
  (`NotifyManager.shared` opts back in). `AppFocusManager` can suppress a
  focus refetch after an absence shorter than
  `refetchMinBackgroundDuration`; the default is upstream's behaviour.
- A fetch is joinable and cancellable from the moment it is announced, and
  every caller of a deduplicated fetch gets one outcome, settled after the
  cache write and the cache hooks; a throwing cache hook is reported to the
  zone and hangs nobody.
- Listeners are a `List`, not a `Set`: Dart tear-offs compare equal, so it is
  one registration per `subscribe`, and a handle called twice removes nothing
  more.
- `MissingQueryFunctionError` is never retried. Timers are clamped to 2^31−1
  ms, so a 30-day `gcTime` does not fire at once on the web.
- Structural sharing walks lists element by element, shares maps and sets
  whole when deeply equal, and treats `TypedData` as a leaf; a typed
  `structuralSharing` hook replaces it for the cache write, and
  `noStructuralSharing()` turns it off everywhere.

**Mutations**

- A mutation function takes its variables only; there is no
  `MutationFunctionContext`. `MutationOptions.simple` is the shape without an
  optimistic step; the callbacks are the typedefs `OnMutate`,
  `OnMutationSuccess`, `OnMutationError` and `OnMutationSettled`.
- `MutationResult.mutate` takes the variables only; per-call callbacks are
  `MutationObserver.mutate(variables, callbacks: MutateCallbacks(…))`. What `onMutate`
  returned goes to `onError` and `onSettled`, not onto the result.
- A mutation removed from the cache stops retrying and fails — with its last
  error, or a `CancelledError` when it was paused — and its error callbacks
  run a few microtasks after the removal. `clear()` empties the caches and
  does not seal them: a rollback written by a dropped optimistic mutation is
  a write like any other, which is why a test teardown clears twice.
- `resumePausedMutations` is gated per mutation on the retryer's
  continuation rule and settles after the resumed mutations' callbacks, so a
  reconnect refetch behind it sees what `onSuccess` wrote.

**Infinite queries**

- The page function is `pageFn`, over a typed `InfinitePageContext`
  (`pageParam`, `direction`); `hasNextPage`, `fetchNextPage` and the paging
  flags are on `InfiniteQueryObserver`, so the sealed result stays one shape.
  `InfiniteQueryOptions` carries its own paging behaviour, so
  `QueryClient.query` accepts it.
- The `pages` and `pageParams` lists the library writes are unmodifiable and
  shared page by page on refetch; `flatten<T>()` throws an `ArgumentError`
  naming the page type when a page is not an `Iterable<T>`.
- `maxPages` is upstream's arithmetic: a directional fetch past the limit
  drops one page from the other end, and the count comes down to the limit on
  the next refetch.

**Beyond `query-core`**

- `QueriesObserver` (upstream's `useQueries`, homogeneous: one data type per
  collection, `select` for the rest, no `combine`), `MutationStateObserver`
  (`useMutationState`), `PlaceholderData.keepPrevious()` and
  `initialDataUpdatedAtCompute`.
- `FetchBehavior` and `FetchContext` are exported so `QueryOptions.behavior`
  is nameable; the observer-ref members and the cache plumbing are
  `@internal`.

Not in this release: persistence and hydration, `streamedQuery`, SSR,
devtools. The README's feature matrix has the list; `test/PORTING_NOTES.md`
records the reason for each row.
