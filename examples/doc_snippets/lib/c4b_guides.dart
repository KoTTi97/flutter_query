/// The samples of the site's refetching, network, paging and early-data
/// guides: background fetching indicators, app focus, network mode,
/// connectivity, polling, retries, cancellation, paginated and infinite
/// queries, initial and placeholder data, scroll restoration.
///
/// Same rule as the rest of this package — each region is marked with the
/// page that shows it, and the fence on that page names the region. The
/// samples share one small domain, a smart-home app's device list, so a page
/// can show where its code lives in an app rather than a call on its own.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'doc_snippets.dart' show MyApp;
import 'guides.dart' show FetchingBar;

// ---------------------------------------------------------------------------
// The domain: devices, their pages, their activity log and a firmware job.
// ---------------------------------------------------------------------------

@immutable
class Device {
  const Device({required this.id, required this.name, required this.kind});

  /// What a detail screen shows while the real device loads.
  static const Device loading = Device(id: '', name: 'Loading…', kind: '');

  final String id;
  final String name;
  final String kind;

  @override
  bool operator ==(Object other) =>
      other is Device &&
      other.id == id &&
      other.name == name &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(id, name, kind);
}

@immutable
class DevicePage {
  const DevicePage(this.devices, {required this.hasMore});

  final List<Device> devices;
  final bool hasMore;
}

@immutable
class ActivityEntry {
  const ActivityEntry(this.message);

  final String message;
}

@immutable
class ActivityPage {
  const ActivityPage(this.entries, {this.nextOffset});

  final List<ActivityEntry> entries;

  /// Where the next, older page starts; `null` at the oldest entry.
  final int? nextOffset;
}

@immutable
class FirmwareJob {
  const FirmwareJob({required this.id, required this.done});

  final String id;
  final bool done;
}

@immutable
class DeviceType {
  const DeviceType(this.name);

  final String name;
}

/// What the app's HTTP layer throws for a response it did not want.
class ApiException implements Exception {
  const ApiException(this.statusCode, {this.retryAfter});

  final int statusCode;

  /// The server's `Retry-After`, when it sent one.
  final Duration? retryAfter;

  @override
  String toString() => 'HTTP $statusCode';
}

/// Stands in for the app's repository over dio or `package:http`; the pages
/// show the real one in prose-only samples.
class DeviceRepository {
  Future<List<Device>> list({QueryCancelToken? signal}) async =>
      const <Device>[];

  Future<List<Device>> byKind(String kind, {QueryCancelToken? signal}) async =>
      const <Device>[];

  Future<Device> byId(String id, {QueryCancelToken? signal}) async =>
      Device(id: id, name: 'Hallway dimmer', kind: 'light');

  Future<DevicePage> page(int page, {QueryCancelToken? signal}) async =>
      const DevicePage(<Device>[], hasMore: false);

  Future<ActivityPage> activity(String deviceId,
          {required int offset, QueryCancelToken? signal}) async =>
      const ActivityPage(<ActivityEntry>[]);

  Future<FirmwareJob> firmwareJob(String jobId,
          {QueryCancelToken? signal}) async =>
      FirmwareJob(id: jobId, done: true);

  Future<List<DeviceType>> types({QueryCancelToken? signal}) async =>
      bundledDeviceTypes;

  Future<List<String>> readLog(String deviceId, int chunk,
          {QueryCancelToken? signal}) async =>
      const <String>[];
}

final DeviceRepository deviceRepository = DeviceRepository();

const List<DeviceType> bundledDeviceTypes = <DeviceType>[
  DeviceType('dimmer'),
  DeviceType('shutter'),
  DeviceType('thermostat'),
];

/// When the app's bundled catalogue was last updated.
final DateTime bundledDeviceTypesDate = DateTime.utc(2026, 1, 1);

class DeviceTile extends StatelessWidget {
  const DeviceTile(this.device, {super.key});

  final Device device;

  @override
  Widget build(BuildContext context) => ListTile(title: Text(device.name));
}

