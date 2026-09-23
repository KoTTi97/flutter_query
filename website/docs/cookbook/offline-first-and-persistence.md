---
title: Offline first, and surviving a restart
sidebar_label: Offline first and persistence
description: Save chosen queries and unsent writes to disk, restore them before the first frame, and let paused writes go out when the network comes back.
sidebar_position: 12
---

# Offline first, and surviving a restart

**The problem.** A notes app is used on a train. The user opens it without a
connection and expects yesterday's notes, not a spinner. They add a note, and
it must reach the server eventually, even if the app is killed first. When
the app restarts on a good connection, the old list shows at once and then
refreshes.

**What query_kit gives you, and what it does not.** The cache is in memory.
There is no built-in persister and no `dehydrate`/`hydrate`. What the library
provides are the points to connect one to:

- `setQueryData(key, data, updatedAt: …)` puts saved data back **with the
  date it was fetched**, so staleness works as it did before the restart.
- `queryCache.subscribe` reports every successful fetch, which tells you when
  to save.
- `mutationCache.build(client, options, state: …)` restores an unsent write
  as a paused mutation, and `resumePausedMutations()` sends it.

This recipe connects them to a key-value store in about a hundred lines.

## The client

```dart title="lib/app/query_client.dart" snippet="cookbook/offline-first-and-persistence.md#client"
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
```

Query and mutation defaults are separate. A `networkMode` set for queries
does not apply to mutations, so this client sets both.
[Network mode](../guides/network-mode.md) covers all three modes.

## The store

Anything that stores a string under a name can back this: shared_preferences,
a file, a database.

```dart title="lib/data/snapshot_store.dart" snippet="cookbook/offline-first-and-persistence.md#store"
/// Where a snapshot lives: shared_preferences, a file, a database.
abstract interface class SnapshotStore {
  Future<String?> read(String name);
  Future<void> write(String name, String value);
}
```

With shared_preferences (2.3 or later), the adapter is a few lines:

```dart title="lib/data/prefs_store.dart" snippet="prose-only: needs shared_preferences, which the snippet package may not depend on"
class PrefsStore implements SnapshotStore {
  PrefsStore(this._prefs);

  final SharedPreferencesAsync _prefs;

  @override
  Future<String?> read(String name) => _prefs.getString('query_kit.$name');

  @override
  Future<void> write(String name, String value) =>
      _prefs.setString('query_kit.$name', value);
}
```

## Saving and restoring queries

A `PersistedQuery` names one key and knows how to turn its data into JSON
and back. The cache only ever sees your typed models.

```dart title="lib/data/persisted_query.dart" snippet="cookbook/offline-first-and-persistence.md#persisted-query"
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
```

The persister restores a snapshot before the app starts, then records every
new success of a listed key. It writes at most once a second.

```dart title="lib/data/query_persister.dart" snippet="cookbook/offline-first-and-persistence.md#persister"
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
```

## Saving and restoring writes

The mutation has a key so that its pending entries can be found. The new
note's id is created on the device. A write the server received just before
the app died will be sent again, and the server needs to recognise it as the
same note, not a second one.

```dart title="lib/data/note_mutations.dart" snippet="cookbook/offline-first-and-persistence.md#add-note"
final QueryKey addNoteKey = QueryKey(<Object?>['addNote']);

MutationOptions<Note, NewNote, void> addNoteMutation(QueryClient client) =>
    MutationOptions.simple(
      mutationKey: addNoteKey,
      mutationFn: notesApi.add,
      onSuccess: (_, __, ___) =>
          client.invalidateQueries(filters: QueryFilters(queryKey: notesKey)),
    );
```

Functions cannot be saved, so only the variables are. On restore, each
variable becomes a pending mutation again, rebuilt with the same options
created in code.

```dart title="lib/data/paused_writes.dart" snippet="cookbook/offline-first-and-persistence.md#paused-writes"
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
```

## Wiring it up in `main`

```dart title="lib/main.dart" snippet="cookbook/offline-first-and-persistence.md#main"
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
```

## Steps

1. Choose which keys survive a restart. Usually these are the lists a user
   opens first, not every detail entry.
2. Restore **before** `runApp`. A screen that mounts first starts its own
   fetch, and the restored data arrives too late to help.
3. Keep `gcTime` at least as long as a snapshot's `maxAge`. A restored entry
   has no observer until its screen opens, and after `gcTime` without one it
   is garbage collected.
4. For writes, give each one an id created on the device and make the server
   treat a repeated id as the same write.

## Traps

- **Restoring with `updatedAt: now`.** The data then counts as just fetched.
  Every screen trusts it for its whole `staleTime` and does not refetch
  yesterday's list. Always pass the saved date.
- **Persisting everything.** A snapshot of every entry includes other users'
  data after an account switch, and errors are not worth restoring. Save
  successes of listed keys only, and delete the snapshot at sign-out (see
  [Sign out and multiple accounts](sign-out-and-multi-account.md)).
- **Calling `mount()` and expecting it to resume.** A mounted client resumes
  paused mutations on reconnect and on focus, not when it is mounted. The
  `restore` above calls `resumePausedMutations()` itself. When the device is
  online at that moment, the writes go out immediately. Otherwise each one
  waits, because the call only runs mutations that may run now.
- **`offlineFirst` for writes.** It makes one attempt even when the device is
  offline, and only a *retry* waits for the network. Mutations do not retry
  by default, so a POST that fails that way ends in an error instead of
  waiting. Writes that should wait for the network belong in `online`.

## Variations

- **Restoring through the cache instead of `setQueryData`.**
  `client.queryCache.build(client, client.defaultQueryOptions(options),
  state: QueryState(...))` restores a whole `QueryState`, including its error
  count. The cache ignores `state` when the key already exists.
- **Several mutation kinds.** Give each kind its own key and its own saved
  list. On restore, rebuild each kind with its own options.
- **Nothing to persist, only offline.** When the app only has to survive going
  offline, the client's defaults are enough.
  [Connectivity](../guides/connectivity.md) connects a connectivity stream so
  that the client knows when it is offline.

## See it run

In the offline demo, switch *Online* off and press *Add todo*. The write
pauses and waits, and the list keeps its data. Switch it back on and the write
goes out, followed by the refetch its success triggers.

<LiveDemo feature="offline" height={760} />

:::note[In React Query]
TanStack Query ships `persistQueryClient`, storage persisters and
`dehydrate`/`hydrate`. query_kit has none of these. It has the parts shown
here: `setQueryData` with `updatedAt`, `QueryCache.build` with a state,
`MutationCache.build` with a state and `resumePausedMutations`, so that the
snapshot format belongs to your app. See [differences from TanStack
Query](../reference/differences-from-tanstack.md).
:::
