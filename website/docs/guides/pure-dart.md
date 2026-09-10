---
title: Without Flutter
sidebar_position: 10
description: Using query_kit on its own — observers, subscribe, and the one thing you have to do yourself.
---

# Without Flutter

`query_kit` has no Flutter dependency. A CLI, a server, a shared package, a
`dart:io` daemon — the cache works the same in all of them; what the Flutter
binding adds is the widget plumbing.

## Imperative

```dart
final client = QueryClient();
client.mount();

final sensors = await client.query<List<Sensor>>(
  QueryOptions<List<Sensor>>(
    queryKey: QueryKey(<Object?>['sensors']),
    queryFn: (context) => api.listSensors(signal: context.signal),
    staleTime: const StaleTime.duration(Duration(seconds: 45)),
  ),
);
```

## Reactive

```dart
final observer = client.observe<Sensor, Sensor>(
  QueryObserverOptions<Sensor, Sensor>(
    queryKey: QueryKey(<Object?>['sensors', id]),
    queryFn: (context) => api.getSensor(id, signal: context.signal),
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

`client.observeInfinite` is the same for an infinite query. `QueriesObserver`
observes a list; `MutationObserver` and `MutationStateObserver` are the write
side.

## What you have to do yourself

**`client.mount()` at start-up.** The Flutter binding mounts the client it is
given; in pure Dart it is your call, and without it nothing reacts to focus or
to the network coming back: no `refetchOnWindowFocus`, no
`refetchOnReconnect`, no resuming of paused mutations, and a `query` that
paused offline waits for a reconnect only while mounted.

**`client.clear()` at the end.** A client owns `gcTime` timers, and a process
with a pending timer does not exit.

**Focus and online, if they mean anything to you.** There is no window and no
connectivity plugin outside Flutter, so `client.focusManager.setFocused(…)`
and `client.onlineManager.setOnline(…)` are yours to drive — or to leave
alone, in which case the client stays focused and online, which is upstream's
behaviour with no listener.

## Where it runs

The core is tested on the Dart VM **and** compiled to JavaScript, both in CI,
because a cache full of timers and microtasks is exactly the sort of code where
the two disagree. Timers are clamped to 2^31−1 ms so a 30-day `gcTime` does not
fire immediately on the web.

## What is Dart rather than JavaScript

The port follows upstream's behaviour, not its type tricks. The differences you
feel at the call site:

- **Two type parameters, not five.** `Query<TQueryData>` at the cache layer,
  `QueryObserver<TQueryData, TData>` where `select` needs a second. There is no
  `TError` — errors are `Object` plus a `StackTrace` — and no `TQueryKey`.
- **`QueryKey` is a value type**, deep-frozen with structural equality, not a
  hashed string. `queryKeyHashFn` is gone; the hash survives as `debugString`.
- **One key, one exact type** — see [the query
  client](the-query-client.md#reading-and-writing-the-cache).
- **Every option union is a sealed value type** — see [options](options.md).
- **Cancellation is `QueryCancelToken.onCancel`**, because Dart has no
  ecosystem-wide cancellation primitive.
- **Time goes through `package:clock`**, so `fake_async` controls it
  completely.

The full name map is [coming from React
Query](../reference/coming-from-react-query.md).
