/// The wire contract, typed by hand — the client's copy of the route table in
/// `react-demo/server/server.ts`.
///
/// The key factory is the other half of what tRPC gives the React app: every
/// query key in this app is minted here, so "which keys exist" has one answer
/// and prefix invalidation has stable anchors.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'models.dart';

/// Query keys, mirroring the React demo's `sensorKeys`.
abstract final class SensorKeys {
  static QueryKey get all => QueryKey(const <Object?>['sensors']);
  static QueryKey get lists => all.append(const <Object?>['list']);
  static QueryKey list(SensorFilters filters) =>
      lists.append(<Object?>[filters.toJson()]);
  static QueryKey get details => all.append(const <Object?>['byId']);
  static QueryKey detail(String id) => details.append(<Object?>[id]);
}

/// Where the gateway lives.
///
/// An Android emulator reaches the host machine through `10.0.2.2`, never
/// through `localhost` — that would be the emulator itself. Override with
/// `--dart-define=GATEWAY=http://192.168.1.5:5174/api` for a real device.
///
/// The platform check goes through [defaultTargetPlatform] rather than
/// `Platform.isAndroid`, because importing `dart:io` at all would stop this
/// app compiling for the web.
String defaultGatewayBaseUrl() {
  const override = String.fromEnvironment('GATEWAY');
  if (override.isNotEmpty) {
    return override;
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:5174/api';
  }
  return 'http://localhost:5174/api';
}

/// What the gateway said when it refused.
///
/// The gateway answers errors with `{ "message": … }`; surfacing that text is
/// the whole reason this class exists, rather than letting dio's generic
/// status-code prose reach the UI.
class GatewayException implements Exception {
  const GatewayException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The six calls the demo makes.
class SensorApi {
  SensorApi({Dio? dio, String? baseUrl})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl ?? defaultGatewayBaseUrl(),
              headers: const <String, String>{'x-demo-client': 'tq-demo'},
              // A gateway that hangs must fail the query, not leave it
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

  Future<SensorListResponse> listSensors(
    SensorFilters filters, {
    QueryCancelToken? signal,
  }) =>
      _run(
        () => _dio.get<Map<String, Object?>>(
          '/sensors',
          queryParameters: filters.toJson(),
          cancelToken: signal == null ? null : _bridge(signal),
        ),
        SensorListResponse.fromJson,
      );

  Future<Sensor> getSensor(String id, {QueryCancelToken? signal}) => _run(
        () => _dio.get<Map<String, Object?>>(
          '/sensors/$id',
          cancelToken: signal == null ? null : _bridge(signal),
        ),
        Sensor.fromJson,
      );

  Future<Sensor> createSensor({
    required String name,
    String? room,
    SensorType? type,
  }) =>
      _run(
        () => _dio.post<Map<String, Object?>>(
          '/sensors',
          data: <String, Object?>{
            'name': name,
            if (room != null) 'room': room,
            if (type != null) 'type': type.name,
          },
        ),
        Sensor.fromJson,
      );

  Future<Sensor> renameSensor(String id, String name) => _run(
        () => _dio.put<Map<String, Object?>>(
          '/sensors/$id/name',
          data: <String, Object?>{'name': name},
        ),
        Sensor.fromJson,
      );

  Future<Sensor> setMatterForwarding(String id, {required bool value}) => _run(
        () => _dio.put<Map<String, Object?>>(
          '/sensors/$id/matter-forwarding',
          data: <String, Object?>{'value': value},
        ),
        Sensor.fromJson,
      );

  Future<String> deleteSensor(String id) => _run(
        () => _dio.delete<Map<String, Object?>>('/sensors/$id'),
        (json) => json['id']! as String,
      );

  /// The gateway answers errors with `{ "message": … }`. Depending on the
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

  /// Every failure leaves here as a [GatewayException] with a sentence a user
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
      throw GatewayException(
        _messageFrom(error.response?.data) ?? _describe(error),
      );
    }
    // A response the client cannot read — a missing field, the wrong type —
    // is as much a gateway failure as a refused one, and its `TypeError` is
    // no message for a user.
    try {
      return parse(response.data!);
    } on Object {
      throw const GatewayException('Unerwartete Antwort vom Gateway');
    }
  }

  static String _describe(DioException error) => switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'Gateway antwortet nicht',
        _ => 'Gateway nicht erreichbar',
      };
}
