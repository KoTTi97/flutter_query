/// Every Dart sample on the documentation site, as code the analyzer sees.
///
/// A documentation site is the one place in a repository where code is not
/// compiled, so it is the one place where code rots without anybody noticing.
/// Writing these pages already caught two wrong signatures by hand; this file
/// is so that the next two are caught by `dart analyze --fatal-infos`
/// instead.
///
/// The rule: **a Dart sample on the site appears here**, under a comment
/// naming the page it appears on, and the two are kept identical. Samples
/// that need a third-party package (`dio`, `connectivity_plus`,
/// `signals_flutter`) are the exception — neither published package may
/// depend on one, so those stay prose-only and say so on the page.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

// ---------------------------------------------------------------------------
// The domain the samples talk about. Small on purpose: the samples are about
// the cache, not about sensors.
// ---------------------------------------------------------------------------

/// A model with value equality — which the samples about structural sharing
/// and rebuilds depend on being true.
@immutable
class Sensor {
  const Sensor({required this.id, required this.name, required this.connected});

  final String id;
  final String name;
  final bool connected;

  Sensor copyWith({String? name}) =>
      Sensor(id: id, name: name ?? this.name, connected: connected);

  @override
  bool operator ==(Object other) =>
      other is Sensor &&
      other.id == id &&
      other.name == name &&
      other.connected == connected;

  @override
  int get hashCode => Object.hash(id, name, connected);
}

@immutable
class Comment {
  const Comment(this.body);

  final String body;
}

@immutable
class Post {
  const Post(this.title);

  final String title;
}

/// Stands in for an HTTP client. The real one would hand `context.signal` to
/// its own cancellation token; see the site's cancellation section.
class Api {
  Future<List<Sensor>> listSensors({QueryCancelToken? signal}) async =>
      const <Sensor>[];

  Future<Sensor> getSensor(String id, {QueryCancelToken? signal}) async =>
      const Sensor(id: '1', name: 'Kitchen', connected: true);

  Future<Sensor> rename(String id, String name) async =>
      Sensor(id: id, name: name, connected: true);

  Future<void> addSensor(String name) async {}

  Future<List<Comment>> comments(String postId) async => const <Comment>[];

  Future<List<Post>> feed({required int cursor}) async => const <Post>[];
}

final Api api = Api();

final QueryKey sensorsKey = QueryKey(<Object?>['sensors']);

QueryKey sensorKey(String id) => QueryKey(<Object?>['sensors', id]);

// ---------------------------------------------------------------------------
// getting-started/first-query.md
// ---------------------------------------------------------------------------

QueryObserverOptions<List<Sensor>, List<Sensor>> sensorsQuery() =>
    QueryObserverOptions(
      queryKey: sensorsKey,
      queryFn: (context) => api.listSensors(signal: context.signal),
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    );

QueryObserverOptions<Sensor, Sensor> sensorQuery(String id) =>
    QueryObserverOptions(
      queryKey: sensorKey(id),
      queryFn: (context) => api.getSensor(id, signal: context.signal),
    );

void mainWithProvider() {
  runApp(
    QueryClientProvider(
      client: QueryClient(),
      child: const MaterialApp(home: SensorsScreen()),
    ),
  );
}

Widget providerThatOwnsItsClient() => QueryClientProvider.create(
      create: QueryClient.new,
      child: const MaterialApp(home: SensorsScreen()),
    );

class SensorsScreen extends StatelessWidget {
  const SensorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sensors = context.query(sensorsQuery());

    return Scaffold(
      appBar: AppBar(title: const Text('Sensors')),
      body: switch (sensors) {
        QueryPending() => const Center(child: CircularProgressIndicator()),
        QueryError(:final error) => Center(child: Text('$error')),
        QuerySuccess(:final data) => ListView(
            children: <Widget>[
              for (final sensor in data) SensorTile(sensor),
            ],
          ),
      },
    );
  }
}

class AddSensorButton extends StatelessWidget {
  const AddSensorButton({super.key});

  @override
  Widget build(BuildContext context) {
    // Take the client here, in build — not inside the callback. A mutation
    // outlives the widget that started it, so `onSuccess` can run after this
    // element is gone, and looking an ancestor up from a deactivated element
    // throws.
    final client = QueryClientProvider.of(context);

    final add = context.mutation(
      MutationOptions.simple(
        mutationFn: api.addSensor,
        onSuccess: (_, __, ___) => client.invalidateQueries(
          filters: QueryFilters(queryKey: sensorsKey),
        ),
      ),
    );

    return FilledButton(
      onPressed: add.value.isPending ? null : () => add.mutate('New sensor'),
      child: Text(add.value.isPending ? 'Adding…' : 'Add'),
    );
  }
}

