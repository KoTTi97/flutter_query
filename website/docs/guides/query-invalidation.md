---
title: Query invalidation
description: invalidateQueries marks matching queries stale and refetches the active ones — prefix matching, exact, and refetchType.
---

{/* depth: todo */}
{/* demo: invalidation-and-filters */}

# Query invalidation

Waiting for data to go stale is not always good enough: after a write you know
the cached data is wrong. `invalidateQueries` says so.

```dart snippet="guides/query-invalidation.md#invalidate"
// Every key that starts with ['tasks']: the lists and every detail.
await client.invalidateQueries(
  filters: QueryFilters(queryKey: TaskKeys.all),
);

// This one detail only.
await client.invalidateQueries(
  filters: QueryFilters(queryKey: TaskKeys.detail(id), exact: true),
);

// Mark everything under ['tasks'] stale, and refetch nothing now.
await client.invalidateQueries(
  filters: QueryFilters(queryKey: TaskKeys.all),
  refetchType: RefetchType.none,
);
```

An invalidation does two things to every matching query:

1. **Marks it stale**, whatever its `staleTime` says, so the next mount, focus
   or reconnect refetches it.
2. **Refetches it now if it is active** — if a widget or observer is reading
   it. An inactive query waits until something reads it again.

The future completes when those refetches have settled.

## What is matched

The key is a **prefix** unless `exact: true`, which is why keys are built from
the most general part down — see [query keys](query-keys.md). Every other
[filter](filters.md) works too: `predicate` for anything a key cannot say.

## Which queries refetch

`refetchType` narrows the second step:

| `RefetchType` | Refetches |
|---|---|
| `active` | the default: matching queries a reader is observing |
| `inactive` | matching queries nobody is observing |
| `all` | both |
| `none` | nothing — the queries are only marked stale |

A disabled query is marked but not refetched, and neither is one whose
`staleTime` is `StaleTime.static` while it is observed.

`cancelRefetch` (default `true`) cancels a fetch already in flight for a
matching query and starts a fresh one, so the data you get back was fetched
after your call. Pass `false` to join the running fetch instead.

## Related operations

- `refetchQueries` refetches without marking anything stale.
- `resetQueries` puts matching queries back to their initial state, then
  refetches the active ones.
- `removeQueries` drops them from the cache — for keys nobody is watching.

After a write, see [invalidations from mutations](invalidations-from-mutations.md).
