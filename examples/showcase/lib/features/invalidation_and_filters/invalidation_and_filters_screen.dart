/// Invalidation and the query filters: one small cache — the posts list,
/// post 1, post 2 and the todos, each with a live `QueryController` reader,
/// and post 3, filled once by `client.query(...)` with no reader at all — and
/// the client's bulk operations run over it with every kind of filter: a key
/// prefix, `exact`, `type`, `stale`, `predicate`. Port-specific; it
/// illustrates upstream's *Query Invalidation*, *Filters* and *Query Keys*
/// guides.
///
/// The readers are `QueryController`s created in `initState` and read through
/// `ListenableBuilder`. The posts have no stale time (the default, stale at
/// once), the todos thirty seconds, so `stale: true` tells them apart; post 2
/// never retries, so a scripted failure is an error at once and the predicate
/// has something to match.
///
/// Proofs (widget tests in `test/features/invalidation_and_filters_test.dart`,
/// end-to-end in `e2e/tests/invalidation_and_filters.spec.ts`): invalidating
/// the `posts` prefix refetches the list, post 1 and post 2 and only marks
/// the unobserved post 3 (`isStale=true`, no fetch), leaving the todos alone;
/// `exact: true` refetches the list alone; `RefetchType.all` refetches post 3
/// as well; `stale: true` refetches the posts and not the fresh todos, until
/// the todos age past their stale time; resetting post 1 puts it back to
/// pending and refetches it because it has a reader; removing post 2 leaves
/// its strip `status=absent` while its reader keeps the last result until it
/// re-resolves the key; cancelling a slow refetch of the list leaves the
/// entry idle with its old data and no answer ever lands; the errored
/// predicate refetches post 2 alone after a scripted failure; uppercasing
/// the titles matches the two active detail entries and is a cache write, not
/// a fetch.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/debug_strip.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';
import '../../shared/theme.dart';

const Feature invalidationAndFiltersFeature = Feature(
  id: 'invalidation-and-filters',
  title: 'Invalidation and filters',
  summary:
      'Invalidate, refetch, reset and remove, by prefix, type or predicate.',
);

/// How long the todos stay fresh; the posts use the default and are stale
/// the moment they arrive.
const StaleTime todosStaleTime = StaleTime.duration(Duration(seconds: 30));

/// The list. [nextDelay] is asked on every fetch, so the screen can make one
/// fetch slow enough to cancel without changing the options.
QueryObserverOptions<List<Post>> postsQuery(
  ShowcaseApi api, {
  Duration? Function()? nextDelay,
}) =>
    QueryObserverOptions<List<Post>>(
      queryKey: ShowcaseKeys.posts,
      queryFn: (context) =>
          api.posts(signal: context.signal, delay: nextDelay?.call()),
    );

/// One post. [prepare] runs before each request — how the screen scripts the
/// backend's next answer for post 2 — and [retry] is what post 2 sets to
/// `never`, so that answer is an error at once.
QueryObserverOptions<Post> postQuery(
  ShowcaseApi api,
  int id, {
  RetryPolicy? retry,
  Future<void> Function()? prepare,
}) =>
    QueryObserverOptions<Post>(
      queryKey: ShowcaseKeys.post(id),
      queryFn: (context) async {
        await prepare?.call();
        return api.post(id, signal: context.signal);
      },
      retry: retry,
    );

/// The todos, fresh for [todosStaleTime].
QueryObserverOptions<List<Todo>> todosQuery(ShowcaseApi api) =>
    QueryObserverOptions<List<Todo>>(
      queryKey: ShowcaseKeys.todos,
      queryFn: (context) => api.todos(signal: context.signal),
      staleTime: todosStaleTime,
    );

class InvalidationAndFiltersScreen extends StatefulWidget {
  const InvalidationAndFiltersScreen({super.key});

  @override
  State<InvalidationAndFiltersScreen> createState() =>
      _InvalidationAndFiltersScreenState();
}

