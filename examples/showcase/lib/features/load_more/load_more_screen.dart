/// Upstream's `load-more-infinite-scroll` example: one infinite query whose
/// pages are cursor slices of the projects (`GET /api/projects?cursor=`), a
/// `Load more` button that appends the next one, and the same append when
/// the list is scrolled near its end — upstream watches the button with an
/// intersection observer, this screen listens to the list's
/// `ScrollController`. The rows are the pages flattened
/// (`InfiniteData.flatten`); `hasNextPage` is `getNextPageParam` over the
/// last page, so a `nextId` of `null` is the end of the list and the button
/// goes dark. An `About` view, upstream's `/about` page, unmounts the list:
/// the pages stay in the cache without an observer and are back at once on
/// return, with no request.
///
/// The read is an `InfiniteQueryBuilder`, whose builder receives the
/// controller — where `hasNextPage`, `isFetchingNextPage` and
/// `fetchNextPage` live. A `select` keeps the page structure and drops the
/// cursors, so the widget sees `InfiniteData<List<Project>, int>`.
///
/// Proofs (widget tests in `test/features/load_more_test.dart`, end-to-end in
/// `e2e/tests/load_more.spec.ts`): the first page arrives after one request
/// with `cursor=0`; `Load more` appends the page at `cursor=10`, and while it
/// loads `isFetchingNextPage` is true and the button disabled; scrolling to
/// the bottom of the list appends the next page without the button; after
/// the tenth page (`cursor=90`) `hasNextPage` is false, the button is disabled
/// and nothing asks for `cursor=100`; going to `About` and back shows the
/// same rows with no request, the entry's observers going 1 → 0 → 1; a
/// refetch re-requests every held page, first to last.
library;

import 'package:flutter/material.dart';
import 'package:tanstack_query_flutter/tanstack_query_flutter.dart';

import '../../shared/api.dart';
import '../../shared/debug_strip.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';
import '../../shared/theme.dart';

const Feature loadMoreFeature = Feature(
  id: 'load-more',
  title: 'Load more and infinite scroll',
  summary: 'An infinite query that appends pages as you scroll.',
  upstream: 'load-more-infinite-scroll',
);

/// How many projects one page holds; the backend has a hundred, so ten pages.
const int pageSize = 10;

/// The list's viewport, so ten rows already overflow it and there is
/// something to scroll on the first page.
const double listHeight = 360;

/// Every row the same height, so the list's extent is arithmetic.
const double rowHeight = 48;

/// How close to the end of the list a scroll has to get before the next page
/// is fetched on its own — upstream's intersection observer, in pixels.
const double loadMoreThreshold = 100;

/// This screen owns its key: the paginated screens share the projects but
/// not the entry, and a page-numbered cache must not be confused with a
/// cursor-based one.
QueryKey get projectsInfiniteKey =>
    QueryKey(const <Object?>['projects', 'infinite']);

/// What the widget sees: the pages as lists of projects, cursors dropped.
typedef ProjectRows = InfiniteData<List<Project>, int>;

/// The screen's one query. `initialPageParam` is the first cursor,
/// `getNextPageParam` reads the cursor the backend sent with the last page —
/// `null` means there is no more, and that is what `hasNextPage` reports.
///
/// Fresh for five minutes: with the default stale time coming back from
/// `About` would be a mount over stale data, and that refetches every held
/// page — ten requests to show that the cache survived. Upstream's example
/// does exactly that; here the survival is what the screen is about.
InfiniteQueryObserverOptions<ProjectSlice, int, ProjectRows>
    projectsInfiniteQuery(ShowcaseApi api) =>
        InfiniteQueryObserverOptions<ProjectSlice, int, ProjectRows>(
          queryKey: projectsInfiniteKey,
          initialPageParam: 0,
          pageFn: (context) => api.projectsFrom(
            context.pageParam,
            limit: pageSize,
            signal: context.signal,
          ),
          getNextPageParam: (page, pages, param, params) => page.nextId,
          select: _rowsOf,
          staleTime: const StaleTime.duration(Duration(minutes: 5)),
        );

/// A top-level function, not a closure: the observer runs `select` again
/// whenever the function is a different one, and the options are rebuilt
/// with every build of the screen.
ProjectRows _rowsOf(InfiniteData<ProjectSlice, int> data) => ProjectRows(
      pages: <List<Project>>[for (final slice in data.pages) slice.items],
      pageParams: data.pageParams,
    );

class LoadMoreScreen extends StatefulWidget {
  const LoadMoreScreen({super.key});

  @override
  State<LoadMoreScreen> createState() => _LoadMoreScreenState();
}

class _LoadMoreScreenState extends State<LoadMoreScreen> {
  /// Upstream's two routes, as one screen with two views.
  bool _about = false;

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: loadMoreFeature,
        children: <Widget>[
          // The strip first, on both views: the list card is tall, and a
          // strip pushed out of the scaffold's lazy viewport is one no test
          // can read.
          QueryDebugStrip(queryKey: projectsInfiniteKey, label: 'projects'),
          if (_about)
            _AboutView(onBack: () => setState(() => _about = false))
          else
            _ProjectList(onAbout: () => setState(() => _about = true)),
        ],
      );
}

class _ProjectList extends StatefulWidget {
  const _ProjectList({required this.onAbout});

  final VoidCallback onAbout;

  @override
  State<_ProjectList> createState() => _ProjectListState();
}

class _ProjectListState extends State<_ProjectList> {
  final ScrollController _scroll = ScrollController();

