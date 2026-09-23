---
title: Default query function
description: Register a queryFn per key prefix with setQueryDefaults, so options without one derive the request from the key — its types, its mutation twin, and client-wide defaults.
---

# Default query function

When every request follows one pattern — a REST path built from the key, say —
there is no need to write a function per query. Register one for a key
prefix, and every query under that prefix without a `queryFn` of its own uses
it:

```dart snippet="guides/default-query-function.md#defaults"
final client = QueryClient(
  defaultOptions: DefaultOptions(
    queries: QueryDefaults(
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
      retry: const RetryPolicy.times(2),
    ),
  ),
);

client.setQueryDefaults(
  QueryKey(<Object?>['tasks']),
  QueryDefaults(queryFn: (context) => api.listTasks()),
);
```

The function reads the key it is fetching from `context.queryKey`, so one
function can serve a whole family of keys.

## The key is the request

Take it one step further, and let the key *be* the request: its second part
the path, its third the query parameters. One function, registered once when
the app starts, serves every GET of the API:

```dart snippet="guides/default-query-function.md#api-default"
// In main(), once: every key under ['api'] is a GET of the path it names.
// ['api', '/devices', {'room': 'kitchen'}] is GET /devices?room=kitchen.
client.setQueryDefaults(
  QueryKey(<Object?>['api']),
  QueryDefaults(
    queryFn: (context) {
      final parts = context.queryKey.parts;
      return api.getJson(
        parts[1]! as String,
        query: parts.length > 2
            ? parts[2]! as Map<String, Object?>
            : const <String, Object?>{},
        signal: context.signal,
      );
    },
  ),
);
```

The `api` client behind it is whatever the app already uses — with dio, a
thin wrapper:

```dart snippet="prose-only: needs dio, which the docs package does not depend on"
class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Future<Object?> getJson(
    String path, {
    Map<String, Object?> query = const {},
    QueryCancelToken? signal,
  }) async {
    final token = CancelToken();
    signal?.onCancel(token.cancel);
    final response = await _dio.get<Object?>(
      path,
      queryParameters: query,
      cancelToken: token,
    );
    return response.data;
  }
}
```

A query is then nothing but its key — and, because the function hands back
raw JSON, a `select` that parses it:

```dart snippet="guides/default-query-function.md#keyed-queries"
// lib/data/device_queries.dart — no queryFn: the key is the request.
QuerySelectOptions<Object?, List<Device>> apiRoomDevices(String room) =>
    QuerySelectOptions(
      queryKey: QueryKey(<Object?>[
        'api',
        '/devices',
        <String, Object?>{'room': room},
      ]),
      select: parseDevices,
    );

// A top-level function, so a rebuild hands in an equal select and the
// parsed list is kept rather than parsed again.
List<Device> parseDevices(Object? json) => <Device>[
      for (final item in json! as List<Object?>)
        Device.fromJson(item! as Map<String, Object?>),
    ];
```

Because the parameters are part of the key, two rooms are two cache entries,
and invalidating `['api', '/devices']` reaches every room's list.

## Name the types

A default query function is registered for many keys, so its type is erased
to `Object?`. The query that uses it states what it expects, and the client
checks the function's answer against it: an answer that is not the query's
data type fails the fetch with a `QueryDataTypeError`.

- When the default returns a **typed value** — `api.listTasks()` returns a
  `List<Task>` — write the type on the options:
  `QueryObserverOptions<List<Task>>(queryKey: …)`. Without a type argument
  and without a `queryFn` to infer it from, the query's type is `dynamic`;
  see [type safety in Dart](../dart-type-safety.md).
- When the default returns **raw JSON**, as above, the cached type is
  `Object?` and the parsing is a `select`:
  `QuerySelectOptions<Object?, List<Device>>`. The cache holds the JSON,
  every reader gets the typed list, and a top-level `select` function parses
  once per fetch rather than once per build.

## Mutations too

`setMutationDefaults` is the same for mutations: a function registered for a
mutation key prefix, used by every mutation under it without a function of
its own.

```dart snippet="guides/default-query-function.md#mutation-default"
client.setMutationDefaults(
  QueryKey(<Object?>['api', 'add-device']),
  MutationDefaults(
    mutationFn: (body) => api.postJson('/devices', body),
  ),
);
```

```dart snippet="guides/default-query-function.md#keyed-mutation"
MutationOptions<Object?, Map<String, Object?>, void> addDeviceByKey() =>
    MutationOptions.simple(
        mutationKey: QueryKey(<Object?>['api', 'add-device']));
```

The mutation's function is erased the same way, and its answer is checked
against the mutation's data type — `Object?` here. A default mutation
function has no context form, and mutation defaults carry no callbacks:
`onSuccess` and the rest stay on the mutation's own options, or go on the
[mutation cache](global-callbacks.md).

## Two levels of defaults

- `QueryClient(defaultOptions: DefaultOptions(queries: …, mutations: …))`
  applies to every query or mutation of the client.
- `client.setQueryDefaults(key, QueryDefaults(...))` applies to every query
  whose key starts with `key`, and sits above the client-wide default.

An option set on the query itself wins over both. When several registered
prefixes match one key — `['api']` and `['api', '/devices']` — their defaults
merge in the order they were registered, the later one winning field by
field. Registering the same key again replaces its defaults.
`setMutationDefaults` is the matching call for mutations.

The `default-query-function` screen registers such a function for its
`['api', …]` keys and has no `queryFn` anywhere. Its queries each cost one
request; press *Fetch a missing post* and the key's path answers with the
backend's 404, shown as the query's error; *Create a todo* runs a mutation
with only a key, which posts once.

<LiveDemo feature="default-query-function" />

:::note[In React Query]
TanStack Query's example sets `queryFn` in the client's `defaultOptions`; the
same works here, and `setQueryDefaults` narrows it to a key prefix. The type
check has no counterpart there: a TypeScript default function's answer is
trusted as whatever the query declared.
:::
