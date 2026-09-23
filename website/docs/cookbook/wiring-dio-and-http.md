---
title: Wiring dio or package:http
description: One API client for every query — cancellation handed on to the transport, timeouts, and failures turned into errors a screen can show.
---

# Wiring dio or package:http

A query function is any function that returns a `Future`, so the library does
not care how you talk to your server. The app does: a request the library has
cancelled should stop on the wire, a server that hangs should fail rather than
spin for ever, a 404 has to become an error (`package:http` does not throw for
one), and whatever reaches a screen should be a sentence a user can read, not a
`DioException` with a stack of HTTP detail. This recipe puts all of that in one
API client and keeps it out of the queries.

Every recipe in the cookbook's first half builds on the same small app: a
product catalogue with a list, a search, a detail screen, an edit form and an
endless feed. This page lays its foundation.

## The finished code

The error type every layer above the transport sees:

```dart snippet="cookbook/wiring-dio-and-http.md#api-exception" title="lib/data/api_exception.dart"
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
```

The client, on dio 5. It is the only file that imports dio:

```dart snippet="prose-only: needs dio, which neither published package may depend on" title="lib/data/api_client.dart"
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'api_exception.dart';

class ApiClient {
  ApiClient({required String baseUrl, Dio? dio})
      : dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              // A server that hangs must fail the query, not leave it
              // fetching for ever.
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            ));

  final Dio dio;

  Future<T> get<T>(
    String path,
    T Function(Object? json) parse, {
    Map<String, Object?>? query,
    QueryCancelToken? signal,
  }) =>
      _run(
        () => dio.get<Object?>(
          path,
          queryParameters: query,
          cancelToken: _bridge(signal),
        ),
        parse,
      );

  Future<T> send<T>(
    String method,
    String path,
    T Function(Object? json) parse, {
    Object? body,
  }) =>
      _run(
        () => dio.request<Object?>(
          path,
          data: body,
          options: Options(method: method),
        ),
        parse,
      );

  /// A query's cancellation, handed on to dio: when the library cancels the
  /// fetch, dio aborts the request.
  static CancelToken? _bridge(QueryCancelToken? signal) {
    if (signal == null) return null;
    final token = CancelToken();
    signal.onCancel(token.cancel);
    return token;
  }

  Future<T> _run<T>(
    Future<Response<Object?>> Function() request,
    T Function(Object? json) parse,
  ) async {
    final Response<Object?> response;
    try {
      response = await request();
    } on DioException catch (error) {
      // Cancelled by the library: it already knows, and a CancelledError of
      // its own wins. Nothing to translate.
      if (CancelToken.isCancel(error)) rethrow;
      throw _translate(error);
    }
    try {
      return parse(response.data);
    } on Object {
      // A missing field or a wrong type is a server failure too, and a
      // TypeError is no message for a user.
      throw const ApiException('The server sent something unexpected');
    }
  }

  static ApiException _translate(DioException error) {
    final status = error.response?.statusCode;
    final body = _decode(error.response?.data);
    if (status == 422 && body is Map && body['errors'] is Map) {
      return ValidationException(<String, String>{
        for (final MapEntry(:key, :value) in (body['errors'] as Map).entries)
          '$key': '$value',
      });
    }
    if (body is Map && body['message'] is String) {
      return ApiException(body['message'] as String, status: status);
    }
    return ApiException(
      switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'The server is not responding',
        DioExceptionType.badResponse => 'The server said no ($status)',
        _ => 'The server is unreachable',
      },
      status: status,
    );
  }

  /// dio hands an error body back parsed or as text, depending on its
  /// content type; read both.
  static Object? _decode(Object? data) {
    if (data is! String) return data;
    try {
      return jsonDecode(data);
    } on FormatException {
      return null;
    }
  }
}
```

The calls the screens make, as an interface, and its dio implementation:

```dart snippet="cookbook/wiring-dio-and-http.md#product-api" title="lib/data/product_api.dart"
/// The calls the screens make. The query functions depend on this, not on
/// dio — so a test hands them a fake, and the transport can change.
abstract interface class ProductApi {
  Future<List<Product>> list({String search = '', QueryCancelToken? signal});

  Future<Product> get(String id, {QueryCancelToken? signal});

  Future<ProductPage> page(int offset, {QueryCancelToken? signal});

  /// Creates the product when [ProductDraft.id] is null, else updates it.
  Future<Product> save(ProductDraft draft);
}
```

