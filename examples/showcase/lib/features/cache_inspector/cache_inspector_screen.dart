/// Port-specific: TanStack's devtools are a separate package (`@tanstack/
/// query-devtools`) and are not ported, so this screen stands in for them —
/// the app's whole cache, live, plus the traffic to make something happen in
/// it.
///
/// It is the one screen built on none of the four call styles. It subscribes
/// to `client.queryCache` and `client.mutationCache` directly, which is what a
/// devtools panel does: no observer, no result, just the sealed
/// `QueryCacheEvent` and `MutationCacheEvent` streams and whatever the caches
/// hold when the frame is built.
///
/// Two events are deliberately watched and never logged, because both are
/// about the *readers* rather than the cache. `QueryObserverOptionsUpdated`
/// fires once per rebuild of every reader — options are re-applied on every
/// build and an inline `queryFn` closure is never equal to the last one — so a
/// log that included it would grow forever with nobody touching the screen,
/// and since this screen rebuilds on cache events it would feed itself.
/// `QueryObserverResultsUpdated` is one line per observer per delivery: it
/// says what the UI saw, not what the cache holds. Both are dropped where the
/// events are named, and neither rebuilds the screen either.
///
/// Proofs (widget tests in `test/features/cache_inspector_test.dart`,
/// end-to-end in `e2e/tests/cache_inspector.spec.ts`): loading posts with the
/// readers mounted logs `QueryAdded`, `QueryObserverAdded`, a fetch and a
/// success in that order and leaves a `["posts"]` row with one observer;
/// invalidating a row makes it stale and refetches it, and so does `Refetch`,
/// both bumping `updates`; `Remove` drops the row and logs `QueryRemoved`;
/// dropping the readers takes `observers` to zero and the entry is collected
/// five seconds later; the missing post lands as `status=error`; a todo shows
/// up in the mutations table going `pending` then `success`; and leaving the
/// screen unsubscribes without leaving a timer or an exception behind.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';
import '../../shared/theme.dart';

const Feature cacheInspectorFeature = Feature(
  id: 'cache-inspector',
  title: 'Cache inspector',
  summary: 'Every entry and every event, live.',
);

/// Short enough that a collection is something a reader can sit and watch —
/// five minutes, the default, is not.
const GcTime inspectorGcTime = GcTime.duration(Duration(seconds: 5));

/// What the mounted readers ask for. Long enough that `isStale` in the table
/// means something: with the default zero every entry would read
/// `isStale=true` the instant its data arrived, and an invalidation would
/// change nothing visible.
const StaleTime readerStaleTime = StaleTime.duration(Duration(minutes: 1));

/// The post that does not exist, so its fetch is a sure 404.
const int missingPostId = 999;

/// The key the todo-creating mutation is tagged with, so the log can name it
/// the way it names a query.
QueryKey get addTodoKey => QueryKey(const <Object?>['todos', 'create']);

/// The three entries this screen generates, one options function per key.
///
/// The stale time is the caller's: a mounted reader asks for
/// [readerStaleTime], while a `Load` button asks for zero so that
/// `QueryClient.query` always fetches instead of deciding the cached data is
/// still fresh.
QueryObserverOptions<List<Post>, List<Post>> inspectorPostsQuery(
  ShowcaseApi api, {
  required StaleTime staleTime,
}) =>
    QueryObserverOptions<List<Post>, List<Post>>(
      queryKey: ShowcaseKeys.posts,
      queryFn: (context) => api.posts(signal: context.signal),
      staleTime: staleTime,
      gcTime: inspectorGcTime,
    );

QueryObserverOptions<List<Todo>, List<Todo>> inspectorTodosQuery(
  ShowcaseApi api, {
  required StaleTime staleTime,
}) =>
    QueryObserverOptions<List<Todo>, List<Todo>>(
      queryKey: ShowcaseKeys.todos,
      queryFn: (context) => api.todos(signal: context.signal),
      staleTime: staleTime,
      gcTime: inspectorGcTime,
    );

/// Post 999. No retries: the point is to watch an error land in the cache,
/// and a reader counting requests should see exactly one.
QueryObserverOptions<Post, Post> inspectorMissingPostQuery(
  ShowcaseApi api, {
  required StaleTime staleTime,
}) =>
    QueryObserverOptions<Post, Post>(
      queryKey: ShowcaseKeys.post(missingPostId),
      queryFn: (context) => api.post(missingPostId, signal: context.signal),
      staleTime: staleTime,
      gcTime: inspectorGcTime,
      retry: RetryPolicy.never,
    );

MutationOptions<Todo, String, void> addTodoMutation(ShowcaseApi api) =>
    MutationOptions.simple<Todo, String>(
      mutationKey: addTodoKey,
      mutationFn: (text) => api.createTodo(text),
      gcTime: inspectorGcTime,
    );

