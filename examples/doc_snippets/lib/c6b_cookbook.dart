/// The cookbook's architecture and integration recipes
/// (`website/docs/cookbook/`), as code the analyzer sees.
///
/// Same rule as the rest of this package: each region is marked with the page
/// that shows it, and the fence on that page names the region. The recipes'
/// third-party halves — riverpod, bloc, provider, get_it, go_router, freezed,
/// web_socket_channel, shared_preferences — are prose-only on the pages,
/// because this package may not depend on them; everything they call into is
/// here.
///
/// The domain is small and its own, so that this file does not move when the
/// guides' samples do.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

// ---------------------------------------------------------------------------
// Domain and fake transports shared by the recipes
// ---------------------------------------------------------------------------

@immutable
class Project {
  const Project(
      {required this.id, required this.name, required this.openTasks});

  final String id;
  final String name;
  final int openTasks;

  @override
  bool operator ==(Object other) =>
      other is Project &&
      other.id == id &&
      other.name == name &&
      other.openTasks == openTasks;

  @override
  int get hashCode => Object.hash(id, name, openTasks);
}

class ProjectApi {
  Future<List<Project>> list(
          {required String filter, QueryCancelToken? signal}) async =>
      const <Project>[
        Project(id: 'p1', name: 'Website', openTasks: 3),
      ];

  Future<Project> get(String id, {QueryCancelToken? signal}) async =>
      Project(id: id, name: 'Website', openTasks: 3);
}

final ProjectApi projectApi = ProjectApi();

abstract final class ProjectKeys {
  static final QueryKey all = QueryKey(<Object?>['projects']);

  static QueryKey list(String filter) => all.append(<Object?>['list', filter]);

  static QueryKey detail(String id) => all.append(<Object?>['detail', id]);
}

class ProjectsApp extends StatelessWidget {
  const ProjectsApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: ProjectScreen(id: 'p1'));
}

// ---------------------------------------------------------------------------
// cookbook/riverpod-bloc-provider.md
// ---------------------------------------------------------------------------

// >>> cookbook/riverpod-bloc-provider.md#queries
QueryObserverOptions<Project> projectQuery(String id) => QueryObserverOptions(
      queryKey: ProjectKeys.detail(id),
      queryFn: (context) => projectApi.get(id, signal: context.signal),
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    );

QueryObserverOptions<List<Project>> projectsQuery(String filter) =>
    QueryObserverOptions(
      queryKey: ProjectKeys.list(filter),
      queryFn: (context) =>
          projectApi.list(filter: filter, signal: context.signal),
    );
// <<<

// >>> cookbook/riverpod-bloc-provider.md#view-model
class ProjectsViewModel extends ChangeNotifier {
  ProjectsViewModel(QueryClient client)
      : projects = QueryController.create(client, projectsQuery('open'));

  /// Server state: a listenable of its own, owned and disposed here.
  final QueryController<List<Project>, List<Project>> projects;

  /// Client state: this app's alone, and never stale.
  String _filter = 'open';
  String get filter => _filter;

  void showFilter(String filter) {
    if (filter == _filter) return;
    _filter = filter;
    // The key follows the filter; the controller switches entries in place.
    projects.setOptions(projectsQuery(filter));
    notifyListeners();
  }

  @override
  void dispose() {
    projects.dispose();
    super.dispose();
  }
}
// <<<

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  late final ProjectsViewModel model =
      ProjectsViewModel(QueryClientProvider.read(context));

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  // >>> cookbook/riverpod-bloc-provider.md#view-model-screen
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        // Rebuilds for either kind of state: a new filter, or a new result.
        listenable: Listenable.merge(<Listenable>[model, model.projects]),
        builder: (context, _) => Column(
          children: <Widget>[
            SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment(value: 'open', label: Text('Open')),
                ButtonSegment(value: 'archived', label: Text('Archived')),
              ],
              selected: <String>{model.filter},
              onSelectionChanged: (selection) =>
                  model.showFilter(selection.single),
            ),
            for (final project
                in model.projects.value.dataOrNull ?? const <Project>[])
              ListTile(title: Text(project.name)),
          ],
        ),
      );
  // <<<
}

// ---------------------------------------------------------------------------
// cookbook/offline-first-and-persistence.md
// ---------------------------------------------------------------------------

@immutable
class Note {
  const Note({required this.id, required this.text});

  factory Note.fromJson(Map<String, Object?> json) =>
      Note(id: json['id']! as String, text: json['text']! as String);

  final String id;
  final String text;

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'text': text};

  @override
  bool operator ==(Object other) =>
      other is Note && other.id == id && other.text == text;

  @override
  int get hashCode => Object.hash(id, text);
}

/// What a new note is sent with. The id is made on the device, so the server
/// can tell a replayed write from a second one.
@immutable
class NewNote {
  const NewNote({required this.clientId, required this.text});

  factory NewNote.fromJson(Map<String, Object?> json) => NewNote(
      clientId: json['clientId']! as String, text: json['text']! as String);

