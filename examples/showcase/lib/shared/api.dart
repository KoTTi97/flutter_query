/// The wire contract, typed by hand — the client's copy of the route table in
/// `server/server.ts`.
///
/// Every request carries the scenario id in `x-scenario`, so the backend keeps
/// a world of this app's own; the end-to-end suite mints one per test.
///
/// **The dio plumbing here is also in the task manager, and that is
/// deliberate.** [defaultBackendBaseUrl], [BackendException], the
/// `BaseOptions`, the cancellation bridge and the error unwrapping are near
/// enough line for line `examples/task_manager/lib/src/api.dart`. An example
/// is read, not depended on, and "how do I wire dio to this?" is the part a
/// reader most wants to lift out whole — putting it in a package both
/// examples import would hide it behind a workspace row and an import. What
/// keeps each copy honest is not a common ancestor but
/// `test/backend_contract_test.dart`: one list of cases, run against this
/// app's fake *and* against its real server
/// (https://github.com/KoTTi97/flutter_query/issues/52).
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'models.dart';

/// The query keys shared by more than one screen. A screen that owns a key
/// defines it next to its options instead.
abstract final class ShowcaseKeys {
  static QueryKey get posts => QueryKey(const <Object?>['posts']);
  static QueryKey post(int id) => posts.append(<Object?>[id]);
  static QueryKey comments(int postId) =>
      post(postId).append(const <Object?>['comments']);
  static QueryKey get todos => QueryKey(const <Object?>['todos']);
  static QueryKey get time => QueryKey(const <Object?>['time']);
}

/// Where the backend lives.
///
/// An Android emulator reaches the host machine through `10.0.2.2`, never
/// through `localhost` — that would be the emulator itself. Override with
/// `--dart-define=BACKEND=http://192.168.1.5:5175/api` for a real device.
///
/// The platform check goes through [defaultTargetPlatform] rather than
/// `Platform.isAndroid`, because importing `dart:io` at all would stop this
/// app compiling for the web.
String defaultBackendBaseUrl() {
  const override = String.fromEnvironment('BACKEND');
  if (override.isNotEmpty) {
    return override;
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:5175/api';
  }
  return 'http://localhost:5175/api';
}

/// Which scenario this run of the app lives in.
///
/// On the web the end-to-end suite passes it as `?scenario=<id>` in the URL —
/// before the `#/route`, so it survives every navigation. Elsewhere
/// `--dart-define=SCENARIO=<id>` does the same; without either, the backend's
/// `default` world.
String scenarioFromEnvironment() =>
    Uri.base.queryParameters['scenario'] ??
    const String.fromEnvironment('SCENARIO', defaultValue: 'default');

/// What the backend said when it refused.
///
/// The backend answers errors with `{ "message": … }`; surfacing that text is
/// the whole reason this class exists, rather than letting dio's generic
/// status-code prose reach the UI.
class BackendException implements Exception {
  const BackendException(this.message, {this.status});

  final String message;

  /// The HTTP status, or null when no response arrived at all.
  final int? status;

  @override
  String toString() => message;
}