```dart snippet="prose-only: needs dio, through the client above" title="lib/data/dio_product_api.dart"
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'api_client.dart';
import 'models.dart';
import 'product_api.dart';

class DioProductApi implements ProductApi {
  DioProductApi(this._client);

  final ApiClient _client;

  @override
  Future<List<Product>> list({String search = '', QueryCancelToken? signal}) =>
      _client.get(
        '/products',
        (json) => <Product>[
          for (final item in json! as List<Object?>)
            Product.fromJson(item! as Map<String, Object?>),
        ],
        query: <String, Object?>{if (search.isNotEmpty) 'q': search},
        signal: signal,
      );

  @override
  Future<Product> get(String id, {QueryCancelToken? signal}) => _client.get(
        '/products/$id',
        (json) => Product.fromJson(json! as Map<String, Object?>),
        signal: signal,
      );

  @override
  Future<ProductPage> page(int offset, {QueryCancelToken? signal}) =>
      _client.get(
        '/products',
        (json) {
          final body = json! as Map<String, Object?>;
          return ProductPage(
            items: <Product>[
              for (final item in body['items']! as List<Object?>)
                Product.fromJson(item! as Map<String, Object?>),
            ],
            nextOffset: body['nextOffset'] as int?,
          );
        },
        query: <String, Object?>{'offset': offset, 'limit': 20},
        signal: signal,
      );

  @override
  Future<Product> save(ProductDraft draft) => _client.send(
        draft.id == null ? 'POST' : 'PUT',
        draft.id == null ? '/products' : '/products/${draft.id}',
        (json) => Product.fromJson(json! as Map<String, Object?>),
        body: <String, Object?>{'name': draft.name, 'price': draft.price},
      );
}
```

And the keys the queries use, in one place:

```dart snippet="cookbook/wiring-dio-and-http.md#keys" title="lib/features/products/product_keys.dart"
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
```

The app hands the implementation to its widgets once, in `main`:

```dart snippet="prose-only: needs dio, through DioProductApi" title="lib/main.dart"
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'data/api_client.dart';
import 'data/dio_product_api.dart';

void main() {
  final api = DioProductApi(ApiClient(baseUrl: 'https://api.example.com/v1'));
  runApp(CatalogueApp(api: api));
}
```