  final String clientId;
  final String text;

  Map<String, Object?> toJson() =>
      <String, Object?>{'clientId': clientId, 'text': text};
}

class NotesApi {
  Future<List<Note>> list({QueryCancelToken? signal}) async => const <Note>[];

  Future<Note> add(NewNote note) async =>
      Note(id: note.clientId, text: note.text);
}

final NotesApi notesApi = NotesApi();

final QueryKey notesKey = QueryKey(<Object?>['notes']);

QueryObserverOptions<List<Note>> notesQuery() => QueryObserverOptions(
      queryKey: notesKey,
      queryFn: (context) => notesApi.list(signal: context.signal),
    );

// >>> cookbook/offline-first-and-persistence.md#client
QueryClient buildClient() => QueryClient(
      defaultOptions: const DefaultOptions(
        queries: QueryDefaults(
          // Try once even offline — the HTTP layer may answer from its own
          // disk cache — and pause instead of retrying.
          networkMode: NetworkMode.offlineFirst,
          // Keep unobserved entries for a day, so a restored snapshot is
          // still there when the screen that reads it opens.
          gcTime: GcTime.duration(Duration(hours: 24)),
        ),
        mutations: MutationDefaults(
          // Said out loud: the query default above does not reach mutations.
          // `online` pauses a write made offline and sends it on reconnect.
          networkMode: NetworkMode.online,
        ),
      ),
    );
// <<<

// >>> cookbook/offline-first-and-persistence.md#store
/// Where a snapshot lives: shared_preferences, a file, a database.
abstract interface class SnapshotStore {
  Future<String?> read(String name);
  Future<void> write(String name, String value);
}
// <<<

// >>> cookbook/offline-first-and-persistence.md#persisted-query
/// One query that survives a restart, and how its data becomes JSON.
class PersistedQuery<T> {
  const PersistedQuery({
    required this.name,
    required this.key,
    required Object? Function(T data) toJson,
    required T Function(Object? json) fromJson,
  })  : _toJson = toJson,
        _fromJson = fromJson;

  final String name;
  final QueryKey key;
  final Object? Function(T data) _toJson;
  final T Function(Object? json) _fromJson;

  Object? save(Query<Object?> query) => <String, Object?>{
        'savedAt': query.state.dataUpdatedAt!.millisecondsSinceEpoch,
        'data': _toJson(query.state.data as T),
      };

  void restore(QueryClient client, Object? saved, {required Duration maxAge}) {
    if (saved is! Map<String, Object?>) return;
    final savedAt =
        DateTime.fromMillisecondsSinceEpoch(saved['savedAt']! as int);
    if (DateTime.now().difference(savedAt) > maxAge) return;
    // Dated when it was fetched, not now: staleTime counts from there, so
    // a screen that reads it refetches old data as usual.
    client.setQueryData<T>(key, _fromJson(saved['data']), updatedAt: savedAt);
  }
}
// <<<

// >>> cookbook/offline-first-and-persistence.md#persister
class QueryPersister {
  QueryPersister(this.client, this.store, this.queries);

  final QueryClient client;
  final SnapshotStore store;
  final List<PersistedQuery<Object?>> queries;

  final Map<String, Object?> _snapshot = <String, Object?>{};
  void Function()? _unsubscribe;
  Timer? _flush;

  /// Before `runApp`: put what was saved back into the cache.
  Future<void> restore({Duration maxAge = const Duration(days: 1)}) async {
    final raw = await store.read('queries');
    if (raw == null) return;
    final saved = jsonDecode(raw) as Map<String, Object?>;
    _snapshot.addAll(saved);
    for (final query in queries) {
      query.restore(client, saved[query.name], maxAge: maxAge);
    }
  }

  /// Then: save every new success of a listed key, at most once a second.
  void start() {
    _unsubscribe = client.queryCache.subscribe((event) {
      if (event case QueryUpdated(:final query, action: QuerySuccessAction())) {
        for (final persisted in queries) {
          if (persisted.key == query.queryKey) {
            _snapshot[persisted.name] = persisted.save(query);
            _flush ??= Timer(const Duration(seconds: 1), _write);
          }
        }
      }
    });
  }

  void _write() {
    _flush = null;
    store.write('queries', jsonEncode(_snapshot)).ignore();
  }

  void stop() {
    _unsubscribe?.call();
    _flush?.cancel();
  }
}
// <<<

// >>> cookbook/offline-first-and-persistence.md#add-note
final QueryKey addNoteKey = QueryKey(<Object?>['addNote']);

MutationOptions<Note, NewNote, void> addNoteMutation(QueryClient client) =>
    MutationOptions.simple(
      mutationKey: addNoteKey,
      mutationFn: notesApi.add,
      onSuccess: (_, __, ___) =>
          client.invalidateQueries(filters: QueryFilters(queryKey: notesKey)),
    );
// <<<

// >>> cookbook/offline-first-and-persistence.md#paused-writes
class PausedWrites {
  PausedWrites(this.client, this.store);

