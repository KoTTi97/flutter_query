/// The samples of the getting-started pages and the queries guides —
/// overview, important defaults, type safety, queries, keys, functions,
/// options, parallel, combined, dependent and disabled queries, side effects.
///
/// Same rule as the rest of this package: each region is marked with the
/// page that shows it, and the fence on that page names the region.
///
/// The samples here speak about one app — a smart-home app with devices in
/// rooms — so a page can show where code lives (`lib/data/…`, a screen)
/// rather than a lone call. The repository below is the one piece that is a
/// stand-in: the real one uses dio, which this package may not depend on, so
/// the query-functions page shows it as prose and this file keeps its
/// signatures.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

// ---------------------------------------------------------------------------
// The domain
// ---------------------------------------------------------------------------

@immutable
class Device {
  const Device({
    required this.id,
    required this.name,
    required this.roomId,
    required this.isOn,
  });

  final String id;
  final String name;
  final String roomId;
  final bool isOn;

  Device copyWith({String? name, bool? isOn}) => Device(
        id: id,
        name: name ?? this.name,
        roomId: roomId,
        isOn: isOn ?? this.isOn,
      );

  @override
  bool operator ==(Object other) =>
      other is Device &&
      other.id == id &&
      other.name == name &&
      other.roomId == roomId &&
      other.isOn == isOn;

  @override
  int get hashCode => Object.hash(id, name, roomId, isOn);
}

