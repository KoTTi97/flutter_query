/// Hands the screens their [ShowcaseApi] and the cache statistics.
library;

import 'package:flutter/widgets.dart';

import 'api.dart';
import 'cache_stats.dart';

/// The api every screen reads, the scenario it is tagged with, and the
/// counters the debug strips show.
class ShowcaseScope extends InheritedWidget {
  const ShowcaseScope({
    super.key,
    required this.api,
    required this.stats,
    required super.child,
  });

  final ShowcaseApi api;
  final CacheStats stats;

  static ShowcaseScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShowcaseScope>()!;

  static ShowcaseApi apiOf(BuildContext context) => of(context).api;

  @override
  bool updateShouldNotify(ShowcaseScope oldWidget) =>
      api != oldWidget.api || stats != oldWidget.stats;
}
