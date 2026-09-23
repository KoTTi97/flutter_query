---
title: Without Flutter
description: Using query_kit on its own — observers, subscribe, and the one thing you have to do yourself.
---

# Without Flutter

`query_kit` has no Flutter dependency. A CLI, a server, a shared package, a
`dart:io` daemon — the cache works the same in all of them; what the Flutter
binding adds is the widget plumbing.

## Imperative

```dart snippet="guides/pure-dart.md#imperative"
final client = QueryClient();
client.mount();

final tasks = await client.query<List<Task>>(
  QueryOptions<List<Task>>(
    queryKey: QueryKey(<Object?>['tasks']),
    queryFn: (context) => api.listTasks(signal: context.signal),
    staleTime: const StaleTime.duration(Duration(seconds: 45)),
  ),
);
```

## Reactive

```dart snippet="guides/pure-dart.md#observe"
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

The result is the same sealed `QueryResult` a Flutter widget switches over;
the binding's readers are this observer with a widget's lifetime around it.
The *Simple* example is that Flutter version of one query: press the refetch
button and watch the post stay on screen while the *refreshing* pill shows
and the strip's `fetches` goes up — every one of those facts is a field of
the result above.

<LiveDemo feature="simple" />

`client.observeInfinite` is the same for an infinite query. `QueriesObserver`
observes a list; `MutationObserver` and `MutationStateObserver` are the write
side.

## What you have to do yourself

**`client.mount()` at start-up.** The Flutter binding mounts the client it is
given; in pure Dart it is your call, and without it nothing reacts to focus or
to the network coming back: no `refetchOnWindowFocus`, no
`refetchOnReconnect`, no resuming of paused mutations, and a `query` that
paused offline waits for a reconnect only while mounted.

**`client.clear()` at the end — and unsubscribe the observers first.** A
client owns `gcTime` timers, and a process with a pending timer does not exit.
`clear()` empties the caches but does not stop observers: a subscribed
observer with a `refetchInterval` keeps its timer across `clear()` and rebuilds
its query on the next tick, so an observer you created is yours to unsubscribe
or `destroy()` before the client is cleared.

**Focus and online, if they mean anything to you.** There is no window and no
connectivity plugin outside Flutter, so `client.focusManager.setFocused(…)`
and `client.onlineManager.setOnline(…)` are yours to drive — or to leave
alone, in which case the client stays focused and online.

## Where it runs

The core is tested on the Dart VM **and** compiled to JavaScript,
because a cache full of timers and microtasks is exactly the sort of code where
the two disagree. Timers are clamped to 2^31−1 ms so a 30-day `gcTime` does not
fire immediately on the web.

## What is Dart rather than JavaScript

The core follows TanStack Query's behaviour, not its type tricks. The differences you
feel at the call site:

- **Two type parameters, not five.** `Query<TQueryData>` at the cache layer,
  `QueryObserver<TQueryData, TData>` where `select` needs a second. There is no
  `TError` — errors are `Object` plus a `StackTrace` — and no `TQueryKey`.
- **`QueryKey` is a value type**, deep-frozen with structural equality, not a
  hashed string. `queryKeyHashFn` is gone; the hash survives as `debugString`.
- **One key, one exact type** — see [type safety in
  Dart](../dart-type-safety.md#one-key-one-exact-type).
- **Every option union is a sealed value type** — see [describing a query
  once](query-options.md).
- **Cancellation is `QueryCancelToken.onCancel`**, because Dart has no
  ecosystem-wide cancellation primitive.
- **Time goes through `package:clock`**, so `fake_async` controls it
  completely.

The full name map is [coming from React
Query](../coming-from-react-query.md), and the behaviour that differs is in
[differences from TanStack Query](../reference/differences-from-tanstack.md).