@immutable
class Room {
  const Room({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is Room && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

@immutable
class Account {
  const Account({required this.id, required this.homeId});

  final String id;
  final String homeId;

  @override
  bool operator ==(Object other) =>
      other is Account && other.id == id && other.homeId == homeId;

  @override
  int get hashCode => Object.hash(id, homeId);
}

@immutable
class Firmware {
  const Firmware(this.version);

  final String version;

  @override
  bool operator ==(Object other) =>
      other is Firmware && other.version == version;

  @override
  int get hashCode => version.hashCode;
}

@immutable
class EnergyReading {
  const EnergyReading(this.watts);

  final double watts;

  @override
  bool operator ==(Object other) =>
      other is EnergyReading && other.watts == watts;

  @override
  int get hashCode => watts.hashCode;
}

// >>> guides/query-functions.md#api-exception
/// What the repository throws when the backend refuses.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;

  /// The HTTP status, or null when no response arrived at all.
  final int? statusCode;

  /// A 4xx: asking again will not change the answer.
  bool get isClientError =>
      statusCode != null && statusCode! >= 400 && statusCode! < 500;

  @override
  String toString() => message;
}
// <<<

/// The stand-in for `lib/data/device_repository.dart`. The real one is on
/// the query-functions page, built on dio.
class DeviceRepository {
  static const Device _lamp =
      Device(id: 'd1', name: 'Hall lamp', roomId: 'hall', isOn: false);

  Future<List<Device>> devices({
    String? roomId,
    QueryCancelToken? signal,
  }) async =>
      const <Device>[_lamp];

  Future<Device> device(String id, {QueryCancelToken? signal}) async => _lamp;

  Future<List<Device>> homeDevices(
    String homeId, {
    QueryCancelToken? signal,
  }) async =>
      const <Device>[_lamp];

  Future<List<Device>> search(String text, {QueryCancelToken? signal}) async =>
      const <Device>[_lamp];

  Future<List<Device>> discover({QueryCancelToken? signal}) async =>
      const <Device>[];

  Future<List<Room>> rooms({QueryCancelToken? signal}) async =>
      const <Room>[Room(id: 'hall', name: 'Hall')];

  Future<Account> account({QueryCancelToken? signal}) async =>
      const Account(id: 'a1', homeId: 'h1');

  Future<Firmware> firmware(String deviceId,
          {QueryCancelToken? signal}) async =>
      const Firmware('2.4.1');

  Future<EnergyReading> energy(
    String deviceId, {
    QueryCancelToken? signal,
  }) async =>
      const EnergyReading(4.5);

  Future<Device> rename(String id, String name) async =>
      _lamp.copyWith(name: name);
}

/// However the app provides it — a top-level, a service locator, a
/// constructor argument. The samples read it as a top-level.
final DeviceRepository repository = DeviceRepository();

// ---------------------------------------------------------------------------
// overview.md
// ---------------------------------------------------------------------------

// >>> overview.md#example
// lib/data/device_queries.dart — what the data is, described once.
QueryObserverOptions<List<Device>> allDevicesQuery() => QueryObserverOptions(
      queryKey: QueryKey(<Object?>['devices']),
      queryFn: (context) => repository.devices(signal: context.signal),
    );

// lib/ui/device_list.dart — a widget that shows it.
class DeviceList extends StatelessWidget {
  const DeviceList({super.key});

  @override
  Widget build(BuildContext context) {
    return switch (context.query(allDevicesQuery())) {
      QueryPending() => const Center(child: CircularProgressIndicator()),
      QueryError(:final error) => Center(child: Text('Could not load: $error')),
      QuerySuccess(:final data) => ListView(
          children: <Widget>[
            for (final device in data) ListTile(title: Text(device.name)),
          ],
        ),
    };
  }
}
// <<<

// ---------------------------------------------------------------------------
// guides/query-keys.md
// ---------------------------------------------------------------------------

// >>> guides/query-keys.md#device-keys
// lib/data/device_keys.dart
abstract final class DeviceKeys {
  static final QueryKey all = QueryKey(<Object?>['devices']);

  static final QueryKey lists = all.append(<Object?>['list']);

  static QueryKey list({String? roomId}) => lists.append(<Object?>[
        <String, Object?>{'room': roomId},
      ]);

  static QueryKey detail(String id) => all.append(<Object?>['detail', id]);

  static QueryKey firmware(String id) =>
      detail(id).append(<Object?>['firmware']);
}
// <<<

Future<void> invalidationsByPrefix(QueryClient client, String id) async {
  // >>> guides/query-keys.md#invalidate-by-prefix
  // One device: its detail, and its firmware, which sits under it.
  await client.invalidateQueries(
    filters: QueryFilters(queryKey: DeviceKeys.detail(id)),
  );

  // Every device list, whatever room it is filtered by.
  await client.invalidateQueries(
    filters: QueryFilters(queryKey: DeviceKeys.lists),
  );

  // Only the unfiltered list: the key exactly, nothing under it.
  await client.invalidateQueries(
    filters: QueryFilters(queryKey: DeviceKeys.list(), exact: true),
  );

  // Everything about devices.
  await client.invalidateQueries(
    filters: QueryFilters(queryKey: DeviceKeys.all),
  );
  // <<<
}

// ---------------------------------------------------------------------------
// guides/queries.md
// ---------------------------------------------------------------------------

// >>> guides/queries.md#device-queries
// lib/data/device_queries.dart
QueryObserverOptions<List<Device>> devicesQuery({String? roomId}) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.list(roomId: roomId),
      queryFn: (context) =>
          repository.devices(roomId: roomId, signal: context.signal),
    );

QueryObserverOptions<Device> deviceQuery(String id) => QueryObserverOptions(
      queryKey: DeviceKeys.detail(id),
      queryFn: (context) => repository.device(id, signal: context.signal),
    );
// <<<

QueryObserverOptions<List<Room>> roomsQuery() => QueryObserverOptions(
      queryKey: QueryKey(<Object?>['rooms']),
      queryFn: (context) => repository.rooms(signal: context.signal),
    );

// >>> guides/queries.md#devices-screen
// lib/ui/devices_screen.dart
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final devices = context.query(devicesQuery());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        // A background refetch: the list stays, and a thin bar says so.
        bottom: devices.isRefetching
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: switch (devices) {
        QueryPending() => const Center(child: CircularProgressIndicator()),
        // A refetch failed: say so above the data that is still good.
        QueryError(:final error, :final staleData?) => Column(
            children: <Widget>[
              Text('Could not refresh: $error'),
              Expanded(child: DeviceListView(staleData)),
            ],
          ),
        // The first load failed: there is nothing to show.
        QueryError(:final error) =>
          Center(child: Text('Could not load devices: $error')),
        QuerySuccess(:final data) => RefreshIndicator(
            onRefresh: devices.refetch,
            child: DeviceListView(data),
          ),
      },
    );
  }
}
// <<<

