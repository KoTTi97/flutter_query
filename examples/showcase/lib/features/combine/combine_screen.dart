/// `combine`: what three queries of three different types amount to together.
///
/// Port-specific. Upstream's `useQueries({ combine })` types a heterogeneous
/// tuple, which a Dart `List` cannot; here the combination is a function over
/// a **record of results** — `(post, comments, counter).combine(...)` — and
/// nothing new observes anything. The three reads are plain `context.query`
/// calls, a `Post`, a `List<Comment>` and an `int`; they rebuild the widget,
/// and `combine` says what they amount to: a sealed `CombinedResult`, read
/// with one exhaustive `switch` over `CombinedPending`, `CombinedError` and
/// `CombinedData`. Controllers combine the same way under a
/// `ListenableBuilder` over `Listenable.merge`.
///
/// The rules the screen walks through, in the library's order: a source that
/// failed **with nothing to show** makes the whole a `CombinedError` — even
/// while another source is still loading, because waiting does not cure it —
/// and `retry()` refetches the failed sources only; otherwise a source without
/// data makes it `CombinedPending`; otherwise the combiner runs, and a
/// background refetch that failed keeps its stale data in the combination and
/// shows up as `refetchError`. `isFetching` is "any source is".
///
/// `The post read` is the failure: set to `is refused`, every read of the post
/// asks the backend for a 500 (`?fail=500`) until it is switched back. The
/// knob is read when the request goes out, so it governs a `Reset` or a
/// `Retry` as much as a refetch. All three queries say `RetryPolicy.never`, so
/// a refusal is an error at once rather than after three more attempts.
///
/// The combiner runs behind a `CombineMemo`, a `State` field: `combines=` is
/// how often it really ran and `builds=` how often `combine` was called. A
/// refetch that changed nothing hands every source the identical instance it
/// had — structural sharing — and the combiner is skipped.
///
/// Proofs (widget tests in `test/features/combine_test.dart`, end-to-end in
/// `e2e/tests/combine.spec.ts`): the whole is `state=pending` while one source
/// is still out although the other two have data, and `state=data` once it
/// lands; a post refused on first load is `state=error` with the backend's
/// message — also while the counter is still loading — and `Retry` sends one
/// more read of the post and none of the comments; a refused background
/// refetch keeps `state=data` and every value, and says
/// `refetchError=Requested: 500`; `isFetching=true` while any source is out;
/// and a refetch that changed nothing builds again without combining again,
/// while an incremented counter combines once more.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/chrome.dart';
import '../../shared/controls.dart';
import '../../shared/debug_strip.dart';
import '../../shared/fact_group.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';

const Feature combineFeature = Feature(
  id: 'combine',
  title: 'Combine',
  summary: 'Three queries of three types, read as one result.',
);

/// The post the screen is about.
const int combinedPostId = 1;

/// The screen's own entries, under one prefix so `Reset` names them all.
QueryKey get combineKey => QueryKey(const <Object?>['combine']);
QueryKey get combinePostKey => combineKey.append(const <Object?>['post']);
QueryKey get combineCommentsKey =>
    combineKey.append(const <Object?>['comments']);
QueryKey get combineCounterKey => combineKey.append(const <Object?>['counter']);

/// What the combiner makes of the three: a record, so two equal combinations
/// are equal and the memo's structural sharing keeps the first.
typedef Overview = ({String title, int comments, int counter});

class CombineScreen extends StatefulWidget {
  const CombineScreen({super.key});

  @override
  State<CombineScreen> createState() => _CombineScreenState();
}

class _CombineScreenState extends State<CombineScreen> {
  /// Next to the reads it serves, as the guide says: one per call site.
  final CombineMemo<Overview> _memo = CombineMemo<Overview>();

  /// Plain fields, not state: both are written during `build` and printed by
  /// the same build.
  int _builds = 0;
  int _combines = 0;

  bool _refusePost = false;

  /// Reads the knob when the request goes out, not when the options were
  /// built: a `Reset` or a `Retry` runs the query function the entry already
  /// holds, and that closure must see the knob as it is now.
  QueryObserverOptions<Post> _postQuery(ShowcaseApi api) =>
      QueryObserverOptions<Post>(
        queryKey: combinePostKey,
        queryFn: (context) => api.post(
          combinedPostId,
          signal: context.signal,
          fail: _refusePost ? 500 : null,
        ),
        retry: RetryPolicy.never,
      );

