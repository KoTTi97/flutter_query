/// Side effects over existing controllers, without rebuilding their
/// children. See [QueryListener], [InfiniteQueryListener] and
/// [MutationListener].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:query_kit/query_kit.dart';

import 'query_controller.dart';

/// Whether a transition from [previous] to [next] should run a listener's
/// side effect.
///
/// ```dart
/// // Only when the query has just failed:
/// listenWhen: (previous, next) =>
///     previous is! QueryError && next is QueryError,
/// ```
///
/// {@category Side effects}
typedef ListenWhen<T> = bool Function(T previous, T next);

/// Runs a side effect — a snackbar, a navigation, a log line — when a
/// query's result changes, without rebuilding [child].
///
/// Listens to a [QueryController] you own; the widget never disposes it.
///
/// ```dart
/// QueryListener(
///   controller: tasks,
///   listenWhen: (previous, next) =>
///       previous is! QueryError && next is QueryError,
///   listener: (context, result) => ScaffoldMessenger.of(context).showSnackBar(
///     const SnackBar(content: Text('Could not refresh the tasks')),
///   ),
///   child: const TaskList(),
/// )
/// ```
///
/// When [listener] runs:
///
/// * **Not on mount.** Only a later change of the controller's value is a
///   transition.
/// * **Outside the build phase**, in a microtask after the notification, so
///   it may show a dialog, navigate or call `setState`. Each transition is
///   delivered with the value it carried, not the latest one.
/// * **Once per notification, with the latest value.** Two cache writes
///   inside one `notifyManager.batch` are one transition to the second
///   value, not two.
/// * **[listenWhen] sees every transition**, and a rejected one still moves
///   the "previous" the next one is compared against.
///
/// An error thrown by [listener] is reported through `FlutterError`, not
/// thrown into the tree. A different controller on a later build is
/// listened to from then on; transitions of the old one still queued are
/// dropped.
///
/// {@category Side effects}
class QueryListener<TQueryData, TData>
    extends _ResultListener<QueryResult<TData>> {
  /// Listens to [controller] without owning it, and runs [listener] for
  /// each accepted transition — see the class doc for the timing.
  const QueryListener({
    super.key,
    required QueryController<TQueryData, TData> controller,
    required super.listener,
    super.listenWhen,
    required super.child,
  }) : super(controller: controller);
}

/// Runs a side effect when an infinite query's result changes, without
/// rebuilding [child].
///
/// The same contract as [QueryListener], over an [InfiniteQueryController]
/// you own:
///
/// ```dart
/// InfiniteQueryListener(
///   controller: feed,
///   listenWhen: (previous, next) => next is QueryError,
///   listener: (context, result) => ScaffoldMessenger.of(context).showSnackBar(
///     const SnackBar(content: Text('Could not load more posts')),
///   ),
///   child: const FeedList(),
/// )
/// ```
///
/// A transition is a change of the result; a paging flag that changes on
/// its own (`isFetchingNextPage`, say) is not one.
///
/// {@category Side effects}
class InfiniteQueryListener<TPageData, TPageParam, TData>
    extends _ResultListener<QueryResult<TData>> {
  /// Listens to [controller] without owning it, and runs [listener] for
  /// each accepted transition — see [QueryListener] for the timing.
  const InfiniteQueryListener({
    super.key,
    required InfiniteQueryController<TPageData, TPageParam, TData> controller,
    required super.listener,
    super.listenWhen,
    required super.child,
  }) : super(controller: controller);
}

/// Runs a side effect when a mutation's result changes, without rebuilding
/// [child].
///
/// Listens to a [MutationController] you own — usually the same one the UI
/// calls `mutate` on. The same contract as [QueryListener]:
///
/// ```dart
/// MutationListener(
///   controller: rename,
///   listener: (context, result) {
///     if (result case MutationError(:final error)) {
///       ScaffoldMessenger.of(context).showSnackBar(
///         SnackBar(content: Text('Could not rename: $error')),
///       );
///     }
///   },
///   child: RenameForm(rename: rename),
/// )
/// ```
///
/// For a side effect of one particular call, the per-call callbacks of
/// `MutationController.mutate` are the alternative; this widget hears every
/// run of the controller.
///
/// {@category Side effects}
class MutationListener<TData, TVariables, TOnMutateResult>
    extends _ResultListener<MutationResult<TData, TVariables>> {
  /// Listens to [controller] without owning it, and runs [listener] for
  /// each accepted transition — see [QueryListener] for the timing. Nothing
  /// runs on mount.
  const MutationListener({
    super.key,
    required MutationController<TData, TVariables, TOnMutateResult> controller,
    required super.listener,
    super.listenWhen,
    required super.child,
  }) : super(controller: controller);
}

abstract class _ResultListener<T> extends StatefulWidget {
  const _ResultListener({
    super.key,
    required this.controller,
    required this.listener,
    this.listenWhen,
    required this.child,
  });

  /// The controller to listen to. Borrowed: whoever created it disposes it,
  /// and a different one on a later build is listened to from then on.
  final ValueListenable<T> controller;

  /// The side effect, run outside the build phase for each accepted
  /// transition with the value that transition carried. Not run on mount.
  /// An error it throws is reported through `FlutterError`.
  final void Function(BuildContext context, T result) listener;

  /// Which transitions run [listener]; `null` accepts every change. A
  /// rejected transition still becomes the `previous` of the next one.
  final ListenWhen<T>? listenWhen;

  /// The subtree, returned unchanged: a transition never rebuilds it.
  final Widget child;

  @override
  State<_ResultListener<T>> createState() => _ResultListenerState<T>();
}

class _ResultListenerState<T> extends State<_ResultListener<T>> {
  late T _previous;
  bool _attaching = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _attaching = true;
    widget.controller.addListener(_onResult);
    _previous = widget.controller.value;
    _attaching = false;
  }

  void _onResult() {
    if (_attaching) return;
    final next = widget.controller.value;
    final previous = _previous;
    _previous = next;
    if (previous == next) return;
    final generation = _generation;
    final listener = widget.listener;
    final listenWhen = widget.listenWhen;
    // A microtask also covers the initial root build, whose scheduler phase
    // is idle. Capture each transition rather than reading the latest value
    // when the callback runs.
    scheduleMicrotask(() {
      if (!mounted || generation != _generation) return;
      try {
        if (listenWhen?.call(previous, next) ?? true) listener(context, next);
      } catch (error, stackTrace) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'query_kit_flutter',
          context:
              ErrorDescription('while delivering a controller side effect'),
        ));
      }
    });
  }

  @override
  void didUpdateWidget(covariant _ResultListener<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _generation++;
      oldWidget.controller.removeListener(_onResult);
      _attach();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    _generation++;
    widget.controller.removeListener(_onResult);
    super.dispose();
  }
}
