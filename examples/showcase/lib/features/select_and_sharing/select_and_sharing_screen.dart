/// Port-specific: what a reader rebuilds on, and what it does not.
///
/// One cache entry — the todos — read by five readers at once: one per call
/// style, each with a different `select`, plus a control without one. Every
/// reader counts its own builds. `builds` is every call of its build;
/// `data builds` only the calls whose selected value differed from the one
/// built before (`!=`, so identity for a list — which is exactly what
/// structural sharing is about). Upstream's guide is
/// `docs/framework/react/guides/render-optimizations.md`; the binding's rules
/// are the README's "What rebuilds, and when".
///
/// What the counters show, read from the binding's source
/// (`query_context.dart`, `query_mixin.dart`, `query_builder.dart`):
///
/// - `context.selectQuery` and `watchSelectQuery` rebuild whenever the result
///   differs from the one last built, and a `QueryResult` carries
///   `fetchStatus` and `dataUpdatedAt`: a refetch that brings back equal data
///   is still two rebuilds — fetching, then idle with a newer
///   `dataUpdatedAt`. `select` decides what the *data* comparison sees, so
///   `data builds` is the honest measure of "did my selection change", and it
///   is what the proofs assert on for those readers.
/// - `QuerySelectBuilder` with `buildWhen: previous.dataOrNull !=
///   next.dataOrNull` skips both of those rebuilds, so its `builds` counter
///   is the one that stands still. It is the only reader *on this screen*
///   that passes a predicate, not the only one that could: all four builders
///   and all eight keyless reads take the same `buildWhen`, and the
///   `build-when` screen is where each of the eight is shown doing it
///   (https://github.com/KoTTi97/flutter_query/issues/68).
/// - `ListenableBuilder` over a `QueryController` rebuilds on every
///   notification, with no equality guard at all: the same two rebuilds per
///   refetch as the context and mixin readers, and a first load of two
///   builds like everyone's — the fetch its subscription starts is already
///   in the first result it builds from.
/// - `structuralSharing` governs the cache write *and* what `select`
///   produces, as upstream's `replaceData` does (see `StructuralSharing` in
///   the core, decided on https://github.com/KoTTi97/flutter_query/issues/12,
///   corrected by the fidelity review of 2026-09-12 — until then the core ran
///   every selection through `replaceEqualDeep` regardless, and the switch
///   was invisible to all four `select` readers). With the switch off, a
///   selection is reported exactly as the selector built it, so a reader
///   moves when its own selected value is not `==` to the last one: the
///   controller's list of texts is a new instance every time and moves, while
///   the `int`, the `String` and the record do not. The fifth reader, the one
///   without `select`, is the control: with sharing off
///   the list in the cache is a new instance on every refetch, and upstream
///   hands an observer without `select` the cache's data as it is — and so
///   does the port's, now: when this screen was first measured (2026-09-09)
///   the observer ran the cache's data through `replaceEqualDeep` against
///   the last result even without a `select`, a pass upstream's
///   `createResult` does not have, which hid the `(_, next) => next` opt-out
///   from every reader. That was a library bug; it is fixed in the core
///   (the no-select branch of `createResult` passes cached data through) and
///   recorded in the core's PORTING_NOTES under "Found by the showcase". The
///   widget test that found it is green and runs with the rest.
///
/// Proofs (widget tests in `test/features/select_and_sharing_test.dart`,
/// end-to-end in `e2e/tests/select_and_sharing.spec.ts`): every reader shows
/// its selection after one `GET /api/todos`; a refetch with equal data moves
/// no reader's `data builds` and not the `buildWhen` reader's `builds`, while
/// the strip's `fetches` becomes 2; toggling todo 1 moves only the done/open
/// record (and the control); renaming todo 2 moves only the list of texts
/// (and the control); with sharing off, a refetch with equal data provably
/// reaches the cache write (an equal list, but a new instance, where sharing
/// on kept the old one) and moves the one `select` reader whose selection is
/// a new instance — the controller's list of texts — while the three whose
/// selections are `==` to the last stand still and the guard-less readers'
/// `builds` climb; and the control's `data builds` climbs with sharing off
/// and stands still once it is back on.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/chrome.dart';
import '../../shared/debug_strip.dart';
import '../../shared/fact_group.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';

