/// What every feature screen says about itself: the catalogue's row.
library;

import 'package:flutter/foundation.dart';

/// One entry of the catalogue. A screen declares its own as a `const` next to
/// its widget; `routes.dart` lists them.
@immutable
class Feature {
  const Feature({
    required this.id,
    required this.title,
    required this.summary,
    this.upstream,
  });

  /// The route segment: `/simple`, `/stale-and-gc`. One segment only —
  /// Flutter's initial-route expansion falls back to `/` on nested paths.
  final String id;

  final String title;

  /// One sentence on what the screen shows.
  final String summary;

  /// The upstream example this mirrors (`query/examples/react/<name>`), or
  /// `null` for a port-specific screen.
  final String? upstream;

  String get route => '/$id';
}