class ActivityTile extends StatelessWidget {
  const ActivityTile(this.entry, {super.key});

  final ActivityEntry entry;

  @override
  Widget build(BuildContext context) => ListTile(title: Text(entry.message));
}

// ---------------------------------------------------------------------------
// guides/background-fetching-indicators.md
// ---------------------------------------------------------------------------

// >>> guides/background-fetching-indicators.md#device-queries
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
// <<<

// >>> guides/background-fetching-indicators.md#first-load-or-refresh
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
// <<<

/// A small spinner for a header's trailing slot.
class RefreshingSpinner extends StatelessWidget {
  const RefreshingSpinner({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.square(
        dimension: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
}

// >>> guides/background-fetching-indicators.md#header-context-query
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
// <<<

// >>> guides/background-fetching-indicators.md#header-builder
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
// <<<

class DevicesHeaderMixin extends StatefulWidget {
  const DevicesHeaderMixin({super.key});

  @override
  State<DevicesHeaderMixin> createState() => _DevicesHeaderMixinState();
}

// >>> guides/background-fetching-indicators.md#header-mixin
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
// <<<

class DevicesHeaderController extends StatefulWidget {
  const DevicesHeaderController({super.key});

  @override
  State<DevicesHeaderController> createState() =>
      _DevicesHeaderControllerState();
}

// >>> guides/background-fetching-indicators.md#header-controller
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
// <<<

// >>> guides/background-fetching-indicators.md#app-bar
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
// <<<

class DeviceSyncIndicator extends StatefulWidget {
  const DeviceSyncIndicator({super.key});

  @override
  State<DeviceSyncIndicator> createState() => _DeviceSyncIndicatorState();
}

class _DeviceSyncIndicatorState extends State<DeviceSyncIndicator> {
  // >>> guides/background-fetching-indicators.md#filtered
  // Every query under ['devices'] — the list, the pages, each detail.
  late final IsFetchingController _devicesFetching = IsFetchingController(
    QueryClientProvider.read(context),
    filters: QueryFilters(queryKey: DeviceKeys.all),
  );
  // <<<

  @override
  void dispose() {
    _devicesFetching.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: _devicesFetching,
        builder: (context, count, _) =>
            Text(count == 0 ? 'Up to date' : 'Syncing $count…'),
      );
}

// ---------------------------------------------------------------------------
// guides/window-focus-refetching.md
// ---------------------------------------------------------------------------

// >>> guides/window-focus-refetching.md#disable-globally
QueryClient clientWithoutFocusRefetch() => QueryClient(
      defaultOptions: const DefaultOptions(
        queries: QueryDefaults(refetchOnWindowFocus: RefetchOn.never),
      ),
    );
// <<<

// >>> guides/window-focus-refetching.md#per-query
// The settings form copies the device into its fields once. A refetch on
// return would not change what the user typed, but it would make the
// "discard changes" button compare against a newer device than the form.
QueryObserverOptions<Device> deviceSettingsQuery(String id) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.detail(id),
      queryFn: (context) => deviceRepository.byId(id, signal: context.signal),
      refetchOnWindowFocus: RefetchOn.never,
    );
// <<<

// >>> guides/window-focus-refetching.md#when
const RefetchOn refetchIfOlderThanAMinute = RefetchOn.when(_olderThanAMinute);

RefetchOn _olderThanAMinute(Query<Object?> query) =>
    query.isStaleByTime(const StaleTime.duration(Duration(minutes: 1)))
        ? RefetchOn.always
        : RefetchOn.never;
// <<<

// >>> guides/window-focus-refetching.md#min-background
QueryClient appClient() => QueryClient(
      focusManager: AppFocusManager(
        // A glance at another app is not a reason to reload every screen.
        refetchMinBackgroundDuration: const Duration(seconds: 30),
      ),
    );
// <<<

// >>> guides/window-focus-refetching.md#event-listener
void followWindowFocus(QueryClient client, Stream<bool> windowFocus) {
  client.focusManager.setEventListener((setFocused) {
    final subscription = windowFocus.listen(setFocused);
    return subscription.cancel;
  });
}
// <<<

List<Widget> focusProviders(QueryClient client) => <Widget>[
      // >>> guides/window-focus-refetching.md#is-app-shown
      QueryClientProvider(
        client: client,
        // Only a fully resumed app counts as focused, on every platform.
        isAppShown: (state) => state == AppLifecycleState.resumed,
        child: const MyApp(),
      ),
      // <<<
    ];

// ---------------------------------------------------------------------------
// guides/network-mode.md
// ---------------------------------------------------------------------------

// >>> guides/network-mode.md#local-devices
// The gateway is on the home network: it answers whether or not the phone
// has a route to the internet. The cloud account's queries keep `online`.
void talkToTheGatewayOffline(QueryClient client) {
  client.setQueryDefaults(
    DeviceKeys.all,
    const QueryDefaults(networkMode: NetworkMode.always),
  );
  client.setMutationDefaults(
    DeviceKeys.all,
    const MutationDefaults(networkMode: NetworkMode.always),
  );
}
// <<<

// >>> guides/network-mode.md#offline-first
// The repository sits behind an HTTP cache that can answer from disk.
QueryObserverOptions<List<DeviceType>> cachedDeviceTypesQuery() =>
    QueryObserverOptions(
      queryKey: QueryKey(<Object?>['device-types']),
      queryFn: (context) => deviceRepository.types(signal: context.signal),
      networkMode: NetworkMode.offlineFirst,
    );
// <<<

// >>> guides/network-mode.md#paused-note
String? offlineNote(QueryResult<List<Device>> devices) => switch (devices) {
      QueryPending(isPaused: true) => 'Waiting for a connection…',
      QuerySuccess(isPaused: true) => 'Offline — showing the last list loaded',
      _ => null,
    };
// <<<

// ---------------------------------------------------------------------------
// guides/connectivity.md
// ---------------------------------------------------------------------------

// >>> guides/connectivity.md#reachability
/// `true` while the link is up *and* [probe] reaches the backend. Probes again
/// every [recheck] while the link is up: a captive portal or a server outage
/// ends without the link changing.
Stream<bool> reachability(
  Stream<bool> link,
  Future<bool> Function() probe, {
  Duration recheck = const Duration(seconds: 20),
}) {
  StreamSubscription<bool>? linkChanges;
  Timer? timer;
  var linkUp = false;
  late final StreamController<bool> out;

  Future<void> check() async {
    final reachable = linkUp && await probe();
    if (!out.isClosed) out.add(reachable);
  }

  out = StreamController<bool>.broadcast(
    onListen: () {
      linkChanges = link.listen((up) {
        linkUp = up;
        check().ignore();
      });
      timer = Timer.periodic(recheck, (_) {
        if (linkUp) check().ignore();
      });
    },
    onCancel: () {
      timer?.cancel();
      linkChanges?.cancel().ignore();
    },
  );
  return out.stream.distinct();
}
// <<<

// ---------------------------------------------------------------------------
// guides/polling.md
// ---------------------------------------------------------------------------

// >>> guides/polling.md#every
// A thermostat's reading changes on its own; nothing in the app invalidates
// it, so the screen that shows it asks every five seconds.
QueryObserverOptions<Device> thermostatQuery(String id) => QueryObserverOptions(
      queryKey: DeviceKeys.detail(id),
      queryFn: (context) => deviceRepository.byId(id, signal: context.signal),
      refetchInterval: const RefetchInterval.every(Duration(seconds: 5)),
    );
// <<<

// >>> guides/polling.md#background
// A wall-mounted dashboard on a desktop: keep it current while another
// window is in front.
QueryObserverOptions<List<Device>> dashboardQuery() => QueryObserverOptions(
      queryKey: DeviceKeys.list,
      queryFn: (context) => deviceRepository.list(signal: context.signal),
      refetchInterval: const RefetchInterval.every(Duration(minutes: 1)),
      refetchIntervalInBackground: true,
    );
// <<<

// >>> guides/polling.md#until-confirmed
// lib/data/firmware_queries.dart
QueryKey firmwareJobKey(String jobId) =>
    QueryKey(<Object?>['firmware-job', jobId]);

QueryObserverOptions<FirmwareJob> firmwareJobQuery(String jobId) =>
    QueryObserverOptions(
      queryKey: firmwareJobKey(jobId),
      queryFn: (context) =>
          deviceRepository.firmwareJob(jobId, signal: context.signal),
      refetchInterval: const RefetchInterval.dynamic(_untilTheJobSettles),
    );

Duration? _untilTheJobSettles(Query<Object?> query) => switch (query.state) {
      QueryState(data: FirmwareJob(done: true)) => null, // confirmed: stop
      QueryState(consecutiveErrorCount: >= 5) => null, // gone quiet: stop
      _ => const Duration(seconds: 2),
    };
// <<<

// >>> guides/polling.md#job-progress
class FirmwareProgress extends StatelessWidget {
  const FirmwareProgress({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context) {
    final job = context.query(firmwareJobQuery(jobId));
    return switch (job) {
      QuerySuccess(data: FirmwareJob(done: true)) =>
        const Text('Update installed'),
      _ when job.consecutiveErrorCount >= 5 =>
        const Text('The device stopped answering. Check it and try again.'),
      _ => const LinearProgressIndicator(),
    };
  }
}
// <<<

// ---------------------------------------------------------------------------
// guides/query-retries.md
// ---------------------------------------------------------------------------

// >>> guides/query-retries.md#client-defaults
QueryClient deviceAppClient() => QueryClient(
      defaultOptions: const DefaultOptions(
        queries: QueryDefaults(
          retry: RetryPolicy.times(2),
          retryDelay: RetryDelay.exponential(
            base: Duration(milliseconds: 500),
            maximum: Duration(seconds: 8),
          ),
        ),
      ),
    );
// <<<

// >>> guides/query-retries.md#server-errors-only
const RetryPolicy retryServerErrors = RetryPolicy.when(_retryServerErrors);

bool _retryServerErrors(int failureCount, Object error, StackTrace _) =>
    failureCount < 3 &&
    switch (error) {
      // 4xx: the request is wrong, and asking again will not change that.
      ApiException(:final statusCode) => statusCode >= 500,
      // A timeout or a dropped connection may well work the second time.
      _ => true,
    };
// <<<

// >>> guides/query-retries.md#retry-after
const RetryDelay honourRetryAfter = RetryDelay.dynamic(_retryAfter);

Duration _retryAfter(int failureCount, Object error) => switch (error) {
      ApiException(:final retryAfter?) => retryAfter,
      _ => RetryDelay.defaultValue.resolve(failureCount, error),
    };
// <<<

// >>> guides/query-retries.md#attempts
Widget devicesStatus(QueryResult<List<Device>> devices) => switch (devices) {
      QueryPending(failureCount: 0) => const Text('Loading devices…'),
      QueryPending(:final failureCount, :final failureReason) =>
        Text('Still trying (attempt ${failureCount + 1}): $failureReason'),
      QueryError(:final error) => Text('Could not load devices: $error'),
      QuerySuccess(:final data) => Text('${data.length} devices'),
    };
// <<<

// ---------------------------------------------------------------------------
// guides/query-cancellation.md
// ---------------------------------------------------------------------------

// >>> guides/query-cancellation.md#steps
// Reading a long log off a device, chunk by chunk, over a slow link.
Future<List<String>> readDeviceLog(
  QueryFunctionContext context,
  String deviceId,
) async {
  final signal = context.signal;
  final lines = <String>[];
  for (var chunk = 0; chunk < 20; chunk++) {
    signal.throwIfCancelled(); // nobody wants the rest
    lines.addAll(
      await deviceRepository.readLog(deviceId, chunk, signal: signal),
    );
  }
  return lines;
}
// <<<

// >>> guides/query-cancellation.md#cancel-button
class CancelLogButton extends StatelessWidget {
  const CancelLogButton({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => QueryClientProvider.read(context)
            .cancelQueries(
              filters: QueryFilters(queryKey: deviceLogKey(deviceId)),
            )
            .ignore(),
        child: const Text('Stop reading'),
      );
}
// <<<

QueryKey deviceLogKey(String deviceId) =>
    QueryKey(<Object?>['device-log', deviceId]);

// ---------------------------------------------------------------------------
// guides/paginated-queries.md
// ---------------------------------------------------------------------------

// >>> guides/paginated-queries.md#page-query
QueryObserverOptions<DevicePage> devicePageQuery(int page) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.page(page),
      queryFn: (context) => deviceRepository.page(page, signal: context.signal),
      // `const`: one value on every build, so the options compare unchanged.
      placeholderData: const PlaceholderData.keepPrevious(),
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    );
// <<<

// >>> guides/paginated-queries.md#page-view
/// The rows and the two buttons, from whichever read the screen uses.
Widget devicePageView(
  QueryResult<DevicePage> result, {
  required int page,
  required ValueChanged<int> goTo,
}) =>
    switch (result) {
      QueryPending() => const Center(child: CircularProgressIndicator()),
      QueryError(:final error) => Center(child: Text('No devices: $error')),
      QuerySuccess(:final data, :final isPlaceholderData) => Column(
          children: <Widget>[
            Expanded(
              // The previous page, dimmed, while this one loads.
              child: Opacity(
                opacity: isPlaceholderData ? 0.5 : 1,
                child: ListView(
                  children: <Widget>[
                    for (final device in data.devices) DeviceTile(device),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                TextButton(
                  onPressed: page == 0 ? null : () => goTo(page - 1),
                  child: const Text('Previous'),
                ),
                Text('Page ${page + 1}'),
                TextButton(
                  // Not while a placeholder shows: `hasMore` is the old page's.
                  onPressed: isPlaceholderData || !data.hasMore
                      ? null
                      : () => goTo(page + 1),
                  child: const Text('Next'),
                ),
              ],
            ),
          ],
        ),
    };
// <<<

class DevicePager extends StatefulWidget {
  const DevicePager({super.key});

  @override
  State<DevicePager> createState() => _DevicePagerState();
}

// >>> guides/paginated-queries.md#pager-context-query
class _DevicePagerState extends State<DevicePager> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    // The id keeps one observer across pages, so keepPrevious has a previous.
    final result = context.query(devicePageQuery(_page), id: 'devices');
    return devicePageView(
      result,
      page: _page,
      goTo: (page) => setState(() => _page = page),
    );
  }
}
// <<<

class DevicePagerBuilder extends StatefulWidget {
  const DevicePagerBuilder({super.key});

  @override
  State<DevicePagerBuilder> createState() => _DevicePagerBuilderState();
}

// >>> guides/paginated-queries.md#pager-builder
class _DevicePagerBuilderState extends State<DevicePagerBuilder> {
  int _page = 0;

  @override
  Widget build(BuildContext context) => QueryBuilder(
        // The builder keeps its observer when the key changes.
        options: devicePageQuery(_page),
        builder: (context, result) => devicePageView(
          result,
          page: _page,
          goTo: (page) => setState(() => _page = page),
        ),
      );
}
// <<<

class DevicePagerMixin extends StatefulWidget {
  const DevicePagerMixin({super.key});

  @override
  State<DevicePagerMixin> createState() => _DevicePagerMixinState();
}

// >>> guides/paginated-queries.md#pager-mixin
class _DevicePagerMixinState extends State<DevicePagerMixin> with QueryMixin {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    // The id keeps one observer across pages, so keepPrevious has a previous.
    final result = watchQuery(devicePageQuery(_page), id: 'devices');
    return devicePageView(
      result,
      page: _page,
      goTo: (page) => setState(() => _page = page),
    );
  }
}
// <<<

class DevicePagerController extends StatefulWidget {
  const DevicePagerController({super.key});

  @override
  State<DevicePagerController> createState() => _DevicePagerControllerState();
}

// >>> guides/paginated-queries.md#pager-controller
class _DevicePagerControllerState extends State<DevicePagerController> {
  int _page = 0;
  late final QueryController<DevicePage, DevicePage> _devices =
      QueryController.create(
    QueryClientProvider.read(context),
    devicePageQuery(_page),
  );

  void _goTo(int page) {
    setState(() => _page = page);
    // The same observer, a new key: keepPrevious has a previous.
    _devices.setOptions(devicePageQuery(page));
  }

  @override
  void dispose() {
    _devices.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: _devices,
        builder: (context, result, _) =>
            devicePageView(result, page: _page, goTo: _goTo),
      );
}
// <<<

// >>> guides/paginated-queries.md#prefetch-next
/// Call from `build` with the page on screen. Starts the next page's fetch
/// after the frame — a fetch fires cache events, and the widgets listening
/// to them are in the middle of building — and only once per page.
void prefetchNextPage(
  BuildContext context,
  QueryResult<DevicePage> result, {
  required int page,
  required Set<int> prefetched,
}) {
  if (result case QuerySuccess(:final data, isPlaceholderData: false)
      when data.hasMore && prefetched.add(page + 1)) {
    final client = QueryClientProvider.read(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      client.query(devicePageQuery(page + 1)).ignore();
    });
  }
}
// <<<

// ---------------------------------------------------------------------------
// guides/infinite-queries.md
// ---------------------------------------------------------------------------

// >>> guides/infinite-queries.md#activity-query
InfiniteQueryObserverOptions<ActivityPage, int> activityQuery(String id) =>
    InfiniteQueryObserverOptions<ActivityPage, int>(
      queryKey: DeviceKeys.activity(id),
      pageFn: (context) => deviceRepository.activity(
        id,
        offset: context.pageParam,
        signal: context.signal,
      ),
      initialPageParam: 0,
      getNextPageParam: (page, pages, offset, offsets) => page.nextOffset,
    );
// <<<

class ActivityLog extends StatefulWidget {
  const ActivityLog({super.key, required this.deviceId});

