/// A strip of facts about one cache entry, under every feature screen.
///
/// It is how a test reads the cache from the screen. The strip is a
/// [SemanticsGroup] named `debug <label>` — one name for both layers, the house
/// convention (C56): a widget test asks `groupNamed('debug <label>')` and the
/// end-to-end suite `getByRole('group', { name: 'debug <label>' })`, and each
/// fact is an exact text inside it. No stopwatch needed to know whether a fetch
/// happened, whether the entry is stale, or how many observers hold it.
///
/// Event-driven, never ticking: it rebuilds on the cache's own events (through
/// [CacheListener], which is built on [CacheStats] and has listened since the
/// app started), and a text that changed every second would churn the
/// semantics tree for nothing.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'cache_listener.dart';
import 'cache_stats.dart';
import 'controls.dart';
import 'fact_group.dart';
import 'scope.dart';

class QueryDebugStrip extends StatelessWidget {
  const QueryDebugStrip({
    super.key,
    required this.queryKey,
    required this.label,
  });

  /// The cache entry to watch.
  final QueryKey queryKey;

  /// A short, stable name: the group is `debug <label>`, in both test layers.
  final String label;

  /// An entry that has never been fetched reads as an en dash rather than as a
  /// blank, so a test can tell "no timestamp" from "no fact".
  static String _clock(DateTime? at) => at == null ? '–' : hhmmss(at);

  @override
  Widget build(BuildContext context) => CacheListener(builder: _buildFacts);

  Widget _buildFacts(BuildContext context) {
    final client = QueryClientProvider.of(context);
    final query =
        client.queryCache.find(filters: QueryFilters(queryKey: queryKey));
    final scope = ShowcaseScope.of(context);
    final scenario = scope.api.scenario;

    final facts = <String>[
      if (query == null)
        'status=absent'
      else ...<String>[
        'status=${query.state.status.name}',
        'fetchStatus=${query.state.fetchStatus.name}',
        'isStale=${query.isStale()}',
        'observers=${query.observersCount}',
        'updates=${query.state.dataUpdateCount}',
        'failures=${query.state.fetchFailureCount}',
        'dataUpdatedAt=${_clock(query.state.dataUpdatedAt)}',
      ],
      'fetches=${scope.stats.fetchesOf(queryKey)}',
      'scenario=$scenario',
    ];

    final scheme = Theme.of(context).colorScheme;
    return SemanticsGroup(
      name: 'debug $label',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'cache · $label · ${queryKey.debugString}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 4),
            FactList(facts, dense: true),
          ],
        ),
      ),
    );
  }
}
