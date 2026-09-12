/// The reads one reader holds: the registry behind `QueryMixin` and
/// `context.query` alike.
///
/// Both keyless call styles
/// (https://github.com/KoTTi97/flutter_query/issues/21) work the same way —
/// a read is identified by its key and types unless it carries an `id`, the
/// controller for an identity lives as long as builds keep asking for it, and
/// what a build stops asking for is released after the frame. That was written
/// out twice until C47
/// (https://github.com/KoTTi97/flutter_query/issues/56), and each of the three
/// fixes of 2026-09-10 had to be applied to both copies.
///
/// What the two callers actually differ in is two things, and they are this
/// module's two constructor arguments: **how a reader is told to rebuild**
/// (`setState` for a `State`, `markNeedsBuild` for an `Element`) and **what a
/// debug message calls it** ("This State", "This widget"). Everything else —
/// the identity tuples, the entries, the epoch, the release — is
/// implementation.
///
/// What deliberately stayed outside:
///
/// * **The client.** Each read takes one, because the two owners resolve it
///   differently: the mixin re-reads an overridable `queryClient` on every
///   read, the scope takes its `InheritedWidget`'s.
/// * **Scheduling the sweep.** [sweep] releases; *when* it runs is the
///   owner's, because a `State` sweeps one set behind a `mounted` check and
///   the scope sweeps every reader's and drops the ones that left the tree.
/// * **`detached`.** It is a fact about a *collection* of read sets — which
///   elements Flutter said stopped depending on the scope — not about one, and
///   a `State` has no equivalent signal at all. It stayed on
///   `QueryScopeElement`.
/// * **The rebuild decision.** What a read records and when a notification is
///   worth a frame is [ReadEntry], which the builder widgets watch their one
///   controller through as well (C48,
///   https://github.com/KoTTi97/flutter_query/issues/57). The `buildWhen:`
///   the two keyless styles gained with C49
///   (https://github.com/KoTTi97/flutter_query/issues/55) is that entry's own
///   argument: all three reads below take one and hand it over, so every call
///   style — a query's four and a mutation's four
///   (https://github.com/KoTTi97/flutter_query/issues/67) — filters through
///   one implementation.
library;

import 'package:flutter/foundation.dart';
import 'package:query_kit/query_kit.dart';

import 'query_controller.dart';
import 'read_entry.dart';
import 'repeat_read.dart';

/// One controller a reader holds — a query's or a mutation's — and the value
/// its last build read. The value type is [Object] here because one set holds
/// a query's, an infinite query's and a mutation's side by side; every read
/// knows the type it asked for.
typedef _Entry = ReadEntry<Object?>;

/// Everything one reader — a `State` with `QueryMixin`, or one `Element`
/// reading through `context.query` — holds between builds.
///
/// A build is a *generation*: [beginBuild] opens one, the `read*` methods
/// record what it asked for, and [sweep] after the frame releases what the
/// generation stopped asking for. The owner supplies the generation counter
/// and bumps it when it sweeps, so several readers of one scope share a frame.
class ReadSet {
  /// [rebuild] is how this reader is told its controllers moved; [who] names
  /// it in the two debug messages ("This State", "This widget").
  ReadSet({required this.rebuild, required this.who});

  /// Called when a controller this set holds reports a change worth a frame.
  /// Whether the reader is still there is this callback's business: a `State`
  /// checks `mounted`, an `Element` checks its own.
  final VoidCallback rebuild;

  /// The reader's name in [debugCheckRepeatRead]'s message and in the
  /// mutation-ambiguity assertion.
  final String who;

  /// Controllers by identity: `(key, types…)` for a query without an `id`,
  /// `(#query, types…, id)` for one with — so a read that carries an `id`
  /// keeps its observer across a key change — and `(#mutation, id or key,
  /// types…)` for a mutation.
  final Map<Object, _Entry> _entries = <Object, _Entry>{};

  /// Identities read during the current generation.
  Set<Object> _current = <Object>{};

  /// Identities held during the previous generation, still to be reconciled.
  Set<Object> _pending = <Object>{};

  /// The generation [_current] belongs to. Below every counter an owner can
  /// pass, so the first [beginBuild] always opens one.
  int _generation = -1;

  /// Opens [generation] if it is not open already: what earlier builds held
  /// becomes provisional, and whatever this build does not read again is
  /// released by [sweep].
  ///
  /// Without this a screen that switches from one key to another would stay
  /// subscribed to the key it no longer shows.
  void beginBuild(int generation) {
    if (_generation == generation) {
      return;
    }
    _generation = generation;
    _pending = <Object>{..._pending, ..._current};
    _current = <Object>{};
  }

