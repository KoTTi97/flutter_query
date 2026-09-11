/// Upstream's `playground` example on the showcase backend: a todo list, an
/// editor for one todo, and four knobs a reader turns while the queries are
/// live — stale time, gc time, latency and error rate. Everything on the
/// screen is read through `QueryMixin`: `watchQuery` for the list and the
/// editor's todo, `watchMutation` for the add and the patch.
///
/// Where the knobs go. Stale time and gc time go into the **client's**
/// defaults with `setDefaultOptions`, the way upstream's playground sets
/// them, on top of whatever the app had (`getDefaultOptions()`, merged, so
/// the other defaults survive). A live observer keeps its defaulted options
/// until its next `setOptions`, and the mixin re-applies options on every
/// build, so a `setState` after the change is what carries the new defaults
/// to every reader on the screen — verified by the widget tests, no
/// re-keying needed. The screen snapshots the defaults on entry and restores
/// them in `dispose`. Latency and error rate go to the **backend's** scenario
/// through `configureScenario`; the scenario is this run's own world, so no
/// other screen sees them, and both are reset to zero in `dispose`. The
/// `backend` facts show the values the backend has acknowledged, which is
/// what a test waits for before it relies on them.
///
/// The editor's query is `['todos', <id>]`. The api has no single-todo GET,
/// so its `queryFn` fetches the list and picks the todo — a fetch of its own,
/// so the entry has its own lifecycle: it is seeded from the cached list with
/// `InitialData.compute` and dated with the list's `dataUpdatedAt` (so under
/// a non-zero stale time opening the editor costs no request), it is
/// refetched by `Invalidate everything` like the list, and once the editor is
/// closed its observer is gone and the gc time decides when it is dropped.
/// After a rename or a completion the PATCH's answer is written to that entry
/// with `setQueryData`, and only the list itself is invalidated (`exact`),
/// so a mutation costs exactly one `GET /api/todos`.
///
/// Both queries run with `retryDelay: RetryDelay.fixed(300 ms)` instead of
/// the client's 1/2/4 s backoff, so the three default retries under
/// `Error rate 100 %` are over in a second, in a test and in a browser.
///
/// Proofs (widget tests in `test/features/playground_test.dart`, end-to-end
/// in `e2e/tests/playground.spec.ts`): under `Error rate 100 %` a refetch's
/// `failureCount` climbs through the retries and ends in
/// `Failed at random (errorRate)` with the stale list still on screen, and
/// `0` plus a refetch brings it back; `Stale time 30 s` flips the live
/// list's `isStale` to `false` without a fetch, `0` flips it back — the
/// "defaults changed under a live observer" proof; with `GC time 5 s` an
/// editor's entry is gone five seconds after the editor closes, with `5 min`
/// it stays; `Invalidate everything` refetches the list and the open editor's
/// entry, `fetches` +1 on both; adding, renaming and completing a todo
/// reaches the list at one `GET /api/todos` per invalidation with one `POST`
/// or `PATCH` each; and leaving the screen restores the client's defaults
/// and the scenario's latency and error rate.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/debug_strip.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';
import '../../shared/theme.dart';

const Feature playgroundFeature = Feature(
  id: 'playground',
  title: 'Playground',
  summary: 'Todos with live knobs for stale time, gc time, latency and errors.',
  upstream: 'playground',
);

/// The editor's key, `['todos', id]`: under the list's prefix, as upstream
/// keys a detail, so a prefix invalidation of `['todos']` would reach it.
QueryKey todoKey(int id) => ShowcaseKeys.todos.append(<Object?>[id]);

/// Three retries 300 ms apart instead of one, two and four seconds: the
/// error-rate knob is meant to be watched, not waited for.
const RetryDelay playgroundRetryDelay =
    RetryDelay.fixed(Duration(milliseconds: 300));

/// A rename, a completion, or both, for one todo.
typedef TodoPatch = ({int id, String? text, bool? done});

/// The list. Stale time and gc time are left unset on purpose: they come
/// from the client's defaults, which is what the knobs change.
QueryObserverOptions<List<Todo>> todosQuery(ShowcaseApi api) =>
    QueryObserverOptions<List<Todo>>(
      queryKey: ShowcaseKeys.todos,
      queryFn: (context) => api.todos(signal: context.signal),
      retryDelay: playgroundRetryDelay,
    );

