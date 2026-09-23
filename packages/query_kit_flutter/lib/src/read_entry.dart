/// The rebuild decision: one controller a reader watches, the value its last
/// build read, and whether a notification is worth a frame.
///
/// "Read the value and its `observedStateOf`, rebuild only if it moved, then
/// ask `buildWhen`" is one decision shared by every call style, because each
/// owes a reader the same guarantee: nothing rebuilds for a notification
/// carrying what the reader is already showing.
///
/// What the owners differ in, and therefore what stays outside:
///
/// * **Who is told, and whether the reader is still there.** [ReadEntry.new]
///   takes the callback: `setState` behind `mounted` for a `State`,
///   `markNeedsBuild` behind its own check for an `Element`.
/// * **What owns the controller's identity.** A builder widget creates one
///   controller from its own options; `ReadSet` keeps a map of them by the
///   identity a keyless read was made under, and releases what a build
///   stopped asking for.
library;

import 'package:flutter/foundation.dart';

import 'query_controller.dart';

/// Whether a reader should rebuild for a change from [previous] to [current]
/// — the `buildWhen` every call style takes.
///
/// It is asked only when the value really changed: a notification carrying
/// what the reader is already showing never rebuilds, predicate or not. When
/// it returns `false`, the reader keeps showing [previous], and the next
/// change is compared against that.
///
/// ```dart
/// // Rebuild only when the task's name changes:
/// final task = context.query(
///   taskQuery(id),
///   buildWhen: (previous, current) =>
///       previous.dataOrNull?.name != current.dataOrNull?.name,
/// );
/// ```
///
/// {@category Reading queries}
typedef BuildWhen<T> = bool Function(T previous, T current);

/// One controller a reader watches, and what its last build read from it.
///
/// The entry listens to [controller] from the moment it is created until
/// [dispose], and calls [rebuild] for every notification that carries
/// something the reader is not already showing. [read] is the other half: a
/// build says what it is showing, so the next notification can be compared
/// against it.
class ReadEntry<T> {
  /// Watches [controller] and calls [rebuild] when a notification of its is
  /// worth a frame.
  ///
  /// Whether the reader is still there is [rebuild]'s business: a `State`
  /// checks `mounted`, an `Element` checks its own.
  ReadEntry(this.controller, this.rebuild) {
    controller.addListener(_onChanged);
  }

  /// The controller this entry watches, owned by this entry: [dispose]
  /// disposes it.
  final ValueListenable<T> controller;

  /// Called for a notification that moved something the reader can see.
  final VoidCallback rebuild;

  /// The value the last build read, valid while [_recorded].
  late T _built;

  /// Whether a build has read this entry yet. Nothing built means anything
  /// the controller says is news.
  bool _recorded = false;

  /// What [observedStateOf] said when [_built] was recorded: the result for
  /// every controller but an infinite query's, which keeps its paging flags
  /// beside the result.
  Object? _builtState;

  /// The predicate the last build handed over, asked once the value is known
  /// to have moved.
  BuildWhen<T>? _buildWhen;

  /// Reads the controller's current value and records it as this build's,
  /// both halves, together with the [buildWhen] this build filters by.
  ///
  /// A build re-states its predicate because a widget's may change between
  /// builds; a reader with no predicate simply leaves it out.
  T read({BuildWhen<T>? buildWhen}) {
    _buildWhen = buildWhen;
    _builtState = observedStateOf(controller);
    _recorded = true;
    return _built = controller.value;
  }

  /// Whether what the controller says now is worth a frame, given what
  /// [read] last recorded.
  ///
  /// A value equal to the one last built is skipped before [BuildWhen] is
  /// even asked: the first build reads the result straight after the
  /// subscribe started the fetch, and the observer's notification about that
  /// very fetch arrives after the frame — a rebuild with nothing new in it.
  /// Results carry value equality, so "nothing new" is `==`.
  bool _shouldRebuild() {
    if (!_recorded) {
      return true;
    }
    if (observedStateOf(controller) == _builtState) {
      return false;
    }
    final current = controller.value;
    if (current == _built) {
      // Only the half that lives beside the result moved — the paging flags
      // of an infinite query. There is nothing for [BuildWhen] to compare,
      // and the reader is showing the stale half right now.
      return true;
    }
    final buildWhen = _buildWhen;
    return buildWhen == null || buildWhen(_built, current);
  }

  void _onChanged() {
    if (_shouldRebuild()) {
      rebuild();
    }
  }

  /// Stops watching and disposes the controller.
  void dispose() {
    controller.removeListener(_onChanged);
    (controller as ChangeNotifier).dispose();
  }
}
