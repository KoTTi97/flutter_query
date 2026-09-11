---
title: Coming from React Query
sidebar_position: 1
description: Every JavaScript name mapped to its Dart counterpart — reading a query, the client, options, infinite queries, mutations.
---

# Coming from TanStack Query (JS)

The behaviour is upstream's — the tests say so — but the surface is Dart's.
This page maps the JavaScript names to the ones here. The source of truth for
every deliberate difference is the divergence table at the end of
[`PORTING_NOTES.md`](https://github.com/KoTTi97/flutter_query/blob/main/packages/query_kit/test/PORTING_NOTES.md);
each row there names the ticket that decided it.

Two rules shape most of the table:

- **`null` means "not configured"** on every option field, so an option with a
  real "off" value is a sealed value type (`StaleTime`, `GcTime`, `Enabled`,
  `RetryPolicy`, `RetryDelay`, `RefetchOn`, `RefetchInterval`), never a magic
  number, string or boolean.
- **The result is a sealed type** — `QueryPending`, `QuerySuccess`,
  `QueryError` — so a `switch` is exhaustive and there is no `data!`. A
  `QueryError` still carries `staleData`.

## Reading a query

`useQuery` has no single counterpart. The binding offers four **equal**
alternatives — there is no recommended default, pick per situation:

| JS | Here |
|---|---|
| `useQuery(options)` in a component | `QueryBuilder<T>(options: …, builder: …)` |
| | `QueryController<TQueryData, TData>(client, options)` — a `ValueListenable` |
| | `with QueryMixin` on a `State`, then `watchQuery(options)` in `build` |
| | `context.query(options)` in any widget under a `QueryClientProvider` |
| `useInfiniteQuery` | `InfiniteQueryBuilder` / `InfiniteQueryController` / `watchInfiniteQuery` / `context.infiniteQuery` |
| `useMutation` | `MutationBuilder` / `MutationController` / `watchMutation` / `context.mutation` |
| `useQueryClient()` | `QueryClientProvider.of(context)` |
| `QueryClientProvider` | `QueryClientProvider(client: …, child: …)` |
| `new QueryObserver(client, options)` | `client.observe(options)` or `QueryObserver(client, options)` |

## The client

| JS | Here |
|---|---|
| `fetchQuery`, `prefetchQuery`, `ensureQueryData` | one `QueryClient.query(options)`; prefetch is `client.query(…).ignore()`, "only if nothing is cached" is `staleTime: StaleTime.static` |
| `ensureQueryData({ revalidateIfStale: true })` | `client.query(options, revalidateIfStale: true)` — cached data now, refresh behind it |
| `useQueries({ queries })` | `QueriesObserver` / `QueriesBuilder`, homogeneous: one data type per collection, `select` when the selected type differs. No `combine` — map the list |
| `useMutationState({ filters, select })` | `MutationStateObserver` / `MutationStateController` |
| `getQueryData<InfiniteData<…>>(key)` | `getInfiniteQueryData<TPage, TParam>(key)` |
| `fetchQuery({ select })` | none — `await` the future and map it |
| `setQueryData(key, value)` | `setQueryData(key, value)` |
| `setQueryData(key, updaterFn)` | `updateQueryData(key, (previous) => …)`; returning `null` leaves the cache untouched |
| `setQueriesData(filters, updaterFn)` | `updateQueriesData(updater, filters: QueryFilters(…))` — every filter parameter in the core is a named `filters:` |
| `getQueryData(key)` | `getQueryData<T>(key)` — a type mismatch throws `QueryDataTypeError` |
| a key read as a looser type (`number \| undefined` where `number` was cached) | throws too: one key, one exact type — `int` and `int?`, `List<Task>` and `List<Object?>` are different types, and `getQueriesData<T>` checks like `getQueryData<T>` |
| `invalidateQueries({ queryKey })` | `invalidateQueries(filters: QueryFilters(queryKey: …))` |
| `queryKeyHashFn` | gone: `QueryKey` is a value type with structural equality; `debugString` is the readable form |
| `focusManager`, `onlineManager`, `notifyManager` (module-level) | per-client instances: `client.focusManager`, `client.onlineManager`, `client.notifyManager` |
| `setMutationDefaults(key, { onSuccess, … })` | `MutationDefaults` carries `mutationFn`, `retry`, `retryDelay`, `networkMode`, `gcTime`, `scope`, `meta` — no callbacks |

## Options

| JS | Here |
|---|---|
| `queryKey: ['tasks', id]` | `QueryKey(['tasks', id])` |
| `queryFn: ({ signal }) => …` | `queryFn: (context) => …`; `context.signal` is a `QueryCancelToken`, and `signal.onCancel(…)` is the interop point for `dio` and friends |
| `enabled: false` | `Enabled.no` |
| `enabled: () => bool` | `Enabled.when((query) => …)` |
| `skipToken` | `Enabled.no` |
| `staleTime: 0` (the default) | `StaleTime.zero` |
| `staleTime: 30_000` | `StaleTime.duration(Duration(seconds: 30))` |
| `staleTime: Infinity` | `StaleTime.infinite` — never stale by time, still refetched when asked |
| `staleTime: 'static'` | `StaleTime.static` — never stale and skipped by every refetch trigger |
| `staleTime: (query) => …` | `StaleTime.dynamic((query) => …)` |
| `gcTime: 300_000` | `GcTime.duration(Duration(minutes: 5))` (`GcTime.defaultValue`) |
| `gcTime: Infinity` | `GcTime.never` |
| `retry: 3` | `RetryPolicy.times(3)` |
| `retry: false` / `retry: true` | `RetryPolicy.never` / `RetryPolicy.always` |
| `retry: (count, error) => bool` | `RetryPolicy.when((failureCount, error, stackTrace) => …)` |
| `retryDelay: 1000` | `RetryDelay.fixed(Duration(seconds: 1))`; the default backoff is `RetryDelay.exponential()` |
| `refetchOnWindowFocus: false` | `RefetchOn.never` |
| `refetchOnWindowFocus: true` | `RefetchOn.ifStale` |
| `refetchOnWindowFocus: 'always'` | `RefetchOn.always` |
| `refetchOnMount`, `refetchOnReconnect` | the same `RefetchOn` values |
| `refetchInterval: 5000` | `RefetchInterval.every(Duration(seconds: 5))` |
| `refetchInterval: false` | `RefetchInterval.off` |
| `refetchInterval: (query) => …` | `RefetchInterval.dynamic((query) => …)` |
| `networkMode: 'online'` | `NetworkMode.online` (also `always`, `offlineFirst`) |
| `initialData: value` | `InitialData.value(value)` |
| `initialData: () => value \| undefined` | `InitialData.compute(() => …)`; returning `null` means "none", while `InitialData.value(null)` is a value of `null` |
| `initialDataUpdatedAt: number` | `initialDataUpdatedAt: DateTime?` |
| `initialDataUpdatedAt: () => number` | `initialDataUpdatedAtCompute: () => DateTime?` — evaluated only when data is actually seeded; `null` means now. Give one form or the other, never both |
| `placeholderData: value` / `(previous) => …` | `PlaceholderData.value(…)` / `PlaceholderData.compute(…)` |
| `placeholderData: keepPreviousData` | `const PlaceholderData.keepPrevious()` |
| `select: (data) => …` | its own options shape: `QuerySelectOptions<TQueryData, TData>`, `select` required. Without one, `QueryObserverOptions<TData>` has a single type argument |
| `notifyOnChangeProps` | gone: `select` narrows what is reported, and the builders take `buildWhen` |
| `throwOnError` | gone: errors are the `QueryError` case of the sealed result |
| `structuralSharing` | on by default: lists are shared element by element, maps and sets whole when deep-equal, everything else by `==`, so typed models need `==`/`hashCode`; `structuralSharing: (previous, next) => …` replaces it for the cache write |
| `structuralSharing: false` | `structuralSharing: (_, next) => next` |
| `queryCache.find({ queryKey })` | `queryCache.find(filters: QueryFilters(queryKey: …))` — exact by default, as upstream; `exact: false` for a prefix |

## Infinite queries

| JS | Here |
|---|---|
| `queryFn: ({ pageParam }) => page` | `pageFn: (context) => page`, where `InfinitePageContext` carries `pageParam` and `direction` |
| `initialPageParam`, `getNextPageParam`, `getPreviousPageParam` | the same names on `InfiniteQueryOptions` |
| `data.pages`, `data.pageParams` | `InfiniteData.pages`, `InfiniteData.pageParams` |
| `hasNextPage`, `fetchNextPage()` on the result | on `InfiniteQueryObserver` / `InfiniteQueryController`; the sealed result keeps one shape |

## Mutations

| JS | Here |
|---|---|
| `mutationFn: (variables, context) => …` | `mutationFn: (variables) => …` — `MutationFunctionContext` is not ported |
| `mutate(vars, { onSuccess })` | `mutate(vars, callbacks: MutateCallbacks(onSuccess: …))` |
| `mutateAsync(vars)` | `mutateAsync(vars)` |
| `onMutate` returning rollback context | `onMutate` returning `TOnMutateResult`, the observer's third type parameter |
| `useMutation` without `onMutate` | `MutationOptions.simple(mutationFn: …)` — fixes the third type parameter to `void`, so the other two infer from `mutationFn` |
| `result.context` (what `onMutate` returned, on the mutation result) | not on `MutationResult`: its job is the rollback, which `onError` and `onSettled` receive as their last argument |

## See it running

Every row above has a screen in [the showcase](../project/examples.md)
that shows the behaviour on a real backend, with widget tests and end-to-end
tests that prove it. Open the app and pick the feature, or read the screen's
file — each starts with what it shows and how it is proven:

| Topic | Screen |
|---|---|
| reading a query, the four call styles | `simple`, `four-call-styles` |
| `select`, `buildWhen`, structural sharing | `select-and-sharing` |
| `initialData`, `placeholderData` | `initial-and-placeholder` |
| `staleTime`, `gcTime` | `stale-and-gc`, `cache-inspector` |
| `enabled` | `dependent-queries` |
| the client's imperative surface, filters | `invalidation-and-filters`, `prefetching`, `default-query-function` |
| infinite queries | `load-more`, `max-pages`; `pagination` for the page-numbered shape |
| mutations, optimistic updates | `mutations`, `optimistic-updates`, `playground` |
| retries, cancellation | `retry`, `cancellation` |
| `refetchInterval`, focus, online | `auto-refetching`, `focus-refetch`, `offline` |
| cache callbacks, `meta` | `global-callbacks` |
| a list of queries (`useQueries`) | `query-collections` |
| cache-wide mutation state (`useMutationState`) | `mutation-state` |
| the provider's knobs — `QueryClientProvider.create`, `isAppShown`, `initialOnlineStatus`, `maybeOf` | `focus-refetch` |
| the errors the port adds — `QueryDataTypeError`, `MissingMutationFunctionError` | `diagnostics` |

## Not here at all

Persistence and hydration, `useQueries`' `combine` step, `streamedQuery`,
Suspense, SSR and
devtools are out of the first release; [the feature matrix](feature-matrix.md)
lists them, and [`PORTING_NOTES.md`](https://github.com/KoTTi97/flutter_query/blob/main/packages/query_kit/test/PORTING_NOTES.md)
records the reason for each.
