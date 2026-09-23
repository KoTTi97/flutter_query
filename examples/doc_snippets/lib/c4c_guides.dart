/// The samples of the mutation, cache and performance guides that show an
/// app rather than a single call: a smart-home app's devices, the rooms they
/// sit in, and its notification settings.
///
/// Same rule as the rest of this package — each region is marked with the
/// page that shows it, and the fence on that page names the region. The
/// repositories below stand in for the app's HTTP layer; the pages show the
/// dio version of one as prose, because neither published package may depend
/// on dio.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'guides.dart' show messengerKey;

// ---------------------------------------------------------------------------
// The domain: devices in rooms, and the settings of the app's user.
// ---------------------------------------------------------------------------

@immutable
class Device {
  const Device({
    required this.id,
    required this.name,
    required this.room,
    this.isOn = false,
  });

  factory Device.fromJson(Map<String, Object?> json) => Device(
        id: json['id']! as String,
        name: json['name']! as String,
        room: json['room']! as String,
        isOn: json['isOn']! as bool,
      );

  final String id;
  final String name;
  final String room;
  final bool isOn;

  Device copyWith({String? name, bool? isOn}) => Device(
        id: id,
        name: name ?? this.name,
        room: room,
        isOn: isOn ?? this.isOn,
      );

  @override
  bool operator ==(Object other) =>
      other is Device &&
      other.id == id &&
      other.name == name &&
      other.room == room &&
      other.isOn == isOn;

  @override
  int get hashCode => Object.hash(id, name, room, isOn);
}

class DeviceRepository {
  Future<List<Device>> list({
    required String room,
    QueryCancelToken? signal,
  }) async =>
      const <Device>[];

  Future<Device> get(String id, {QueryCancelToken? signal}) async =>
      Device(id: id, name: 'Desk lamp', room: 'office');

  Future<List<double>> energy(String id, {QueryCancelToken? signal}) async =>
      const <double>[];

  Future<List<String>> firmwareChannels({QueryCancelToken? signal}) async =>
      const <String>['stable'];

  Future<Device> add({required String name, required String room}) async =>
      Device(id: 'd-1', name: name, room: room);

  Future<Device> rename(String id, String name) async =>
      Device(id: id, name: name, room: 'office');

  Future<Device> move(String id, String room) async =>
      Device(id: id, name: 'Desk lamp', room: room);

  Future<Device> setPower(String id, {required bool on}) async =>
      Device(id: id, name: 'Desk lamp', room: 'office', isOn: on);

  Future<Device> uploadFirmware(
    String id,
    Uint8List image, {
    QueryCancelToken? signal,
  }) async =>
      Device(id: id, name: 'Desk lamp', room: 'office');

  Future<void> remove(String id) async {}
}

/// The one repository the app builds at startup.
final DeviceRepository devices = DeviceRepository();

@immutable
class NotificationSettings {
  const NotificationSettings({required this.pushEnabled});

  final bool pushEnabled;

  NotificationSettings copyWith({bool? pushEnabled}) =>
      NotificationSettings(pushEnabled: pushEnabled ?? this.pushEnabled);

  @override
  bool operator ==(Object other) =>
      other is NotificationSettings && other.pushEnabled == pushEnabled;

  @override
  int get hashCode => pushEnabled.hashCode;
}

class SettingsRepository {
  Future<NotificationSettings> load({QueryCancelToken? signal}) async =>
      const NotificationSettings(pushEnabled: true);

  Future<NotificationSettings> save(NotificationSettings settings) async =>
      settings;
}

final SettingsRepository settingsRepository = SettingsRepository();

/// A JSON client, for the default query function's page.
class ApiClient {
  Future<Object?> getJson(
    String path, {
    Map<String, Object?> query = const <String, Object?>{},
    QueryCancelToken? signal,
  }) async =>
      null;

  Future<Object?> postJson(String path, Object? body) async => null;
}

// ---------------------------------------------------------------------------
// guides/query-invalidation.md
// ---------------------------------------------------------------------------

