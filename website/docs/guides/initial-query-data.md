---
title: Initial query data
description: InitialData seeds the cache with data the app already has — a value or a computed seed, and how old it is.
---

{/* depth: todo */}
{/* demo: initial-and-placeholder */}

# Initial query data

When the app already has the data a query will fetch — the list screen holds
the task the detail screen is about to load — hand it over as initial data.
The query starts in `success` with it, and no spinner is shown.

**`InitialData` is written to the cache.** It is indistinguishable from a
fetch result: every reader of the key sees it, and it is subject to
`staleTime` like fetched data. If it should not be believed, you want
[placeholder data](placeholder-query-data.md) instead.

| | |
|---|---|
| `InitialData.value(v)` | this value |
| `InitialData.compute(() => …)` | computed; returning `null` means "none". `InitialData.value(null)` is a value *of* `null` |
| `initialDataUpdatedAt: DateTime?` | how old it is; `null` means now |
| `initialDataUpdatedAtCompute: () => DateTime?` | the lazy form, evaluated only when the data is actually seeded. Give one form or the other, never both |

## Seeding a detail from a list

`InitialData.compute` can look in another cache entry:

```dart snippet="guides/initial-query-data.md#seed-from-list"
QueryObserverOptions<Task> taskSeededFromList(QueryClient client, String id) =>
    QueryObserverOptions(
      queryKey: taskKey(id),
      queryFn: (context) => api.getTask(id, signal: context.signal),
      initialData: InitialData.compute(
        () => client
            .getQueryData<List<Task>>(tasksKey)
            ?.where((task) => task.id == id)
            .firstOrNull,
      ),
      // As old as the list it came from.
      initialDataUpdatedAtCompute: () => client.queryCache
          .find(filters: QueryFilters(queryKey: tasksKey))
          ?.state
          .dataUpdatedAt,
    );
```

Giving the list's `dataUpdatedAt` as the seed's age means the detail is as
stale as the list it came from, and refetches on the same schedule.

`InitialData.compute` is asked again on every rebuild and every fetch until
the entry holds data, so a seed it finds later still lands. Keep it cheap.

## With `staleTime`

With the default `staleTime` of zero, initial data is stale at once, so it is
shown *and* refetched behind. With a `staleTime`, initial data younger than
it is not refetched — which is why its age matters.

An alternative to initial data in the options is writing to the cache before
the screen opens; see [prefetching](prefetching.md) and
[updates from mutation responses](updates-from-mutation-responses.md).