// ---------------------------------------------------------------------------
// guides/query-functions.md
// ---------------------------------------------------------------------------

// >>> guides/query-functions.md#from-key
// One function for every detail key: the id is read back from the key.
Future<Device> fetchDevice(QueryFunctionContext context) {
  final id = context.queryKey.parts[2]! as String;
  return repository.device(id, signal: context.signal);
}
// <<<

QueryObserverOptions<Device> deviceQueryWithRetry(String id) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.detail(id),
      queryFn: fetchDevice,
      // >>> guides/query-functions.md#retry-on-status
      // A 404 or a 403 will not change on the third try; a timeout might.
      retry: RetryPolicy.when(
        (failureCount, error, _) =>
            failureCount < 3 && !(error is ApiException && error.isClientError),
      ),
      // <<<
    );

// ---------------------------------------------------------------------------
// guides/query-options.md
// ---------------------------------------------------------------------------

class DeviceNameLabel extends StatelessWidget {
  const DeviceNameLabel(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    // >>> guides/query-options.md#with-select
    // The name only: this label rebuilds when the name changes, not when the
    // device is switched on or off.
    final name = context.selectQuery(
      deviceQuery(id).withSelect((device) => device.name),
    );
    // <<<
    return Text(name.dataOrNull ?? '…');
  }
}

// >>> guides/query-options.md#prefetch
// The same options, handed to the client: warm the detail before the
// detail screen opens. A second reader within staleTime fetches nothing.
Future<void> prefetchDevice(QueryClient client, String id) =>
    client.query(deviceQuery(id));
// <<<

// ---------------------------------------------------------------------------
// important-defaults.md
// ---------------------------------------------------------------------------

// >>> important-defaults.md#client-defaults
// lib/main.dart
final QueryClient queryClient = QueryClient(
  defaultOptions: const DefaultOptions(
    queries: QueryDefaults(
      // Fresh for 30 seconds: a second screen within that time reads the
      // cache and asks nobody.
      staleTime: StaleTime.duration(Duration(seconds: 30)),
      // One retry, not three, before the error reaches the screen.
      retry: RetryPolicy.times(1),
    ),
    mutations: MutationDefaults(
      // Our writes are idempotent PUTs, so sending one twice is safe.
      retry: RetryPolicy.times(2),
    ),
  ),
);
// <<<

// >>> important-defaults.md#per-query
QueryObserverOptions<Firmware> firmwareQuery(String deviceId) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.firmware(deviceId),
      queryFn: (context) =>
          repository.firmware(deviceId, signal: context.signal),
      // Only an update changes it, and the update invalidates this key.
      staleTime: StaleTime.infinite,
      // Coming back to the app is no reason to ask again.
      refetchOnWindowFocus: RefetchOn.never,
    );
// <<<

void configureKeyDefaults(QueryClient client) {
  // >>> important-defaults.md#key-defaults
  // Live readings: refetched on every return to the app, and dropped soon
  // after no screen shows them.
  client.setQueryDefaults(
    QueryKey(<Object?>['energy']),
    const QueryDefaults(
      refetchOnWindowFocus: RefetchOn.always,
      gcTime: GcTime.duration(Duration(seconds: 30)),
    ),
  );
  // <<<
}

