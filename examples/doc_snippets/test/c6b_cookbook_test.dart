/// The cookbook recipes' claims, run: what `lib/c6b_cookbook.dart` shows on
/// the architecture and integration pages does what the pages say it does.
///
/// Regions here are samples a page shows as a test a reader can copy.
library;

import 'dart:convert';

import 'package:doc_snippets/c6b_cookbook.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

/// The teardown from the testing guide, for the tests below.
Future<void> tearDownClient(WidgetTester tester, QueryClient client) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  client.clear();
  await tester.pump();
  client.clear();
}

void main() {
  // >>> cookbook/dependency-injection.md#test
  testWidgets('the project screen shows the project', (tester) async {
    // A client per test: nothing cached leaks from one test into the next.
    final client = QueryClient(
      defaultOptions: const DefaultOptions(
        queries: QueryDefaults(retry: RetryPolicy.never),
      ),
    );
    await tester.pumpWidget(QueryClientProvider(
      client: client,
      child: const MaterialApp(home: ProjectScreen(id: 'p1')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('3 open tasks'), findsOneWidget);

    // The testing guide's teardown.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    client.clear();
    await tester.pump();
    client.clear();
  });
  // <<<

  testWidgets('a restored snapshot keeps its date, and new data is saved',
      (tester) async {
    final store = MemoryStore();
    final savedAt = DateTime.now().subtract(const Duration(minutes: 10));
    await store.write(
      'queries',
      jsonEncode(<String, Object?>{
        'notes': <String, Object?>{
          'savedAt': savedAt.millisecondsSinceEpoch,
          'data': <Object?>[
            const Note(id: 'n1', text: 'Milk').toJson(),
          ],
        },
      }),
    );
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
    await persister.restore();
    persister.start();

    expect(client.getQueryData<List<Note>>(notesKey),
        const <Note>[Note(id: 'n1', text: 'Milk')]);
    expect(
      client
          .getQueryState<List<Note>>(notesKey)!
          .dataUpdatedAt!
          .millisecondsSinceEpoch,
      savedAt.millisecondsSinceEpoch,
    );

    client.setQueryData<List<Note>>(
        notesKey, const <Note>[Note(id: 'n2', text: 'Eggs')]);
    await tester.pump(const Duration(seconds: 1));
    final saved = jsonDecode((await store.read('queries'))!) as Map;
    expect(jsonEncode(saved['notes']), contains('Eggs'));

    persister.stop();
    client.clear();
  });

  testWidgets('a paused write is saved, restored, and sent on reconnect',
      (tester) async {
    final store = MemoryStore();
    final first = buildClient()..mount();
    first.onlineManager.setOnline(false);
    PausedWrites(first, store).start();
    final observer = MutationObserver(first, addNoteMutation(first));
    observer.mutate(const NewNote(clientId: 'c1', text: 'Milk'));
    await tester.pump();
    expect(jsonDecode((await store.read('addNote'))!), hasLength(1));
    observer.reset();
    first.unmount();

    // The next launch.
    final second = buildClient()..mount();
    second.onlineManager.setOnline(false);
    await PausedWrites(second, store).restore();
    PausedWrites(second, store).start();
    final restored = second.mutationCache.findAll(
      filters: MutationFilters(mutationKey: addNoteKey),
    );
    expect(restored.single.state.isPaused, isTrue);

    second.onlineManager.setOnline(true);
    await tester.pump();
    await tester.pump();
    expect(restored.single.state.status, MutationStatus.success);
    expect(restored.single.state.data, const Note(id: 'c1', text: 'Milk'));
    expect(jsonDecode((await store.read('addNote'))!), isEmpty);

    first.clear();
    second.unmount();
    second.clear();
    await tester.pump();
  });

  testWidgets('a disconnected device is not fetched again', (tester) async {
    final client = buildDeviceClient();
    final connection = DeviceConnection('kitchen');
    await tester.pumpWidget(QueryClientProvider(
      client: client,
      child: MaterialApp(
        home: Scaffold(body: DeviceScreen(connection: connection)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('21.5 °C'), findsOneWidget);

    final done = disconnect(client, connection);
    await tester.pump();
    await done;
    expect(client.getQueryState<DeviceStatus>(DeviceKeys.status('kitchen')),
        isNull);

    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Disconnected'), findsOneWidget);
    expect(client.getQueryState<DeviceStatus>(DeviceKeys.status('kitchen')),
        isNull);

    await tearDownClient(tester, client);
  });

  test('shareById keeps the contacts that did not change', () {
    const ada = Contact(id: 'c1', name: 'Ada');
    const bob = Contact(id: 'c2', name: 'Bob');
    final before = <String, Contact>{'c1': ada, 'c2': bob};
    final after = shareById(before, <String, Contact>{
      'c1': Contact(id: 'c1', name: 'Ada'.toString()),
      'c2': bob.copyWith(name: 'Bobby'),
    });
    expect(identical(after['c1'], ada), isTrue);
    expect(after['c2']!.name, 'Bobby');

    final unchanged = shareById(after, Map<String, Contact>.of(after));
    expect(identical(unchanged, after), isTrue);
  });

  test('a ContactBook shares its entries through the default walk', () {
    const ada = Contact(id: 'c1', name: 'Ada');
    final before = ContactBook(
      byId: const <String, Contact>{
        'c1': ada,
        'c2': Contact(id: 'c2', name: 'Bob')
      },
      order: const <String>['c1', 'c2'],
    );
    final next = ContactBook(
      byId: <String, Contact>{
        'c1': const Contact(id: 'c1', name: 'Ada').copyWith(),
        'c2': const Contact(id: 'c2', name: 'Bobby'),
      },
      order: <String>['c1', 'c2'],
    );
    final shared = replaceEqualDeep(before, next);
    expect(identical(shared.byId['c1'], ada), isTrue);
    expect(identical(shared.order, before.order), isTrue);
  });

  test('a wrapper is a leaf, a StructurallyShareable one is not', () {
    Invoice invoice(String id, int cents) =>
        Invoice(id: id, customer: 'ACME', cents: cents);

    // >>> cookbook/freezed-and-json-models.md#measure
    final before = InvoiceList([invoice('i1', 100), invoice('i2', 200)]);
    // A refetch in which only i2 changed:
    final after = replaceEqualDeep(
      before,
      InvoiceList([invoice('i1', 100), invoice('i2', 250)]),
    );
    // i1 is equal, but it is not the instance the cache held:
    expect(identical(after.items[0], before.items[0]), isFalse);
    // <<<

    final page =
        InvoicePage(items: [invoice('i1', 100), invoice('i2', 200)], total: 2);
    final nextPage = replaceEqualDeep(
      page,
      InvoicePage(items: [invoice('i1', 100), invoice('i2', 250)], total: 2),
    );
    expect(identical(nextPage.items[0], page.items[0]), isTrue);
    expect(nextPage.items[1].cents, 250);
  });

  test('the relay gives up after five failures or the timeout', () {
    final pending = Relay(
      id: 'r1',
      on: false,
      requestedOn: true,
      pendingSince: DateTime.now(),
    );
    expect(gaveUp(pending, 0), isFalse);
    expect(gaveUp(pending, 5), isTrue);
    final old = Relay(
      id: 'r1',
      on: false,
      requestedOn: true,
      pendingSince: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    expect(gaveUp(old, 0), isTrue);
  });
}
