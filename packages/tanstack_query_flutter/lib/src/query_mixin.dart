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
/// released after the frame, the way `context.query` releases it — a mutation
/// likewise. A `State` that stops calling `watchQuery` *altogether* gives no
/// signal, so its last observers stay until it is disposed; keep a
/// conditional read in its own widget, and the condition becomes that
/// widget's presence in the tree.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:tanstack_query_core/tanstack_query_core.dart';

import 'query_client_provider.dart';
import 'query_controller.dart';
import 'repeat_read.dart';

/// One controller the State holds — a query's or a mutation's — and the value
/// its last build read. See `_Entry` in `query_context.dart`: a notification
/// carrying the value already built is not worth a `setState`.
class _WatchEntry {
  _WatchEntry(this.controller, this.rebuild) {
    controller.addListener(_onChanged);
  }

  final ValueListenable<Object?> controller;
  final VoidCallback rebuild;
  Object? built;

  T read<T>() => (built = controller.value) as T;

  void _onChanged() {
    if (controller.value != built) {
      rebuild();
    }
  }

  void dispose() {
    controller.removeListener(_onChanged);
    (controller as ChangeNotifier).dispose();
  }
}

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
  /// Controllers by identity: `(key, types…, id)` for a query,
  /// `(#mutation, id or key, types…)` for a mutation.
  final Map<Object, _WatchEntry> _entries = <Object, _WatchEntry>{};
  QueryClient? _client;

  // The same epoch bookkeeping `QueryScopeElement` keeps per reader: what the
  // current build read, what earlier builds held, and a sweep after the frame
  // that releases the difference.
  Set<Object> _current = <Object>{};
  Set<Object> _pending = <Object>{};
  bool _sweepScheduled = false;

  /// The client these observers run on. Defaults to the nearest provider;
  /// override it to run against a client of your own.
  QueryClient get queryClient => QueryClientProvider.of(context);

  /// Subscribes to [options]'s query and returns its current result.
  ///
  /// The first call for a key creates the observer; later calls with the
  /// same key reuse it and apply the new options — options built inline are
  /// re-applied on every build, as upstream re-applies them on every render,
  /// and the observer decides what, if anything, actually changed. A
  /// *different* key is a different observer, and the one for the key no
  /// longer read is released after the frame. [id] tells apart two reads of
  /// one key in the same widget.
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
    final entry = _entryFor(
      identity,
      () => QueryController<TQueryData, TData>(_currentClient, options),
    );
    final controller = entry.controller as QueryController<TQueryData, TData>;
    final before = repeat ? controller.value : null;
    // Unconditional, as upstream re-applies options on every render: the
    // observer itself decides whether anything actually changed, and
    // options built inline carry a fresh closure every build anyway.
    controller.setOptions(options);
    final result = entry.read<QueryResult<TData>>();
    debugCheckRepeatRead(repeat, before, result, identity, 'This State');
    return result;
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
    final entry = _entryFor(
      identity,
      () => InfiniteQueryController<TPageData, TPageParam, TData>(
        _currentClient,
        options,
      ),
    );
    final controller = entry.controller
        as InfiniteQueryController<TPageData, TPageParam, TData>;
    final before = repeat ? controller.value : null;
    controller.setInfiniteOptions(options);
    debugCheckRepeatRead(
      repeat,
      before,
      entry.read<QueryResult<TData>>(),
      identity,
      'This State',
    );
    return controller;
  }

  _WatchEntry _entryFor(
    Object identity,
    ValueListenable<Object?> Function() create,
  ) {
    _current.add(identity);
    return _entries.putIfAbsent(
      identity,
      () => _WatchEntry(create(), _rebuild),
    );
  }

  /// Subscribes to a mutation and returns its controller.
  ///
  /// One is identified by [id], else by the options' `mutationKey`, each
  /// together with its three types; without either, by the types alone — so
  /// pass [id] when one widget runs two mutations of the same shape. Released
  /// after the frame once a build stops reading it, the way a query is.
  MutationController<TData, TVariables, TOnMutateResult>
      watchMutation<TData, TVariables, TOnMutateResult>(
    MutationOptions<TData, TVariables, TOnMutateResult> options, {
    Object? id,
  }) {
    // Never the function itself: a closure built in `build` is a new object
    // every build, and the types are part of the identity (see
    // `context.mutation` on both).
    final identity = (
      #mutation,
      id ?? options.mutationKey,
      TData,
      TVariables,
      TOnMutateResult,
    );
    final current = _startEpoch();
    assert(() {
      if (id == null &&
          options.mutationKey == null &&
          current.contains(identity)) {
        throw FlutterError(
          'This State read two mutations of the shape '
          '${(TData, TVariables, TOnMutateResult)} in one build. They would '
          'share one controller, and whichever was read last would run for '
          'both. Give each an `id:`.',
        );
      }
      return true;
    }());
    final existed = _entries.containsKey(identity);
    final entry = _entryFor(
      identity,
      () => MutationController<TData, TVariables, TOnMutateResult>(
        _currentClient,
        options,
      ),
    );
    final controller = entry.controller
        as MutationController<TData, TVariables, TOnMutateResult>;
    if (existed) {
      controller.setOptions(options);
    }
    entry.read<Object?>();
    return controller;
  }

  /// The first read of a build: what earlier builds held becomes provisional,
  /// and whatever this build does not read again is released after the frame.
  Set<Object> _startEpoch() {
    if (!_sweepScheduled) {
      _sweepScheduled = true;
      _pending = <Object>{..._pending, ..._current};
      _current = <Object>{};
      SchedulerBinding.instance.addPostFrameCallback((_) => _sweep());
    }
    return _current;
  }

  /// Releases what the last build stopped reading, mutations included.
  void _sweep() {
    _sweepScheduled = false;
    if (!mounted) {
      return;
    }
    for (final identity in _pending.difference(_current)) {
      _entries.remove(identity)?.dispose();
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
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
    _current = <Object>{};
    _pending = <Object>{};
  }

  @override
  void dispose() {
    _disposeAll();
    super.dispose();
  }
}