// ---------------------------------------------------------------------------
// guides/reading-a-query.md — the four call styles
// ---------------------------------------------------------------------------

class SensorScreenContext extends StatelessWidget {
  const SensorScreenContext(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    final sensor = context.query(sensorQuery(id));
    return switch (sensor) {
      QueryPending() => const CircularProgressIndicator(),
      QuerySuccess(:final data) => SensorCard(data),
      QueryError(:final error, :final staleData) =>
        ErrorBanner(error, staleData),
    };
  }
}

Widget sensorScreenBuilder(String id) => QueryBuilder<Sensor>(
      options: sensorQuery(id),
      builder: (context, result) => switch (result) {
        QueryPending() => const CircularProgressIndicator(),
        QuerySuccess(:final data) => SensorCard(data),
        QueryError(:final error, :final staleData) =>
          ErrorBanner(error, staleData),
      },
    );

class SensorScreenMixin extends StatefulWidget {
  const SensorScreenMixin(this.id, {super.key});

  final String id;

  @override
  State<SensorScreenMixin> createState() => _SensorScreenMixinState();
}

class _SensorScreenMixinState extends State<SensorScreenMixin> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final sensor = watchQuery(sensorQuery(widget.id));
    final rename = watchMutation(renameSensor(widget.id));

    return Column(
      children: <Widget>[
        Text(sensor.dataOrNull?.name ?? '…'),
        FilledButton(
          onPressed: () => rename.mutate('Renamed'),
          child: const Text('Rename'),
        ),
      ],
    );
  }
}

/// A read whose key the screen switches needs an `id:`, so the observer
/// follows the key and `keepPrevious` has a previous.
class PagedReader extends StatefulWidget {
  const PagedReader(this.page, {super.key});

  final int page;

  @override
  State<PagedReader> createState() => _PagedReaderState();
}

class _PagedReaderState extends State<PagedReader> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final page = watchQuery(pageQuery(widget.page), id: 'page');
    return Text('${page.dataOrNull?.length ?? 0} rows');
  }
}

QueryObserverOptions<List<Post>, List<Post>> pageQuery(int page) =>
    QueryObserverOptions(
      queryKey: QueryKey(<Object?>['posts', page]),
      queryFn: (context) => api.feed(cursor: page),
      placeholderData: PlaceholderData.compute((previous, _) => previous),
    );

QueryController<Sensor, Sensor> controllerStyle(QueryClient client, String id) {
  final sensor = QueryController.create(client, sensorQuery(id));
  // … sensor.value, sensor.addListener, sensor.refetch() …
  return sensor;
}

// ---------------------------------------------------------------------------
// guides/options.md
// ---------------------------------------------------------------------------

QueryObserverOptions<List<Comment>, List<Comment>> commentsQuery(
  String? postId,
) =>
    QueryObserverOptions(
      queryKey: QueryKey(<Object?>['posts', postId, 'comments']),
      queryFn: (context) => api.comments(postId!),
      enabled: postId == null ? Enabled.no : Enabled.yes,
    );

QueryObserverOptions<Sensor, Sensor> withoutStructuralSharing(String id) =>
    QueryObserverOptions(
      queryKey: sensorKey(id),
      queryFn: (context) => api.getSensor(id),
      structuralSharing: (previous, next) => next,
    );

// ---------------------------------------------------------------------------
// guides/rebuilds.md
// ---------------------------------------------------------------------------

QueryObserverOptions<List<Sensor>, int> connectedCountQuery() =>
    QueryObserverOptions(
      queryKey: sensorsKey,
      queryFn: (context) => api.listSensors(signal: context.signal),
      select: (sensors) => sensors.where((s) => s.connected).length,
    );

/// A record has value equality already, which makes it the easy pick for a
/// `select` output.
QueryObserverOptions<List<Sensor>, ({int connected, int total})>
    connectedRecordQuery() => QueryObserverOptions(
          queryKey: sensorsKey,
          queryFn: (context) => api.listSensors(signal: context.signal),
          select: (data) => (
            connected: data.where((s) => s.connected).length,
            total: data.length,
          ),
        );

Widget buildWhenSample(String id) => QueryBuilder<Sensor>(
      options: sensorQuery(id),
      buildWhen: (previous, current) =>
          previous.dataOrNull != current.dataOrNull,
      builder: (context, result) => Text(result.dataOrNull?.name ?? '…'),
    );

