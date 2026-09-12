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
// the cache, not about tasks.
// ---------------------------------------------------------------------------

/// A model with value equality — which the samples about structural sharing
/// and rebuilds depend on being true.
@immutable
class Task {
  const Task({required this.id, required this.name, required this.done});

  final String id;
  final String name;
  final bool done;

  Task copyWith({String? name}) =>
      Task(id: id, name: name ?? this.name, done: done);

  @override
  bool operator ==(Object other) =>
      other is Task &&
      other.id == id &&
      other.name == name &&
      other.done == done;

  @override
  int get hashCode => Object.hash(id, name, done);
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
  Future<List<Task>> listTasks({QueryCancelToken? signal}) async =>
      const <Task>[];

  Future<Task> getTask(String id, {QueryCancelToken? signal}) async =>
      const Task(id: '1', name: 'Draft the changelog', done: true);

  Future<Task> rename(String id, String name) async =>
      Task(id: id, name: name, done: true);

  Future<void> addTask(String name) async {}

  Future<List<Comment>> comments(String postId) async => const <Comment>[];

  Future<List<Post>> feed({required int cursor}) async => const <Post>[];
}

final Api api = Api();

final QueryKey tasksKey = QueryKey(<Object?>['tasks']);

QueryKey taskKey(String id) => QueryKey(<Object?>['tasks', id]);

// ---------------------------------------------------------------------------
// getting-started/first-query.md
// ---------------------------------------------------------------------------

QueryObserverOptions<List<Task>> tasksQuery() => QueryObserverOptions(
      queryKey: tasksKey,
      queryFn: (context) => api.listTasks(signal: context.signal),
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    );

QueryObserverOptions<Task> taskQuery(String id) => QueryObserverOptions(
      queryKey: taskKey(id),
      queryFn: (context) => api.getTask(id, signal: context.signal),
    );

void mainWithProvider() {
  runApp(
    QueryClientProvider(
      client: QueryClient(),
      child: const MaterialApp(home: TasksScreen()),
    ),
  );
}

Widget providerThatOwnsItsClient() => QueryClientProvider.create(
      create: QueryClient.new,
      child: const MaterialApp(home: TasksScreen()),
    );

// --- Guides / Lifecycle and connectivity ------------------------------------

/// A client whose focus comes from a `setEventListener` adapter of its own.
/// The `connectivity_plus` sample on the same page stays prose-only, but this
/// one and the fixed status below need nothing beyond Flutter.
Widget providerWithItsOwnFocusSource(QueryClient client) => QueryClientProvider(
      client: client,
      // The lifecycle listener and a setEventListener adapter are two sources
      // of focus for one manager. Pick one.
      observeAppLifecycle: false,
      child: const MaterialApp(home: TasksScreen()),
    );

/// Connectivity with no stream behind it: the value *is* the verdict, and a
/// changed one reaches the client on the rebuild that changes it.
Widget providerWithAFixedOnlineStatus(QueryClient client, bool online) =>
    QueryClientProvider(
      client: client,
      onlineStatus: OnlineStatus.fixed(online),
      child: const MaterialApp(home: TasksScreen()),
    );

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = context.query(tasksQuery());

    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      body: switch (tasks) {
        QueryPending() => const Center(child: CircularProgressIndicator()),
        QueryError(:final error) => Center(child: Text('$error')),
        QuerySuccess(:final data) => ListView(
            children: <Widget>[
              for (final task in data) TaskTile(task),
            ],
          ),
      },
    );
  }
}

class AddTaskButton extends StatelessWidget {
  const AddTaskButton({super.key});

  @override
  Widget build(BuildContext context) {
    // Take the client here, in build — not inside the callback. A mutation
    // outlives the widget that started it, so `onSuccess` can run after this
    // element is gone, and looking an ancestor up from a deactivated element
    // throws.
    final client = QueryClientProvider.of(context);

    final add = context.mutation(
      MutationOptions.simple(
        mutationFn: api.addTask,
        onSuccess: (_, __, ___) => client.invalidateQueries(
          filters: QueryFilters(queryKey: tasksKey),
        ),
      ),
    );

    return FilledButton(
      onPressed: add.value.isPending ? null : () => add.mutate('New task'),
      child: Text(add.value.isPending ? 'Adding…' : 'Add'),
    );
  }
}

// ---------------------------------------------------------------------------
// guides/reading-a-query.md — the four call styles
// ---------------------------------------------------------------------------

