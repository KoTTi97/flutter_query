/// Port-specific: the cache-wide callbacks a `QueryCache` and a
/// `MutationCache` take in their constructors — upstream's `QueryCacheConfig`
/// and `MutationCacheConfig` — and `meta`, on its way from the options to the
/// query function (`context.meta`) and to those callbacks (`query.meta`).
///
/// The callbacks are constructor arguments, so a cache that has them has to
/// be built with them: this screen runs on a `QueryClient` of its own, wrapped
/// in a nested `QueryClientProvider`, and the debug strips under it read that
/// client. A log panel shows every callback as one line. The query side has
/// no per-query `onSuccess`/`onError` — upstream removed those in v5, and the
/// cache-level ones are what replaced them — so the log is the whole story
/// for queries; the mutation side has both, and the log shows the cache's
/// running first (`mutation success` before `option onSuccess`), which is the
/// order the core runs them in.
///
/// Two of upstream's `meta` idioms are here. `Fetch a missing post` asks for
/// post 999 with `meta: {'toast': true}`, and the cache's `onError` reads
/// `query.meta` to decide whether the failure deserves a `SnackBar` — the
/// "meta drives global error handling" pattern from the `QueryCache` docs.
/// `Fetch with meta tag` runs a query function that reads `context.meta` and
/// echoes it into its data, which is upstream's "additional information about
/// your query" reaching the function.
///
/// Proofs (widget tests in `test/features/global_callbacks_test.dart`,
/// end-to-end in `e2e/tests/global_callbacks.spec.ts`): loading the screen
/// logs `query success posts` and then `query settled posts`; the missing
/// post logs `query error post-999 (meta: toast)` and shows the `SnackBar`
/// `Post not found`; the meta query shows `meta seen=showcase`; a created
/// todo logs `mutation mutate`, `mutation success`, `option onSuccess`,
/// `mutation settled`, `option onSettled` in that order, and a refused one
/// logs `mutation error (Requested: 500)`; leaving the screen disposes its
/// client, and the app's client never held any of these entries.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/cache_listener.dart';
import '../../shared/debug_strip.dart';
import '../../shared/fact_group.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';
import '../../shared/theme.dart';

const Feature globalCallbacksFeature = Feature(
  id: 'global-callbacks',
  title: 'Global callbacks',
  summary: 'Cache-level callbacks, and meta on its way through.',
);

/// The post that does not exist, so its fetch is a sure error.
const int missingPostId = 999;

/// The key of the query that proves `meta` reaches the query function. Owned
/// by this screen alone, so it lives here rather than in `ShowcaseKeys`.
QueryKey get metaKey => QueryKey(const <Object?>['meta']);

QueryObserverOptions<List<Post>> postsQuery(ShowcaseApi api) =>
    QueryObserverOptions<List<Post>>(
      queryKey: ShowcaseKeys.posts,
      queryFn: (context) => api.posts(signal: context.signal),
    );

/// Post 999, tagged for the cache's `onError`. No retries: the point is the
/// error, and a reader counting requests should see one. Disabled until
/// [wanted], so the entry sits idle in the cache until the button.
QueryObserverOptions<Post> missingPostQuery(
  ShowcaseApi api, {
  required bool wanted,
}) =>
    QueryObserverOptions<Post>(
      queryKey: ShowcaseKeys.post(missingPostId),
      queryFn: (context) => api.post(missingPostId, signal: context.signal),
      enabled: wanted ? Enabled.yes : Enabled.no,
      retry: RetryPolicy.never,
      // A const map: options carry value equality, and a fresh map every
      // build would count as a change on every rebuild.
      meta: const <String, Object?>{'toast': true},
    );

/// What the meta query hands back: the tag it found in `context.meta`, next
/// to the serial the backend answered with, so the fetch is a real one.
class MetaEcho {
  const MetaEcho({required this.tag, required this.serial});

  final String tag;
  final int serial;
}

QueryObserverOptions<MetaEcho> metaQuery(
  ShowcaseApi api, {
  required bool wanted,
}) =>
    QueryObserverOptions<MetaEcho>(
      queryKey: metaKey,
      queryFn: (context) async {
        final meta = context.meta as Map<String, Object?>?;
        final time = await api.time(signal: context.signal);
        return MetaEcho(tag: '${meta?['tag']}', serial: time.serial);
      },
      enabled: wanted ? Enabled.yes : Enabled.no,
      meta: const <String, Object?>{'tag': 'showcase'},
    );

/// One `mutate` call's input: the todo's text and whether the backend should
/// refuse it. One mutation serves both buttons.
typedef CreateTodoInput = ({String text, bool fail});

/// The mutation's own callbacks log with an `option` prefix, so the log
/// shows where they land relative to the cache's.
MutationOptions<Todo, CreateTodoInput, void> createTodoMutation(
  ShowcaseApi api, {
  required void Function(String line) log,
}) =>
    MutationOptions.simple<Todo, CreateTodoInput>(
      mutationFn: (input) =>
          api.createTodo(input.text, fail: input.fail ? 500 : null),
      onSuccess: (_, __, ___) => log('option onSuccess'),
      onError: (_, __, ___, ____) => log('option onError'),
      onSettled: (_, __, ___, ____, _____) => log('option onSettled'),
    );

