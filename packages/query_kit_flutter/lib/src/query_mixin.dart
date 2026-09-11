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

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:query_kit/query_kit.dart';

import 'query_client_provider.dart';
import 'query_controller.dart';
import 'read_set.dart';

/// Adds [watchQuery] and [watchMutation] to a [State].
///
/// ```dart
/// class _TaskScreenState extends State<TaskScreen> with QueryMixin {
///   @override
///   Widget build(BuildContext context) {
///     final task = watchQuery(taskQuery(widget.id));
///     final rename = watchMutation(renameTask());
///     …
///   }
/// }
/// ```
///
/// Everything created this way is disposed with the [State], and recreated
/// when the client above it changes.
mixin QueryMixin<T extends StatefulWidget> on State<T> {
  /// This State's reads — the registry `context.query` keeps one of per
  /// reading `Element` (C47,
  /// https://github.com/KoTTi97/flutter_query/issues/56). A `State` is one
  /// reader, so it holds exactly one.
  late final ReadSet _reads = ReadSet(rebuild: _rebuild, who: 'This State');

  QueryClient? _client;

  /// The generation [_reads] is on: bumped by the post-frame sweep, so the
  /// first read of each frame rotates what the previous one held.
  int _generation = 0;
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
  /// longer read is released after the frame — unless the read carries an
  /// [id]: then the id is the read's identity and the observer follows the
  /// key, as upstream's one-observer-per-call-site does. That is what
  /// `PlaceholderData.compute((previous, _) => previous)` needs to show the
  /// previous key's data while the next loads. [id] also tells apart two
  /// reads of one key in the same widget.
  QueryResult<TData> watchQuery<TData>(
    QueryObserverOptions<TData> options, {
    Object? id,
  }) =>
      _watch<TData, TData>(options, id);

  /// [watchQuery] for a query with a `select`: a [QuerySelectOptions], whose
  /// required `select` anchors [TData] (ADR-0001).
  QueryResult<TData> watchSelectQuery<TQueryData, TData>(
    QuerySelectOptions<TQueryData, TData> options, {
    Object? id,
  }) =>
      _watch<TQueryData, TData>(options, id);

  QueryResult<TData> _watch<TQueryData, TData>(
    QueryObserverOptionsBase<TQueryData, TData> options,
    Object? id,
  ) =>
      _beginRead().readQuery<TQueryData, TData>(_currentClient, options, id);

  /// [watchQuery] for an infinite query. Returns the controller rather than
  /// the result, because paging lives on it.
  InfiniteQueryController<TPageData, TPageParam, TData>
      watchInfiniteQuery<TPageData, TPageParam, TData>(
    InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options, {
    Object? id,
  }) =>
          _beginRead().readInfiniteQuery<TPageData, TPageParam, TData>(
            _currentClient,
            options,
            id,
          );

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
  }) =>
          _beginRead().readMutation<TData, TVariables, TOnMutateResult>(
            _currentClient,
            options,
            id,
          );

  /// Every read goes through here: the client is reconciled, this frame's
  /// generation is opened if it is not open already, and the sweep that ends
  /// it is booked.
  ReadSet _beginRead() {
    // Before anything is recorded: a client switch releases what the old one
    // owned, and leaves the set empty for this build to repopulate.
    _reconcileClient();
    _reads.beginBuild(_generation);
    if (!_sweepScheduled) {
      _sweepScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) => _sweep());
    }
    return _reads;
  }

  /// Releases what the last build stopped reading, mutations included, and
  /// opens the next generation.
  void _sweep() {
    _sweepScheduled = false;
    _generation++;
    if (!mounted) {
      return;
    }
    _reads.sweep();
  }

  /// The client this State's reads run on, as [_reconcileClient] last left it.
  QueryClient get _currentClient => _client ??= queryClient;

  /// Looks the client up again and releases everything held when it changed.
  ///
  /// Run at the start of every read rather than once: [queryClient] is
  /// overridable, and the usual override — `widget.client` — changes on a
  /// plain widget update, which is not a dependency change and so never
  /// reached `didChangeDependencies`. Everything held belongs to the client
  /// it was created on, so a switch releases all of it and this build's reads
  /// recreate it on the new one (third review, 2026-09-10).
  ///
  /// Looking the client up lazily is also what lets a `State` mix this in
  /// without a provider above it: only a read needs one, and a `build` that
  /// reads nothing no longer throws for a client it never wanted (second
  /// review, 2026-09-10).
  void _reconcileClient() {
    final client = queryClient;
    if (_client != null && _client != client) {
      _reads.releaseAll();
    }
    _client = client;
  }

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _reads.releaseAll();
    super.dispose();
  }
}
