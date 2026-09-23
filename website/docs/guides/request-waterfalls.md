---
title: Request waterfalls
description: When one request cannot start before another has answered — where waterfalls come from in a widget tree, and how hoisting, prefetching and flatter reads avoid them.
---

# Request waterfalls

A waterfall is a request that could have started earlier but waited for
another one to finish. Each step adds a full round trip, and on a phone
network a round trip is what the user waits for. Three requests of 300 ms
each take 300 ms side by side and 900 ms in a row.

The library does not create waterfalls, and it cannot remove them either:
they come from where the widgets that read the queries sit in the tree. This
page is about spotting them and flattening them.

## Where they come from

- **Nested widgets.** A parent reads its query and shows a spinner; only when
  its data arrives does it build the child, and only then does the child's
  query start. Neither request needed the other, but the tree made them wait.
- **Dependent queries.** The second query really does need the first one's
  answer — the readings of a device whose id comes from a scan. That one is
  in the data, not in the tree; see [dependent queries](dependent-queries.md).
- **Navigation.** The detail screen's query starts when its route is built,
  which is after the tap, after the transition has begun.
- **Code loaded on demand.** A deferred library on the web loads first, then
  the screen in it builds, then its query starts.

## Nested widgets

A device screen shows the device, and under it a chart of its energy use.
The chart is its own widget with its own query — which is good design — and
it is only built once the device has arrived:

```dart snippet="guides/request-waterfalls.md#nested"
class DeviceScreen extends StatelessWidget {
  const DeviceScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final device = context.query(deviceQuery(id));
    return switch (device) {
      QueryPending() => const Center(child: CircularProgressIndicator()),
      QueryError(:final error) => Center(child: Text('$error')),
      QuerySuccess(:final data) => Column(
          children: <Widget>[
            Text(data.name),
            // Built only once the device has arrived — and only then does
            // the chart's own query start.
            EnergyChart(deviceId: id),
          ],
        ),
    };
  }
}
```

The requests go out one after the other:

```text
device   |-------->
energy             |-------->
```

The energy query did not need the device. It only waited because the widget
that reads it is built inside the success branch. There are two fixes.

### Read both where the parent reads

Queries read in the same `build` start together. Read the chart's query in
the screen, and hand the chart its result:

```dart snippet="guides/request-waterfalls.md#hoisted"
class HoistedDeviceScreen extends StatelessWidget {
  const HoistedDeviceScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    // Both read in the same build: both requests start now, side by side.
    final device = context.query(deviceQuery(id));
    final energy = context.query(energyQuery(id));
    return switch (device) {
      QueryPending() => const Center(child: CircularProgressIndicator()),
      QueryError(:final error) => Center(child: Text('$error')),
      QuerySuccess(:final data) => Column(
          children: <Widget>[
            Text(data.name),
            EnergyChartView(energy),
          ],
        ),
    };
  }
}
```

```text
device   |-------->
energy   |-------->
```

The chart has become a plain widget that takes a `QueryResult`, which also
makes it easier to test. The cost is that the screen now knows what the
chart reads.

### Prefetch in the parent

When the child should keep its own query, the parent can start the same
request early without reading it, and the child joins it when it is built:

```dart snippet="guides/request-waterfalls.md#prefetch-in-parent"
class _PrefetchingDeviceScreenState extends State<PrefetchingDeviceScreen> {
  @override
  void initState() {
    super.initState();
    // The chart below will read this. Start it now, beside the device's own
    // request; the chart joins it, or finds the answer cached.
    QueryClientProvider.read(context).query(energyQuery(widget.id)).ignore();
  }

  @override
  Widget build(BuildContext context) {
    final device = context.query(deviceQuery(widget.id));
    return switch (device) {
      QueryPending() => const Center(child: CircularProgressIndicator()),
      QueryError(:final error) => Center(child: Text('$error')),
      QuerySuccess(:final data) => Column(
          children: <Widget>[
            Text(data.name),
            EnergyChart(deviceId: widget.id),
          ],
        ),
    };
  }
}
```

`client.query(...).ignore()` starts the fetch and forgets about it. When the
chart is built, its `context.query` finds the fetch in flight and joins it,
or finds the answer cached. Both widgets name the query through the same
options function, `energyQuery(id)`, which is what keeps the two in step: the
same key, the same function, the same `staleTime`.

## Dependent queries

When the second request needs the first one's answer, some waiting is
unavoidable — but it is often less than it looks. Ask whether the server can
answer the second question from what you *already* have: a device's readings
by the device id you navigated with, rather than by a sensor id that only the
device's detail contains. If it can, the dependency disappears and both
requests run side by side. If it cannot, [dependent
queries](dependent-queries.md) shows how to chain them with `enabled`.

## Navigation

The detail screen's queries cannot start before the screen is built — unless
someone else starts them. The row the user tapped knows exactly what the next
screen will read, so it can prefetch on tap, before the push, or earlier
still, on hover on the web and desktop. A route guard or a router's
`redirect` can do the same for deep links. [Prefetching](prefetching.md) has
the samples.

## Code loaded on demand

A `deferred as` import on the web downloads the library the first time
`loadLibrary()` is called, and the screen in it builds only afterwards. Start
the screen's query next to `loadLibrary()` rather than inside the screen: the
query's options live in your data layer, which is not deferred, so the two
downloads run side by side.

## Seeing it

The `prefetching` screen shows the difference a head start makes. Open a
post from the list without prefetching it: the detail waits for its own
request. Press a row's prefetch button first (tooltip *Prefetch post
N*), wait for its *prefetched* pill, then open it: the title is there at once
and no request is made.

<LiveDemo feature="prefetching" />

## Summary

| Waterfall | Fix |
|---|---|
| a child's query starts when the parent's data arrives | read both in the parent, or prefetch in the parent |
| the second query needs the first's answer | ask the server differently, or chain with `enabled` |
| the screen's query starts after navigation | prefetch on tap, hover or in the route guard |
| a deferred screen loads, then fetches | start the query beside `loadLibrary()` |

Two queries the server could answer in one response are the last kind: if
they always go together, one endpoint and one query beat two.

:::note[In React Query]
The same guide exists there, with Suspense and lazy components as the usual
culprits. Flutter has neither, so the cases here are nested widgets,
navigation and deferred imports, and the fixes are the same: hoist the read,
or prefetch with `queryClient.prefetchQuery` — `client.query(...).ignore()`
here.
:::
