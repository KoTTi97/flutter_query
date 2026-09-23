---
title: Scroll restoration
description: A list comes back where it was when its data is still cached, because the first build already has the rows — and what Flutter needs from you, a PageStorageKey or a restorationId, to put the position back.
---

# Scroll restoration

The user scrolls halfway down a list of sixty devices, opens one, comes back
— and lands at the top of an empty list with a spinner, then at the top of
the full list. Two things went wrong there, and only one of them is about
data.

**The data half is solved by the cache.** Coming back to a list whose query
is still cached is instant: the first build after navigating back already
has the rows — a `QuerySuccess` on the first frame, no spinner and no empty
frame. That is what makes restoring a scroll position possible at all: a
saved offset into a list that is still loading has nothing to point at, and
Flutter clamps it to zero.

If the data is stale, it is refetched **behind** the rows, and
[structural sharing](structural-sharing.md) keeps the instances of the rows
that did not change, so the list does not jump or rebuild what is the same.

**The position half is Flutter's.** What you need to do depends on how the
list went away.

## Pushed routes: nothing to do

`Navigator.push` keeps the route below alive, its widgets and its scroll
position included. Popping back to the list needs nothing from you or from
the cache. (The list's query still has a reader the whole time, so it is not
even collected.)

## Tabs, page views, switched bodies: `PageStorageKey`

A `TabBarView`, a `PageView`, or a screen that swaps its body builds the list
again from scratch when it comes back. Give the scrollable a
`PageStorageKey`, and Flutter's `PageStorage` keeps its offset while it is
gone and puts it back when it is built again — with its rows, since they
come from the cache:

```dart snippet="guides/scroll-restoration.md#page-storage-key"
class DeviceList extends StatelessWidget {
  const DeviceList({super.key, required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final devices = context.query(devicesOfKind(kind));
    final rows = devices.dataOrNull;
    if (rows == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.builder(
      // Where PageStorage files this list's offset.
      key: PageStorageKey<String>('devices-$kind'),
      itemCount: rows.length,
      itemBuilder: (context, index) => DeviceTile(rows[index]),
    );
  }
}

class DeviceTabs extends StatelessWidget {
  const DeviceTabs({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            bottom: const TabBar(
              tabs: <Widget>[Tab(text: 'Lights'), Tab(text: 'Shutters')],
            ),
          ),
          body: const TabBarView(
            children: <Widget>[
              DeviceList(kind: 'light'),
              DeviceList(kind: 'shutter'),
            ],
          ),
        ),
      );
}
```

Two details matter:

- **The spinner has no key.** While the rows are loading there is no list to
  restore; the `ListView` with the key is built only once there is data. The
  first time, that is after the fetch; every time after, it is the first
  frame.
- **One key per list.** Each tab's list files its offset under its own key
  (`devices-light`, `devices-shutter`), so switching tabs does not hand one
  list the other's position.

`AutomaticKeepAliveClientMixin` is the other way to keep a tab's position: it
keeps the whole tab alive while it is off screen. That costs the widgets'
memory, and the tab's queries keep a reader — so they keep polling and
refetching on focus. With a `PageStorageKey`, the tab is gone, its queries
have no reader, and it is rebuilt from the cache when it returns.

## How long the rows are there

The cache keeps a query without readers for its `gcTime` — five minutes by
default — before collecting it; see
[garbage collection](caching.md#garbage-collection). Come back within that
and the rows are there on the first frame. Come back later and the list
loads from scratch, and the saved offset has nothing to restore into.

For a list the user returns to after longer breaks, raise the `gcTime` on
that query. An [infinite query](infinite-queries.md) keeps every page it had
loaded — up to `maxPages` — so a long scrolled list comes back to its full
length, not to its first page.

## Across app restarts: state restoration

When the operating system ends a backgrounded app and the user returns to
it, Flutter's state restoration can bring the scroll position back: a
`restorationScopeId` on the app, a `restorationId` on the scrollable. The
data does not come back with it — the cache lives in memory — so the list
loads, and the restored offset applies once the rows are there. A long list
may briefly show the top first. There is no persistence of the cache in 1.0.

Try it: in the screen below, press *Load more* a couple of times and
scroll down, then press *Go to about*. The list is unmounted — its query has
no reader — and *Back to list* rebuilds it with every page on the first
frame and no new request.

<LiveDemo feature="load-more" />

:::note[In React Query]
The web has the browser's own scroll restoration, which works when the data
is cached and the first render has it; TanStack's guide says as much. In
Flutter the position is `PageStorage`'s or state restoration's, and the
cache supplies the same thing — the rows on the first build. See
[differences from TanStack Query](../reference/differences-from-tanstack.md).
:::
