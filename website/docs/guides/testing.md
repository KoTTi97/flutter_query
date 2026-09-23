---
title: Testing
description: The teardown every widget test needs, a harness that wraps it, a client without retries, and the pump rules that fake timers impose.
---

# Testing

## The teardown every widget test needs

A `QueryClient` outlives the widget tree by design — it owns the cache and its
`gcTime` timers. Flutter's test binding asserts that **no timer is pending**
when the tree comes down, and it checks that *before* any `tearDown` runs, so
the cleanup has to happen inside the test body. Get it wrong and the test
fails with a pending-timer error that says nothing about queries. The end of
a query widget test is therefore always the same steps:

```dart snippet="guides/testing.md#teardown"
testWidgets('the list loads', (tester) async {
  final client = QueryClient();
  await tester.pumpWidget(QueryClientProvider(
    client: client,
    child: const MaterialApp(home: TasksScreen()),
  ));
  await tester.pumpAndSettle();
  expect(find.byType(ListView), findsOneWidget);

  // Let the widgets go, and the frame after them run.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  // Then the cache and its timers.
  client.clear();
  // A mutation the clear dropped fails a moment later and its callbacks
  // run then; let them, then clear what they wrote.
  await tester.pump();
  client.clear();
});
```

Tear the tree down first and let the frame after it run: the binding's
`context.query` scope releases observers in a post-frame sweep, and clearing
the client before that runs would leave the sweep to re-create what it is
about to drop. Then `clear()` cancels the `gcTime` timers. The last two steps
matter when a test leaves a mutation paused offline: `clear()` fails it, its
`onError` runs a moment later, and an optimistic rollback's `setQueryData`
re-creates the query it names — gc timer included.

