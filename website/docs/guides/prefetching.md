---
title: Prefetching
description: client.query fetches imperatively — await it, ignore it to prefetch, fetch only when nothing is cached, or serve the cache and revalidate behind it.
---

{/* depth: todo */}
{/* demo: prefetching */}

# Prefetching

If you know a screen is about to need data, fetch it before the screen asks.
By the time a widget reads the key, the data is in the cache — or its fetch is
already running, and the widget joins it.

Everything imperative is one method on the client, `client.query`:

```dart snippet="guides/prefetching.md#imperative"
final tasks = await client.query<List<Task>>(
  QueryOptions<List<Task>>(
    queryKey: tasksKey,
    queryFn: (context) => api.listTasks(signal: context.signal),
  ),
);
```

| You want | Write |
|---|---|
| fetch and await | `await client.query(options)` |
| prefetch, don't wait | `client.query(options).ignore()` |
| only if nothing is cached | `staleTime: StaleTime.static` |
| cached data now, refresh behind it | `client.query(options, revalidateIfStale: true)` |

TanStack Query has `fetchQuery`, `prefetchQuery` and `ensureQueryData` for
these; here they are the rows of one table. The last one is
stale-while-revalidate as an imperative call: cached data comes back at once
while a stale entry refreshes behind it; with nothing cached, the fetch is
awaited as usual.

`client.query` also accepts `InfiniteQueryOptions`, which fetches the first
page; see [infinite queries](infinite-queries.md).

## Where to prefetch

- **On intent** — a tap-down, a hover on the web, a row scrolling into view:
  call `client.query(options).ignore()` with the options the next screen will
  read.
- **In a parent**, for data a child is certain to read, so the two fetches do
  not wait for each other. See [request waterfalls](request-waterfalls.md).

Prefetched data is cached like any other: it is garbage-collected after
`gcTime` if no one reads it, and it is stale after `staleTime`.

## What `client.query` joins

`client.query` **joins** a fetch already in flight for its key rather than
starting another — so a call right after your write may hand back what the
running fetch brings. Use `refetchQueries` for a fetch that starts after your
write.

The options it is given become the query's, as an observer's do: an explicit
`retry` in them is the policy a later invalidation or focus refetch of that
query uses too, until an observer or another call hands in its own. Only the
no-retry default, for a call that configured none, is limited to that one
fetch.