Widget appShownProvider(Widget app) =>
    // >>> important-defaults.md#app-shown
    QueryClientProvider(
      client: queryClient,
      // Only a fully resumed app counts as focused, on every platform.
      isAppShown: (state) => state == AppLifecycleState.resumed,
      child: app,
    );
// <<<

// ---------------------------------------------------------------------------
// dart-type-safety.md
// ---------------------------------------------------------------------------

// >>> dart-type-safety.md#sealed-switch
Widget deviceTitle(QueryResult<Device> device) => switch (device) {
      QueryPending() => const Text('…'),
      QuerySuccess(:final data) => Text(data.name),
      // `staleData` is a Device? — the last good value, when there was one.
      QueryError(:final staleData?) => Text('${staleData.name} (offline)'),
      QueryError() => const Text('Unknown device'),
    };
// <<<

class CachedDeviceTitle extends StatelessWidget {
  const CachedDeviceTitle(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    // >>> dart-type-safety.md#key-only
    // Nothing to infer the type from — no queryFn, no expected type — so name
    // it. Without <Device>, this would be a QueryResult<dynamic>.
    final device = context.query(
      QueryObserverOptions<Device>(queryKey: DeviceKeys.detail(id)),
    );
    // <<<
    return deviceTitle(device);
  }
}

void oneKeyOneType(QueryClient client) {
  // >>> dart-type-safety.md#one-type
  final key = DeviceKeys.list();
  client.setQueryData<List<Device>>(key, const <Device>[]);

  client.getQueryData<List<Device>>(key); // the entry's own type: fine
  client.getQueryData<List<Object?>>(key); // throws QueryDataTypeError
  // <<<
}

void writesThatInfer(QueryClient client, Device device) {
  // >>> dart-type-safety.md#writes
  // The type comes from the value: a Device, into an entry holding a Device.
  client.setQueryData(
      DeviceKeys.detail(device.id), device.copyWith(isOn: true));

  // The type comes from the updater's parameter.
  client.updateQueryData(
    DeviceKeys.list(),
    (List<Device>? devices) => <Device>[
      for (final each in devices ?? const <Device>[])
        each.id == device.id ? device : each,
    ],
  );
  // <<<
}

// ---------------------------------------------------------------------------
// guides/parallel-queries.md — the four call styles, side by side
// ---------------------------------------------------------------------------

/// What the dashboard shows. Takes the two results as they are, so each
/// style below ends in the same widget.
class DashboardView extends StatelessWidget {
  const DashboardView({super.key, required this.rooms, required this.devices});

  final QueryResult<List<Room>> rooms;
  final QueryResult<List<Device>> devices;

  @override
  Widget build(BuildContext context) => Text(
        '${rooms.dataOrNull?.length ?? '–'} rooms, '
        '${devices.dataOrNull?.length ?? '–'} devices',
      );
}

// >>> guides/parallel-queries.md#context
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
// <<<

// >>> guides/parallel-queries.md#builder
Widget homeDashboard() => QueryBuilder<List<Room>>(
      options: roomsQuery(),
      builder: (context, rooms) => QueryBuilder<List<Device>>(
        options: devicesQuery(),
        builder: (context, devices) =>
            DashboardView(rooms: rooms, devices: devices),
      ),
    );
// <<<

class HomeDashboardMixin extends StatefulWidget {
  const HomeDashboardMixin({super.key});

  @override
  State<HomeDashboardMixin> createState() => _HomeDashboardMixinState();
}

// >>> guides/parallel-queries.md#mixin
class _HomeDashboardMixinState extends State<HomeDashboardMixin>
    with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final rooms = watchQuery(roomsQuery());
    final devices = watchQuery(devicesQuery());

    return DashboardView(rooms: rooms, devices: devices);
  }
}
// <<<

class HomeDashboardControllers extends StatefulWidget {
  const HomeDashboardControllers({super.key});

  @override
  State<HomeDashboardControllers> createState() =>
      _HomeDashboardControllersState();
}

// >>> guides/parallel-queries.md#controller
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
// <<<

