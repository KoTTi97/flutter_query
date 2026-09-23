---
title: Debugging
description: There are no devtools — what the cache can tell you instead, by subscribing to its events or reading its entries.
---

{/* depth: todo */}
{/* demo: cache-inspector, diagnostics */}

# Debugging

There is no devtools panel. The cache can tell you everything one would show,
though: every entry, its state and its observers.

## Listening to the cache

`queryCache.subscribe` reports every change as a `QueryCacheEvent`:

```dart snippet="guides/debugging.md#subscribe"
void Function() logCacheEvents(QueryClient client) =>
    client.queryCache.subscribe((event) {
      final key = event.query.queryKey.debugString;
      switch (event) {
        case QueryAdded():
          debugPrint('added $key');
        case QueryRemoved():
          debugPrint('removed $key');
        case QueryUpdated():
          final state = event.query.state;
          debugPrint('$key: ${state.status} / ${state.fetchStatus}');
        default:
          break;
      }
    });
```

The function it returns unsubscribes. The events are `QueryAdded`,
`QueryRemoved`, `QueryUpdated`, `QueryObserverAdded`, `QueryObserverRemoved`,
`QueryObserverOptionsUpdated` and `QueryObserverResultsUpdated`; the mutation
cache has its own `subscribe`. Call it once, at start-up, under
`kDebugMode`.

## Reading the cache

- `client.queryCache.queries` — every entry right now.
- `query.state` — `status`, `fetchStatus`, `dataUpdatedAt`, `error`,
  `consecutiveErrorCount`, `isInvalidated`.
- `query.observersCount` — how many readers hold it. An entry with none is
  waiting for garbage collection.
- `query.isStale()` — whether the next trigger would refetch it.
- `key.debugString` — the key, readable.

A screen that lists these is a devtools of your own; the `cache-inspector`
screen in the [examples](../examples/index.md) is one, and `diagnostics`
shows the type errors and debug-build assertions the library raises.

## Common surprises

[Troubleshooting](../reference/troubleshooting.md) lists symptoms — a query
that refetches on every build, a list that never releases, a
`QueryDataTypeError` for a type that looks right — each with its cause and
fix.
