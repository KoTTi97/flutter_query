/// Port-specific: `buildWhen` on the **eight keyless reads**, each one beside
/// its unfiltered twin.
///
/// The site's [What rebuilds, and when](https://github.com/KoTTi97/flutter_query/blob/main/website/docs/guides/rebuilds.md)
/// names twelve places that take the predicate: four builders and eight
/// keyless reads — `watchQuery`, `watchSelectQuery`, `watchInfiniteQuery`,
/// `watchMutation`, `context.query`, `context.selectQuery`,
/// `context.infiniteQuery` and `context.mutation`. The builders are
/// demonstrated on `select-and-sharing`; the eight are demonstrated here,
/// which is the whole reason this screen exists (C39,
/// https://github.com/KoTTi97/flutter_query/issues/68). This screen shows
/// what that page describes and explains nothing a second way.
///
/// **Sixteen readers, in eight pairs.** Every member is read twice over the
/// same cache entry: once **filtered**, passing the predicate the knob names,
/// and once **plain**, passing none. Both halves count their own builds, so
/// the effect of the predicate is the difference between two numbers on one
/// screen rather than the same number before and after a knob.
///
/// What the counters do, and why:
///
/// - **A first load is two builds for everyone.** The first build reads the
///   result the subscribe produced — pending, already fetching — and the
///   data landing is the second. `null` to a list is a change of the data,
///   so the `data` predicate lets it through too. A mutation reader starts at
///   one: nothing has been reported yet.
/// - **A refetch that brings back equal data is two builds for a plain
///   reader and none for a filtered one.** `QueryResult`'s `==` covers
///   `fetchStatus` and `dataUpdatedAt`, so the flip to fetching and the
///   landing are both changed results — and `select` cannot narrow either of
///   them away, which is why the two select reads sit here next to the two
///   plain ones and move exactly as far.
/// - **A real change gets through the filter.** `Drop a post` writes a
///   shorter list straight into the cache; the data moved, so every reader
///   rebuilds, filtered ones included.
/// - **`Load next` is two builds plain and one filtered.** The page fetch
///   starting moves `fetchStatus` while the pages are still the pages the
///   reader is showing — refused — and the new page is a real change.
/// - **A mutation run is three builds plain and two filtered.** `idle`,
///   `pending` and `success` are three results; only the last of them carries
///   data, so the `data` predicate drops the pending one. A mutation has no
///   `select`, so the predicate is the *only* filter one of these readers has
///   (https://github.com/KoTTi97/flutter_query/issues/67).
/// - **The knob moves every counter by one.** A predicate filters
///   *notifications*, not rebuilds from above: a new value for the knob is a
///   new widget for all sixteen readers, and nothing about `buildWhen` can
///   refuse a parent. `never` freezes the filtered half where it stands and
///   `always` makes it its twin again, which is the proof that the predicate
///   is the only difference between the two halves of a pair.
///
/// One case the screen deliberately does **not** reach: an infinite query
/// whose paging flags move while the result stays equal — two fetches in
/// opposite directions — rebuilds whatever the predicate says, because there
/// is nothing there for a predicate over results to compare. `max-pages` is
/// the screen with fetches in both directions; here every page fetch moves
/// `fetchStatus` too, so the predicate is always the one that answers.
///
/// Proofs (widget tests in `test/features/build_when_test.dart`, end-to-end
/// in `e2e/tests/build_when.spec.ts`): all sixteen readers load from one
/// request per entry; a refetch with equal data moves the eight plain query
/// counters by two and none of the filtered ones; `Drop a post` moves all
/// sixteen posts-side counters by one; `Load next` is two against one; a
/// mutation run is three against two; `never` freezes the filtered half and
/// `always` makes both halves of every pair equal again.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/controls.dart';
import '../../shared/debug_strip.dart';
import '../../shared/fact_group.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';
import '../../shared/theme.dart';

const Feature buildWhenFeature = Feature(
  id: 'build-when',
  title: 'Filtering rebuilds',
  summary: 'buildWhen on the eight keyless reads, each beside its '
      'unfiltered twin.',
);

/// Which predicate the filtered half of every pair passes. The knob's three
/// values, and the one string each is named by in both test layers.
enum Filter {
  /// `previous.dataOrNull != current.dataOrNull`, the canonical one: rebuild
  /// for the data and for nothing else.
  data('data'),

