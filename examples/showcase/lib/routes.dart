/// The catalogue: every feature, in the order the home screen lists them, and
/// the route table that reaches each one by `/<id>`.
///
/// A feature that is not built yet still has its stub screen, so the
/// catalogue's shape is complete from the start and each feature's file can be
/// replaced on its own.
library;

import 'package:flutter/material.dart';

import 'features/auto_refetching/auto_refetching_screen.dart';
import 'features/basic/basic_screen.dart';
import 'features/cache_inspector/cache_inspector_screen.dart';
import 'features/cancellation/cancellation_screen.dart';
import 'features/default_query_function/default_query_function_screen.dart';
import 'features/dependent_queries/dependent_queries_screen.dart';
import 'features/diagnostics/diagnostics_screen.dart';
import 'features/focus_refetch/focus_refetch_screen.dart';
import 'features/four_call_styles/four_call_styles_screen.dart';
import 'features/global_callbacks/global_callbacks_screen.dart';
import 'features/initial_and_placeholder/initial_and_placeholder_screen.dart';
import 'features/invalidation_and_filters/invalidation_and_filters_screen.dart';
import 'features/load_more/load_more_screen.dart';
import 'features/max_pages/max_pages_screen.dart';
import 'features/mutation_state/mutation_state_screen.dart';
import 'features/mutations/mutations_screen.dart';
import 'features/offline/offline_screen.dart';
import 'features/optimistic_updates/optimistic_updates_screen.dart';
import 'features/pagination/pagination_screen.dart';
import 'features/parallel_queries/parallel_queries_screen.dart';
import 'features/playground/playground_screen.dart';
import 'features/prefetching/prefetching_screen.dart';
import 'features/query_collections/query_collections_screen.dart';
import 'features/retry/retry_screen.dart';
import 'features/select_and_sharing/select_and_sharing_screen.dart';
import 'features/simple/simple_screen.dart';
import 'features/stale_and_gc/stale_and_gc_screen.dart';
import 'home_screen.dart';
import 'shared/feature.dart';

class FeatureEntry {
  const FeatureEntry(this.feature, this.builder);

  final Feature feature;
  final WidgetBuilder builder;
}

final List<FeatureEntry> featureEntries = <FeatureEntry>[
  FeatureEntry(simpleFeature, (_) => const SimpleScreen()),
  FeatureEntry(basicFeature, (_) => const BasicScreen()),
  FeatureEntry(
      defaultQueryFunctionFeature, (_) => const DefaultQueryFunctionScreen()),
  FeatureEntry(dependentQueriesFeature, (_) => const DependentQueriesScreen()),
  FeatureEntry(parallelQueriesFeature, (_) => const ParallelQueriesScreen()),
  FeatureEntry(queryCollectionsFeature, (_) => const QueryCollectionsScreen()),
  FeatureEntry(prefetchingFeature, (_) => const PrefetchingScreen()),
  FeatureEntry(selectAndSharingFeature, (_) => const SelectAndSharingScreen()),
  FeatureEntry(
      initialAndPlaceholderFeature, (_) => const InitialAndPlaceholderScreen()),
  FeatureEntry(staleAndGcFeature, (_) => const StaleAndGcScreen()),
  FeatureEntry(paginationFeature, (_) => const PaginationScreen()),
  FeatureEntry(loadMoreFeature, (_) => const LoadMoreScreen()),
  FeatureEntry(maxPagesFeature, (_) => const MaxPagesScreen()),
  FeatureEntry(mutationsFeature, (_) => const MutationsScreen()),
  FeatureEntry(
      optimisticUpdatesFeature, (_) => const OptimisticUpdatesScreen()),
  FeatureEntry(mutationStateFeature, (_) => const MutationStateScreen()),
  FeatureEntry(playgroundFeature, (_) => const PlaygroundScreen()),
  FeatureEntry(invalidationAndFiltersFeature,
      (_) => const InvalidationAndFiltersScreen()),
  FeatureEntry(autoRefetchingFeature, (_) => const AutoRefetchingScreen()),
  FeatureEntry(retryFeature, (_) => const RetryScreen()),
  FeatureEntry(cancellationFeature, (_) => const CancellationScreen()),
  FeatureEntry(offlineFeature, (_) => const OfflineScreen()),
  FeatureEntry(focusRefetchFeature, (_) => const FocusRefetchScreen()),
  FeatureEntry(fourCallStylesFeature, (_) => const FourCallStylesScreen()),
  FeatureEntry(globalCallbacksFeature, (_) => const GlobalCallbacksScreen()),
  FeatureEntry(cacheInspectorFeature, (_) => const CacheInspectorScreen()),
  FeatureEntry(diagnosticsFeature, (_) => const DiagnosticsScreen()),
];

/// Serves `/` and every feature route. Unknown names get the home screen, so
/// a mistyped deep link never strands the app on an empty navigator.
///
/// **The fallback is deliberate, and it no longer hides anything** (C59,
/// https://github.com/KoTTi97/flutter_query/issues/66). What the review named
/// is that a silent fallback makes a missing catalogue entry look like a
/// working app; that is now `test/catalogue_test.dart`'s job — it compares the
/// five sets a feature exists in and pins every route to its own screen, so
/// the only name that can reach this branch comes from *outside* the app: a
/// typed or stale deep link. Answering one with the catalogue is the honest
/// 404 for an app whose home screen is an index, and the settings are kept so
/// the navigator still reports the route that was asked for. Asserting instead
/// was considered and refused: it would turn a human's URL typo into a red
/// screen in debug — which is every `flutter run` — while proving nothing the
/// test does not already prove.
Route<Object?> onGenerateRoute(RouteSettings settings) {
  final name = settings.name ?? '/';
  final entry = featureEntries
      .where((candidate) => candidate.feature.route == name)
      .firstOrNull;
  if (entry == null) {
    return MaterialPageRoute<Object?>(
      settings: settings,
      builder: (_) => const HomeScreen(),
    );
  }
  return MaterialPageRoute<Object?>(
    settings: settings,
    builder: entry.builder,
  );
}
