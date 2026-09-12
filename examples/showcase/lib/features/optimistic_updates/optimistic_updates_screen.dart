/// Upstream's `nextjs-app-optimistic-updates` example: a todo shown in the
/// list before the backend has confirmed it, two ways.
///
/// **Via variables** (upstream `TodoListUI`): the cache is never touched.
/// While the mutation is pending, its `variables` — the text being saved —
/// are rendered as one extra greyed row; when it fails, that row turns into
/// an error with a `Retry` button that runs `mutate` again with the same
/// variables. `onSettled` invalidates the list either way. This variant reads
/// with `context.query` and `context.mutation`.
///
/// **Via cache** (upstream `TodoListCache`): `onMutate` cancels the todos
/// query, snapshots `getQueryData`, writes the optimistic row into the cache
/// with a negative temporary id and returns the snapshot; `onError` puts the
/// snapshot back; `onSettled` invalidates. Every reader of the key sees the
/// row, and the rollback, without knowing about the mutation. This variant
/// is a `QueryBuilder` around a `MutationBuilder`.
///
/// `Refuse next write` asks the backend to answer the next `POST` with 500
/// (`?fail=500`), consumed by the request that carries it, so a retry of a
/// refused write is a clean one.
///
/// Proofs (widget tests in `test/features/optimistic_updates_test.dart`,
/// end-to-end in `e2e/tests/optimistic_updates.spec.ts`): via variables, a
/// held write shows the text as a `saving` row while the cache still holds
/// three todos, and becomes a real row after one `POST` and one refetch; a
/// refused write shows the error row with `Retry`, leaves the cache alone,
/// and `Retry` makes it real. Via cache, a held write is in the cache — four
/// entries, `todos=4` — before the backend answers, and the temporary row is
/// replaced by the backend's after the refetch; a refused write appears,
/// disappears again, and `Rolled back: Requested: 500` is shown while the
/// refetch on settle still happens. And `onMutate`'s `cancelQueries` really
/// cancels an in-flight refetch, whose late answer would otherwise overwrite
/// the optimistic row.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/debug_strip.dart';
import '../../shared/fact_group.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';
import '../../shared/theme.dart';

const Feature optimisticUpdatesFeature = Feature(
  id: 'optimistic-updates',
  title: 'Optimistic updates',
  summary: 'Show the write before the server answers — two ways.',
  upstream: 'nextjs-app-optimistic-updates',
);

/// The list both variants read. One key, so a write through either variant
/// is seen by whichever is on screen.
QueryObserverOptions<List<Todo>> todosQuery(ShowcaseApi api) =>
    QueryObserverOptions<List<Todo>>(
      queryKey: ShowcaseKeys.todos,
      queryFn: (context) => api.todos(signal: context.signal),
    );

/// The status the next write asks the backend to refuse with, or `null` for
/// a write that should succeed. Read when the request goes out — not when
/// the button is pressed — so `Retry` re-sends the same variables without
/// re-sending the refusal.
typedef FailKnob = int? Function();

/// What the cache variant's `onMutate` hands to `onError`: the list as it
/// was, and the id of the row it wrote — upstream's `MutationContext`.
typedef TodosSnapshot = ({List<Todo>? previous, int optimisticId});

QueryFilters get _todosFilter => QueryFilters(queryKey: ShowcaseKeys.todos);

/// Upstream's `TodoListUI` mutation: no `onMutate`, so `MutationOptions.simple`
/// and nothing to roll back. `onSettled` returns the invalidation's future,
/// which keeps the mutation pending — and the `saving` row on screen — until
/// the refetch has landed, so the row never flickers off before the real one
/// is there.
MutationOptions<Todo, String, void> addTodoViaVariables(
  QueryClient client,
  ShowcaseApi api,
  FailKnob fail,
) =>
    MutationOptions.simple(
      mutationFn: (text) => api.createTodo(text, fail: fail()),
      onSettled: (_, __, ___, ____, _____) =>
          client.invalidateQueries(filters: _todosFilter),
    );

