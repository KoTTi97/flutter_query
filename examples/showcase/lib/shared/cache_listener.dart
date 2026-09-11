/// The phase-aware rebuild the feature screens are driven by, and the widget
/// that wraps it.
///
/// A cache event, a focus change, a global callback, a cancel signal — the
/// showcase is driven by events raised from wherever the change happened: a
/// resolved future, a microtask, a sibling's build, a gc timer. Inside a
/// frame's build phase a `setState` is not allowed and the rebuild has to wait
/// for the frame to end; anywhere else it can go straight in.
///
/// Eleven screens wrote that dance out by hand, byte for byte, and one wrote a
/// fourth variant of it; the review's C55 counted them. It lives here now, in
/// two layers: [PhaseSafeRebuild] for a [State] that owns its own
/// subscription, and [CacheListener] for the common case of "rebuild this
/// subtree whenever the query cache says anything".
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'cache_stats.dart';
import 'scope.dart';

/// Gives a [State] a `setState` that is safe to call from any scheduler phase.
///
/// Mix it in wherever a screen is driven by an event it does not control the
/// timing of, and call [scheduleRebuild] instead of `setState(() {})`.
mixin PhaseSafeRebuild<T extends StatefulWidget> on State<T> {
  bool _rebuildScheduled = false;

  /// Marks this widget dirty — now, or at the end of the frame being built.
  ///
  /// Calls made while one is already pending coalesce into that one, so an
  /// event storm inside a single frame costs one rebuild.
  ///
  /// Safe to hand to a [Listenable]: a tear-off of the same instance method on
  /// the same object compares equal, so `removeListener(scheduleRebuild)`
  /// undoes `addListener(scheduleRebuild)`.
  void scheduleRebuild() {
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
}

/// Rebuilds its subtree on every event of the query cache.
///
/// The events come from [CacheStats], which has listened since the app started
/// and already filters out the ones that say nothing about a query's state —
/// without that filter a screen that rebuilds on cache events feeds itself,
/// because every build re-applies a reader's options.
///
/// Use it where the thing on screen reads the cache but holds no observer of
/// its own: a `prefetched` pill, a "queries in flight" count, a row that shows
/// what `getQueryData` currently returns.
class CacheListener extends StatefulWidget {
  const CacheListener({super.key, required this.builder});

  /// Built afresh on every cache event, and on nothing else.
  final WidgetBuilder builder;

  @override
  State<CacheListener> createState() => _CacheListenerState();
}

class _CacheListenerState extends State<CacheListener>
    with PhaseSafeRebuild<CacheListener> {
  CacheStats? _stats;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final stats = ShowcaseScope.of(context).stats;
    if (stats != _stats) {
      _stats?.removeListener(scheduleRebuild);
      _stats = stats..addListener(scheduleRebuild);
    }
  }

  @override
  void dispose() {
    _stats?.removeListener(scheduleRebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
