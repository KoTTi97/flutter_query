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
import 'package:flutter/widgets.dart';
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
///
/// **Only the reader's own build opens a generation.** A read can also come
/// from a callback that runs *later* with the reader's context — a nested
/// `ValueListenableBuilder`, `LayoutBuilder` or `AnimatedBuilder` using the
/// outer `context` or `watchQuery`. Such a callback re-runs without the
/// reader's `build`, and a generation opened by it alone released everything
/// `build` had read (release review 2026-09-23, BIND-1). So a read made
/// outside the reader's own build is *additive*: it joins whatever the
/// reader holds and releases nothing, and what such a callback stops reading
/// is released at the reader's own next build or unmount. [beginBuild] tells
/// the two apart.
///
/// "Own build" is a `ComponentElement`'s notion — a `StatelessWidget`'s or a
/// `State`'s `build`. A reader that is not one runs its callback wholesale
/// instead: a `LayoutBuilder`'s element (an `OrientationBuilder` hands its
/// builder the `LayoutBuilder`'s context too) calls its builder during
/// layout, never while dirty, so every run of it is that reader's build and
/// opens the frame's generation — what it stopped reading goes after the
/// frame (second pass, V-B-1). The exception is an element that builds its
/// children *piecemeal*: a `ListView.builder`'s sliver, a grid's, a
/// `PageView`'s, a `ListWheelScrollView`'s, a two-dimensional viewport's.
/// Its item builder runs for the rows scrolling in, not for the rows still
/// shown, so neither rule is right for it — per frame releases the visible
/// rows, additive holds every row ever built. Reading through that context
/// is a debug-mode error that names the fix, a widget per row
/// ([debugCheckReader]); release builds keep the per-frame rule, which is
/// bounded (second pass, V-B-2).
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

  /// Identities read during the frame [_seenIn] names, own build or not —
  /// what the two same-build checks ask about. Kept apart from [_current],
  /// which an additive read does not reset.
  Set<Object> _seen = <Object>{};
  int _seenIn = -1;

  /// The mutations the reader's own build read in the frame [_seenIn] names,
  /// with the functions the first read of each ran — what the debug
  /// ambiguity check compares a repeat against. Only written in debug
  /// builds.
  Map<Object, (Object?, Object?)> _mutationsRead =
      <Object, (Object?, Object?)>{};

  /// The element the last [beginBuild] was for.
  Element? _reader;

  /// The widget the reader's element had when a generation was last opened.
  /// A parent handing it a new one rebuilds it with `Element.dirty` false.
  Widget? _builtFor;

  /// Opens [generation] if it is not open already *and* [reader] is building
  /// itself: what earlier builds held becomes provisional, and whatever this
  /// build does not read again is released by [sweep]. A read from anywhere
  /// else — a nested builder running with [reader]'s context — is additive
  /// and opens nothing (see the class doc).
  ///
  /// "Building itself" is Flutter's own bookkeeping, the same in every build
  /// mode: `Element.dirty` stays true for the whole of a `build()` that
  /// `markNeedsBuild` — `setState`, a dependency change, the first build —
  /// caused, and is cleared before the children, and so every nested
  /// builder, are built. The one own build that does not start dirty is a
  /// parent handing the element a new widget (`update` forces the rebuild),
  /// and that one is told apart by the widget having changed since the last
  /// generation opened. A nested callback sees neither. A [reader] that is
  /// no `ComponentElement` has no `build` to tell apart from its callbacks:
  /// every read through it is its own build (V-B-1).
  ///
  /// Without the release a screen that switches from one key to another
  /// would stay subscribed to the key it no longer shows.
  void beginBuild(int generation, Element reader) {
    if (_seenIn != generation) {
      _seenIn = generation;
      _seen = <Object>{};
      _mutationsRead = <Object, (Object?, Object?)>{};
    }
    _reader = reader;
    final widget = reader.widget;
    final ownBuild = reader is! ComponentElement ||
        reader.dirty ||
        !identical(widget, _builtFor);
    if (!ownBuild || _generation == generation) {
      return;
    }
    _builtFor = widget;
    _generation = generation;
    _pending = <Object>{..._pending, ..._current};
    _current = <Object>{};
  }

  /// Throws, in debug builds, when [reader] builds its children piecemeal —
  /// the `context` a `ListView.builder`, `GridView.builder`,
  /// `PageView.builder`, `ListWheelScrollView.useDelegate` or a
  /// two-dimensional scroll view hands its item builder. That context is the
  /// whole list's, not the row's, and no rule over it both keeps the rows on
  /// screen and lets go of the ones scrolled away (see the class doc).
  /// [call] names the read in the message. Called before anything is
  /// recorded. Release builds skip it and treat every read as the list's own
  /// build: bounded, but a row still on screen can lose its subscription
  /// when others scroll in.
  static void debugCheckReader(Element reader, String call) {
    assert(() {
      if (reader is SliverMultiBoxAdaptorElement ||
          reader is ListWheelElement ||
          reader is TwoDimensionalChildManager) {
        throw FlutterError.fromParts([
          ErrorSummary(
            '$call was called with the context an item builder was given.',
          ),
          ErrorDescription(
            'That context belongs to ${reader.widget.runtimeType}, which '
            'builds its rows piecemeal as they scroll in: it is the whole '
            'list, not the row, and cannot tell which row a read belongs to. '
            'Its reads would either be released while their row is still '
            'shown or never be released at all.',
          ),
          ErrorHint(
            'Give each row a widget of its own and read inside its build — '
            '`itemBuilder: (_, i) => TaskTile(ids[i])` with the read in '
            "`TaskTile.build`. Each row's reads then live and go with it.",
          ),
        ]);
      }
      return true;
    }());
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
    final repeat = _seen.contains(identity);
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
    final repeat = _seen.contains(identity);
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
      // Two mutations of one identity in one build without `id` would share
      // a controller, and the second `setOptions` would win: a tap on
      // "archive" running the delete. A `mutationKey` does not rule that
      // out: upstream's is a *category* — `setMutationDefaults`, the
      // `isMutating` and `MutationState` filters, prefix matching — and two
      // different mutations under `['todos']` are ordinary there (release
      // review 2026-09-23, B1-1). Distinct keys still tell two reads apart;
      // only an `id` names one.
      //
      // What is *not* ambiguous (second pass, V-B-4): a read outside the
      // reader's own build — a nested builder re-reading what `build` read
      // — is the same call site's controller handed on, and a repeat whose
      // mutation function is the same (`==`: one stored options object, a
      // tear-off, a top-level function, or none at all when
      // `setMutationDefaults` supplies it) runs the same thing whichever
      // read wins. A function literal is a new object every time it is
      // evaluated, so a getter building one per read looks exactly like two
      // different mutations and still asserts.
      final reader = _reader;
      final ownBuild = reader is! ComponentElement || reader.debugDoingBuild;
      if (id == null && ownBuild) {
        final fns = (options.mutationFn, options.mutationFnWithContext);
        final first = _mutationsRead[identity];
        if (first == null) {
          _mutationsRead[identity] = fns;
        } else if (first != fns) {
          final key = options.mutationKey;
          throw FlutterError(
            '$who read two mutations of the shape '
            '${(TData, TVariables, TOnMutateResult)}'
            '${key == null ? '' : ' and the mutationKey $key'} with different '
            'mutation functions in one build. They would share one '
            'controller, and whichever was read last would run for both. A '
            'mutationKey is a category, not a name: give each read an `id:`. '
            'If both reads are one mutation, read it once and share the '
            'controller, or keep its options (or its function) in a field — '
            'a function literal is a new function every time it is built.',
          );
        }
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
    _seen.add(identity);
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
    _seen = <Object>{};
  }
}
