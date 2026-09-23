---
title: Queries
description: What a query is, where it lives in an app, the three result states, status versus fetchStatus, and the flags that combine them.
---

# Queries

A screen that shows server data has to answer the same questions every time:
is it loading, did it fail, is what I show still current, is a refresh
running? Written by hand, that is a `Future` in a `State`, three flags and a
`setState` per screen — and two screens showing the same data fetch it twice.

A **query** answers those questions once. It is a declarative dependency on a
piece of asynchronous data, tied to a **unique key**. You give it the key and
a function that returns a `Future`; the cache decides when to call the
function, keeps the result under the key, and tells every widget that reads
it.

## Describing a query

The smallest useful shape is a function that returns the options, kept next
to the rest of the app's data layer:

```dart snippet="guides/queries.md#device-queries"
// lib/data/device_queries.dart
QueryObserverOptions<List<Device>> devicesQuery({String? roomId}) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.list(roomId: roomId),
      queryFn: (context) =>
          repository.devices(roomId: roomId, signal: context.signal),
    );

QueryObserverOptions<Device> deviceQuery(String id) => QueryObserverOptions(
      queryKey: DeviceKeys.detail(id),
      queryFn: (context) => repository.device(id, signal: context.signal),
    );
```

- The **key** is how the cache stores, shares and invalidates the data. Two
  widgets that build the same key share one entry and one request. See [query
  keys](query-keys.md).
- The **function** resolves with the data or throws. Passing
  `context.signal` on lets the cache cancel a request nobody waits for any
  more. See [query functions](query-functions.md).
- The **type** comes from the function: `devicesQuery()` is a
  `QueryObserverOptions<List<Device>>`, and so is everything read through it.

A function per query, not a widget-local literal, is what lets the same
description be read on one screen, prefetched on another and invalidated by a
mutation — see [describing a query once](query-options.md).

## Reading it on a screen

Every call style hands you the same `QueryResult`. Here it is read with
`context.query`, one of [four equal ways](reading-queries-in-widgets.md):

```dart snippet="guides/queries.md#devices-screen"
// lib/ui/devices_screen.dart
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final devices = context.query(devicesQuery());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        // A background refetch: the list stays, and a thin bar says so.
        bottom: devices.isRefetching
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: switch (devices) {
        QueryPending() => const Center(child: CircularProgressIndicator()),
        // A refetch failed: say so above the data that is still good.
        QueryError(:final error, :final staleData?) => Column(
            children: <Widget>[
              Text('Could not refresh: $error'),
              Expanded(child: DeviceListView(staleData)),
            ],
          ),
        // The first load failed: there is nothing to show.
        QueryError(:final error) =>
          Center(child: Text('Could not load devices: $error')),
        QuerySuccess(:final data) => RefreshIndicator(
            onRefresh: devices.refetch,
            child: DeviceListView(data),
          ),
      },
    );
  }
}
```

Four things are happening without code of their own:

- The first build starts the fetch; the second screen that reads
  `devicesQuery()` does not start another.
- Pull-to-refresh awaits `refetch()`, which completes when the fetch does.
- A failed *refetch* keeps the list: `staleData` is the last good value, and
  the banner sits above it.
- Leaving the screen and coming back within five minutes renders the cached
  list at once and refetches behind it — the [important
  defaults](../important-defaults.md) at work.

The showcase's *basic* screen is that last point, live. Tap a post, go back —
its row now says `cached` — and open it again: the title is there at once,
with a `refreshing` pill while the refetch runs. The screen sets a `gcTime` of
ten seconds, so wait that long on the list and the entry is gone:

<LiveDemo feature="basic" />

## The three states

A `QueryResult<T>` is sealed, and is exactly one of:

- **`QueryPending`** — there is no data yet.
- **`QuerySuccess`** — `data` holds the data.
- **`QueryError`** — the query failed. `error` and `stackTrace` say why, and
  `staleData` holds the last good data when there was any (`hasStaleData`
  tells a real `null` from none).