  final String deviceId;

  @override
  State<ActivityLog> createState() => _ActivityLogState();
}

// >>> guides/infinite-queries.md#activity-log
class _ActivityLogState extends State<ActivityLog> {
  late final InfiniteQueryController<ActivityPage, int,
      InfiniteData<ActivityPage, int>> _log = InfiniteQueryController(
    QueryClientProvider.read(context),
    activityQuery(widget.deviceId),
  );
  final ScrollController _scroll = ScrollController();
  double? _askedAt;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final position = _scroll.position;
    if (position.extentAfter < 400 &&
        position.pixels != _askedAt &&
        _log.hasNextPage &&
        !_log.isFetchingNextPage) {
      _askedAt = position.pixels;
      _log.fetchNextPage().ignore();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _log.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _log,
        builder: (context, _) {
          final result = _log.value;
          if (result is QueryPending) {
            return const Center(child: CircularProgressIndicator());
          }
          if (result case QueryError(hasStaleData: false, :final error)) {
            return Center(child: Text('No activity: $error'));
          }
          final entries = <ActivityEntry>[
            for (final page in result.dataOrNull?.pages ?? <ActivityPage>[])
              ...page.entries,
          ];
          return RefreshIndicator(
            // Refetches every page held, first to last.
            onRefresh: _log.refetch,
            child: ListView.builder(
              controller: _scroll,
              // Pull-to-refresh needs a list that scrolls when it is short.
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: entries.length + 1,
              // A widget per row: the row reads nothing through this context.
              itemBuilder: (context, index) => index < entries.length
                  ? ActivityTile(entries[index])
                  : _footer(),
            ),
          );
        },
      );

