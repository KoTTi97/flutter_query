# Pre-release changelog of `query_kit`

The `1.0.0` entry of `packages/query_kit/CHANGELOG.md` as it stood before the
release-1.0 documentation pass (2026-09-23), kept for the record. It
describes the fix history of code that was never published, with the
review and ticket identifiers of the time. The published CHANGELOG now
carries a feature summary for users instead.

## 1.0.0 (pre-release history)

First release. `query_kit` is a Dart port of TanStack Query's `query-core`,
pinned at upstream `50680b98c`: queries, mutations, infinite queries, their
observers, the client and both caches, with no Flutter dependency. It starts
at 1.0.0 because the surface is meant to hold: a breaking change is a major
version.

The claim it makes is fidelity. Upstream's own test suite is ported case for
case — 17 suites, **414 of their 536** cases, every omitted case accounted for
in `test/PORTING_NOTES.md` by name or by the upstream block it belongs to,
with its category and its reason. The complete core suite has **823** VM tests;
**819** also run compiled to JavaScript (four barrel checks are VM-only),
including pre-release ownership regressions, the regressions of the release
review, the cases found by the example apps and a first real integration, and
32 bounded confidence sequences over the public API. Closeness to
upstream is a tiebreaker, not a goal: where a Dart idiom is better the port
diverges, and every divergence is a row of the notes' table. The ones a user
meets first:

**Pre-release correctness fixes**

- Structural sharing no longer hands a fixed-length or unmodifiable list back
  growable: the shared copy is fixed-length, and a sealed list with nothing to
  share is stored as it came (first real integration, 2026-09-19).
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
  previous key's selection as stale data (OB-01) — nor the selection of a
  placeholder, which upstream shows there as a refetch error. A divergence,
  recorded.
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

**Release review (2026-09-23)**

- A `CancelledError` the query function throws itself — it awaited another
  query that was cancelled, say — is an ordinary error of that query; it used
  to revert silently and never settle. It does not count toward
  `consecutiveErrorCount`.
- `client.query` of an infinite key that has an observer, without a page
  function, borrows the observer's paging, and so does an invalidation driven
  by a select-only reader; both used to throw "missing queryFn".
- `setOptions` with an `InitialData.compute` that throws leaves the observer's
  query and the previous key's running fetch untouched, and a same-key
  `setOptions` that brings a new `select` with a new `initialData` runs the
  new `select` on the seed. `QueriesObserver.setQueries` is atomic: a member
  whose options throw leaves the collection as it was, with its combined
  result recomputed and its listeners told.
- A `keepPrevious` placeholder is not reported as the new key's `staleData`
  when that key's `select` throws; the result is a loading error.
- `==` is symmetric across type arguments for `InitialData`,
  `PlaceholderData` and `InfiniteData`.
- Mutations: one started paused that could run by the time an async
  `onMutate` returned no longer reports `isPaused` while its function runs;
  `cancel()` on one restored `pending` from persistence fails it instead of
  doing nothing, and hands its scope on only if it held it — cancelling a
  restored scope's tail leaves the head paused, and a head cancelled and
  removed from the cache (in either order) still hands on to its tail;
  offline, `resumePausedMutations()` no longer waits for an
  `always` mutation queued behind an `online` scope-mate that cannot run; a
  second run whose `onMutate` threw no longer hands the first run's
  `onMutateResult` to its error callbacks.
- A `FocusSetup` / `OnlineSetup` that throws when it is reinstalled is
  reported to the zone and no longer leaks the listener.

**Types and options**

- Two options shapes, not one (ADR-0001): `QueryObserverOptions<TData>` has
  no `select` and one type slot, anchored by `queryFn`;
  `QuerySelectOptions<TQueryData, TData>` has a *required* `select`. Mirrored
  for infinite queries. `withSelect(select)` turns the first into the second
  and keeps every other field, so one options factory serves a projecting
  reader too. Without a query function or an expected type, an
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
  `DateTime` parts compare by instant — UTC and local of one moment are one
  key, as upstream's JSON hash makes them. A map part may be keyed by any
  valid part (a record, an enum, a value class), not by a collection.
- No `TError` (an error is `Object` plus a `StackTrace`) and no `TQueryKey`.
  `throwOnError`, `notifyOnChangeProps` and `trackResult` have no counterpart:
  errors live in the sealed `QueryResult`, narrowing is `select`.

**Client and cache**

