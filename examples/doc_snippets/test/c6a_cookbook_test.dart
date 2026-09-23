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
