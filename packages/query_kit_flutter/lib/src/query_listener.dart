/// Side effects over existing controllers, without rebuilding their children.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:query_kit/query_kit.dart';

import 'query_controller.dart';

/// Whether a result transition should invoke a side effect.
typedef ListenWhen<T> = bool Function(T previous, T next);

/// Listens to query transitions without owning the supplied controller.
class QueryListener<TQueryData, TData>
    extends _ResultListener<QueryResult<TData>> {
  /// Does not invoke [listener] on mount. Each later notification of the
  /// controller whose value differs from the last one seen is a transition,
  /// and [listenWhen] sees each of them — a rejected transition still moves
  /// the "previous" the next one is compared against. What a notification
  /// carries is the controller's *latest* value, as with any
  /// `ValueListenable`: two cache writes inside one `notifyManager.batch`
  /// are one transition to the second value, not two (ninth review,
  /// 2026-09-10, C19).
  const QueryListener({
    super.key,
    required QueryController<TQueryData, TData> controller,
    required super.listener,
    super.listenWhen,
    required super.child,
  }) : super(controller: controller);
}

/// Listens to infinite-query transitions on an existing paging controller.
class InfiniteQueryListener<TPageData, TPageParam, TData>
    extends _ResultListener<QueryResult<TData>> {
  /// Observes [controller] without disposing it or rebuilding [child].
  const InfiniteQueryListener({
    super.key,
    required InfiniteQueryController<TPageData, TPageParam, TData> controller,
    required super.listener,
    super.listenWhen,
    required super.child,
  }) : super(controller: controller);
}

/// Listens to the same mutation controller that the UI executes.
class MutationListener<TData, TVariables, TOnMutateResult>
    extends _ResultListener<MutationResult<TData, TVariables>> {
  /// Observes [controller] without owning it. No initial callback is emitted.
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

  /// The borrowed controller, disposed by its owner.
  final ValueListenable<T> controller;

  /// Runs outside the build phase for each accepted transition.
  final void Function(BuildContext context, T result) listener;

  /// Filters transitions; omission accepts every changed result.
  final ListenWhen<T>? listenWhen;

  /// Returned unchanged; controller events never rebuild this child.
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