const Feature selectAndSharingFeature = Feature(
  id: 'select-and-sharing',
  title: 'Select and structural sharing',
  summary: 'What a reader rebuilds on, and what it does not.',
);

// The selectors are top-level functions, not closures built in `build`: a
// tear-off of one is the same object every build, which is what lets the
// observer skip re-running it while the data has not changed — upstream's
// "extract it to a stable function reference".

int countTodos(List<Todo> todos) => todos.length;

String firstText(List<Todo> todos) => todos.isEmpty ? '' : todos.first.text;

({int done, int open}) doneAndOpen(List<Todo> todos) => (
      done: todos.where((todo) => todo.done).length,
      open: todos.where((todo) => !todo.done).length,
    );

List<String> todoTexts(List<Todo> todos) =>
    <String>[for (final todo in todos) todo.text];

/// The opt-out: what arrives is written as it is, never reconciled with what
/// the cache held — upstream's `structuralSharing: false`. The core's
/// `noStructuralSharing()` rather than a `(_, next) => next` of the screen's
/// own: a hook of one's own governs the cache write only, and only the
/// recognised opt-out turns sharing off for what `select` produces too
/// (pre-release review, 2026-09-12, F4).
final StructuralSharing<List<Todo>> keepNext = noStructuralSharing();

/// The one query every reader shares. They differ only in what they select
/// and in whether the cache write shares structure. A select is its own
/// options shape (ADR-0001), so the raw reader has [rawTodosQuery].
QuerySelectOptions<List<Todo>, T> todosQuery<T>(
  ShowcaseApi api, {
  required T Function(List<Todo> todos) select,
  bool sharing = true,
}) =>
    QuerySelectOptions<List<Todo>, T>(
      queryKey: ShowcaseKeys.todos,
      queryFn: (context) => api.todos(signal: context.signal),
      select: select,
      structuralSharing: sharing ? null : keepNext,
    );

/// [todosQuery] without a select: the same key, the same fetch, the list as
/// the cache holds it.
QueryObserverOptions<List<Todo>> rawTodosQuery(
  ShowcaseApi api, {
  bool sharing = true,
}) =>
    QueryObserverOptions<List<Todo>>(
      queryKey: ShowcaseKeys.todos,
      queryFn: (context) => api.todos(signal: context.signal),
      structuralSharing: sharing ? null : keepNext,
    );

typedef _TodoPatch = ({int id, String? text, bool? done});

class SelectAndSharingScreen extends StatefulWidget {
  const SelectAndSharingScreen({super.key});

  @override
  State<SelectAndSharingScreen> createState() => _SelectAndSharingScreenState();
}

class _SelectAndSharingScreenState extends State<SelectAndSharingScreen> {
  bool _sharingOff = false;

  @override
  Widget build(BuildContext context) {
    final sharing = !_sharingOff;
    return FeatureScaffold(
      feature: selectAndSharingFeature,
      children: <Widget>[
        SectionCard(
          title: 'One cache entry: the todos',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _Actions(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Structural sharing off'),
                value: _sharingOff,
                onChanged: (value) => setState(() => _sharingOff = value),
              ),
            ],
          ),
        ),
        // Above the readers, not below: the end-to-end suite reads the
        // semantics tree, and a lazily built list only has the rows in view.
        QueryDebugStrip(queryKey: ShowcaseKeys.todos, label: 'todos'),
        SectionCard(
          title: 'Five readers, one entry',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _ContextReader(sharing: sharing),
              _BuilderReader(sharing: sharing),
              _MixinReader(sharing: sharing),
              _ControllerReader(sharing: sharing),
              _RawReader(sharing: sharing),
            ],
          ),
        ),
      ],
    );
  }
}

/// The buttons, and the mutation behind two of them. A widget of its own
/// because a mutation rebuilds the widget that reads it on every state
/// change, and that widget must not be the readers' parent.
class _Actions extends StatefulWidget {
  const _Actions();

  @override
  State<_Actions> createState() => _ActionsState();
}

class _ActionsState extends State<_Actions> {
  int _renames = 0;