  final QueryClient client;
  final SnapshotStore store;
  String? _last;

  /// Before `runApp`: rebuild every write that had not gone through. Each
  /// comes back pending and paused, with the options built in code again —
  /// a function cannot be saved, and does not have to be.
  Future<void> restore() async {
    final raw = await store.read('addNote');
    if (raw == null) return;
    for (final json in jsonDecode(raw) as List<Object?>) {
      client.mutationCache.build(
        client,
        client.defaultMutationOptions(addNoteMutation(client)),
        state: MutationState<Note, NewNote, void>(
          status: MutationStatus.pending,
          variables: NewNote.fromJson(json! as Map<String, Object?>),
          hasVariables: true,
        ),
      );
    }
    // Online, they go now; offline, each waits for the reconnect.
    client.resumePausedMutations().ignore();
  }

  /// Then: keep the list of unfinished writes on disk.
  void start() {
    client.mutationCache.subscribe((_) {
      final waiting = <Object?>[
        for (final mutation in client.mutationCache.findAll(
          filters: MutationFilters(mutationKey: addNoteKey),
        ))
          if (mutation.state.status == MutationStatus.pending)
            (mutation.state.variables! as NewNote).toJson(),
      ];
      final json = jsonEncode(waiting);
      if (json == _last) return;
      _last = json;
      store.write('addNote', json).ignore();
    });
  }
}
// <<<

/// Stands in for shared_preferences in the compiled twin.
class MemoryStore implements SnapshotStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String name) async => _values[name];

  @override
  Future<void> write(String name, String value) async => _values[name] = value;
}

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(home: SizedBox());
}

// >>> cookbook/offline-first-and-persistence.md#main
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = MemoryStore(); // your shared_preferences adapter
  final client = buildClient();

  final persister = QueryPersister(client, store, <PersistedQuery<Object?>>[
    PersistedQuery<List<Note>>(
      name: 'notes',
      key: notesKey,
      toJson: (notes) => <Object?>[for (final n in notes) n.toJson()],
      fromJson: (json) => <Note>[
        for (final n in json! as List<Object?>)
          Note.fromJson(n! as Map<String, Object?>),
      ],
    ),
  ]);
  final writes = PausedWrites(client, store);

  await persister.restore();
  await writes.restore();
  persister.start();
  writes.start();

  runApp(QueryClientProvider(client: client, child: const NotesApp()));
}
// <<<

// ---------------------------------------------------------------------------
// cookbook/dependency-injection.md
// ---------------------------------------------------------------------------

const DefaultOptions appDefaults = DefaultOptions(
  queries: QueryDefaults(retry: RetryPolicy.times(2)),
);

void runProjectsApp() {
  // >>> cookbook/dependency-injection.md#create
  runApp(
    QueryClientProvider.create(
      create: () => QueryClient(defaultOptions: appDefaults),
      child: const ProjectsApp(),
    ),
  );
  // <<<
}

// >>> cookbook/dependency-injection.md#lookups
class ProjectCard extends StatefulWidget {
  const ProjectCard({super.key, required this.id});

  final String id;

  @override
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard> {
  // `read`: no dependency, so it is allowed in initState and in callbacks.
  late final QueryController<Project, Project> project = QueryController.create(
    QueryClientProvider.read(context),
    projectQuery(widget.id),
  );

  @override
  void dispose() {
    project.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // `of`: in build, where depending on the provider is what you want.
    final client = QueryClientProvider.of(context);
    return ValueListenableBuilder(
      valueListenable: project,
      builder: (context, result, _) => ListTile(
        title: Text(result.dataOrNull?.name ?? '…'),
        onTap: () => client.invalidateQueries(
          filters: QueryFilters(queryKey: ProjectKeys.detail(widget.id)),
        ),
      ),
    );
  }
}
// <<<

// >>> cookbook/dependency-injection.md#maybe-of
/// From a shared design-system package: it shows a thin progress bar under a
/// QueryClientProvider, and nothing in an app that has none.
class FetchingBar extends StatelessWidget {
  const FetchingBar({super.key});

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.maybeOf(context);
    if (client == null) return const SizedBox.shrink();
    return _FetchingBar(client: client);
  }
}
// <<<

class _FetchingBar extends StatefulWidget {
  const _FetchingBar({required this.client});

  final QueryClient client;

  @override
  State<_FetchingBar> createState() => _FetchingBarState();
}

class _FetchingBarState extends State<_FetchingBar> {
  late final IsFetchingController fetching =
      IsFetchingController(widget.client);

  @override
  void dispose() {
    fetching.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: fetching,
        builder: (context, count, _) => count > 0
            ? const LinearProgressIndicator()
            : const SizedBox(height: 4),
      );
}

// >>> cookbook/dependency-injection.md#per-user
class SignedInScope extends StatelessWidget {
  const SignedInScope({super.key, required this.userId, required this.child});

  final String userId;
  final Widget child;