`result.status` gives the same thing as a `QueryStatus` value, and
`isPending`, `isSuccess` and `isError` are there for when a `switch` is more
than you need. `result.dataOrNull` is the data of a success or the stale data
of an error.

## What the query is doing: `fetchStatus`

The status says whether there is data. It says nothing about whether a fetch
is running — a query can hold data *and* be refetching it. That is the second
axis, `fetchStatus`:

- **`FetchStatus.fetching`** — the function is running (a first load, a
  retry, or a background refetch).
- **`FetchStatus.paused`** — it wanted to fetch but may not go on yet. A
  fetch under the default network mode that finds the client offline waits
  before its first attempt. A fetch that failed and is due for a retry
  waits between attempts while the client is offline, and also while the app
  is in the background — a retry resumes when the app is back in the
  foreground. See [network mode](network-mode.md).
- **`FetchStatus.idle`** — nothing is running.

Any status combines with any fetch status. The flags on every result name the
common combinations:

| Flag | Means |
|---|---|
| `isFetching` | `fetchStatus` is `fetching` — anything is running |
| `isPaused` | `fetchStatus` is `paused` |
| `isLoading` | pending **and** fetching: the first load is in flight |
| `isRefetching` | fetching but **not** pending: a background refetch of data already there |
| `isLoadingError` (on `QueryError`) | failed with no data to show |
| `isRefetchError` (on `QueryError`) | a refetch failed; `staleData` is still good |

A `switch` can use them directly:

```dart snippet="guides/queries.md#status"
Widget taskTitle(QueryResult<Task> task) => switch (task) {
      QueryPending(isPaused: true) => const Text('Waiting for the network…'),
      QueryPending() => const Text('Loading…'),
      QueryError(:final staleData?) =>
        Text('${staleData.name} (not refreshed)'),
      QueryError(:final error) => Text('Could not load: $error'),
      QuerySuccess(:final data, isRefetching: true) => Text('${data.name} …'),
      QuerySuccess(:final data) => Text(data.name),
    };
```

## Other fields worth knowing

- `dataUpdatedAt` and `errorUpdatedAt` — when the data or the error arrived.
- `isStale` — whether the data is older than its `staleTime`, or was
  invalidated, and `true` while there is no data yet. A **disabled** query
  is never stale, and neither is a `StaleTime.static` query that has data —
  invalidation included.
- `failureCount` and `failureReason` — how many attempts of the current fetch
  have failed, while it retries. See [retries](query-retries.md).
- `consecutiveErrorCount` — fetches in a row that ended in an error. See
  [polling](polling.md).
- `isPlaceholderData` — the data is a placeholder, not in the cache. See
  [placeholder data](placeholder-query-data.md).
- `refetch()` — fetch again now. Its future completes with the new result.
  A fetch already running over data is cancelled and replaced; pass
  `cancelRefetch: false` to join it instead. A first load, with no data
  yet, is always joined.

## Traps

- **Build the options, not the client, in `build`.** An options function is
  cheap to call on every build: the reader compares it by value and changes
  nothing when it is equal. A `QueryClient` built in `build` is a new, empty
  cache every time.
- **`isLoading` is not "a spinner is needed".** It is false during a
  background refetch, when the data is on screen — which is what you want —
  and also false for a pending query that is *paused*. Match
  `QueryPending(isPaused: true)` if that deserves its own message.
- **An error does not clear the data.** Match `QueryError(:final staleData?)`
  before `QueryError()`, or the screen blanks on the first failed refresh.

:::note[In React Query]
This is `useQuery`. `status` and `fetchStatus` are the same two axes; the
sealed result replaces `data | undefined` with a field that exists only on the
states that have it, and `isLoadingError`/`isRefetchError` move onto
`QueryError`. See [differences from
TanStack Query](../reference/differences-from-tanstack.md).
:::