- One `QueryClient.query` in place of `fetchQuery`, `prefetchQuery` and
  `ensureQueryData`: prefetch is `.ignore()`, ensure is
  `staleTime: StaleTime.static`, stale-while-revalidate is
  `revalidateIfStale: true`. It has no `select`; map the future. It joins a
  fetch already in flight — use `refetchQueries` for one that starts after
  your write — and the options it is given, `retry` included, stay on the
  query.
- `setQueryData`, `updateQueryData` and `updateQueriesData` let an existing
  entry take any value its own type can hold, so the ordinary
  optimistic-update spellings write; `updateQueriesData` checks every
  updater's result before it writes anything, and paged data keeps the exact
  rule. `setQueryData` returns what the cache stored, after structural
  sharing. A bare `setQueryData(key, null)` infers `Null` and writes nothing,
  as upstream's `undefined` does; `setQueryData<T?>(key, null)` stores a null.
- `isFetching(filters:)` and `isMutating(filters:)` override the filter's
  `fetchStatus` / `status`, as upstream does.
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

- `mutationFn` takes its variables only; `mutationFnWithContext` is the
  two-argument form (below). Setting both is a debug assertion at the options
  literal and an `ArgumentError` when the client resolves them.
  `MutationOptions.simple` is the shape without an optimistic step; the
  callbacks are the typedefs `OnMutate`, `OnMutationSuccess`,
  `OnMutationError` and `OnMutationSettled`.
- In a `MutationScope` only the function waits its turn: `onMutate` runs at
  submission, and the scope is held until `onSettled`'s future completes —
  `isMutating()` counts the mutation inside its own `onSettled`.
  `MutationResult.isPaused` covers a run queued behind its scope or waiting
  for focus, not only the network.
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
  collection, `select` for the rest), `MutationStateObserver`
  (`useMutationState`), `PlaceholderData.keepPrevious()` and
  `initialDataUpdatedAtCompute`.
- `combine` on a record of two to six `QueryResult`s of different data types
  gives a sealed `CombinedResult` — pending, error, or data with a
  `refetchError` — with `retry()`, `refetch()` and an optional `CombineMemo`
  (with `keys:` for whatever else the combiner reads), `optional()` for a
  source the screen can do without, the same `combine` over a
  `List<QueryResult<T>>`, and `combineWith` for such a list plus a source of
  another type; sources of more types go in a list typed by what they have
  in common, cast in the combiner. Stands in for `useQueries`' heterogeneous
  tuple and `combine` step. `refetch(cancelRefetch: false)` and
  `retry(cancelRefetch: false)` join a fetch in flight, so two combinations
  sharing a source and refreshed together fetch it once.
- `StructurallyShareable<T>`: a value class implements `shareWith(previous)`
  and structural sharing walks into it — a wrapper around a list is otherwise
  a leaf, and one changed element renews every instance. Returning `previous`
  is right exactly when nothing changed — how a class without value equality
  keeps its instance across an unchanged refetch. Nothing checks the
  contract, in debug builds or release: for an `==` that is not deep, the
  walk cannot tell a correct `previous` from a stale one.
- `QueryState.consecutiveErrorCount`, carried on `QueryResult` too — failed
  fetches in a row, zero again with the next *fetched* data; a manual write
  and a cancelled fetch leave it alone — so a `RefetchInterval.dynamic` can
  give up after N and a widget can say so from the result it has; and
  `MutationStateObserver.typed`, a mutation-state selection filtered by and
  typed to one mutation type, for the observer's life — a later `setOptions`
  keeps the type, and a filter's `predicate` only sees mutations of that
  type, so it may read the declared type without a cast.
- An `Enabled.when` over state outside the cache is re-evaluated when the
  observer is handed its options again — every rebuild — because `setOptions`
  compares against what the observer last committed rather than resolving the
  old options at the same instant, as upstream does; a query update between
  the flip and the rebuild no longer hides it. `StaleTime.dynamic` over
  outside state is re-evaluated the same way. A predicate over the query
  itself whose answer changes between rebuilds refetches on the next rebuild
  if the data is stale, which upstream does not.
- `mutationFnWithContext: (variables, context)` — upstream's
  `MutationFunctionContext` (`client`, `meta`, `mutationKey`) plus a typed
  `onMutateResult` and a `signal` — and `cancel()` on `Mutation` and
  `MutationObserver`, which fails the run with a `CancelledError` so the
  error callbacks roll back. Upstream cannot cancel a mutation.
- `FetchBehavior` and `FetchContext` are exported so `QueryOptions.behavior`
  is nameable; the observer-ref members and the cache plumbing are
  `@internal`.

Not in this release: persistence and hydration, `streamedQuery`, SSR,
devtools. The README's feature matrix has the list; `test/PORTING_NOTES.md`
records the reason for each row.
