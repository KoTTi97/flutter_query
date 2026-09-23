/// The cookbook's "testing a screen" recipe, run: the fake, the harness and
/// the cases on `cookbook/testing-a-screen.md` are the regions below, and
/// they drive the screens the other recipes build
/// (`lib/c6a_cookbook.dart`).
library;

import 'package:doc_snippets/c6a_cookbook.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

// >>> cookbook/testing-a-screen.md#fake-api
/// Answers from memory, after [latency], and records every call.
class FakeProductApi implements ProductApi {
  FakeProductApi({List<Product>? products})
      : products = products ??
            <Product>[
              const Product(id: 'p1', name: 'Kettle', price: 3900),
              const Product(id: 'p2', name: 'Toaster', price: 4900),
            ];

  List<Product> products;
  Duration latency = const Duration(milliseconds: 100);

  /// Thrown by the next call instead of answering, then forgotten.
  Object? failNext;

  final List<String> calls = <String>[];

  Future<T> _answer<T>(String call, T Function() body) async {
    calls.add(call);
    await Future<void>.delayed(latency);
    if (failNext case final failure?) {
      failNext = null;
      throw failure;
    }
    return body();
  }

  @override
  Future<List<Product>> list({String search = '', QueryCancelToken? signal}) =>
      _answer('list $search', () => List<Product>.of(products));

  @override
  Future<Product> get(String id, {QueryCancelToken? signal}) =>
      _answer('get $id', () => products.firstWhere((p) => p.id == id));

  @override
  Future<ProductPage> page(int offset, {QueryCancelToken? signal}) =>
      _answer('page $offset', () {
        final items = products.skip(offset).take(20).toList();
        final next = offset + items.length;
        return ProductPage(
          items: items,
          nextOffset: next < products.length ? next : null,
        );
      });

  @override
  Future<Product> save(ProductDraft draft) => _answer('save', () {
        final saved = Product(
          id: draft.id ?? 'p${products.length + 1}',
          name: draft.name,
          price: draft.price,
        );
        products = <Product>[
          for (final p in products)
            if (p.id != saved.id) p,
          saved,
        ];
        return saved;
      });
}
// <<<

// >>> cookbook/testing-a-screen.md#harness
/// `testWidgets` with a fresh fake, a client without retries, the app's
/// wiring around [home] — and the teardown a `QueryClient` needs.
void screenTest(
  String description,
  Widget home,
  Future<void> Function(WidgetTester tester, FakeProductApi api) body,
) {
  testWidgets(description, (tester) async {
    final api = FakeProductApi();
    final client = QueryClient(
      defaultOptions: const DefaultOptions(
        queries: QueryDefaults(retry: RetryPolicy.never),
      ),
    );
    try {
      await tester.pumpWidget(ProductApiScope(
        api: api,
        child: QueryClientProvider(
          client: client,
          child: MaterialApp(home: home),
        ),
      ));
      await body(tester, api);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      client.clear();
      await tester.pump();
      client.clear();
    }
  });
}
// <<<

