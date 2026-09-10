/// Upstream's `prefetching` example: the posts list, each row with a
/// prefetch button that warms the cache for the detail before it opens, and
/// an open button that then reads it — within `staleTime` — without a
/// request. The list and the detail are both `QueryBuilder`s.
///
/// The prefetch is `client.query(options).ignore()`: upstream's
/// `prefetchQuery` is folded into `query`
/// (https://github.com/KoTTi97/flutter_query/issues/17), and ignoring the
/// future is what makes it a prefetch. Upstream prefetches on hover; here it
/// is a button, because hover never reaches a `MouseRegion` through Flutter
/// web's semantics overlay. A row whose post is in the cache shows a
/// `prefetched` pill, rebuilt on the cache's own events like the debug
/// strips. The prefetch options say `retry: RetryPolicy.never` out loud: the
/// imperative path makes one attempt unless a retry is configured, and a
/// refused prefetch must be one request, not four, for a reader counting
/// them.
///
/// The last card contrasts the three imperative reads of one key, the
/// backend's counter. `client.query(options)` awaits the fetch whenever the
/// entry is stale and hands back the new value. `client.query(options,
/// revalidateIfStale: true)` hands back what the cache holds on the spot and
/// refreshes behind it, so the value it returns is the old one for as long as
/// the fetch takes; it fails only when nothing at all is cached. The same
/// call under `staleTime: StaleTime.static` returns the cached value and
/// makes no request, background one included: a static entry is never stale.
/// `Increment on the server` moves the counter without touching the cache,
/// which is what makes a cached answer tell itself apart from a fresh one by
/// its value alone.
///
/// Proofs (widget tests in `test/features/prefetching_test.dart`, end-to-end
/// in `e2e/tests/prefetching.spec.ts`): a prefetch is one request and marks
/// the row with nobody observing the entry; opening the prefetched post costs
/// no request and shows the title at once; opening an unprefetched post costs
/// one; a second prefetch within `staleTime` is a no-op and a third after it
/// fetches again; a refused prefetch throws nothing into the UI, leaves the
/// row unmarked, and the post opens normally afterwards; a stale read with
/// `revalidateIfStale` returns the old value on the frame of the tap while
/// the entry is fetching and the cache holds the new one once the answer
/// lands, the plain read returns the new value, and the static read makes no
/// request at all.
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

const Feature prefetchingFeature = Feature(
  id: 'prefetching',
  title: 'Prefetching',
  summary: 'Warm the cache before the screen that needs it opens.',
  upstream: 'prefetching',
);

/// How long a post counts as fresh, for the prefetch and the detail alike:
/// the whole point is that the open within this window costs nothing.
const StaleTime postStaleTime = StaleTime.duration(Duration(seconds: 10));

QueryObserverOptions<List<Post>, List<Post>> postsQuery(ShowcaseApi api) =>
    QueryObserverOptions<List<Post>, List<Post>>(
      queryKey: ShowcaseKeys.posts,
      queryFn: (context) => api.posts(signal: context.signal),
    );

/// The detail's options: an observer's, since a `QueryBuilder` reads them.
QueryObserverOptions<Post, Post> postQuery(ShowcaseApi api, int id) =>
    QueryObserverOptions<Post, Post>(
      queryKey: ShowcaseKeys.post(id),
      queryFn: (context) => api.post(id, signal: context.signal),
      staleTime: postStaleTime,
    );

/// The prefetch's options: the plain cache-layer kind, since nothing observes
/// this fetch. Same key and same `staleTime` as [postQuery], so the detail
/// finds the entry fresh; no retries, so a refused prefetch is one request.
QueryOptions<Post> postPrefetch(ShowcaseApi api, int id) => QueryOptions<Post>(
      queryKey: ShowcaseKeys.post(id),
      queryFn: (context) => api.post(id, signal: context.signal),
      staleTime: postStaleTime,
      retry: RetryPolicy.never,
    );

/// The key the imperative-read card reads. Its own, not one of
/// [ShowcaseKeys]: the counter is a value a button can move on the server
/// behind the cache's back, which is what makes "cached" and "fresh" tell
/// themselves apart by the number alone.
final QueryKey counterKey = QueryKey(const <Object?>['prefetching', 'counter']);