class CacheInspectorScreen extends StatefulWidget {
  const CacheInspectorScreen({super.key});

  @override
  State<CacheInspectorScreen> createState() => _CacheInspectorScreenState();
}

class _CacheInspectorScreenState extends State<CacheInspectorScreen> {
  /// The log keeps the last of these, newest last. A devtools log is a tail,
  /// not a transcript.
  static const int logLimit = 30;

  final List<String> _log = <String>[];
  bool _keepReaders = false;
  bool _rebuildScheduled = false;
  bool _wired = false;
  int _todoSerial = 0;

  late final ShowcaseApi _api;
  late final QueryClient _client;
  void Function()? _unsubscribeQueries;
  void Function()? _unsubscribeMutations;

  /// The observer behind `Add a todo`, built on the first press. A
  /// `MutationObserver` rather than one of the widget call styles: this screen
  /// watches the cache, and a mutation that appears in the table has to come
  /// from somewhere that is not a builder.
  MutationObserver<Todo, String, void>? _addTodo;

  /// Both subscriptions are opened here rather than in `initState`: the client
  /// and the api are inherited widgets, and `initState` may not look one up.
  /// The guard makes this run exactly once per mount, which is what
  /// `initState` would have given.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) {
      return;
    }
    _wired = true;
    _api = ShowcaseScope.apiOf(context);
    _client = QueryClientProvider.of(context);
    _unsubscribeQueries = _client.queryCache.subscribe(_onQueryEvent);
    _unsubscribeMutations = _client.mutationCache.subscribe(_onMutationEvent);
  }

  @override
  void dispose() {
    _unsubscribeQueries?.call();
    _unsubscribeMutations?.call();
    // The observer outlives the widget otherwise: a mutation whose only
    // observer is never removed can never be collected.
    _addTodo?.destroy();
    super.dispose();
  }

  // --- the two subscriptions -------------------------------------------

  void _onQueryEvent(QueryCacheEvent event) {
    final name = switch (event) {
      QueryAdded() => 'QueryAdded',
      QueryRemoved() => 'QueryRemoved',
      QueryUpdated(:final action) =>
        'QueryUpdated(${_queryActionName(action)})',
      QueryObserverAdded() => 'QueryObserverAdded',
      QueryObserverRemoved() => 'QueryObserverRemoved',
      QueryObserverOptionsUpdated() || QueryObserverResultsUpdated() => null,
    };
    if (name == null) {
      return;
    }
    _append('$name ${event.query.queryKey.debugString}');
  }

  void _onMutationEvent(MutationCacheEvent event) {
    final name = switch (event) {
      MutationAdded() => 'MutationAdded',
      MutationRemoved() => 'MutationRemoved',
      MutationUpdated(:final action) =>
        'MutationUpdated(${_mutationActionName(action)})',
      MutationObserverAdded() => 'MutationObserverAdded',
      MutationObserverRemoved() => 'MutationObserverRemoved',
      MutationObserverOptionsUpdated() => null,
    };
    if (name == null) {
      return;
    }
    final key = event.mutation.options.mutationKey;
    _append('$name ${key == null ? '(no key)' : key.debugString}');
  }

  /// The action's own name, spelled out rather than taken from
  /// `runtimeType`: the two generic actions would otherwise print their type
  /// argument, which differs per key and per compiler.
  static String _queryActionName(QueryAction action) => switch (action) {
        QueryFetchAction() => 'QueryFetchAction',
        QueryFailedAction() => 'QueryFailedAction',
        QuerySuccessAction<Object?>() => 'QuerySuccessAction',
        QueryErrorAction() => 'QueryErrorAction',
        QueryPauseAction() => 'QueryPauseAction',
        QueryContinueAction() => 'QueryContinueAction',
        QueryInvalidateAction() => 'QueryInvalidateAction',
        QuerySetStateAction<Object?>() => 'QuerySetStateAction',
      };

  static String _mutationActionName(MutationAction action) => switch (action) {
        MutationPendingAction() => 'MutationPendingAction',
        MutationSuccessAction() => 'MutationSuccessAction',
        MutationErrorAction() => 'MutationErrorAction',
        MutationFailedAction() => 'MutationFailedAction',
        MutationPauseAction() => 'MutationPauseAction',
        MutationContinueAction() => 'MutationContinueAction',
      };

  void _append(String line) {
    _log.add(line);
    if (_log.length > logLimit) {
      _log.removeRange(0, _log.length - logLimit);
    }
    _rebuild();
  }

  /// Cache events arrive from wherever the change happened — a resolved
  /// future, a microtask, a sibling's build. Inside a frame's build phase a
  /// rebuild has to wait for the frame to end; anywhere else it can go
  /// straight in. Copied from `QueryDebugStrip`, which has the same problem.
  void _rebuild() {
    if (!mounted || _rebuildScheduled) {
      return;
    }
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      _rebuildScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _rebuildScheduled = false;
        if (mounted) {
          setState(() {});
        }
      });
    } else {
      setState(() {});
    }
  }

  // --- the traffic generators ------------------------------------------

  /// The imperative read: no observer, no refetch triggers, and nobody
  /// waiting on the future — a refused one (the missing post) is meant to
  /// land in the cache as an error, not to be thrown at the widget tree.
  void _load<T>(QueryObserverOptions<T, T> options) =>
      _client.query<T>(options).ignore();

  void _addATodo() {
    _todoSerial += 1;
    final observer = _addTodo ??=
        MutationObserver<Todo, String, void>(_client, addTodoMutation(_api));
    observer.mutate('Inspected #$_todoSerial');
  }

  /// `refetchType: RefetchType.all`, not the default `active`: most rows here
  /// have no observer at all, and an invalidation that only marks them would
  /// never show the fetch the button promises.
  void _invalidate(Query<Object?> query) => _client
      .invalidateQueries(
        filters: QueryFilters(queryKey: query.queryKey, exact: true),
        refetchType: RefetchType.all,
      )
      .ignore();

  void _refetch(Query<Object?> query) => _client
      .refetchQueries(
        filters: QueryFilters(queryKey: query.queryKey, exact: true),
      )
      .ignore();

  void _remove(Query<Object?> query) => _client.removeQueries(
        filters: QueryFilters(queryKey: query.queryKey, exact: true),
      );

  @override
  Widget build(BuildContext context) {
    final queries = _client.queryCache.queries;
    final mutations = _client.mutationCache.mutations;

    return FeatureScaffold(
      feature: cacheInspectorFeature,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Notice(
            'Built on none of the four call styles: this screen subscribes to '
            'client.queryCache and client.mutationCache directly, the way '
            'devtools do, and reads whatever the caches hold when the frame '
            'is built. Everything it generates carries gcTime 5 s, so an '
            'entry nobody reads is collected five seconds after its last '
            'fetch settles.',
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Notice(
            'Two events are watched and never logged, because both are about '
            'the readers rather than the cache. QueryObserverOptionsUpdated '
            'fires once per rebuild of every reader — options are re-applied '
            'on every build and an inline queryFn closure is never equal — so '
            'logging it would grow the log with nobody touching the screen, '
            'and this screen rebuilds on cache events, so it would feed '
            'itself. QueryObserverResultsUpdated is one line per observer per '
            'delivery: what the UI saw, not what the cache holds.',
          ),
        ),
        SectionCard(
          title: 'Traffic',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Semantics(
                container: true,
                explicitChildNodes: true,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: <Widget>[
                    _Action(
                      label: 'Load posts',
                      onPressed: () => _load<List<Post>>(
                        inspectorPostsQuery(_api, staleTime: StaleTime.zero),
                      ),
                    ),
                    _Action(
                      label: 'Load todos',
                      onPressed: () => _load<List<Todo>>(
                        inspectorTodosQuery(_api, staleTime: StaleTime.zero),
                      ),
                    ),
                    _Action(
                      label: 'Load a missing post',
                      onPressed: () => _load<Post>(
                        inspectorMissingPostQuery(
                          _api,
                          staleTime: StaleTime.zero,
                        ),
                      ),
                    ),
                    _Action(label: 'Add a todo', onPressed: _addATodo),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep readers'),
                value: _keepReaders,
                onChanged: (value) => setState(() => _keepReaders = value),
              ),
              const Text(
                'Mounts a QueryBuilder on each of the three keys, so the '
                'table shows observers and an entry is pinned against '
                'collection. The readers ask for a one-minute stale time, so '
                'isStale says something other than "always". With a reader '
                'mounted, Remove is undone at once: the observer rebuilds and '
                'builds the entry again.',
              ),
              if (_keepReaders) ...<Widget>[
                const SizedBox(height: 8),
                _Reader<List<Post>>(
                  options: inspectorPostsQuery(
                    _api,
                    staleTime: readerStaleTime,
                  ),
                  describe: (data) => '${data.length} posts',
                ),
                _Reader<List<Todo>>(
                  options: inspectorTodosQuery(
                    _api,
                    staleTime: readerStaleTime,
                  ),
                  describe: (data) => '${data.length} todos',
                ),
                _Reader<Post>(
                  options: inspectorMissingPostQuery(
                    _api,
                    staleTime: readerStaleTime,
                  ),
                  describe: (data) => data.title,
                ),
              ],
            ],
          ),
        ),
        SectionCard(
          title: 'Entries',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('entries=${queries.length}'),
              const SizedBox(height: 8),
              if (queries.isEmpty)
                const Text('The query cache is empty.')
              else
                for (final query in queries)
                  _EntryRow(
                    query: query,
                    onRefetch: () => _refetch(query),
                    onInvalidate: () => _invalidate(query),
                    onRemove: () => _remove(query),
                  ),
            ],
          ),
        ),
        SectionCard(
          title: 'Mutations',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('mutations=${mutations.length}'),
              const SizedBox(height: 8),
              if (mutations.isEmpty)
                const Text('The mutation cache is empty.')
              else
                for (final mutation in mutations)
                  _MutationRow(mutation: mutation),
            ],
          ),
        ),
        SectionCard(
          title: 'Event log',
          trailing: IconButton(
            tooltip: 'Clear log',
            onPressed: _log.isEmpty ? null : () => setState(_log.clear),
            icon: const Icon(Icons.delete_outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('log=${_log.length}'),
              const SizedBox(height: 4),
              // Its own semantics group, like a debug strip: a test finds the
              // group and each line as an exact text inside it.
              Semantics(
                container: true,
                explicitChildNodes: true,
                label: 'event log',
                child: Column(
                  key: const ValueKey<String>('event-log'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (_log.isEmpty)
                      const Text('Nothing yet.')
                    else
                      for (final line in _log) Text(line, style: _mono),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

const TextStyle _mono = TextStyle(fontFamily: 'monospace', fontSize: 12);

/// `null` reads as `never` rather than as a blank: a test asserts on it.
String _clock(DateTime? at) {
  if (at == null) {
    return 'never';
  }
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

/// One of the traffic buttons. The visible label is the accessible name; the
/// tooltip is for a pointer only, which is why it is excluded from semantics.
class _Action extends StatelessWidget {
  const _Action({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: FilledButton.tonal(
          onPressed: onPressed,
          child: Text(label),
        ),
      );
}

/// A mounted reader: it holds an observer on its key and shows what the entry
/// currently is. Nothing here drives the table — the table reads the cache.
class _Reader<T> extends StatelessWidget {
  const _Reader({required this.options, required this.describe});

  final QueryObserverOptions<T, T> options;
  final String Function(T data) describe;

  @override
  Widget build(BuildContext context) => QueryBuilder<T>(
        options: options,
        builder: (context, result) => Text(
          'reader ${options.queryKey.debugString}=${switch (result) {
            QueryPending() => 'pending',
            QueryError(:final error) => 'error: $error',
            QuerySuccess(:final data) => describe(data),
          }}',
          style: _mono,
        ),
      );
}

/// One row of the entries table: the key, its facts as texts of their own,
/// and the three buttons that act on it.
///
/// A named semantics group per row, and a widget key to match, so a test can
/// ask for one row's `status=` and not another's — two rows carry the same
/// fact names, and unscoped they would collide.
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.query,
    required this.onRefetch,
    required this.onInvalidate,
    required this.onRemove,
  });

  final Query<Object?> query;
  final VoidCallback onRefetch;
  final VoidCallback onInvalidate;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final key = query.queryKey.debugString;
    final state = query.state;
    final facts = <String>[
      'status=${state.status.name}',
      'fetchStatus=${state.fetchStatus.name}',
      'isStale=${query.isStale()}',
      'observers=${query.observersCount}',
      'updates=${state.dataUpdateCount}',
      'dataUpdatedAt=${_clock(state.dataUpdatedAt)}',
    ];

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'entry $key',
      child: Padding(
        key: ValueKey<String>('entry-$key'),
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(key, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 2,
              children: <Widget>[
                for (final fact in facts) Text(fact, style: _mono),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                TextButton(onPressed: onRefetch, child: Text('Refetch $key')),
                TextButton(
                  onPressed: onInvalidate,
                  child: Text('Invalidate $key'),
                ),
                TextButton(onPressed: onRemove, child: Text('Remove $key')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the mutations table. Mutations are never shared by key, so the
/// row is named by the cache's own `mutationId`.
class _MutationRow extends StatelessWidget {
  const _MutationRow({required this.mutation});

  final Mutation<Object?, Object?, Object?> mutation;

  @override
  Widget build(BuildContext context) {
    final state = mutation.state;
    final key = mutation.options.mutationKey;
    final facts = <String>[
      'status=${state.status.name}',
      'isPaused=${state.isPaused}',
      'failureCount=${state.failureCount}',
    ];

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'mutation #${mutation.mutationId}',
      child: Padding(
        key: ValueKey<String>('mutation-${mutation.mutationId}'),
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '#${mutation.mutationId} ${key == null ? '(no key)' : key.debugString}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 2,
              children: <Widget>[
                for (final fact in facts) Text(fact, style: _mono),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