// ---------------------------------------------------------------------------
// guides/mutations.md
// ---------------------------------------------------------------------------

MutationOptions<void, String, void> renameSensor(String id) =>
    MutationOptions.simple(mutationFn: (String name) => api.rename(id, name));

/// The optimistic shape: `onMutate` snapshots and patches, and what it returns
/// is the rollback handle `onError` and `onSettled` receive.
MutationOptions<Sensor, String, Sensor?> renameOptimistically(
  QueryClient client,
  String id,
) =>
    MutationOptions<Sensor, String, Sensor?>(
      mutationFn: (name) => api.rename(id, name),
      onMutate: (name) async {
        await client.cancelQueries(
          filters: QueryFilters(queryKey: sensorKey(id)),
        );
        final previous = client.getQueryData<Sensor>(sensorKey(id));
        client.updateQueryData<Sensor>(
          sensorKey(id),
          (sensor) => sensor?.copyWith(name: name),
        );
        return previous; // the rollback handle
      },
      onError: (error, stack, name, previous) {
        if (previous != null) client.setQueryData(sensorKey(id), previous);
      },
      onSettled: (_, __, ___, ____, _____) => client.invalidateQueries(
        filters: QueryFilters(queryKey: sensorKey(id)),
      ),
    );

void mutateWithPerCallCallbacks(
  MutationController<void, String, void> add,
  BuildContext context,
) {
  add.mutate(
    'New sensor',
    callbacks: MutateCallbacks<void, String, void>(
      onSuccess: (data, vars, _) => Navigator.of(context).pop(),
    ),
  );
}

MutationOptions<void, String, void> serialisedWrite(String id) =>
    MutationOptions.simple(
      mutationFn: (String name) => api.rename(id, name),
      scope: const MutationScope('sensor-writes'),
    );

// ---------------------------------------------------------------------------
// guides/infinite-queries.md
// ---------------------------------------------------------------------------

/// What an *observer* takes: a third type argument, for `select`. Its default
/// is the whole `InfiniteData`.
InfiniteQueryObserverOptions<List<Post>, int, InfiniteData<List<Post>, int>>
    feedQuery() => InfiniteQueryObserverOptions<List<Post>, int,
            InfiniteData<List<Post>, int>>(
          queryKey: QueryKey(<Object?>['feed']),
          pageFn: (context) => api.feed(cursor: context.pageParam),
          initialPageParam: 0,
          getNextPageParam: (page, pages, pageParam, pageParams) =>
              page.isEmpty ? null : pageParam + page.length,
        );

/// What `QueryClient.query` takes: no observer, so no `select`, so two type
/// arguments.
InfiniteQueryOptions<List<Post>, int> feedQueryForClient() =>
    InfiniteQueryOptions<List<Post>, int>(
      queryKey: QueryKey(<Object?>['feed']),
      pageFn: (context) => api.feed(cursor: context.pageParam),
      initialPageParam: 0,
      getNextPageParam: (page, pages, pageParam, pageParams) =>
          page.isEmpty ? null : pageParam + page.length,
    );

class Feed extends StatelessWidget {
  const Feed({super.key});

  @override
  Widget build(BuildContext context) {
    final feed = context.infiniteQuery(feedQuery());

    final posts = feed.value.dataOrNull?.flatten<Post>() ?? const <Post>[];
    if (feed.hasNextPage && !feed.isFetchingNextPage) {
      feed.fetchNextPage().ignore();
    }

    return ListView(
      children: <Widget>[for (final post in posts) Text(post.title)],
    );
  }
}

/// A scroll listener is level-triggered: a view resting near the bottom keeps
/// receiving notifications, and a page landing sends one of its own. Remember
/// where the last request was made and require the view to have moved.
mixin LoadMoreOnScroll<T extends StatefulWidget> on State<T> {
  final ScrollController scrollController = ScrollController();
  double? _askedAt;

  InfiniteQueryController<List<Post>, int, InfiniteData<List<Post>, int>>
      get feed;

  void onScroll() {
    final position = scrollController.position;
    if (position.extentAfter < 400 &&
        position.pixels != _askedAt &&
        feed.hasNextPage &&
        !feed.isFetchingNextPage) {
      _askedAt = position.pixels;
      feed.fetchNextPage().ignore();
    }
  }
}

// ---------------------------------------------------------------------------
// guides/the-query-client.md
// ---------------------------------------------------------------------------