// >>> guides/query-invalidation.md#device-keys
// lib/data/device_keys.dart
abstract final class DeviceKeys {
  static final QueryKey all = QueryKey(<Object?>['devices']);

  static final QueryKey lists = all.append(<Object?>['list']);

  static QueryKey list({required String room}) => lists.append(<Object?>[room]);

  static final QueryKey details = all.append(<Object?>['detail']);

  static QueryKey detail(String id) => details.append(<Object?>[id]);
}
// <<<

Future<void> invalidationInAnApp(QueryClient client, Device device) async {
  // >>> guides/query-invalidation.md#device-invalidations
  // Something changed about this device: its detail, and every room list.
  await client.invalidateQueries(
    filters: QueryFilters(queryKey: DeviceKeys.detail(device.id)),
  );
  await client.invalidateQueries(
    filters: QueryFilters(queryKey: DeviceKeys.lists),
  );

  // A bulk import from the hub: everything about devices is suspect.
  await client.invalidateQueries(
    filters: QueryFilters(queryKey: DeviceKeys.all),
  );
  // <<<
}

Future<void> invalidateByPredicate(QueryClient client) async {
  // >>> guides/query-invalidation.md#predicate
  // The kitchen and the hallway were merged on the hub: invalidate the lists
  // of both rooms, and nothing else.
  const merged = <String>{'kitchen', 'hallway'};
  await client.invalidateQueries(
    filters: QueryFilters(
      queryKey: DeviceKeys.lists,
      predicate: (query) => merged.contains(query.queryKey.parts.last),
    ),
  );
  // <<<
}

// ---------------------------------------------------------------------------
// guides/caching.md
// ---------------------------------------------------------------------------

// >>> guides/caching.md#device-queries
// lib/data/device_queries.dart
QueryObserverOptions<List<Device>> roomDevicesQuery(String room) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.list(room: room),
      queryFn: (context) => devices.list(room: room, signal: context.signal),
      // Switching between room tabs within ten seconds costs no request.
      staleTime: const StaleTime.duration(Duration(seconds: 10)),
    );

QueryObserverOptions<Device> deviceQuery(String id) => QueryObserverOptions(
      queryKey: DeviceKeys.detail(id),
      queryFn: (context) => devices.get(id, signal: context.signal),
      staleTime: const StaleTime.duration(Duration(seconds: 10)),
    );

QueryObserverOptions<List<double>> energyQuery(String id) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.detail(id).append(<Object?>['energy']),
      queryFn: (context) => devices.energy(id, signal: context.signal),
      // Hourly readings: a minute old is new enough.
      staleTime: const StaleTime.duration(Duration(minutes: 1)),
    );

QueryObserverOptions<List<String>> firmwareChannelsQuery() =>
    QueryObserverOptions(
      queryKey: QueryKey(<Object?>['firmware-channels']),
      queryFn: (context) => devices.firmwareChannels(signal: context.signal),
      // Changes with a server release, not while the app runs: fetch it once
      // and keep it for the session.
      staleTime: StaleTime.static,
      gcTime: GcTime.never,
    );
// <<<

// >>> guides/caching.md#client-defaults
// lib/main.dart
final QueryClient appClient = QueryClient(
  defaultOptions: const DefaultOptions(
    queries: QueryDefaults(
      staleTime: StaleTime.duration(Duration(seconds: 20)),
      gcTime: GcTime.duration(Duration(minutes: 10)),
    ),
  ),
);
// <<<

// ---------------------------------------------------------------------------
// guides/mutations.md — one mutation, four call styles
// ---------------------------------------------------------------------------

// >>> guides/mutations.md#set-power
// lib/data/device_mutations.dart
MutationOptions<Device, bool, void> setPowerMutation(
  QueryClient client,
  String id,
) =>
    MutationOptions.simple(
      mutationFn: (bool on) => devices.setPower(id, on: on),
      onSuccess: (device, _, __) {
        client.setQueryData<Device>(DeviceKeys.detail(id), device);
        client
            .invalidateQueries(
              filters: QueryFilters(queryKey: DeviceKeys.lists),
            )
            .ignore();
      },
    );
