---
title: Disconnecting a device
sidebar_label: Device and IoT disconnect
description: Stop every query for a device the user disconnected, with no request sent to it afterwards and no old reading left in the cache.
---

# Disconnecting a device

**The problem.** A thermostat app talks to devices on the local network over
Bluetooth or a socket. The device screen polls its status every two seconds.
When the user disconnects the kitchen thermostat, every query for it must
stop. No request may go to it afterwards: a closed Bluetooth connection
throws, and some transports reconnect by themselves if asked. And the cache
must not keep an old reading that looks current.

The obvious fix, `removeQueries` under the device's prefix, is not enough by
itself. An observer follows a **key**, not an entry. A screen still mounted
on that key recreates the entry on its next poll tick or rebuild, and fetches
again. The order is what matters.

**The recipe.** First make the transport refuse and let the screens stop
reading. Then remove the entries.

## Keys with one prefix per device

```dart title="lib/data/device_keys.dart" snippet="cookbook/device-and-iot-disconnect.md#keys"
abstract final class DeviceKeys {
  static final QueryKey all = QueryKey(<Object?>['devices']);

  /// Everything about one device lives under this prefix.
  static QueryKey device(String id) => all.append(<Object?>[id]);

  static QueryKey status(String id) => device(id).append(<Object?>['status']);
}
```

Everything about one device is under `DeviceKeys.device(id)`, so one filter
reaches all of it: status, settings, history.

## A transport that can say no

```dart title="lib/data/device_connection.dart" snippet="cookbook/device-and-iot-disconnect.md#connection"
class DeviceGone implements Exception {
  const DeviceGone(this.deviceId);

  final String deviceId;

  @override
  String toString() => 'Device $deviceId is disconnected';
}

class DeviceConnection {
  DeviceConnection(this.deviceId);

  final String deviceId;

  /// Whether the device may be talked to. Screens rebuild on it.
  final ValueNotifier<bool> open = ValueNotifier<bool>(true);

  Future<DeviceStatus> status({QueryCancelToken? signal}) async {
    _ensureOpen();
    return const DeviceStatus(temperature: 21.5); // the real call goes here
  }

  /// From here on every call refuses, before anything goes on the wire.
  void close() => open.value = false;

  void _ensureOpen() {
    if (!open.value) throw DeviceGone(deviceId);
  }
}
```

`close()` flips a `ValueNotifier`, so widgets can rebuild on it. After it, a
call throws `DeviceGone` before anything reaches the wire.

## A client that does not retry a gone device

```dart title="lib/app/query_client.dart" snippet="cookbook/device-and-iot-disconnect.md#client"
QueryClient buildDeviceClient() => QueryClient(
      defaultOptions: const DefaultOptions(
        queries: QueryDefaults(
          // A device on the local network answers whatever the phone's
          // internet connection says.
          networkMode: NetworkMode.always,
          retry: RetryPolicy.when(retryUnlessGone),
        ),
        // Not inherited from the query defaults: said again.
        mutations: MutationDefaults(networkMode: NetworkMode.always),
      ),
    );

bool retryUnlessGone(int failureCount, Object error, StackTrace _) =>
    error is! DeviceGone && failureCount < 2;
```

`NetworkMode.always`, because the phone's internet connection has nothing to
do with a device on the local network (see [Network
mode](../guides/network-mode.md)). The retry policy retries ordinary failures
twice and never retries `DeviceGone`: a closed connection does not come back
with a backoff.

## The query takes the connection's state as a value

```dart title="lib/data/device_queries.dart" snippet="cookbook/device-and-iot-disconnect.md#status-query"
QueryObserverOptions<DeviceStatus> deviceStatusQuery(
  DeviceConnection connection, {
  required bool open,
}) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.status(connection.deviceId),
      queryFn: (context) => connection.status(signal: context.signal),
      // Values, not callbacks: a closed connection rebuilds the screen, and
      // the rebuild hands the observer options that neither fetch nor poll.
      enabled: open ? Enabled.yes : Enabled.no,
      refetchInterval: open
          ? const RefetchInterval.every(Duration(seconds: 2))
          : RefetchInterval.off,
    );
```

`enabled` and `refetchInterval` are values computed from `open`, not
callbacks. A callback over outside state is only read again when something
hands the options over, so a value computed in the build makes that handover
explicit. When `open` flips, the screen rebuilds, and the rebuild gives the
observer options that neither fetch nor poll.