  @override
  Widget build(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    final client = QueryClientProvider.of(context);
    final update = context.mutation(
      MutationOptions.simple<Todo, _TodoPatch>(
        mutationFn: (patch) =>
            api.updateTodo(patch.id, text: patch.text, done: patch.done),
        onSuccess: (_, __, ___) => client.invalidateQueries(
          filters: QueryFilters(queryKey: ShowcaseKeys.todos),
        ),
      ),
    );
    final busy = update.value.isPending;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        _ActionButton(
          'Refetch',
          enabled: !busy,
          onPressed: () => client
              .refetchQueries(
                filters: QueryFilters(queryKey: ShowcaseKeys.todos),
              )
              .ignore(),
        ),
        _ActionButton(
          'Toggle todo 1',
          enabled: !busy,
          onPressed: () {
            // Read, not watched: the button needs the current `done` once,
            // at the tap, and must not become a reader of its own.
            final todo = client
                .getQueryData<List<Todo>>(ShowcaseKeys.todos)
                ?.where((todo) => todo.id == 1)
                .firstOrNull;
            if (todo != null) {
              update.mutate((id: 1, text: null, done: !todo.done));
            }
          },
        ),
        _ActionButton(
          'Rename todo 2',
          enabled: !busy,
          onPressed: () {
            _renames += 1;
            update
                .mutate((id: 2, text: 'Renamed todo 2 x$_renames', done: null));
          },
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(
    this.label, {
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  // The visible label is the button's accessible name; the tooltip is for
  // hovering only, so it stays out of the semantics tree rather than
  // doubling the text.
  @override
  Widget build(BuildContext context) => Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: FilledButton.tonal(
          onPressed: enabled ? onPressed : null,
          child: Text(label),
        ),
      );
}

/// An honest build count. [builds] is every build; [dataBuilds] only the
/// ones whose selected value differed from the one built before — `!=`, so
/// value equality for a scalar or a record and identity for a list.
class _Counter {
  int builds = 0;
  int dataBuilds = 0;
  Object? _lastData;

  void record(Object? data) {
    builds += 1;
    if (data != _lastData) {
      dataBuilds += 1;
      _lastData = data;
    }
  }
}

/// One reader's row: its style, what it selects, the selected value as exact
/// `key=value` texts, and its two counters. A semantics group named
/// `reader <id>`, so a browser-driving test can scope to one reader the way
/// it scopes to a debug strip.
class _ReaderRow extends StatelessWidget {
  const _ReaderRow({
    required this.id,
    required this.style,
    required this.selection,
    required this.counter,
    required this.result,
    required this.facts,
  });

  final String id;
  final String style;
  final String selection;
  final _Counter counter;
  final QueryResult<Object?> result;

  /// The selected value as exact texts, given the data.
  final List<String> Function() facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = switch (result) {
      QueryPending() => const <String>['pending'],
      QueryError(:final error, staleData: null) => <String>['error=$error'],
      QuerySuccess() || QueryError() => facts(),
    };
    return SemanticsGroup(
      name: 'reader $id',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(style, style: theme.textTheme.labelLarge),
                ),
                Text(selection, style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 2),
            Wrap(
              spacing: 12,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                FactList(values, dense: true),
                Pill('builds=${counter.builds}'),
                Pill(
                  'data builds=${counter.dataBuilds}',
                  color: theme.colorScheme.tertiary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Reader 1: `context.selectQuery`, selecting the count.
class _ContextReader extends StatefulWidget {
  const _ContextReader({required this.sharing});

  final bool sharing;

  @override
  State<_ContextReader> createState() => _ContextReaderState();
}

class _ContextReaderState extends State<_ContextReader> {
  final _Counter _counter = _Counter();

  @override
  Widget build(BuildContext context) {
    final result = context.selectQuery<List<Todo>, int>(
      todosQuery(
        ShowcaseScope.apiOf(context),
        select: countTodos,
        sharing: widget.sharing,
      ),
    );
    _counter.record(result.dataOrNull);
    return _ReaderRow(
      id: 'context',
      style: 'context.selectQuery',
      selection: 'int: the count',
      counter: _counter,
      result: result,
      facts: () => <String>['count=${result.dataOrNull}'],
    );
  }
}

/// Reader 2: `QuerySelectBuilder`, selecting the first todo's text, with a
/// `buildWhen` that ignores everything but the data.
class _BuilderReader extends StatefulWidget {
  const _BuilderReader({required this.sharing});

  final bool sharing;

  @override
  State<_BuilderReader> createState() => _BuilderReaderState();
}

class _BuilderReaderState extends State<_BuilderReader> {
  final _Counter _counter = _Counter();

  @override
  Widget build(BuildContext context) => QuerySelectBuilder<List<Todo>, String>(
        options: todosQuery(
          ShowcaseScope.apiOf(context),
          select: firstText,
          sharing: widget.sharing,
        ),
        buildWhen: (previous, next) => previous.dataOrNull != next.dataOrNull,
        builder: (context, result) {
          _counter.record(result.dataOrNull);
          return _ReaderRow(
            id: 'builder',
            style: 'QuerySelectBuilder + buildWhen',
            selection: 'String: the first text',
            counter: _counter,
            result: result,
            facts: () => <String>['first=${result.dataOrNull}'],
          );
        },
      );
}

/// Reader 3: `QueryMixin.watchSelectQuery`, selecting a done/open record.
class _MixinReader extends StatefulWidget {
  const _MixinReader({required this.sharing});

  final bool sharing;

  @override
  State<_MixinReader> createState() => _MixinReaderState();
}

class _MixinReaderState extends State<_MixinReader> with QueryMixin {
  final _Counter _counter = _Counter();

  @override
  Widget build(BuildContext context) {
    final result = watchSelectQuery<List<Todo>, ({int done, int open})>(
      todosQuery(
        ShowcaseScope.apiOf(context),
        select: doneAndOpen,
        sharing: widget.sharing,
      ),
    );
    _counter.record(result.dataOrNull);
    return _ReaderRow(
      id: 'mixin',
      style: 'QueryMixin.watchSelectQuery',
      selection: 'record: done and open',
      counter: _counter,
      result: result,
      facts: () {
        final data = result.dataOrNull!;
        return <String>['done=${data.done}', 'open=${data.open}'];
      },
    );
  }
}

/// Reader 4: a `QueryController` selecting the list of texts, read through
/// a `ListenableBuilder`.
class _ControllerReader extends StatefulWidget {
  const _ControllerReader({required this.sharing});

  final bool sharing;

  @override
  State<_ControllerReader> createState() => _ControllerReaderState();
}

class _ControllerReaderState extends State<_ControllerReader> {
  final _Counter _counter = _Counter();
  QueryController<List<Todo>, List<String>>? _controller;

  QuerySelectOptions<List<Todo>, List<String>> get _options => todosQuery(
        ShowcaseScope.apiOf(context),
        select: todoTexts,
        sharing: widget.sharing,
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The controller is created here, not in `initState`: it needs the
    // provider's client, which is an inherited widget.
    final client = QueryClientProvider.of(context);
    if (_controller?.client != client) {
      _controller?.dispose();
      _controller = QueryController<List<Todo>, List<String>>(client, _options);
    }
  }

  @override
  void didUpdateWidget(_ControllerReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sharing != widget.sharing) {
      _controller!.setOptions(_options);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final result = controller.value;
        _counter.record(result.dataOrNull);
        return _ReaderRow(
          id: 'controller',
          style: 'QueryController + ListenableBuilder',
          selection: 'List<String>: the texts',
          counter: _counter,
          result: result,
          facts: () => result.dataOrNull!,
        );
      },
    );
  }
}

/// Reader 5, the control: no `select`, the cache's own list. The only reader
/// whose selected value is the thing `structuralSharing` decides about.
class _RawReader extends StatefulWidget {
  const _RawReader({required this.sharing});

  final bool sharing;

  @override
  State<_RawReader> createState() => _RawReaderState();
}

class _RawReaderState extends State<_RawReader> {
  final _Counter _counter = _Counter();

  @override
  Widget build(BuildContext context) => QueryBuilder<List<Todo>>(
        options: rawTodosQuery(
          ShowcaseScope.apiOf(context),
          sharing: widget.sharing,
        ),
        builder: (context, result) {
          _counter.record(result.dataOrNull);
          return _ReaderRow(
            id: 'raw',
            style: 'QueryBuilder, no select',
            selection: "List<Todo>: the cache's own list",
            counter: _counter,
            result: result,
            facts: () => <String>['length=${result.dataOrNull!.length}'],
          );
        },
      );
}
