---
title: Filters
description: QueryFilters and MutationFilters — the one named filters argument every bulk operation takes, what each field matches, and how to match a query yourself.
---

# Filters

Every operation that acts on many queries at once — invalidating, refetching,
resetting, removing, cancelling, counting — takes its target as a named
`filters:` argument. One value type describes "which queries", so the call
sites read the same everywhere:

```dart snippet="guides/filters.md#filters"
client.invalidateQueries(filters: QueryFilters(queryKey: tasksKey)).ignore();
client.removeQueries(
  filters: QueryFilters(queryKey: tasksKey, exact: true),
);
client
    .refetchQueries(filters: QueryFilters(type: QueryTypeFilter.active))
    .ignore();
client
    .resetQueries(
        filters: QueryFilters(predicate: (query) => query.isStale()))
    .ignore();
```

Leaving the filters out matches everything.

## `QueryFilters`

| Field | Matches |
|---|---|
| `queryKey` | keys that start with this one — a **prefix** |
| `exact` | with `true`, only the key itself |
| `type` | `QueryTypeFilter.active` (read by at least one enabled observer), `inactive` or `all` (the default) |
| `stale` | stale (`true`) or fresh (`false`) queries |
| `fetchStatus` | `FetchStatus.fetching`, `paused` or `idle` |
| `status` | `QueryStatus.pending`, `error` or `success` |
| `predicate` | anything else: a function from the `Query` to `bool` |

Every field given must match; a field left out matches anything. The
operations that take them: `invalidateQueries`, `refetchQueries`,
`resetQueries`, `removeQueries`, `cancelQueries`, `isFetching`,
`getQueriesData`, `updateQueriesData`, and the query cache's `findAll`.
`isFetching` is the one exception to "every field given must match": it
always counts queries that are fetching right now, so a `fetchStatus` passed
to it is ignored rather than combined.

In an app, the key factory does most of the work, and the other fields cut
the set down:

```dart snippet="guides/filters.md#query-filters"
// Every device query, lists and details alike.
await client.invalidateQueries(
  filters: QueryFilters(queryKey: DeviceKeys.all),
);

// The kitchen's list only — `exact` stops the prefix match.
await client.refetchQueries(
  filters: QueryFilters(
    queryKey: DeviceKeys.list(room: 'kitchen'),
    exact: true,
  ),
);

// Device details nobody is showing: dropped, not refetched.
client.removeQueries(
  filters: QueryFilters(
    queryKey: DeviceKeys.details,
    type: QueryTypeFilter.inactive,
  ),
);

// Every query whose last fetch failed, whatever its key.
await client.refetchQueries(
  filters: const QueryFilters(status: QueryStatus.error),
);

// Only what has gone stale, for a pull-to-refresh that skips fresh data.
await client.refetchQueries(
  filters: QueryFilters(queryKey: DeviceKeys.all, stale: true),
);

// How many device requests are out right now — for a spinner.
final loading = client.isFetching(
  filters: QueryFilters(queryKey: DeviceKeys.all),
);
```

### The predicate

`predicate` runs last, after every other field has matched, and receives the
whole `Query` — its key, its state, its options' `meta`. That makes it the
place for rules that cut across keys. A query can carry a tag in `meta`, and
sign-out drops everything so tagged, whatever it is called:

```dart snippet="guides/filters.md#predicate"
// At sign-out, drop every query tagged as the user's own, whatever its key.
client.removeQueries(
  filters: QueryFilters(
    predicate: (query) => switch (query.meta) {
      {'personal': true} => true,
      _ => false,
    },
  ),
);
```

Give the predicate a `queryKey` alongside it when you can, so it is asked
about fewer queries.

### One asymmetry

`queryCache.find` — one query, by key — defaults to an **exact** match, as
you would expect from a lookup. The bulk operations default to a **prefix**,
as you would expect from "everything about devices". Pass `exact: true` to a
bulk operation when you mean one key.

## `MutationFilters`

The same idea over the mutation cache: `mutationKey` (a prefix unless
`exact`), `exact`, `status` and `predicate`.
`mutationCache.findAll(filters: …)` returns the mutations they match, and
[mutation state](mutation-state.md) reads them as a listenable.
`client.isMutating(filters: …)` counts only the matching mutations that are
pending: a `status` passed to it is ignored, as `isFetching` ignores
`fetchStatus`.



```dart snippet="guides/filters.md#mutation-filters"
// Adds still out in any room — `['add-device']` is a prefix.
final adding = client.isMutating(
  filters: MutationFilters(mutationKey: QueryKey(<Object?>['add-device'])),
);

// Every write that failed, for a "retry all" banner.
final failed = client.mutationCache.findAll(
  filters: const MutationFilters(status: MutationStatus.error),
);
```

A mutation without a `mutationKey` is matched only by filters that name no
key.

## Matching a query yourself

A filter is a value with a public `matches(query)`. That is useful outside
the bulk operations — in a cache listener that should only log what happens
to one part of the cache, for instance:

```dart snippet="guides/filters.md#matches"
final QueryFilters kitchenLists = QueryFilters(
  queryKey: DeviceKeys.list(room: 'kitchen'),
);

void Function() logKitchen(QueryClient client) =>
    client.queryCache.subscribe((event) {
      if (kitchenLists.matches(event.query)) debugPrint('kitchen: $event');
    });
```

`MutationFilters` has the same `matches(mutation)`.

The `invalidation-and-filters` screen runs these fields against a small
cache. Tick *Fail post 2 next*, press *Refetch post 2*, then *Predicate:
errored*: only the failed post is invalidated. *Refetch stale only* refetches
the posts and leaves the todos alone, which are fresh for thirty seconds.

<LiveDemo feature="invalidation-and-filters" />

:::note[In React Query]
The same fields, with two spellings changed: `type: 'active'` is
`QueryTypeFilter.active`, and the filters are always a named `filters:`
argument rather than the first positional one. `matches` is TanStack Query's
exported `matchQuery` and `matchMutation`.
:::