  Widget _footer() {
    if (_log.isFetchingNextPage) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_log.isFetchNextPageError) {
      return TextButton(
        onPressed: _log.fetchNextPage,
        child: const Text('Could not load older entries. Try again'),
      );
    }
    return _log.hasNextPage
        ? const SizedBox(height: 64)
        : const ListTile(title: Text('No older activity'));
  }
}
// <<<

// ---------------------------------------------------------------------------
// guides/initial-query-data.md
// ---------------------------------------------------------------------------

// >>> guides/initial-query-data.md#bundled
// The catalogue ships with the app, so the "add a device" picker never
// shows a spinner. Dated when it was bundled, it is older than a day on
// most phones, and the server's copy replaces it in the background.
QueryObserverOptions<List<DeviceType>> deviceTypesQuery() =>
    QueryObserverOptions(
      queryKey: QueryKey(<Object?>['device-types']),
      queryFn: (context) => deviceRepository.types(signal: context.signal),
      staleTime: const StaleTime.duration(Duration(days: 1)),
      initialData: const InitialData.value(bundledDeviceTypes),
      initialDataUpdatedAt: bundledDeviceTypesDate,
    );
// <<<

// >>> guides/initial-query-data.md#only-if-recent
QueryObserverOptions<Device> deviceSeededIfRecent(
  QueryClient client,
  String id,
) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.detail(id),
      queryFn: (context) => deviceRepository.byId(id, signal: context.signal),
      initialData: InitialData.compute(() {
        final list = client.getQueryState<List<Device>>(DeviceKeys.list);
        final updatedAt = list?.dataUpdatedAt;
        // An old list is not worth showing as the device's current state.
        if (updatedAt == null ||
            DateTime.now().difference(updatedAt) >
                const Duration(seconds: 10)) {
          return null;
        }
        return list?.data?.where((device) => device.id == id).firstOrNull;
      }),
    );