void main() {
  // >>> cookbook/testing-a-screen.md#loading-then-rows
  screenTest('shows a spinner, then the products', const ProductListScreen(),
      (tester, api) async {
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(api.latency); // the fake's latency is a timer
    expect(find.text('Kettle'), findsOneWidget);
    expect(find.text('Toaster'), findsOneWidget);
    expect(api.calls, <String>['list ']);
  });
  // <<<

  // >>> cookbook/testing-a-screen.md#error-and-empty
  screenTest('a first load that fails says so', const ProductListScreen(),
      (tester, api) async {
    api.failNext = const ApiException('The server is down');
    await tester.pump(api.latency);
    expect(
      find.text('Could not load products: The server is down'),
      findsOneWidget,
    );
  });

  screenTest('an empty catalogue says so', const ProductListScreen(),
      (tester, api) async {
    api.products = <Product>[]; // read when the fake answers
    await tester.pump(api.latency);
    expect(find.text('No products yet'), findsOneWidget);
  });
  // <<<

  // >>> cookbook/testing-a-screen.md#seeded-detail
  screenTest('a tapped row opens with no request of its own',
      const ProductListScreen(), (tester, api) async {
    await tester.pump(api.latency);

    await tester.tap(find.text('Kettle'));
    await tester.pumpAndSettle(); // the route transition is frames
    expect(find.text('€39.00'), findsOneWidget);
    expect(api.calls, <String>['list ']); // no 'get p1'
  });
  // <<<

  // >>> cookbook/testing-a-screen.md#stale-time
  screenTest('data older than its staleTime is refetched behind the rows',
      const ProductListScreen(), (tester, api) async {
    await tester.pump(api.latency);
    await tester.tap(find.text('Kettle'));
    await tester.pumpAndSettle();

    // Thirty seconds of fake time: the detail is stale now.
    await tester.pump(const Duration(seconds: 31));
    api.products = <Product>[
      const Product(id: 'p1', name: 'Kettle', price: 3500),
      ...api.products.skip(1),
    ];
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kettle'));
    await tester.pump(); // a stale entry mounts: it shows, and refetches
    expect(api.calls.last, 'get p1');
    await tester.pumpAndSettle();
    expect(find.text('€35.00'), findsOneWidget);
  });
  // <<<

  // >>> cookbook/testing-a-screen.md#mutation-failure
  screenTest('a refused save shows the server\'s field errors',
      const ProductFormScreen(), (tester, api) async {
    await tester.enterText(find.byType(TextFormField).at(0), 'Kettle');
    await tester.enterText(find.byType(TextFormField).at(1), '39');
    api.failNext = const ValidationException(<String, String>{
      'name': 'A product with this name exists',
    });

    await tester.tap(find.text('Save'));
    await tester.pump(); // pending: the button spins
    expect(find.text('Save'), findsNothing);

    await tester.pump(api.latency);
    expect(find.text('A product with this name exists'), findsOneWidget);
    expect(api.calls, <String>['save']);
  });
  // <<<

  screenTest('a save that succeeds leaves the form', const _FormOpener(),
      (tester, api) async {
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Grinder');
    await tester.enterText(find.byType(TextFormField).at(1), '59.5');
    await tester.tap(find.text('Save'));
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    expect(find.text('saved Grinder at 5950'), findsOneWidget);
  });

  screenTest(
      'the feed appends a page from its footer', const ProductFeedScreen(),
      (tester, api) async {
    api.products = <Product>[
      for (var i = 0; i < 25; i++)
        Product(id: 'p$i', name: 'Product $i', price: 100 * i),
    ];
    await tester.pump(api.latency);
    expect(find.text('Product 0'), findsOneWidget);

    // Near the end, the scroll listener asks for the next page.
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text("That's everything"), 200);
    expect(find.text('Product 24'), findsOneWidget);
    expect(api.calls, <String>['page 0', 'page 20']);
  });

  screenTest('search waits for the typing to stop', const ProductSearchScreen(),
      (tester, api) async {
    expect(find.text('Type to search'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'k');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'ke');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(api.latency);
    expect(api.calls, <String>['list ke']);
  });

  test('the retry policy repeats transient failures only', () {
    bool retries(int count, Object error) =>
        retryTransientFailures.shouldRetry(count, error, StackTrace.empty);
    expect(retries(0, const ApiException('down', status: 503)), isTrue);
    expect(retries(0, const ApiException('timeout')), isTrue);
    expect(retries(2, StateError('anything')), isTrue);
    expect(retries(3, const ApiException('down', status: 503)), isFalse);
    expect(retries(0, const ApiException('gone', status: 404)), isFalse);
    expect(retries(0, const ApiException('no', status: 401)), isFalse);
  });

  screenTest(
      'a failed pull keeps the list, with a banner', const ProductListScreen(),
      (tester, api) async {
    await tester.pump(api.latency);
    api.failNext = const ApiException('The server is down');

    await tester.fling(find.text('Kettle'), const Offset(0, 400), 1000);
    await tester.pump(); // the indicator starts …
    await tester.pump(const Duration(seconds: 1)); // … and calls onRefresh
    expect(api.calls, <String>['list ', 'list ']);
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    expect(find.text('Kettle'), findsOneWidget);
    expect(
      find.text('Could not refresh: The server is down'),
      findsOneWidget,
    );
    expect(find.byType(RefreshProgressIndicator), findsNothing);
  });

  screenTest('a detail nobody seeded pulls from a cached list',
      const ProductListScreen(), (tester, api) async {
    await tester.pump(api.latency);
    final client =
        QueryClientProvider.of(tester.element(find.byType(ProductListScreen)));
    // As if the pushed entry had been garbage-collected.
    client.removeQueries(
      filters: QueryFilters(queryKey: ProductKeys.detail('p1'), exact: true),
    );

    await tester.tap(find.text('Kettle'));
    await tester.pumpAndSettle();
    expect(find.text('€39.00'), findsOneWidget);
    expect(api.calls, <String>['list ']); // fresh as its list: no 'get p1'
    expect(
      client.getQueryState<Product>(ProductKeys.detail('p1'))?.dataUpdatedAt,
      client.getQueryState<List<Product>>(ProductKeys.list())?.dataUpdatedAt,
    );
  });

  screenTest('a newer needle cancels the older one and keeps its rows',
      const ProductSearchScreen(), (tester, api) async {
    final client = QueryClientProvider.of(
      tester.element(find.byType(ProductSearchScreen)),
    );
    // Slower than the debounce, so a request can be overtaken.
    api.latency = const Duration(seconds: 1);
    await tester.enterText(find.byType(TextField), 'ke');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(api.latency);
    expect(find.text('Kettle'), findsOneWidget);

    // 'ket' goes out; 'kett' replaces it before it answers.
    await tester.enterText(find.byType(TextField), 'ket');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(); // the rebuild re-keys the read
    await tester.enterText(find.byType(TextField), 'kett');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    final ket = client.getQueryState<List<Product>>(
      ProductKeys.list(search: 'ket'),
    );
    expect(ket?.fetchStatus, FetchStatus.idle); // cancelled, put back
    expect(ket?.hasData, isFalse);
    // 'ke''s rows stay, dimmed, while 'kett' loads.
    expect(find.text('Kettle'), findsOneWidget);
    expect(
      tester.widget<Opacity>(find.byType(Opacity)).opacity,
      0.5,
    );

    await tester.pump(api.latency);
    expect(api.calls, <String>['list ke', 'list ket', 'list kett']);
    expect(
      client.getQueryData<List<Product>>(ProductKeys.list(search: 'ket')),
      isNull, // the late answer was dropped
    );
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
  });

  group('the global error snackbar', () {
    Future<(QueryClient, FakeProductApi)> pumpApp(
      WidgetTester tester,
      Widget home,
    ) async {
      final api = FakeProductApi();
      final client = createQueryClient()
        ..setDefaultOptions(
          const DefaultOptions(
            queries: QueryDefaults(retry: RetryPolicy.never),
          ),
        );
      await tester.pumpWidget(ProductApiScope(
        api: api,
        child: QueryClientProvider(
          client: client,
          child: MaterialApp(
            scaffoldMessengerKey: scaffoldMessengerKey,
            home: home,
          ),
        ),
      ));
      return (client, api);
    }

    Future<void> tearDownApp(WidgetTester tester, QueryClient client) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      client.clear();
      await tester.pump();
      client.clear();
    }

    testWidgets('toasts a failed refresh, not a failed first load',
        (tester) async {
      final (client, api) = await pumpApp(tester, const ProductListScreen());
      api.failNext = const ApiException('The server is down');
      await tester.pump(api.latency);
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);

      client.refetchQueries().ignore();
      await tester.pump(api.latency);
      await tester.pump();
      expect(find.text('Kettle'), findsOneWidget);
      api.failNext = const ApiException('The server is down');
      client.refetchQueries().ignore();
      await tester.pump(api.latency);
      await tester.pump();
      // The toast — and, the trap on the pull-to-refresh page, the list's
      // own banner saying the same.
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Could not refresh: The server is down'),
        ),
        findsOneWidget,
      );
      await tearDownApp(tester, client);
    });

    testWidgets('stays quiet for a query marked silent', (tester) async {
      final (client, api) = await pumpApp(tester, const SizedBox());
      final observer = client.observe(quietProductListQuery(api));
      final unsubscribe = observer.subscribe((_) {});
      await tester.pump(api.latency);
      api.failNext = const ApiException('The server is down');
      observer.refetch().ignore();
      await tester.pump(api.latency);
      await tester.pump();
      expect(observer.currentResult, isA<QueryError<List<Product>>>());
      expect(find.byType(SnackBar), findsNothing);
      unsubscribe();
      await tearDownApp(tester, client);
    });
  });
}

/// Opens the form and shows what it popped with.
class _FormOpener extends StatefulWidget {
  const _FormOpener();

  @override
  State<_FormOpener> createState() => _FormOpenerState();
}

class _FormOpenerState extends State<_FormOpener> {
  Product? _saved;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: <Widget>[
            TextButton(
              onPressed: () async {
                final saved = await Navigator.of(context).push<Product>(
                  MaterialPageRoute<Product>(
                    builder: (_) => const ProductFormScreen(),
                  ),
                );
                setState(() => _saved = saved);
              },
              child: const Text('New'),
            ),
            if (_saved case final saved?)
              Text('saved ${saved.name} at ${saved.price}'),
          ],
        ),
      );
}
