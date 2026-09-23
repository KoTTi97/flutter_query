---
title: Testing a screen
description: Widget tests for screens that read queries — a fake API with latency, a harness with the teardown built in, and tests for loading, errors, seeded data, staleness and a refused save.
sidebar_position: 10
---

# Testing a screen

The screens in the other recipes read queries and mutations against a
`ProductApi`. A widget test for one of them should run the real screen, the
real options and a real `QueryClient` — only the network replaced — and it
should be able to say *when* things happen: that a spinner shows first, that a
tapped row opens without a request, that data older than thirty seconds is
fetched again. The library's timers and the fake's latency run on the test's
fake clock, so none of this needs a real wait. What needs care is the
beginning and the end of each test: a client with no retries, and a teardown
that leaves no timer behind.

## The finished code

A fake of the API, with latency and a record of every call:

```dart snippet="cookbook/testing-a-screen.md#fake-api" title="test/fake_product_api.dart"
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
```

A harness: a fresh fake and client per test, the app's wiring, and the
teardown.

```dart snippet="cookbook/testing-a-screen.md#harness" title="test/harness.dart"
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
```

## The tests

A first load: the spinner, then the rows, after one request.

```dart snippet="cookbook/testing-a-screen.md#loading-then-rows" title="test/product_list_screen_test.dart"
screenTest('shows a spinner, then the products', const ProductListScreen(),
    (tester, api) async {
  expect(find.byType(CircularProgressIndicator), findsOneWidget);

  await tester.pump(api.latency); // the fake's latency is a timer
  expect(find.text('Kettle'), findsOneWidget);
  expect(find.text('Toaster'), findsOneWidget);
  expect(api.calls, <String>['list ']);
});
```

A failure and an empty answer, each with its own message:

```dart snippet="cookbook/testing-a-screen.md#error-and-empty" title="test/product_list_screen_test.dart"
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
```

The detail screen opens from the list's data, with no request of its own —
the [seeding recipe](list-detail-seeding.md), proved:

```dart snippet="cookbook/testing-a-screen.md#seeded-detail" title="test/product_detail_test.dart"
screenTest('a tapped row opens with no request of its own',
    const ProductListScreen(), (tester, api) async {
  await tester.pump(api.latency);

  await tester.tap(find.text('Kettle'));
  await tester.pumpAndSettle(); // the route transition is frames
  expect(find.text('€39.00'), findsOneWidget);
  expect(api.calls, <String>['list ']); // no 'get p1'
});
```

Staleness, with fake time: after thirty-one seconds the seeded detail is
stale, so opening it again shows it *and* fetches it.

```dart snippet="cookbook/testing-a-screen.md#stale-time" title="test/product_detail_test.dart"
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
```

A save the server refuses, with its field error under the field — the
[form recipe](forms-and-server-validation.md):

```dart snippet="cookbook/testing-a-screen.md#mutation-failure" title="test/product_form_screen_test.dart"
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
```

## How it works

1. **The fake replaces the network, nothing else.** `FakeProductApi`
   implements the same `ProductApi` the dio client does, so the screen, its
   options and the client are the ones the app runs. `calls` records every
   request, which is how a test says "no request was made".
2. **Latency is a timer.** The fake waits `latency` before it answers, with a
   plain `Future.delayed`. In a widget test that runs on the fake clock:
   `tester.pump(api.latency)` moves time forward exactly that far, and the
   answer arrives. `pumpAndSettle` does not do it — it pumps only while a frame
   is scheduled, and a pending timer is not a frame.
3. **A failure is set before it happens.** `failNext` makes the next call throw
   the given error. Because the fake reads it only when it answers, a test can
   also set it after the call has started.
4. **No retries in tests.** The harness's client says
   `RetryPolicy.never`. With the default three retries, a failing request
   would take seconds of fake time and three more calls before the error
   shows.
5. **Time moves the cache too.** `staleTime` and `gcTime` are measured with the
   library's clock, which the test binding fakes as well. `tester.pump(const
   Duration(seconds: 31))` is thirty-one seconds for the detail's
   `dataUpdatedAt` — the stale-time test takes no real time.
6. **The teardown is the harness's `finally`.** A `QueryClient` outlives the
   widget tree and owns `gcTime` timers, and the test binding fails a test that
   ends with a timer pending — before any `tearDown` runs. So the tree comes
   down (`pumpWidget(const SizedBox())`), the frames settle, the client is
   cleared, and one more pump and clear catch what a dropped mutation's
   callbacks wrote.

## Traps

- **One client per test.** A client shared across tests carries one test's
  cache into the next. The harness creates both the fake and the client inside
  `testWidgets`.
- **`pumpAndSettle` does not wait for the fake.** It returns as soon as no
  frame is scheduled, with the request still on its timer. Step time with
  `tester.pump(duration)`, then settle the frames it caused.
- **Assert on the calls, not only the screen.** "The detail shows the price" is
  true with or without a request. `api.calls` is what proves the seeding.
- **A route transition shows both screens.** Right after a tap, the old and
  the new route are both on the tree. `pumpAndSettle` after the tap lets the
  transition finish before a finder looks for a single match.
- **Values in the fake are read when it answers.** `api.products = []` after
  `pumpWidget` still takes effect for the first request, because the fake
  builds its answer after the latency. Set it before if a test needs it to
  count from the very first call.

## Variations

- **The same cases against the real backend.** A list of cases run against
  the fake *and* against a local copy of the server keeps the two from
  drifting apart. The
  [task manager](https://github.com/KoTTi97/flutter_query/tree/main/examples/task_manager)
  and the [showcase](https://github.com/KoTTi97/flutter_query/tree/main/examples/showcase)
  both have one, `backend_contract_test.dart`.
- **Testing a query without widgets.** A query's options are plain values: in
  a unit test, `await client.query(productListQuery(fake))` runs the query
  function against the fake and returns what the screen would receive.
- **Another call style.** The harness does not care which one the screen
  uses; the tests on this page drive a `context.query` screen, a `QueryBuilder`
  one and a `QueryMixin` form through the same harness.

:::note[In React Query]
The same advice as React Query's testing guide: a new `QueryClient` per test,
`retry: false`, and a mocked network layer. Flutter's fake clock replaces
`waitFor`: time is stepped rather than awaited.
:::

## See also

- [Testing](../guides/testing.md) — the teardown snippet on its own, and why
  each line of it is there.
- [Caching](../guides/caching.md) — `staleTime` and `gcTime`, which the
  stale-time test steps through.
- [Mutations](../guides/mutations.md) — the result a refused save leaves
  behind.