  @override
  Widget build(BuildContext context) => QueryClientProvider.create(
        // Another user is another key: the old provider is disposed and its
        // client cleared, and the subtree starts over on an empty cache.
        key: ValueKey<String>(userId),
        create: () => QueryClient(defaultOptions: appDefaults),
        child: child,
      );
}
// <<<

class LeakyRoot extends StatelessWidget {
  const LeakyRoot({super.key});

  // >>> cookbook/dependency-injection.md#never-in-build
  // Wrong: every rebuild makes a new client — a new, empty cache — and the
  // screens below lose everything they had loaded.
  @override
  Widget build(BuildContext context) =>
      QueryClientProvider(client: QueryClient(), child: const ProjectsApp());
  // <<<
}

// ---------------------------------------------------------------------------
// cookbook/routing-go-router.md
// ---------------------------------------------------------------------------

// >>> cookbook/routing-go-router.md#screen
class ProjectScreen extends StatelessWidget {
  const ProjectScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final project = context.query(projectQuery(id));
    return Scaffold(
      appBar: AppBar(title: Text(project.dataOrNull?.name ?? '')),
      body: switch (project) {
        QueryPending() => const Center(child: CircularProgressIndicator()),
        QueryError(:final error) => Center(child: Text('$error')),
        QuerySuccess(:final data) =>
          Center(child: Text('${data.openTasks} open tasks')),
      },
    );
  }
}
// <<<

// >>> cookbook/routing-go-router.md#prefetch-on-tap
class ProjectTile extends StatelessWidget {
  const ProjectTile(this.project, {super.key});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    return ListTile(
      title: Text(project.name),
      onTap: () {
        // Start the fetch before the route animates in; the screen's read
        // joins it, or finds it done.
        client.query(projectQuery(project.id)).ignore();
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ProjectScreen(id: project.id),
        ));
      },
    );
  }
}
// <<<

// >>> cookbook/routing-go-router.md#refetch-on-return
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

/// Refetches [queryKey]'s stale entries when the route it sits in becomes
/// visible again — when the route pushed over it is popped.
class RefetchOnReturn extends StatefulWidget {
  const RefetchOnReturn(
      {super.key, required this.queryKey, required this.child});

  final QueryKey queryKey;
  final Widget child;

  @override
  State<RefetchOnReturn> createState() => _RefetchOnReturnState();
}

class _RefetchOnReturnState extends State<RefetchOnReturn> with RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    QueryClientProvider.read(context)
        .refetchQueries(
          filters: QueryFilters(
            queryKey: widget.queryKey,
            type: QueryTypeFilter.active,
            stale: true,
          ),
        )
        .ignore();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
// <<<

// >>> cookbook/routing-go-router.md#dialog
Future<void> showProjectDialog(BuildContext context, String id) =>
    showDialog<void>(
      context: context,
      // A widget of its own, reading through its own context: subscribed for
      // as long as the dialog is open, and rebuilt when the project changes.
      builder: (_) => ProjectDialog(id: id),
    );

class ProjectDialog extends StatelessWidget {
  const ProjectDialog({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final project = context.query(projectQuery(id));
    return AlertDialog(
      title: Text(project.dataOrNull?.name ?? '…'),
      content: Text('${project.dataOrNull?.openTasks ?? '–'} open tasks'),
    );
  }
}
// <<<

// ---------------------------------------------------------------------------
// cookbook/realtime-websockets.md
// ---------------------------------------------------------------------------

@immutable
class Order {
  const Order({required this.id, required this.status, required this.version});

  final String id;
  final String status;

  /// Goes up with every change on the server.
  final int version;

  @override
  bool operator ==(Object other) =>
      other is Order &&
      other.id == id &&
      other.status == status &&
      other.version == version;

  @override
  int get hashCode => Object.hash(id, status, version);
}

class OrdersApi {
  Future<Order> get(String id, {QueryCancelToken? signal}) async =>
      Order(id: id, status: 'packing', version: 1);
}

final OrdersApi ordersApi = OrdersApi();

abstract final class OrderKeys {
  static final QueryKey all = QueryKey(<Object?>['orders']);
  static final QueryKey lists = all.append(<Object?>['list']);

  static QueryKey detail(String id) => all.append(<Object?>['detail', id]);
}

// >>> cookbook/realtime-websockets.md#events
sealed class ServerEvent {
  const ServerEvent();
}

/// An order changed, and the event carries all of it.
final class OrderChanged extends ServerEvent {
  const OrderChanged(this.order);

  final Order order;
}

/// An order is gone.
final class OrderRemoved extends ServerEvent {
  const OrderRemoved(this.id);

  final String id;
}

/// Events may have been missed — the socket reconnected.
final class Resync extends ServerEvent {
  const Resync();
}
// <<<

// >>> cookbook/realtime-websockets.md#order-query
QueryObserverOptions<Order> orderQuery(String id) => QueryObserverOptions(
      queryKey: OrderKeys.detail(id),
      queryFn: (context) => ordersApi.get(id, signal: context.signal),
      // The socket keeps it fresh. The stale time is only the safety net
      // for a socket that went quiet without anybody noticing.
      staleTime: const StaleTime.duration(Duration(minutes: 5)),
    );
// <<<

// >>> cookbook/realtime-websockets.md#sync
class RealtimeSync {
  RealtimeSync(this.client);

