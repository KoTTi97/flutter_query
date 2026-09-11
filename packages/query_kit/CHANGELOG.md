# Changelog

## 0.1.0

First release. `query_kit` is a Dart port of TanStack Query's `query-core`,
pinned at upstream `50680b98c`: queries, mutations, infinite queries, their
observers, the client and both caches, with no Flutter dependency.

The claim it makes is fidelity. Upstream's own test suite is ported case for
case — 17 suites, 409 of their 535 cases, every omitted case listed by name
with its reason in `test/PORTING_NOTES.md` — and run on the VM and compiled
to JavaScript: 586 tests in all, the regressions of nine review rounds and of
the two example apps included. Closeness to upstream is a tiebreaker, not a
goal: where a Dart idiom is better the port diverges, and every divergence is
a row of the notes' table. The ones a user meets first:

**Types and options**

- Two options shapes, not one (ADR-0001): `QueryObserverOptions<TData>` has
  no `select` and one type slot, anchored by `queryFn`;
  `QuerySelectOptions<TQueryData, TData>` has a *required* `select`. Mirrored
  for infinite queries. A literal that would infer its data type to `dynamic`
  is a compile error, not a `Query<dynamic>` in the cache.
- Every option union is a sealed value type — `StaleTime`, `GcTime`,
  `Enabled`, `RetryPolicy`, `RetryDelay`, `RefetchOn`, `RefetchInterval`,
  `InitialData`, `PlaceholderData` — printing as its source form. `null` means
  "not configured" on every field; "off" is a value, never a magic number.
  `skipToken` is `Enabled.no`; `staleTime: Infinity` is `StaleTime.infinite`,
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
- Structural sharing walks lists element by element and treats maps, sets and
  `TypedData` as leaves; a typed `structuralSharing` hook replaces it per
  query.

**Mutations**

- A mutation function takes its variables only; there is no
  `MutationFunctionContext`. `MutationOptions.simple` is the shape without an
  optimistic step; the callbacks are the typedefs `OnMutate`,
  `OnMutationSuccess`, `OnMutationError` and `OnMutationSettled`.
- `MutationResult.mutate` takes the variables only; per-call callbacks are
  `MutationObserver.mutate(variables, MutateCallbacks(…))`. What `onMutate`
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
devtools. The README's feature matrix has the list, each row with its reason.
