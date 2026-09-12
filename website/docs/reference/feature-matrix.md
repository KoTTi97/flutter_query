---
title: Feature matrix
sidebar_position: 2
description: What is here, what is deliberately not, and where the reason for each omission is recorded.
---

# Feature matrix

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
| `select` and structural sharing | `QuerySelectOptions`, a second options shape with `select` required ([ADR-0001](https://github.com/KoTTi97/flutter_query/blob/main/docs/adr/0001-one-type-slot-for-plain-queries.md)); plus `buildWhen` on the builders and the keyless reads |
| A list of queries | `QueriesObserver` / `QueriesBuilder` |
| Cache-wide mutation state | `MutationStateObserver` / `MutationStateController` |
| Cache events and global callbacks | `queryCache.subscribe`, `mutationCache.subscribe`, `meta` |
| Offline behaviour | `NetworkMode`, paused mutations, `resumePausedMutations` |
| Per-client focus / online / notify managers | not module-level singletons |
| A Flutter binding with four equal call styles | and no dependency beyond Flutter |
| Widget tests | the teardown is a documented snippet, not an export — see [Testing](../guides/testing.md) |

## Deliberately not in 0.1

Every row is recorded, with its reason, in
[`PORTING_NOTES.md`](https://github.com/KoTTi97/flutter_query/blob/main/packages/query_kit/test/PORTING_NOTES.md).
No omission is silent.

| Upstream | Here |
|---|---|
| Persistence and hydration (`hydrate`, `dehydrate`, `persister`, `isRestoring`) | not in 0.1; `Query.setState` is the door a persister would use |
| `notifyOnChangeProps`, `trackResult` | `select`, plus `buildWhen` on the builders and the keyless reads, mutations included |
| `throwOnError` | errors live in the sealed result (`QueryError`) |
| `queryKeyHashFn` | `QueryKey` is a value type |
| `structuralSharing` via `replaceEqualDeep` | deep value equality for lists, maps and sets, `==` for everything else, plus an optional `structuralSharing` hook |
| `useQueries`' heterogeneous tuple and its `combine` step | `QueriesObserver` is homogeneous; mixed data types need a `select`, and the returned list is mapped by the caller |
| `streamedQuery` | not ported |
| `experimental_prefetchInRender`, Suspense, `fetchOptimistic` | React-only, not ported |
| `select` on `fetchQuery` | map the future |
| `initialDataUpdatedAt` as a function | `initialDataUpdatedAtCompute`, a `DateTime? Function()` evaluated only when the data is actually seeded |
| SSR: `isServer`, `environmentManager`, `timeoutManager` | not ported |
| `MutationFunctionContext` | not ported; a mutation function takes its variables only |
| Callbacks in `setMutationDefaults` | not ported |
| Devtools | none — the showcase's `cache-inspector` screen is the stand-in |

## The divergences

Where the port deliberately behaves differently rather than not at all, the
divergence table at the end of PORTING_NOTES has the list and names the ticket
that decided each one. The ones you are most likely to notice:

- **Rebuilds are compared whole**, not per touched field — see [what
  rebuilds](../guides/rebuilds.md#why-not-upstreams-trick).
- **One key, one exact type**, where upstream casts blindly — see [the query
  client](../guides/the-query-client.md#reading-and-writing-the-cache).
- **`refetchMinBackgroundDuration`** suppresses a focus refetch after an
  absence too short to matter. Upstream always refetches; the default here is
  upstream's behaviour.
- **Two options shapes, not one.** `QueryObserverOptions<TData>` has no
  `select` and one type slot; `QuerySelectOptions<TQueryData, TData>` has a
  required one. Upstream's one object with an optional `select` let a
  literal without one infer its data type to `dynamic`; here that is a
  compile error — [ADR-0001](https://github.com/KoTTi97/flutter_query/blob/main/docs/adr/0001-one-type-slot-for-plain-queries.md).
- **Every filter parameter is a named `filters:`.**
- **A `Set` of listeners does not port.** Dart tear-offs compare equal
  (`watcher.onEvent == watcher.onEvent` is `true`, which is never true in JS),
  so upstream's `Set<TListener>` would silently drop a second subscription.
  Listeners are a `List` here, and one ported upstream assertion is flipped
  because of it — recorded, with the reasoning, in the notes.
