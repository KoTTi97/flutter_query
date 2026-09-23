/// The cookbook's first ten recipes (R1–R10), as code the analyzer sees.
///
/// Every recipe works on the same small app — a product catalogue with a
/// list, a search, a detail screen, an edit form and an endless feed — so a
/// reader can follow one codebase from recipe to recipe. In an app these
/// would be several files; the section comments name the file each part
/// would live in. What needs `dio`, `package:http` or `connectivity_plus`
/// stays prose-only on the pages, since this package may depend on none of
/// them; [ProductApi] is the seam between the two.
///
/// Same rule as the rest of this package: each region is marked with the
/// page that shows it, and the fence on that page names the region.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

// ===========================================================================
// lib/data/models.dart
// ===========================================================================

/// A product as the backend sends it. Value equality, so a refetch that
/// returns the same product keeps the widgets built from it.
@immutable
class Product {
  const Product({required this.id, required this.name, required this.price});

  factory Product.fromJson(Map<String, Object?> json) => Product(
        id: json['id']! as String,
        name: json['name']! as String,
        price: json['price']! as int,
      );

  final String id;
  final String name;

  /// In cents.
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

/// One page of the endless feed: its products, and where the next page
/// starts — `null` on the last one.
@immutable
class ProductPage {
  const ProductPage({required this.items, required this.nextOffset});

  final List<Product> items;
  final int? nextOffset;
}

/// What the edit form sends: no id for a new product.
@immutable
class ProductDraft {
  const ProductDraft({this.id, required this.name, required this.price});

  final String? id;
  final String name;
  final int price;
}

// ===========================================================================
// lib/data/api_exception.dart
// ===========================================================================

// >>> cookbook/wiring-dio-and-http.md#api-exception
/// Every failure the API layer throws: a sentence a user can read, and the
/// HTTP status when a response arrived.
class ApiException implements Exception {
  const ApiException(this.message, {this.status});

  final String message;

  /// `null` when no response arrived at all — a timeout, no network.
  final int? status;

  /// The server knows who we are and said no, or does not know who we are.
  bool get isAuth => status == 401 || status == 403;

  /// The request itself was wrong; asking again will not help.
  bool get isClientError => status != null && status! >= 400 && status! < 500;

  @override
  String toString() => message;
}

/// A 422: the server refused the input, field by field.
class ValidationException extends ApiException {
  const ValidationException(this.fieldErrors)
      : super('Please correct the highlighted fields', status: 422);

  /// Field name → what is wrong with it, as the server said it.
  final Map<String, String> fieldErrors;
}
// <<<

// ===========================================================================
// lib/data/product_api.dart
// ===========================================================================

// >>> cookbook/wiring-dio-and-http.md#product-api
/// The calls the screens make. The query functions depend on this, not on
/// dio — so a test hands them a fake, and the transport can change.
abstract interface class ProductApi {
  Future<List<Product>> list({String search = '', QueryCancelToken? signal});

  Future<Product> get(String id, {QueryCancelToken? signal});

  Future<ProductPage> page(int offset, {QueryCancelToken? signal});

  /// Creates the product when [ProductDraft.id] is null, else updates it.
  Future<Product> save(ProductDraft draft);
}
// <<<

/// How widgets reach the [ProductApi]. Any dependency-injection tool does
/// the same job; this one is plain Flutter.
class ProductApiScope extends InheritedWidget {
  const ProductApiScope({super.key, required this.api, required super.child});

  final ProductApi api;

  static ProductApi of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProductApiScope>()!.api;

  @override
  bool updateShouldNotify(ProductApiScope oldWidget) => oldWidget.api != api;
}

// ===========================================================================
// lib/features/products/product_queries.dart
// ===========================================================================

// >>> cookbook/wiring-dio-and-http.md#keys
/// Every key of the products feature, in one place.
abstract final class ProductKeys {
  static final QueryKey all = QueryKey(const <Object?>['products']);

  /// Every list, whatever it was searched for — the prefix a write
  /// invalidates.
  static final QueryKey lists = all.append(const <Object?>['list']);

  static QueryKey list({String search = ''}) => lists.append(<Object?>[search]);

