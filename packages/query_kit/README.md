# query_kit

TanStack Query for Dart: a cache for server state that knows when data is
stale, refetches it in the background, retries, cancels, deduplicates
requests, and runs mutations and infinite queries — with **no Flutter
dependency**. In a Flutter app, use
[`query_kit_flutter`](https://pub.dev/packages/query_kit_flutter), which
re-exports all of this.

> **AI-coded.** query_kit is an entirely AI-coded project: all code, tests
> and documentation were written by AI coding agents (Anthropic's Claude). A
> human maintainer set the goals and reviews releases, but did not write the
> code.
>
> **A port, not affiliated.** The behaviour is
> [TanStack Query](https://tanstack.com/query)'s, and upstream's own test
> suite is ported case by case — every case left out is listed with its
> reason — and run against this code, with thanks to Tanner Linsley and the
> TanStack team. This package is not affiliated with,
> endorsed by or connected to them; please take problems to
> [this repository's issues](https://github.com/KoTTi97/flutter_query/issues),
> not to TanStack.

## Install

```bash
dart pub add query_kit
```

Dart SDK 3.6 or later. In a Flutter app, add `query_kit_flutter` instead
(`flutter pub add query_kit_flutter`); it brings this package with it.

## Quick start

### Create a client

One `QueryClient` holds the cache. Mounting it lets it react to the focus
and connectivity changes its `focusManager` and `onlineManager` report —
refetch on focus and on reconnect, resume paused mutations. The Flutter
binding mounts the client and feeds both managers for you; in pure Dart
nothing reports a change until you do (`client.onlineManager.setOnline`).

```dart snippet="packages/query_kit/README.md#setup"
final client = QueryClient();
client.mount(); // react to focus and connectivity changes
```

### A first query

A query is a key plus a function that fetches. Read it once, or observe it
and hear about every change:

```dart snippet="packages/query_kit/README.md#first-query"
// Imperative: fetch and cache, completing with the data.
final tasks = await client.query<List<Task>>(
  QueryOptions<List<Task>>(
    queryKey: QueryKey(<Object?>['tasks']),
    queryFn: (context) => api.listTasks(signal: context.signal),
    staleTime: const StaleTime.duration(Duration(seconds: 45)),
  ),
);

// Reactive: an observer that keeps a widget (or anything) up to date.
final observer = client.observe<Task, Task>(
  QueryObserverOptions<Task>(
    queryKey: QueryKey(<Object?>['tasks', id]),
    queryFn: (context) => api.getTask(id, signal: context.signal),
  ),
);

final unsubscribe = observer.subscribe((result) {
  switch (result) {
    case QueryPending():
      print('loading');
    case QuerySuccess(:final data):
      print(data.name);
    case QueryError(:final error, :final staleData):
      print('$error (still showing ${staleData?.name})');
  }
});
```

The result is a **sealed** type, so the `switch` is exhaustive and the data
needs no `!`. A `QueryError` still carries the last good data, which is what
makes stale-while-revalidate readable.

### A first mutation

A mutation changes something on the server. Invalidating the list afterwards
marks it stale and refetches it for everyone observing it:

```dart snippet="packages/query_kit/README.md#first-mutation"
final addTask = MutationObserver(
  client,
  MutationOptions.simple(
    mutationFn: api.addTask,
    // Mark the list stale and refetch it for whoever is watching.
    onSuccess: (_, __, ___) => client.invalidateQueries(
      filters: QueryFilters(queryKey: QueryKey(<Object?>['tasks'])),
    ),
  ),
);

await addTask.mutateAsync('Write the release notes');
```

### Cleaning up

A client owns timers (unused entries are garbage-collected after `gcTime`),
so a command-line program ends by letting its observers go and clearing the
cache:

```dart snippet="packages/query_kit/README.md#cleanup"
unsubscribe();
client.unmount();
client.clear(); // empties the cache and cancels its timers
```

Unsubscribe (or `destroy()`) observers first: an observer with a
`refetchInterval` keeps polling into a cleared cache.

## Features

- **Caching with staleness.** `staleTime` decides when data is old, `gcTime`
  when an unused entry goes; stale data is shown while it is refreshed.
- **Request deduplication.** Every caller of the same key shares one fetch.
- **Background refetching** on focus, on reconnect, on an interval, and after
  invalidation.
- **Retries** with exponential backoff, and **cancellation** through
  `QueryCancelToken`, whose `onCancel` hook wires into `dio`'s `CancelToken`
  or any other client that can abort a request.
- **Mutations** with `onMutate` / `onSuccess` / `onError` / `onSettled`,
  optimistic updates and rollback, serialised writes through
  `MutationScope`, and paused mutations that resume when you are back online.
- **Infinite queries** with `fetchNextPage` / `fetchPreviousPage` and
  `maxPages`.
- **Initial and placeholder data**, `select` to derive what a reader sees,
  and **structural sharing**, so an unchanged refetch keeps your lists and
  maps — and, through `StructurallyShareable`, your own classes.
- **Lists and combinations of queries**: `QueriesObserver` for a dynamic
  list, and `(a, b).combine(…)` for results of different types.
- **Cache-wide state**: `isFetching`, `isMutating`, `MutationStateObserver`,
  and direct reads and writes with `getQueryData` / `setQueryData`.
- **Dart-first types**: sealed results, sealed option values (`StaleTime`,
  `RetryPolicy`, `Enabled`, …) instead of magic numbers, and `QueryKey` as a
  value type. A key is bound to one data type, and a mismatched read throws
  a `QueryDataTypeError` naming both types.
- **Testable**: time goes through `package:clock`, so `fake_async` controls
  every timer.

Not in 1.0: persistence and hydration, `streamedQuery`, server-side
rendering and devtools.

## Learn more

- [Overview](https://kotti97.github.io/flutter_query/docs/overview) and
  [important defaults](https://kotti97.github.io/flutter_query/docs/important-defaults)
- [Using the core without Flutter](https://kotti97.github.io/flutter_query/docs/guides/pure-dart)
- [Queries](https://kotti97.github.io/flutter_query/docs/guides/queries),
  [query keys](https://kotti97.github.io/flutter_query/docs/guides/query-keys),
  [mutations](https://kotti97.github.io/flutter_query/docs/guides/mutations)
  and [infinite queries](https://kotti97.github.io/flutter_query/docs/guides/infinite-queries)
- [Coming from React Query](https://kotti97.github.io/flutter_query/docs/coming-from-react-query):
  the JavaScript names and their Dart counterparts
- [Differences from TanStack Query](https://kotti97.github.io/flutter_query/docs/reference/differences-from-tanstack)
- [Troubleshooting](https://kotti97.github.io/flutter_query/docs/reference/troubleshooting)
- [API reference](https://pub.dev/documentation/query_kit/latest/)
- A runnable tour: [`example/example.dart`](https://github.com/KoTTi97/flutter_query/blob/main/packages/query_kit/example/example.dart)

## License and credits

MIT. query_kit is a port of [TanStack Query](https://tanstack.com/query) by
Tanner Linsley and contributors, whose MIT notice is kept in
`LICENSE-TANSTACK`. Bugs and questions go to
[the issue tracker](https://github.com/KoTTi97/flutter_query/issues).
