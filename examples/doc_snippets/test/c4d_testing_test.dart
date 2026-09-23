/// The testing guide's samples beyond the teardown
/// (`website/docs/guides/testing.md`): a fake repository, the loading,
/// error and empty states, a mutation's two outcomes, stale time and polling
/// stepped with `pump(duration)`, and a controller tested without widgets.
/// The screens under test are in `lib/c4d_reference.dart`.
library;

import 'dart:async';

import 'package:doc_snippets/c4d_reference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'teardown_snippet_test.dart' show queryWidgetTest;

// >>> guides/testing.md#fake-repository
/// Answers from memory, after [latency], or fails with [failWith].
class FakeProductRepository implements ProductRepository {
  FakeProductRepository({
    List<Product> catalogue = const [],
    this.latency = const Duration(milliseconds: 300),
    this.failWith,
  }) : catalogue = [...catalogue];

  final List<Product> catalogue;
  final Duration latency;
  Object? failWith;

  /// How many calls reached the "server".
  int requests = 0;

  Future<T> _answer<T>(T Function() body) async {
    requests++;
    await Future<void>.delayed(latency);
    if (failWith case final error?) throw error;
    return body();
  }

  @override
  Future<List<Product>> products({QueryCancelToken? signal}) =>
      _answer(() => List.unmodifiable(catalogue));

  @override
  Future<Product> product(String id, {QueryCancelToken? signal}) =>
      _answer(() => catalogue.firstWhere((p) => p.id == id));

  @override
  Future<Product> addProduct(String name) => _answer(() {
        final product =
            Product(id: 'p${catalogue.length + 1}', name: name, price: 0);
        catalogue.add(product);
        return product;
      });
}
// <<<

const lamp = Product(id: 'p1', name: 'Desk lamp', price: 4900);

// >>> guides/testing.md#test-client
QueryClient productTestClient() => QueryClient(
      defaultOptions: const DefaultOptions(
        queries: QueryDefaults(retry: RetryPolicy.never),
      ),
    );

Widget productApp(QueryClient client, Widget screen) => QueryClientProvider(
      client: client,
      child: MaterialApp(home: Scaffold(body: screen)),
    );
// <<<

void main() {
  // -------------------------------------------------------------------------
  // Loading, error and empty
  // -------------------------------------------------------------------------

  // >>> guides/testing.md#states
  queryWidgetTest('shows a spinner, then the products', (tester, client) async {
    final repo = FakeProductRepository(catalogue: [lamp]);
    await tester.pumpWidget(productApp(client, ProductListScreen(repo: repo)));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(repo.latency);
    expect(find.text('Desk lamp'), findsOneWidget);
  }, createClient: productTestClient);

  queryWidgetTest('shows the error', (tester, client) async {
    final repo = FakeProductRepository(failWith: Exception('offline'));
    await tester.pumpWidget(productApp(client, ProductListScreen(repo: repo)));

    await tester.pump(repo.latency);
    expect(find.text('Could not load products'), findsOneWidget);
    expect(repo.requests, 1); // no retries in this client
  }, createClient: productTestClient);

  queryWidgetTest('shows the empty state', (tester, client) async {
    final repo = FakeProductRepository();
    await tester.pumpWidget(productApp(client, ProductListScreen(repo: repo)));

    await tester.pump(repo.latency);
    expect(find.text('No products yet'), findsOneWidget);
  }, createClient: productTestClient);
  // <<<

  // -------------------------------------------------------------------------
  // A mutation's success and failure
  // -------------------------------------------------------------------------

  // >>> guides/testing.md#mutation
  queryWidgetTest('saves a product', (tester, client) async {
    final repo = FakeProductRepository();
    await tester.pumpWidget(productApp(client, AddProductButton(repo: repo)));

    await tester.tap(find.text('Add a desk lamp'));
    await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);

    await tester.pump(repo.latency);
    expect(find.text('Saved'), findsOneWidget);
    expect(repo.catalogue.single.name, 'Desk lamp');
  });

  queryWidgetTest('says so when saving fails', (tester, client) async {
    final repo = FakeProductRepository(failWith: Exception('409'));
    await tester.pumpWidget(productApp(client, AddProductButton(repo: repo)));

    await tester.tap(find.text('Add a desk lamp'));
    await tester.pump(repo.latency);
    expect(find.text('Could not save'), findsOneWidget);
    expect(repo.catalogue, isEmpty);
  });
  // <<<

  // -------------------------------------------------------------------------
  // Time: stale time and polling
  // -------------------------------------------------------------------------

  // >>> guides/testing.md#stale-time
  queryWidgetTest('a fresh list is not fetched again', (tester, client) async {
    final repo = FakeProductRepository(catalogue: [lamp]);
    final screen = productApp(client, ProductListScreen(repo: repo));
    await tester.pumpWidget(screen);
    await tester.pump(repo.latency);
    expect(repo.requests, 1);

    // Leave and come back within the stale time: served from the cache.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpWidget(screen);
    expect(find.text('Desk lamp'), findsOneWidget);
    expect(repo.requests, 1);

    // Come back after it: shown from the cache, and fetched again.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpWidget(screen);
    expect(find.text('Desk lamp'), findsOneWidget);
    await tester.pump(repo.latency);
    expect(repo.requests, 2);
  },
      createClient: () => QueryClient(
            defaultOptions: const DefaultOptions(
              queries: QueryDefaults(
                retry: RetryPolicy.never,
                staleTime: StaleTime.duration(Duration(minutes: 1)),
              ),
            ),
          ));
  // <<<

  // >>> guides/testing.md#polling
  queryWidgetTest('polls every ten seconds', (tester, client) async {
    final repo = FakeProductRepository(catalogue: [lamp]);
    await tester.pumpWidget(productApp(client, ProductListScreen(repo: repo)));
    await tester.pump(repo.latency);
    expect(repo.requests, 1);

    // Each poll: the interval, then the fake's latency.
    for (final expected in [2, 3]) {
      await tester.pump(const Duration(seconds: 10));
      expect(repo.requests, expected);
      await tester.pump(repo.latency);
    }
  },
      createClient: () => QueryClient(
            defaultOptions: const DefaultOptions(
              queries: QueryDefaults(
                retry: RetryPolicy.never,
                refetchInterval: RefetchInterval.every(Duration(seconds: 10)),
              ),
            ),
          ));
  // <<<

  // -------------------------------------------------------------------------
  // A controller without widgets
  // -------------------------------------------------------------------------

  // >>> guides/testing.md#controller
  test('a controller loads without a widget', () async {
    final client = productTestClient();
    final repo = FakeProductRepository(
      catalogue: [lamp],
      latency: Duration.zero,
    );
    final controller = QueryController(client, productsQuery(repo));

    // A controller fetches while something listens.
    final loaded = Completer<List<Product>>();
    void onChange() {
      if (controller.value case QuerySuccess(:final data)) {
        if (!loaded.isCompleted) loaded.complete(data);
      }
    }

    controller.addListener(onChange);
    expect(controller.value, isA<QueryPending<List<Product>>>());
    expect(await loaded.future, [lamp]);

    controller
      ..removeListener(onChange)
      ..dispose();
    client.clear();
  });
  // <<<
}