  static QueryKey detail(String id) => all.append(<Object?>['detail', id]);

  static final QueryKey feed = all.append(const <Object?>['feed']);
}
// <<<

// >>> cookbook/list-detail-seeding.md#list-query
QueryObserverOptions<List<Product>> productListQuery(
  ProductApi api, {
  String search = '',
}) =>
    QueryObserverOptions<List<Product>>(
      queryKey: ProductKeys.list(search: search),
      queryFn: (context) async {
        final products = await api.list(search: search, signal: context.signal);
        // One entry per product, so the detail screen opens with data and
        // every later list response reaches the detail too.
        for (final product in products) {
          context.client
              .setQueryData<Product>(ProductKeys.detail(product.id), product);
        }
        return products;
      },
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    );
// <<<

// >>> cookbook/list-detail-seeding.md#detail-query
QueryObserverOptions<Product> productQuery(
  QueryClient client,
  ProductApi api,
  String id,
) =>
    QueryObserverOptions<Product>(
      queryKey: ProductKeys.detail(id),
      queryFn: (context) => api.get(id, signal: context.signal),
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
      // The fallback for an entry the list has not seeded yet — a deep
      // link, or a list still loading when the row was tapped.
      initialData: InitialData<Product>.compute(() => _findInLists(client, id)),
      // As old as the list it came from, so it is refetched when that is
      // stale rather than trusted as brand new.
      initialDataUpdatedAtCompute: () => _listUpdatedAt(client, id),
    );

Product? _findInLists(QueryClient client, String id) {
  for (final (_, products) in client.getQueriesData<List<Product>>(
    filters: QueryFilters(queryKey: ProductKeys.lists),
  )) {
    for (final product in products ?? const <Product>[]) {
      if (product.id == id) return product;
    }
  }
  return null;
}

DateTime? _listUpdatedAt(QueryClient client, String id) {
  for (final (key, products) in client.getQueriesData<List<Product>>(
    filters: QueryFilters(queryKey: ProductKeys.lists),
  )) {
    if (products?.any((product) => product.id == id) ?? false) {
      return client.getQueryState<List<Product>>(key)?.dataUpdatedAt;
    }
  }
  return null;
}
// <<<

// ===========================================================================
// R2 — auth-and-token-refresh.md
// ===========================================================================

// >>> cookbook/auth-and-token-refresh.md#retry-policy
/// Retries what might succeed next time — a timeout, a 503 — and never a
/// refused login or a request the server called wrong.
const RetryPolicy retryTransientFailures = RetryPolicy.when(_isTransient);

bool _isTransient(int failureCount, Object error, StackTrace _) =>
    failureCount < 3 && !(error is ApiException && error.isClientError);
// <<<

// >>> cookbook/auth-and-token-refresh.md#client-per-user
/// Who is signed in: `null` while nobody is. Your auth layer owns this.
final ValueNotifier<String?> signedInUser = ValueNotifier<String?>(null);

class SignedInShell extends StatelessWidget {
  const SignedInShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
        valueListenable: signedInUser,
        builder: (context, userId, _) {
          if (userId == null) return const SignInScreen();
          // A new user is a new key, so a new client with an empty cache;
          // the old one is cleared once its subtree has gone.
          return QueryClientProvider.create(
            key: ValueKey<String>(userId),
            create: () => QueryClient(
              defaultOptions: const DefaultOptions(
                queries: QueryDefaults(retry: retryTransientFailures),
              ),
            ),
            child: child,
          );
        },
      );
}
// <<<

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) => const Placeholder();
}

// >>> cookbook/auth-and-token-refresh.md#sign-out-same-client
Future<void> signOutKeepingTheClient(QueryClient client) async {
  // 1. Leave the signed-in screens, so nothing reads a key any more …
  signedInUser.value = null;
  // … and let that frame run, so their observers are gone.
  await WidgetsBinding.instance.endOfFrame;
  // 2. Stop what is still in flight, then drop every entry and mutation.
  await client.cancelQueries();
  client.clear();
}
// <<<

// ===========================================================================
// R3 — pull-to-refresh.md (lib/features/products/product_list_screen.dart)
// ===========================================================================

