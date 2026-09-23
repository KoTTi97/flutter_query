---
title: Parallel queries
description: Several queries at once — separate reads that run side by side in every call style, QueriesBuilder for a list that changes length or order, and one loading indicator over all of them.
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

# Parallel queries

A home screen rarely needs one thing. The dashboard of a smart-home app wants
the rooms and the devices; the energy panel wants one reading per device on
screen, however many that is. Fetched one after the other, each request waits
for the one before it — a waterfall, and a slower screen for no reason.

Queries that do not depend on each other run in parallel, and there is
nothing to set up: each read starts its fetch when it subscribes.

## A fixed number of queries

Read each one. Both reads subscribe in the same build, so both requests are
in flight at once. The same dashboard in each of the [four call
styles](reading-queries-in-widgets.md):

<Tabs groupId="call-style">
<TabItem value="context" label="context.query">

```dart snippet="guides/parallel-queries.md#context"
class HomeDashboard extends StatelessWidget {
  const HomeDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    // Both reads subscribe in this build, so both requests start now.
    final rooms = context.query(roomsQuery());
    final devices = context.query(devicesQuery());

    return DashboardView(rooms: rooms, devices: devices);
  }
}
```

</TabItem>
<TabItem value="builder" label="QueryBuilder">

```dart snippet="guides/parallel-queries.md#builder"
Widget homeDashboard() => QueryBuilder<List<Room>>(
      options: roomsQuery(),
      builder: (context, rooms) => QueryBuilder<List<Device>>(
        options: devicesQuery(),
        builder: (context, devices) =>
            DashboardView(rooms: rooms, devices: devices),
      ),
    );
```

Nesting does not serialise the requests: the outer builder's child — the
inner builder — is built in the same frame, before either answer arrives.

</TabItem>
<TabItem value="mixin" label="QueryMixin">

```dart snippet="guides/parallel-queries.md#mixin"
class _HomeDashboardMixinState extends State<HomeDashboardMixin>
    with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final rooms = watchQuery(roomsQuery());
    final devices = watchQuery(devicesQuery());

    return DashboardView(rooms: rooms, devices: devices);
  }
}
```

</TabItem>
<TabItem value="controller" label="QueryController">

```dart snippet="guides/parallel-queries.md#controller"
class _HomeDashboardControllersState extends State<HomeDashboardControllers> {
  late final QueryController<List<Room>, List<Room>> _rooms;
  late final QueryController<List<Device>, List<Device>> _devices;

  @override
  void initState() {
    super.initState();
    final client = QueryClientProvider.read(context);
    _rooms = QueryController.create(client, roomsQuery());
    _devices = QueryController.create(client, devicesQuery());
  }

  @override
  void dispose() {
    _rooms.dispose();
    _devices.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[_rooms, _devices]),
        builder: (context, _) =>
            DashboardView(rooms: _rooms.value, devices: _devices.value),
      );
}
```

</TabItem>
</Tabs>

Each result settles on its own: the rooms can be on screen while the devices
still load, and one failing does not touch the other. When the screen wants
the two as one value — loading while either loads, an error if either failed
— [combine them](combining-queries.md).

The showcase's *parallel queries* screen reads three posts side by side.
Opening it shows `fetching=3` before any answer arrives. Switch *Slow post 3*
on and press *Refetch all*: the other two settle while post 3 still fetches,
and the count drops to `fetching=1`. *Refetch post 2* moves only that post's
`fetches`:

<LiveDemo feature="parallel-queries" />

## A list of queries

When the set of queries is data — one reading per device on screen — you
cannot write one read per query in source. `QueriesBuilder` observes a list
that may change length or order:

```dart snippet="guides/parallel-queries.md#energy-query guides/parallel-queries.md#queries-builder-devices"
QueryObserverOptions<EnergyReading> energyQuery(String deviceId) =>
    QueryObserverOptions(
      queryKey: QueryKey(<Object?>['energy', deviceId]),
      queryFn: (context) => repository.energy(deviceId, signal: context.signal),
    );

// One reading per device on screen — however many that is.
Widget energyPanel(List<String> deviceIds) =>
    QueriesBuilder<EnergyReading, double>(
      queries: <QuerySelectOptions<EnergyReading, double>>[
        for (final id in deviceIds)
          energyQuery(id).withSelect((reading) => reading.watts),
      ],
      builder: (context, results) => switch (results.combine(
        (watts) => watts.fold<double>(0, (sum, each) => sum + each),
      )) {
        CombinedPending() => const Text('Measuring…'),
        CombinedError(:final error) => Text('No reading: $error'),
        CombinedData(:final data) => Text('${data.toStringAsFixed(1)} W now'),
      },
    );
```

- **One description per query.** `energyQuery(id)` is an ordinary options
  function; `withSelect` narrows each reading to its watts, so a refetch that
  brings back the same reading rebuilds nothing.
- **Observers are reused by key and occurrence**, so reordering the list
  starts no requests, and adding an id fetches only the new one.
- **Duplicate keys** share one cache entry while keeping their own observers.
- **Each query fails and settles on its own**; `combine` then turns the list
  into one value, pending until every member has data. See [combining
  queries](combining-queries.md).

It is homogeneous: one data type per collection, because a Dart `List` has
one element type. For queries of **different** types, read each one as above
and combine the results. The other call styles have the same collection:
`QueriesController(client, queries)` is it as a `ValueListenable`, and
`QueriesObserver` is it without Flutter.

The showcase's *query collections* screen is a list of posts built from a
list of ids. *Reverse* reorders them without a single request; *Duplicate
first* adds a second reader of the same entry (`observers=2`, still one
fetch); *Add missing id* adds a post the server does not have, which fails
alone while its neighbours keep their data:

<LiveDemo feature="query-collections" />

## One indicator for many queries

Parallel queries each report their own `isFetching`. For a single "syncing"
bar over all of them — whichever screen started them — count them instead:

```dart snippet="guides/parallel-queries.md#is-fetching"
// A thin bar under the app bar while any device query is fetching — however
// many there are, and whichever screen started them.
class _DevicesSyncIndicatorState extends State<DevicesSyncIndicator> {
  late final IsFetchingController _fetching = IsFetchingController(
    QueryClientProvider.read(context),
    filters: QueryFilters(queryKey: DeviceKeys.all),
  );

  @override
  void dispose() {
    _fetching.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: _fetching,
        builder: (context, count, _) => count > 0
            ? const LinearProgressIndicator(minHeight: 2)
            : const SizedBox(height: 2),
      );
}
```

`IsFetchingController` is a `ValueListenable<int>` that notifies only when
the count changes, and the filters narrow it — here to every key under
`['devices']`. `client.isFetching(filters: …)` is the same count as a
one-off snapshot.

## Traps

- **A waterfall by accident.** Reading one query only in the success branch
  of another serialises them. That is right when the second needs the
  first's data — see [dependent queries](dependent-queries.md) — and a
  needless wait when it does not.
- **A hand-written list of reads for a data-driven set.** When which queries
  run comes from data, give each item its own widget — see [a row per
  item](reading-queries-in-widgets.md) — or use `QueriesBuilder`, so the set
  of observers follows the list as it changes.

:::note[In React Query]
Two `useQuery` calls side by side are two reads here too. `useQueries` is
`QueriesBuilder` / `QueriesController`, homogeneous by design — a
heterogeneous tuple is a record of separate reads, combined with
`(a, b).combine(…)`. `useIsFetching` is `IsFetchingController`. See
[differences from TanStack Query](../reference/differences-from-tanstack.md).
:::
