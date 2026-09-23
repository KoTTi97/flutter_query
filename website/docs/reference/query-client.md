---
title: QueryClient
description: Every member of QueryClient — constructor, reads, writes, bulk operations, defaults and lifecycle — with its signature and what it does.
---

# QueryClient

[`QueryClient`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient-class.html)
owns the caches and everything imperative: fetching, reading and writing
cached data, invalidating, cancelling. Create one per app (or one per test)
and keep it for as long as the app runs — the cache lives in it. In Flutter
it goes into a [`QueryClientProvider`](widgets-and-controllers.md#queryclientprovider),
which mounts it; in pure Dart you call `mount()` yourself (see [without
Flutter](../guides/pure-dart.md)).

A typical setup, in `lib/main.dart`, with a cache-wide error hook for the
app's logger:

```dart snippet="reference/query-client.md#setup"
final QueryClient appClient = QueryClient(
  queryCache: QueryCache(
    onError: (error, stackTrace, query) => log.warning(
      'query ${query.queryKey.debugString} failed',
      error,
      stackTrace,
    ),
  ),
  defaultOptions: const DefaultOptions(
    queries: QueryDefaults(
      staleTime: StaleTime.duration(Duration(seconds: 30)),
    ),
  ),
);
```

Every method that takes filters takes them as a named `filters:` argument, a
[`QueryFilters`](caches-and-observers.md#filters) (or `MutationFilters`).
The empty filter matches everything.

Where a member's TanStack Query name differs from the Dart one, the table
says so at the end of the row; a member without such a note has the same
name in TanStack Query.

## Constructor and fields

| Member | Type | Default | What it is |
|---|---|---|---|
| `QueryClient({queryCache, mutationCache, defaultOptions, focusManager, onlineManager, notifyManager})` | | a fresh instance of each; `defaultOptions` empty | Every collaborator is optional. Pass your own caches to install cache-wide callbacks. TanStack: `new QueryClient(config)`, whose config takes no managers. |
| [`queryCache`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/queryCache.html) | `QueryCache` | | Every query, keyed by `QueryKey`. Subscribe to it for [cache events](caches-and-observers.md#querycache). TanStack: `getQueryCache()`. |
| [`mutationCache`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/mutationCache.html) | `MutationCache` | | Every mutation, in submission order. TanStack: `getMutationCache()`. |
| [`focusManager`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/focusManager.html) | `AppFocusManager` | | Whether the app is in the foreground. The Flutter binding drives it from the app lifecycle. TanStack: the module-level `focusManager`. |
| [`onlineManager`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/onlineManager.html) | `OnlineManager` | | Whether the device is believed online. The binding drives it from `QueryClientProvider.onlineStatus`. TanStack: the module-level `onlineManager`. |
| [`notifyManager`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/notifyManager.html) | `NotifyManager` | | Batches this client's listener notifications. Pass `NotifyManager.shared` to batch across clients. TanStack: the module-level `notifyManager`. |

The three managers belong to the client rather than to the module, so two
clients — two tests — never share focus, connectivity or batching state.

## Fetching

| Method | Returns | What it does |
|---|---|---|
| [`query<T>(options, {revalidateIfStale = false})`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/query.html) | `Future<T>` | Takes a `QueryOptions<T>`. Returns cached data if it is fresh under the options' `staleTime`; otherwise fetches (or joins the fetch in flight), caches and completes with the data. A failed fetch fails the future. **No retries unless `retry` is set** on the options or in the defaults. With `revalidateIfStale`, cached data is returned at once while a stale query refreshes in the background, and the future fails only when nothing is cached. When the call creates the entry or starts a fetch, the options become the query's options (with `retry` unset, the query keeps its own); served from the cache or joining a fetch in flight, they are not applied. |
| [`infiniteQuery<P, Q>(options, {revalidateIfStale = false})`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/infiniteQuery.html) | `Future<InfiniteData<P, Q>>` | The same for an `InfiniteQueryOptions<P, Q>`: the first page, or `options.pages` pages. |
| [`observe<TQueryData, TData>(options)`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/observe.html) | `QueryObserver<TQueryData, TData>` | Creates an observer on this client — the same as `QueryObserver(client, options)`. It does nothing until subscribed; the caller owns it. TanStack: `new QueryObserver(client, options)`. |
| [`observeInfinite<P, Q, TData>(options)`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/observeInfinite.html) | `InfiniteQueryObserver<P, Q, TData>` | The infinite twin of `observe`. TanStack: `new InfiniteQueryObserver(client, options)`. |

TanStack Query's `query` and `infiniteQuery` replace its deprecated
`fetchQuery`, `prefetchQuery` and `ensureQueryData` (and their infinite
twins); this package has only the new pair. To prefetch, `.ignore()` the
future; to fetch only when nothing is cached, pass `staleTime:
StaleTime.static`; to reshape the result, `await` and map it — there is no
`select` here. See [prefetching](../guides/prefetching.md).

## Reading

| Method | Returns | What it does |
|---|---|---|
| [`getQueryData<T>(key)`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/getQueryData.html) | `T?` | The cached data, stale or not, or `null`. Neither fetches nor subscribes. Throws `QueryDataTypeError` if the entry holds another type. |
| [`getInfiniteQueryData<P, Q>(key)`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/getInfiniteQueryData.html) | `InfiniteData<P, Q>?` | `getQueryData` for an infinite query. TanStack: `getQueryData`. |
| [`getQueryState<T>(key)`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/getQueryState.html) | `QueryState<T>?` | The entry's whole [state](results.md): status, fetch status, timestamps, counters. Throws `QueryDataTypeError` on a type mismatch. |
| [`getQueriesData<T>({required filters})`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/getQueriesData.html) | `List<(QueryKey, T?)>` | The data of every matching entry, `null` where one holds none yet. Throws `QueryDataTypeError` if any match holds another type. |
| [`isFetching({filters})`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/isFetching.html) | `int` | How many matching queries are fetching right now (not paused). A `fetchStatus` in the filters is ignored. |
| [`isMutating({filters})`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/isMutating.html) | `int` | How many matching mutations are pending, callbacks included. A `status` in the filters is ignored. Takes a `MutationFilters`. |

## Writing

| Method | Returns | What it does |
|---|---|---|
| [`setQueryData<T>(key, data, {updatedAt})`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/setQueryData.html) | `T` | Writes `data`, creating the entry if needed; it counts as freshly fetched (`updatedAt`, default now). An existing entry takes any value its type can hold; otherwise `QueryDataTypeError`. Returns what the cache now holds, after structural sharing. A bare `setQueryData(key, null)` writes nothing; name the nullable type to store `null`. TanStack: `setQueryData(key, value)`. |
| [`updateQueryData<T>(key, updater, {updatedAt})`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/updateQueryData.html) | `T?` | `updater` receives the current data (or `null`) and returns the new data; returning `null` writes nothing and returns `null`. Throws `QueryDataTypeError` when the held data is not a `T` or the entry cannot hold what the updater returned. TanStack: `setQueryData(key, updater)`. |
| [`updateQueriesData<T>(updater, {required filters, updatedAt})`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/updateQueriesData.html) | `List<(QueryKey, T?)>` | The same over every match, in one batch. Every updater runs, and every type is checked, before anything is written, so an updater that reads another matched key sees it unwritten. TanStack: `setQueriesData`. |

See [updates from mutation responses](../guides/updates-from-mutation-responses.md)
and [optimistic updates](../guides/optimistic-updates.md).

## Operating on many queries

All five take `filters` (default: every query). The four that return a future
report a throwing filter predicate by failing the future, and their refetch
failures land in the queries' states, not in the future.

| Method | Returns | What it does |
|---|---|---|
| [`invalidateQueries({filters, refetchType, cancelRefetch = true})`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/invalidateQueries.html) | `Future<void>` | Marks the matches stale, then refetches those `refetchType` names — a `RefetchType` (`active`, `inactive`, `all`, `none`); unset, the filter's own `type`, else the active ones. `RefetchType.none` only marks. The matched set is fixed before marking. |
| [`refetchQueries({filters, cancelRefetch = true})`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/refetchQueries.html) | `Future<void>` | Refetches the matches, stale or not. Skipped: a query none of whose observers is enabled, an unobserved query that has never fetched, and one an observer marks `StaleTime.static`. Does not wait for a fetch paused for the network. |
| [`cancelQueries({filters, revert = true, silent = false})`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/cancelQueries.html) | `Future<void>` | Cancels matching fetches in flight and completes when they have settled. `revert` puts each query back to its state before the fetch; `silent` cancels without dispatching an error. A failed cancellation never fails the future. |
| [`resetQueries({filters, cancelRefetch = true})`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/resetQueries.html) | `Future<void>` | Puts the matches back to their initial state (initial data included), then refetches the active ones. |
| [`removeQueries({filters})`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/removeQueries.html) | `void` | Removes the matches from the cache, cancelling their fetches silently. For keys nobody watches; an observer stays on the removed entry. |

`cancelRefetch: true` restarts a fetch already in flight on a query that
holds data, and joins it on one that does not; `false` always joins. See
[query invalidation](../guides/query-invalidation.md) and
[filters](../guides/filters.md).

## Defaults

| Member | Returns | What it does |
|---|---|---|
| [`getDefaultOptions()`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/getDefaultOptions.html) | `DefaultOptions` | The client-wide defaults in force. |
| [`setDefaultOptions(options)`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/setDefaultOptions.html) | `void` | Replaces them. Takes effect wherever options are resolved next; options a query already holds are not changed. |
| [`setQueryDefaults(key, defaults)`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/setQueryDefaults.html) | `void` | Defaults for every query whose key starts with `key`. The same key again replaces them. |
| [`getQueryDefaults(key)`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/getQueryDefaults.html) | `QueryDefaults?` | Every registration matching `key`, merged in the order the keys were first registered (registering a key again replaces its defaults but keeps its place), the later winning per field; `null` when none matches. The client-wide defaults are not included. |
| [`setMutationDefaults(key, defaults)`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/setMutationDefaults.html) | `void` | The mutation twin. Carries no callbacks. |
| [`getMutationDefaults(key)`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/getMutationDefaults.html) | `MutationDefaults?` | The mutation twin of `getQueryDefaults`. |
| [`defaultQueryOptions(options)`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/defaultQueryOptions.html) | `DefaultedQueryOptions<T>` | The options with every unset field filled in: what a query actually runs with. Throws `ArgumentError` when both `initialDataUpdatedAt` forms are set. Rarely needed outside a test. |
| [`defaultQueryObserverOptions(options)`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/defaultQueryObserverOptions.html) | `DefaultedQueryObserverOptions<TQueryData, TData>` | The same for observer options, observer fields included. TanStack: `defaultQueryOptions`. |
| [`defaultMutationOptions(options)`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/defaultMutationOptions.html) | `DefaultedMutationOptions<TData, TVariables, TOnMutateResult>` | The same for mutation options. Throws `ArgumentError` when both `mutationFn` and `mutationFnWithContext` are set. |
| [`infiniteObserverOptions(options)`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/infiniteObserverOptions.html) | `QueryObserverOptionsBase<InfiniteData<P, Q>, TData>` | Turns infinite observer options into the options an `InfiniteQueryObserver.setOptions` takes; `setInfiniteOptions` on the observer is the shorter way. No TanStack counterpart. |

The three defaults classes:

| Class | Fields |
|---|---|
| [`DefaultOptions`](https://pub.dev/documentation/query_kit/latest/query_kit/DefaultOptions-class.html) | `queries` (`QueryDefaults?`), `mutations` (`MutationDefaults?`). |
| [`QueryDefaults`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryDefaults-class.html) | `queryFn`, `structuralSharing`, `enabled`, `staleTime`, `gcTime`, `retry`, `retryDelay`, `retryOnMount`, `networkMode`, `refetchOnMount`, `refetchOnWindowFocus`, `refetchOnReconnect`, `refetchInterval`, `refetchIntervalInBackground`, `meta`. TanStack: `DefaultOptions.queries`. |
| [`MutationDefaults`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationDefaults-class.html) | `mutationFn`, `retry`, `retryDelay`, `networkMode`, `gcTime`, `scope`, `meta`. TanStack: `DefaultOptions.mutations`, which also takes callbacks. |

Each field means what the [option](query-options.md) of the same name means.
`queryFn`, `structuralSharing` and `mutationFn` are typed on `Object?`,
because one default serves every type under a key prefix; the result is
checked against the reader's type and a mismatch throws
`QueryDataTypeError`. `initialData`, `placeholderData` and `select` belong to
one query and have no default. All three classes are `const`, compare by
value (functions by `==`, so a closure equals only itself), and `QueryDefaults` and `MutationDefaults`
have `mergedWith(other)`, which lays `other`'s set fields over these. See
[default query function](../guides/default-query-function.md).

## Lifecycle

| Method | What it does |
|---|---|
| [`mount()`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/mount.html) | Starts listening to focus and connectivity: focus and reconnect refetches, resuming paused mutations (first, and the queries wait for them). Counted: two mounts need two unmounts. `QueryClientProvider` mounts its client. |
| [`unmount()`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/unmount.html) | Stops listening. Does not touch the caches. An unmount without a mount does nothing. |
| [`clear()`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/clear.html) | Empties both caches, cancelling fetches and every `gcTime` timer. Observers are not stopped — destroy them first. A pending mutation dropped here fails, and its callbacks run a few microtasks later; see [testing](../guides/testing.md) for the teardown that allows for it. |
| [`resumePausedMutations()`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/resumePausedMutations.html) | Returns a `Future<void>`. Resumes every paused mutation that can run now and completes when they have settled. The gate is each mutation's own network mode; TanStack Query instead skips the whole call while offline. |

## Not here

`getQueryCache()` and `getMutationCache()` are fields, and the deprecated
`fetchQuery`, `prefetchQuery` and `ensureQueryData` family is covered by
`query`. Persistence (`hydrate`, `dehydrate`), `isRestoring` and
`queryKeyHashFn` are not in 1.0; see the [feature matrix](feature-matrix.md).
