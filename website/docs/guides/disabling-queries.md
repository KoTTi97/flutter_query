---
title: Disabling queries
description: Enabled.no keeps a query from fetching on its own — lazy queries, what a disabled query still does, and why there is no skipToken.
---

{/* depth: todo */}
{/* demo: dependent-queries */}

# Disabling queries

`enabled: Enabled.no` keeps a query from fetching on its own: not on mount,
not on focus or reconnect, not on an interval.

## What a disabled query still does

- It **serves cached data**. Without data it is `pending` with `fetchStatus:
  idle`; with data it stays `success`.
- **`refetch()` still fetches.** That is the way to run a disabled query on
  demand — though a query that is only ever fetched by hand is usually better
  written as an enabled query whose key changes.
- **`invalidateQueries` marks it stale** but does not refetch it while a
  disabled observer holds it. `refetchQueries` skips it too.
- Once **nothing observes** a query that has fetched before, `refetchQueries`
  and `invalidateQueries(refetchType: RefetchType.all)` refetch it whatever
  `enabled` its last observer had.

## Lazy queries

A query that should wait for input — a search box — is disabled until there is
input, and its key carries the input:

```dart snippet="guides/disabling-queries.md#lazy"
QueryObserverOptions<List<Task>> searchQuery(String needle) =>
    QueryObserverOptions(
      queryKey: TaskKeys.all.append(<Object?>['search', needle]),
      queryFn: (context) => api.search(needle, signal: context.signal),
      // Nothing typed yet: nothing to ask the server.
      enabled: needle.isEmpty ? Enabled.no : Enabled.yes,
    );
```

While the box is empty, the result is `pending` and not fetching: show a hint,
not a spinner. `result.isLoading` — pending **and** fetching — is the flag
for a spinner; it is `false` for a query that is only waiting to be enabled.

## No `skipToken`

TanStack Query's `skipToken` is `Enabled.no` here. Where the two differ,
`Enabled.no` behaves like `enabled: false`: an unobserved query that
fetched before is refetched by `refetchQueries` and
`invalidateQueries(refetchType: RefetchType.all)`, where `skipToken` would
skip it.
