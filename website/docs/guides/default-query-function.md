---
title: Default query function
description: Register a queryFn per key prefix with setQueryDefaults, so options without one derive the request from the key — and client-wide defaults.
---

{/* depth: todo */}
{/* demo: default-query-function */}

# Default query function

When every request follows one pattern — a REST path built from the key, say —
there is no need to write a function per query. Register one for a key, and
every query under that key without a `queryFn` of its own uses it:

```dart snippet="guides/default-query-function.md#defaults"
final client = QueryClient(
  defaultOptions: DefaultOptions(
    queries: QueryDefaults(
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
      retry: const RetryPolicy.times(2),
    ),
  ),
);

client.setQueryDefaults(
  QueryKey(<Object?>['tasks']),
  QueryDefaults(queryFn: (context) => api.listTasks()),
);
```

The function reads the key it is fetching from `context.queryKey`, so one
function can serve a whole family of keys.

## Two levels of defaults

- `QueryClient(defaultOptions: DefaultOptions(queries: …, mutations: …))`
  applies to every query or mutation of the client.
- `client.setQueryDefaults(key, QueryDefaults(...))` applies to every query
  whose key starts with `key`, and sits above the client-wide default.

An option set on the query itself wins over both. `setMutationDefaults` is the
matching call for mutations, without callbacks.

## Name the type

A query with no `queryFn` of its own has nothing to infer its data type from.
Write the type argument — `QueryObserverOptions<List<Task>>(queryKey: …)` — or
it is `dynamic`; see [type safety in Dart](../dart-type-safety.md).
