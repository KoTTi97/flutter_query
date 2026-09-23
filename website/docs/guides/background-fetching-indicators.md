---
title: Background fetching indicators
description: Show that a query is refreshing without hiding the data it already has — isRefetching on one result, and IsFetchingController for an app-wide progress bar.
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

# Background fetching indicators

A screen that already shows data should keep showing it while that data is
refreshed. Dropping back to a full-screen spinner every time the app comes to
the foreground, or every time a mutation invalidates the list, makes a fast
app feel slow. What the screen wants instead is a quiet sign that something
is in flight: a thin bar under the app bar, a small spinner in a header.

A result answers two separate questions:

- **`status`** — does the query have data? `QueryPending`, `QuerySuccess` or
  `QueryError`, the three variants of the sealed result.
- **`fetchStatus`** — is a request running right now? `fetching`, `paused`
  or `idle`.

A background refresh is the combination the spinner-only approach misses:
`QuerySuccess` **and** `fetching`. See [queries](queries.md#what-the-query-is-doing-fetchstatus)
for the full table.

| On the result | True when |
|---|---|
| `isFetching` | any fetch of this query is running — the first load and every refresh |
| `isLoading` | the first load: pending **and** fetching |
| `isRefetching` | a refresh of data already there: fetching **and not** pending |
| `isPaused` | a fetch wants to run but is waiting for the network or for focus |

## First load or refresh

The device list of a smart-home app, with its keys and options in one file:

```dart snippet="guides/background-fetching-indicators.md#device-queries"
// lib/data/device_queries.dart
abstract final class DeviceKeys {
  static final QueryKey all = QueryKey(<Object?>['devices']);
  static final QueryKey list = all.append(<Object?>['list']);
  static QueryKey byKind(String kind) => all.append(<Object?>['kind', kind]);
  static QueryKey page(int page) => all.append(<Object?>['page', page]);
  static QueryKey detail(String id) => all.append(<Object?>['detail', id]);
  static QueryKey activity(String id) => all.append(<Object?>['activity', id]);
}

abstract final class DeviceQueries {
  static QueryObserverOptions<List<Device>> list() => QueryObserverOptions(
        queryKey: DeviceKeys.list,
        queryFn: (context) => deviceRepository.list(signal: context.signal),
      );
}
```

The body of the list screen switches on the result. The first load gets the
whole area; a refresh gets two pixels above data that stays where it is:

```dart snippet="guides/background-fetching-indicators.md#first-load-or-refresh"
Widget deviceListBody(QueryResult<List<Device>> devices) => switch (devices) {
      // Nothing to show yet: the whole area is the spinner.
      QueryPending() => const Center(child: CircularProgressIndicator()),
      QueryError(:final error) => Center(child: Text('No devices: $error')),
      // Data on screen: keep it, and say quietly that it is being refreshed.
      QuerySuccess(:final data, :final isRefetching) => Column(
          children: <Widget>[
            if (isRefetching) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView(
                children: <Widget>[
                  for (final device in data) DeviceTile(device),
                ],
              ),
            ),
          ],
        ),
    };
```

A failed refresh does not throw the data away either: the result is a
`QueryError` whose `staleData` still holds the list, and `hasStaleData` says
so. Whether to show the rows with a warning or only the error is the screen's
decision; see [queries](queries.md).

## One query's indicator, in each call style

The same header — "Devices", and a small spinner while the list refreshes —
in the four ways to read a query. They are equal: pick the one your widget is
already written in. See [four ways to read a query](reading-queries-in-widgets.md).

<Tabs groupId="call-style">
<TabItem value="context-query" label="context.query">

```dart snippet="guides/background-fetching-indicators.md#header-context-query"
class DevicesHeader extends StatelessWidget {
  const DevicesHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final devices = context.query(DeviceQueries.list());
    return ListTile(
      title: const Text('Devices'),
      trailing: devices.isRefetching ? const RefreshingSpinner() : null,
    );
  }
}
```

</TabItem>
<TabItem value="query-builder" label="QueryBuilder">

```dart snippet="guides/background-fetching-indicators.md#header-builder"
class DevicesHeaderBuilder extends StatelessWidget {
  const DevicesHeaderBuilder({super.key});

  @override
  Widget build(BuildContext context) => QueryBuilder(
        options: DeviceQueries.list(),
        builder: (context, devices) => ListTile(
          title: const Text('Devices'),
          trailing: devices.isRefetching ? const RefreshingSpinner() : null,
        ),
      );
}
```

</TabItem>
<TabItem value="query-mixin" label="QueryMixin">

```dart snippet="guides/background-fetching-indicators.md#header-mixin"
class _DevicesHeaderMixinState extends State<DevicesHeaderMixin>
    with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final devices = watchQuery(DeviceQueries.list());
    return ListTile(
      title: const Text('Devices'),
      trailing: devices.isRefetching ? const RefreshingSpinner() : null,
    );
  }
}
```

</TabItem>
<TabItem value="query-controller" label="QueryController">

```dart snippet="guides/background-fetching-indicators.md#header-controller"
class _DevicesHeaderControllerState extends State<DevicesHeaderController> {
  late final QueryController<List<Device>, List<Device>> _devices =
      QueryController.create(
    QueryClientProvider.read(context),
    DeviceQueries.list(),
  );

  @override
  void dispose() {
    _devices.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: _devices,
        builder: (context, devices, _) => ListTile(
          title: const Text('Devices'),
          trailing: devices.isRefetching ? const RefreshingSpinner() : null,
        ),
      );
}
```

</TabItem>
</Tabs>

The header and the list body can read the same key in two widgets. They
share one cache entry and one request; each widget rebuilds for its own read.

## Every query: a global progress bar

A bar that shows while *anything* loads is not about one query, so it does
not read one. `IsFetchingController` counts the queries whose `fetchStatus`
is `fetching` right now, as a `ValueListenable<int>`:

```dart snippet="guides/background-fetching-indicators.md#global-indicator"
class FetchingBar extends StatefulWidget {
  const FetchingBar({super.key});

  @override
  State<FetchingBar> createState() => _FetchingBarState();
}

class _FetchingBarState extends State<FetchingBar> {
  late final IsFetchingController _fetching =
      IsFetchingController(QueryClientProvider.read(context));

  @override
  void dispose() {
    _fetching.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: _fetching,
        builder: (context, count, _) => count == 0
            ? const SizedBox(height: 2)
            : const LinearProgressIndicator(minHeight: 2),
      );
}
```

`QueryClientProvider.read` looks the client up without subscribing to the
provider, which is what a `late final` field initialiser wants. The
controller subscribes to the cache only while something listens to it, and
notifies only when the count changes, not for every cache event.

Put it where every screen shows it. Under the app bar's title, it costs no
layout: two pixels, empty or filled.

```dart snippet="guides/background-fetching-indicators.md#app-bar"
class DevicesScaffold extends StatelessWidget {
  const DevicesScaffold({super.key, required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('My home'),
          // Two pixels under the title: empty, or a bar while anything loads.
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(2),
            child: FetchingBar(),
          ),
        ),
        body: body,
      );
}
```

A paused fetch — offline under the default [network mode](network-mode.md) —
is not counted: nothing is in flight, so a bar that stayed on would lie.

### Only some queries

`filters:` narrows the count, with the same `QueryFilters` every bulk
operation takes (see [filters](filters.md)). A sync badge on the devices tab
counts only what lives under `['devices']`:

```dart snippet="guides/background-fetching-indicators.md#filtered"
// Every query under ['devices'] — the list, the pages, each detail.
late final IsFetchingController _devicesFetching = IsFetchingController(
  QueryClientProvider.read(context),
  filters: QueryFilters(queryKey: DeviceKeys.all),
);
```

The filters are fixed for the controller's life; another set is another
controller. Without a widget, `client.isFetching(filters: …)` is the same
count, read once.

Try it: open the screen below, turn on *Slow post 3* and press
*Refetch all*. The `fetching=` count next to the button drops as the fast posts
land and stays at one while post 3 is still on its way, and each post's own
row says `refreshing` while its data stays on screen.

<LiveDemo feature="parallel-queries" />

### Mutations in flight

`client.isMutating()` is the count of running mutations, read once. To
subscribe to it — a "saving…" label — use a `MutationStateController`
filtered on `MutationStatus.pending`; the length of its list is the count.
See [mutation state](mutation-state.md).

:::note[In React Query]
`isFetching` and `isRefetching` are the fields of the same name on
`useQuery`'s result, and `IsFetchingController` is `useIsFetching`. The count
is the same; it is a `ValueListenable` because a Flutter widget subscribes
through one. See [differences from TanStack Query](../reference/differences-from-tanstack.md).
:::