/// The counter read: always stale, so the plain `client.query` fetches on
/// every press and `revalidateIfStale` always has a refresh to run behind
/// the cached answer it returns.
QueryOptions<int> counterRead(ShowcaseApi api) => QueryOptions<int>(
      queryKey: counterKey,
      queryFn: (context) => api.counter(signal: context.signal),
      staleTime: StaleTime.zero,
    );

/// The same read declared static. `StaleTime.static` is never stale, so a
/// cached entry is handed straight back and no request is made — not even the
/// background one `revalidateIfStale` would otherwise start.
QueryOptions<int> counterStaticRead(ShowcaseApi api) => QueryOptions<int>(
      queryKey: counterKey,
      queryFn: (context) => api.counter(signal: context.signal),
      staleTime: StaleTime.static,
    );

class PrefetchingScreen extends StatefulWidget {
  const PrefetchingScreen({super.key});

  @override
  State<PrefetchingScreen> createState() => _PrefetchingScreenState();
}

class _PrefetchingScreenState extends State<PrefetchingScreen> {
  /// The post whose detail is open, if any.
  int? _selected;

  /// The post the second debug strip watches: the last one prefetched or
  /// opened. A prefetch has no screen of its own, so this is where a reader
  /// sees its entry land with `observers=0`.
  int? _watched;

  /// What the last imperative read was and what it handed back, plus how
  /// often the server's counter has been moved behind the cache's back.
  String _lastRead = 'none';
  int? _returned;
  bool _readFailed = false;
  int _increments = 0;

  void _prefetch(int id) {
    final api = ShowcaseScope.apiOf(context);
    // The future is the prefetch's only handle, and nobody wants it: a
    // refused prefetch is the cache's business, not the screen's.
    QueryClientProvider.of(context).query(postPrefetch(api, id)).ignore();
    setState(() => _watched = id);
  }

  void _open(int id) => setState(() {
        _selected = id;
        _watched = id;
      });

  void _back() => setState(() => _selected = null);

  Future<void> _read(
    String label, {
    required bool revalidateIfStale,
    required bool neverStale,
  }) async {
    final api = ShowcaseScope.apiOf(context);
    final client = QueryClientProvider.of(context);
    final options = neverStale ? counterStaticRead(api) : counterRead(api);
    setState(() {
      _lastRead = label;
      _returned = null;
      _readFailed = false;
    });
    try {
      final value =
          await client.query(options, revalidateIfStale: revalidateIfStale);
      if (mounted) {
        setState(() => _returned = value);
      }
    } on Object {
      // The plain call fails whenever its fetch does; with
      // `revalidateIfStale` only an empty cache can fail. Either way the
      // card says so rather than leaving an error to the zone.
      if (mounted) {
        setState(() => _readFailed = true);
      }
    }
  }

  /// Moves the counter on the server and leaves the cache alone, so the
  /// cached value is provably out of date and a read's answer says which of
  /// the two it is.
  Future<void> _incrementOnServer() async {
    final api = ShowcaseScope.apiOf(context);
    try {
      await api.increment();
      if (mounted) {
        setState(() => _increments += 1);
      }
    } on Object {
      // A refused increment is not this card's subject; the reads are.
    }
  }