// <<<

// >>> guides/mutations.md#switch-context
class PowerSwitch extends StatelessWidget {
  const PowerSwitch({super.key, required this.device});

  final Device device;

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    final power = context.mutation(setPowerMutation(client, device.id));
    final result = power.value;
    return Switch(
      // While the write is out, show what was asked for.
      value: result.isPending ? result.variables! : device.isOn,
      onChanged: result.isPending ? null : power.mutate,
    );
  }
}
// <<<

// >>> guides/mutations.md#switch-builder
Widget powerSwitch(QueryClient client, Device device) => MutationBuilder(
      options: setPowerMutation(client, device.id),
      builder: (context, power) {
        final result = power.value;
        return Switch(
          value: result.isPending ? result.variables! : device.isOn,
          onChanged: result.isPending ? null : power.mutate,
        );
      },
    );
// <<<

class MixinPowerSwitch extends StatefulWidget {
  const MixinPowerSwitch({super.key, required this.device});

  final Device device;

  @override
  State<MixinPowerSwitch> createState() => _MixinPowerSwitchState();
}

// >>> guides/mutations.md#switch-mixin
class _MixinPowerSwitchState extends State<MixinPowerSwitch> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final power = watchMutation(setPowerMutation(queryClient, device.id));
    final result = power.value;
    return Switch(
      value: result.isPending ? result.variables! : device.isOn,
      onChanged: result.isPending ? null : power.mutate,
    );
  }
}
// <<<

class ControllerPowerSwitch extends StatefulWidget {
  const ControllerPowerSwitch({super.key, required this.device});

  final Device device;

  @override
  State<ControllerPowerSwitch> createState() => _ControllerPowerSwitchState();
}

// >>> guides/mutations.md#switch-controller
class _ControllerPowerSwitchState extends State<ControllerPowerSwitch> {
  late final QueryClient _client = QueryClientProvider.read(context);
  late final MutationController<Device, bool, void> _power =
      MutationController(_client, setPowerMutation(_client, widget.device.id));

  @override
  void dispose() {
    _power.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<MutationResult<Device, bool>>(
        valueListenable: _power,
        builder: (context, result, _) => Switch(
          value: result.isPending ? result.variables! : widget.device.isOn,
          onChanged: result.isPending ? null : _power.mutate,
        ),
      );
}
// <<<

// ---------------------------------------------------------------------------
// guides/invalidations-from-mutations.md
// ---------------------------------------------------------------------------

// >>> guides/invalidations-from-mutations.md#remove-device
// lib/data/device_mutations.dart
MutationOptions<void, String, void> removeDeviceMutation(QueryClient client) =>
    MutationOptions.simple(
      mutationFn: devices.remove,
      onSuccess: (_, id, __) {
        // The device is gone: drop its detail rather than refetch a 404 …
        client.removeQueries(
          filters: QueryFilters(queryKey: DeviceKeys.detail(id)),
        );
        // … and refetch every room list that may have shown it.
        return client.invalidateQueries(
          filters: QueryFilters(queryKey: DeviceKeys.lists),
        );
      },
    );
// <<<

// >>> guides/invalidations-from-mutations.md#move-device
MutationOptions<Device, String, void> moveDeviceMutation(
  QueryClient client,
  Device device,
) =>
    MutationOptions.simple(
      mutationFn: (String toRoom) => devices.move(device.id, toRoom),
      // Two lists changed. Both refetches run at once, and the mutation
      // settles when both have landed.
      onSuccess: (moved, toRoom, _) => Future.wait(<Future<void>>[
        client.invalidateQueries(
          filters: QueryFilters(queryKey: DeviceKeys.list(room: device.room)),
        ),
        client.invalidateQueries(
          filters: QueryFilters(queryKey: DeviceKeys.list(room: toRoom)),
        ),
      ]),
    );
// <<<

// >>> guides/invalidations-from-mutations.md#do-not-wait
MutationOptions<Device, String, void> renameDeviceQuickly(
  QueryClient client,
  String id,
) =>
    MutationOptions.simple(
      mutationFn: (String name) => devices.rename(id, name),
      // A block body that returns nothing: the mutation succeeds as soon as
      // the server has answered, and the lists refresh behind it.
      onSuccess: (_, __, ___) {
        client
            .invalidateQueries(
              filters: QueryFilters(queryKey: DeviceKeys.all),
            )
            .ignore();
      },
    );
// <<<

// ---------------------------------------------------------------------------
// guides/updates-from-mutation-responses.md
// ---------------------------------------------------------------------------

// >>> guides/updates-from-mutation-responses.md#settings
// lib/data/settings_queries.dart
final QueryKey settingsKey = QueryKey(<Object?>['settings', 'notifications']);

QueryObserverOptions<NotificationSettings> settingsQuery() =>
    QueryObserverOptions(
      queryKey: settingsKey,
      queryFn: (context) => settingsRepository.load(signal: context.signal),
    );

MutationOptions<NotificationSettings, NotificationSettings, void>
    saveSettingsMutation(QueryClient client) => MutationOptions.simple(
          mutationFn: settingsRepository.save,
          // The server answers with what it stored — defaults applied,
          // values clamped. That is the new truth; there is nothing to
          // fetch.
          onSuccess: (saved, _, __) {
            client.setQueryData(settingsKey, saved);
          },
        );
// <<<

// >>> guides/updates-from-mutation-responses.md#settings-screen
class NotificationSettingsTile extends StatelessWidget {
  const NotificationSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    final settings = context.query(settingsQuery()).dataOrNull;
    final save = context.mutation(saveSettingsMutation(client));
    if (settings == null) return const LinearProgressIndicator();

