/// A write that knows about its run, and can be called off:
/// `mutationFnWithContext` and `cancel()`.
///
/// Port-specific — upstream cannot cancel a mutation, and its
/// `MutationFunctionContext` carries neither of the two fields this screen is
/// about. The mutation is an optimistic rename of the first todo:
///
/// * `onMutate` cancels the list's fetches, snapshots it, writes the new text
///   into the cache and returns the snapshot.
/// * `mutationFnWithContext` sends the write. The cache already says the new
///   text by then, so "what was it before?" cannot be read from there any
///   more: it comes from **`context.onMutateResult`** and goes out as `from`.
///   And **`context.signal`** goes to dio through `ShowcaseApi.bridge`, the
///   same bridge a query's signal takes.
/// * `onError` puts the snapshot back, and `onSettled` invalidates the list.
///
/// **Cancelling is failing.** `Cancel` calls `cancel()` on the controller the
/// mixin handed out: the run fails with a `CancelledError`, so the rollback
/// above rolls it back and the invalidation above asks the backend what it
/// really holds — which nobody can know otherwise, because the request may
/// have arrived. The write takes three seconds on the backend (`?delay`), long
/// enough for a human to press `Cancel` in the middle of it.
///
/// The list and the mutation are read through `QueryMixin` (`watchQuery`,
/// `watchMutation`).
///
/// Proofs (widget tests in `test/features/mutation_cancel_test.dart`,
/// end-to-end in `e2e/tests/mutation_cancel.spec.ts`): a held rename is in the
/// cache before the backend answers, `from=` is the text `onMutate` kept, and
/// after the answer the backend's log shows that `from` in the request's
/// query; cancelling a held rename ends in `status=error` with
/// `error=cancelled`, one `signal.onCancel`, one rollback to the old text and
/// one settle whose invalidation refetched the list — while the browser gave
/// the request up and the backend never answered a `PATCH`; and a rename after
/// a cancelled one goes through.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/cache_listener.dart';
import '../../shared/chrome.dart';
import '../../shared/controls.dart';
import '../../shared/debug_strip.dart';
import '../../shared/fact_group.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';

const Feature mutationCancelFeature = Feature(
  id: 'mutation-cancel',
  title: 'Mutation context and cancel',
  summary: 'A write that reads what onMutate kept, and can be called off.',
);

/// The todo every rename here is of.
const int renamedTodoId = 1;

/// Long enough that a human can hit `Cancel` in the middle of it.
const Duration slowWriteDelay = Duration(seconds: 3);

/// What one rename asks for.
typedef Rename = ({int id, String text});

/// What the screen wants to be told about a run, so it can count it: the
/// mutation itself knows nothing of the screen.
typedef RenameProbe = ({
  void Function(String? from) onSent,
  VoidCallback onSignalCancelled,
  VoidCallback onRolledBack,
  VoidCallback onSettled,
});

QueryFilters get _todosFilter => QueryFilters(queryKey: ShowcaseKeys.todos);

QueryObserverOptions<List<Todo>> todosQuery(ShowcaseApi api) =>
    QueryObserverOptions<List<Todo>>(
      queryKey: ShowcaseKeys.todos,
      queryFn: (context) => api.todos(signal: context.signal),
    );

/// The rename. What `onMutate` returns — the list as it was — is the third
/// type argument, and so it is what `context.onMutateResult` is typed as.
MutationOptions<Todo, Rename, List<Todo>> renameMutation(
  ShowcaseApi api,
  QueryClient client,
  RenameProbe probe,
) =>
    MutationOptions<Todo, Rename, List<Todo>>(
      onMutate: (rename) async {
        // A refetch already in flight would land after the write below and
        // put the old text back over it.
        await client.cancelQueries(filters: _todosFilter);
        final previous = client.getQueryData<List<Todo>>(ShowcaseKeys.todos);
        client.updateQueryData<List<Todo>>(
          ShowcaseKeys.todos,
          (old) => <Todo>[
            for (final todo in old ?? const <Todo>[])
              todo.id == rename.id ? todo.copyWith(text: rename.text) : todo,
          ],
        );
        return previous;
      },
      mutationFnWithContext: (rename, context) {
        // The cache says `rename.text` already. What it said before is what
        // `onMutate` kept.
        final from = context.onMutateResult
            ?.where((todo) => todo.id == rename.id)
            .firstOrNull
            ?.text;
        probe.onSent(from);
        // Beside the bridge's own `onCancel`, which is dio's: this one only
        // counts, as proof that `cancel()` reached the signal.
        context.signal.onCancel(probe.onSignalCancelled);
        return api.updateTodo(
          rename.id,
          text: rename.text,
          from: from,
          signal: context.signal,
          delay: slowWriteDelay,
        );
      },
      // A cancelled run arrives here as any other failure does, with a
      // `CancelledError`: there is no second rollback to write.
      onError: (_, __, ___, previous) {
        if (previous != null) {
          client.setQueryData<List<Todo>>(ShowcaseKeys.todos, previous);
          probe.onRolledBack();
        }
      },
      onSettled: (_, __, ___, ____, _____) {
        probe.onSettled();
        return client.invalidateQueries(filters: _todosFilter);
      },
    );