  final QueryClient client;

  StreamSubscription<ServerEvent> listen(Stream<ServerEvent> events) =>
      events.listen(apply);

  void apply(ServerEvent event) {
    switch (event) {
      case OrderChanged(:final order):
        // The whole order is in the event: write it, unless the cache
        // already holds the same version or a newer one.
        client.updateQueryData<Order>(
          OrderKeys.detail(order.id),
          (cached) =>
              cached != null && cached.version >= order.version ? null : order,
        );
        // Which lists it belongs to, and where, is the server's business.
        client
            .invalidateQueries(filters: QueryFilters(queryKey: OrderKeys.lists))
            .ignore();
      case OrderRemoved(:final id):
        client
            .invalidateQueries(filters: QueryFilters(queryKey: OrderKeys.lists))
            .ignore();
        client
            .invalidateQueries(
                filters: QueryFilters(queryKey: OrderKeys.detail(id)))
            .ignore();
      case Resync():
        client
            .invalidateQueries(filters: QueryFilters(queryKey: OrderKeys.all))
            .ignore();
    }
  }
}
// <<<

// >>> cookbook/realtime-websockets.md#live-scope
/// Keeps the cache in step with [events] for as long as it is mounted. Put it
/// below the QueryClientProvider and above the screens.
class LiveOrders extends StatefulWidget {
  const LiveOrders({super.key, required this.events, required this.child});

  final Stream<ServerEvent> events;
  final Widget child;

  @override
  State<LiveOrders> createState() => _LiveOrdersState();
}

class _LiveOrdersState extends State<LiveOrders> {
  late final StreamSubscription<ServerEvent> _subscription;

  @override
  void initState() {
    super.initState();
    _subscription =
        RealtimeSync(QueryClientProvider.read(context)).listen(widget.events);
  }