Future<List<Sensor>> fetchImperatively(QueryClient client) => client.query(
      QueryOptions<List<Sensor>>(
        queryKey: sensorsKey,
        queryFn: (context) => api.listSensors(signal: context.signal),
      ),
    );

void filterSamples(QueryClient client) {
  client
      .invalidateQueries(filters: QueryFilters(queryKey: sensorsKey))
      .ignore();
  client.removeQueries(
    filters: QueryFilters(queryKey: sensorsKey, exact: true),
  );
  client
      .refetchQueries(filters: QueryFilters(type: QueryTypeFilter.active))
      .ignore();
  client
      .resetQueries(
          filters: QueryFilters(predicate: (query) => query.isStale()))
      .ignore();
}

void cacheWriteSamples(QueryClient client, String id, Sensor sensor) {
  client.getQueryData<List<Sensor>>(sensorsKey);
  client.setQueryData<Sensor>(sensorKey(id), sensor);
  client.updateQueryData<Sensor>(
    sensorKey(id),
    (previous) => previous?.copyWith(name: 'Renamed'),
  );
  client.updateQueriesData<Sensor>(
    (previous) => previous?.copyWith(name: 'Renamed'),
    filters: QueryFilters(queryKey: sensorsKey),
  );
}

QueryClient clientWithDefaults() {
  final client = QueryClient(
    defaultOptions: DefaultOptions(
      queries: QueryDefaults(
        staleTime: const StaleTime.duration(Duration(seconds: 30)),
        retry: const RetryPolicy.times(2),
      ),
    ),
  );

  client.setQueryDefaults(
    QueryKey(<Object?>['sensors']),
    QueryDefaults(queryFn: (context) => api.listSensors()),
  );

  return client;
}

// ---------------------------------------------------------------------------
// guides/collections-and-side-effects.md
// ---------------------------------------------------------------------------

Widget queriesBuilderSample(List<String> visibleIds) =>
    QueriesBuilder<Sensor, String>(
      queries: <QueryObserverOptions<Sensor, String>>[
        for (final id in visibleIds)
          QueryObserverOptions<Sensor, String>(
            queryKey: sensorKey(id),
            queryFn: (context) => api.getSensor(id, signal: context.signal),
            select: (sensor) => sensor.name,
          ),
      ],
      builder: (context, results) => Column(
        children: <Widget>[
          for (final result in results) Text(result.dataOrNull ?? '…'),
        ],
      ),
    );

Widget queryListenerSample(QueryController<Sensor, Sensor> sensor) =>
    QueryListener<Sensor, Sensor>(
      controller: sensor,
      listenWhen: (previous, next) => previous.errorOrNull != next.errorOrNull,
      listener: (context, result) => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sensor unreachable')),
      ),
      child: const SizedBox.shrink(),
    );

MutationStateController<int> writesInFlight(QueryClient client) =>
    MutationStateController<int>(
      client,
      filters: const MutationFilters(status: MutationStatus.pending),
      select: (mutation) => 1,
    );

// ---------------------------------------------------------------------------
// guides/pure-dart.md — the parts that do not need `dart:io`
// ---------------------------------------------------------------------------

void Function() observeWithoutFlutter(QueryClient client, String id) {
  final observer = client.observe<Sensor, Sensor>(
    QueryObserverOptions<Sensor, Sensor>(
      queryKey: sensorKey(id),
      queryFn: (context) => api.getSensor(id, signal: context.signal),
    ),
  );

  return observer.subscribe((result) {
    switch (result) {
      case QueryPending():
        debugPrint('loading');
      case QuerySuccess(:final data):
        debugPrint(data.name);
      case QueryError(:final error, :final staleData):
        debugPrint('$error (still showing ${staleData?.name})');
    }
  });
}

// ---------------------------------------------------------------------------
// The two leaf widgets the samples above render into.
// ---------------------------------------------------------------------------

class SensorCard extends StatelessWidget {
  const SensorCard(this.sensor, {super.key});

  final Sensor sensor;

  @override
  Widget build(BuildContext context) => Card(child: Text(sensor.name));
}

class SensorTile extends StatelessWidget {
  const SensorTile(this.sensor, {super.key});

  final Sensor sensor;

  @override
  Widget build(BuildContext context) => ListTile(title: Text(sensor.name));
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.error, this.staleData, {super.key});

  final Object error;
  final Sensor? staleData;

  @override
  Widget build(BuildContext context) => Text('$error');
}
