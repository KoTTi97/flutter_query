/// Upstream's `infinite-query-with-max-pages` example: an infinite query that
/// pages in both directions from a cursor in the middle of the data, holding
/// a window of at most three pages. `maxPages: 3` drops the page at the far
/// end whenever a fourth comes in, so paging forward slides the window and
/// paging back slides it again; a refetch re-requests exactly the pages the
/// window holds, first to last, and every row's `fetched` stamp moves.
///
/// The query is an `InfiniteQueryController` created in `initState` and read
/// through a `ListenableBuilder`; the paging half — `hasNextPage`,
/// `isFetchingPreviousPage`, `fetchNextPage` — lives on the controller, not
/// on the sealed result.
///
/// Proofs (widget tests in `test/features/max_pages_test.dart`, end-to-end in
/// `e2e/tests/max_pages.spec.ts`): the screen starts on the page at cursor 30
/// with both directions available; two `Load next` make `pageParams=30,40,50`
/// and a third slides the window to `40,50,60` — still three pages, rows
/// 30–39 gone, rows 60–69 there, one request per cursor; `Load previous`
/// from there slides it back to `30,40,50` with one new request for 30;
/// `Refetch` sends one request per page in the window, bumps `fetches` by one
/// and renews every row's `fetched` stamp; cursor 90 ends the forward
/// direction (`hasNextPage=false`, button disabled) and cursor 0 the backward
/// one.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/debug_strip.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';
import '../../shared/theme.dart';

const Feature maxPagesFeature = Feature(
  id: 'max-pages',
  title: 'Infinite query with max pages',
  summary: 'Pages in both directions, with a window of three.',
  upstream: 'infinite-query-with-max-pages',
);

/// The window's cache entry — its own key, so the pagination and load-more
/// screens' project entries are untouched by what happens here.
QueryKey get projectsWindowKey =>
    QueryKey(const <Object?>['projects', 'window']);

/// Ten rows per page; the backend has a hundred, ids 0 to 99.
const int pageSize = 10;

/// Where the window starts: in the middle, so there is a page on either side
/// from the first frame on.
const int startCursor = 30;

/// How many pages the window keeps.
const int windowSize = 3;

typedef ProjectWindow = InfiniteData<ProjectSlice, int>;

/// The window's options. The cursors come back with every slice, so the
/// paging functions read them off the page rather than counting.
InfiniteQueryObserverOptions<ProjectSlice, int, ProjectWindow>
    projectsWindowQuery(ShowcaseApi api) =>
        InfiniteQueryObserverOptions<ProjectSlice, int, ProjectWindow>(
          queryKey: projectsWindowKey,
          initialPageParam: startCursor,
          pageFn: (context) => api.projectsFrom(
            context.pageParam,
            limit: pageSize,
            signal: context.signal,
          ),
          getNextPageParam: (page, _, __, ___) => page.nextId,
          getPreviousPageParam: (page, _, __, ___) => page.previousId,
          maxPages: windowSize,
        );

class MaxPagesScreen extends StatefulWidget {
  const MaxPagesScreen({super.key});

  @override
  State<MaxPagesScreen> createState() => _MaxPagesScreenState();
}

class _MaxPagesScreenState extends State<MaxPagesScreen> {
  late final InfiniteQueryController<ProjectSlice, int, ProjectWindow> _window;

  @override
  void initState() {
    super.initState();
    // Neither lookup subscribes: the api and the client are fixed for the
    // life of the app, and a subscribing lookup is not allowed here anyway.
    final api = context.getInheritedWidgetOfExactType<ShowcaseScope>()!.api;
    _window = InfiniteQueryController<ProjectSlice, int, ProjectWindow>(
      QueryClientProvider.read(context),
      projectsWindowQuery(api),
    );
  }