    return SwitchListTile(
      title: const Text('Push notifications'),
      subtitle: save.value.isError ? const Text('Could not save') : null,
      value: settings.pushEnabled,
      onChanged: save.value.isPending
          ? null
          : (on) => save.mutate(settings.copyWith(pushEnabled: on)),
    );
  }
}
// <<<

// >>> guides/updates-from-mutation-responses.md#rename-everywhere
MutationOptions<Device, String, void> renameDeviceMutation(
  QueryClient client,
  String id,
) =>
    MutationOptions.simple(
      mutationFn: (String name) => devices.rename(id, name),
      onSuccess: (renamed, _, __) {
        client.setQueryData<Device>(DeviceKeys.detail(id), renamed);
        // Every room list that holds it gets a new list with the new device;
        // `null` leaves the others untouched.
        client.updateQueriesData<List<Device>>(
          (list) => list == null || !list.any((device) => device.id == id)
              ? null
              : <Device>[
                  for (final device in list) device.id == id ? renamed : device,
                ],
          filters: QueryFilters(queryKey: DeviceKeys.lists),
        );
      },
    );
// <<<

void immutability(QueryClient client, QueryKey key, Device device) {
  // >>> guides/updates-from-mutation-responses.md#immutability
  // Wrong: the cached list changes under every reader, and none is told.
  client.getQueryData<List<Device>>(key)?.add(device);

  // Right: a new list. The cache compares it, stores it and notifies.
  client.updateQueryData<List<Device>>(
    key,
    (list) => <Device>[...?list, device],
  );
  // <<<
}

// ---------------------------------------------------------------------------
// guides/optimistic-updates.md
// ---------------------------------------------------------------------------

// >>> guides/optimistic-updates.md#add-device
// lib/data/device_mutations.dart
QueryKey addDeviceKey(String room) => QueryKey(<Object?>['add-device', room]);

MutationOptions<Device, String, void> addDeviceMutation(
  QueryClient client,
  String room,
) =>
    MutationOptions.simple(
      mutationKey: addDeviceKey(room),
      mutationFn: (String name) => devices.add(name: name, room: room),
      // Returned, so the mutation stays pending — and its greyed row on
      // screen — until the list has refetched with the real row in it.
      onSettled: (_, __, ___, ____, _____) => client.invalidateQueries(
        filters: QueryFilters(queryKey: DeviceKeys.list(room: room)),
      ),
    );