class TaskScreenContext extends StatelessWidget {
  const TaskScreenContext(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    final task = context.query(taskQuery(id));
    return switch (task) {
      QueryPending() => const CircularProgressIndicator(),
      QuerySuccess(:final data) => TaskCard(data),
      QueryError(:final error, :final staleData) =>
        ErrorBanner(error, staleData),
    };
  }
}

Widget taskScreenBuilder(String id) => QueryBuilder<Task>(
      options: taskQuery(id),
      builder: (context, result) => switch (result) {
        QueryPending() => const CircularProgressIndicator(),
        QuerySuccess(:final data) => TaskCard(data),
        QueryError(:final error, :final staleData) =>
          ErrorBanner(error, staleData),
      },
    );

class TaskScreenMixin extends StatefulWidget {
  const TaskScreenMixin(this.id, {super.key});

  final String id;

  @override
  State<TaskScreenMixin> createState() => _TaskScreenMixinState();
}

class _TaskScreenMixinState extends State<TaskScreenMixin> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final task = watchQuery(taskQuery(widget.id));
    final rename = watchMutation(renameTask(widget.id));

    return Column(
      children: <Widget>[
        Text(task.dataOrNull?.name ?? '…'),
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

QueryObserverOptions<List<Post>> pageQuery(int page) => QueryObserverOptions(
      queryKey: QueryKey(<Object?>['posts', page]),
      queryFn: (context) => api.feed(cursor: page),
      placeholderData: PlaceholderData.compute((previous, _) => previous),
    );

QueryController<Task, Task> controllerStyle(QueryClient client, String id) {
  final task = QueryController.create(client, taskQuery(id));
  // … task.value, task.addListener, task.refetch() …
  return task;
}

// ---------------------------------------------------------------------------
// guides/options.md
// ---------------------------------------------------------------------------

/// The two shapes side by side; `taskQuery` above is the plain one.
QuerySelectOptions<Task, String> taskNameQuery(String id) => QuerySelectOptions(
      queryKey: taskKey(id),
      queryFn: (context) => api.getTask(id, signal: context.signal),
      select: (task) => task.name,
    );

QueryObserverOptions<List<Comment>> commentsQuery(
  String? postId,
) =>
    QueryObserverOptions(
      queryKey: QueryKey(<Object?>['posts', postId, 'comments']),
      queryFn: (context) => api.comments(postId!),
      enabled: postId == null ? Enabled.no : Enabled.yes,
    );

QueryObserverOptions<Task> withoutStructuralSharing(String id) =>
    QueryObserverOptions(
      queryKey: taskKey(id),
      queryFn: (context) => api.getTask(id),
      structuralSharing: (previous, next) => next,
    );

// ---------------------------------------------------------------------------
// guides/rebuilds.md
// ---------------------------------------------------------------------------

QuerySelectOptions<List<Task>, int> doneCountQuery() => QuerySelectOptions(
      queryKey: tasksKey,
      queryFn: (context) => api.listTasks(signal: context.signal),
      select: (tasks) => tasks.where((s) => s.done).length,
    );

/// A record has value equality already, which makes it the easy pick for a
/// `select` output.
QuerySelectOptions<List<Task>, ({int done, int total})> doneRecordQuery() =>
    QuerySelectOptions(
      queryKey: tasksKey,
      queryFn: (context) => api.listTasks(signal: context.signal),
      select: (data) => (
        done: data.where((s) => s.done).length,
        total: data.length,
      ),
    );

Widget buildWhenSample(String id) => QueryBuilder<Task>(
      options: taskQuery(id),
      buildWhen: (previous, current) =>
          previous.dataOrNull != current.dataOrNull,
      builder: (context, result) => Text(result.dataOrNull?.name ?? '…'),
    );

/// The same predicate on a keyless read: one implementation for all six places
/// that take one (C49, https://github.com/KoTTi97/flutter_query/issues/55).
QueryResult<Task> keylessBuildWhenSample(BuildContext context, String id) {
  final task = context.query(
    taskQuery(id),
    buildWhen: (previous, current) => previous.dataOrNull != current.dataOrNull,
  );
  return task;
}

// ---------------------------------------------------------------------------
// guides/mutations.md
// ---------------------------------------------------------------------------

MutationOptions<void, String, void> renameTask(String id) =>
    MutationOptions.simple(mutationFn: (String name) => api.rename(id, name));

/// The optimistic shape: `onMutate` snapshots and patches, and what it returns
/// is the rollback handle `onError` and `onSettled` receive.
MutationOptions<Task, String, Task?> renameOptimistically(
  QueryClient client,
  String id,
) =>
    MutationOptions<Task, String, Task?>(
      mutationFn: (name) => api.rename(id, name),
      onMutate: (name) async {
        await client.cancelQueries(
          filters: QueryFilters(queryKey: taskKey(id)),
        );
        final previous = client.getQueryData<Task>(taskKey(id));
        client.updateQueryData<Task>(
          taskKey(id),
          (task) => task?.copyWith(name: name),
        );
        return previous; // the rollback handle
      },
      onError: (error, stack, name, previous) {
        if (previous != null) client.setQueryData(taskKey(id), previous);
      },
      onSettled: (_, __, ___, ____, _____) => client.invalidateQueries(
        filters: QueryFilters(queryKey: taskKey(id)),
      ),
    );

void mutateWithPerCallCallbacks(
  MutationController<void, String, void> add,
  BuildContext context,
) {
  add.mutate(
    'New task',
    callbacks: MutateCallbacks<void, String, void>(
      onSuccess: (data, vars, _) => Navigator.of(context).pop(),
    ),
  );
}

MutationOptions<void, String, void> serialisedWrite(String id) =>
    MutationOptions.simple(
      mutationFn: (String name) => api.rename(id, name),
      scope: const MutationScope('task-writes'),
    );

// ---------------------------------------------------------------------------
// guides/infinite-queries.md
// ---------------------------------------------------------------------------

/// What an *observer* takes: the plain shape, whose data is the whole
/// `InfiniteData<List<Post>, int>`. `InfiniteQuerySelectOptions` is the
/// shape with a required `select` over it.
InfiniteQueryObserverOptions<List<Post>, int> feedQuery() =>
    InfiniteQueryObserverOptions<List<Post>, int>(
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

Future<List<Task>> fetchImperatively(QueryClient client) => client.query(
      QueryOptions<List<Task>>(
        queryKey: tasksKey,
        queryFn: (context) => api.listTasks(signal: context.signal),
      ),
    );

void filterSamples(QueryClient client) {
  client.invalidateQueries(filters: QueryFilters(queryKey: tasksKey)).ignore();
  client.removeQueries(
    filters: QueryFilters(queryKey: tasksKey, exact: true),
  );
  client
      .refetchQueries(filters: QueryFilters(type: QueryTypeFilter.active))
      .ignore();
  client
      .resetQueries(
          filters: QueryFilters(predicate: (query) => query.isStale()))
      .ignore();
}

void cacheWriteSamples(QueryClient client, String id, Task task) {
  client.getQueryData<List<Task>>(tasksKey);
  client.setQueryData<Task>(taskKey(id), task);
  client.updateQueryData<Task>(
    taskKey(id),
    (previous) => previous?.copyWith(name: 'Renamed'),
  );
  client.updateQueriesData<Task>(
    (previous) => previous?.copyWith(name: 'Renamed'),
    filters: QueryFilters(queryKey: tasksKey),
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
    QueryKey(<Object?>['tasks']),
    QueryDefaults(queryFn: (context) => api.listTasks()),
  );

  return client;
}

// ---------------------------------------------------------------------------
// guides/collections-and-side-effects.md
// ---------------------------------------------------------------------------

Widget queriesBuilderSample(List<String> visibleIds) =>
    QueriesBuilder<Task, String>(
      queries: <QuerySelectOptions<Task, String>>[
        for (final id in visibleIds)
          QuerySelectOptions<Task, String>(
            queryKey: taskKey(id),
            queryFn: (context) => api.getTask(id, signal: context.signal),
            select: (task) => task.name,
          ),
      ],
      builder: (context, results) => Column(
        children: <Widget>[
          for (final result in results) Text(result.dataOrNull ?? '…'),
        ],
      ),
    );

Widget queryListenerSample(QueryController<Task, Task> task) =>
    QueryListener<Task, Task>(
      controller: task,
      listenWhen: (previous, next) => previous.errorOrNull != next.errorOrNull,
      listener: (context, result) => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task unreachable')),
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
  final observer = client.observe<Task, Task>(
    QueryObserverOptions<Task>(
      queryKey: taskKey(id),
      queryFn: (context) => api.getTask(id, signal: context.signal),
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

class TaskCard extends StatelessWidget {
  const TaskCard(this.task, {super.key});

  final Task task;

  @override
  Widget build(BuildContext context) => Card(child: Text(task.name));
}

class TaskTile extends StatelessWidget {
  const TaskTile(this.task, {super.key});

  final Task task;

  @override
  Widget build(BuildContext context) => ListTile(title: Text(task.name));
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.error, this.staleData, {super.key});

  final Object error;
  final Task? staleData;

  @override
  Widget build(BuildContext context) => Text('$error');
}