Nothing here is exported by the package. `flutter_test` is a dev dependency
of `query_kit_flutter`, not a regular one, so nothing a test needs sits in
your app's dependency graph. Copy the steps, or the harness below, into your
own test folder. The Flutter samples on this page are test cases in
[`examples/doc_snippets/test/`](https://github.com/KoTTi97/query_kit/tree/main/examples/doc_snippets/test)
— the teardown and the harness in `teardown_snippet_test.dart` — which CI
runs, so they cannot rot.

## A harness

Written once per test suite, so no case repeats the steps:

```dart snippet="guides/testing.md#harness"
/// `testWidgets` plus the teardown a `QueryClient` needs.
void queryWidgetTest(
  String description,
  Future<void> Function(WidgetTester tester, QueryClient client) body, {
  QueryClient Function()? createClient,
}) {
  testWidgets(description, (tester) async {
    final client = (createClient ?? QueryClient.new)();
    try {
      await body(tester, client);
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

The client is built for the case and taken down after it; pass `createClient`
to give it `defaultOptions`. A case then reads as the first sample without
its last five lines:

```dart snippet="guides/testing.md#using-the-harness"
queryWidgetTest('the list loads', (tester, client) async {
  await tester.pumpWidget(QueryClientProvider(
    client: client,
    child: const MaterialApp(home: TasksScreen()),
  ));
  await tester.pumpAndSettle();
  expect(find.byType(ListView), findsOneWidget);
});
```

Both example apps wrap this shape with a fixture of their own, in the same
teardown order: `showcaseTest` in
[`examples/showcase/test/harness.dart`](https://github.com/KoTTi97/query_kit/blob/main/examples/showcase/test/harness.dart),
which also brings a fresh fake backend and opens the app on one route, and
`demoTest` in
[`examples/task_manager/test/acceptance_test.dart`](https://github.com/KoTTi97/query_kit/blob/main/examples/task_manager/test/acceptance_test.dart).
The binding's own suite has the fuller version in
[`packages/query_kit_flutter/test/harness.dart`](https://github.com/KoTTi97/query_kit/blob/main/packages/query_kit_flutter/test/harness.dart)
— a second client adopted for the teardown, the provider wired with lifecycle
observation off, the app lifecycle put back to `resumed` when a case faked
it. None of them is importable; they are worth reading before you write your
own.

## A client for tests

The default retries — three, with backoff — make a failing query take seven
seconds to fail. A test's client turns them off:

```dart snippet="guides/testing.md#no-retries"
QueryClient testClient() => QueryClient(
      defaultOptions: const DefaultOptions(
        queries: QueryDefaults(retry: RetryPolicy.never),
      ),
    );
```

Pass it as the harness's `createClient: testClient`. Mutations already default
to no retries. Build a **new client per test**: a shared one carries cached
data from one case into the next.

The rest of this page tests a small shop screen. Its cases use a client like
that one, and a helper that puts a screen under a provider:

```dart snippet="guides/testing.md#test-client"
QueryClient productTestClient() => QueryClient(
      defaultOptions: const DefaultOptions(
        queries: QueryDefaults(retry: RetryPolicy.never),
      ),
    );

Widget productApp(QueryClient client, Widget screen) => QueryClientProvider(
      client: client,
      child: MaterialApp(home: Scaffold(body: screen)),
    );
```

Anything else the app sets on its own client — a `staleTime`, a
`refetchInterval` — goes into the test client too, when a test is about it.
The stale-time and polling cases below do that.

## Faking the backend

Fake the transport, not the library. The query functions under test call
your API client; hand them one that answers from memory. The cache then
behaves exactly as it does in the app: retries, staleness, structural sharing
and all. There are two usual places to cut.

**An injected repository.** When the screen takes its data source as a
parameter or from your dependency injection, the fake is a class with the
same interface:

```dart snippet="guides/testing.md#fake-repository"
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
```

`latency` is what makes a loading state observable, `failWith` switches a
case to the error path, and `requests` counts what reached the "server" —
the number a staleness or polling test asserts on.

**Your HTTP client's adapter.** When the app talks to `dio` directly, keep
the real repository and swap what is under it. `dio` takes an
`HttpClientAdapter`; one that answers from a map is a dozen lines:

```dart snippet="prose-only: needs package:dio, which this site's compiled samples do not depend on"
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.routes);

  /// `'GET /products'` → the JSON body to answer with.
  final Map<String, Object?> routes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final route = '${options.method} ${options.path}';
    if (!routes.containsKey(route)) {
      return ResponseBody.fromString('not found', 404);
    }
    return ResponseBody.fromString(
      jsonEncode(routes[route]),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final dio = Dio(BaseOptions(baseUrl: 'https://shop.test/api'))
  ..httpClientAdapter = FakeAdapter({
    'GET /products': [
      {'id': 'p1', 'name': 'Desk lamp', 'price': 4900},
    ],
  });
```

This is how the *Showcase* example's widget tests run: an in-memory
backend behind `dio`, in
[`examples/showcase/lib/demo/in_memory_backend.dart`](https://github.com/KoTTi97/query_kit/blob/main/examples/showcase/lib/demo/in_memory_backend.dart),
with a contract test that runs the same cases against it and the real
server, so the fake cannot drift from what it stands in for.

Either way, a mock of `QueryClient` itself is the wrong cut: it tests your
mock, not what the screen will do.

## Loading, error and empty states

The screen under test lists products, with a spinner, an error line and an
empty state:

```dart snippet="guides/testing.md#screen"
QueryObserverOptions<List<Product>> productsQuery(ProductRepository repo) =>
    QueryObserverOptions(
      queryKey: QueryKey(<Object?>['products']),
      queryFn: (context) => repo.products(signal: context.signal),
    );

class ProductListScreen extends StatelessWidget {
  const ProductListScreen({super.key, required this.repo});

  final ProductRepository repo;

  @override
  Widget build(BuildContext context) => QueryBuilder<List<Product>>(
        options: productsQuery(repo),
        builder: (context, result) => switch (result) {
          QueryPending() => const Center(child: CircularProgressIndicator()),
          QueryError() => const Center(child: Text('Could not load products')),
          QuerySuccess(:final data) when data.isEmpty =>
            const Center(child: Text('No products yet')),
          QuerySuccess(:final data) => ListView(
              children: [
                for (final product in data) ListTile(title: Text(product.name)),
              ],
            ),
        },
      );
}

class AddProductButton extends StatelessWidget {
  const AddProductButton({super.key, required this.repo});

  final ProductRepository repo;

  @override
  Widget build(BuildContext context) => MutationBuilder(
        options: MutationOptions.simple(
          mutationFn: repo.addProduct,
        ),
        builder: (context, mutation) => switch (mutation.value) {
          MutationPending() => const Text('Saving…'),
          MutationSuccess() => const Text('Saved'),
          MutationError() => const Text('Could not save'),
          MutationIdle() => TextButton(
              onPressed: () => mutation.mutate('Desk lamp'),
              child: const Text('Add a desk lamp'),
            ),
        },
      );
}
```

One case per state. Each steps the fake's latency with `pump` rather than
`pumpAndSettle` — the spinner animates forever, so the tree never settles
while it is on screen:

```dart snippet="guides/testing.md#states"
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
```

The error case asserts one request: with the default retries it would still
be waiting a second before the second attempt, and the error text would not
be there yet. `find.byType(CircularProgressIndicator)` straight after
`pumpWidget` works because a query with no data starts pending in the very
first frame; no pump is needed to see it.

## Mutations: success and failure

The button under test is the `AddProductButton` above. A mutation's result
moves from idle to pending to success or error, and each step is one pump:

```dart snippet="guides/testing.md#mutation"
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
```

`tester.pump()` after the tap builds the pending frame; `pump(repo.latency)`
lets the fake answer. `mutation.mutate` swallows the error for you — it lands
in the result, not in the test zone — so the failure case needs no
`expectLater` or `runZonedGuarded`. A test that calls `mutateAsync` itself
gets the error from the returned future instead, and has to catch it.

When a mutation updates the cache — an optimistic `setQueryData`, an
`invalidateQueries` in `onSettled` — assert on the screen that shows the
query, not on the cache: that is what the user sees, and it catches a wrong
key as well as a wrong value.

## The pump rules

Two things surprise people, and both come from `testWidgets` running under
`FakeAsync`.

**`pumpAndSettle` only pumps while a frame is scheduled.** A fake backend's
latency is a *timer*, not a frame, and so is a `refetchInterval`. Step them
explicitly:

```dart snippet="guides/testing.md#stepping-a-fake"
await tester.pump(const Duration(milliseconds: 300)); // the fake's latency
await tester.pumpAndSettle();
```

So `pumpAndSettle` never reaches the next poll or retry: it returns as soon
as no frame is scheduled, long before the timer is due — or, with a spinner
on screen while a query retries, it times out. Drive those with
`pump(duration)` only.

**`tester.pump()` with no duration does not let a `dio` response resolve.**
`dio` hangs its pipeline off zero-duration timers, and `FakeAsync` runs those
only when the clock moves. Step with a real duration.

## Time: stale time and polling

The whole library reads time through `package:clock`, and `testWidgets` binds
`clock` to the fake one. So `pump(const Duration(minutes: 5))` genuinely ages
data past its `staleTime` and fires `gcTime` timers — no `withClock`, no
sleeping, no flake.

A stale-time case leaves the screen and comes back, once inside the stale
time and once after it, and counts requests:

```dart snippet="guides/testing.md#stale-time"
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
```

The second visit shows the list without a request; the third shows the
cached list at once *and* fetches, because stale data is still shown while
it is refreshed. Keep the gap under `gcTime` (five minutes by default), or the
entry is gone and the third visit starts from a spinner.

A polling case steps the interval:

```dart snippet="guides/testing.md#polling"
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
```

The interval counts from the query's last update, not from the first fetch,
so each poll is the interval plus the fake's latency. Polling stops when the
screen goes, so the harness's teardown settles as usual.

## Testing without widgets

A `QueryController` is a plain `ValueListenable`, testable with `test()`
rather than `testWidgets`. It fetches only while something listens — the
same rule a widget follows — so a case adds a listener and waits for the
result it wants:

```dart snippet="guides/testing.md#controller"
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
```

This runs on real time: the fake's latency is zero, and the case awaits a
completer rather than sleeping. The teardown is shorter than a widget test's
because no binding checks for pending timers — but `client.clear()` still
cancels the `gcTime` timer the query started.

For the pure-Dart core, the same case runs under `dart test` with a
`QueryObserver`. When the case is about time, wrap it in `fakeAsync` from
[`package:fake_async`](https://pub.dev/packages/fake_async): `clock` follows
its fake time, and `async.elapse` fires the timers.

```dart snippet="prose-only: needs package:fake_async and package:test, which this site's compiled samples do not depend on"
import 'package:fake_async/fake_async.dart';
import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

void main() {
  test('a price goes stale after two minutes', () {
    fakeAsync((async) {
      final client = QueryClient();
      final observer = client.observe<Product, Product>(
        productQuery(FakeProductRepository(catalogue: [lamp]), 'p1'),
      );
      final unsubscribe = observer.subscribe((_) {});

      async.elapse(const Duration(milliseconds: 300)); // the fake's latency
      expect(observer.currentResult.dataOrNull, lamp);
      expect(observer.currentResult.isStale, isFalse);

      async.elapse(const Duration(minutes: 2));
      expect(observer.currentResult.isStale, isTrue);

      unsubscribe();
      client.clear();
    });
  });
}
```

`productQuery` is the product-detail options from the [options
reference](../reference/query-options.md), with a two-minute `staleTime`.
The observer marks its result stale on a timer of its own, which is why
`elapse` alone flips `isStale` with no refetch.

:::note[In React Query]
The React docs recommend a fresh `QueryClient` per test with `retry: false`
and wrapping the component in a provider — the same shape as here. What has
no React counterpart is the teardown: Jest does not check for pending timers
when a test ends, and Flutter's test binding does.
:::

## In the examples

The *Task manager* example's acceptance suite,
[`examples/task_manager/test/acceptance_test.dart`](https://github.com/KoTTi97/query_kit/blob/main/examples/task_manager/test/acceptance_test.dart),
is one widget test per feature of a whole app — the first load, detail
entries seeded from the list, a debounced search, a rename that rolls back,
a switch confirmed by polling, a retried error — against a fake of its
backend, in the shape this page describes.