// <<<

// >>> guides/optimistic-updates.md#via-ui
class RoomDeviceList extends StatelessWidget {
  const RoomDeviceList({super.key, required this.room});

  final String room;

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    final list = context.query(roomDevicesQuery(room));
    final add = context.mutation(addDeviceMutation(client, room));

    return ListView(
      children: <Widget>[
        for (final device in list.dataOrNull ?? const <Device>[])
          DeviceTile(device: device),
        // The write in flight, drawn from what it was called with.
        if (add.value case MutationPending(:final variables?))
          Opacity(opacity: 0.5, child: ListTile(title: Text(variables))),
        // A failed write keeps its variables: offer to send them again.
        if (add.value case MutationError(:final variables?))
          ListTile(
            title: Text(variables),
            subtitle: const Text('Not saved'),
            trailing: TextButton(
              onPressed: () => add.mutate(variables),
              child: const Text('Retry'),
            ),
          ),
        AddDeviceField(onSubmit: add.mutate),
      ],
    );
  }
}
// <<<

class PendingDevices extends StatefulWidget {
  const PendingDevices({super.key, required this.room});

  final String room;

  @override
  State<PendingDevices> createState() => _PendingDevicesState();
}

// >>> guides/optimistic-updates.md#elsewhere
class _PendingDevicesState extends State<PendingDevices> {
  // Every pending add for this room, wherever in the app it was started.
  late final MutationStateController<String> _adding =
      MutationStateController.typed(
    QueryClientProvider.read(context),
    filters: MutationFilters(
      mutationKey: addDeviceKey(widget.room),
      status: MutationStatus.pending,
    ),
    select: (Mutation<Object?, String, Object?> mutation) =>
        mutation.state.variables!,
  );

  @override
  void dispose() {
    _adding.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<String>>(
        valueListenable: _adding,
        builder: (context, names, _) => Column(
          children: <Widget>[
            for (final name in names)
              Opacity(opacity: 0.5, child: ListTile(title: Text(name))),
          ],
        ),
      );
}
// <<<

// >>> guides/optimistic-updates.md#via-cache
int _temporaryIds = 0;

MutationOptions<Device, String, String> addDeviceOptimistically(
  QueryClient client,
  String room,
) {
  final key = DeviceKeys.list(room: room);
  return MutationOptions<Device, String, String>(
    mutationFn: (name) => devices.add(name: name, room: room),
    onMutate: (name) async {
      // A refetch already in flight would land after the patch and undo it.
      await client.cancelQueries(filters: QueryFilters(queryKey: key));
      // Until the server names the device, a temporary id marks the row.
      final temporaryId = 'pending-${_temporaryIds++}';
      client.updateQueryData<List<Device>>(
        key,
        (list) => <Device>[
          ...?list,
          Device(id: temporaryId, name: name, room: room),
        ],
      );
      return temporaryId; // what onSuccess and onError need to find the row
    },
    onSuccess: (device, _, temporaryId) {
      // Swap in the server's device at once; the refetch below confirms it.
      client.updateQueryData<List<Device>>(
        key,
        (list) => list == null
            ? null
            : <Device>[
                for (final row in list) row.id == temporaryId ? device : row,
              ],
      );
    },
    onError: (error, stackTrace, name, temporaryId) {
      // Take out this row only: another add may be in flight beside it.
      client.updateQueryData<List<Device>>(
        key,
        (list) => list?.where((row) => row.id != temporaryId).toList(),
      );
    },
    onSettled: (_, __, ___, ____, _____) =>
        client.invalidateQueries(filters: QueryFilters(queryKey: key)),
  );
}
// <<<

// ---------------------------------------------------------------------------
// guides/mutation-scopes.md
// ---------------------------------------------------------------------------

// >>> guides/mutation-scopes.md#per-device
MutationOptions<Device, bool, void> setPowerInOrder(
  QueryClient client,
  String id,
) =>
    MutationOptions.simple(
      mutationFn: (bool on) => devices.setPower(id, on: on),
      // Every write to this device waits for the one before it; writes to
      // other devices do not wait for it.
      scope: MutationScope('device-$id'),
      onSuccess: (device, _, __) {
        client.setQueryData<Device>(DeviceKeys.detail(id), device);
      },
    );
// <<<

// ---------------------------------------------------------------------------
// guides/cancelling-mutations.md
// ---------------------------------------------------------------------------

// >>> guides/cancelling-mutations.md#upload
MutationOptions<Device, Uint8List, void> firmwareUploadMutation(
  QueryClient client,
  String id,
) =>
    MutationOptions.simple(
      mutationFnWithContext: (image, context) =>
          devices.uploadFirmware(id, image, signal: context.signal),
      // Cancelled or not, ask the device what it is running now.
      onSettled: (_, __, ___, ____, _____) => client.invalidateQueries(
        filters: QueryFilters(queryKey: DeviceKeys.detail(id)),
      ),
    );

class FirmwareUpdateButton extends StatelessWidget {
  const FirmwareUpdateButton({
    super.key,
    required this.deviceId,
    required this.image,
  });