// >>> cookbook/pull-to-refresh.md#screen
class ProductListScreen extends StatelessWidget {
  const ProductListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final products =
        context.query(productListQuery(ProductApiScope.of(context)));
    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      body: RefreshIndicator(
        // Completes when the refetch has settled, success or failure; it
        // never throws, so the spinner always goes away.
        onRefresh: products.refetch,
        child: switch (products) {
          QueryPending() => const _Scrollable(
              child: Center(child: CircularProgressIndicator()),
            ),
          QuerySuccess(:final data) => ProductListView(data),
          // A failed refresh keeps the list on screen, with a banner.
          QueryError(:final error, staleData: final data?) =>
            ProductListView(data, problem: '$error'),
          QueryError(:final error) => _Scrollable(
              child: Center(child: Text('Could not load products: $error')),
            ),
        },
      ),
    );
  }
}
// <<<

// >>> cookbook/pull-to-refresh.md#scrollable
/// A `RefreshIndicator` only works over something that scrolls — also when
/// there is nothing to show yet.
class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(height: constraints.maxHeight, child: child),
        ),
      );
}
// <<<

class ProductListView extends StatelessWidget {
  const ProductListView(this.products, {super.key, this.problem});

  final List<Product> products;

  /// Why the last refresh failed, when it did.
  final String? problem;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const _Scrollable(child: Center(child: Text('No products yet')));
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: products.length + (problem == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (problem case final problem? when index == 0) {
          return ListTile(
            leading: const Icon(Icons.cloud_off),
            title: Text('Could not refresh: $problem'),
          );
        }
        return ProductTile(products[index - (problem == null ? 0 : 1)]);
      },
    );
  }
}

// >>> cookbook/list-detail-seeding.md#tile
class ProductTile extends StatelessWidget {
  const ProductTile(this.product, {super.key});

  final Product product;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(product.name),
        subtitle: Text(formatPrice(product.price)),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ProductDetailScreen(id: product.id),
          ),
        ),
      );
}
// <<<

String formatPrice(int cents) =>
    '€${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

// >>> cookbook/pull-to-refresh.md#refresh-everything
/// Everything under `products` that is on screen, at once. Unlike an
/// observer's `refetch`, it does not wait for a fetch paused offline.
Future<void> refreshProducts(BuildContext context) =>
    QueryClientProvider.read(context).refetchQueries(
      filters: QueryFilters(
        queryKey: ProductKeys.all,
        type: QueryTypeFilter.active,
      ),
    );
// <<<

// ===========================================================================
// R5 — list-detail-seeding.md (lib/features/products/product_detail_screen.dart)
// ===========================================================================

// >>> cookbook/list-detail-seeding.md#detail-screen
class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    final api = ProductApiScope.of(context);
    return QueryBuilder<Product>(
      options: productQuery(client, api, id),
      builder: (context, product) => Scaffold(
        appBar: AppBar(title: Text(product.dataOrNull?.name ?? 'Product')),
        body: switch (product) {
          QueryPending() => const Center(child: CircularProgressIndicator()),
          QueryError(:final error, staleData: null) =>
            Center(child: Text('Could not load: $error')),
          QueryError(staleData: final data?) ||
          QuerySuccess(:final data) =>
            ProductDetails(data, refreshing: product.isFetching),
        },
      ),
    );
  }
}
// <<<

class ProductDetails extends StatelessWidget {
  const ProductDetails(this.product, {super.key, this.refreshing = false});

  final Product product;
  final bool refreshing;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          if (refreshing) const LinearProgressIndicator(),
          Text(product.name, style: Theme.of(context).textTheme.headlineSmall),
          Text(formatPrice(product.price)),
        ],
      );
}

// ===========================================================================
// R4 — search-as-you-type.md (lib/features/products/product_search.dart)
// ===========================================================================

// >>> cookbook/search-as-you-type.md#options
QueryObserverOptions<List<Product>> productSearchQuery(
  ProductApi api,
  String needle,
) =>
    productListQuery(api, search: needle).copyWith(
      // An empty box asks the server nothing.
      enabled: needle.isEmpty ? Enabled.no : Enabled.yes,
      // While the new needle loads, keep showing the last results.
      placeholderData: const PlaceholderData<List<Product>>.keepPrevious(),
    );