class MutationCancelScreen extends StatefulWidget {
  const MutationCancelScreen({super.key});

  @override
  State<MutationCancelScreen> createState() => _MutationCancelScreenState();
}

class _MutationCancelScreenState extends State<MutationCancelScreen>
    with QueryMixin, PhaseSafeRebuild<MutationCancelScreen> {
  final TextEditingController _text = TextEditingController();

  late final ShowcaseApi _api;
  late final QueryClient _client;

  String? _from;
  int _signalCancels = 0;
  int _rollbacks = 0;
  int _settles = 0;

  @override
  void initState() {
    super.initState();
    // Neither lookup subscribes: the api and the client are fixed for the
    // life of the app, and a subscribing lookup is not allowed here anyway.
    _api = context.getInheritedWidgetOfExactType<ShowcaseScope>()!.api;
    _client = QueryClientProvider.read(context);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// The probe's callbacks run from the mutation's own futures — and
  /// `onSignalCancelled` synchronously inside `cancel()` — and a mutation
  /// outlives the widget that fired it, so: only while mounted, and whatever
  /// the scheduler phase.
  void _count(VoidCallback change) {
    if (!mounted) {
      return;
    }
    change();
    scheduleRebuild();
  }

  late final RenameProbe _probe = (
    onSent: (from) => _count(() => _from = from),
    onSignalCancelled: () => _count(() => _signalCancels += 1),
    onRolledBack: () => _count(() => _rollbacks += 1),
    onSettled: () => _count(() => _settles += 1),
  );

  void _submit(void Function(Rename) mutate) {
    final value = _text.text.trim();
    if (value.isEmpty) {
      return;
    }
    mutate((id: renamedTodoId, text: value));
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final todos = watchQuery(todosQuery(_api));
    final rename = watchMutation(renameMutation(_api, _client, _probe));
    final result = rename.value;
    final rows = todos.dataOrNull ?? const <Todo>[];
    final first = rows.where((todo) => todo.id == renamedTodoId).firstOrNull;

    return FeatureScaffold(
      feature: mutationCancelFeature,
      children: <Widget>[
        SectionCard(
          title: 'Rename the first todo',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: _text,
                decoration: const InputDecoration(
                  labelText: 'New text',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Toolbar(
                children: <Widget>[
                  ActionButton(
                    label: 'Rename',
                    filled: true,
                    onPressed: result.isPending || first == null
                        ? null
                        : () => _submit(rename.mutate),
                  ),
                  // Enabled only while there is a run to call off; with none
                  // in flight `cancel()` does nothing anyway.
                  ActionButton(
                    label: 'Cancel',
                    onPressed: result.isPending ? rename.cancel : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'The write takes three seconds on the backend. The new text '
                'is on screen at once, written into the cache by onMutate; '
                'Cancel fails the run with a CancelledError, so onError puts '
                'the old text back and onSettled refetches the list.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FactGroup(
                name: 'rename facts',
                dense: true,
                facts: <String>[
                  'status=${result.status.name}',
                  'error=${switch (result) {
                    MutationError(error: CancelledError()) => 'cancelled',
                    MutationError(:final error) => '$error',
                    _ => 'none',
                  }}',
                  'text=${first?.text ?? 'none'}',
                  'from=${_from ?? 'none'}',
                  'signalCancels=$_signalCancels',
                  'rollbacks=$_rollbacks',
                  'settles=$_settles',
                ],
              ),
            ],
          ),
        ),
        QueryDebugStrip(queryKey: ShowcaseKeys.todos, label: 'todos'),
        SectionCard(
          title: 'Todos',
          trailing: todos.isFetching ? const Pill('fetching') : null,
          child: switch (todos) {
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
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: <Widget>[
                          Expanded(child: Text(todo.text)),
                          Text(
                            '#${todo.id}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          },
        ),
        if (result case MutationError(error: CancelledError()))
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Notice(
              'Cancelled. Whether the backend took the write is not known '
              'here — the refetch on settle is what found out.',
            ),
          ),
      ],
    );
  }
}