  final String deviceId;
  final Uint8List image;

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    final upload = context.mutation(firmwareUploadMutation(client, deviceId));
    return switch (upload.value) {
      MutationPending() => OutlinedButton(
          onPressed: upload.cancel,
          child: const Text('Cancel update'),
        ),
      MutationError(error: CancelledError()) => FilledButton(
          onPressed: () => upload.mutate(image),
          child: const Text('Update cancelled — try again'),
        ),
      _ => FilledButton(
          onPressed: () => upload.mutate(image),
          child: const Text('Install update'),
        ),
    };
  }
}
// <<<

// ---------------------------------------------------------------------------
// guides/mutation-state.md
// ---------------------------------------------------------------------------

class SavingIndicator extends StatefulWidget {
  const SavingIndicator({super.key});

  @override
  State<SavingIndicator> createState() => _SavingIndicatorState();
}

// >>> guides/mutation-state.md#saving-indicator
// lib/widgets/saving_indicator.dart — in the app bar, owning no mutation.
class _SavingIndicatorState extends State<SavingIndicator> {
  late final MutationStateController<int> _saving = MutationStateController(
    QueryClientProvider.read(context),
    filters: const MutationFilters(status: MutationStatus.pending),
    select: (mutation) => mutation.mutationId,
  );

  @override
  void dispose() {
    _saving.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<int>>(
        valueListenable: _saving,
        builder: (context, running, _) => running.isEmpty
            ? const SizedBox.shrink()
            : Text('Saving ${running.length}…'),
      );
}
// <<<

// ---------------------------------------------------------------------------
// guides/filters.md
// ---------------------------------------------------------------------------

Future<void> queryFilterExamples(QueryClient client) async {
  // >>> guides/filters.md#query-filters
  // Every device query, lists and details alike.
  await client.invalidateQueries(
    filters: QueryFilters(queryKey: DeviceKeys.all),
  );

  // The kitchen's list only — `exact` stops the prefix match.
  await client.refetchQueries(
    filters: QueryFilters(
      queryKey: DeviceKeys.list(room: 'kitchen'),
      exact: true,
    ),
  );

  // Device details nobody is showing: dropped, not refetched.
  client.removeQueries(
    filters: QueryFilters(
      queryKey: DeviceKeys.details,
      type: QueryTypeFilter.inactive,
    ),
  );

  // Every query whose last fetch failed, whatever its key.
  await client.refetchQueries(
    filters: const QueryFilters(status: QueryStatus.error),
  );

  // Only what has gone stale, for a pull-to-refresh that skips fresh data.
  await client.refetchQueries(
    filters: QueryFilters(queryKey: DeviceKeys.all, stale: true),
  );

  // How many device requests are out right now — for a spinner.
  final loading = client.isFetching(
    filters: QueryFilters(queryKey: DeviceKeys.all),
  );
  // <<<
  debugPrint('$loading');
}

void signOut(QueryClient client) {
  // >>> guides/filters.md#predicate
  // At sign-out, drop every query tagged as the user's own, whatever its key.
  client.removeQueries(
    filters: QueryFilters(
      predicate: (query) => switch (query.meta) {
        {'personal': true} => true,
        _ => false,
      },
    ),
  );
  // <<<
}

void mutationFilterExamples(QueryClient client) {
  // >>> guides/filters.md#mutation-filters
  // Adds still out in any room — `['add-device']` is a prefix.
  final adding = client.isMutating(
    filters: MutationFilters(mutationKey: QueryKey(<Object?>['add-device'])),
  );

  // Every write that failed, for a "retry all" banner.
  final failed = client.mutationCache.findAll(
    filters: const MutationFilters(status: MutationStatus.error),
  );
  // <<<
  debugPrint('$adding ${failed.length}');
}

// >>> guides/filters.md#matches
final QueryFilters kitchenLists = QueryFilters(
  queryKey: DeviceKeys.list(room: 'kitchen'),
);

void Function() logKitchen(QueryClient client) =>
    client.queryCache.subscribe((event) {
      if (kitchenLists.matches(event.query)) debugPrint('kitchen: $event');
    });
// <<<

// ---------------------------------------------------------------------------
// guides/request-waterfalls.md
// ---------------------------------------------------------------------------

class EnergyChart extends StatelessWidget {
  const EnergyChart({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final energy = context.query(energyQuery(deviceId));
    return Text('${energy.dataOrNull?.length ?? 0} readings');
  }
}

// >>> guides/request-waterfalls.md#nested
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
// <<<

class PrefetchingDeviceScreen extends StatefulWidget {
  const PrefetchingDeviceScreen({super.key, required this.id});