  /// `(_, __) => false`. The filtered half stops rebuilding entirely, which
  /// is what makes "the predicate decides" visible rather than plausible.
  never('never'),

  /// `(_, __) => true`. The filtered half becomes its plain twin again: the
  /// predicate is the only difference between them.
  always('always');

  const Filter(this.label);

  /// The knob's segment, and the word the screen prints.
  final String label;
}

// The predicates are top-level functions, not closures built in `build`: a
// tear-off of one is the same object on every build, so nothing about the
// filtering depends on which frame asked.

bool queryDataMoved<TData>(
  QueryResult<TData> previous,
  QueryResult<TData> current,
) =>
    previous.dataOrNull != current.dataOrNull;

bool mutationDataMoved<TData, TVariables>(
  MutationResult<TData, TVariables> previous,
  MutationResult<TData, TVariables> current,
) =>
    previous.dataOrNull != current.dataOrNull;

bool refuse<T>(T previous, T current) => false;

bool accept<T>(T previous, T current) => true;

/// The predicate a filtered query or infinite read passes for [filter].
BuildWhen<QueryResult<TData>> queryBuildWhen<TData>(Filter filter) =>
    switch (filter) {
      Filter.data => queryDataMoved<TData>,
      Filter.never => refuse<QueryResult<TData>>,
      Filter.always => accept<QueryResult<TData>>,
    };

/// [queryBuildWhen] for a mutation read, whose result is a different type
/// with the same `dataOrNull`.
BuildWhen<MutationResult<TData, TVariables>>
    mutationBuildWhen<TData, TVariables>(Filter filter) => switch (filter) {
          Filter.data => mutationDataMoved<TData, TVariables>,
          Filter.never => refuse<MutationResult<TData, TVariables>>,
          Filter.always => accept<MutationResult<TData, TVariables>>,
        };

/// The entry the eight posts-side readers share.
///
/// The `staleTime` is what makes "eight readers, one request" hold whichever
/// frame each one first builds in: a reader that subscribes after the data is
/// in joins it instead of starting a refetch of its own. The buttons are
/// unaffected — `refetchQueries` ignores staleness.
QueryObserverOptions<List<Post>> postsQuery(ShowcaseApi api) =>
    QueryObserverOptions<List<Post>>(
      queryKey: ShowcaseKeys.posts,
      queryFn: (context) => api.posts(signal: context.signal),
      staleTime: const StaleTime.duration(Duration(minutes: 5)),
    );

/// [postsQuery] with a `select`, for the two select reads: the same entry,
/// the same fetch, the count instead of the list.
QuerySelectOptions<List<Post>, int> postCountQuery(ShowcaseApi api) =>
    QuerySelectOptions<List<Post>, int>(
      queryKey: ShowcaseKeys.posts,
      queryFn: (context) => api.posts(signal: context.signal),
      select: countPosts,
      staleTime: const StaleTime.duration(Duration(minutes: 5)),
    );

int countPosts(List<Post> posts) => posts.length;

/// This screen's own infinite entry, so the `load-more` and `max-pages`
/// entries are untouched by what happens here.
QueryKey get pagesKey => QueryKey(const <Object?>['projects', 'build-when']);

InfiniteQueryObserverOptions<ProjectSlice, int> pagesQuery(ShowcaseApi api) =>
    InfiniteQueryObserverOptions<ProjectSlice, int>(
      queryKey: pagesKey,
      initialPageParam: 0,
      pageFn: (context) => api.projectsFrom(
        context.pageParam,
        limit: 10,
        signal: context.signal,
      ),
      getNextPageParam: (page, _, __, ___) => page.nextId,
      staleTime: const StaleTime.duration(Duration(minutes: 5)),
    );

/// One increment, so a mutation reader has something to report. Each of the
/// four mutation readers owns a mutation of its own — mutations are never
/// shared — and what any of them wrote is deliberately not on screen: the
/// four run at once, so the value the backend answers depends on the order
/// four requests happened to arrive in, and nothing here may depend on that.
MutationOptions<int, int, void> incrementMutation(ShowcaseApi api) =>
    MutationOptions.simple<int, int>(
      mutationFn: (by) => api.increment(by: by),
    );

