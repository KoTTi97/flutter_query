---
title: Caching
description: How long data is fresh (StaleTime), how long an unobserved entry is kept (GcTime), and what happens to a query from its first read to garbage collection.
---

# Caching

Two options decide the life of a cache entry: how long its data counts as
**fresh**, and how long the entry is **kept** once nothing reads it. Most of
what the library does without being asked — refetching on mount, on focus, on
reconnect, dropping old data — follows from those two numbers.

## A query's life, with the defaults

Take a room screen that reads the kitchen's devices, with the defaults —
`StaleTime.zero` and a five-minute `GcTime`:

1. **The first read.** `RoomScreen('kitchen')` builds and reads
   `roomDevicesQuery('kitchen')`. Nothing is cached under
   `['devices', 'list', 'kitchen']`: a new entry is created, the result is
   `QueryPending`, and the query function runs.
2. **The data arrives** and is cached under that key. The screen rebuilds
   with `QuerySuccess`. With `StaleTime.zero`, the data is **stale at once** —
   the cache keeps it, but no longer vouches for it.
3. **A second reader.** A kitchen badge on the home tab reads the same
   options. It gets the cached list on its first frame — no spinner — and,
   because the data is stale, a refetch runs behind it. It is one request for
   both readers; both rebuild when it lands, and only if the list changed.
4. **The readers go.** The user leaves the room screen and the home tab. The
   entry has no observers any more, so it becomes **inactive** and its
   **garbage-collection timer** starts: five minutes.
5. **Back within five minutes.** The user opens the kitchen again. The screen
   shows the cached list on its first frame and refetches behind it, because
   it is stale. The collection timer is cancelled — the entry has a reader.
6. **Gone for five minutes.** Nobody reads the kitchen for five minutes: the
   entry is dropped. The next read starts again at step 1, with a spinner.

Two things follow. A stale entry is not a problem to be avoided: it is shown
at once and refreshed behind the reader, which is the whole point of the
cache. And "refetch behind it" only happens on the triggers — a new reader,
[app focus](window-focus-refetching.md), reconnect, an
[invalidation](query-invalidation.md) — never on a timer unless you ask for
[polling](polling.md).

## Choosing the numbers

The defaults assume that data may have changed the moment it arrived. For
most apps that is too cautious: it refetches every time a tab is switched.
Give each query the freshness its data really has:

```dart snippet="guides/caching.md#device-queries"
// lib/data/device_queries.dart
QueryObserverOptions<List<Device>> roomDevicesQuery(String room) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.list(room: room),
      queryFn: (context) => devices.list(room: room, signal: context.signal),
      // Switching between room tabs within ten seconds costs no request.
      staleTime: const StaleTime.duration(Duration(seconds: 10)),
    );

QueryObserverOptions<Device> deviceQuery(String id) => QueryObserverOptions(
      queryKey: DeviceKeys.detail(id),
      queryFn: (context) => devices.get(id, signal: context.signal),
      staleTime: const StaleTime.duration(Duration(seconds: 10)),
    );

QueryObserverOptions<List<double>> energyQuery(String id) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.detail(id).append(<Object?>['energy']),
      queryFn: (context) => devices.energy(id, signal: context.signal),
      // Hourly readings: a minute old is new enough.
      staleTime: const StaleTime.duration(Duration(minutes: 1)),
    );

QueryObserverOptions<List<String>> firmwareChannelsQuery() =>
    QueryObserverOptions(
      queryKey: QueryKey(<Object?>['firmware-channels']),
      queryFn: (context) => devices.firmwareChannels(signal: context.signal),
      // Changes with a server release, not while the app runs: fetch it once
      // and keep it for the session.
      staleTime: StaleTime.static,
      gcTime: GcTime.never,
    );
```

The question to ask per query is "how old can this be before the user would
notice or care?" A light's state that someone else may switch: seconds.
Hourly energy readings: a minute. A list of firmware channels that changes
with a server release: never, for the life of the app.

When most of the app agrees, set the numbers once on the client and override
them per query:

```dart snippet="guides/caching.md#client-defaults"
// lib/main.dart
final QueryClient appClient = QueryClient(
  defaultOptions: const DefaultOptions(
    queries: QueryDefaults(
      staleTime: StaleTime.duration(Duration(seconds: 20)),
      gcTime: GcTime.duration(Duration(minutes: 10)),
    ),
  ),
);
```

## Staleness

`StaleTime` decides whether cached data counts as fresh. Fresh data is
returned without a fetch; stale data is returned *and* refetched behind it —
on mount, on [app focus](window-focus-refetching.md) and on reconnect.

| | |
|---|---|
| `StaleTime.zero` | stale immediately — the default |
| `StaleTime.duration(d)` | fresh for `d` after it was fetched |
| `StaleTime.infinite` | never stale by time, still refetched when explicitly asked |
| `StaleTime.static` | never stale **and**, while an observer holds the query, skipped by every refetch trigger — mount, focus, reconnect, `invalidateQueries`, `refetchQueries` — but not by an observer's own `refetch()`, and not by an explicit `refetchInterval`. An entry nobody observes is refetched by `invalidateQueries` and `refetchQueries` like any other |
| `StaleTime.dynamic((query) => …)` | computed per query, from its current state |

`StaleTime.static` is the "fetch this once, ever" option. A dynamic stale time
is asked several times per operation; keep its function cheap and free of side
effects.

An [invalidation](query-invalidation.md) marks data stale whatever its
`staleTime` says — except `StaleTime.static`, which an invalidation does not
make stale. So `StaleTime.infinite` is the choice for data that only your own
writes change: it never refetches by itself, and invalidating it after a write
still works.

## Garbage collection

`GcTime` is how long an entry with no observers is kept before it is dropped.

| | |
|---|---|
| `GcTime.duration(d)` | drop `d` after the last observer leaves |
| `GcTime.defaultValue` | five minutes |
| `GcTime.never` | keep for the life of the client |

An entry keeps the **longest** `gcTime` any reader has given it. A screen
that reads a key with ten minutes and a badge that reads it with one minute
leave an entry that is kept for ten, whichever went last.

Garbage collection frees memory; it has nothing to do with freshness. A
long `gcTime` with a short `staleTime` is common and useful: the data comes
back instantly when the user returns, and is refreshed as it does. The
opposite — a `gcTime` shorter than the time a user spends away — means a
spinner on every return.

A client owns its garbage-collection timers, which is why a widget test has to
[clear it](testing.md) before the test ends.

## Seeing it

The `stale-and-gc` screen has one entry and a knob for every `StaleTime` and
`GcTime` value. Pick *GC time* 5 s and press *Detach reader* (the icon with that
tooltip): the entry has no observers, and five seconds later it is gone;
*Attach reader* starts again from nothing. With *Stale time* set to
`static`, *Invalidate* fetches nothing, while *Refetch* — the reader's own
request — still does.

<LiveDemo feature="stale-and-gc" />

The `cache-inspector` screen lists every entry of the cache, with its status
and its observer count. Press *Load posts* and *Load todos*,
then untick *Keep readers*: the observer counts drop to zero, and five
seconds later the rows disappear as their entries are collected.

<LiveDemo feature="cache-inspector" />

For the same view of your own app, see [debugging](debugging.md).

:::note[In React Query]
`staleTime` and `gcTime`, with the same defaults and the same lifecycle. The
values are sealed types here instead of numbers: `staleTime: Infinity` is
`StaleTime.infinite`, `'static'` is `StaleTime.static`, a function is
`StaleTime.dynamic`, and `gcTime: Infinity` is `GcTime.never`.
:::