  final String id;

  @override
  State<PrefetchingDeviceScreen> createState() =>
      _PrefetchingDeviceScreenState();
}

// >>> guides/request-waterfalls.md#prefetch-in-parent
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
// <<<

class EnergyChartView extends StatelessWidget {
  const EnergyChartView(this.readings, {super.key});

  final QueryResult<List<double>> readings;

  @override
  Widget build(BuildContext context) =>
      Text('${readings.dataOrNull?.length ?? 0} readings');
}

// >>> guides/request-waterfalls.md#hoisted
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
// <<<

// ---------------------------------------------------------------------------
// guides/prefetching.md
// ---------------------------------------------------------------------------

// >>> guides/prefetching.md#on-intent
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
// <<<

class AddDeviceField extends StatelessWidget {
  const AddDeviceField({super.key, required this.onSubmit});

  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) => TextField(onSubmitted: onSubmit);
}

Future<void> revalidateExample(QueryClient client) async {
  // >>> guides/prefetching.md#revalidate
  // The kitchen's devices at once, even a stale list; a stale entry
  // refreshes behind this call. Nothing cached: the fetch is awaited.
  final kitchen = await client.query(
    roomDevicesQuery('kitchen'),
    revalidateIfStale: true,
  );
  // <<<
  debugPrint('$kitchen');
}

void primeFromList(QueryClient client, List<Device> list) {
  // >>> guides/prefetching.md#prime
  // The room list already holds every device's fields: seed each detail, so
  // opening one shows it at once.
  for (final device in list) {
    client.setQueryData<Device>(DeviceKeys.detail(device.id), device);
  }
  // <<<
}

// ---------------------------------------------------------------------------
// guides/render-optimizations.md
// ---------------------------------------------------------------------------

// >>> guides/render-optimizations.md#room-badge
class RoomBadge extends StatelessWidget {
  const RoomBadge({super.key, required this.room});

  final String room;