// <<<

// >>> cookbook/search-as-you-type.md#screen
class ProductSearchScreen extends StatefulWidget {
  const ProductSearchScreen({super.key});

  @override
  State<ProductSearchScreen> createState() => _ProductSearchScreenState();
}

class _ProductSearchScreenState extends State<ProductSearchScreen>
    with QueryMixin {
  static const Duration debounce = Duration(milliseconds: 300);

  Timer? _debounce;
  String _needle = '';

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(debounce, () {
      final needle = text.trim();
      if (mounted && needle != _needle) setState(() => _needle = needle);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // One `id`, so the read follows the needle from key to key and
    // `keepPrevious` has a previous to keep.
    final results = watchQuery(
      productSearchQuery(ProductApiScope.of(context), _needle),
      id: 'search',
    );
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(hintText: 'Search products'),
        ),
        bottom: results.isFetching
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: _needle.isEmpty
          ? const Center(child: Text('Type to search'))
          : switch (results) {
              QueryPending() => const SizedBox.shrink(),
              QueryError(:final error) => Center(child: Text('$error')),
              QuerySuccess(data: []) =>
                Center(child: Text('Nothing matches "$_needle"')),
              QuerySuccess(:final data) => Opacity(
                  // Last needle's results, while this one loads.
                  opacity: results.isPlaceholderData ? 0.5 : 1,
                  child: ListView(
                    children: <Widget>[
                      for (final product in data) ProductTile(product),
                    ],
                  ),
                ),
            },
    );
  }
}
// <<<

// ===========================================================================
// R6 — forms-and-server-validation.md (lib/features/products/product_form.dart)
// ===========================================================================

// >>> cookbook/forms-and-server-validation.md#mutation
MutationOptions<Product, ProductDraft, void> saveProductMutation(
  QueryClient client,
  ProductApi api,
) =>
    MutationOptions.simple(
      mutationKey: QueryKey(const <Object?>['products', 'save']),
      mutationFn: api.save,
      onSuccess: (product, _, __) {
        // The response is the product as saved: the detail has it now …
        client.setQueryData<Product>(ProductKeys.detail(product.id), product);
        // … and every list may have changed order or membership.
        return client.invalidateQueries(
          filters: QueryFilters(queryKey: ProductKeys.lists),
        );
      },
    );
// <<<

// >>> cookbook/forms-and-server-validation.md#form
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.initial});

  /// The product being edited, or `null` for a new one.
  final Product? initial;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> with QueryMixin {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name);
  late final TextEditingController _price = TextEditingController(
    text: widget.initial == null ? '' : '${widget.initial!.price / 100}',
  );

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final save = watchMutation(
      saveProductMutation(queryClient, ProductApiScope.of(context)),
    );
    final result = save.value;

    // The server's verdict, read off the mutation's state: no second copy
    // of it to keep in sync.
    final serverErrors = switch (result) {
      MutationError(error: ValidationException(:final fieldErrors)) =>
        fieldErrors,
      _ => const <String, String>{},
    };

    void submit() {
      if (!_form.currentState!.validate()) return;
      save.mutate(
        ProductDraft(
          id: widget.initial?.id,
          name: _name.text.trim(),
          price: (double.parse(_price.text) * 100).round(),
        ),
        callbacks: MutateCallbacks<Product, ProductDraft, void>(
          // Runs only while this screen still listens, so the context is
          // still in the tree.
          onSuccess: (product, _, __) => Navigator.of(context).pop(product),
        ),
      );
    }

    // Typing into a field the server refused clears the refusal.
    void edited(String _) {
      if (result.isError) save.reset();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'New product' : 'Edit product'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (result case MutationError(:final error)
                when error is! ValidationException)
              Text('Could not save: $error'),
            TextFormField(
              controller: _name,
              enabled: !result.isPending,
              onChanged: edited,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: serverErrors['name'],
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Required' : null,
            ),
            TextFormField(
              controller: _price,
              enabled: !result.isPending,
              onChanged: edited,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Price',
                errorText: serverErrors['price'],
              ),
              validator: (value) =>
                  double.tryParse(value ?? '') == null ? 'A number' : null,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: result.isPending ? null : submit,
              child: result.isPending
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
// <<<

// >>> cookbook/forms-and-server-validation.md#mutate-async
Future<void> saveAndReport(
  MutationController<Product, ProductDraft, void> save,
  ProductDraft draft,
  ScaffoldMessengerState messenger,
) async {
  try {
    final product = await save.mutateAsync(draft);
    messenger.showSnackBar(SnackBar(content: Text('Saved ${product.name}')));
  } on ValidationException {
    // The form shows these next to the fields; nothing to add here.
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('Could not save: $error')));
  }
}
// <<<