`CatalogueApp` is the root widget from
[A global error snackbar](global-error-snackbar.md#the-finished-code): a
`ProductApiScope` (a plain `InheritedWidget` holding the `ProductApi`), the
`QueryClientProvider` and the `MaterialApp`. Any dependency-injection tool does
the same job as `ProductApiScope`.

## How it works

1. **The query functions depend on `ProductApi`, not on dio.** A query's
   `queryFn` calls `api.list(signal: context.signal)` and never sees an HTTP
   type. That is what lets [Testing a screen](testing-a-screen.md) hand the
   same screens a fake that answers from memory, and what would let you swap
   dio for `package:http` without touching a query.
2. **Cancellation crosses the bridge in `_bridge`.** Every query function is
   handed a `QueryCancelToken` as `context.signal`. `signal.onCancel(token.cancel)`
   hands the library's cancel on to a dio `CancelToken`, so when the library
   cancels a fetch — `cancelQueries` was called, or the last reader left while
   it ran, as when a newer search replaces an older one — dio aborts the
   request. (Reading `context.signal` is what allows the second case: a query
   function that never reads it is left to finish when its readers go.)
   `onCancel` runs the callback at once if the signal is already cancelled.
3. **A cancelled request is rethrown untouched.** When dio reports
   `CancelToken.isCancel(error)`, the library cancelled the fetch itself and
   already knows. Translating that into an `ApiException` would turn a quiet
   cancel into a failure a toast could report.
4. **Everything else becomes an `ApiException`.** A 422 with field errors
   becomes a `ValidationException` (the form in
   [Forms and server validation](forms-and-server-validation.md) reads it), a
   body with a `message` keeps the server's wording, and the rest is a sentence
   per failure kind. The `status` survives, so the retry policy in
   [Auth and token refresh](auth-and-token-refresh.md#retry-only-what-can-succeed)
   can refuse to repeat a 4xx.
5. **A parse failure is a server failure.** `parse` runs inside the client, so
   a missing field or a wrong type fails the query with a readable message
   instead of a `TypeError`.
6. **Timeouts are set on `BaseOptions`.** Without a `receiveTimeout`, a server
   that accepts the connection and never answers leaves the query fetching —
   the library has no timeout of its own, as TanStack Query has none.

## The same client on package:http

`package:http` 1.5 and later can abort a request: send an `AbortableRequest`
and complete its `abortTrigger`. A `QueryCancelToken` has a future that
completes on cancel, `whenCancelled`, which is exactly that trigger:

```dart snippet="prose-only: needs package:http, which neither published package may depend on" title="lib/data/http_api_client.dart"
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'api_exception.dart';

class HttpApiClient {
  HttpApiClient({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// No trailing slash, as for dio: `https://api.example.com/v1`, and paths
  /// start with one, `/products`. (`Uri.resolve` would drop the `/v1`.)
  final String baseUrl;
  final http.Client _client;

  Future<T> get<T>(
    String path,
    T Function(Object? json) parse, {
    Map<String, String>? query,
    QueryCancelToken? signal,
  }) async {
    final url = Uri.parse('$baseUrl$path');
    final request = http.AbortableRequest(
      'GET',
      query == null ? url : url.replace(queryParameters: query),
      // http 1.5 and later: the request is aborted when this completes.
      abortTrigger: signal?.whenCancelled,
    );
    final http.Response response;
    try {
      // The timeout covers waiting for the headers and reading the body.
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 30));
    } on http.RequestAbortedException {
      rethrow; // cancelled by the library, which already knows
    } on http.ClientException {
      throw const ApiException('The server is unreachable');
    } on TimeoutException {
      throw const ApiException('The server is not responding');
    }
    // package:http does not throw for a 404 or a 500 — a status is just a
    // number on a response. A query only fails if its function throws.
    if (response.statusCode >= 400) {
      throw ApiException(
        'The server said no (${response.statusCode})',
        status: response.statusCode,
      );
    }
    try {
      return parse(jsonDecode(response.body));
    } on Object {
      throw const ApiException('The server sent something unexpected');
    }
  }
}
```

## Traps

- **`package:http` does not throw for an error status.** A 404 or a 500 is a
  response like any other, and a query only fails when its function throws. A
  client that returns `jsonDecode(response.body)` without checking the status
  hands an error page to `fromJson`, or, worse, succeeds with it.
- **`.timeout` stops waiting; it does not stop the request.** On
  `package:http` the request goes on until the server answers or the client is
  closed. For a real deadline on dio, use its timeouts, which do abort.
- **Before `package:http` 1.5 there is no abort.** On an older version the
  request runs to the end on the wire whatever the library does. An explicit
  cancel (`cancelQueries`) still puts the entry back and drops the late
  answer; a query function that never reads `context.signal` is not even
  cancelled when its last reader leaves — the request finishes and its answer
  is cached. Upgrade rather than work around it.
- **Do not create a `CancelToken` per client.** One shared token cancels every
  request the client ever makes. Make one per call, from that call's signal, as
  `_bridge` does.
- **A mutation's signal is opt-in.** `mutationFn` receives only the variables,
  which is why `send` takes no `signal` here. A write that can be cancelled
  uses `mutationFnWithContext`, whose context carries a signal to bridge the
  same way — see [Cancelling mutations](../guides/cancelling-mutations.md).

## Variations

- **Several backends.** One `ApiClient` per base URL, and one `ProductApi`-style
  interface per feature. The queries still only see interfaces.
- **Auth headers and token refresh** go into a dio interceptor on the same
  `Dio` — see [Auth and token refresh](auth-and-token-refresh.md).
- **Logging.** dio's `LogInterceptor` on the client, not a `print` in each
  query function.

:::note[In React Query]
The same split: a query function receives an `AbortSignal` and passes it to
`fetch` or axios. Here the signal is a `QueryCancelToken`, and the one-line
bridge in `_bridge` plays the part that `signal` plays for axios. The
[showcase](https://github.com/KoTTi97/flutter_query/blob/main/examples/showcase/lib/shared/api.dart)
and the [task manager](https://github.com/KoTTi97/flutter_query/blob/main/examples/task_manager/lib/src/api.dart)
both wire dio this way.
:::

## See also

- [Query cancellation](../guides/query-cancellation.md) — what the library does
  when it cancels, and what the signal adds.
- [Query functions](../guides/query-functions.md) — what a query function is
  handed and what it may throw.
- [Query keys](../guides/query-keys.md) — why the keys are a hierarchy.
