# Changelog

## 1.0.0

First release. `query_kit` is a Dart port of TanStack Query's `query-core`:
a cache for server state with no Flutter dependency. The Flutter binding is
[`query_kit_flutter`](https://pub.dev/packages/query_kit_flutter). From here
on, a breaking change is a major version.

query_kit is an entirely AI-coded project: all code, tests and documentation
were written by AI coding agents (Anthropic's Claude). A human maintainer set
the goals and reviews releases, but did not write the code. It is a community
port, not affiliated with or endorsed by TanStack.

**Queries**

- `QueryClient` with a `QueryCache`: caching by `QueryKey`, `staleTime` and
  `gcTime`, request deduplication, retries with backoff (`RetryPolicy`,
  `RetryDelay`) and cancellation through `QueryCancelToken`.
- `QueryObserver` for reactive reads, with sealed `QueryResult`s
  (`QueryPending`, `QuerySuccess`, `QueryError` carrying the last good data).
- Refetching on focus, on reconnect, on an interval (`RefetchInterval`) and
  after `invalidateQueries`; `Enabled` for dependent and lazy queries.
- `select`, `InitialData`, `PlaceholderData` (including
  `PlaceholderData.keepPrevious()`) and structural sharing, extendable to
  your own classes with `StructurallyShareable`.
- `QueryClient.query` for imperative reads — fetch, prefetch, "ensure" and
  stale-while-revalidate in one method.
- `getQueryData`, `setQueryData`, `updateQueryData`, `cancelQueries`,
  `refetchQueries`, `resetQueries`, `removeQueries`, `QueryFilters`, and
  per-key defaults through `setQueryDefaults`.
- `consecutiveErrorCount` on every result, so polling can give up after N
  failures.

**Mutations**

- `MutationObserver` and `MutationCache`, with `onMutate`, `onSuccess`,
  `onError` and `onSettled`, optimistic updates and rollback.
- `MutationOptions.simple` for mutations without an optimistic step;
  `mutationFnWithContext` and `cancel()` for cancellable mutations.
- `MutationScope` to run writes one after another; paused mutations resume
  when the client is back online (`resumePausedMutations`).
- `MutationStateObserver` for cache-wide mutation state, `isMutating`.

**Infinite queries**

- `InfiniteQueryObserver` with `fetchNextPage`, `fetchPreviousPage`,
  `hasNextPage` and `maxPages`, over a typed `InfinitePageContext`.

**Collections**

- `QueriesObserver` for a dynamic list of queries, and `combine` over a
  record or a list of results (`CombinedResult`, `CombineMemo`, `optional()`,
  `combineWith`).

**Dart-first design**

- Sealed option values (`StaleTime`, `GcTime`, `Enabled`, `RetryPolicy`,
  `RefetchOn`, `RefetchInterval`, …) instead of magic numbers.
- `QueryKey` is a value type; a key is bound to one data type and a
  mismatched read throws `QueryDataTypeError`.
- `AppFocusManager`, `OnlineManager` and `NotifyManager` owned per client;
  time goes through `package:clock`, so `fake_async` controls every timer.

Not in this release: persistence and hydration, `streamedQuery`,
server-side rendering, devtools.