  /// The three calls side by side, with what came back and whether a request
  /// was made. `cached` and `requests` are read on every cache event, the way
  /// the strips are: the background refresh has no observer to announce it.
  Widget _readsCard() => SectionCard(
        title: 'Imperative reads',
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'reads',
          child: _OnCacheEvent(
            builder: (context) {
              final client = QueryClientProvider.of(context);
              final cached = client.getQueryData<int>(counterKey);
              final requests =
                  ShowcaseScope.of(context).stats.fetchesOf(counterKey);
              return Column(
                key: const ValueKey<String>('reads'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      FilledButton(
                        onPressed: () => _read(
                          'await',
                          revalidateIfStale: false,
                          neverStale: false,
                        ),
                        child: const Text('Read (await)'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _read(
                          'revalidate',
                          revalidateIfStale: true,
                          neverStale: false,
                        ),
                        child: const Text('Read (revalidateIfStale)'),
                      ),
                      OutlinedButton(
                        onPressed: () => _read(
                          'static',
                          revalidateIfStale: true,
                          neverStale: true,
                        ),
                        child: const Text('Read (static)'),
                      ),
                      OutlinedButton(
                        onPressed: _incrementOnServer,
                        child: const Text('Increment on the server'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    children: <Widget>[
                      for (final fact in <String>[
                        'read=$_lastRead',
                        if (_readFailed)
                          'returned=failed'
                        else
                          'returned=${_returned ?? '–'}',
                        'cached=${cached ?? '–'}',
                        'requests=$requests',
                        'increments=$_increments',
                      ])
                        Text(
                          fact,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    final selected = _selected;
    final watched = _watched;

    return FeatureScaffold(
      feature: prefetchingFeature,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Notice(
            'Prefetching warms the cache for a screen that has not opened '
            'yet. Within staleTime (10 s) opening the post costs no request.',
          ),
        ),
        if (selected == null)
          _PostList(
            options: postsQuery(api),
            onPrefetch: _prefetch,
            onOpen: _open,
          )
        else
          _PostDetail(
            id: selected,
            options: postQuery(api, selected),
            onBack: _back,
          ),
        QueryDebugStrip(queryKey: ShowcaseKeys.posts, label: 'posts'),
        if (watched != null)
          QueryDebugStrip(
            queryKey: ShowcaseKeys.post(watched),
            label: 'post-$watched',
          ),
        _readsCard(),
        QueryDebugStrip(queryKey: counterKey, label: 'counter'),
      ],
    );
  }
}

class _PostList extends StatelessWidget {
  const _PostList({
    required this.options,
    required this.onPrefetch,
    required this.onOpen,
  });

  final QueryObserverOptions<List<Post>, List<Post>> options;
  final void Function(int id) onPrefetch;
  final void Function(int id) onOpen;

  @override
  Widget build(BuildContext context) => QueryBuilder<List<Post>>(
        options: options,
        builder: (context, posts) => SectionCard(
          title: 'Posts',
          trailing: posts.isFetching ? const Pill('refreshing') : null,
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
              _OnCacheEvent(
                builder: (context) {
                  final client = QueryClientProvider.of(context);
                  // Bounded and scrolling on its own, so the debug strips
                  // under the card stay in view whatever the list's length:
                  // a card of thirty rows would push them off the screen,
                  // and a test only reads what is on it.
                  return SizedBox(
                    height: 200,
                    child: ListView.builder(
                      itemCount: data.length,
                      itemBuilder: (context, index) {
                        final post = data[index];
                        return _PostRow(
                          post: post,
                          // What upstream's bold marker reads too: the cache,
                          // not a flag the screen keeps — the entry may also
                          // have come from an open, or be gone by gcTime.
                          prefetched: client.getQueryData<Post>(
                                ShowcaseKeys.post(post.id),
                              ) !=
                              null,
                          onPrefetch: () => onPrefetch(post.id),
                          onOpen: () => onOpen(post.id),
                        );
                      },
                    ),
                  );
                },
              ),
          },
        ),
      );
}

class _PostRow extends StatelessWidget {
  const _PostRow({
    required this.post,
    required this.prefetched,
    required this.onPrefetch,
    required this.onOpen,
  });

  final Post post;
  final bool prefetched;
  final VoidCallback onPrefetch;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Semantics(
        // A group per row, so a test can tie the pill to its post; explicit
        // children keep the texts and buttons findable on their own.
        container: true,
        explicitChildNodes: true,
        label: 'post ${post.id}',
        child: Row(
          key: ValueKey<String>('post-row-${post.id}'),
          children: <Widget>[
            Expanded(child: Text('${post.id} · ${post.title}')),
            if (prefetched) ...<Widget>[
              const Pill('prefetched'),
              const SizedBox(width: 4),
            ],
            IconButton(
              tooltip: 'Prefetch post ${post.id}',
              onPressed: onPrefetch,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.download_outlined),
            ),
            IconButton(
              tooltip: 'Open post ${post.id}',
              onPressed: onOpen,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      );
}

class _PostDetail extends StatelessWidget {
  const _PostDetail({
    required this.id,
    required this.options,
    required this.onBack,
  });

  final int id;
  final QueryObserverOptions<Post, Post> options;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => QueryBuilder<Post>(
        options: options,
        builder: (context, post) => SectionCard(
          title: 'Post #$id',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (post.isFetching) const Pill('refreshing'),
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
        ),
      );
}

/// Rebuilds its subtree on every event of the query cache, the way the debug
/// strip does: the `prefetched` pills read the cache, and nothing else tells
/// the list that a prefetch landed — the prefetch has no observer.
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

  /// An event raised inside a frame's build phase — a sibling builder's first
  /// fetch — cannot mark this widget dirty there; it waits for the frame to
  /// end. Any other time the rebuild goes straight in.
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