  @override
  void dispose() {
    _subscription.cancel().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
// <<<

// ---------------------------------------------------------------------------
// cookbook/poll-until-confirmed.md
// ---------------------------------------------------------------------------

// >>> cookbook/poll-until-confirmed.md#model
@immutable
class Relay {
  const Relay({
    required this.id,
    required this.on,
    this.requestedOn,
    this.pendingSince,
  });

  final String id;

  /// What the device last confirmed.
  final bool on;

  /// What a write asked for and the device has not confirmed; `null` when
  /// nothing is outstanding. A field of its own, so that a poll answer
  /// cannot overwrite the value the user just chose.
  final bool? requestedOn;

  /// When the server accepted a write the device has not confirmed yet.
  final DateTime? pendingSince;

  bool get isPending => pendingSince != null;

  /// What the switch shows: a requested value outranks the confirmed one.
  bool get shownOn => requestedOn ?? on;

  Relay copyWith({bool? requestedOn}) => Relay(
        id: id,
        on: on,
        requestedOn: requestedOn ?? this.requestedOn,
        pendingSince: pendingSince,
      );

  @override
  bool operator ==(Object other) =>
      other is Relay &&
      other.id == id &&
      other.on == on &&
      other.requestedOn == requestedOn &&
      other.pendingSince == pendingSince;

  @override
  int get hashCode => Object.hash(id, on, requestedOn, pendingSince);
}
// <<<

class RelayApi {
  Future<Relay> get(String id, {QueryCancelToken? signal}) async =>
      Relay(id: id, on: false);

  /// Accepted, not confirmed: the answer carries `pendingSince`.
  Future<Relay> set(String id, {required bool on}) async =>
      Relay(id: id, on: !on, requestedOn: on, pendingSince: DateTime.now());
}

final RelayApi relayApi = RelayApi();

QueryKey relayKey(String id) => QueryKey(<Object?>['relay', id]);

// >>> cookbook/poll-until-confirmed.md#query
const Duration confirmTimeout = Duration(seconds: 30);

QueryObserverOptions<Relay> relayQuery(String id) => QueryObserverOptions(
      queryKey: relayKey(id),
      queryFn: (context) => relayApi.get(id, signal: context.signal),
      refetchInterval: const RefetchInterval.dynamic(pollWhilePending),
      // A confirmation that lands while the user glances away still counts.
      refetchIntervalInBackground: true,
    );

/// Asked again after every poll: half a second while the device owes a
/// confirmation, and `null` — stop — once it has answered or given up.
Duration? pollWhilePending(Query<Object?> query) {
  final relay = query.state.data;
  if (relay is! Relay || !relay.isPending) return null;
  if (gaveUp(relay, query.state.consecutiveErrorCount)) return null;
  return const Duration(milliseconds: 500);
}

/// Five failed polls in a row, or no confirmation within [confirmTimeout].
bool gaveUp(Relay relay, int consecutiveErrors) =>
    consecutiveErrors >= 5 ||
    DateTime.now().difference(relay.pendingSince!) > confirmTimeout;
// <<<

// >>> cookbook/poll-until-confirmed.md#mutation
typedef RelayWrite = ({String id, bool on});

MutationOptions<Relay, RelayWrite, Relay?> switchRelay(QueryClient client) =>
    MutationOptions<Relay, RelayWrite, Relay?>(
      mutationFn: (write) => relayApi.set(write.id, on: write.on),
      onMutate: (write) async {
        final key = relayKey(write.id);
        await client.cancelQueries(filters: QueryFilters(queryKey: key));
        final previous = client.getQueryData<Relay>(key);
        // The requested value, not the confirmed one — and no pendingSince:
        // polling starts when the server has accepted, not before.
        client.updateQueryData<Relay>(
          key,
          (relay) => relay?.copyWith(requestedOn: write.on),
        );
        return previous;
      },
      onError: (_, __, write, previous) {
        if (previous != null) {
          client.setQueryData<Relay>(relayKey(write.id), previous);
        }
      },
      // The answer says "pending": writing it is what starts the poll.
      onSuccess: (accepted, write, _) =>
          client.setQueryData<Relay>(relayKey(write.id), accepted),
    );
// <<<

// >>> cookbook/poll-until-confirmed.md#switch
class RelaySwitch extends StatelessWidget {
  const RelaySwitch({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    final result = context.query(relayQuery(id));
    final write = context.mutation(switchRelay(client));

    final relay = result.dataOrNull;
    if (relay == null) {
      return ListTile(
        title: const Text('Relay'),
        subtitle: Text(result.isError ? 'Unreachable' : 'Loading…'),
      );
    }
    return SwitchListTile(
      title: const Text('Relay'),
      value: relay.shownOn,
      subtitle: Text(switch (relay) {
        Relay(isPending: false, on: true) => 'On',
        Relay(isPending: false) => 'Off',
        _ when gaveUp(relay, result.consecutiveErrorCount) =>
          'The device did not confirm',
        _ => 'Waiting for the device…',
      }),
      onChanged: write.value.isPending || relay.isPending
          ? null
          : (on) => write.mutate((id: id, on: on)),
    );
  }
}
// <<<

// ---------------------------------------------------------------------------
// cookbook/device-and-iot-disconnect.md
// ---------------------------------------------------------------------------

@immutable
class DeviceStatus {
  const DeviceStatus({required this.temperature});

  final double temperature;

  @override
  bool operator ==(Object other) =>
      other is DeviceStatus && other.temperature == temperature;

  @override
  int get hashCode => temperature.hashCode;
}

// >>> cookbook/device-and-iot-disconnect.md#keys
abstract final class DeviceKeys {
  static final QueryKey all = QueryKey(<Object?>['devices']);

  /// Everything about one device lives under this prefix.
  static QueryKey device(String id) => all.append(<Object?>[id]);

  static QueryKey status(String id) => device(id).append(<Object?>['status']);
}
// <<<

// >>> cookbook/device-and-iot-disconnect.md#connection
class DeviceGone implements Exception {
  const DeviceGone(this.deviceId);

  final String deviceId;

  @override
  String toString() => 'Device $deviceId is disconnected';
}

class DeviceConnection {
  DeviceConnection(this.deviceId);

  final String deviceId;

  /// Whether the device may be talked to. Screens rebuild on it.
  final ValueNotifier<bool> open = ValueNotifier<bool>(true);

  Future<DeviceStatus> status({QueryCancelToken? signal}) async {
    _ensureOpen();
    return const DeviceStatus(temperature: 21.5); // the real call goes here
  }

  /// From here on every call refuses, before anything goes on the wire.
  void close() => open.value = false;

  void _ensureOpen() {
    if (!open.value) throw DeviceGone(deviceId);
  }
}
// <<<

// >>> cookbook/device-and-iot-disconnect.md#client
QueryClient buildDeviceClient() => QueryClient(
      defaultOptions: const DefaultOptions(
        queries: QueryDefaults(
          // A device on the local network answers whatever the phone's
          // internet connection says.
          networkMode: NetworkMode.always,
          retry: RetryPolicy.when(retryUnlessGone),
        ),
        // Not inherited from the query defaults: said again.
        mutations: MutationDefaults(networkMode: NetworkMode.always),
      ),
    );

bool retryUnlessGone(int failureCount, Object error, StackTrace _) =>
    error is! DeviceGone && failureCount < 2;
// <<<

// >>> cookbook/device-and-iot-disconnect.md#status-query
QueryObserverOptions<DeviceStatus> deviceStatusQuery(
  DeviceConnection connection, {
  required bool open,
}) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.status(connection.deviceId),
      queryFn: (context) => connection.status(signal: context.signal),
      // Values, not callbacks: a closed connection rebuilds the screen, and
      // the rebuild hands the observer options that neither fetch nor poll.
      enabled: open ? Enabled.yes : Enabled.no,
      refetchInterval: open
          ? const RefetchInterval.every(Duration(seconds: 2))
          : RefetchInterval.off,
    );
// <<<

// >>> cookbook/device-and-iot-disconnect.md#screen
class DeviceScreen extends StatelessWidget {
  const DeviceScreen({super.key, required this.connection});

  final DeviceConnection connection;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: connection.open,
        builder: (_, open, __) =>
            DeviceStatusView(connection: connection, open: open),
      );
}

class DeviceStatusView extends StatelessWidget {
  const DeviceStatusView(
      {super.key, required this.connection, required this.open});

