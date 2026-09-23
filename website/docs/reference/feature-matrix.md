---
title: Feature matrix
description: What is here, and what is deliberately not in 1.0.
---

{/* depth: todo */}

# Feature matrix

Every feature of TanStack Query's core, and where to find it — or why it is
not here.

## Here

| | |
|---|---|
| Queries, staleness, background refetching | `StaleTime`, `RefetchOn`, `RefetchInterval` |
| Request deduplication across observers | one fetch for N readers of one key |
| Retries with backoff | `RetryPolicy`, `RetryDelay`, `failureCount`, `failureReason` |
| Cancellation | `QueryCancelToken`, `client.cancelQueries` |
| Garbage collection | `GcTime` |
| Mutations, optimistic updates, rollback | `onMutate` → `onError`/`onSettled` |
| Mutation scopes (serialised writes) | `MutationScope` |
| Infinite queries, both directions, `maxPages` | `InfiniteQueryOptions` |
| `initialData` and `placeholderData` | including `keepPrevious` |
| `select` and structural sharing | `QuerySelectOptions`, a second options shape with `select` required; plus `buildWhen` on the builders and the keyless reads |
| `select` from a shared options factory | `withSelect(select)` keeps every other field |
| A list of queries | `QueriesObserver` / `QueriesBuilder` |
| Combining results of different types | `(a, b).combine(…)` over a record, `combine` over a `List`, `combineWith`, `optional()`, `CombineMemo` |
| How many queries are fetching (`useIsFetching`) | `client.isFetching()` / `IsFetchingController` |
| Cancelling a mutation, a context for its function | `Mutation.cancel()`, `MutationController.cancel()`, `mutationFnWithContext` |
| Giving up after N failures | `consecutiveErrorCount` on `QueryState` and `QueryResult` |
| Structural sharing into your own classes | `StructurallyShareable` |
| Cache-wide mutation state | `MutationStateObserver` / `MutationStateController`, and `.typed` for one mutation type |
| Cache events and global callbacks | `queryCache.subscribe`, `mutationCache.subscribe`, `meta` |
| Offline behaviour | `NetworkMode`, paused mutations, `resumePausedMutations` |
| Per-client focus / online / notify managers | not module-level singletons |
| A Flutter binding with four equal call styles | and no dependency beyond Flutter |
| Widget tests | the teardown is a documented snippet, not an export — see [Testing](../guides/testing.md) |

## Deliberately not in 1.0

| TanStack Query | Here |
|---|---|
| Persistence and hydration (`hydrate`, `dehydrate`, `persister`, `isRestoring`) | not in 1.0; `Query.setState` is the door a persister would use |
| `notifyOnChangeProps`, `trackResult` | `select`, plus `buildWhen` on the builders and the keyless reads, mutations included |
| `throwOnError` | errors live in the sealed result (`QueryError`) |
| `queryKeyHashFn` | `QueryKey` is a value type |
| `structuralSharing` via `replaceEqualDeep` | deep value equality for lists, maps and sets, `==` for everything else, plus an optional `structuralSharing` hook; a class that implements `StructurallyShareable` is walked into |
| `useQueries`' heterogeneous tuple and its `combine` step | `QueriesObserver` is homogeneous. Different data types are combined with `combine` on a **record of results** — `(a, b).combine((a, b) => …)` gives a `CombinedResult` (pending / error / data with `refetchError`), with an optional `CombineMemo`; the same `combine` over a `List`, `combineWith` for a list plus a source of another type, `optional()` for a source the screen can do without |
| `streamedQuery` | not ported |
| `experimental_prefetchInRender`, Suspense, `fetchOptimistic` | React-only, not ported |
| `select` on `fetchQuery` | map the future |
| `initialDataUpdatedAt` as a function | `initialDataUpdatedAtCompute`, a `DateTime? Function()` evaluated only when the data is actually seeded |
| SSR: `isServer`, `environmentManager`, `timeoutManager` | not ported |
| `MutationFunctionContext` | `mutationFn` takes its variables only; `mutationFnWithContext: (variables, context)` is the two-argument form. Its context adds the typed `onMutateResult` and a `signal` to `client`, `meta` and `mutationKey` — and `cancel()` on a mutation, which TanStack Query does not have, cancels it |
| Callbacks in `setMutationDefaults` | not ported |
| Devtools | none — see [debugging](../guides/debugging.md) |

## The differences

Where query_kit behaves differently rather than not at all — one key, one
exact type; whole-result comparison with `buildWhen`; two options shapes;
named `filters:` — see [differences from TanStack
Query](differences-from-tanstack.md).