  QueryObserverOptions<List<Comment>> _commentsQuery(ShowcaseApi api) =>
      QueryObserverOptions<List<Comment>>(
        queryKey: combineCommentsKey,
        queryFn: (context) =>
            api.comments(combinedPostId, signal: context.signal),
        retry: RetryPolicy.never,
      );

  QueryObserverOptions<int> _counterQuery(ShowcaseApi api) =>
      QueryObserverOptions<int>(
        queryKey: combineCounterKey,
        queryFn: (context) => api.counter(signal: context.signal),
        retry: RetryPolicy.never,
      );

  /// The one write on the screen: it changes what the counter read answers,
  /// so the next combination has something new to combine.
  MutationOptions<int, int, void> _incrementMutation(
    ShowcaseApi api,
    QueryClient client,
  ) =>
      MutationOptions.simple<int, int>(
        mutationFn: (by) => api.increment(by: by),
        onSuccess: (_, __, ___) => client.invalidateQueries(
          filters: QueryFilters(queryKey: combineCounterKey),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    final client = QueryClientProvider.of(context);
    final increment = context.mutation(_incrementMutation(api, client));

    final combined = (
      context.query(_postQuery(api), id: 'post'),
      context.query(_commentsQuery(api), id: 'comments'),
      context.query(_counterQuery(api), id: 'counter'),
    ).combine<Overview>(
      (post, comments, counter) {
        _combines += 1;
        return (
          title: post.title,
          comments: comments.length,
          counter: counter,
        );
      },
      memo: _memo,
    );
    _builds += 1;

    return FeatureScaffold(
      feature: combineFeature,
      children: <Widget>[
        SectionCard(
          title: 'Controls',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              knob<bool>(
                context,
                title: 'The post read',
                name: 'post knob',
                choices: const <(String, bool)>[
                  ('answers', false),
                  ('is refused', true),
                ],
                selected: _refusePost,
                onChanged: (value) => setState(() => _refusePost = value),
              ),
              const SizedBox(height: 12),
              Toolbar(
                children: <Widget>[
                  // `refetch()` is every source's; `retry()`, on the error
                  // below, is only the failed ones'.
                  ActionButton(
                    label: 'Refetch all',
                    onPressed: combined.isFetching ? null : combined.refetch,
                  ),
                  ActionButton(
                    label: 'Reset',
                    onPressed: () => client.resetQueries(
                      filters: QueryFilters(queryKey: combineKey),
                    ),
                  ),
                  ActionButton(
                    label: 'Increment counter',
                    onPressed: increment.value.isPending
                        ? null
                        : () => increment.mutate(1),
                  ),
                ],
              ),
            ],
          ),
        ),
        QueryDebugStrip(queryKey: combinePostKey, label: 'post'),
        QueryDebugStrip(queryKey: combineCommentsKey, label: 'comments'),
        QueryDebugStrip(queryKey: combineCounterKey, label: 'counter'),
        SectionCard(
          title: 'Post, comments and counter',
          trailing: combined.isFetching ? const Pill('fetching') : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FactGroup(
                name: 'combined',
                facts: <String>[
                  // Spelled out per variant, and exhaustively: a fourth
                  // variant would be a compile error here, not a blank fact.
                  switch (combined) {
                    CombinedPending() => 'state=pending',
                    CombinedError() => 'state=error',
                    CombinedData() => 'state=data',
                  },
                  'isFetching=${combined.isFetching}',
                  'builds=$_builds',
                  'combines=$_combines',
                ],
              ),
              const SizedBox(height: 12),
              switch (combined) {
                CombinedPending() => const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SkeletonBox(height: 20, width: 240),
                      SizedBox(height: 8),
                      SkeletonBox(width: 160),
                    ],
                  ),
                CombinedError(:final error) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Notice('$error', error: true),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ActionButton(
                          label: 'Retry',
                          filled: true,
                          onPressed:
                              combined.isFetching ? null : combined.retry,
                        ),
                      ),
                    ],
                  ),
                CombinedData(:final data, :final refetchError) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        data.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      FactGroup(
                        name: 'overview',
                        facts: <String>[
                          'comments=${data.comments}',
                          'counter=${data.counter}',
                          'refetchError=${refetchError ?? 'none'}',
                        ],
                      ),
                      if (refetchError != null) ...<Widget>[
                        const SizedBox(height: 8),
                        // The content stays: what failed is the refresh.
                        Notice('Could not refresh: $refetchError', error: true),
                      ],
                    ],
                  ),
              },
            ],
          ),
        ),
      ],
    );
  }
}