/// What a toolbar button asks a reader to do.
///
/// The work a card offers — run the mutation, load the next page — lives on a
/// controller a *reader* holds, and a button inside one reader would make
/// that row different from its twin. So the buttons stay in the card's
/// toolbar and tick this, and the readers that must act listen.
class Trigger extends ValueNotifier<int> {
  Trigger() : super(0);

  /// One more press.
  void fire() => value += 1;
}

class BuildWhenScreen extends StatefulWidget {
  const BuildWhenScreen({super.key});

  @override
  State<BuildWhenScreen> createState() => _BuildWhenScreenState();
}

class _BuildWhenScreenState extends State<BuildWhenScreen> {
  Filter _filter = Filter.data;

  /// Created once and never replaced, which is why the readers may listen in
  /// `initState` and forget about them until `dispose`.
  final Trigger _loadNext = Trigger();
  final Trigger _runMutation = Trigger();

  @override
  void dispose() {
    _loadNext.dispose();
    _runMutation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = _filter;
    return FeatureScaffold(
      feature: buildWhenFeature,
      children: <Widget>[
        SectionCard(
          title: 'The predicate the filtered half passes',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Every read below is made twice over one entry: filtered, '
                'with the predicate this knob names, and plain, with none. '
                'A predicate filters notifications, not rebuilds from above — '
                'moving this knob is a new widget for all sixteen readers, so '
                'every counter goes up by one whichever value you pick.',
              ),
              const SizedBox(height: 12),
              knob<Filter>(
                context,
                title: 'buildWhen',
                name: 'predicate',
                choices: <(String, Filter)>[
                  for (final value in Filter.values) (value.label, value),
                ],
                selected: filter,
                onChanged: (value) => setState(() => _filter = value),
              ),
            ],
          ),
        ),
        QueryDebugStrip(queryKey: ShowcaseKeys.posts, label: 'posts'),
        _QueryReadsCard(filter: filter),
        QueryDebugStrip(queryKey: pagesKey, label: 'pages'),
        _InfiniteReadsCard(filter: filter, loadNext: _loadNext),
        _MutationReadsCard(filter: filter, run: _runMutation),
      ],
    );
  }
}

/// The four query-shaped reads, filtered and plain: one entry, eight
/// observers.
class _QueryReadsCard extends StatelessWidget {
  const _QueryReadsCard({required this.filter});

  final Filter filter;

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    return SectionCard(
      title: 'The query reads: watchQuery, context.query, and the two selects',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Toolbar(
            children: <Widget>[
              ActionButton(
                label: 'Refetch the posts',
                filled: true,
                onPressed: () => client
                    .refetchQueries(
                      filters: QueryFilters(queryKey: ShowcaseKeys.posts),
                    )
                    .ignore(),
              ),
              ActionButton(
                label: 'Drop a post',
                onPressed: () => client.updateQueryData<List<Post>>(
                  ShowcaseKeys.posts,
                  (previous) => previous == null || previous.isEmpty
                      ? null
                      : previous.sublist(1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'The backend answers the same thirty posts every time, so a '
            'refetch is a changed result with unchanged data: two rebuilds '
            'for a plain reader and none for a filtered one. Dropping a post '
            'changes the data, and every reader shows it.',
          ),
          for (final filtered in <bool>[true, false]) ...<Widget>[
            _WatchQueryReader(filter: filter, filtered: filtered),
            _ContextQueryReader(filter: filter, filtered: filtered),
            _WatchSelectQueryReader(filter: filter, filtered: filtered),
            _ContextSelectQueryReader(filter: filter, filtered: filtered),
          ],
        ],
      ),
    );
  }
}

/// The two infinite reads, filtered and plain. Both hand back the controller,
/// because paging lives on it.
class _InfiniteReadsCard extends StatelessWidget {
  const _InfiniteReadsCard({required this.filter, required this.loadNext});

