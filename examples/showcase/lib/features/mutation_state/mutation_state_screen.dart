/// Mutation state: what every mutation in the cache is doing, read from a
/// widget that owns none of them. Port-specific — it is
/// `MutationStateController`, the port's `useMutationState`.
///
/// The problem it solves: a mutation is owned by the widget that asks for it,
/// so the widget that wants to show "2 saving…" in an app bar cannot see it.
/// A `MutationStateController` reads the *cache* instead — `MutationFilters`
/// picks the mutations, a `select` turns each one into whatever the badge
/// needs — so the writer and the indicator never have to know each other.
///
/// Two things to notice. Concurrent runs under one key stay separate entries,
/// which is why the badge can say `2` for two saves of the same kind. And the
/// selection goes through structural sharing, so a cache event that leaves the
/// selected list equal does not rebuild the badge at all.
///
/// Proofs (widget tests in `test/features/mutation_state_test.dart`,
/// end-to-end in `e2e/tests/mutation_state.spec.ts`): the badge counts two
/// concurrent adds under one key as two, drops back to zero when they settle,
/// counts a failing mutation as an error rather than as pending, and rebuilds
/// only when the selection actually changed. The todos list under it is the
/// thing being written to, so the invalidation the writers fire has a reader.
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

const Feature mutationStateFeature = Feature(
  id: 'mutation-state',
  title: 'Mutation state',
  summary: 'Every running mutation in the cache, read by a widget that owns '
      'none of them.',
);

/// The key both writers share, so the badge can filter on it and still see
/// two concurrent runs as two entries.
QueryKey get addTodoKey => QueryKey(const <Object?>['todos', 'add']);

class MutationStateScreen extends StatefulWidget {
  const MutationStateScreen({super.key});

  @override
  State<MutationStateScreen> createState() => _MutationStateScreenState();
}

class _MutationStateScreenState extends State<MutationStateScreen> {
  /// Slow enough that two adds are in flight together without a stopwatch:
  /// the test presses twice, then lets the backend answer.
  static const Duration _slow = Duration(milliseconds: 600);

  late final ShowcaseApi _api;
  late final QueryClient _client;
  int _added = 0;

  @override
  void initState() {
    super.initState();
    _api = context.getInheritedWidgetOfExactType<ShowcaseScope>()!.api;
    _client = QueryClientProvider.read(context);
  }

  MutationOptions<Todo, String, void> _addOptions({bool fail = false}) =>
      MutationOptions.simple<Todo, String>(
        mutationKey: addTodoKey,
        mutationFn: (String text) =>
            _api.createTodo(text, delay: _slow, fail: fail ? 500 : null),
        onSuccess: (_, __, ___) => _client.invalidateQueries(
          filters: QueryFilters(queryKey: ShowcaseKeys.todos),
        ),
      );

  /// Runs a mutation nobody watches: an owned controller that disposes itself
  /// when it settles. The badge still sees it, which is the whole point.
  void _fireAndForget({bool fail = false}) {
    final controller = MutationController<Todo, String, void>(
      _client,
      _addOptions(fail: fail),
    );
    final text = fail ? 'doomed write' : 'write ${++_added}';
    controller
        .mutateAsync(text)
        .then<void>((_) {}, onError: (Object _) {})
        // Detach only after the badge has seen the settled state; disposing
        // sooner would drop the entry before its last event.
        .whenComplete(() => WidgetsBinding.instance
            .addPostFrameCallback((_) => controller.dispose()));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: mutationStateFeature,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonal(
                  onPressed: _fireAndForget,
                  child: const Text('Add todo'),
                ),
                OutlinedButton(
                  onPressed: () => _fireAndForget(fail: true),
                  child: const Text('Add, failing'),
                ),
              ],
            ),
          ),
          _SavingBadge(client: _client),
          // The list the writers invalidate. Without a reader on screen the
          // invalidation would be a write into an empty cache, and the strip
          // below would say `status=absent` for good.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: QueryBuilder<List<Todo>>(
              options: QueryObserverOptions<List<Todo>>(
                queryKey: ShowcaseKeys.todos,
                queryFn: (context) => _api.todos(signal: context.signal),
              ),
              builder: (context, result) => SectionCard(
                title: 'Todos',
                trailing: switch (result) {
                  QueryResult(isLoading: true) => const Pill('loading'),
                  QueryResult(isRefetching: true) => const Pill('refreshing'),
                  _ => const SizedBox.shrink(),
                },
                child: switch (result) {
                  QueryPending() => const SkeletonBox(height: 20),
                  QueryError(:final error, staleData: null) =>
                    Notice('$error', error: true),
                  QuerySuccess(:final data) ||
                  QueryError(staleData: final data!) =>
                    SemanticsGroup(
                      child: Text(
                        'todos=${data.length}',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                },
              ),
            ),
          ),
          QueryDebugStrip(queryKey: ShowcaseKeys.todos, label: 'todos'),
        ],
      );
}

/// The indicator. It owns no mutation and is not rebuilt by the writers —
/// only by its own controller, and only when the selection changed.
class _SavingBadge extends StatefulWidget {
  const _SavingBadge({required this.client});

  final QueryClient client;

  @override
  State<_SavingBadge> createState() => _SavingBadgeState();
}

class _SavingBadgeState extends State<_SavingBadge> {
  late final MutationStateController<MutationStatus> _statuses;
  int _builds = 0;

  @override
  void initState() {
    super.initState();
    _statuses = MutationStateController<MutationStatus>(
      widget.client,
      filters: MutationFilters(mutationKey: addTodoKey),
      select: (mutation) => mutation.state.status,
    );
  }

  @override
  void dispose() {
    _statuses.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: SemanticsGroup(
          child: ListenableBuilder(
            listenable: _statuses,
            builder: (context, _) {
              _builds++;
              final statuses = _statuses.value;
              final pending = statuses
                  .where((status) => status == MutationStatus.pending)
                  .length;
              final failed = statuses
                  .where((status) => status == MutationStatus.error)
                  .length;
              return Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  if (pending > 0)
                    const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  Text(
                    'saving=$pending',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  Text(
                    'failed=$failed',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  Text(
                    'tracked=${statuses.length}',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  // Proof that an unchanged selection does not rebuild.
                  Text(
                    'badge-builds=$_builds',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              );
            },
          ),
        ),
      );
}
