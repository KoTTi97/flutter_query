/// Upstream's `offline` example, and the `network-mode` guide next to it: a
/// query and a mutation under a connection the reader controls.
///
/// The switch *is* the connectivity source here. The library installs no
/// listener and depends on no connectivity package
/// (https://github.com/KoTTi97/flutter_query/issues/21), so a client nobody
/// tells otherwise believes it is online — which is what upstream does with
/// no listener too. A real app hands `QueryClientProvider` an
/// `OnlineStatus.stream`; this screen calls
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
/// The reconnect is also an event of its own: `refetchOnReconnect` — the
/// `On reconnect` knob, a [RefetchOn] like the focus screen's — decides
/// whether a query that was *not* paused refetches when the connection
/// returns. The default is `ifStale`, and the todos' stale time is zero, so
/// out of the box every reconnect refetches them; `never` leaves them alone,
/// and `always` would refetch fresh data too.
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
/// offline and the retry after it pauses; two todos added offline are sent
/// in the order they were made once the connection is back; and a reconnect
/// with nothing paused refetches the todos under `always` and not under
/// `never`.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/cache_listener.dart';
import '../../shared/controls.dart';
import '../../shared/debug_strip.dart';
import '../../shared/fact_group.dart';
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
QueryObserverOptions<List<Todo>> todosQuery(
  ShowcaseApi api,
  NetworkMode mode, {
  RefetchOn onReconnect = RefetchOn.ifStale,
}) =>
    QueryObserverOptions<List<Todo>>(
      queryKey: ShowcaseKeys.todos,
      queryFn: (context) => api.todos(signal: context.signal),
      networkMode: mode,
      retry: const RetryPolicy.times(2),
      retryDelay: const RetryDelay.fixed(Duration(milliseconds: 400)),
      refetchOnReconnect: onReconnect,
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

class _OfflineScreenState extends State<OfflineScreen>
    with QueryMixin, PhaseSafeRebuild<OfflineScreen> {
  late final ShowcaseApi _api;
  late final QueryClient _client;
  late final void Function() _unsubscribeOnline;
  late final void Function() _unsubscribeMutations;

  final TextEditingController _text = TextEditingController();
  NetworkMode _mode = NetworkMode.online;
  RefetchOn _onReconnect = RefetchOn.ifStale;

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
    _unsubscribeOnline =
        _client.onlineManager.subscribe((_) => scheduleRebuild());
    _unsubscribeMutations = _client.mutationCache.subscribe((event) {
      // State-changing events only. Every build re-applies the mutation's
      // options, whose callbacks are closures built in `build` and therefore
      // never equal, so `MutationObserverOptionsUpdated` fires once per
      // build — rebuilding on it is a loop that never settles.
      if (event is MutationUpdated ||
          event is MutationAdded ||
          event is MutationRemoved) {
        scheduleRebuild();
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
    final todos =
        watchQuery(todosQuery(_api, _mode, onReconnect: _onReconnect));
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
            'QueryClientProvider(onlineStatus: OnlineStatus.stream(…, '
            'initial: …)); six lines with connectivity_plus, which stays '
            'your dependency.',
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
              // Each segmented button in a named semantics group: this one
              // and the reconnect knob both have an `always`.
              _Knob<NetworkMode>(
                name: 'network-mode',
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
                selected: _mode,
                onChanged: (value) => setState(() => _mode = value),
              ),
              const SizedBox(height: 12),
              const Text('On reconnect'),
              const SizedBox(height: 4),
              _Knob<RefetchOn>(
                name: 'on-reconnect',
                segments: const <ButtonSegment<RefetchOn>>[
                  ButtonSegment<RefetchOn>(
                    value: RefetchOn.never,
                    label: Text('never'),
                  ),
                  ButtonSegment<RefetchOn>(
                    value: RefetchOn.ifStale,
                    label: Text('ifStale'),
                  ),
                  ButtonSegment<RefetchOn>(
                    value: RefetchOn.always,
                    label: Text('always'),
                  ),
                ],
                selected: _onReconnect,
                onChanged: (value) => setState(() => _onReconnect = value),
              ),
              const SizedBox(height: 4),
              const Text(
                'refetchOnReconnect: what a query that was not paused does '
                'when the connection returns. ifStale is the default, and the '
                'todos are stale the moment they arrive, so out of the box '
                'every reconnect refetches them; never leaves them alone.',
              ),
              const SizedBox(height: 12),
              Toolbar(
                children: <Widget>[
                  ActionButton(
                    label: 'Refetch',
                    filled: true,
                    onPressed: () => todos.refetch().ignore(),
                  ),
                  ActionButton(
                    label: 'Resume paused mutations',
                    onPressed: () => _client.resumePausedMutations().ignore(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FactGroup(
                name: 'facts offline',
                facts: <String>[
                  'online=$online',
                  'query fetchStatus=${todos.fetchStatus.name}',
                  'mutation status=${mutation.status.name}',
                  'mutation isPaused=${mutation.isPaused}',
                  'mutations pending=${_client.isMutating()}',
                  'mutations paused=$paused',
                  'todos=${rows.length}',
                ],
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
              Toolbar(
                children: <Widget>[
                  ActionButton(
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

/// A segmented button in a named semantics group, so a test can pick this
/// knob's `always` apart from another's.
class _Knob<T extends Object> extends StatelessWidget {
  const _Knob({
    required this.name,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final String name;
  final List<ButtonSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SemanticsGroup(
        name: name,
        child: SegmentedButton<T>(
          showSelectedIcon: false,
          segments: segments,
          selected: <T>{selected},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      );
}