class _InvalidationAndFiltersScreenState
    extends State<InvalidationAndFiltersScreen> {
  static const Duration _slowDelay = Duration(seconds: 2);

  late final ShowcaseApi _api;
  late final QueryClient _client;
  late final QueryController<List<Post>, List<Post>> _posts;
  late final QueryController<Post, Post> _post1;
  late final QueryController<Post, Post> _post2;
  late final QueryController<List<Todo>, List<Todo>> _todos;

  /// Consumed by the next fetch of the list.
  bool _slowNextPosts = false;

  /// Consumed by the next fetch of post 2.
  bool _failPost2Next = false;

  int? _matched;
  bool _rebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    // Neither lookup subscribes: the api and the client are fixed for the
    // life of the app, and a subscribing lookup is not allowed here anyway.
    _api = context.getInheritedWidgetOfExactType<ShowcaseScope>()!.api;
    _client = QueryClientProvider.read(context);
    _posts = QueryController.create(
        _client, postsQuery(_api, nextDelay: _takeDelay));
    _post1 = QueryController.create(_client, postQuery(_api, 1));
    _post2 = QueryController.create(_client, _post2Options);
    _todos = QueryController.create(_client, todosQuery(_api));
    // Post 3 has no reader: fetched once, imperatively, it sits in the cache
    // as an inactive entry — what `type: inactive` and `RefetchType.all`
    // are about.
    _client.query(postQuery(_api, 3)).ignore();
  }

  @override
  void dispose() {
    _posts.dispose();
    _post1.dispose();
    _post2.dispose();
    _todos.dispose();
    super.dispose();
  }

  QueryObserverOptions<Post> get _post2Options => postQuery(
        _api,
        2,
        retry: RetryPolicy.never,
        prepare: _scriptPost2Failure,
      );

  Duration? _takeDelay() {
    if (!_slowNextPosts) {
      return null;
    }
    _slowNextPosts = false;
    return _slowDelay;
  }

  /// Ticked, the backend is told to refuse the next `GET /api/posts/2`
  /// before the request goes out; the tick is spent by that one fetch.
  Future<void> _scriptPost2Failure() async {
    if (!_failPost2Next) {
      return;
    }
    _failPost2Next = false;
    _rebuild();
    await _api.configureScenario(
      failNext: const <FailNext>[
        FailNext(method: 'GET', path: '/api/posts/2', status: 500),
      ],
    );
  }

  /// A fetch can start from anywhere — a tap, an invalidation, a sibling's
  /// first build. Inside a frame's build phase a rebuild has to wait for the
  /// frame to end; anywhere else it can go straight in.
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

  // --- invalidateQueries ---------------------------------------------------

  /// A prefix: every key starting with `['posts']` — the list and the three
  /// details. Only the active ones refetch; post 3 is merely marked.
  void _invalidatePrefix() => _client
      .invalidateQueries(filters: QueryFilters(queryKey: ShowcaseKeys.posts))
      .ignore();

  /// `exact`: the list alone.
  void _invalidateExactly() => _client
      .invalidateQueries(
        filters: QueryFilters(queryKey: ShowcaseKeys.posts, exact: true),
      )
      .ignore();

  /// The same prefix, and the inactive post 3 refetches as well.
  void _invalidateInactiveToo() => _client
      .invalidateQueries(
        filters: QueryFilters(queryKey: ShowcaseKeys.posts),
        refetchType: RefetchType.all,
      )
      .ignore();

  /// A predicate over the state: whatever is in error right now.
  void _invalidateErrored() => _client
      .invalidateQueries(
        filters: QueryFilters(
          predicate: (query) => query.state.status == QueryStatus.error,
        ),
      )
      .ignore();

  // --- refetchQueries, resetQueries, removeQueries -------------------------

  /// `stale: true` across the whole cache: the posts, never the todos while
  /// they are fresh — and not post 3, which nobody observes and which
  /// counts as fresh until it is invalidated.
  void _refetchStale() =>
      _client.refetchQueries(filters: const QueryFilters(stale: true)).ignore();

  void _resetPost1() => _client
      .resetQueries(
        filters: QueryFilters(queryKey: ShowcaseKeys.post(1), exact: true),
      )
      .ignore();

  void _removePost2() => _client.removeQueries(
        filters: QueryFilters(queryKey: ShowcaseKeys.post(2), exact: true),
      );

  /// A reader stays on the entry it was removed with; giving it its options
  /// again makes it resolve the key afresh, and the new entry fetches.
  void _reattachPost2() => _post2.setOptions(_post2Options);

  void _refetchPost2() => _post2.refetch().ignore();

  // --- cancelQueries -------------------------------------------------------

  void _refetchPostsSlowly() {
    _slowNextPosts = true;
    _posts.refetch().ignore();
  }

  void _cancelPosts() => _client
      .cancelQueries(
        filters: QueryFilters(queryKey: ShowcaseKeys.posts, exact: true),
      )
      .ignore();

  // --- getQueriesData, updateQueriesData -----------------------------------

  /// The two active details and nothing else: `updateQueriesData<Post>`
  /// type-checks every match before writing, and the list under the same
  /// prefix holds a `List<Post>`, so the key's shape (`['posts', id]`) picks
  /// the details and `type` leaves the unobserved post 3 out.
  static final QueryFilters _activeDetails = QueryFilters(
    queryKey: ShowcaseKeys.posts,
    type: QueryTypeFilter.active,
    predicate: (query) => query.queryKey.parts.length == 2,
  );

  void _uppercaseTitles() {
    final matched =
        _client.getQueriesData<Post>(filters: _activeDetails).length;
    _client.updateQueriesData<Post>(
      (previous) => previous == null
          ? null
          : Post(
              id: previous.id,
              title: previous.title.toUpperCase(),
              body: previous.body,
            ),
      filters: _activeDetails,
    );
    setState(() => _matched = matched);
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return FeatureScaffold(
      feature: invalidationAndFiltersFeature,
      children: <Widget>[
        SectionCard(
          title: 'Operations',
          // Explicit child nodes: a row folds every plain text inside it into
          // one label, and `matched=<n>` is read as an exact text.
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Group(
                  name: 'invalidateQueries',
                  children: <Widget>[
                    _Action('Invalidate posts prefix', _invalidatePrefix),
                    _Action('Invalidate posts exactly', _invalidateExactly),
                    _Action('Invalidate inactive too', _invalidateInactiveToo),
                    _Action('Predicate: errored', _invalidateErrored),
                  ],
                ),
                _Group(
                  name: 'refetchQueries · resetQueries · removeQueries',
                  children: <Widget>[
                    _Action('Refetch stale only', _refetchStale),
                    _Action('Reset post 1', _resetPost1),
                    _Action('Remove post 2', _removePost2),
                    _Action('Re-attach post 2', _reattachPost2),
                  ],
                ),
                _Group(
                  name: 'cancelQueries',
                  children: <Widget>[
                    _Action('Refetch posts slowly', _refetchPostsSlowly),
                    _Action('Cancel posts', _cancelPosts),
                  ],
                ),
                _Group(
                  name: 'getQueriesData · updateQueriesData',
                  children: <Widget>[
                    _Action('Uppercase all post titles', _uppercaseTitles),
                    Text(
                      'matched=${_matched ?? '–'}',
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ],
                ),
                // No subtitle: a tile folds it into the checkbox's accessible
                // name, and the tests find the box by its title alone.
                CheckboxListTile(
                  title: const Text('Fail post 2 next'),
                  contentPadding: EdgeInsets.zero,
                  value: _failPost2Next,
                  onChanged: (value) =>
                      setState(() => _failPost2Next = value ?? false),
                ),
                _Action('Refetch post 2', _refetchPost2),
              ],
            ),
          ),
        ),
        SectionCard(
          title: 'The cache',
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _ReaderRow<List<Post>>(
                  label: 'posts',
                  controller: _posts,
                  describe: (posts) => '${posts.length} posts',
                ),
                _ReaderRow<Post>(
                  label: 'post 1',
                  controller: _post1,
                  describe: (post) => post.title,
                ),
                _ReaderRow<Post>(
                  label: 'post 2',
                  controller: _post2,
                  describe: (post) => post.title,
                ),
                _ReaderRow<List<Todo>>(
                  label: 'todos',
                  controller: _todos,
                  describe: (todos) => '${todos.length} todos',
                ),
                const SizedBox(height: 8),
                Text(
                  'Post 3 has no reader: fetched once by client.query, it is '
                  'an inactive entry. The posts are stale at once, the todos '
                  'fresh for 30 s; post 2 never retries.',
                  style: small,
                ),
              ],
            ),
          ),
        ),
        QueryDebugStrip(queryKey: ShowcaseKeys.posts, label: 'posts'),
        QueryDebugStrip(queryKey: ShowcaseKeys.post(1), label: 'post-1'),
        QueryDebugStrip(queryKey: ShowcaseKeys.post(2), label: 'post-2'),
        QueryDebugStrip(queryKey: ShowcaseKeys.post(3), label: 'post-3'),
        QueryDebugStrip(queryKey: ShowcaseKeys.todos, label: 'todos'),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Notice(
            'Invalidate posts prefix: every key under [posts] is marked '
            'stale; the active ones refetch, post 3 only shows isStale=true.\n'
            'Invalidate posts exactly: exact: true, the list alone.\n'
            'Invalidate inactive too: refetchType: all, post 3 refetches as '
            'well.\n'
            'Predicate: errored: invalidates whatever is in error — tick '
            '"Fail post 2 next" and refetch post 2 first.\n'
            'Refetch stale only: stale: true — the posts, not the fresh '
            'todos, and not the unobserved post 3 until it is invalidated.\n'
            'Reset post 1: back to its initial state, then refetched because '
            'it has a reader.\n'
            'Remove post 2: the entry is gone (status=absent) while the '
            'reader keeps its last result; Re-attach post 2 resolves the key '
            'again and fetches.\n'
            'Refetch posts slowly, then Cancel posts: the fetch is reverted, '
            'the entry idle with its old data, and the late answer is '
            'ignored.\n'
            'Uppercase all post titles: getQueriesData counts the active '
            'detail entries (matched=), updateQueriesData rewrites them — a '
            'cache write, not a fetch.',
          ),
        ),
      ],
    );
  }
}

