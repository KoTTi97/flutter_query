/// An in-memory stand-in for `react-demo/server/server.ts`, wired into dio as
/// an [HttpClientAdapter].
///
/// The tests drive the *real* `SensorApi` — its URLs, its JSON, its error
/// normalisation and its cancellation — against this instead of the express
/// process. Same routes, same scripted failures ("fail" rejects a rename, every
/// second delete fails, a Matter write is confirmed later), so the acceptance
/// suite runs offline and deterministically. Pointing the same app at the real
/// gateway is then a smoke test, not a leap of faith.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

class FakeGateway implements HttpClientAdapter {
  FakeGateway({
    this.listLatency = Duration.zero,
    this.detailLatency = Duration.zero,
    this.writeLatency = Duration.zero,
    this.confirmAfter = const Duration(milliseconds: 300),
  });

  Duration listLatency;
  Duration detailLatency;
  Duration writeLatency;

  /// How long the "device" takes to apply a Matter write.
  Duration confirmAfter;

  final Map<String, Map<String, Object?>> sensors =
      <String, Map<String, Object?>>{
    '1': _sensor(id: '1', name: 'Fensterkontakt', room: 'Wohnzimmer'),
    '2':
        _sensor(id: '2', name: 'Bewegungsmelder', room: 'Flur', type: 'motion'),
    '3': _sensor(
      id: '3',
      name: 'Thermostat',
      room: 'Küche',
      type: 'temperature',
      connected: false,
    ),
  };

  /// Every request the app has made, in order — the demo's own request log.
  final List<String> requests = <String>[];

  int _deleteAttempts = 0;
  int _nextId = 4;

  /// Requests that are parked until [release] is called, by path.
  final Map<String, Completer<void>> _gates = <String, Completer<void>>{};

  /// Holds the next request to [path] until [release].
  void hold(String path) => _gates[path] = Completer<void>();

  void release(String path) {
    _gates.remove(path)?.complete();
  }

  static Map<String, Object?> _sensor({
    required String id,
    required String name,
    required String room,
    String type = 'contact',
    bool connected = true,
  }) =>
      <String, Object?>{
        'id': id,
        'name': name,
        'type': type,
        'room': room,
        'battery': 87,
        'temperature': 21.5,
        'connected': connected,
        'matterForwarding': false,
        'matterForwardingTarget': null,
        'matterForwardingPending': false,
      };

  /// The request body as a map.
  ///
  /// dio hands an adapter the original Dart object in `options.data` and the
  /// encoded bytes separately, so this reads whichever form arrived rather
  /// than assuming the encoded one.
  static Map<String, Object?> _body(RequestOptions options) {
    final data = options.data;
    if (data is Map) {
      return data.cast<String, Object?>();
    }
    if (data is String) {
      return jsonDecode(data) as Map<String, Object?>;
    }
    return const <String, Object?>{};
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    final method = options.method;
    requests.add('$method $path');

    final gate = _gates[path];
    if (gate != null) {
      await gate.future;
    }

    // `cancelFuture` completes when dio's CancelToken is cancelled, which is
    // what a cancelled query does to the HTTP request.
    var cancelled = false;
    unawaited(cancelFuture?.then((_) => cancelled = true));

    Future<ResponseBody> answer(
      Duration latency,
      Object? Function() body, {
      int status = 200,
    }) async {
      if (latency > Duration.zero) {
        await Future<void>.delayed(latency);
      }
      if (cancelled) {
        throw DioException.requestCancelled(
          requestOptions: options,
          reason: 'cancelled',
        );
      }
      return ResponseBody.fromString(
        jsonEncode(body()),
        status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );
    }

    ResponseBody error(int status, String message) => ResponseBody.fromString(
          jsonEncode(<String, Object?>{'message': message}),
          status,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>[Headers.jsonContentType],
          },
        );

    if (method == 'GET' && path == '/sensors') {
      return answer(listLatency, () {
        final search =
            (options.queryParameters['search'] as String? ?? '').toLowerCase();
        final room = options.queryParameters['room'] as String? ?? 'all';
        final matching = sensors.values.where((sensor) {
          final name = (sensor['name']! as String).toLowerCase();
          return (search.isEmpty || name.contains(search)) &&
              (room == 'all' || sensor['room'] == room);
        }).toList();
        return <String, Object?>{
          'sensors': matching,
          'fetchedAt': DateTime.now().toIso8601String(),
        };
      });
    }

    if (method == 'GET' && path.startsWith('/sensors/')) {
      final id = path.split('/').last;
      final sensor = sensors[id];
      if (sensor == null) {
        return error(404, 'Sensor $id nicht gefunden');
      }
      return answer(detailLatency, () => sensor);
    }

    if (method == 'POST' && path == '/sensors') {
      return answer(writeLatency, () {
        final body = _body(options);
        final id = '${_nextId++}';
        final created = _sensor(
          id: id,
          name: body['name']! as String,
          room: body['room'] as String? ?? 'Flur',
          type: body['type'] as String? ?? 'contact',
        );
        sensors[id] = created;
        return created;
      }, status: 201);
    }

    if (method == 'PUT' && path.endsWith('/name')) {
      final id = path.split('/')[2];
      final body = _body(options);
      final name = (body['name'] as String? ?? '').trim();
      if (writeLatency > Duration.zero) {
        await Future<void>.delayed(writeLatency);
      }
      if (name.toLowerCase() == 'fail') {
        return error(500, 'Gateway hat den Schreibvorgang abgelehnt');
      }
      sensors[id]!['name'] = name;
      return answer(Duration.zero, () => sensors[id]!);
    }

    if (method == 'PUT' && path.endsWith('/matter-forwarding')) {
      final id = path.split('/')[2];
      final body = _body(options);
      final value = body['value']! as bool;
      return answer(writeLatency, () {
        final sensor = sensors[id]!;
        sensor['matterForwardingPending'] = true;
        sensor['matterForwardingTarget'] = value;
        Timer(confirmAfter, () {
          sensor['matterForwarding'] = value;
          sensor['matterForwardingTarget'] = null;
          sensor['matterForwardingPending'] = false;
        });
        return sensor;
      });
    }

    if (method == 'DELETE' && path.startsWith('/sensors/')) {
      final id = path.split('/').last;
      if (writeLatency > Duration.zero) {
        await Future<void>.delayed(writeLatency);
      }
      _deleteAttempts += 1;
      // Every second delete fails, odd attempts first — deterministic, so the
      // demo needs no magic names.
      if (_deleteAttempts.isOdd) {
        return error(
            500, 'Gateway hat das Löschen abgelehnt — nochmal versuchen');
      }
      sensors.remove(id);
      return answer(Duration.zero, () => <String, Object?>{'id': id});
    }

    return error(404, 'Unbekannte Route $method $path');
  }

  @override
  void close({bool force = false}) {}
}
