---
title: Debugging
description: There are no devtools — what the cache can tell you instead, by subscribing to its events, reading its entries, or putting a small inspector on screen.
---

# Debugging

"Why did this refetch?", "is this still cached?", "who is holding that
query?" — in React, the devtools panel answers these. query_kit has no
devtools package, but everything such a panel shows is public: every entry of
the cache, its state, its readers, and an event for every change. This page
turns that into a log line, a small on-screen inspector, and a list of what
the library throws when something is wrong.

## Listening to the cache

`client.queryCache.subscribe` calls you back with a `QueryCacheEvent` for
every change and returns the function that unsubscribes. Put it next to the
client, in `lib/main.dart`, under `kDebugMode`:

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

The events, each carrying the `query` it is about:

| Event | When |
|---|---|
| `QueryAdded` | an entry is created — by a reader, `client.query` or `setQueryData` |
| `QueryRemoved` | an entry leaves the cache — garbage collection, `removeQueries`, `clear` |
| `QueryUpdated` | the entry's state changed; its `action` says how (a fetch started, succeeded, failed, paused, was invalidated, …) |
| `QueryObserverAdded` / `QueryObserverRemoved` | a reader subscribed or left |
| `QueryObserverOptionsUpdated` | a reader was handed options that are not `==` to its last ones — with a `queryFn` closure written in the options, that is **every build** of that reader |
| `QueryObserverResultsUpdated` | a reader delivered a new result to its listeners |

The last two are about readers, not about the cache, and the first of them
usually fires on every rebuild: leave both out of a log, or it grows with
nobody touching the screen. `client.mutationCache.subscribe` is the same for
mutations, with `MutationAdded`, `MutationRemoved`, `MutationUpdated`,
`MutationObserverAdded`, `MutationObserverRemoved` and
`MutationObserverOptionsUpdated` — the last one only once the reader has run
a mutation; there is no results event on the mutation side. The full lists,
with the actions, are on [caches and
observers](../reference/caches-and-observers.md).

Only a log? The cache-wide callbacks are shorter: `QueryCache(onError: …)`
runs once per fetch that fails for good, whichever widget asked. See [global
callbacks](global-callbacks.md).

## Reading the cache

What an inspector reads, all public:

- `client.queryCache.queries` — every entry right now.
- `query.state` — `status`, `fetchStatus`, `dataUpdatedAt`, `dataUpdateCount`,
  `error`, `fetchFailureCount`, `consecutiveErrorCount`, `isInvalidated`.
- `query.observersCount` — how many readers hold it. An entry with none is
  waiting for garbage collection, `gcTime` after its last reader left.
- `query.isStale()` — whether the next trigger would refetch it.
- `query.options` — the options it runs with, every default filled in.
- `key.debugString` — the key, readable.
- `client.isFetching()` and `client.isMutating()` — how much is in flight.

## A small inspector

A widget that lists the cache and rebuilds on its events, to drop into a
debug drawer or behind a long-press. It lives in your app, for instance in
`lib/debug/cache_inspector.dart`:

```dart snippet="guides/debugging.md#inspector"
/// Every entry of the query cache, one line each. For debug builds.
class CacheInspector extends StatefulWidget {
  const CacheInspector({super.key});

  @override
  State<CacheInspector> createState() => _CacheInspectorState();
}

class _CacheInspectorState extends State<CacheInspector> {
  QueryClient? _client;
  void Function()? _unsubscribe;
  bool _rebuildPending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = QueryClientProvider.of(context);
    if (client == _client) return;
    _unsubscribe?.call();
    _client = client;
    _unsubscribe = client.queryCache.subscribe((event) {
      // About the readers, not the cache — and the first fires on every
      // reader's build.
      if (event is QueryObserverOptionsUpdated ||
          event is QueryObserverResultsUpdated) {
        return;
      }
      _rebuildAfterFrame();
    });
  }

  /// An event can arrive while a frame is being built, when `setState` is
  /// not allowed; rebuild once that frame is done, however many came.
  void _rebuildAfterFrame() {
    if (_rebuildPending) return;
    _rebuildPending = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _rebuildPending = false;
        if (mounted) setState(() {});
      })
      ..scheduleFrame();
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final query in _client!.queryCache.queries)
            Text(
              '${query.queryKey.debugString} '
              '${query.state.status.name}/${query.state.fetchStatus.name} '
              'observers=${query.observersCount} '
              'stale=${query.isStale()}',
            ),
        ],
      );
}
```

It reads the cache directly and holds no observer, so it never keeps an entry
alive or triggers a fetch — what it shows is what the cache holds.

The *Cache inspector* example is a fuller version: a table of every entry
with *Refetch*, *Invalidate* and *Remove* buttons, the mutations, and the
event log. Press *Load posts*, then *Invalidate* on its row and watch the
log; switch on *Keep readers* and see `observers` go to one, then off again
and watch the entry disappear five seconds later.

<LiveDemo feature="cache-inspector" />

## What the library throws

Some mistakes fail loudly rather than showing up as wrong data:

- **`QueryDataTypeError`** — a key holds exactly one type, and reading or
  writing it as another throws at the call. The message names the key, the
  type asked for and the type held. Usually two options functions share a
  key; see [type safety in Dart](../dart-type-safety.md#one-key-one-exact-type).
- **`MissingQueryFunctionError`** and **`MissingMutationFunctionError`** — a
  query or mutation ran with no function and no default registered for its
  key. They become the error state, and are not retried.
- **Assertions in debug builds** — for example, `context.query` read through
  a `ListView.builder`'s item context. Each message says what to do instead.

In the *Diagnostics* example, press *Read as String* and *Write a String*
against an `int` entry, then *Mutate without a function*, and *Register a
default mutationFn* to see the same mutation succeed.

<LiveDemo feature="diagnostics" />

Every error, with when it is thrown, is on the [errors
reference](../reference/errors.md).

:::note[In React Query]
The React devtools (`@tanstack/react-query-devtools`) have no counterpart
here. The events they are built on are the same: `queryCache.subscribe` and
`mutationCache.subscribe`, with the same event names in Dart class form.
:::

## Common surprises

[Troubleshooting](../reference/troubleshooting.md) lists symptoms — a query
that refetches on every build, a list that never releases, a
`QueryDataTypeError` for a type that looks right — each with its cause and
fix.