  final Filter filter;
  final Trigger loadNext;

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    return SectionCard(
      title: 'The infinite reads: watchInfiniteQuery, context.infiniteQuery',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Toolbar(
            children: <Widget>[
              ActionButton(
                label: 'Load next',
                filled: true,
                onPressed: loadNext.fire,
              ),
              ActionButton(
                label: 'Refetch the pages',
                onPressed: () => client
                    .refetchQueries(filters: QueryFilters(queryKey: pagesKey))
                    .ignore(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Load next is two rebuilds plain and one filtered: the fetch '
            'starting moves fetchStatus while the pages are still the pages '
            'on screen, and the page landing is a real change. Refetching the '
            'pages brings back the pages that are already there, so the '
            'filtered half does not move at all. Paging goes through the '
            'plain mixin reader, so no row carries a button its twin does '
            'not.',
          ),
          for (final filtered in <bool>[true, false]) ...<Widget>[
            _WatchInfiniteQueryReader(
              filter: filter,
              filtered: filtered,
              loadNext: filtered ? null : loadNext,
            ),
            _ContextInfiniteQueryReader(filter: filter, filtered: filtered),
          ],
        ],
      ),
    );
  }
}

/// The two mutation reads, filtered and plain. Four readers, four mutations:
/// one is never shared, so all four run together on one button.
class _MutationReadsCard extends StatelessWidget {
  const _MutationReadsCard({required this.filter, required this.run});

  final Filter filter;
  final Trigger run;

  @override
  Widget build(BuildContext context) => SectionCard(
        title: 'The mutation reads: watchMutation, context.mutation',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Toolbar(
              children: <Widget>[
                ActionButton(
                  label: 'Run the mutation',
                  filled: true,
                  onPressed: run.fire,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'A run is idle, pending and success: three results, of which '
              'only the last carries data. The plain half rebuilds three '
              'times, the filtered half twice. A mutation has no select, so '
              'the predicate is the only filter one of these readers has.',
            ),
            for (final filtered in <bool>[true, false]) ...<Widget>[
              _WatchMutationReader(
                  filter: filter, filtered: filtered, run: run),
              _ContextMutationReader(
                  filter: filter, filtered: filtered, run: run),
            ],
          ],
        ),
      );
}

/// One reader's row: which member it is, whether it filters, what it shows,
/// and how often it has built.
///
/// A semantics group named `reader watchQuery filtered` or
/// `reader watchQuery plain` — the member spelled exactly as the call is
/// written, because the
/// eight members are what this screen is a catalogue of. It composes
/// [SemanticsGroup] and [FactList] rather than calling `FactGroup`, since it
/// carries a heading beside its facts.
class _ReaderRow extends StatelessWidget {
  const _ReaderRow({
    required this.member,
    required this.filter,
    required this.filtered,
    required this.builds,
    required this.facts,
  });

  /// `watchQuery`, `context.mutation`: the call, as written.
  final String member;

  /// The knob's value — printed, but only used when [filtered].
  final Filter filter;

  /// Whether this half of the pair passes the predicate.
  final bool filtered;

  final int builds;

  /// What the reader read, as exact `key=value` texts.
  final List<String> facts;

  @override
  Widget build(BuildContext context) => SemanticsGroup(
        name: 'reader $member ${filtered ? 'filtered' : 'plain'}',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                filtered
                    ? '$member · buildWhen ${filter.label}'
                    : '$member · no buildWhen',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 2),
              FactList(<String>[...facts, 'builds=$builds'], dense: true),
            ],
          ),
        ),
      );
}

/// The facts a query-shaped reader prints, given what it read.
List<String> _queryFacts(
        QueryResult<Object?> result, String name, Object? had) =>
    <String>['status=${result.status.name}', '$name=$had'];

/// Reader 1: `watchQuery`, in a `QueryMixin`.
class _WatchQueryReader extends StatefulWidget {
  const _WatchQueryReader({required this.filter, required this.filtered});

  final Filter filter;
  final bool filtered;

  @override
  State<_WatchQueryReader> createState() => _WatchQueryReaderState();
}

class _WatchQueryReaderState extends State<_WatchQueryReader> with QueryMixin {
  int _builds = 0;

  @override
  Widget build(BuildContext context) {
    final result = watchQuery<List<Post>>(
      postsQuery(ShowcaseScope.apiOf(context)),
      buildWhen:
          widget.filtered ? queryBuildWhen<List<Post>>(widget.filter) : null,
    );
    _builds += 1;
    return _ReaderRow(
      member: 'watchQuery',
      filter: widget.filter,
      filtered: widget.filtered,
      builds: _builds,
      facts: _queryFacts(result, 'posts', result.dataOrNull?.length ?? 0),
    );
  }
}

/// Reader 2: `context.query`.
class _ContextQueryReader extends StatefulWidget {
  const _ContextQueryReader({required this.filter, required this.filtered});

