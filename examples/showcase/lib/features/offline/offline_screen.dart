/// Upstream's `offline` example, and the `network-mode` guide next to it: a
/// query and a mutation under a connection the reader controls.
///
/// The switch *is* the connectivity source here. The library installs no
/// listener and depends on no connectivity package
/// (https://github.com/KoTTi97/flutter_query/issues/21), so a client nobody
/// tells otherwise believes it is online — which is what upstream does with
/// no listener too. A real app hands `QueryClientProvider` an
/// `onlineStatus` stream; this screen calls
/// `client.onlineManager.setOnline` by hand, which is exactly what upstream's
/// devtools "mock offline behavior" button does.
///
/// Both the todos query and the add-todo mutation run under the network mode
/// the segmented button picks, so the three modes can be compared on the same
/// pair:
///
/// * `online` — neither fetches while offline. The query goes
///   `fetchStatus=paused` without sending anything, the mutation is `pending`
///   with `isPaused=true`, and both continue when the connection returns.
/// * `always` — connectivity is ignored: the request goes out and fails like
///   any other, and retries do not pause.
/// * `offlineFirst` — one attempt runs even offline (a service worker or an
///   HTTP cache may answer it); a *retry* after it pauses, which is
///   `retryer.dart`'s `canFetch` for the start and `_canContinue` for the
///   continue.
///
/// Coming back online is the library's own work, not this screen's:
/// `QueryClient.mount` — which `QueryClientProvider` calls — subscribes to the
/// online manager, resumes the paused mutations and only then lets the query
/// cache continue its paused fetches. `Resume paused mutations` is the manual
/// door onto the same call, and it is deliberately *not* a no-op-free one:
/// `MutationCache.resumePaused` gates per mutation, so an `online` mutation
/// asked to resume while still offline is skipped rather than parked on the
/// same wait.
///
/// The mutation's `onSuccess` invalidates the todos but does not return the
/// invalidation's future. Returning it is the idiom the `mutations` screen
/// shows, and it works here too — `invalidateQueries` refetches with
/// `cancelRefetch: true`, so it replaces a paused fetch instead of waiting
/// behind it — but it would keep the mutation `pending` well past the moment
/// its write reached the backend, and that moment is what this screen is
/// about.
///
/// Read through `QueryMixin` (`watchQuery`, `watchMutation`).
///
/// Proofs (widget tests in `test/features/offline_test.dart`, end-to-end in
/// `e2e/tests/offline.spec.ts`): offline, `Refetch` under `online` pauses the
/// query and sends nothing, and going online resumes it with one request, not
/// two; offline, `Add todo` pauses the mutation and sends no `POST`, and going
/// online sends it without anyone asking; `Resume paused mutations` while
/// still offline leaves an `online` mutation exactly where it was; under
/// `always` nothing pauses; under `offlineFirst` the first attempt goes out
/// offline and the retry after it pauses; and two todos added offline are sent
/// in the order they were made once the connection is back.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:tanstack_query_flutter/tanstack_query_flutter.dart';

import '../../shared/api.dart';
import '../../shared/debug_strip.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';
import '../../shared/theme.dart';

const Feature offlineFeature = Feature(
  id: 'offline',
  title: 'Offline',
  summary: 'Network modes, paused mutations, and coming back online.',
  upstream: 'offline',
);

QueryFilters get _todosFilter => QueryFilters(queryKey: ShowcaseKeys.todos);

/// The list, under the mode the screen is set to.
///
/// The retry policy is written out because `offlineFirst` is only visible
/// through it: the first attempt runs offline, and it is the *retry* that
/// pauses. A fixed, short delay keeps that pause a second away rather than
/// the default backoff's one, two and four.
QueryObserverOptions<List<Todo>, List<Todo>> todosQuery(
  ShowcaseApi api,
  NetworkMode mode,
) =>
    QueryObserverOptions<List<Todo>, List<Todo>>(
      queryKey: ShowcaseKeys.todos,
      queryFn: (context) => api.todos(signal: context.signal),
      networkMode: mode,
      retry: const RetryPolicy.times(2),
      retryDelay: const RetryDelay.fixed(Duration(milliseconds: 400)),
    );

