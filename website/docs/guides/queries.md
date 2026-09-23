---
title: Queries
description: What a query is, the three result states, status versus fetchStatus, and the flags that combine them.
---

{/* depth: todo */}
{/* demo: simple */}

# Queries

A query is a declarative dependency on a piece of asynchronous data, tied to a
**unique key**. You give it the key and a function that returns a `Future`;
the cache decides when to call the function and who is told about the
result.

```dart snippet="quick-start.md#key quick-start.md#options"
final QueryKey tasksKey = QueryKey(<Object?>['tasks']);

QueryObserverOptions<List<Task>> tasksQuery() => QueryObserverOptions(
      queryKey: tasksKey,
      queryFn: (context) => api.listTasks(signal: context.signal),
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    );
```

- The key is how the cache stores, shares and invalidates the data. See
  [query keys](query-keys.md).
- The function resolves with the data or throws. See [query
  functions](query-functions.md).

Reading it in a widget is covered in [four ways to read a
query](reading-queries-in-widgets.md); every style hands you the same
`QueryResult`.

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
- **`FetchStatus.paused`** — it wanted to fetch but is waiting for the
  network. See [network mode](network-mode.md).
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
- `isStale` — whether the data is older than its `staleTime`.
- `failureCount` and `failureReason` — how many attempts of the current fetch
  have failed, while it retries. See [retries](query-retries.md).
- `consecutiveErrorCount` — fetches in a row that ended in an error. See
  [polling](polling.md).
- `isPlaceholderData` — the data is a placeholder, not in the cache. See
  [placeholder data](placeholder-query-data.md).
- `refetch()` — fetch again now.
