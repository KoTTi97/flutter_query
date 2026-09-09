/// The mixin way to read a query: call it in `build`, flat, no nesting.
///
/// One of four equal call styles
/// (https://github.com/KoTTi97/flutter_query/issues/21). Reads like a hook, but
/// entries are identified by their [QueryKey] and types rather than by call
/// order, so there is nothing like the rules of hooks: calling [watchQuery]
/// inside an `if` is fine.
///
/// What that identity does *not* cover: two reads of one key with different
/// selectors of the same output type, or two mutations of the same shape. Pass
/// `id` to tell those apart.
///
/// **Release.** A key read in the previous build but not in this one is
/// released after the frame, the way `context.query` releases it. A `State`
/// that stops calling `watchQuery` *altogether* gives no signal, so its last
/// observers stay until it is disposed; keep a conditional read in its own
/// widget, and the condition becomes that widget's presence in the tree.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:tanstack_query_core/tanstack_query_core.dart';

import 'query_client_provider.dart';
import 'query_controller.dart';

/// Adds [watchQuery] and [watchMutation] to a [State].
///
/// ```dart
/// class _SensorScreenState extends State<SensorScreen> with QueryMixin {
///   @override
///   Widget build(BuildContext context) {
///     final sensor = watchQuery(sensorQuery(widget.id));
///     final rename = watchMutation(renameSensor());
///     …
///   }
/// }
/// ```
///
/// Everything created this way is disposed with the [State], and recreated
/// when the client above it changes.
mixin QueryMixin<T extends StatefulWidget> on State<T> {
  final Map<Object, ChangeNotifier> _queries = <Object, ChangeNotifier>{};
  final Map<Object, MutationController<Object?, Object?, Object?>> _mutations =
      <Object, MutationController<Object?, Object?, Object?>>{};
  QueryClient? _client;

  // The same epoch bookkeeping `QueryScopeElement` keeps per reader: what the
  // current build read, what earlier builds held, and a sweep after the frame
  // that releases the difference.
  Set<Object> _current = <Object>{};
  Set<Object> _pending = <Object>{};
  Set<Object> _mutationsByShape = <Object>{};
  bool _sweepScheduled = false;

  /// The client these observers run on. Defaults to the nearest provider;
  /// override it to run against a client of your own.
  QueryClient get queryClient => QueryClientProvider.of(context);

  /// Subscribes to [options]'s query and returns its current result.
  ///
  /// The first call for a key creates the observer; later calls with the
  /// same key reuse it and apply the new options. A *different* key is a
  /// different observer, and the one for the key no longer read is released
  /// after the frame. [id] tells apart two reads of one key in the same
  /// widget.
  QueryResult<TData> watchQuery<TData>(
    QueryObserverOptions<TData, TData> options, {
    Object? id,
  }) =>
      watchSelectQuery<TData, TData>(options, id: id);

  /// [watchQuery] for a query with a `select`.
  QueryResult<TData> watchSelectQuery<TQueryData, TData>(
    QueryObserverOptions<TQueryData, TData> options, {
    Object? id,
  }) {
    final identity = (options.queryKey!, TQueryData, TData, id);
    final repeat = _startEpoch().contains(identity);
    final controller = _query<QueryController<TQueryData, TData>>(
      identity,
      () => QueryController<TQueryData, TData>(_currentClient, options),
    );
    final before = repeat ? controller.value : null;
    // Unconditional, as upstream re-applies options on every render: the
    // observer itself decides whether anything actually changed, and
    // options built inline carry a fresh closure every build anyway.
    controller.setOptions(options);
    _debugCheckRepeatRead(repeat, before, controller.value, identity);
    return controller.value;
  }

  /// [watchQuery] for an infinite query. Returns the controller rather than
  /// the result, because paging lives on it.
  InfiniteQueryController<TPageData, TPageParam, TData>
      watchInfiniteQuery<TPageData, TPageParam, TData>(
    InfiniteQueryObserverOptions<TPageData, TPageParam, TData> options, {
    Object? id,
  }) {
    final identity = (options.queryKey, TPageData, TPageParam, TData, id);
    final repeat = _startEpoch().contains(identity);
    final controller =
        _query<InfiniteQueryController<TPageData, TPageParam, TData>>(
      identity,
      () => InfiniteQueryController<TPageData, TPageParam, TData>(
        _currentClient,
        options,
      ),
    );
    final before = repeat ? controller.value : null;
    controller.setInfiniteOptions(options);
    _debugCheckRepeatRead(repeat, before, controller.value, identity);
    return controller;
  }

  C _query<C extends ChangeNotifier>(Object identity, C Function() create) {
    _current.add(identity);
    final existing = _queries[identity];
    if (existing != null) {
      return existing as C;
    }
    final controller = create()..addListener(_rebuild);
    _queries[identity] = controller;
    return controller;
  }

  /// See `QueryScopeElement._debugCheckRepeatRead`: the same identity read
  /// twice in one build with options that yield different results would flip
  /// the observer on every build, and rebuild forever.
  static void _debugCheckRepeatRead(
    bool repeat,
    Object? before,
    Object? after,
    Object identity,
  ) {
    assert(() {
      if (repeat && before != after) {
        throw FlutterError(
          'This State read the query $identity twice in one build with '
          'options that produce different results — most likely two '
          'different `select`s of the same output type. Give each read its '
          'own `id:` so they get observers of their own.',
        );
      }
      return true;
    }());
  }

  /// Subscribes to a mutation and returns its controller.
  ///
  /// One is identified by [id], else by the options' `mutationKey`, else by
  /// its three types — so pass [id] when one widget runs two mutations of the
  /// same shape.
  MutationController<TData, TVariables, TOnMutateResult>
      watchMutation<TData, TVariables, TOnMutateResult>(
    MutationOptions<TData, TVariables, TOnMutateResult> options, {
    Object? id,
  }) {
    // Never the function itself: a closure built in `build` is a new object
    // every build (see `context.mutation`).
    final identity =
        id ?? options.mutationKey ?? (TData, TVariables, TOnMutateResult);
    _startEpoch();
    assert(() {
      if (id == null &&
          options.mutationKey == null &&
          !_mutationsByShape.add(identity)) {
        throw FlutterError(
          'This State read two mutations of the shape $identity in one '
          'build. They would share one controller, and whichever was read '
          'last would run for both. Give each an `id:`.',
        );
      }
      return true;
    }());
    final existing = _mutations[identity];
    if (existing != null) {
      final controller = existing
          as MutationController<TData, TVariables, TOnMutateResult>
        ..setOptions(options);
      return controller;
    }

    final controller = MutationController<TData, TVariables, TOnMutateResult>(
      _currentClient,
      options,
    )..addListener(_rebuild);
    _mutations[identity] =
        controller as MutationController<Object?, Object?, Object?>;
    return controller;
  }

  /// The first read of a build: what earlier builds held becomes provisional,
  /// and whatever this build does not read again is released after the frame.
  Set<Object> _startEpoch() {
    if (!_sweepScheduled) {
      _sweepScheduled = true;
      _pending = <Object>{..._pending, ..._current};
      _current = <Object>{};
      _mutationsByShape = <Object>{};
      SchedulerBinding.instance.addPostFrameCallback((_) => _sweep());
    }
    return _current;
  }

  void _sweep() {
    _sweepScheduled = false;
    if (!mounted) {
      return;
    }
    for (final identity in _pending.difference(_current)) {
      _queries.remove(identity)
        ?..removeListener(_rebuild)
        ..dispose();
    }
    _pending = <Object>{};
  }

  QueryClient get _currentClient => _client ??= queryClient;

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reading the client here is what subscribes the State to the provider.
    // When it hands out a different client, everything held belongs to the
    // old one; `build` recreates it on the new one.
    final client = queryClient;
    if (_client != null && _client != client) {
      _disposeAll();
    }
    _client = client;
  }

  void _disposeAll() {
    for (final controller in _queries.values) {
      controller
        ..removeListener(_rebuild)
        ..dispose();
    }
    _queries.clear();
    for (final controller in _mutations.values) {
      controller
        ..removeListener(_rebuild)
        ..dispose();
    }
    _mutations.clear();
    _current = <Object>{};
    _pending = <Object>{};
  }

  @override
  void dispose() {
    _disposeAll();
    super.dispose();
  }
}