  /// The builder's controller, kept for the scroll listener; the builder owns
  /// and disposes it.
  InfiniteQueryController<ProjectSlice, int, ProjectRows>? _projects;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Where the scroll was when the last page was asked for, so that resting
  /// at the end does not ask again.
  double? _askedAt;

  /// The same guard as upstream's effect: near the end, a page to fetch, and
  /// none in flight — and the view has moved since the last time we asked.
  ///
  /// The listener hears every scroll notification, and a list whose content
  /// grew sends some too. Without the last clause a page landing while the
  /// view still sat at the bottom asked for the next one straight away,
  /// because the notification can arrive before the new rows are laid out and
  /// `extentAfter` still reads as the end. How many pages that produced
  /// depended on how fast the machine was — two here, three on CI. "Waits for
  /// the next scroll" is now what the code says, not just the comment.
  void _onScroll() {
    final projects = _projects;
    if (projects == null || !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    if (!position.hasContentDimensions || !position.hasPixels) {
      return;
    }
    if (position.extentAfter < loadMoreThreshold &&
        position.pixels != _askedAt &&
        projects.hasNextPage &&
        !projects.isFetchingNextPage) {
      _askedAt = position.pixels;
      projects.fetchNextPage().ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    return InfiniteQueryBuilder<ProjectSlice, int, ProjectRows>(
      options: projectsInfiniteQuery(api),
      builder: (context, projects) {
        _projects = projects;
        final result = projects.value;
        final data = result.dataOrNull;
        final rows = data?.flatten<Project>().toList() ?? const <Project>[];
        final canLoadMore =
            projects.hasNextPage && !projects.isFetchingNextPage;

        return SectionCard(
          title: 'Projects',
          trailing: Semantics(
            container: true,
            explicitChildNodes: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // A refetch over the pages already held — upstream's
                // "Background Updating..." — as opposed to a page being added.
                if (projects.isRefetching) const Pill('refreshing'),
                IconButton(
                  tooltip: 'Refetch',
                  onPressed: result.isFetching ? null : projects.refetch,
                  icon: const Icon(Icons.refresh),
                ),
                FilledButton.tonal(
                  onPressed: widget.onAbout,
                  child: const Text('Go to about'),
                ),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Facts(<String>[
                'pages=${data?.pages.length ?? 0}',
                'rows=${rows.length}',
                'hasNextPage=${projects.hasNextPage}',
                'isFetchingNextPage=${projects.isFetchingNextPage}',
              ]),
              const SizedBox(height: 8),
              if (result case QueryError(:final error, staleData: null))
                Notice('$error', error: true)
              else ...<Widget>[
                if (result case QueryError(:final error)) ...<Widget>[
                  Notice(
                    projects.isFetchNextPageError
                        ? 'Load more failed: $error'
                        : 'Refetch failed: $error',
                    error: true,
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  height: listHeight,
                  child: rows.isEmpty
                      ? const _ListSkeleton()
                      : ListView.builder(
                          key: const ValueKey<String>('projects-list'),
                          controller: _scroll,
                          itemExtent: rowHeight,
                          itemCount: rows.length,
                          itemBuilder: (context, index) =>
                              _ProjectRow(rows[index]),
                        ),
                ),
              ],
              const SizedBox(height: 8),
              Semantics(
                container: true,
                explicitChildNodes: true,
                child: Row(
                  children: <Widget>[
                    FilledButton(
                      onPressed: canLoadMore ? projects.fetchNextPage : null,
                      child: const Text('Load more'),
                    ),
                    const SizedBox(width: 12),
                    if (projects.isFetchingNextPage)
                      const Pill('loading')
                    else if (data != null && !projects.hasNextPage)
                      const Text('Nothing more to load'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The paging facts as exact `key=value` texts, in a group of their own so
/// the strip's facts and these never look alike to a test.
class _Facts extends StatelessWidget {
  const _Facts(this.facts);

  final List<String> facts;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'projects facts',
        child: Wrap(
          key: const ValueKey<String>('projects-facts'),
          spacing: 12,
          children: <Widget>[
            for (final fact in facts)
              Text(
                fact,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
          ],
        ),
      );
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow(this.project);

  final Project project;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            // Upstream's `hsla(id * 30, 60%, 80%)`: a different pastel per
            // row, so a new page is visibly new.
            color: HSLColor.fromAHSL(1, (project.id * 30) % 360, 0.6, 0.8)
                .toColor(),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            project.name,
            style: const TextStyle(color: Colors.black87),
          ),
        ),
      );
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SkeletonBox(height: rowHeight - 4),
          SizedBox(height: 4),
          SkeletonBox(height: rowHeight - 4),
          SizedBox(height: 4),
          SkeletonBox(height: rowHeight - 4),
        ],
      );
}

/// Upstream's `/about` page: nothing here reads the projects, so the entry
/// has no observer while this is on screen — and it is still in the cache.
class _AboutView extends StatelessWidget {
  const _AboutView({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => SectionCard(
        title: 'About',
        trailing: FilledButton.tonal(
          onPressed: onBack,
          child: const Text('Back to list'),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'The list is unmounted. Nothing on this view reads the projects '
              'query, so its entry has no observer — the strip above says '
              'observers=0 — and the pages it holds are untouched.',
            ),
            SizedBox(height: 8),
            Text(
              'Going back mounts a fresh reader on the same entry. The data '
              'is still fresh, so every page is on screen at once and no '
              'request is made.',
            ),
          ],
        ),
      );
}