## The screen rebuilds on the connection

```dart title="lib/features/device/device_screen.dart" snippet="cookbook/device-and-iot-disconnect.md#screen"
class DeviceScreen extends StatelessWidget {
  const DeviceScreen({super.key, required this.connection});

  final DeviceConnection connection;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: connection.open,
        builder: (_, open, __) =>
            DeviceStatusView(connection: connection, open: open),
      );
}

class DeviceStatusView extends StatelessWidget {
  const DeviceStatusView(
      {super.key, required this.connection, required this.open});

  final DeviceConnection connection;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final status = context.query(deviceStatusQuery(connection, open: open));
    return ListTile(
      title: Text(connection.deviceId),
      subtitle: Text(switch (status) {
        _ when !open => 'Disconnected',
        QuerySuccess(:final data) => '${data.temperature} °C',
        QueryError(:final error) => '$error',
        QueryPending() => 'Connecting…',
      }),
    );
  }
}
```

## Disconnect: readers first, entries second

```dart title="lib/data/device_actions.dart" snippet="cookbook/device-and-iot-disconnect.md#disconnect"
Future<void> disconnect(QueryClient client, DeviceConnection connection) async {
  // 1. The transport refuses, and every screen of the device rebuilds with
  //    its queries disabled.
  connection.close();
  await WidgetsBinding.instance.endOfFrame;
  // 2. Only now the entries: no reader is left that would fetch them again.
  //    Removing an entry also cancels a fetch it still has in flight.
  client.removeQueries(
    filters: QueryFilters(queryKey: DeviceKeys.device(connection.deviceId)),
  );
}
```

`endOfFrame` waits for the rebuild that `close()` scheduled. When it
completes, every reader of the device has switched to disabled options, and
nothing fetches or polls the removed entries again. Removing an entry also
cancels a fetch it still has in flight, silently, so no separate
`cancelQueries` call is needed.

A reader that is still mounted and builds again after the removal resolves
its key afresh. It brings back an *empty* entry: no data and no request,
because its options are disabled. The old reading is gone either way, and
the empty entry is garbage collected `gcTime` after its last reader leaves.

## Steps

1. Put all of a device's keys under one prefix.
2. Give the transport a closed state that throws before sending.
3. Derive `enabled` and `refetchInterval` from that state in `build`.
4. On disconnect, close the transport, wait for the frame, then remove the
   prefix.

## Traps

- **Removing first.** The entry is gone for one frame. Then the next poll
  tick or rebuild of a still-mounted screen creates it again and fetches from
  a device that is gone.
- **An `Enabled.when` callback over the connection.** It is only read when
  the options are handed over again. Without a rebuild, the observer keeps
  its previous verdict and the poll continues. See
  [Troubleshooting](../reference/troubleshooting.md).
- **Relying on a navigation pop.** Popping the device screen releases its
  readers, but other screens may still read the same device: a dashboard
  tile, a notification badge. Close the transport so that every reader sees
  it.
- **Pending writes.** A mutation already in flight is not a query and is not
  removed. Find it with `client.mutationCache.findAll(filters:
  MutationFilters(mutationKey: …))` and call `cancel()` on it. A cancelled
  mutation fails, and its `onError` runs, so a rollback still happens. See
  [Cancelling mutations](../guides/cancelling-mutations.md).

## Variations

- **Leave the screen showing the last reading.** Skip `removeQueries` and
  let the disabled query keep its data. Show it greyed out with the
  `dataUpdatedAt` of the last reading. It is garbage collected after `gcTime`
  once no screen reads it.
- **Reconnect.** A new `DeviceConnection` whose `open` is `true` rebuilds the
  screen with enabled options, and the query fetches as if for the first
  time.
- **Many devices.** Each device has its own prefix and connection, so
  disconnecting one leaves the others' polls running.

## See it run

The invalidation and filters demo shows the mechanism this recipe works
around. Press *Remove post 2*: the entry disappears from the cache
(`status=absent`) but its reader keeps its last result. *Re-attach post 2*
resolves the key again, and the entry comes back with a fetch.

<LiveDemo feature="invalidation-and-filters" height={760} />

:::note[In React Query]
The same order applies there: `removeQueries` while a `useQuery` for that key
is mounted creates the entry again. The Flutter-specific part is waiting for
`endOfFrame`, the point where the rebuild with disabled options has
happened. See [differences from TanStack
Query](../reference/differences-from-tanstack.md).
:::