// <<<

// ---------------------------------------------------------------------------
// guides/placeholder-query-data.md
// ---------------------------------------------------------------------------

// >>> guides/placeholder-query-data.md#value
QueryObserverOptions<Device> deviceQuery(String id) => QueryObserverOptions(
      queryKey: DeviceKeys.detail(id),
      queryFn: (context) => deviceRepository.byId(id, signal: context.signal),
      placeholderData: const PlaceholderData.value(Device.loading),
    );
// <<<

// >>> guides/placeholder-query-data.md#from-list
QueryObserverOptions<Device> devicePreviewedFromList(
  QueryClient client,
  String id,
) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.detail(id),
      queryFn: (context) => deviceRepository.byId(id, signal: context.signal),
      // The list row, shown while the detail loads — and not cached as it.
      placeholderData: PlaceholderData.compute(
        (_, __) => client
            .getQueryData<List<Device>>(DeviceKeys.list)
            ?.where((device) => device.id == id)
            .firstOrNull,
      ),
    );
// <<<

// >>> guides/placeholder-query-data.md#render
Widget deviceTitle(QueryResult<Device> device) => switch (device) {
      QuerySuccess(:final data, isPlaceholderData: true) =>
        Opacity(opacity: 0.5, child: Text(data.name)),
      QuerySuccess(:final data) => Text(data.name),
      QueryPending() => const Text('…'),
      QueryError(:final error) => Text('Could not load: $error'),
    };
// <<<

// ---------------------------------------------------------------------------
// guides/scroll-restoration.md
// ---------------------------------------------------------------------------

QueryObserverOptions<List<Device>> devicesOfKind(String kind) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.byKind(kind),
      queryFn: (context) =>
          deviceRepository.byKind(kind, signal: context.signal),
    );

// >>> guides/scroll-restoration.md#page-storage-key
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
// <<<

void followReachability(QueryClient client, Stream<bool> reachable) {
  // >>> guides/connectivity.md#online-manager
  client.onlineManager.setEventListener((setOnline) {
    final subscription = reachable.listen(setOnline);
    return subscription.cancel;
  });
  // …or by hand:
  client.onlineManager.setOnline(false);
  // <<<
}
