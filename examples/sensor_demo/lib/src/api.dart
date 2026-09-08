/// The wire contract, typed by hand — the client's copy of the route table in
/// `react-demo/server/server.ts`.
///
/// The key factory is the other half of what tRPC gives the React app: every
/// query key in this app is minted here, so "which keys exist" has one answer
/// and prefix invalidation has stable anchors.
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:tanstack_query_flutter/tanstack_query_flutter.dart';

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
/// `--dart-define=GATEWAY=http://192.168.1.5:5174` for a real device.
String defaultGatewayBaseUrl() {
  const override = String.fromEnvironment('GATEWAY');
  if (override.isNotEmpty) {
    return override;
  }
  if (!kIsWeb && Platform.isAndroid) {
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
  const GatewayException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

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

  Future<T> _run<T>(
    Future<Response<Map<String, Object?>>> Function() request,
    T Function(Map<String, Object?> json) parse,
  ) async {
    try {
      final response = await request();
      return parse(response.data!);
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        // A cancelled request is the library's business, not the user's: let
        // the CancelledError the core raised win.
        rethrow;
      }
      throw GatewayException(
        _messageFrom(error.response?.data) ?? 'Gateway nicht erreichbar',
        statusCode: error.response?.statusCode,
      );
    }
  }
}
