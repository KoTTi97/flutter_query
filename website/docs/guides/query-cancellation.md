---
title: Query cancellation
description: context.signal is a QueryCancelToken — hand it to your HTTP client, and what cancelQueries and a leaving reader do to a fetch in flight.
---

{/* demo: cancellation */}

# Query cancellation

A query function receives `context.signal`, a `QueryCancelToken`. It is
cancelled when the fetch is no longer wanted. Dart has no ecosystem-wide
cancellation primitive, so the token's `onCancel` is the interop point with
whatever your HTTP client uses:

```dart snippet="prose-only: needs dio, which neither published package may depend on"
Future<List<Task>> listTasks(QueryFunctionContext context) {
  final token = CancelToken();                     // dio
  context.signal.onCancel(token.cancel);
  return dio.get<…>('/tasks', cancelToken: token).then(…);
}
```

The token also has `isCancelled`, `whenCancelled` (a future) and
`throwIfCancelled()`, for a function that does its work in steps.

## When a fetch is cancelled

- **The last reader leaves** while the fetch runs. If the function *read*
  `context.signal`, the fetch is cancelled and the query goes back to what it
  held before. If it never read the signal, the request cannot be stopped, so
  it is left to finish and its result is cached — only further retries are
  stopped.
- **`client.cancelQueries(filters: …)`** cancels matching fetches, for
  example before an [optimistic update](optimistic-updates.md) writes to the
  cache.
- **A refetch with `cancelRefetch: true`** — the default for `refetch()`,
  `invalidateQueries` and `refetchQueries` — cancels the fetch in flight and
  starts its own, when the query already has data. A query still loading its
  first data joins the running fetch instead.

## What `cancelQueries` does

The defaults are `revert: true, silent: false`: each query goes back to the
state it held before the fetch, `fetchStatus` `idle`, so a reader keeps the
data it had, and whoever awaited the fetch gets that data back — or a
`CancelledError` when there was none.

`silent: true` means "a new fetch is taking over"; a silently cancelled fetch
that nothing replaces is put back to `idle` rather than left `fetching`.

A cancelled fetch is never retried, and it is not an error on the result.

## Disconnecting a device

To stop talking to something — a device the user disconnected — cancel its
queries and remove them, so nothing refetches them:

```dart snippet="reference/troubleshooting.md#disconnect"
void disconnect(QueryClient client, QueryKey deviceKey) {
  final filters = QueryFilters(queryKey: deviceKey);
  client.cancelQueries(filters: filters).ignore();
  client.removeQueries(filters: filters);
}
```

Cancelling a *mutation* works differently — it fails the run; see [cancelling
mutations](cancelling-mutations.md).