/// Upstream's `TodoListCache` mutation: cancel, snapshot, write, and on
/// error put the snapshot back.
MutationOptions<Todo, String, TodosSnapshot> addTodoViaCache(
  QueryClient client,
  ShowcaseApi api,
  FailKnob fail,
) =>
    MutationOptions<Todo, String, TodosSnapshot>(
      mutationFn: (text) => api.createTodo(text, fail: fail()),
      onMutate: (text) async {
        // A refetch already in flight would land *after* the write below and
        // put the backend's list — without this row — back over it.
        await client.cancelQueries(filters: _todosFilter);
        final previous = client.getQueryData<List<Todo>>(ShowcaseKeys.todos);
        // Negative, so it can never collide with an id the backend hands out,
        // and one below the rows already there, so two writes in flight get
        // two different ids.
        final optimisticId = -((previous?.length ?? 0) + 1);
        client.updateQueryData<List<Todo>>(
          ShowcaseKeys.todos,
          (old) => <Todo>[
            ...?old,
            Todo(id: optimisticId, text: text, done: false),
          ],
        );
        return (previous: previous, optimisticId: optimisticId);
      },
      onError: (_, __, ___, snapshot) {
        if (snapshot == null) {
          return;
        }
        if (snapshot.previous case final List<Todo> previous) {
          client.setQueryData<List<Todo>>(ShowcaseKeys.todos, previous);
        } else {
          // Nothing was cached before the write: drop only the row it added.
          client.updateQueryData<List<Todo>>(
            ShowcaseKeys.todos,
            (old) =>
                old?.where((todo) => todo.id != snapshot.optimisticId).toList(),
          );
        }
      },
      onSettled: (_, __, ___, ____, _____) =>
          client.invalidateQueries(filters: _todosFilter),
    );

enum _Variant { variables, cache }

class OptimisticUpdatesScreen extends StatefulWidget {
  const OptimisticUpdatesScreen({super.key});

  @override
  State<OptimisticUpdatesScreen> createState() =>
      _OptimisticUpdatesScreenState();
}

class _OptimisticUpdatesScreenState extends State<OptimisticUpdatesScreen> {
  final TextEditingController _text = TextEditingController();
  _Variant _variant = _Variant.variables;
  bool _refuseNext = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Consumed by the request that carries it, whichever variant sends it.
  int? _takeFail() {
    if (!_refuseNext) {
      return null;
    }
    setState(() => _refuseNext = false);
    return 500;
  }

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: optimisticUpdatesFeature,
        children: <Widget>[
          SectionCard(
            title: 'Add a todo',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: _text,
                  decoration: const InputDecoration(
                    labelText: 'New todo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<_Variant>(
                  showSelectedIcon: false,
                  segments: const <ButtonSegment<_Variant>>[
                    ButtonSegment<_Variant>(
                      value: _Variant.variables,
                      label: Text('Via variables'),
                    ),
                    ButtonSegment<_Variant>(
                      value: _Variant.cache,
                      label: Text('Via cache'),
                    ),
                  ],
                  selected: <_Variant>{_variant},
                  onSelectionChanged: (selection) =>
                      setState(() => _variant = selection.first),
                ),
                // No subtitle: a tile folds it into the checkbox's accessible
                // name, and the tests find the box by its title alone.
                CheckboxListTile(
                  title: const Text('Refuse next write'),
                  contentPadding: EdgeInsets.zero,
                  value: _refuseNext,
                  onChanged: (value) =>
                      setState(() => _refuseNext = value ?? false),
                ),
                Text(
                  'Ticked, the next POST asks the backend for a 500 and the '
                  'tick clears itself. Via variables the row is rendered from '
                  'the pending mutation; via cache it is written into the '
                  'cache and rolled back on error.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          QueryDebugStrip(queryKey: ShowcaseKeys.todos, label: 'todos'),
          switch (_variant) {
            _Variant.variables => _ViaVariables(text: _text, fail: _takeFail),
            _Variant.cache => _ViaCache(text: _text, fail: _takeFail),
          },
        ],
      );
}

/// Takes the field's text, if any, and hands it to [mutate].
void _submit(TextEditingController text, void Function(String) mutate) {
  final value = text.text.trim();
  if (value.isEmpty) {
    return;
  }
  mutate(value);
  text.clear();
}

/// Upstream's `TodoListUI`: the pending row comes from the mutation's
/// `variables`, the error row too, and the cache holds only what the backend
/// said.
class _ViaVariables extends StatelessWidget {
  const _ViaVariables({required this.text, required this.fail});