/// The calls the screens make.
///
/// Reads take the query's cancellation token; a few calls take the backend's
/// per-request fault knobs (`delay`, `fail`) so a screen can ask for a slow or
/// refused answer on purpose.
class ShowcaseApi {
  ShowcaseApi({Dio? dio, String? baseUrl, this.scenario = 'default'})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl ?? defaultBackendBaseUrl(),
              // A backend that hangs must fail the query, not leave it
              // fetching forever.
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            )) {
    _dio.options.headers['x-scenario'] = scenario;
  }

  final Dio _dio;

  /// The scenario every request of this api is tagged with.
  final String scenario;

  /// Bridges a query's cancellation to dio's.
  ///
  /// This is the interop point the core is designed around
  /// (https://github.com/KoTTi97/flutter_query/issues/11): reading
  /// `context.signal` marks the fetch as cancellable, and `onCancel` hands the
  /// abort to whatever transport is underneath. A `queryFn` that never touches
  /// the token is simply uncancellable, and its result still lands in the cache.
  static CancelToken? bridge(QueryCancelToken? signal) {
    if (signal == null) {
      return null;
    }
    final token = CancelToken();
    signal.onCancel(token.cancel);
    return token;
  }

  static Map<String, Object?> _knobs({Duration? delay, int? fail}) =>
      <String, Object?>{
        if (delay != null && delay > Duration.zero)
          'delay': delay.inMilliseconds,
        if (fail != null) 'fail': fail,
      };

  // --- posts -------------------------------------------------------------

  Future<List<Post>> posts({
    QueryCancelToken? signal,
    Duration? delay,
    int? fail,
  }) =>
      _list(
        '/posts',
        Post.fromJson,
        signal: signal,
        query: _knobs(delay: delay, fail: fail),
      );

  Future<Post> post(
    int id, {
    QueryCancelToken? signal,
    Duration? delay,
    int? fail,
  }) =>
      _one('/posts/$id', Post.fromJson,
          signal: signal, query: _knobs(delay: delay, fail: fail));

  Future<List<Comment>> comments(int postId, {QueryCancelToken? signal}) =>
      _list('/posts/$postId/comments', Comment.fromJson, signal: signal);

  Future<List<Post>> search(
    String needle, {
    QueryCancelToken? signal,
    Duration? delay,
  }) =>
      _list(
        '/search',
        Post.fromJson,
        signal: signal,
        query: <String, Object?>{'q': needle, ..._knobs(delay: delay)},
      );

  // --- todos -------------------------------------------------------------

  Future<List<Todo>> todos({QueryCancelToken? signal, Duration? delay}) =>
      _list('/todos', Todo.fromJson,
          signal: signal, query: _knobs(delay: delay));

  Future<Todo> createTodo(String text, {Duration? delay, int? fail}) => _run(
        () => _dio.post<Map<String, Object?>>(
          '/todos',
          data: <String, Object?>{'text': text},
          queryParameters: _knobs(delay: delay, fail: fail),
        ),
        Todo.fromJson,
      );

  Future<Todo> updateTodo(
    int id, {
    String? text,
    bool? done,
    Duration? delay,
    int? fail,
  }) =>
      _run(
        () => _dio.patch<Map<String, Object?>>(
          '/todos/$id',
          data: <String, Object?>{
            if (text != null) 'text': text,
            if (done != null) 'done': done,
          },
          queryParameters: _knobs(delay: delay, fail: fail),
        ),
        Todo.fromJson,
      );

  Future<int> deleteTodo(int id, {Duration? delay, int? fail}) => _run(
        () => _dio.delete<Map<String, Object?>>(
          '/todos/$id',
          queryParameters: _knobs(delay: delay, fail: fail),
        ),
        (json) => json['id']! as int,
      );

  // --- projects ----------------------------------------------------------

  Future<ProjectPage> projectsPage(
    int page, {
    int size = 10,
    QueryCancelToken? signal,
  }) =>
      _one(
        '/projects',
        ProjectPage.fromJson,
        signal: signal,
        query: <String, Object?>{'page': page, 'size': size},
      );

  Future<ProjectSlice> projectsFrom(
    int cursor, {
    int limit = 10,
    QueryCancelToken? signal,
  }) =>
      _one(
        '/projects',
        ProjectSlice.fromJson,
        signal: signal,
        query: <String, Object?>{'cursor': cursor, 'limit': limit},
      );

  // --- ticks, time, counter ---------------------------------------------

  Future<List<Tick>> ticks({QueryCancelToken? signal}) =>
      _list('/ticks', Tick.fromJson, signal: signal);

  Future<Tick> addTick() =>
      _run(() => _dio.post<Map<String, Object?>>('/ticks'), Tick.fromJson);

  Future<int> clearTicks() => _run(
        () => _dio.delete<Map<String, Object?>>('/ticks'),
        (json) => json['cleared']! as int,
      );

  Future<ServerTime> time({
    QueryCancelToken? signal,
    Duration? delay,
    int? fail,
  }) =>
      _one('/time', ServerTime.fromJson,
          signal: signal, query: _knobs(delay: delay, fail: fail));

  Future<int> counter({QueryCancelToken? signal}) => _one(
        '/counter',
        (json) => json['value']! as int,
        signal: signal,
      );

  Future<int> increment({int by = 1, Duration? delay, int? fail}) => _run(
        () => _dio.post<Map<String, Object?>>(
          '/counter/increment',
          data: <String, Object?>{'by': by},
          queryParameters: _knobs(delay: delay, fail: fail),
        ),
        (json) => json['value']! as int,
      );

  // --- untyped, for the default-query-function screen --------------------

  /// A raw GET, for a query function that derives the path from its key.
  Future<Object?> getJson(String path, {QueryCancelToken? signal}) => _run(
        () => _dio.get<Object?>(path, cancelToken: bridge(signal)),
        (data) => data,
      );

  // --- the scenario's own controls ---------------------------------------

  /// Reseeds this api's scenario on the backend.
  Future<void> resetScenario() => _run(
        () => _dio.post<Map<String, Object?>>('/__scenario/$scenario/reset'),
        (_) {},
      );

  /// Changes this api's scenario on the backend: the latency every request
  /// starts with, the share of requests that fail at random, and scripted
  /// failures for the next matching requests.
  Future<void> configureScenario({
    Duration? latency,
    double? errorRate,
    List<FailNext>? failNext,
  }) =>
      _run(
        () => _dio.post<Map<String, Object?>>(
          '/__scenario/$scenario/config',
          data: <String, Object?>{
            if (latency != null) 'latency': latency.inMilliseconds,
            if (errorRate != null) 'errorRate': errorRate,
            if (failNext != null)
              'failNext': failNext.map((entry) => entry.toJson()).toList(),
          },
        ),
        (_) {},
      );

  /// This api's scenario's request log — every request the backend answered,
  /// as `{method, path, query, at, status}`.
  Future<List<Map<String, Object?>>> scenarioRequests() => _run(
        () => _dio.get<List<Object?>>('/__scenario/$scenario/requests'),
        (items) => items.cast<Map<String, Object?>>(),
      );

  // --- plumbing ----------------------------------------------------------

  Future<T> _one<T>(
    String path,
    T Function(Map<String, Object?> json) parse, {
    QueryCancelToken? signal,
    Map<String, Object?> query = const <String, Object?>{},
  }) =>
      _run(
        () => _dio.get<Map<String, Object?>>(
          path,
          queryParameters: query,
          cancelToken: bridge(signal),
        ),
        parse,
      );

  Future<List<T>> _list<T>(
    String path,
    T Function(Map<String, Object?> json) parse, {
    QueryCancelToken? signal,
    Map<String, Object?> query = const <String, Object?>{},
  }) =>
      _run(
        () => _dio.get<List<Object?>>(
          path,
          queryParameters: query,
          cancelToken: bridge(signal),
        ),
        (items) =>
            items.map((item) => parse(item! as Map<String, Object?>)).toList(),
      );

  /// The backend answers errors with `{ "message": … }`. Depending on the
  /// response's content type dio hands that back parsed or as raw text, so both
  /// are read here rather than only the convenient one.
  static String? _messageFrom(Object? data) {
    final decoded = data is String ? _tryDecode(data) : data;
    if (decoded is Map && decoded['message'] is String) {
      return decoded['message'] as String;
    }
    return null;
  }

  static Object? _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  /// Every failure leaves here as a [BackendException] with a sentence a user
  /// can read; nothing raw reaches the screens.
  Future<T> _run<R, T>(
    Future<Response<R>> Function() request,
    T Function(R data) parse,
  ) async {
    final Response<R> response;
    try {
      response = await request();
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        // A cancelled request is the library's business, not the user's: let
        // the CancelledError the core raised win.
        rethrow;
      }
      throw BackendException(
        _messageFrom(error.response?.data) ?? _describe(error),
        status: error.response?.statusCode,
      );
    }
    // A response the client cannot read — a missing field, the wrong type —
    // is as much a backend failure as a refused one, and its `TypeError` is
    // no message for a user.
    try {
      return parse(response.data as R);
    } on Object {
      throw const BackendException('Unexpected response from the backend');
    }
  }

  static String _describe(DioException error) => switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'The backend is not responding',
        _ => 'The backend is unreachable',
      };
}
