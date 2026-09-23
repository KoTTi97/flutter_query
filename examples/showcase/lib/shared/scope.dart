/// Hands the screens their [ShowcaseApi], the cache statistics, and how the
/// app is being run.
library;

import 'package:flutter/widgets.dart';

import 'api.dart';
import 'cache_stats.dart';

/// The api every screen reads, the scenario it is tagged with, the counters
/// the debug strips show, and the two facts about this run that change the
/// frame around a screen: whether it is [embed]ded in the documentation site,
/// and whether its backend is the [inMemory] one.
class ShowcaseScope extends InheritedWidget {
  const ShowcaseScope({
    super.key,
    required this.api,
    required this.stats,
    this.embed = false,
    this.inMemory = false,
    required super.child,
  });

  final ShowcaseApi api;
  final CacheStats stats;

  /// One feature, alone, inside the documentation site's `<LiveDemo>` frame:
  /// no back button, no catalogue to return to (`?embed=1`, `main.dart`).
  final bool embed;

  /// The backend is `lib/demo/in_memory_backend.dart`, in this very tab
  /// (`--dart-define=QK_BACKEND=inmemory`), not the express server.
  final bool inMemory;

  static ShowcaseScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShowcaseScope>()!;

  static ShowcaseApi apiOf(BuildContext context) => of(context).api;

  /// What the app bar says about the backend: the scenario against the
  /// server, `in-memory backend` without one, and nothing in an embedded
  /// frame that has a server — a reader of the docs has no use for an id.
  String? get backendLabel => inMemory
      ? 'in-memory backend'
      : embed
          ? null
          : 'scenario ${api.scenario}';

  @override
  bool updateShouldNotify(ShowcaseScope oldWidget) =>
      api != oldWidget.api ||
      stats != oldWidget.stats ||
      embed != oldWidget.embed ||
      inMemory != oldWidget.inMemory;
}