/// One todo, for the editor. [seed] reads it from the cached list — `null`
/// when the list is not there, which means "no seed" — and [seededAt] is
/// the list's own `dataUpdatedAt`, so the seed is exactly as old as the
/// list it came from.
QueryObserverOptions<Todo> todoQuery(
  ShowcaseApi api,
  int id, {
  required Todo? Function() seed,
  required DateTime? seededAt,
}) =>
    QueryObserverOptions<Todo>(
      queryKey: todoKey(id),
      queryFn: (context) async {
        final todos = await api.todos(signal: context.signal);
        return todos.where((todo) => todo.id == id).firstOrNull ??
            (throw const BackendException('Todo not found', status: 404));
      },
      retryDelay: playgroundRetryDelay,
      initialData: InitialData<Todo>.compute(seed),
      initialDataUpdatedAt: seededAt,
    );

/// `POST /api/todos`, then the list is invalidated so it shows the new row.
MutationOptions<Todo, String, void> addTodoMutation(
  ShowcaseApi api,
  QueryClient client,
) =>
    MutationOptions.simple<Todo, String>(
      mutationFn: (text) => api.createTodo(text),
      onSuccess: (_, __, ___) => client.invalidateQueries(
        filters: QueryFilters(queryKey: ShowcaseKeys.todos, exact: true),
      ),
    );

/// `PATCH /api/todos/:id`. The answer is the todo as the backend now has it,
/// so it goes straight into the editor's entry; the list is the only thing
/// that still needs a request, hence `exact`.
MutationOptions<Todo, TodoPatch, void> patchTodoMutation(
  ShowcaseApi api,
  QueryClient client,
) =>
    MutationOptions.simple<Todo, TodoPatch>(
      mutationFn: (patch) =>
          api.updateTodo(patch.id, text: patch.text, done: patch.done),
      onSuccess: (todo, _, __) {
        client.setQueryData<Todo>(todoKey(todo.id), todo);
        return client.invalidateQueries(
          filters: QueryFilters(queryKey: ShowcaseKeys.todos, exact: true),
        );
      },
    );

class PlaygroundScreen extends StatefulWidget {
  const PlaygroundScreen({super.key});

  @override
  State<PlaygroundScreen> createState() => _PlaygroundScreenState();
}

class _PlaygroundScreenState extends State<PlaygroundScreen> with QueryMixin {
  static const List<(String, StaleTime)> _staleTimes = <(String, StaleTime)>[
    ('0', StaleTime.zero),
    ('5 s', StaleTime.duration(Duration(seconds: 5))),
    ('30 s', StaleTime.duration(Duration(seconds: 30))),
  ];

  static const List<(String, GcTime)> _gcTimes = <(String, GcTime)>[
    ('5 s', GcTime.duration(Duration(seconds: 5))),
    ('5 min', GcTime.duration(Duration(minutes: 5))),
  ];

  static const List<(String, Duration)> _latencies = <(String, Duration)>[
    ('0', Duration.zero),
    ('300 ms', Duration(milliseconds: 300)),
    ('2 s', Duration(seconds: 2)),
  ];

  static const List<(String, double)> _errorRates = <(String, double)>[
    ('0', 0),
    ('50 %', 0.5),
    ('100 %', 1),
  ];

  // The library's own defaults, so the knobs start out telling the truth.
  StaleTime _staleTime = StaleTime.zero;
  GcTime _gcTime = _gcTimes.last.$2;
  Duration _latency = Duration.zero;
  double _errorRate = 0;

  /// What the backend has acknowledged, or null before the first answer.
  ({Duration latency, double errorRate})? _applied;
  String? _scenarioError;
  int _configVersion = 0;

  /// The todo the editor is open on, and the last one it was open on — the
  /// strip keeps showing that entry after the editor closes, which is how a
  /// test watches it being collected.
  int? _editingId;
  int? _stripId;

  final TextEditingController _newTodo = TextEditingController();