// ===========================================================================
// R7 — global-error-snackbar.md (lib/app/query_client.dart)
// ===========================================================================

// >>> cookbook/global-error-snackbar.md#meta
/// What a query or a mutation tells the app-wide error handler. The library
/// never reads `meta`; this app's handler does.
@immutable
class ErrorReporting {
  /// Toast failures, saying [message] instead of the generic sentence.
  const ErrorReporting.toast([this.message]) : show = true;

  const ErrorReporting._silent()
      : show = false,
        message = null;

  /// No toast: the screen shows this failure itself.
  static const ErrorReporting silent = ErrorReporting._silent();

  final bool show;
  final String? message;
}
// <<<

// >>> cookbook/global-error-snackbar.md#client
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

QueryClient createQueryClient() => QueryClient(
      queryCache: QueryCache(
        onError: (error, _, query) {
          // A first load has nothing on screen and shows its own error
          // state; a toast is for a refresh of data the user is looking at.
          if (!query.state.hasData) return;
          _toast(error, query.meta, fallback: 'Could not refresh');
        },
      ),
      mutationCache: MutationCache(
        onError: (error, _, __, ___, mutation) {
          // A form shows its field errors next to the fields.
          if (error is ValidationException) return;
          // A mutation with an `onError` of its own handles its failures.
          if (mutation.options.onError != null) return;
          _toast(error, mutation.meta, fallback: 'Could not save');
        },
      ),
    );

void _toast(Object error, Object? meta, {required String fallback}) {
  final reporting = meta is ErrorReporting ? meta : null;
  if (reporting?.show == false) return;
  final detail = error is ApiException ? error.message : 'Something went wrong';
  scaffoldMessengerKey.currentState
    // Ten queries failing together — the network went — say it once.
    ?..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text('${reporting?.message ?? fallback}: $detail')));
}
// <<<

// >>> cookbook/global-error-snackbar.md#app
class CatalogueApp extends StatelessWidget {
  const CatalogueApp({super.key, required this.api});

  final ProductApi api;

  @override
  Widget build(BuildContext context) => ProductApiScope(
        api: api,
        child: QueryClientProvider.create(
          create: createQueryClient,
          child: MaterialApp(
            scaffoldMessengerKey: scaffoldMessengerKey,
            home: const ProductListScreen(),
          ),
        ),
      );
}
// <<<

// >>> cookbook/global-error-snackbar.md#opt-out
QueryObserverOptions<List<Product>> quietProductListQuery(ProductApi api) =>
    productListQuery(api).copyWith(meta: ErrorReporting.silent);
// <<<

// ===========================================================================
// R8 — infinite-list-view.md (lib/features/products/product_feed.dart)
// ===========================================================================

// >>> cookbook/infinite-list-view.md#options
InfiniteQuerySelectOptions<ProductPage, int, List<Product>> productFeedQuery(
  ProductApi api,
) =>
    InfiniteQuerySelectOptions<ProductPage, int, List<Product>>(
      queryKey: ProductKeys.feed,
      initialPageParam: 0,
      pageFn: (context) => api.page(context.pageParam, signal: context.signal),
      getNextPageParam: (page, _, __, ___) => page.nextOffset,
      select: _productsOf,
    );

/// A top-level function, not a closure: a new function on every build would
/// run the select again on every build.
List<Product> _productsOf(InfiniteData<ProductPage, int> data) =>
    <Product>[for (final page in data.pages) ...page.items];
// <<<

// >>> cookbook/infinite-list-view.md#screen
class ProductFeedScreen extends StatefulWidget {
  const ProductFeedScreen({super.key});