// >>> guides/parallel-queries.md#energy-query
QueryObserverOptions<EnergyReading> energyQuery(String deviceId) =>
    QueryObserverOptions(
      queryKey: QueryKey(<Object?>['energy', deviceId]),
      queryFn: (context) => repository.energy(deviceId, signal: context.signal),
    );
// <<<

// >>> guides/parallel-queries.md#queries-builder-devices
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
// <<<

class DevicesSyncIndicator extends StatefulWidget {
  const DevicesSyncIndicator({super.key});

  @override
  State<DevicesSyncIndicator> createState() => _DevicesSyncIndicatorState();
}

// >>> guides/parallel-queries.md#is-fetching
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
// <<<

// ---------------------------------------------------------------------------
// guides/combining-queries.md
// ---------------------------------------------------------------------------

// >>> guides/combining-queries.md#rooms-overview
// lib/ui/rooms_overview.dart
class RoomsOverview extends StatelessWidget {
  const RoomsOverview({super.key});

  @override
  Widget build(BuildContext context) {
    final rooms = (
      context.query(roomsQuery()),
      context.query(devicesQuery()),
    ).combine(
      (rooms, devices) => <({Room room, List<Device> devices})>[
        for (final room in rooms)
          (
            room: room,
            devices: <Device>[
              for (final device in devices)
                if (device.roomId == room.id) device,
            ],
          ),
      ],
    );

    return switch (rooms) {
      CombinedPending() => const Center(child: CircularProgressIndicator()),
      CombinedError(:final error) => Center(
          child: TextButton(
            onPressed: rooms.retry,
            child: Text('$error — try again'),
          ),
        ),
      CombinedData(:final data) => ListView(
          children: <Widget>[
            for (final entry in data)
              ListTile(
                title: Text(entry.room.name),
                trailing: Text('${entry.devices.length}'),
              ),
          ],
        ),
    };
  }
}
// <<<

// ---------------------------------------------------------------------------
// guides/dependent-queries.md
// ---------------------------------------------------------------------------

QueryObserverOptions<Account> accountQuery() => QueryObserverOptions(
      queryKey: QueryKey(<Object?>['account']),
      queryFn: (context) => repository.account(signal: context.signal),
    );

// >>> guides/dependent-queries.md#home-devices
QueryObserverOptions<List<Device>> homeDevicesQuery(String? homeId) =>
    QueryObserverOptions(
      // The value the query waits for is part of its key.
      queryKey: DeviceKeys.all.append(<Object?>['home', homeId]),
      queryFn: (context) =>
          repository.homeDevices(homeId!, signal: context.signal),
      // No home yet: nothing to ask the server.
      enabled: homeId == null ? Enabled.no : Enabled.yes,
    );
// <<<

class MyHomeScreen extends StatelessWidget {
  const MyHomeScreen({super.key});

  // >>> guides/dependent-queries.md#screen
  @override
  Widget build(BuildContext context) {
    final account = context.query(accountQuery());
    // null until the account is there — and until then, this one waits.
    final devices = context.query(
      homeDevicesQuery(account.dataOrNull?.homeId),
    );

    return switch ((account, devices)) {
      (QueryError(:final error), _) ||
      (_, QueryError(:final error)) =>
        Center(child: Text('Could not load your home: $error')),
      (_, QuerySuccess(:final data)) => DeviceListView(data),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
  // <<<
}

/// What the three other styles below end in: the same switch as the screen
/// above.
Widget homeView(
  QueryResult<Account> account,
  QueryResult<List<Device>> devices,
) =>
    switch ((account, devices)) {
      (QueryError(:final error), _) ||
      (_, QueryError(:final error)) =>
        Center(child: Text('Could not load your home: $error')),
      (_, QuerySuccess(:final data)) => DeviceListView(data),
      _ => const Center(child: CircularProgressIndicator()),
    };

// >>> guides/dependent-queries.md#builder
Widget myHome() => QueryBuilder<Account>(
      options: accountQuery(),
      builder: (context, account) => QueryBuilder<List<Device>>(
        // Rebuilt with the account's home once it is there.
        options: homeDevicesQuery(account.dataOrNull?.homeId),
        builder: (context, devices) => homeView(account, devices),
      ),
    );
// <<<

class MyHomeMixin extends StatefulWidget {
  const MyHomeMixin({super.key});

  @override
  State<MyHomeMixin> createState() => _MyHomeMixinState();
}

// >>> guides/dependent-queries.md#mixin
class _MyHomeMixinState extends State<MyHomeMixin> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final account = watchQuery(accountQuery());
    final devices = watchQuery(homeDevicesQuery(account.dataOrNull?.homeId));

    return homeView(account, devices);
  }
}
// <<<