class GlobalCallbacksScreen extends StatefulWidget {
  const GlobalCallbacksScreen({super.key});

  @override
  State<GlobalCallbacksScreen> createState() => _GlobalCallbacksScreenState();
}

class _GlobalCallbacksScreenState extends State<GlobalCallbacksScreen>
    with PhaseSafeRebuild<GlobalCallbacksScreen> {
  final List<String> _log = <String>[];
  bool _missingWanted = false;
  bool _metaWanted = false;

  /// The screen's own client, built with both caches configured. The app's
  /// client cannot be given callbacks after the fact — they are constructor
  /// arguments of the caches — and the app's must stay callback-free for the
  /// other screens.
  late final QueryClient _client = QueryClient(
    queryCache: QueryCache(
      onSuccess: _onQuerySuccess,
      onError: _onQueryError,
      onSettled: _onQuerySettled,
    ),
    mutationCache: MutationCache(
      onMutate: _onMutationMutate,
      onSuccess: _onMutationSuccess,
      onError: _onMutationError,
      onSettled: _onMutationSettled,
    ),
  );
  late final void Function() _unsubscribeQueries;
  late final void Function() _unsubscribeMutations;

  @override
  void initState() {
    super.initState();
    // The strips rebuild on the *app's* cache events (through `CacheStats`),
    // which this client never emits; this screen stands in for that listener
    // so the strips under it stay live. Only the events that change what a
    // strip shows: a rebuild re-applies every builder's options, and the
    // options-updated event that follows would rebuild again, for good.
    _unsubscribeQueries = _client.queryCache.subscribe((event) {
      if (event is QueryUpdated ||
          event is QueryAdded ||
          event is QueryRemoved ||
          event is QueryObserverAdded ||
          event is QueryObserverRemoved) {
        scheduleRebuild();
      }
    });
    _unsubscribeMutations = _client.mutationCache.subscribe((event) {
      if (event is MutationUpdated ||
          event is MutationAdded ||
          event is MutationRemoved) {
        scheduleRebuild();
      }
    });
  }

  @override
  void dispose() {
    _unsubscribeQueries();
    _unsubscribeMutations();
    // The nested provider unmounted the client when it went; what is left is
    // the cache itself, with its `gcTime` timers. `clear` is the whole of a
    // client's teardown — there is nothing else to release.
    _client.clear();
    super.dispose();
  }

  // --- the query cache's callbacks -------------------------------------

  static String _labelOf(QueryKey key) {
    if (key == ShowcaseKeys.posts) {
      return 'posts';
    }
    if (key == ShowcaseKeys.post(missingPostId)) {
      return 'post-$missingPostId';
    }
    if (key == metaKey) {
      return 'meta';
    }
    return key.debugString;
  }

  void _onQuerySuccess(Object? data, Query<Object?> query) =>
      _append('query success ${_labelOf(query.queryKey)}');

  /// Upstream's idiom: a global error handler that looks at `query.meta` to
  /// decide what the failure deserves. Here `toast` means a `SnackBar`.
  void _onQueryError(Object error, StackTrace _, Query<Object?> query) {
    final meta = query.meta;
    final toast = meta is Map<String, Object?> && meta['toast'] == true;
    _append(
      'query error ${_labelOf(query.queryKey)}${toast ? ' (meta: toast)' : ''}',
    );
    if (toast && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error'),
          // Long enough for a test to read it; a reader dismisses it.
          duration: const Duration(seconds: 30),
        ),
      );
    }
  }

  void _onQuerySettled(
    Object? data,
    Object? error,
    StackTrace? _,
    Query<Object?> query,
  ) =>
      _append('query settled ${_labelOf(query.queryKey)}');

  // --- the mutation cache's callbacks ----------------------------------

  FutureOr<void> _onMutationMutate(
    Object? variables,
    Mutation<Object?, Object?, Object?> mutation,
  ) {
    _append('mutation mutate');
  }

  FutureOr<void> _onMutationSuccess(
    Object? data,
    Object? variables,
    Object? onMutateResult,
    Mutation<Object?, Object?, Object?> mutation,
  ) {
    _append('mutation success');
  }

  FutureOr<void> _onMutationError(
    Object error,
    StackTrace stackTrace,
    Object? variables,
    Object? onMutateResult,
    Mutation<Object?, Object?, Object?> mutation,
  ) {
    _append('mutation error ($error)');
  }

  FutureOr<void> _onMutationSettled(
    Object? data,
    Object? error,
    StackTrace? stackTrace,
    Object? variables,
    Object? onMutateResult,
    Mutation<Object?, Object?, Object?> mutation,
  ) {
    _append('mutation settled');
  }

  // --- the log ---------------------------------------------------------

  void _append(String line) {
    _log.add(line);
    scheduleRebuild();
  }

  @override
  Widget build(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    // Everything below — the builders, the mutation, the strips — reads the
    // nearest provider, and that is this one. The app's lifecycle is left to
    // the app's provider: two focus listeners on one app would refetch twice.
    return QueryClientProvider(
      client: _client,
      observeAppLifecycle: false,
      child: FeatureScaffold(
        feature: globalCallbacksFeature,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Notice(
              'This screen runs on a QueryClient of its own, because the '
              'callbacks are constructor arguments of its caches. The strips '
              'below read that client; their fetches counter is the app '
              "client's and is not tracked for a nested one.",
            ),
          ),
          SectionCard(
            title: 'Queries',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                QueryBuilder<List<Post>>(
                  options: postsQuery(api),
                  builder: (context, posts) => switch (posts) {
                    QueryPending() => const Text('posts=loading'),
                    QueryError(:final error) => Notice('$error', error: true),
                    QuerySuccess(:final data) => Text('posts=${data.length}'),
                  },
                ),
                const SizedBox(height: 12),
                QueryBuilder<Post>(
                  options: missingPostQuery(api, wanted: _missingWanted),
                  builder: (context, result) => _QueryRow(
                    label: 'Fetch a missing post',
                    fetching: result.isFetching,
                    onPressed: () {
                      if (_missingWanted) {
                        result.refetch();
                      } else {
                        setState(() => _missingWanted = true);
                      }
                    },
                    child: Text(switch (result) {
                      QueryPending() => result.isFetching
                          ? 'missing=fetching'
                          : 'missing=not fetched yet',
                      QueryError(:final error) => 'missing=error: $error',
                      QuerySuccess(:final data) => 'missing=${data.title}',
                    }),
                  ),
                ),
                const SizedBox(height: 12),
                QueryBuilder<MetaEcho>(
                  options: metaQuery(api, wanted: _metaWanted),
                  builder: (context, result) => _QueryRow(
                    label: 'Fetch with meta tag',
                    fetching: result.isFetching,
                    onPressed: () {
                      if (_metaWanted) {
                        result.refetch();
                      } else {
                        setState(() => _metaWanted = true);
                      }
                    },
                    child: switch (result) {
                      QueryPending() => Text(result.isFetching
                          ? 'meta seen=fetching'
                          : 'meta seen=not fetched yet'),
                      QueryError(:final error) =>
                        Text('meta seen=error: $error'),
                      QuerySuccess(:final data) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('meta seen=${data.tag}'),
                            Text('serial=${data.serial}'),
                          ],
                        ),
                    },
                  ),
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'Mutations',
            child: _MutationsCard(api: api, log: _append),
          ),
          QueryDebugStrip(queryKey: ShowcaseKeys.posts, label: 'posts'),
          QueryDebugStrip(
            queryKey: ShowcaseKeys.post(missingPostId),
            label: 'post-$missingPostId',
          ),
          QueryDebugStrip(queryKey: metaKey, label: 'meta'),
          SectionCard(
            title: 'Callback log',
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
                // Its own semantics group, like a strip: a test finds the
                // group and each line as an exact text inside it.
                SemanticsGroup(
                  name: 'callback log',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (final line in _log)
                        Text(
                          line,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A button next to what its query shows. The button's label is its
/// accessible name; the tooltip is for a pointer only.
class _QueryRow extends StatelessWidget {
  const _QueryRow({
    required this.label,
    required this.fetching,
    required this.onPressed,
    required this.child,
  });

  final String label;
  final bool fetching;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => SemanticsGroup(
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Tooltip(
              message: label,
              excludeFromSemantics: true,
              child: FilledButton.tonal(
                onPressed: fetching ? null : onPressed,
                child: Text(label),
              ),
            ),
            if (fetching) const Pill('fetching'),
            child,
          ],
        ),
      );
}

/// Its own widget so `context.mutation` reads the nested provider's client:
/// the screen's own `context` sits above that provider.
class _MutationsCard extends StatelessWidget {
  const _MutationsCard({required this.api, required this.log});

  final ShowcaseApi api;
  final void Function(String line) log;

  @override
  Widget build(BuildContext context) {
    final create = context.mutation(createTodoMutation(api, log: log));
    final pending = create.value.isPending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SemanticsGroup(
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Tooltip(
                message: 'Create todo',
                excludeFromSemantics: true,
                child: FilledButton.tonal(
                  onPressed: pending
                      ? null
                      : () => create.mutate(
                            (text: 'From the callbacks screen', fail: false),
                          ),
                  child: const Text('Create todo'),
                ),
              ),
              Tooltip(
                message: 'Create failing todo',
                excludeFromSemantics: true,
                child: FilledButton.tonal(
                  onPressed: pending
                      ? null
                      : () => create.mutate(
                            (text: 'Refused by the backend', fail: true),
                          ),
                  child: const Text('Create failing todo'),
                ),
              ),
              if (pending) const Pill('pending'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(switch (create.value) {
          MutationIdle() => 'todo=idle',
          MutationPending() => 'todo=pending',
          MutationSuccess(:final data) => 'todo=#${data.id} ${data.text}',
          MutationError(:final error) => 'todo=error: $error',
        }),
      ],
    );
  }
}
