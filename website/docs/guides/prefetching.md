---
title: Prefetching
description: client.query fetches imperatively — await it, ignore it to prefetch on tap, hover or in a route redirect, fetch only when nothing is cached, or serve the cache and revalidate behind it.
---

# Prefetching

If you know a screen is about to need data, fetch it before the screen asks.
By the time a widget reads the key, the data is in the cache — or its fetch is
already running, and the widget joins it. The user sees the screen with its
content instead of a spinner.

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

`client.query` fetches only when the entry is missing or stale by the
options' `staleTime` — zero unless you set one. Fresh data comes back without
a request, so prefetching the same key twice within its `staleTime` costs
nothing. A call makes one attempt unless the options configure `retry`, and
an error is thrown to the caller; `.ignore()` drops it, which is what a
prefetch wants — the screen will fetch and show the error itself.

`client.query` also accepts `InfiniteQueryOptions` — with nothing cached, it
fetches the first page — and `client.infiniteQuery` is the typed form; see
[infinite queries](infinite-queries.md).

## Prefetch on intent

The best moment is the moment the user shows what they are about to do. In a
device list, that is a pointer resting on a row on the web and desktop, and
the tap on a phone:

```dart snippet="guides/prefetching.md#on-intent"
class DeviceTile extends StatelessWidget {
  const DeviceTile({super.key, required this.device});

  final Device device;

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    void prefetch() {
      client.query(deviceQuery(device.id)).ignore();
      client.query(energyQuery(device.id)).ignore();
    }

    return MouseRegion(
      // Web and desktop: a pointer resting on the row is intent enough.
      onEnter: (_) => prefetch(),
      child: ListTile(
        title: Text(device.name),
        onTap: () {
          // Touch has no hover. Start both requests before the push, so the
          // chart's does not wait for the device to arrive first.
          prefetch();
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => DeviceScreen(id: device.id),
            ),
          );
        },
      ),
    );
  }
}
```

The tile prefetches with the **same options function** the detail screen
reads with — `deviceQuery(id)` and `energyQuery(id)` — so the key, the
function and the `staleTime` cannot drift apart. On the tap, both requests
leave before the push, and the transition animation covers part of the wait.
A pointer that sweeps across twenty rows asks for twenty devices, but only
once each within the `staleTime`.

:::tip[Give the reader a `staleTime`]
Prefetched data is only useful if the screen that reads it accepts it. With
the default `staleTime` of zero, the cached device is stale the moment it
lands, so the detail screen shows it at once *and* refetches it on mount.
That is still better than a spinner, but it is two requests where one would
do. The device queries here are fresh for ten seconds.
:::

## Prefetch in a route

A deep link or a push notification opens the detail screen directly, with no
row to tap. The router is the one place that knows where the user is going.
With go_router, start the fetch in the route's `redirect`, which runs before
the screen is built:

```dart snippet="prose-only: needs go_router, which the docs package does not depend on"
GoRouter buildRouter(QueryClient client) => GoRouter(
      routes: [
        GoRoute(
          path: '/devices/:id',
          redirect: (context, state) {
            final id = state.pathParameters['id']!;
            client.query(deviceQuery(id)).ignore();
            client.query(energyQuery(id)).ignore();
            return null; // no redirect — only a head start
          },
          builder: (context, state) =>
              DeviceScreen(id: state.pathParameters['id']!),
        ),
      ],
    );
```

Build the router with the client it prefetches into, as you would pass it to
a `QueryClientProvider`. An `async` redirect that *awaits* `client.query`
holds the navigation until the data is there — use that when a screen without
its data makes no sense, and remember that an error then has to be handled in
the redirect. With `Navigator` alone, prefetch next to the `push`, as the
tile above does.

## Prefetch in a parent

A parent that knows its child will read a query can start it while it loads
its own, so the two requests do not wait for each other. See [request
waterfalls](request-waterfalls.md#prefetch-in-the-parent).

## Seed from what you have

Sometimes the data is already in the cache under another key. A room's list
holds every field the detail screen shows, so the list can seed each detail
when it arrives:

```dart snippet="guides/prefetching.md#prime"
// The room list already holds every device's fields: seed each detail, so
// opening one shows it at once.
for (final device in list) {
  client.setQueryData<Device>(DeviceKeys.detail(device.id), device);
}
```

Opening a device then shows it at once, and its own `staleTime` decides
whether the detail refetches. When the list holds only part of the detail,
use it as the detail's [`placeholderData`](placeholder-query-data.md)
instead, which is shown but never cached as the detail's data.

## Cached data now, fresh data soon

`revalidateIfStale: true` is stale-while-revalidate as an imperative call:
whatever the cache holds comes back at once, even if it is stale, and a stale
entry refreshes behind the call. Only with nothing cached is the fetch
awaited:

```dart snippet="guides/prefetching.md#revalidate"
// The kitchen's devices at once, even a stale list; a stale entry
// refreshes behind this call. Nothing cached: the fetch is awaited.
final kitchen = await client.query(
  roomDevicesQuery('kitchen'),
  revalidateIfStale: true,
);
```

It is the right call for a background task or a service that needs *some*
answer now and wants the cache to catch up — it fails only when nothing is
cached and the fetch fails.

The `prefetching` screen prefetches from a button on each row rather than
on hover, so it works the same with a mouse and a finger. Press a row's prefetch button (tooltip *Prefetch post N*): the row gets
a *prefetched* pill; open it, and the title is there without a request. The
last card contrasts the imperative reads: press *Increment on the server*,
then *Read (revalidateIfStale)* — it shows the old value at once and the new
one lands behind it — and *Read (await)*, which waits for the new one.

<LiveDemo feature="prefetching" />

Prefetched data is cached like any other: it is garbage-collected after
`gcTime` if no one reads it, and it is stale after `staleTime`.

## What `client.query` joins

`client.query` **joins** a fetch already in flight for its key rather than
starting another — so a call right after your write may hand back what the
running fetch brings, and a cancelled fetch that reverts resolves it with the
reverted data. Use `refetchQueries` for a fetch that starts after your write.

The options it is given become the query's, as an observer's do: an explicit
`retry` in them is the policy a later invalidation or focus refetch of that
query uses too, until an observer or another call hands in its own. Only the
no-retry default, for a call that configured none, is limited to that one
fetch.

:::note[In React Query]
TanStack Query has `fetchQuery`, `prefetchQuery`, `ensureQueryData` and
`usePrefetchQuery` for these; here they are the rows of one table on one
method. `prefetchQuery` is `client.query(options).ignore()`,
`ensureQueryData` is `staleTime: StaleTime.static` (or `revalidateIfStale:
true` for its `revalidateIfStale` option), and `prefetchInfiniteQuery` is
`client.infiniteQuery(options).ignore()`.
:::