class MyHomeControllers extends StatefulWidget {
  const MyHomeControllers({super.key});

  @override
  State<MyHomeControllers> createState() => _MyHomeControllersState();
}

// >>> guides/dependent-queries.md#controller
class _MyHomeControllersState extends State<MyHomeControllers> {
  late final QueryController<Account, Account> _account;
  late final QueryController<List<Device>, List<Device>> _devices;

  @override
  void initState() {
    super.initState();
    final client = QueryClientProvider.read(context);
    _account = QueryController.create(client, accountQuery());
    _devices = QueryController.create(
      client,
      homeDevicesQuery(_account.value.dataOrNull?.homeId),
    );
    // No build to re-run the options: when the account changes, hand the
    // devices controller its new ones.
    _account.addListener(_followAccount);
  }

  void _followAccount() {
    _devices.setOptions(homeDevicesQuery(_account.value.dataOrNull?.homeId));
  }

  @override
  void dispose() {
    _account.removeListener(_followAccount);
    _account.dispose();
    _devices.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[_account, _devices]),
        builder: (context, _) => homeView(_account.value, _devices.value),
      );
}
// <<<

// ---------------------------------------------------------------------------
// guides/disabling-queries.md
// ---------------------------------------------------------------------------

// >>> guides/disabling-queries.md#discovery
QueryObserverOptions<List<Device>> discoveryQuery() => QueryObserverOptions(
      queryKey: QueryKey(<Object?>['discovery']),
      queryFn: (context) => repository.discover(signal: context.signal),
      // A scan floods the local network: run it only when asked to.
      enabled: Enabled.no,
    );

class ScanButton extends StatelessWidget {
  const ScanButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scan = context.query(discoveryQuery());

    return Column(
      children: <Widget>[
        FilledButton(
          onPressed: scan.isFetching ? null : scan.refetch,
          child: Text(scan.isFetching ? 'Scanning…' : 'Scan for devices'),
        ),
        if (scan case QuerySuccess(:final data))
          Text('${data.length} new devices found'),
      ],
    );
  }
}
// <<<

// >>> guides/disabling-queries.md#search-query
QueryObserverOptions<List<Device>> deviceSearchQuery(String text) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.all.append(<Object?>['search', text]),
      queryFn: (context) => repository.search(text, signal: context.signal),
      // One letter matches half the house: wait for two.
      enabled: text.length >= 2 ? Enabled.yes : Enabled.no,
    );
// <<<

class DeviceSearch extends StatefulWidget {
  const DeviceSearch({super.key});

  @override
  State<DeviceSearch> createState() => _DeviceSearchState();
}

// >>> guides/disabling-queries.md#search-screen
class _DeviceSearchState extends State<DeviceSearch> with QueryMixin {
  String _text = '';

