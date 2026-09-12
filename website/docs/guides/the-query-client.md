---
title: The query client
sidebar_position: 6
description: One QueryClient.query instead of three, filters, cache writes, defaults, cancellation, and the mount contract.
---

# The query client

`QueryClient` owns the two caches and the per-client managers. Everything
imperative goes through it.

## Fetching: one method, not three

Upstream has `fetchQuery`, `prefetchQuery` and `ensureQueryData`, all three now
deprecated there. Here it is one:

```dart snippet="guides/the-query-client.md#imperative"
final tasks = await client.query<List<Task>>(
  QueryOptions<List<Task>>(
    queryKey: tasksKey,
    queryFn: (context) => api.listTasks(signal: context.signal),
  ),
);
```

| You want | Write |
|---|---|
| fetch and await | `await client.query(options)` |
| prefetch, don't wait | `client.query(options).ignore()` |
| only if nothing is cached | `staleTime: StaleTime.static` |
| cached data now, refresh behind it | `client.query(options, revalidateIfStale: true)` |

The last one is stale-while-revalidate as an imperative call: cached data comes
back at once while a stale entry refreshes behind it; with nothing cached, the
fetch is awaited as usual.

`QueryClient.query` also accepts `InfiniteQueryOptions`, because an
`InfiniteQueryOptions` carries its own paging behaviour.

## Filters

**Every filter parameter in the core is a named `filters:`.** That is a
deliberate divergence from upstream's positional object, and it makes the call
sites read the same everywhere.

```dart snippet="guides/the-query-client.md#filters"
client.invalidateQueries(filters: QueryFilters(queryKey: tasksKey)).ignore();
client.removeQueries(
  filters: QueryFilters(queryKey: tasksKey, exact: true),
);
client
    .refetchQueries(filters: QueryFilters(type: QueryTypeFilter.active))
    .ignore();
client
    .resetQueries(
        filters: QueryFilters(predicate: (query) => query.isStale()))
    .ignore();
```

`QueryFilters` takes `queryKey` (a **prefix** unless `exact: true`), `exact`,
`type`, `stale`, `fetchStatus`, `status` and `predicate`. `MutationFilters` is
the same idea over the mutation cache.

One asymmetry worth knowing, and it is upstream's: `queryCache.find` defaults
to **exact**, while the bulk operations default to prefix.

## Reading and writing the cache

```dart snippet="excerpt: guides/the-query-client.md#cache-writes"
final tasks = client.getQueryData<List<Task>>(tasksKey);
client.setQueryData<Task>(taskKey(id), task);
client.updateQueryData<Task>(taskKey(id), (previous) => previous?.copyWith(…));
client.updateQueriesData<Task>((previous) => …, filters: QueryFilters(…));
```

`setQueryData` takes a **value**; the updater form is `updateQueryData`, and
returning `null` from it leaves the cache untouched. For an infinite query, the
typed read is `getInfiniteQueryData<TPageData, TPageParam>(key)`.

:::danger One key, one exact type
A key is bound to the data type it was first used with, and reading it as any
other type throws `QueryDataTypeError` — **related types included**. `int` and
`int?` are two types. So are `List<Task>` and `List<Object?>`.

Upstream casts blindly and cannot tell. Here `getQueryData<T>`,
`getQueriesData<T>`, `setQueryData<T>` and an observer's `TQueryData` all have
to agree with the key's first use. It is the single most likely thing to catch
you out when porting JavaScript, and it is catching a real bug.
:::

## Defaults

Two levels, and a key-specific default sits above the client-wide one:

```dart snippet="guides/the-query-client.md#defaults"
final client = QueryClient(
  defaultOptions: DefaultOptions(
    queries: QueryDefaults(
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
      retry: const RetryPolicy.times(2),
    ),
  ),
);

client.setQueryDefaults(
  QueryKey(<Object?>['tasks']),
  QueryDefaults(queryFn: (context) => api.listTasks()),
);
```

A `queryFn` registered per key is upstream's "default query function": options
without one derive the request from the key. `setMutationDefaults` is the
matching call for writes — everything except callbacks, which are not ported.

`Defaulted*Options` are distinct types, not a flag: only a `QueryClient` can
produce them, so nothing downstream can be handed half-resolved options.

## Cancellation

A query function receives `context.signal`, a `QueryCancelToken`. Dart has no
ecosystem-wide cancellation primitive, so `onCancel` is the interop point:

```dart snippet="prose-only: needs dio, which neither published package may depend on"
Future<List<Task>> listTasks(QueryFunctionContext context) {
  final token = CancelToken();                     // dio
  context.signal.onCancel(token.cancel);
  return dio.get<…>('/tasks', cancelToken: token).then(…);
}
```

`client.cancelQueries(filters: …)` cancels in flight. The defaults are
`revert: true, silent: false`: each query goes back to the state it held
before the fetch, `fetchStatus` `idle`, so a reader keeps the data it had, and
whoever awaited the fetch gets that data back — or a `CancelledError` when
there was none. `silent: true` is not the default: it means "a new fetch is
taking over", and a silently cancelled fetch that nothing replaces is put
back to `idle` too rather than left `fetching` forever.

## The mount contract

```dart snippet="guides/the-query-client.md#mount-contract"
client.mount(); // once, at start-up
client.unmount(); // to balance your own mount()
client.clear(); // at the end: drop the caches and their timers
```

Without a mount, **nothing** reacts to the app returning to the foreground or
the device coming back online: no `refetchOnWindowFocus`, no
`refetchOnReconnect`, no resuming of paused mutations, and a `query` that
paused offline waits for a reconnect only while mounted.

:::warning In Flutter, the provider owns this
`QueryClientProvider` mounts the client it is given and unmounts it again when
it goes. That count is what keeps focus and reconnect refetches wired, so **an
extra `unmount()` of your own unbalances it** and the client stops listening to
either. Call `unmount()` only to balance a `mount()` you made yourself.

`clear()` is still yours: the provider does not dispose the client, because a
`QueryClient` outlives the tree.
:::

## Per-client managers

`focusManager`, `onlineManager` and `notifyManager` are **instances on the
client**, not module-level singletons as in JavaScript. Two clients in one
process are genuinely independent — which is what makes a widget test able to
drive focus without touching its neighbours.

See [lifecycle and connectivity](lifecycle-and-connectivity.md).