  @override
  void dispose() {
    _window.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: maxPagesFeature,
        children: <Widget>[
          ListenableBuilder(
            listenable: _window,
            builder: (context, _) => _WindowCard(window: _window),
          ),
          QueryDebugStrip(queryKey: projectsWindowKey, label: 'projects'),
        ],
      );
}

/// The window: its facts, the three buttons, and the rows it holds.
class _WindowCard extends StatelessWidget {
  const _WindowCard({required this.window});

  final InfiniteQueryController<ProjectSlice, int, ProjectWindow> window;

  @override
  Widget build(BuildContext context) {
    final result = window.value;
    final data = result.dataOrNull;
    final pages = data?.pages ?? const <ProjectSlice>[];
    final pageParams = data?.pageParams ?? const <int>[];
    final rows = <Project>[
      for (final page in pages) ...page.items,
    ];

    return SectionCard(
      title: '$pageSize projects per page, $windowSize pages at most',
      trailing: switch (result) {
        QueryResult(isLoading: true) => const Pill('loading'),
        _ when window.isFetchingPreviousPage => const Pill('loading previous'),
        _ when window.isFetchingNextPage => const Pill('loading next'),
        _ when window.isRefetching => const Pill('refreshing'),
        _ => const SizedBox.shrink(),
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Explicit child nodes: a row of buttons and texts folds into one
          // semantics node otherwise, and every `key=value` here is read as
          // an exact text.
          Semantics(
            container: true,
            explicitChildNodes: true,
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: <Widget>[
                _Fact('pages=${pages.length}'),
                _Fact('pageParams=${pageParams.join(',')}'),
                _Fact('hasPreviousPage=${window.hasPreviousPage}'),
                _Fact('hasNextPage=${window.hasNextPage}'),
                _Fact(
                    'isFetchingPreviousPage=${window.isFetchingPreviousPage}'),
                _Fact('isFetchingNextPage=${window.isFetchingNextPage}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            container: true,
            explicitChildNodes: true,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed:
                      window.hasPreviousPage && !window.isFetchingPreviousPage
                          ? () => window.fetchPreviousPage().ignore()
                          : null,
                  icon: const Icon(Icons.arrow_upward),
                  label: const Text('Load previous'),
                ),
                FilledButton.tonalIcon(
                  onPressed: window.hasNextPage && !window.isFetchingNextPage
                      ? () => window.fetchNextPage().ignore()
                      : null,
                  icon: const Icon(Icons.arrow_downward),
                  label: const Text('Load next'),
                ),
                OutlinedButton.icon(
                  onPressed: result.isFetching
                      ? null
                      : () => window.refetch().ignore(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refetch'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          switch (result) {
            QueryPending() => const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SkeletonBox(height: 20),
                  SizedBox(height: 4),
                  SkeletonBox(height: 20),
                  SizedBox(height: 4),
                  SkeletonBox(height: 20),
                ],
              ),
            QueryError(:final error, staleData: null) =>
              Notice('$error', error: true),
            _ => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (result case QueryError(:final error)) ...<Widget>[
                    Notice('Fetch failed: $error', error: true),
                    const SizedBox(height: 8),
                  ],
                  _Rows(rows: rows),
                ],
              ),
          },
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      );
}

/// The rows of every page in the window, in a scroller of their own: the
/// screen's scaffold builds its children lazily, and the strip under thirty
/// rows would otherwise never be built.
///
/// Not a lazy list. Thirty rows are nothing, and a lazy list whose row count
/// grows under a fixed row height keeps its old scroll extent until the next
/// scroll — the rows the new page brought would be unreachable for one
/// frame. With every row in the tree the far end of the window is always
/// there to be found.
class _Rows extends StatelessWidget {
  const _Rows({required this.rows});

  final List<Project> rows;

  static String _clock(DateTime at) {
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey<String>('project-rows'),
      height: 240,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final project in rows)
              SizedBox(
                height: 40,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: <Widget>[
                      Expanded(child: Text(project.name)),
                      Text(
                        'fetched ${_clock(project.fetchedAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