/// The write, under the same mode. `retry` stays at a mutation's default of
/// never: pausing is not retrying, and a paused mutation keeps its one
/// attempt for when the network is back.
MutationOptions<Todo, String, void> addTodoMutation(
  ShowcaseApi api,
  QueryClient client,
  NetworkMode mode,
) =>
    MutationOptions.simple<Todo, String>(
      mutationFn: (text) => api.createTodo(text),
      networkMode: mode,
      onSuccess: (_, __, ___) {
        // Fired, not returned: the mutation's status is meant to say when the
        // write reached the backend, and awaiting the refetch would move it
        // to whenever the list came back. See the library doc above.
        client.invalidateQueries(filters: _todosFilter).ignore();
      },
    );

class OfflineScreen extends StatefulWidget {
  const OfflineScreen({super.key});

  @override
  State<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends State<OfflineScreen> with QueryMixin {
  late final ShowcaseApi _api;
  late final QueryClient _client;
  late final void Function() _unsubscribeOnline;
  late final void Function() _unsubscribeMutations;

  final TextEditingController _text = TextEditingController();
  NetworkMode _mode = NetworkMode.online;
  bool _rebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    // Plain reads: a State may not depend on an inherited widget yet, and
    // neither the api nor the client changes underneath a screen.
    _api = context.getInheritedWidgetOfExactType<ShowcaseScope>()!.api;
    _client = QueryClientProvider.read(context);
    // The online state is not part of any query's result, and a mutation the
    // observer no longer holds — the first of two paused writes — still
    // changes what `isMutating` answers.
    _unsubscribeOnline = _client.onlineManager.subscribe((_) => _rebuild());
    _unsubscribeMutations = _client.mutationCache.subscribe((event) {
      // State-changing events only. Every build re-applies the mutation's
      // options, whose callbacks are closures built in `build` and therefore
      // never equal, so `MutationObserverOptionsUpdated` fires once per
      // build — rebuilding on it is a loop that never settles.
      if (event is MutationUpdated ||
          event is MutationAdded ||
          event is MutationRemoved) {
        _rebuild();
      }
    });
  }

  @override
  void dispose() {
    _unsubscribeOnline();
    _unsubscribeMutations();
    _text.dispose();
    super.dispose();
  }