  final TextEditingController text;
  final FailKnob fail;

  @override
  Widget build(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    final client = QueryClientProvider.of(context);
    final todos = context.query(todosQuery(api));
    final add = context.mutation(addTodoViaVariables(client, api, fail));
    final result = add.value;

    return _TodoCard(
      title: 'Todos · via variables',
      todos: todos,
      pending: result.isPending,
      onAdd: result.isPending ? null : () => _submit(text, add.mutate),
      extraRows: switch (result) {
        MutationPending(:final variables?) => <Widget>[
            _TodoRow(text: variables, saving: true),
          ],
        MutationError(:final variables?, :final error) => <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(variables),
                      const SizedBox(height: 4),
                      Notice('Not saved: $error', error: true),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // The variables survive the error, so the same text can be
                // sent again without the user retyping it.
                TextButton(
                  onPressed: () => add.mutate(variables),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ],
        _ => const <Widget>[],
      },
    );
  }
}

/// Upstream's `TodoListCache`: the list is whatever the cache holds, and the
/// optimistic row is in it — told apart only by its negative id.
class _ViaCache extends StatelessWidget {
  const _ViaCache({required this.text, required this.fail});

  final TextEditingController text;
  final FailKnob fail;

  @override
  Widget build(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    final client = QueryClientProvider.of(context);
    return QueryBuilder<List<Todo>>(
      options: todosQuery(api),
      builder: (context, todos) => MutationBuilder<Todo, String, TodosSnapshot>(
        options: addTodoViaCache(client, api, fail),
        builder: (context, add) {
          final result = add.value;
          return _TodoCard(
            title: 'Todos · via cache',
            todos: todos,
            pending: result.isPending,
            onAdd: result.isPending ? null : () => _submit(text, add.mutate),
            notice: switch (result) {
              MutationError(:final error) =>
                Notice('Rolled back: $error', error: true),
              _ => null,
            },
          );
        },
      ),
    );
  }
}

/// The list card both variants render: its facts, its rows, and whatever a
/// variant appends below them.
class _TodoCard extends StatelessWidget {
  const _TodoCard({
    required this.title,
    required this.todos,
    required this.pending,
    required this.onAdd,
    this.notice,
    this.extraRows = const <Widget>[],
  });

  final String title;
  final QueryResult<List<Todo>> todos;
  final bool pending;
  final VoidCallback? onAdd;
  final Widget? notice;
  final List<Widget> extraRows;

  @override
  Widget build(BuildContext context) {
    final rows = todos.dataOrNull ?? const <Todo>[];
    return SectionCard(
      title: title,
      // Explicit child nodes: two buttons in one row would otherwise fold
      // into a single semantics node, and the tests find each by name.
      trailing: SemanticsGroup(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              tooltip: 'Refetch',
              onPressed: todos.isFetching ? null : todos.refetch,
              icon: const Icon(Icons.refresh),
            ),
            FilledButton(onPressed: onAdd, child: const Text('Add')),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SemanticsGroup(
            child: Wrap(
              spacing: 12,
              children: <Widget>[
                Text('todos=${rows.length}'),
                Text('pending=$pending'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (notice case final Widget notice) ...<Widget>[
            notice,
            const SizedBox(height: 8),
          ],
          switch (todos) {
            QueryPending() => const Column(
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
            _ => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final todo in rows)
                    _TodoRow(
                      text: todo.text,
                      done: todo.done,
                      id: todo.id,
                      saving: todo.id < 0,
                    ),
                  ...extraRows,
                ],
              ),
          },
        ],
      ),
    );
  }
}

/// One row. A [saving] row — the cache variant's negative id, or the
/// variables variant's pending text — is greyed and carries the pill instead
/// of an id.
class _TodoRow extends StatelessWidget {
  const _TodoRow({
    required this.text,
    this.done = false,
    this.id,
    this.saving = false,
  });

  final String text;
  final bool done;
  final int? id;
  final bool saving;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: saving ? 0.5 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: <Widget>[
              Icon(
                done ? Icons.check_box : Icons.check_box_outline_blank,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(text)),
              if (saving)
                const Pill('saving')
              else if (id case final int id)
                Text('#$id', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      );
}