  /// Creates or reuses this reader's observer for [options] and returns its
  /// current result. Covers a plain read and a `select` one alike: the caller
  /// anchors [TQueryData] and [TData] (ADR-0001).
  QueryResult<TData> readQuery<TQueryData, TData>(
    QueryClient client,
    QueryObserverOptionsBase<TQueryData, TData> options,
    Object? id, {
    BuildWhen<QueryResult<TData>>? buildWhen,
  }) {
    final identity = id == null
        ? (options.queryKey, TQueryData, TData)
        : (#query, TQueryData, TData, id);
    final repeat = _current.contains(identity);
    final entry = _entryFor(
      identity,
      () => QueryController<TQueryData, TData>(client, options),
    );
    final controller = entry.controller as QueryController<TQueryData, TData>;
    final before = repeat ? controller.value : null;
    // Unconditional, as upstream re-applies options on every render: the
    // observer itself decides whether anything actually changed, and options
    // built inline carry a fresh closure every build anyway.
    controller.setOptions(options);
    final result =
        entry.read(buildWhen: _erased(buildWhen)) as QueryResult<TData>;
    debugCheckRepeatRead(repeat, before, result, identity, who);
    return result;
  }

  /// The infinite twin of [readQuery]. Returns the controller rather than the
  /// result, because paging lives on it.
  InfiniteQueryController<TPageData, TPageParam, TData>
      readInfiniteQuery<TPageData, TPageParam, TData>(
    QueryClient client,
    InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options,
    Object? id, {
    BuildWhen<QueryResult<TData>>? buildWhen,
  }) {
    final identity = id == null
        ? (options.queryKey, TPageData, TPageParam, TData)
        : (#infinite, TPageData, TPageParam, TData, id);
    final repeat = _current.contains(identity);
    final entry = _entryFor(
      identity,
      () => InfiniteQueryController<TPageData, TPageParam, TData>(
        client,
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
      entry.read(buildWhen: _erased(buildWhen)) as QueryResult<TData>,
      identity,
      who,
    );
    return controller;
  }

  /// A mutation controller owned by this reader.
  MutationController<TData, TVariables, TOnMutateResult>
      readMutation<TData, TVariables, TOnMutateResult>(
    QueryClient client,
    MutationOptions<TData, TVariables, TOnMutateResult> options,
    Object? id, {
    BuildWhen<MutationResult<TData, TVariables>>? buildWhen,
  }) {
    // Never the function itself: a closure built in `build` is a new object
    // every build, and a controller keyed on it would be replaced — idle
    // again — by the very rebuild its own result caused. The types are part
    // of the identity the way they are for a query: the same `mutationKey`
    // read with two type triples is two controllers, not a failed cast
    // (fourth review, 2026-09-09).
    final identity = (
      #mutation,
      id ?? options.mutationKey,
      TData,
      TVariables,
      TOnMutateResult,
    );
    assert(() {
      // Two mutations of one shape in one build without `id` would share a
      // controller, and the second `setOptions` would win: a tap on
      // "archive" running the delete. Only the type-triple fallback is
      // ambiguous; an `id` or a `mutationKey` names the mutation.
      if (id == null &&
          options.mutationKey == null &&
          _current.contains(identity)) {
        throw FlutterError(
          '$who read two mutations of the shape '
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
        client,
        options,
      ),
    );
    final controller = entry.controller
        as MutationController<TData, TVariables, TOnMutateResult>;
    if (existed) {
      controller.setOptions(options);
    }
    // The predicate is the only filter a mutation read has, and unlike a
    // query's it is asked about every notification: a `MutationController`
    // has no `observedState` beside its value, so [ReadEntry]'s equality
    // gate is the same comparison `MutationObserver` already made before it
    // notified at all (C49 follow-on,
    // https://github.com/KoTTi97/flutter_query/issues/67).
    entry.read(buildWhen: _erased(buildWhen));
    return controller;
  }

  /// A caller's predicate as the untyped entries take it.
  ///
  /// One set holds a query's, an infinite query's and a mutation's controller
  /// side by side, so its entries are `ReadEntry<Object?>` and a
  /// `BuildWhen<QueryResult<TData>>` is not one of theirs — function types are
  /// contravariant in their parameters. The casts are safe by construction:
  /// an entry only ever compares values it read from the controller this read
  /// just typed.
  static BuildWhen<Object?>? _erased<T>(BuildWhen<T>? buildWhen) =>
      buildWhen == null
          ? null
          : (previous, current) => buildWhen(previous as T, current as T);

  _Entry _entryFor(
    Object identity,
    ValueListenable<Object?> Function() create,
  ) {
    _current.add(identity);
    return _entries.putIfAbsent(identity, () => _Entry(create(), rebuild));
  }

  /// Releases what the last generation stopped reading, mutations included.
  /// Called by the owner after the frame.
  void sweep() {
    for (final identity in _pending.difference(_current)) {
      _entries.remove(identity)?.dispose();
    }
    _pending = <Object>{};
  }

  /// Releases everything and forgets every read. The set is empty afterwards
  /// and usable again — which is what a client switch needs, since the reader
  /// that triggered it is in the middle of the build that will repopulate it.
  void releaseAll() {
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
    _current = <Object>{};
    _pending = <Object>{};
  }
}