  final DeviceConnection connection;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final status = context.query(deviceStatusQuery(connection, open: open));
    return ListTile(
      title: Text(connection.deviceId),
      subtitle: Text(switch (status) {
        _ when !open => 'Disconnected',
        QuerySuccess(:final data) => '${data.temperature} °C',
        QueryError(:final error) => '$error',
        QueryPending() => 'Connecting…',
      }),
    );
  }
}
// <<<

// >>> cookbook/device-and-iot-disconnect.md#disconnect
Future<void> disconnect(QueryClient client, DeviceConnection connection) async {
  // 1. The transport refuses, and every screen of the device rebuilds with
  //    its queries disabled.
  connection.close();
  await WidgetsBinding.instance.endOfFrame;
  // 2. Only now the entries: no reader is left that would fetch them again.
  //    Removing an entry also cancels a fetch it still has in flight.
  client.removeQueries(
    filters: QueryFilters(queryKey: DeviceKeys.device(connection.deviceId)),
  );
}
// <<<

// ---------------------------------------------------------------------------
// cookbook/sign-out-and-multi-account.md
// ---------------------------------------------------------------------------

// >>> cookbook/sign-out-and-multi-account.md#auth-gate
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.userId});

  /// From your session state: `null` while nobody is signed in.
  final String? userId;

  @override
  Widget build(BuildContext context) => switch (userId) {
        null => const MaterialApp(home: SignInScreen()),
        final String id => SignedInScope(userId: id, child: const HomeApp()),
      };
}
// <<<

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold();
}

class HomeApp extends StatelessWidget {
  const HomeApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(home: Scaffold());
}

// >>> cookbook/sign-out-and-multi-account.md#shell
/// Everything a signed-in user sees is below this widget, on a client the
/// whole app shares. When it goes, the user's cache goes with it.
class SignedInShell extends StatefulWidget {
  const SignedInShell({super.key, required this.child});

  final Widget child;

  @override
  State<SignedInShell> createState() => _SignedInShellState();
}

class _SignedInShellState extends State<SignedInShell> {
  late final QueryClient _client;

  @override
  void initState() {
    super.initState();
    // Looked up while mounted: in dispose, the ancestors are out of reach.
    _client = QueryClientProvider.read(context);
  }