  /// The debug strip's phase-aware rebuild: a cache event can arrive from
  /// inside a frame's build phase, where `setState` is not allowed.
  void _rebuild() {
    if (!mounted || _rebuildScheduled) {
      return;
    }
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      _rebuildScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _rebuildScheduled = false;
        if (mounted) {
          setState(() {});
        }
      });
    } else {
      setState(() {});
    }
  }

  void _submit(void Function(String text) mutate) {
    final text = _text.text.trim();
    if (text.isEmpty) {
      return;
    }
    mutate(text);
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final todos = watchQuery(todosQuery(_api, _mode));
    final add = watchMutation(addTodoMutation(_api, _client, _mode));
    final mutation = add.value;
    final online = _client.onlineManager.isOnline();
    final rows = todos.dataOrNull ?? const <Todo>[];
    final paused = _client.mutationCache.mutations
        .where((entry) => entry.state.isPaused)
        .length;

    return FeatureScaffold(
      feature: offlineFeature,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Notice(
            'Nothing installs a connectivity listener — the binding depends on '
            'no connectivity package — so a client nobody tells otherwise '
            'believes it is online, and this switch is the whole source of '
            'the online state here. A real app passes '
            'QueryClientProvider(onlineStatus: …) a Stream<bool>; six lines '
            'with connectivity_plus, which stays your dependency.',
          ),
        ),
        SectionCard(
          title: 'Connection',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // No subtitle: a tile folds one into the switch's accessible
              // name, and the explanation belongs in its own text anyway.
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Online'),
                value: online,
                onChanged: _client.onlineManager.setOnline,
              ),
              const Text(
                'Turning this back on is all the reconnect there is: the '
                'client is mounted, so it resumes the paused mutations and '
                'then continues the paused fetches by itself.',
              ),
              const SizedBox(height: 12),
              const Text('Network mode'),
              const SizedBox(height: 4),
              SegmentedButton<NetworkMode>(
                showSelectedIcon: false,
                segments: const <ButtonSegment<NetworkMode>>[
                  ButtonSegment<NetworkMode>(
                    value: NetworkMode.online,
                    label: Text('online'),
                  ),
                  ButtonSegment<NetworkMode>(
                    value: NetworkMode.always,
                    label: Text('always'),
                  ),
                  ButtonSegment<NetworkMode>(
                    value: NetworkMode.offlineFirst,
                    label: Text('offlineFirst'),
                  ),
                ],
                selected: <NetworkMode>{_mode},
                onSelectionChanged: (selection) =>
                    setState(() => _mode = selection.first),
              ),
              const SizedBox(height: 12),
              _Toolbar(
                children: <Widget>[
                  _Action(
                    label: 'Refetch',
                    filled: true,
                    onPressed: () => todos.refetch().ignore(),
                  ),
                  _Action(
                    label: 'Resume paused mutations',
                    onPressed: () => _client.resumePausedMutations().ignore(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _Facts(
                <String>[
                  'online=$online',
                  'query fetchStatus=${todos.fetchStatus.name}',
                  'mutation status=${mutation.status.name}',
                  'mutation isPaused=${mutation.isPaused}',
                  'mutations pending=${_client.isMutating()}',
                  'mutations paused=$paused',
                  'todos=${rows.length}',
                ],
                label: 'offline',
              ),
              const SizedBox(height: 8),
              const Text(
                'Resume paused mutations gates per mutation: one under the '
                'online mode is skipped while the device is offline, because '
                'resuming it would only park it on the same wait.',
              ),
            ],
          ),
        ),
        QueryDebugStrip(queryKey: ShowcaseKeys.todos, label: 'todos'),
        SectionCard(
          title: 'Add todo',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _text,
                decoration: const InputDecoration(
                  labelText: 'New todo',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(add.mutate),
              ),
              const SizedBox(height: 12),
              _Toolbar(
                children: <Widget>[
                  _Action(
                    label: 'Add todo',
                    filled: true,
                    onPressed: () => _submit(add.mutate),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (mutation.isPaused)
                const Notice(
                  'The write is waiting for the network. Its request has not '
                  'been sent, and it goes out as it stands the moment the '
                  'connection is back.',
                )
              else if (mutation case MutationError(:final error))
                Notice('Write failed: $error', error: true),
              const SizedBox(height: 8),
              const Text(
                'Every write goes to the same mutation, so adding twice while '
                'offline leaves two paused mutations in the cache — the '
                'observer holds the second, the count holds both.',
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Todos',
          trailing: todos.isFetching ? const Pill('fetching') : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (todos case QueryError(:final error))
                Notice('$error', error: true),
              for (final todo in rows) Text('#${todo.id} ${todo.text}'),
            ],
          ),
        ),
        SectionCard(
          title: 'The three network modes',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const <Widget>[
              Notice(
                'online — the default: nothing is sent while offline, the '
                'query pauses and the mutation pauses, and both continue when '
                'the connection returns.',
              ),
              SizedBox(height: 8),
              Notice(
                'always — connectivity is ignored: the request goes out '
                'offline and fails like any other, and retries never pause.',
              ),
              SizedBox(height: 8),
              Notice(
                'offlineFirst — one attempt runs even offline, for a service '
                'worker or an HTTP cache that can answer it; a retry after '
                'that one pauses, like online.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

const TextStyle _mono = TextStyle(fontFamily: 'monospace', fontSize: 13);

/// A row of buttons, each its own semantics node — several in one row
/// otherwise fold into the row's.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        explicitChildNodes: true,
        child: Wrap(spacing: 8, runSpacing: 8, children: children),
      );
}

/// A button named by its label. The tooltip is for hovering humans and stays
/// out of the semantics tree, so the accessible name is the label alone.
class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: filled
            ? FilledButton.tonal(onPressed: onPressed, child: Text(label))
            : OutlinedButton(onPressed: onPressed, child: Text(label)),
      );
}

/// `key=value` texts, one node each, inside a group a test can address — the
/// strip below says what the cache holds, these say what the screen sees.
class _Facts extends StatelessWidget {
  const _Facts(this.facts, {required this.label});

  final List<String> facts;

  /// The semantics group is `facts <label>`, the widget key `facts-<label>`.
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'facts $label',
        child: Wrap(
          key: ValueKey<String>('facts-$label'),
          spacing: 12,
          runSpacing: 4,
          children: <Widget>[
            for (final fact in facts) Text(fact, style: _mono),
          ],
        ),
      );
}
