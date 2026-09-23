/// The samples of the site's tools guides and API reference pages that need
/// no test runner: `reference/*.md`, `guides/debugging.md` and
/// `guides/does-this-replace-state-management.md`, and the screens the
/// testing guide tests. The testing guide's tests themselves run in
/// `test/c4d_testing_test.dart`.
///
/// Same rule as the rest of this package — each region is marked with the
/// page that shows it, and the fence on that page names the region.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

// ---------------------------------------------------------------------------
// The shop the reference pages talk about.
// ---------------------------------------------------------------------------

@immutable
class Product {
  const Product({required this.id, required this.name, required this.price});

  final String id;
  final String name;
  final int price;

  @override
  bool operator ==(Object other) =>
      other is Product &&
      other.id == id &&
      other.name == name &&
      other.price == price;

  @override
  int get hashCode => Object.hash(id, name, price);
}

/// Stands in for a repository over an HTTP client.
abstract interface class ProductRepository {
  Future<Product> product(String id, {QueryCancelToken? signal});

  Future<List<Product>> products({QueryCancelToken? signal});

  Future<Product> addProduct(String name);
}

/// Stands in for `package:logging`'s `Logger`, which this package may not
/// depend on; the signature is the same.
class AppLog {
  void warning(Object? message, [Object? error, StackTrace? stackTrace]) =>
      debugPrint('$message: $error');
}

final AppLog log = AppLog();

// ---------------------------------------------------------------------------
// guides/debugging.md
// ---------------------------------------------------------------------------

// >>> guides/debugging.md#inspector
/// Every entry of the query cache, one line each. For debug builds.
class CacheInspector extends StatefulWidget {
  const CacheInspector({super.key});

  @override
  State<CacheInspector> createState() => _CacheInspectorState();
}

class _CacheInspectorState extends State<CacheInspector> {
  QueryClient? _client;
  void Function()? _unsubscribe;
  bool _rebuildPending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = QueryClientProvider.of(context);
    if (client == _client) return;
    _unsubscribe?.call();
    _client = client;
    _unsubscribe = client.queryCache.subscribe((event) {
      // About the readers, not the cache — and the first fires on every
      // reader's build.
      if (event is QueryObserverOptionsUpdated ||
          event is QueryObserverResultsUpdated) {
        return;
      }
      _rebuildAfterFrame();
    });
  }

  /// An event can arrive while a frame is being built, when `setState` is
  /// not allowed; rebuild once that frame is done, however many came.
  void _rebuildAfterFrame() {
    if (_rebuildPending) return;
    _rebuildPending = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _rebuildPending = false;
        if (mounted) setState(() {});
      })
      ..scheduleFrame();
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final query in _client!.queryCache.queries)
            Text(
              '${query.queryKey.debugString} '
              '${query.state.status.name}/${query.state.fetchStatus.name} '
              'observers=${query.observersCount} '
              'stale=${query.isStale()}',
            ),
        ],
      );
}
// <<<

// ---------------------------------------------------------------------------
// reference/query-options.md
// ---------------------------------------------------------------------------

// >>> reference/query-options.md#product-query
QueryObserverOptions<Product> productQuery(ProductRepository repo, String id) =>
    QueryObserverOptions(
      queryKey: QueryKey(<Object?>['products', 'detail', id]),
      queryFn: (context) => repo.product(id, signal: context.signal),
      // A price may change, but not every second.
      staleTime: const StaleTime.duration(Duration(minutes: 2)),
      // Kept for a while after the detail screen closes, for the back button.
      gcTime: const GcTime.duration(Duration(minutes: 10)),
      retry: const RetryPolicy.times(2),
      refetchOnWindowFocus: RefetchOn.never,
    );
// <<<

// ---------------------------------------------------------------------------
// reference/query-client.md
// ---------------------------------------------------------------------------

// >>> reference/query-client.md#setup
final QueryClient appClient = QueryClient(
  queryCache: QueryCache(
    onError: (error, stackTrace, query) => log.warning(
      'query ${query.queryKey.debugString} failed',
      error,
      stackTrace,
    ),
  ),
  defaultOptions: const DefaultOptions(
    queries: QueryDefaults(
      staleTime: StaleTime.duration(Duration(seconds: 30)),
    ),
  ),
);
// <<<

// ---------------------------------------------------------------------------
// guides/testing.md — the screen under test
// ---------------------------------------------------------------------------

// >>> guides/testing.md#screen
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
// <<<