/// One row of the operations: the method's name, and its buttons.
class _Group extends StatelessWidget {
  const _Group({required this.name, required this.children});

  final String name;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(name, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: children,
            ),
          ],
        ),
      );
}

/// A button named by its label: the visible text is its accessible name, and
/// the tooltip stays out of the semantics so it cannot become a second one.
class _Action extends StatelessWidget {
  const _Action(this.label, this.onPressed);

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: OutlinedButton(
          onPressed: onPressed,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(label),
        ),
      );
}

/// One entry, read from its controller: what it holds, one text; its error,
/// another; and a pill while it fetches.
class _ReaderRow<T> extends StatelessWidget {
  const _ReaderRow({
    required this.label,
    required this.controller,
    required this.describe,
  });

  final String label;
  final QueryController<T, T> controller;
  final String Function(T data) describe;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final result = controller.value;
          final data = result.dataOrNull;
          final scheme = Theme.of(context).colorScheme;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 72,
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (data != null)
                        Text(describe(data))
                      else if (result is! QueryError<T>)
                        const SkeletonBox(width: 200),
                      if (result case QueryError<T>(:final error))
                        Text('$error', style: TextStyle(color: scheme.error)),
                    ],
                  ),
                ),
                if (result.isFetching)
                  Pill(result.isPending ? 'loading' : 'refreshing'),
              ],
            ),
          );
        },
      );
}
