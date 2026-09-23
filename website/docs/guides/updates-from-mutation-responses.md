---
title: Updates from mutation responses
description: Write what a mutation returned straight into the cache — getQueryData, setQueryData, updateQueryData and updateQueriesData — and the one-key-one-type rule.
---

{/* depth: todo */}
{/* demo: optimistic-updates */}

# Updates from mutation responses

When the server answers a write with the updated object, there is no need to
fetch it again: write it into the cache in `onSuccess`, and every reader of
that key shows it at once.

```dart snippet="guides/updates-from-mutation-responses.md#cache-writes"
client.getQueryData<List<Task>>(tasksKey);
client.setQueryData<Task>(taskKey(id), task);
client.updateQueryData<Task>(
  taskKey(id),
  (previous) => previous?.copyWith(name: 'Renamed'),
);
client.updateQueriesData<Task>(
  (previous) => previous?.copyWith(name: 'Renamed'),
  filters: QueryFilters(queryKey: tasksKey),
);
```

- `getQueryData` reads what is cached, or `null`.
- `setQueryData` takes a **value** and returns what the cache stored, after
  [structural sharing](structural-sharing.md).
- `updateQueryData` takes an updater from the previous value; returning
  `null` from it leaves the cache untouched.
- `updateQueriesData` runs one updater over every query the filters match. It
  runs every updater and checks every result before writing any.

For an infinite query, the typed read is
`getInfiniteQueryData<TPageData, TPageParam>(key)`.

A bare `setQueryData(key, null)` infers `Null` and writes nothing, as
`undefined` does in TanStack Query; write `setQueryData<Task?>(key, null)` to
store a null.

:::danger One key, one exact type
A key is bound to the data type it was first used with, and reading it as any
other type throws `QueryDataTypeError` — **related types included**. `int` and
`int?` are two types. So are `List<Task>` and `List<Object?>`.
`getQueryData<T>`, `getQueriesData<T>` and an observer's `TQueryData` all have
to agree with the key's first use.

A **write** is the one place a related type is welcome. `setQueryData` infers
its type from the value (and so do `updateQueryData` and `updateQueriesData`
from the updater), so an entry that already exists takes any value its own
type can hold — a `String` into a `String?` query, a sealed type's variant
into a query of the sealed type — and keeps its type. Name the type when the
write *creates* the entry, as when seeding a key before its query exists:
`setQueryData<List<Task>>(key, [])`.
:::

A cache write marks the data fresh as of now, so it does not trigger a
refetch. When the response is only part of the picture — the list the new
object belongs in, a count — [invalidate](invalidations-from-mutations.md) the
rest.