  @override
  State<ProductFeedScreen> createState() => _ProductFeedScreenState();
}

class _ProductFeedScreenState extends State<ProductFeedScreen> {
  static const double loadMoreThreshold = 400;

  final ScrollController _scroll = ScrollController();

  /// The builder's controller, for the scroll listener. The builder owns it.
  InfiniteQueryController<ProductPage, int, List<Product>>? _feed;

  /// How long the list was when the last page was asked for.
  double? _askedAtExtent;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final feed = _feed;
    if (feed == null || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.extentAfter < loadMoreThreshold &&
        // Once per length of the list: the listener hears every pixel.
        position.maxScrollExtent != _askedAtExtent &&
        feed.hasNextPage &&
        !feed.isFetchingNextPage) {
      _askedAtExtent = position.maxScrollExtent;
      feed.fetchNextPage().ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('All products')),
      body: InfiniteQueryBuilder(
        options: productFeedQuery(ProductApiScope.of(context)),
        builder: (context, feed) {
          _feed = feed;
          return switch (feed.value) {
            QueryPending() => const Center(child: CircularProgressIndicator()),
            QueryError(:final error, staleData: null) =>
              Center(child: Text('Could not load: $error')),
            QuerySuccess(:final data) ||
            QueryError(staleData: final data?) =>
              RefreshIndicator(
                onRefresh: feed.refetch,
                child: ListView.builder(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  // One more row than there are products: the footer.
                  itemCount: data.length + 1,
                  itemBuilder: (context, index) => index < data.length
                      ? ProductTile(data[index])
                      : FeedFooter(feed),
                ),
              ),
          };
        },
      ),
    );
  }
}
// <<<

// >>> cookbook/infinite-list-view.md#footer
class FeedFooter extends StatelessWidget {
  const FeedFooter(this.feed, {super.key});

  final InfiniteQueryController<ProductPage, int, List<Product>> feed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: switch ((
            feed.isFetchingNextPage,
            feed.isFetchNextPageError,
            feed.hasNextPage,
          )) {
            (true, _, _) => const CircularProgressIndicator(),
            (_, true, _) => TextButton(
                onPressed: feed.fetchNextPage,
                child: const Text('Could not load more — try again'),
              ),
            // Also the way on when the first page does not fill the screen,
            // so there is nothing to scroll.
            (_, _, true) => TextButton(
                onPressed: feed.fetchNextPage,
                child: const Text('Load more'),
              ),
            _ => const Text("That's everything"),
          },
        ),
      );
}
// <<<

// ===========================================================================
// R9 — lifecycle-and-connectivity-wiring.md (lib/main.dart)
// ===========================================================================

// >>> cookbook/lifecycle-and-connectivity-wiring.md#focus
QueryClient createClientWithFocusRules() => QueryClient(
      // Back after less than a minute away? Not a reason to refetch the
      // world. Paused work still resumes at once.
      focusManager: AppFocusManager(
        refetchMinBackgroundDuration: const Duration(minutes: 1),
      ),
    );
// <<<

// >>> cookbook/lifecycle-and-connectivity-wiring.md#probe
/// Asks [probe] — "can I reach my own backend?" — every [every], and says
/// whenever the answer changes.
Stream<bool> reachability(
  Future<bool> Function() probe, {
  Duration every = const Duration(seconds: 30),
}) async* {
  bool? last;
  while (true) {
    final reachable = await probe();
    if (reachable != last) yield last = reachable;
    await Future<void>.delayed(every);
  }
}
// <<<

// >>> cookbook/lifecycle-and-connectivity-wiring.md#debug-switch
/// A developer's "pretend to be offline" switch, for trying the offline
/// states without a flight-mode dance.
final ValueNotifier<bool> simulateOffline = ValueNotifier<bool>(false);

class DebugOnlineSwitch extends StatelessWidget {
  const DebugOnlineSwitch({
    super.key,
    required this.client,
    required this.child,
  });

  final QueryClient client;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: simulateOffline,
        builder: (context, offline, _) => QueryClientProvider(
          client: client,
          onlineStatus: OnlineStatus.fixed(!offline),
          child: child,
        ),
      );
}
// <<<
