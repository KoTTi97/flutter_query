/// The wire contract, typed by hand — the client's copy of the route table in
/// `server/server.ts`.
///
/// The key factory below is the other half of it: every query key in this app
/// is minted there, so "which keys exist" has one answer and prefix
/// invalidation has stable anchors.
///
/// **The dio plumbing here is also in the showcase, and that is deliberate.**
/// [defaultBackendBaseUrl], [BackendException], the `BaseOptions`, the
/// cancellation bridge and the error unwrapping are near enough line for line
/// `examples/showcase/lib/shared/api.dart`. An example is read, not depended
/// on, and "how do I wire dio to this?" is the part a reader most wants to
/// lift out whole — putting it in a package both examples import would hide
/// it behind a workspace row and an import. What keeps each copy honest is
/// not a common ancestor but `test/backend_contract_test.dart`: one list of
/// cases, run against this app's fake *and* against its real server
/// (https://github.com/KoTTi97/flutter_query/issues/52).
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'models.dart';

/// Every query key this app uses, in one place.
abstract final class TaskKeys {
  static QueryKey get all => QueryKey(const <Object?>['tasks']);
  static QueryKey get lists => all.append(const <Object?>['list']);
  static QueryKey list(TaskFilters filters) =>
      lists.append(<Object?>[filters.toJson()]);
  static QueryKey get details => all.append(const <Object?>['byId']);
  static QueryKey detail(String id) => details.append(<Object?>[id]);
}

/// Where the backend lives.
///
/// An Android emulator reaches the host machine through `10.0.2.2`, never
/// through `localhost` — that would be the emulator itself. Override with
/// `--dart-define=BACKEND=http://192.168.1.5:5174/api` for a real device.
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
    return 'http://10.0.2.2:5174/api';
  }
  return 'http://localhost:5174/api';
}

/// What the backend said when it refused.
///
/// The backend answers errors with `{ "message": … }`; surfacing that text is
/// the whole reason this class exists, rather than letting dio's generic
/// status-code prose reach the UI.
class BackendException implements Exception {
  const BackendException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The six calls the demo makes.
class TaskApi {
  TaskApi({Dio? dio, String? baseUrl})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl ?? defaultBackendBaseUrl(),
              headers: const <String, String>{'x-demo-client': 'task-manager'},
              // A backend that hangs must fail the query, not leave it
              // fetching forever. The real one answers within a second.
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ));

  final Dio _dio;

  /// Bridges a query's cancellation to dio's.
  ///
  /// This is the interop point the core is designed around
  /// (https://github.com/KoTTi97/flutter_query/issues/11): reading
  /// `context.signal` marks the fetch as cancellable, and `onCancel` hands the
  /// abort to whatever transport is underneath. A `queryFn` that never touches
  /// the token is simply uncancellable, and its result still lands in the cache.
  CancelToken _bridge(QueryCancelToken signal) {
    final token = CancelToken();
    signal.onCancel(token.cancel);
    return token;
  }

  Future<TaskListResponse> listTasks(
    TaskFilters filters, {
    QueryCancelToken? signal,
  }) =>
      _run(
        () => _dio.get<Map<String, Object?>>(
          '/tasks',
          queryParameters: filters.toJson(),
          cancelToken: signal == null ? null : _bridge(signal),
        ),
        TaskListResponse.fromJson,
      );

  Future<Task> getTask(String id, {QueryCancelToken? signal}) => _run(
        () => _dio.get<Map<String, Object?>>(
          '/tasks/$id',
          cancelToken: signal == null ? null : _bridge(signal),
        ),
        Task.fromJson,
      );

  Future<Task> createTask({
    required String name,
    String? project,
    Priority? priority,
  }) =>
      _run(
        () => _dio.post<Map<String, Object?>>(
          '/tasks',
          data: <String, Object?>{
            'name': name,
            if (project != null) 'project': project,
            if (priority != null) 'priority': priority.name,
          },
        ),
        Task.fromJson,
      );

  Future<Task> renameTask(String id, String name) => _run(
        () => _dio.put<Map<String, Object?>>(
          '/tasks/$id/name',
          data: <String, Object?>{'name': name},
        ),
        Task.fromJson,
      );

  Future<Task> setReminder(String id, {required bool value}) => _run(
        () => _dio.put<Map<String, Object?>>(
          '/tasks/$id/reminder',
          data: <String, Object?>{'value': value},
        ),
        Task.fromJson,
      );

  Future<String> deleteTask(String id) => _run(
        () => _dio.delete<Map<String, Object?>>('/tasks/$id'),
        (json) => json['id']! as String,
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
  Future<T> _run<T>(
    Future<Response<Map<String, Object?>>> Function() request,
    T Function(Map<String, Object?> json) parse,
  ) async {
    final Response<Map<String, Object?>> response;
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
      );
    }
    // A response the client cannot read — a missing field, the wrong type —
    // is as much a backend failure as a refused one, and its `TypeError` is
    // no message for a user.
    try {
      return parse(response.data!);
    } on Object {
      throw const BackendException('Unexpected response from the server');
    }
  }

  static String _describe(DioException error) => switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'The server is not responding',
        _ => 'The server is unreachable',
      };
}
