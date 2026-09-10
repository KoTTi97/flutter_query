/// Upstream's `basic` example: a list of posts, a detail opened from it in
/// the same screen, and what the cache already knows shown in the list —
/// a row is marked `cached` when `getQueryData` finds its post. Reopening a
/// visited post shows it at once and refreshes it in the background; the
/// detail entry has a short `gcTime`, so a post left alone is dropped from
/// the cache ten seconds later and its mark disappears.
///
/// The list is a `QueryBuilder`, the detail reads `context.query` — two of
/// the four call styles, side by side.
///
/// Proofs (widget tests in `test/features/basic_test.dart`, end-to-end in
/// `e2e/tests/basic.spec.ts`): the list arrives after one request with no
/// row marked; opening a post fetches it once and marks its row on the way
/// back, no other row; reopening it shows the title from the cache while the
/// refetch is still in flight; the entry is collected once `gcTime` passes
/// and the mark goes with it; leaving the screen releases every observer.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/cache_stats.dart';
import '../../shared/debug_strip.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';
import '../../shared/theme.dart';

const Feature basicFeature = Feature(
  id: 'basic',
  title: 'Basic',
  summary: 'A list, a detail, and what the cache already knows.',
  upstream: 'basic',
);

/// How long a post's entry outlives its last reader. Upstream keeps posts
/// for a day; ten seconds is long enough to see the `cached` mark and short
/// enough to watch it go.
const Duration postGcTime = Duration(seconds: 10);

/// The list's query, with the client's defaults for everything else.
QueryObserverOptions<List<Post>, List<Post>> postsQuery(ShowcaseApi api) =>
    QueryObserverOptions<List<Post>, List<Post>>(
      queryKey: ShowcaseKeys.posts,
      queryFn: (context) => api.posts(signal: context.signal),
    );

/// One post's query. The default `staleTime` is what makes a reopened post
/// refetch in the background; [postGcTime] is what lets it go.
QueryObserverOptions<Post, Post> postQuery(ShowcaseApi api, int id) =>
    QueryObserverOptions<Post, Post>(
      queryKey: ShowcaseKeys.post(id),
      queryFn: (context) => api.post(id, signal: context.signal),
      gcTime: const GcTime.duration(postGcTime),
    );

class BasicScreen extends StatefulWidget {
  const BasicScreen({super.key});

  @override
  State<BasicScreen> createState() => _BasicScreenState();
}

class _BasicScreenState extends State<BasicScreen> {
  /// The open post, or null for the list — upstream's `postId` state.
  int? _selectedId;

  @override
  Widget build(BuildContext context) {
    final selectedId = _selectedId;
    return FeatureScaffold(
      feature: basicFeature,
      children: <Widget>[
        if (selectedId == null) ...<Widget>[
          // The strip goes above the list: thirty rows push anything below
          // them out of the scaffold's lazily built viewport, and a strip
          // that is not built is a strip no test can read.
          QueryDebugStrip(queryKey: ShowcaseKeys.posts, label: 'posts'),
          _PostList(onOpen: (id) => setState(() => _selectedId = id)),
        ] else ...<Widget>[
          // Its own widget, so leaving it unmounts the `context.query`
          // reader and releases the post's observer at once.
          _PostDetail(
            id: selectedId,
            onBack: () => setState(() => _selectedId = null),
          ),
          QueryDebugStrip(
            queryKey: ShowcaseKeys.post(selectedId),
            label: 'post-$selectedId',
          ),
          QueryDebugStrip(queryKey: ShowcaseKeys.posts, label: 'posts'),
        ],
      ],
    );
  }
}

class _PostList extends StatelessWidget {
  const _PostList({required this.onOpen});

  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    final client = QueryClientProvider.of(context);
    return QueryBuilder<List<Post>>(
      options: postsQuery(api),
      builder: (context, posts) => SectionCard(
        title: 'Posts',
        trailing: posts.isFetching && posts.dataOrNull != null
            ? const Pill('refreshing')
            : null,
        child: switch (posts) {
          QueryPending() => const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SkeletonBox(),
                SizedBox(height: 8),
                SkeletonBox(),
                SizedBox(height: 8),
                SkeletonBox(),
              ],
            ),
          QueryError(:final error, staleData: null) =>
            Notice('$error', error: true),
          QuerySuccess(:final data) ||
          QueryError(staleData: final data!) =>
            // Whether a row's post is cached is not part of this query's
            // result: it is read straight from the cache, so the rows are
            // rebuilt on the cache's own events.
            _OnCacheEvent(
              builder: (context) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final post in data)
                    _PostRow(
                      post: post,
                      cached: client
                              .getQueryData<Post>(ShowcaseKeys.post(post.id)) !=
                          null,
                      onOpen: () => onOpen(post.id),
                    ),
                ],
              ),
            ),
        },
      ),
    );
  }
}

class _PostRow extends StatelessWidget {
  const _PostRow({
    required this.post,
    required this.cached,
    required this.onOpen,
  });

  final Post post;
  final bool cached;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Semantics(
        // A named group per row, so a test can ask for row 3's mark and
        // nobody else's; the mark stays a text of its own outside the button.
        container: true,
        explicitChildNodes: true,
        label: 'post ${post.id}',
        child: Row(
          key: ValueKey<String>('post-row-${post.id}'),
          children: <Widget>[
            Expanded(
              child: MergeSemantics(
                child: Semantics(
                  button: true,
                  child: InkWell(
                    onTap: onOpen,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      child: Text(
                        post.title,
                        style: cached
                            ? TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (cached) const Pill('cached'),
          ],
        ),
      );
}

class _PostDetail extends StatelessWidget {
  const _PostDetail({required this.id, required this.onBack});

  final int id;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    final post = context.query(postQuery(api, id));

    return SectionCard(
      title: 'Post #$id',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // A refetch over data already on screen: upstream's "Background
          // Updating...". The first load shows the skeleton instead.
          if (post.isFetching && post.dataOrNull != null)
            const Pill('refreshing'),
          IconButton(
            tooltip: 'Back to list',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          ),
        ],
      ),
      child: switch (post) {
        QueryPending() => const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SkeletonBox(height: 20, width: 240),
              SizedBox(height: 8),
              SkeletonBox(),
              SizedBox(height: 4),
              SkeletonBox(),
            ],
          ),
        QueryError(:final error, staleData: null) =>
          Notice('$error', error: true),
        QuerySuccess(:final data) ||
        QueryError(staleData: final data!) =>
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (post case QueryError(:final error)) ...<Widget>[
                Notice('Refetch failed: $error', error: true),
                const SizedBox(height: 8),
              ],
              Text(
                data.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(data.body),
            ],
          ),
      },
    );
  }
}

/// Rebuilds its subtree on every event of the query cache.
///
/// [CacheStats] fires from wherever the event came — a build that started a
/// fetch, a widget going away, a gc timer. The same rule as the debug strip:
/// inside a frame's build phase the rebuild waits for the frame to end,
/// anywhere else it goes straight in.
class _OnCacheEvent extends StatefulWidget {
  const _OnCacheEvent({required this.builder});

  final WidgetBuilder builder;

  @override
  State<_OnCacheEvent> createState() => _OnCacheEventState();
}

class _OnCacheEventState extends State<_OnCacheEvent> {
  CacheStats? _stats;
  bool _rebuildScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final stats = ShowcaseScope.of(context).stats;
    if (stats != _stats) {
      _stats?.removeListener(_rebuild);
      _stats = stats..addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    _stats?.removeListener(_rebuild);
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
