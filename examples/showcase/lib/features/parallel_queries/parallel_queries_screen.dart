/// Parallel queries: three independent queries in one widget, and the global
/// fetching count. Port-specific — the upstream docs page
/// `guides/parallel-queries.md` says a fixed number of queries needs nothing
/// more than writing them side by side, which is exactly this screen. When the
/// number is *not* fixed, `query-collections` is the screen: it uses
/// `QueriesBuilder` over a list that changes at runtime.
///
/// Each post has a `QueryController` of its own, created in `initState`,
/// disposed in `dispose`, and read through a `ListenableBuilder`; the toolbar
/// reads all three at once through `Listenable.merge`. The status line is
/// `client.isFetching()` — how many queries are fetching right now, across
/// the whole cache — rebuilt on every cache event.
///
/// Proofs (widget tests in `test/features/parallel_queries_test.dart`,
/// end-to-end in `e2e/tests/parallel_queries.spec.ts`): opening the screen
/// starts all three requests at once (`fetching=3`, every strip fetching
/// before any answer) and they all settle; `Refetch all` bumps every strip's
/// `fetches`; `Refetch post 2` bumps only `post-2`; with post 3 held back the
/// other two settle while it still fetches (`fetching=1`); leaving the screen
/// releases every observer.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/cache_listener.dart';
import '../../shared/cache_stats.dart';
import '../../shared/chrome.dart';
import '../../shared/debug_strip.dart';
import '../../shared/fact_group.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';

const Feature parallelQueriesFeature = Feature(
  id: 'parallel-queries',
  title: 'Parallel queries',
  summary: 'Several queries in one widget, and the global fetching count.',
);

/// One post's query. [delay] is the backend's per-request knob, so one of the
/// three can be made to finish visibly later than the others.
QueryObserverOptions<Post> postQuery(
  ShowcaseApi api,
  int id, {
  Duration? delay,
}) =>
    QueryObserverOptions<Post>(
      queryKey: ShowcaseKeys.post(id),
      queryFn: (context) => api.post(id, signal: context.signal, delay: delay),
    );

class ParallelQueriesScreen extends StatefulWidget {
  const ParallelQueriesScreen({super.key});

  @override
  State<ParallelQueriesScreen> createState() => _ParallelQueriesScreenState();
}

class _ParallelQueriesScreenState extends State<ParallelQueriesScreen> {
  static const Duration _slowDelay = Duration(seconds: 2);

  late final ShowcaseApi _api;
  late final QueryController<Post, Post> _post1;
  late final QueryController<Post, Post> _post2;
  late final QueryController<Post, Post> _post3;
  late final Listenable _all;
  bool _slowPost3 = false;

  @override
  void initState() {
    super.initState();
    // Neither lookup subscribes: the api and the client are fixed for the
    // life of the app, and a subscribing lookup is not allowed here anyway.
    _api = context.getInheritedWidgetOfExactType<ShowcaseScope>()!.api;
    final client = QueryClientProvider.read(context);
    _post1 = QueryController.create(client, postQuery(_api, 1));
    _post2 = QueryController.create(client, postQuery(_api, 2));
    _post3 = QueryController.create(client, postQuery(_api, 3));
    _all = Listenable.merge(<Listenable>[_post1, _post2, _post3]);
  }

  @override
  void dispose() {
    _post1.dispose();
    _post2.dispose();
    _post3.dispose();
    super.dispose();
  }

  List<QueryController<Post, Post>> get _controllers =>
      <QueryController<Post, Post>>[_post1, _post2, _post3];

  void _refetchAll() {
    for (final controller in _controllers) {
      controller.refetch().ignore();
    }
  }

  void _setSlowPost3(bool slow) {
    setState(() => _slowPost3 = slow);
    // Same key, another query function: the observer keeps its entry and
    // does not refetch by itself. The delay applies from the next fetch on.
    _post3.setOptions(
      postQuery(_api, 3, delay: slow ? _slowDelay : null),
    );
  }

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: parallelQueriesFeature,
        children: <Widget>[
          // Explicit child nodes: a list row folds every plain text inside
          // it into one label, and `fetching=<n>` is read as an exact text.
          SemanticsGroup(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListenableBuilder(
                listenable: _all,
                builder: (context, _) {
                  final anyFetching =
                      _controllers.any((c) => c.value.isFetching);
                  return Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      _FetchingCount(stats: ShowcaseScope.of(context).stats),
                      Tooltip(
                        message: 'Refetch all',
                        child: FilledButton.tonalIcon(
                          onPressed: anyFetching ? null : _refetchAll,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refetch all'),
                        ),
                      ),
                      Tooltip(
                        message: 'Refetch post 2',
                        child: OutlinedButton(
                          onPressed: _post2.value.isFetching
                              ? null
                              : () => _post2.refetch().ignore(),
                          child: const Text('Refetch post 2'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          SwitchListTile(
            dense: true,
            title: const Text('Slow post 3'),
            value: _slowPost3,
            onChanged: _setSlowPost3,
          ),
          // Side by side where there is room: the point is to watch three
          // requests run at the same time, and a browser-driven test can
          // only read what is in view.
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = <Widget>[
                for (final (index, controller) in _controllers.indexed)
                  _PostCard(index: index + 1, controller: controller),
              ];
              return constraints.maxWidth >= 560
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (final card in cards) Expanded(child: card),
                      ],
                    )
                  : Column(children: cards);
            },
          ),
          for (final id in <int>[1, 2, 3])
            QueryDebugStrip(queryKey: ShowcaseKeys.post(id), label: 'post-$id'),
        ],
      );
}

/// One post, read from its controller.
class _PostCard extends StatelessWidget {
  const _PostCard({required this.index, required this.controller});

  final int index;
  final QueryController<Post, Post> controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final post = controller.value;
          return SectionCard(
            title: 'Post #$index',
            trailing: switch (post) {
              QueryResult(isLoading: true) => const Pill('loading'),
              QueryResult(isRefetching: true) => const Pill('refreshing'),
              _ => const SizedBox.shrink(),
            },
            child: switch (post) {
              QueryPending() => const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SkeletonBox(height: 20),
                    SizedBox(height: 4),
                    SkeletonBox(height: 20, width: 120),
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
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
            },
          );
        },
      );
}

/// `fetching=<n>`: how many queries in the whole cache are fetching, read
/// from the client on every cache event.
///
/// Rebuilt the way the debug strip is: a cache event can arrive from a
/// sibling's first build, when a rebuild has to wait for the frame to end.
class _FetchingCount extends StatefulWidget {
  const _FetchingCount({required this.stats});

  final CacheStats stats;

  @override
  State<_FetchingCount> createState() => _FetchingCountState();
}

class _FetchingCountState extends State<_FetchingCount>
    with PhaseSafeRebuild<_FetchingCount> {
  @override
  void initState() {
    super.initState();
    widget.stats.addListener(scheduleRebuild);
  }

  @override
  void didUpdateWidget(_FetchingCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stats != widget.stats) {
      oldWidget.stats.removeListener(scheduleRebuild);
      widget.stats.addListener(scheduleRebuild);
    }
  }

  @override
  void dispose() {
    widget.stats.removeListener(scheduleRebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fetching = widget.stats.client.isFetching();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'client.isFetching()',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(width: 8),
        Text(
          'fetching=$fetching',
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      ],
    );
  }
}