  @override
  Widget build(BuildContext context) {
    final results = watchQuery(deviceSearchQuery(_text));

    return Column(
      children: <Widget>[
        TextField(
          decoration: const InputDecoration(labelText: 'Find a device'),
          onChanged: (text) => setState(() => _text = text.trim()),
        ),
        switch (results) {
          // Disabled: pending, and nothing is running. A hint, not a spinner.
          QueryPending(isFetching: false) =>
            const Text('Type two letters or more'),
          QueryPending() => const LinearProgressIndicator(),
          QueryError(:final error) => Text('Search failed: $error'),
          QuerySuccess(:final data) => Expanded(child: DeviceListView(data)),
        },
      ],
    );
  }
}
// <<<

// ---------------------------------------------------------------------------
// guides/side-effects.md
// ---------------------------------------------------------------------------

class DeviceDetailScreen extends StatefulWidget {
  const DeviceDetailScreen(this.id, {super.key});

  final String id;

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

// >>> guides/side-effects.md#device-screen
class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  late final QueryController<Device, Device> _device;

  @override
  void initState() {
    super.initState();
    _device = QueryController.create(
      QueryClientProvider.read(context),
      deviceQuery(widget.id),
    );
  }

  @override
  void didUpdateWidget(DeviceDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _device.setOptions(deviceQuery(widget.id));
  }

  @override
  void dispose() {
    _device.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return QueryListener<Device, Device>(
      controller: _device,
      // The moment it starts failing — not every notification while it stays
      // failed.
      listenWhen: (previous, next) =>
          previous is! QueryError && next is QueryError,
      listener: (context, result) {
        if (result case QueryError(error: ApiException(statusCode: 404))) {
          // Removed on another phone: nothing left to show here.
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not refresh this device')),
          );
        }
      },
      child: ValueListenableBuilder<QueryResult<Device>>(
        valueListenable: _device,
        builder: (context, device, _) => deviceTitle(device),
      ),
    );
  }
}
// <<<

// >>> guides/side-effects.md#rename-mutation
MutationOptions<Device, String, void> renameDevice(
  QueryClient client,
  String id,
) =>
    MutationOptions.simple(
      mutationFn: (String name) => repository.rename(id, name),
      // The server's answer is the new detail: write it, no refetch needed.
      onSuccess: (device, _, __) {
        client.setQueryData(DeviceKeys.detail(id), device);
      },
    );
// <<<

class RenameDeviceSheet extends StatelessWidget {
  const RenameDeviceSheet(this.id, {super.key});

  final String id;

  // >>> guides/side-effects.md#rename-listener
  @override
  Widget build(BuildContext context) {
    final rename = context.mutation(
      renameDevice(QueryClientProvider.of(context), id),
    );

    return MutationListener<Device, String, void>(
      controller: rename,
      listenWhen: (previous, next) => next is MutationSuccess,
      // Saved: the sheet has done its job.
      listener: (context, _) => Navigator.of(context).pop(),
      child: TextField(
        enabled: !rename.value.isPending,
        onSubmitted: rename.mutate,
      ),
    );
  }
  // <<<
}

// ---------------------------------------------------------------------------
// guides/reading-queries-in-widgets.md
// ---------------------------------------------------------------------------

Widget deviceRows(List<String> ids) =>
    // >>> guides/reading-queries-in-widgets.md#device-rows
    ListView.builder(
      itemCount: ids.length,
      // Each row is a widget of its own, so each row's read is its own.
      itemBuilder: (context, index) => DeviceRow(ids[index]),
    );
// <<<

// >>> guides/reading-queries-in-widgets.md#device-row
class DeviceRow extends StatelessWidget {
  const DeviceRow(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    final device = context.query(deviceQuery(id));
    return ListTile(title: deviceTitle(device));
  }
}
// <<<

// ---------------------------------------------------------------------------
// Widgets the samples end in. Not the subject of any page.
// ---------------------------------------------------------------------------

class DeviceListView extends StatelessWidget {
  const DeviceListView(this.devices, {super.key});

  final List<Device> devices;

  @override
  Widget build(BuildContext context) => ListView(
        children: <Widget>[
          for (final device in devices) ListTile(title: Text(device.name)),
        ],
      );
}
