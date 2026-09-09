/// A strip of facts about one cache entry, under every feature screen.
///
/// It is how a test reads the cache from the screen: a widget test finds the
/// strip by its key and a fact by its exact text; the end-to-end suite finds
/// the semantics group `debug <label>` and the same exact text inside it. No
/// stopwatch needed to know whether a fetch happened, whether the entry is
/// stale, or how many observers hold it.
///
/// Event-driven, never ticking: it rebuilds on the cache's own events (through
/// [CacheStats], which has listened since the app started), and a text that
/// changed every second would churn the semantics tree for nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:tanstack_query_flutter/tanstack_query_flutter.dart';

import 'cache_stats.dart';
import 'scope.dart';

class QueryDebugStrip extends StatefulWidget {
  const QueryDebugStrip({
    super.key,
    required this.queryKey,
    required this.label,
  });

  /// The cache entry to watch.
  final QueryKey queryKey;

  /// A short, stable name: the semantics group is `debug <label>` and the
  /// widget key `debug-<label>`.
  final String label;

  @override
  State<QueryDebugStrip> createState() => _QueryDebugStripState();
}

class _QueryDebugStripState extends State<QueryDebugStrip> {
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

  /// Cache events arrive from wherever the change happened — a sibling's
  /// build, a microtask, a timer. Inside a frame's build phase a rebuild has
  /// to wait for the frame to end; anywhere else it can go straight in.
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

  static String _clock(DateTime? at) {
    if (at == null) {
      return '–';
    }
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    final query = client.queryCache
        .find(filters: QueryFilters(queryKey: widget.queryKey));
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
      'fetches=${scope.stats.fetchesOf(widget.queryKey)}',
      'scenario=$scenario',
    ];

    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'debug ${widget.label}',
      child: Container(
        key: ValueKey<String>('debug-${widget.label}'),
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
              'cache · ${widget.label} · ${widget.queryKey.debugString}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 2,
              children: <Widget>[
                for (final fact in facts)
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
        ),
      ),
    );
  }
}