  @override
  void dispose() {
    // Flutter disposes children before their parent, so every reader below
    // is gone and nothing refetches what this empties.
    _client.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
// <<<

// >>> cookbook/sign-out-and-multi-account.md#unsaved-writes
/// Asks before signing out over writes that have not gone through.
Future<bool> mayDropWrites(BuildContext context) async {
  final writing = QueryClientProvider.read(context).isMutating();
  if (writing == 0) return true;
  final drop = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('$writing changes are not saved yet'),
      content: const Text('Sign out anyway? They will be lost.'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Stay'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  return drop ?? false;
}
// <<<

// >>> cookbook/sign-out-and-multi-account.md#account-keys
abstract final class AccountKeys {
  static QueryKey account(String userId) =>
      QueryKey(<Object?>['account', userId]);

  static QueryKey inbox(String userId) =>
      account(userId).append(<Object?>['inbox']);
}

/// Forget one account, and keep the others this client holds.
void forgetAccount(QueryClient client, String userId) => client.removeQueries(
      filters: QueryFilters(queryKey: AccountKeys.account(userId)),
    );
// <<<

// ---------------------------------------------------------------------------
// cookbook/normalised-vs-per-entity-keys.md
// ---------------------------------------------------------------------------

@immutable
class Contact {
  const Contact({required this.id, required this.name});

  final String id;
  final String name;

  Contact copyWith({String? name}) => Contact(id: id, name: name ?? this.name);

  @override
  bool operator ==(Object other) =>
      other is Contact && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

class ContactsApi {
  Future<List<Contact>> list({QueryCancelToken? signal}) async =>
      const <Contact>[Contact(id: 'c1', name: 'Ada')];

  Future<Contact> get(String id, {QueryCancelToken? signal}) async =>
      Contact(id: id, name: 'Ada');
}

final ContactsApi contactsApi = ContactsApi();

// >>> cookbook/normalised-vs-per-entity-keys.md#per-entity
abstract final class ContactKeys {
  static final QueryKey all = QueryKey(<Object?>['contacts']);
  static final QueryKey list = all.append(<Object?>['list']);
  static final QueryKey byId = all.append(<Object?>['by-id']);

  static QueryKey detail(String id) => all.append(<Object?>['detail', id]);
}

QueryObserverOptions<List<Contact>> contactListQuery(QueryClient client) =>
    QueryObserverOptions(
      queryKey: ContactKeys.list,
      queryFn: (context) async {
        final contacts = await contactsApi.list(signal: context.signal);
        // Every contact is also an entry of its own, seeded fresh, so the
        // detail screen opens without a request and later list fetches
        // keep it current.
        for (final contact in contacts) {
          client.setQueryData<Contact>(ContactKeys.detail(contact.id), contact);
        }
        return contacts;
      },
    );

QueryObserverOptions<Contact> contactQuery(String id) => QueryObserverOptions(
      queryKey: ContactKeys.detail(id),
      queryFn: (context) => contactsApi.get(id, signal: context.signal),
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    );
// <<<

// >>> cookbook/normalised-vs-per-entity-keys.md#share-by-id
/// A structuralSharing hook for a normalised map: an unchanged contact keeps
/// the instance the cache already holds, and nothing changed at all keeps the
/// whole map.
Map<String, Contact> shareById(
  Map<String, Contact>? previous,
  Map<String, Contact> next,
) {
  if (previous == null) return next;
  var changed = previous.length != next.length;
  final shared = <String, Contact>{};
  for (final MapEntry(:key, :value) in next.entries) {
    final kept = previous[key];
    if (kept == value) {
      shared[key] = kept!;
    } else {
      shared[key] = value;
      changed = true;
    }
  }
  return changed ? shared : previous;
}

QueryObserverOptions<Map<String, Contact>> contactsByIdQuery() =>
    QueryObserverOptions(
      queryKey: ContactKeys.byId,
      queryFn: (context) async => <String, Contact>{
        for (final contact in await contactsApi.list(signal: context.signal))
          contact.id: contact,
      },
      structuralSharing: shareById,
    );
// <<<

// >>> cookbook/normalised-vs-per-entity-keys.md#row
class ContactRow extends StatelessWidget {
  const ContactRow({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final contact = context.selectQuery(
      contactsByIdQuery().withSelect((byId) => byId[id]),
      // A refetch that leaves this contact alone rebuilds nothing here.
      buildWhen: (previous, current) =>
          previous.dataOrNull != current.dataOrNull,
    );
    return ListTile(title: Text(contact.dataOrNull?.name ?? '…'));
  }
}
// <<<

// >>> cookbook/normalised-vs-per-entity-keys.md#contact-book
/// The normalised shape many APIs answer with: entities by id, plus an order.
@immutable
class ContactBook implements StructurallyShareable<ContactBook> {
  const ContactBook({required this.byId, required this.order});

  final Map<String, Contact> byId;
  final List<String> order;

  // Asked only when the two are not equal: share what did not change.
  @override
  ContactBook shareWith(ContactBook previous) => ContactBook(
        byId: shareById(previous.byId, byId),
        order: replaceEqualDeep(previous.order, order),
      );

  @override
  bool operator ==(Object other) =>
      other is ContactBook &&
      mapEquals(other.byId, byId) &&
      listEquals(other.order, order);

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(byId.values),
        Object.hashAll(order),
      );
}
// <<<

// ---------------------------------------------------------------------------
// cookbook/freezed-and-json-models.md
// ---------------------------------------------------------------------------

// >>> cookbook/freezed-and-json-models.md#by-hand
/// What freezed generates, in essence — and what a model needs either way.
@immutable
class Invoice {
  const Invoice(
      {required this.id, required this.customer, required this.cents});

  factory Invoice.fromJson(Map<String, Object?> json) => Invoice(
        id: json['id']! as String,
        customer: json['customer']! as String,
        cents: json['cents']! as int,
      );

  final String id;
  final String customer;
  final int cents;

  @override
  bool operator ==(Object other) =>
      other is Invoice &&
      other.id == id &&
      other.customer == customer &&
      other.cents == cents;

  @override
  int get hashCode => Object.hash(id, customer, cents);
}
// <<<

/// A wrapper with value equality and nothing else: a leaf to sharing.
@immutable
class InvoiceList {
  const InvoiceList(this.items);

  final List<Invoice> items;

  @override
  bool operator ==(Object other) =>
      other is InvoiceList && listEquals(other.items, items);

  @override
  int get hashCode => Object.hashAll(items);
}

// >>> cookbook/freezed-and-json-models.md#shareable-page
@immutable
class InvoicePage implements StructurallyShareable<InvoicePage> {
  const InvoicePage({required this.items, required this.total});

  final List<Invoice> items;
  final int total;

  @override
  InvoicePage shareWith(InvoicePage previous) => InvoicePage(
        items: replaceEqualDeep(previous.items, items),
        total: total,
      );

  @override
  bool operator ==(Object other) =>
      other is InvoicePage &&
      other.total == total &&
      listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(total, Object.hashAll(items));
}
// <<<
