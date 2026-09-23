---
title: Query functions
description: A query function returns a Future and throws on failure — what that means for dio and package:http, and what the function context carries.
---

{/* depth: todo */}
{/* demo: cancellation */}

# Query functions

A query function is any function that returns a `Future` of the data. It
receives a `QueryFunctionContext`, and it has one job besides fetching:
**throw when it fails.**

```dart snippet="quick-start.md#options"
QueryObserverOptions<List<Task>> tasksQuery() => QueryObserverOptions(
      queryKey: tasksKey,
      queryFn: (context) => api.listTasks(signal: context.signal),
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    );
```

## Throwing is how a query fails

The cache knows a fetch failed only because its future completed with an
error. Retries, `QueryError`, `failureCount` and the error callbacks all start
there.

- **`dio`** throws a `DioException` for a non-2xx response by default, so a
  function built on it fails correctly as written.
- **`package:http` does not throw** on a 4xx or 5xx response: it returns the
  response. A function built on it has to check `response.statusCode` and
  throw itself, or a server error is cached as a success.

Whatever you throw is the `error` on the result, and it is handed to your
`retry` policy, so throw something your UI and your policy can tell apart —
an exception type of your own with the status code, for example.

## The context

`QueryFunctionContext` carries:

- **`queryKey`** — the key being fetched, so one function can serve several
  keys (see [default query function](default-query-function.md));
- **`signal`** — a `QueryCancelToken` that is cancelled when the fetch is no
  longer wanted. Hand it to your HTTP client; see [query
  cancellation](query-cancellation.md);
- **`meta`** — the query's `meta` option, for information that is not part of
  the key;
- **`client`** — the `QueryClient` running the fetch.

An infinite query's function is `pageFn`, and its context also carries the
`pageParam` and the `direction`; see [infinite queries](infinite-queries.md).

## Keep it free of widget state

The function runs when the cache decides — on mount, on focus, on reconnect,
on an invalidation — possibly after the widget that first asked is gone. It
should read everything it needs from the key and its own closure over stable
objects (an API client), not from a `BuildContext`.
