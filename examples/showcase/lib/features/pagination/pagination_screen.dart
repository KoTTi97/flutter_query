/// Upstream's `pagination` example: page-numbered projects, one cache entry
/// per page, read with `context.query` under an `id:` so the observer follows
/// the key from page to page. `PlaceholderData.compute((previous, _) =>
/// previous)` — upstream's `keepPreviousData` — keeps the last page's rows on
/// screen while the next loads, and `isPlaceholderData` says when that is
/// what is showing. `Next page` is disabled while a placeholder is on screen,
/// as upstream disables it, so nobody skips past a page they have not seen;
/// and while the current page has real data and `hasMore`, the next page is
/// prefetched with `client.query(...).ignore()`, so the usual `Next page`
/// costs no request at all. `staleTime` is 5 s, upstream's, which is what
/// makes the prefetched page count as fresh when it is opened.
///
/// Proofs (widget tests in `test/features/pagination_test.dart`, end-to-end
/// in `e2e/tests/pagination.spec.ts`): page 0 costs one request and, once it
/// has data, page 1 is fetched with nobody observing it; `Next page` onto the
/// prefetched page costs no request and prefetches the page after; a page
/// whose prefetch has not answered shows the previous page's rows with
/// `isPlaceholderData=true` and `Next page` disabled until it does; `Previous
/// page` returns to a cached page with no request; on the last page `Next
/// page` is disabled and nothing beyond it is prefetched.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:tanstack_query_flutter/tanstack_query_flutter.dart';

import '../../shared/api.dart';
import '../../shared/debug_strip.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';
import '../../shared/theme.dart';

const Feature paginationFeature = Feature(
  id: 'pagination',
  title: 'Pagination',
  summary:
      'Page by page, keeping the previous page on screen while the next loads.',
  upstream: 'pagination',
);

/// One entry per page: the page number is part of the key.
QueryKey projectsPageKey(int page) =>
    QueryKey(<Object?>['projects', 'page', page]);

/// Upstream's 5 s: the window within which the prefetched next page counts as
/// fresh, so opening it costs no request.
const StaleTime projectsPageStaleTime =
    StaleTime.duration(Duration(seconds: 5));

/// The screen's read. The placeholder is the previous page's data, whatever
/// it was, so the rows never blank out between pages.
QueryObserverOptions<ProjectPage, ProjectPage> projectsPageQuery(
  ShowcaseApi api,
  int page,
) =>
    QueryObserverOptions<ProjectPage, ProjectPage>(
      queryKey: projectsPageKey(page),
      queryFn: (context) => api.projectsPage(page, signal: context.signal),
      staleTime: projectsPageStaleTime,
      placeholderData: PlaceholderData.compute((previous, _) => previous),
    );

/// The prefetch's options: the cache-layer kind, since nothing observes it.
/// Same key and `staleTime` as [projectsPageQuery], so the read finds the
/// entry fresh.
QueryOptions<ProjectPage> projectsPagePrefetch(ShowcaseApi api, int page) =>
    QueryOptions<ProjectPage>(
      queryKey: projectsPageKey(page),
      queryFn: (context) => api.projectsPage(page, signal: context.signal),
      staleTime: projectsPageStaleTime,
    );

class PaginationScreen extends StatefulWidget {
  const PaginationScreen({super.key});

  @override
  State<PaginationScreen> createState() => _PaginationScreenState();
}

class _PaginationScreenState extends State<PaginationScreen> {
  int _page = 0;

  /// The page whose successor has been prefetched. Upstream prefetches from
  /// an effect on `[data, page]`; here the build is the effect, and this is
  /// what keeps one page from prefetching on every rebuild.
  int? _prefetchedFrom;

  void _prefetchNext(int page) {
    _prefetchedFrom = page;
    final api = ShowcaseScope.apiOf(context);
    final client = QueryClientProvider.of(context);
    // After the frame, not inside the build: starting a fetch fires cache
    // events, and the widgets listening to them are mid-build right now.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        client.query(projectsPagePrefetch(api, page + 1)).ignore();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    final page = _page;
    // The `id` is what lets the observer follow the key: without it a new
    // page would be a new observer, with no previous data to keep.
    final result = context.query(projectsPageQuery(api, page), id: 'page');
    final data = result.dataOrNull;
    final hasMore = data?.hasMore ?? false;

    if (data != null &&
        !result.isPlaceholderData &&
        hasMore &&
        _prefetchedFrom != page) {
      _prefetchNext(page);
    }

    final canGoBack = page > 0;
    // Upstream's rule: no skipping past a page that is still a placeholder.
    final canGoForward = !result.isPlaceholderData && hasMore;

    return FeatureScaffold(
      feature: paginationFeature,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Notice(
            'Each page keeps the previous one on screen while it loads, and '
            'the next page is prefetched as soon as this one has data. Pages '
            'stay fresh for 5 s, so going back costs no request.',
          ),
        ),
        SectionCard(
          title: 'Pages',
          trailing: result.isFetching ? const Pill('loading') : null,
          child: Semantics(
            // Explicit children keep each button and each `key=value` text a
            // node of its own rather than folded into the row.
            container: true,
            explicitChildNodes: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    OutlinedButton(
                      onPressed:
                          canGoBack ? () => setState(() => _page -= 1) : null,
                      child: const Text('Previous page'),
                    ),
                    FilledButton(
                      onPressed: canGoForward
                          ? () => setState(() => _page += 1)
                          : null,
                      child: const Text('Next page'),
                    ),
                    Text('page=$page'),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  children: <Widget>[
                    Text('isPlaceholderData=${result.isPlaceholderData}'),
                    Text('hasMore=$hasMore'),
                    Text('isFetching=${result.isFetching}'),
                  ],
                ),
              ],
            ),
          ),
        ),
        QueryDebugStrip(queryKey: projectsPageKey(page), label: 'page-$page'),
        QueryDebugStrip(
          queryKey: projectsPageKey(page + 1),
          label: 'page-${page + 1}',
        ),
        SectionCard(
          title: 'Projects',
          child: switch (result) {
            QueryPending() => const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SkeletonBox(),
                  SizedBox(height: 4),
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
                  if (result case QueryError(:final error)) ...<Widget>[
                    Notice('Fetch failed: $error', error: true),
                    const SizedBox(height: 8),
                  ],
                  for (final project in data.projects)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('Project ${project.id}'),
                    ),
                ],
              ),
          },
        ),
      ],
    );
  }
}