  final Filter filter;
  final bool filtered;

  @override
  State<_ContextQueryReader> createState() => _ContextQueryReaderState();
}

class _ContextQueryReaderState extends State<_ContextQueryReader> {
  int _builds = 0;

  @override
  Widget build(BuildContext context) {
    final result = context.query<List<Post>>(
      postsQuery(ShowcaseScope.apiOf(context)),
      buildWhen:
          widget.filtered ? queryBuildWhen<List<Post>>(widget.filter) : null,
    );
    _builds += 1;
    return _ReaderRow(
      member: 'context.query',
      filter: widget.filter,
      filtered: widget.filtered,
      builds: _builds,
      facts: _queryFacts(result, 'posts', result.dataOrNull?.length ?? 0),
    );
  }
}

/// Reader 3: `watchSelectQuery`. The same entry, the count instead of the
/// list — and the same two rebuilds per refetch, because `select` decides
/// what the data is and not when the widget rebuilds.
class _WatchSelectQueryReader extends StatefulWidget {
  const _WatchSelectQueryReader({
    required this.filter,
    required this.filtered,
  });

  final Filter filter;
  final bool filtered;

  @override
  State<_WatchSelectQueryReader> createState() =>
      _WatchSelectQueryReaderState();
}

class _WatchSelectQueryReaderState extends State<_WatchSelectQueryReader>
    with QueryMixin {
  int _builds = 0;

  @override
  Widget build(BuildContext context) {
    final result = watchSelectQuery<List<Post>, int>(
      postCountQuery(ShowcaseScope.apiOf(context)),
      buildWhen: widget.filtered ? queryBuildWhen<int>(widget.filter) : null,
    );
    _builds += 1;
    return _ReaderRow(
      member: 'watchSelectQuery',
      filter: widget.filter,
      filtered: widget.filtered,
      builds: _builds,
      facts: _queryFacts(result, 'count', result.dataOrNull ?? 0),
    );
  }
}

/// Reader 4: `context.selectQuery`.
class _ContextSelectQueryReader extends StatefulWidget {
  const _ContextSelectQueryReader({
    required this.filter,
    required this.filtered,
  });

  final Filter filter;
  final bool filtered;

  @override
  State<_ContextSelectQueryReader> createState() =>
      _ContextSelectQueryReaderState();
}

class _ContextSelectQueryReaderState extends State<_ContextSelectQueryReader> {
  int _builds = 0;

  @override
  Widget build(BuildContext context) {
    final result = context.selectQuery<List<Post>, int>(
      postCountQuery(ShowcaseScope.apiOf(context)),
      buildWhen: widget.filtered ? queryBuildWhen<int>(widget.filter) : null,
    );
    _builds += 1;
    return _ReaderRow(
      member: 'context.selectQuery',
      filter: widget.filter,
      filtered: widget.filtered,
      builds: _builds,
      facts: _queryFacts(result, 'count', result.dataOrNull ?? 0),
    );
  }
}

/// The facts an infinite reader prints.
List<String> _pageFacts(QueryResult<InfiniteData<ProjectSlice, int>> result) =>
    <String>[
      'status=${result.status.name}',
      'pages=${result.dataOrNull?.pages.length ?? 0}',
    ];

/// Reader 5: `watchInfiniteQuery`, in a `QueryMixin`.
///
/// The plain half of the pair is also the one the card's `Load next` button
/// reaches, through [loadNext] — one reader pages, or four observers of one
/// entry would each ask for the next page.
class _WatchInfiniteQueryReader extends StatefulWidget {
  const _WatchInfiniteQueryReader({
    required this.filter,
    required this.filtered,
    required this.loadNext,
  });

  final Filter filter;
  final bool filtered;

  /// Non-null on exactly one of the four infinite readers.
  final Trigger? loadNext;

  @override
  State<_WatchInfiniteQueryReader> createState() =>
      _WatchInfiniteQueryReaderState();
}

