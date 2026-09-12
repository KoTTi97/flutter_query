/// Upstream's `simple` example: one query read in build, its states told
/// apart with a `switch` over the sealed result, and a refetch button that
/// shows `isFetching` while the background fetch runs.
///
/// Proofs (widget tests in `test/features/simple_test.dart`, end-to-end in
/// `e2e/tests/simple.spec.ts`): the skeleton gives way to the post after one
/// request; a refetch shows the "refreshing" pill while the data stays on
/// screen and bumps the strip's `fetches`; a refused first fetch ends in the
/// error state after the default retries; a refused refetch keeps the stale
/// data next to the error.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/chrome.dart';
import '../../shared/debug_strip.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';

const Feature simpleFeature = Feature(
  id: 'simple',
  title: 'Simple',
  summary: 'One query, its states, and a refetch.',
  upstream: 'simple',
);

/// The screen's one query. The options are a function, not a constant, so
/// the `queryFn` can close over the api; the key is what the cache goes by.
QueryObserverOptions<Post> firstPostQuery(ShowcaseApi api) =>
    QueryObserverOptions<Post>(
      queryKey: ShowcaseKeys.post(1),
      queryFn: (context) => api.post(1, signal: context.signal),
    );

class SimpleScreen extends StatelessWidget {
  const SimpleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    // Read in build: the widget rebuilds when the result changes.
    final post = context.query(firstPostQuery(api));

    return FeatureScaffold(
      feature: simpleFeature,
      children: <Widget>[
        SectionCard(
          title: 'Post #1',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (post.isFetching) const Pill('refreshing'),
              IconButton(
                tooltip: 'Refetch',
                onPressed: post.isFetching ? null : post.refetch,
                icon: const Icon(Icons.refresh),
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
        QueryDebugStrip(queryKey: ShowcaseKeys.post(1), label: 'post'),
      ],
    );
  }
}
