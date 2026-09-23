---
title: Filters
description: QueryFilters and MutationFilters — the one named filters argument every bulk operation takes, and what each field matches.
---

{/* depth: todo */}
{/* demo: invalidation-and-filters */}

# Filters

Every bulk operation — invalidating, refetching, resetting, removing,
cancelling, counting — takes its target as a named `filters:` argument, so
the call sites read the same everywhere.

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
| `type` | `QueryTypeFilter.active` (read by at least one enabled observer), `inactive` or `all` |
| `stale` | stale (`true`) or fresh (`false`) queries |
| `fetchStatus` | `FetchStatus.fetching`, `paused` or `idle` |
| `status` | `QueryStatus.pending`, `error` or `success` |
| `predicate` | anything else: a function from the `Query` to `bool` |

Every field given must match. The operations that take them:
`invalidateQueries`, `refetchQueries`, `resetQueries`, `removeQueries`,
`cancelQueries`, `isFetching`, `getQueriesData`, `updateQueriesData`, and the
query cache's `findAll`.

One asymmetry to know: `queryCache.find` defaults to an **exact** key, while
the bulk operations default to a prefix.

## `MutationFilters`

The same idea over the mutation cache: `mutationKey`, `exact`, `status` and
`predicate`. `client.isMutating(filters: …)` counts the mutations they match,
and [mutation state](mutation-state.md) reads them.