class _WatchInfiniteQueryReaderState extends State<_WatchInfiniteQueryReader>
    with QueryMixin {
  int _builds = 0;
  InfiniteQueryController<ProjectSlice, int, InfiniteData<ProjectSlice, int>>?
      _controller;

  @override
  void initState() {
    super.initState();
    widget.loadNext?.addListener(_loadNext);
  }

  @override
  void dispose() {
    widget.loadNext?.removeListener(_loadNext);
    super.dispose();
  }

  void _loadNext() {
    final controller = _controller;
    if (controller != null &&
        controller.hasNextPage &&
        !controller.isFetchingNextPage) {
      controller.fetchNextPage().ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller = watchInfiniteQuery(
      pagesQuery(ShowcaseScope.apiOf(context)),
      buildWhen: widget.filtered
          ? queryBuildWhen<InfiniteData<ProjectSlice, int>>(widget.filter)
          : null,
    );
    _builds += 1;
    return _ReaderRow(
      member: 'watchInfiniteQuery',
      filter: widget.filter,
      filtered: widget.filtered,
      builds: _builds,
      facts: _pageFacts(controller.value),
    );
  }
}

/// Reader 6: `context.infiniteQuery`.
class _ContextInfiniteQueryReader extends StatefulWidget {
  const _ContextInfiniteQueryReader({
    required this.filter,
    required this.filtered,
  });

  final Filter filter;
  final bool filtered;

  @override
  State<_ContextInfiniteQueryReader> createState() =>
      _ContextInfiniteQueryReaderState();
}

class _ContextInfiniteQueryReaderState
    extends State<_ContextInfiniteQueryReader> {
  int _builds = 0;

  @override
  Widget build(BuildContext context) {
    final controller = context.infiniteQuery(
      pagesQuery(ShowcaseScope.apiOf(context)),
      buildWhen: widget.filtered
          ? queryBuildWhen<InfiniteData<ProjectSlice, int>>(widget.filter)
          : null,
    );
    _builds += 1;
    return _ReaderRow(
      member: 'context.infiniteQuery',
      filter: widget.filter,
      filtered: widget.filtered,
      builds: _builds,
      facts: _pageFacts(controller.value),
    );
  }
}

/// Reader 7: `watchMutation`, in a `QueryMixin`.
class _WatchMutationReader extends StatefulWidget {
  const _WatchMutationReader({
    required this.filter,
    required this.filtered,
    required this.run,
  });

  final Filter filter;
  final bool filtered;
  final Trigger run;

  @override
  State<_WatchMutationReader> createState() => _WatchMutationReaderState();
}

class _WatchMutationReaderState extends State<_WatchMutationReader>
    with QueryMixin {
  int _builds = 0;
  MutationController<int, int, void>? _controller;

  @override
  void initState() {
    super.initState();
    widget.run.addListener(_run);
  }

  @override
  void dispose() {
    widget.run.removeListener(_run);
    super.dispose();
  }

  void _run() => _controller?.mutate(1);

  @override
  Widget build(BuildContext context) {
    final controller = _controller = watchMutation<int, int, void>(
      incrementMutation(ShowcaseScope.apiOf(context)),
      buildWhen:
          widget.filtered ? mutationBuildWhen<int, int>(widget.filter) : null,
    );
    _builds += 1;
    return _ReaderRow(
      member: 'watchMutation',
      filter: widget.filter,
      filtered: widget.filtered,
      builds: _builds,
      facts: <String>['status=${controller.value.status.name}'],
    );
  }
}

/// Reader 8: `context.mutation`.
class _ContextMutationReader extends StatefulWidget {
  const _ContextMutationReader({
    required this.filter,
    required this.filtered,
    required this.run,
  });

  final Filter filter;
  final bool filtered;
  final Trigger run;

  @override
  State<_ContextMutationReader> createState() => _ContextMutationReaderState();
}

class _ContextMutationReaderState extends State<_ContextMutationReader> {
  int _builds = 0;
  MutationController<int, int, void>? _controller;

  @override
  void initState() {
    super.initState();
    widget.run.addListener(_run);
  }

  @override
  void dispose() {
    widget.run.removeListener(_run);
    super.dispose();
  }

  void _run() => _controller?.mutate(1);

  @override
  Widget build(BuildContext context) {
    final controller = _controller = context.mutation<int, int, void>(
      incrementMutation(ShowcaseScope.apiOf(context)),
      buildWhen:
          widget.filtered ? mutationBuildWhen<int, int>(widget.filter) : null,
    );
    _builds += 1;
    return _ReaderRow(
      member: 'context.mutation',
      filter: widget.filter,
      filtered: widget.filtered,
      builds: _builds,
      facts: <String>['status=${controller.value.status.name}'],
    );
  }
}