  @override
  Widget build(BuildContext context) {
    // Reads the room's list, keeps a count. A device renamed, or a refetch
    // that changes nothing, leaves the count — and this badge — alone.
    final on = context.selectQuery(
      roomDevicesQuery(room).withSelect(_countOn),
      buildWhen: (previous, current) =>
          previous.dataOrNull != current.dataOrNull,
    );
    return Badge(
      label: Text('${on.dataOrNull ?? 0}'),
      child: const Icon(Icons.lightbulb_outline),
    );
  }
}

// Top-level, so the options compare equal from one build to the next.
int _countOn(List<Device> list) => list.where((device) => device.isOn).length;
// <<<

// ---------------------------------------------------------------------------
// guides/default-query-function.md
// ---------------------------------------------------------------------------

void registerApiDefaults(QueryClient client, ApiClient api) {
  // >>> guides/default-query-function.md#api-default
  // In main(), once: every key under ['api'] is a GET of the path it names.
  // ['api', '/devices', {'room': 'kitchen'}] is GET /devices?room=kitchen.
  client.setQueryDefaults(
    QueryKey(<Object?>['api']),
    QueryDefaults(
      queryFn: (context) {
        final parts = context.queryKey.parts;
        return api.getJson(
          parts[1]! as String,
          query: parts.length > 2
              ? parts[2]! as Map<String, Object?>
              : const <String, Object?>{},
          signal: context.signal,
        );
      },
    ),
  );
  // <<<

  // >>> guides/default-query-function.md#mutation-default
  client.setMutationDefaults(
    QueryKey(<Object?>['api', 'add-device']),
    MutationDefaults(
      mutationFn: (body) => api.postJson('/devices', body),
    ),
  );
  // <<<
}

// >>> guides/default-query-function.md#keyed-queries
// lib/data/device_queries.dart — no queryFn: the key is the request.
QuerySelectOptions<Object?, List<Device>> apiRoomDevices(String room) =>
    QuerySelectOptions(
      queryKey: QueryKey(<Object?>[
        'api',
        '/devices',
        <String, Object?>{'room': room},
      ]),
      select: parseDevices,
    );

// A top-level function, so a rebuild hands in an equal select and the
// parsed list is kept rather than parsed again.
List<Device> parseDevices(Object? json) => <Device>[
      for (final item in json! as List<Object?>)
        Device.fromJson(item! as Map<String, Object?>),
    ];
// <<<

// >>> guides/default-query-function.md#keyed-mutation
MutationOptions<Object?, Map<String, Object?>, void> addDeviceByKey() =>
    MutationOptions.simple(
        mutationKey: QueryKey(<Object?>['api', 'add-device']));
// <<<

// ---------------------------------------------------------------------------
// guides/global-callbacks.md
// ---------------------------------------------------------------------------

// >>> guides/global-callbacks.md#wiring
// lib/main.dart
class DevicesApp extends StatelessWidget {
  const DevicesApp({super.key, required this.client, required this.home});

  final QueryClient client;
  final Widget home;

  @override
  Widget build(BuildContext context) => QueryClientProvider(
        client: client,
        child: MaterialApp(
          // The key the cache's onError shows its SnackBar through.
          scaffoldMessengerKey: messengerKey,
          home: home,
        ),
      );
}
// <<<

// >>> guides/global-callbacks.md#invalidate-by-meta
QueryClient clientInvalidatingByMeta() {
  late final QueryClient client;
  client = QueryClient(
    mutationCache: MutationCache(
      onSuccess: (data, variables, onMutateResult, mutation) async {
        // A mutation names the keys it makes stale; the cache does the rest.
        if (mutation.meta case {'invalidates': final List<QueryKey> keys}) {
          await Future.wait(<Future<void>>[
            for (final key in keys)
              client.invalidateQueries(filters: QueryFilters(queryKey: key)),
          ]);
        }
      },
    ),
  );
  return client;
}

MutationOptions<Device, String, void> renameDevice(String id) =>
    MutationOptions.simple(
      mutationFn: (String name) => devices.rename(id, name),
      meta: <String, Object>{
        'invalidates': <QueryKey>[DeviceKeys.all],
      },
    );
// <<<