  late final ShowcaseApi _api;

  /// Held from `didChangeDependencies`: `dispose` restores the defaults, and
  /// an inherited widget cannot be looked up from a State that is going.
  late final QueryClient _client;
  DefaultOptions? _snapshot;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_snapshot == null) {
      _api = ShowcaseScope.apiOf(context);
      _client = queryClient;
      _snapshot = _client.getDefaultOptions();
      _applyDefaults();
      unawaited(_pushScenario());
    }
  }

  @override
  void dispose() {
    final snapshot = _snapshot;
    if (snapshot != null) {
      _client.setDefaultOptions(snapshot);
      _api.configureScenario(latency: Duration.zero, errorRate: 0).ignore();
    }
    _newTodo.dispose();
    super.dispose();
  }

  /// The two knobs over the app's defaults, the rest of them untouched.
  void _applyDefaults() {
    final current = _client.getDefaultOptions();
    _client.setDefaultOptions(DefaultOptions(
      queries: (current.queries ?? const QueryDefaults()).mergedWith(
        QueryDefaults(staleTime: _staleTime, gcTime: _gcTime),
      ),
      mutations: current.mutations,
    ));
  }

  /// New defaults reach a live observer on its next `setOptions`, and the
  /// mixin runs that on every build — so the `setState` is the delivery.
  void _changeDefaults(void Function() change) {
    setState(() {
      change();
      _applyDefaults();
    });
  }

  void _changeScenario(void Function() change) {
    setState(change);
    unawaited(_pushScenario());
  }

  /// Sends the two backend knobs. Answers can cross when the knobs are turned
  /// quickly, so only the latest request's answer is shown as applied.
  Future<void> _pushScenario() async {
    final version = ++_configVersion;
    final latency = _latency;
    final errorRate = _errorRate;
    try {
      await _api.configureScenario(latency: latency, errorRate: errorRate);
      if (mounted && version == _configVersion) {
        setState(() {
          _applied = (latency: latency, errorRate: errorRate);
          _scenarioError = null;
        });
      }
    } on Object catch (error) {
      if (mounted && version == _configVersion) {
        setState(() => _scenarioError = '$error');
      }
    }
  }

  void _invalidateEverything() {
    _client.invalidateQueries().ignore();
  }

  void _openEditor(int id) {
    setState(() {
      _editingId = id;
      _stripId = id;
    });
  }

  void _closeEditor() {
    setState(() => _editingId = null);
  }

  /// One knob: its name, and a segmented button in a named semantics group,
  /// so a test can pick the `0` of one knob apart from the others'.
  Widget _knob<T extends Object>(
    BuildContext context, {
    required String name,
    required String semanticsKey,
    required List<(String, T)> choices,
    required T selected,
    required ValueChanged<T> onChanged,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(name, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Semantics(
            container: true,
            explicitChildNodes: true,
            label: semanticsKey,
            child: SegmentedButton<T>(
              key: ValueKey<String>(semanticsKey),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: <ButtonSegment<T>>[
                for (final (label, value) in choices)
                  ButtonSegment<T>(value: value, label: Text(label)),
              ],
              selected: <T>{selected},
              onSelectionChanged: (selection) => onChanged(selection.single),
            ),
          ),
        ],
      );

  Widget _knobs(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final applied = _applied;
    return SectionCard(
      title: 'Knobs',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: <Widget>[
              _knob<StaleTime>(
                context,
                name: 'Stale time',
                semanticsKey: 'stale-time',
                choices: _staleTimes,
                selected: _staleTime,
                onChanged: (value) => _changeDefaults(() => _staleTime = value),
              ),
              _knob<GcTime>(
                context,
                name: 'GC time',
                semanticsKey: 'gc-time',
                choices: _gcTimes,
                selected: _gcTime,
                onChanged: (value) => _changeDefaults(() => _gcTime = value),
              ),
              _knob<Duration>(
                context,
                name: 'Latency',
                semanticsKey: 'latency',
                choices: _latencies,
                selected: _latency,
                onChanged: (value) => _changeScenario(() => _latency = value),
              ),
              _knob<double>(
                context,
                name: 'Error rate',
                semanticsKey: 'error-rate',
                choices: _errorRates,
                selected: _errorRate,
                onChanged: (value) => _changeScenario(() => _errorRate = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Stale time and GC time go into the client's defaults "
            '(setDefaultOptions); every reader on this screen picks them up '
            'on its next build. An entry keeps the longest gc time a reader '
            "ever gave it. Latency and error rate go to the backend's "
            'scenario, and the retries are 300 ms apart here.',
            style: small,
          ),
          const SizedBox(height: 8),
          _Facts(
            label: 'backend',
            facts: <String>[
              if (applied == null)
                'backend=pending'
              else ...<String>[
                'latency=${applied.latency.inMilliseconds}ms',
                'errorRate=${(applied.errorRate * 100).round()}%',
              ],
            ],
          ),
          if (_scenarioError != null) ...<Widget>[
            const SizedBox(height: 8),
            Notice('Scenario not applied: $_scenarioError', error: true),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: _invalidateEverything,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Invalidate everything'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _todos(BuildContext context) {
    final todos = watchQuery(todosQuery(_api));
    final add = watchMutation(addTodoMutation(_api, _client));
    final adding = add.value;

    return SectionCard(
      title: 'Todos',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (todos.isFetching) const Pill('fetching'),
          IconButton(
            tooltip: 'Refetch',
            onPressed: todos.isFetching ? null : todos.refetch,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Facts(
            label: 'todos-reader',
            facts: <String>[
              'status=${todos.status.name}',
              'failureCount=${todos.failureCount}',
              'isStale=${todos.isStale}',
            ],
          ),
          const SizedBox(height: 8),
          switch (todos) {
            QueryPending() => const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SkeletonBox(),
                  SizedBox(height: 8),
                  SkeletonBox(),
                  SizedBox(height: 8),
                  SkeletonBox(),
                ],
              ),
            QueryError(:final error, staleData: null) =>
              Notice('$error', error: true),
            QuerySuccess(:final data) ||
            QueryError(staleData: final data!) =>
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (todos case QueryError(:final error)) ...<Widget>[
                    Notice('Refetch failed: $error', error: true),
                    const SizedBox(height: 8),
                  ],
                  // Bounded and scrolling on its own, so the editor and the
                  // strips below it are built whatever the list's length.
                  SizedBox(
                    height: 200,
                    child: ListView(
                      children: <Widget>[
                        for (final todo in data)
                          _TodoRow(
                            todo: todo,
                            selected: todo.id == _editingId,
                            onOpen: () => _openEditor(todo.id),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
          },
          const Divider(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _newTodo,
                  enabled: !adding.isPending,
                  decoration: const InputDecoration(
                    labelText: 'New todo',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _submitNewTodo(add),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: adding.isPending ? null : () => _submitNewTodo(add),
                child: const Text('Add todo'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _Facts(
            label: 'add',
            facts: <String>['adding=${adding.status.name}'],
          ),
          if (adding case MutationError(:final error)) ...<Widget>[
            const SizedBox(height: 8),
            Notice('Add failed: $error', error: true),
          ],
        ],
      ),
    );
  }

  void _submitNewTodo(MutationController<Todo, String, void> add) {
    add.mutate(
      _newTodo.text,
      // Per-call, not on the options: clearing the field is this widget's
      // business, invalidating the list is the mutation's.
      callbacks: MutateCallbacks<Todo, String, void>(
        onSuccess: (_, __, ___) => _newTodo.clear(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editingId = _editingId;
    final stripId = _stripId;
    return FeatureScaffold(
      feature: playgroundFeature,
      children: <Widget>[
        _knobs(context),
        _todos(context),
        if (editingId != null)
          _TodoEditor(
            key: ValueKey<int>(editingId),
            id: editingId,
            onClose: _closeEditor,
          ),
        QueryDebugStrip(queryKey: ShowcaseKeys.todos, label: 'todos'),
        if (stripId != null)
          QueryDebugStrip(queryKey: todoKey(stripId), label: 'todo-$stripId'),
      ],
    );
  }
}

/// One row of the list: a button named by the todo's text, so a test opens
/// the editor by that text, and a mark for the one the editor is on.
class _TodoRow extends StatelessWidget {
  const _TodoRow({
    required this.todo,
    required this.selected,
    required this.onOpen,
  });

  final Todo todo;
  final bool selected;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'todo ${todo.id}',
      child: Row(
        key: ValueKey<String>('todo-row-${todo.id}'),
        children: <Widget>[
          Icon(
            todo.done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: todo.done ? scheme.primary : scheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: MergeSemantics(
              child: Semantics(
                button: true,
                child: InkWell(
                  onTap: onOpen,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Text(
                      todo.text,
                      style: TextStyle(
                        decoration:
                            todo.done ? TextDecoration.lineThrough : null,
                        fontWeight: selected ? FontWeight.bold : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (selected) const Pill('editing'),
        ],
      ),
    );
  }
}

/// The editor for one todo. Its own `State` with the mixin, so closing it
/// removes the widget and with it the observer on `['todos', id]` — the
/// moment the entry's gc timer starts.
class _TodoEditor extends StatefulWidget {
  const _TodoEditor({super.key, required this.id, required this.onClose});

  final int id;
  final VoidCallback onClose;

  @override
  State<_TodoEditor> createState() => _TodoEditorState();
}

class _TodoEditorState extends State<_TodoEditor> with QueryMixin {
  final TextEditingController _text = TextEditingController();

  /// Whether the field has been filled from the data once. Later data
  /// (a refetch, the PATCH's answer) does not overwrite what is typed.
  bool _filled = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    final client = queryClient;
    final id = widget.id;

    final todo = watchQuery(todoQuery(
      api,
      id,
      seed: () => client
          .getQueryData<List<Todo>>(ShowcaseKeys.todos)
          ?.where((todo) => todo.id == id)
          .firstOrNull,
      seededAt:
          client.getQueryState<List<Todo>>(ShowcaseKeys.todos)?.dataUpdatedAt,
    ));
    final patch = watchMutation(patchTodoMutation(api, client));
    final saving = patch.value;

    final data = todo.dataOrNull;
    if (data != null && !_filled) {
      _filled = true;
      _text.text = data.text;
    }

    return SectionCard(
      title: 'Edit todo #$id',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (todo.isFetching) const Pill('fetching'),
          IconButton(
            tooltip: 'Close editor',
            onPressed: widget.onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Facts(
            label: 'editor',
            facts: <String>[
              'editing=$id',
              'status=${todo.status.name}',
              'failureCount=${todo.failureCount}',
              'isStale=${todo.isStale}',
              'saving=${saving.status.name}',
            ],
          ),
          const SizedBox(height: 8),
          if (data == null)
            switch (todo) {
              QueryError(:final error) => Notice('$error', error: true),
              _ => const SkeletonBox(width: 240),
            }
          else ...<Widget>[
            if (todo case QueryError(:final error)) ...<Widget>[
              Notice('Refetch failed: $error', error: true),
              const SizedBox(height: 8),
            ],
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _text,
                    enabled: !saving.isPending,
                    decoration: const InputDecoration(
                      labelText: 'Text',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: saving.isPending
                      ? null
                      : () => patch.mutate(
                            (id: id, text: _text.text, done: null),
                          ),
                  child: const Text('Rename'),
                ),
              ],
            ),
            CheckboxListTile(
              title: const Text('Done'),
              value: data.done,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              onChanged: saving.isPending
                  ? null
                  : (done) => patch.mutate((id: id, text: null, done: done)),
            ),
            if (saving case MutationError(:final error))
              Notice('Save failed: $error', error: true),
          ],
        ],
      ),
    );
  }
}

/// A reader's own facts as `key=value` texts in a semantics group of their
/// own, so a test tells the reader's `isStale` apart from the strip's.
class _Facts extends StatelessWidget {
  const _Facts({required this.label, required this.facts});

  final String label;
  final List<String> facts;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        explicitChildNodes: true,
        label: label,
        child: Wrap(
          key: ValueKey<String>('$label-facts'),
          spacing: 12,
          runSpacing: 2,
          children: <Widget>[
            for (final fact in facts)
              Text(
                fact,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
          ],
        ),
      );
}
