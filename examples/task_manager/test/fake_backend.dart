/// An in-memory stand-in for `server/server.ts`, wired into dio as
/// an [HttpClientAdapter].
///
/// The tests drive the *real* `TaskApi` — its URLs, its JSON, its error
/// normalisation and its cancellation — against this instead of the express
/// process. Same routes, same scripted failures ("fail" rejects a rename, every
/// second delete fails, a reminder write is confirmed later), so the acceptance
/// suite runs offline and deterministically. Pointing the same app at the real
/// backend is then a smoke test, not a leap of faith.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

class FakeBackend implements HttpClientAdapter {
  FakeBackend({
    this.listLatency = Duration.zero,
    this.detailLatency = Duration.zero,
    this.writeLatency = Duration.zero,
    this.confirmAfter = const Duration(milliseconds: 300),
  });

  Duration listLatency;
  Duration detailLatency;
  Duration writeLatency;

  /// How long the "scheduler" takes to confirm a reminder write.
  Duration confirmAfter;

  final Map<String, Map<String, Object?>> tasks =
      <String, Map<String, Object?>>{
    '1': _task(id: '1', name: 'Draft the changelog', project: 'Website'),
    '2': _task(
      id: '2',
      name: 'Book the venue',
      project: 'Errands',
      priority: 'high',
    ),
    '3': _task(
      id: '3',
      name: 'Renew the domain',
      project: 'Admin',
      priority: 'low',
      synced: false,
    ),
  };

  /// Every request the app has made, in order — the demo's own request log.
  final List<String> requests = <String>[];

  int _deleteAttempts = 0;
  int _nextId = 4;

  static Map<String, Object?> _task({
    required String id,
    required String name,
    required String project,
    String priority = 'normal',
    bool synced = true,
  }) =>
      <String, Object?>{
        'id': id,
        'name': name,
        'priority': priority,
        'project': project,
        'progress': 40,
        'estimate': 1.5,
        'synced': synced,
        'reminder': false,
        'reminderTarget': null,
        'reminderPending': false,
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

    if (method == 'GET' && path == '/tasks') {
      return answer(listLatency, () {
        final search =
            (options.queryParameters['search'] as String? ?? '').toLowerCase();
        final project = options.queryParameters['project'] as String? ?? 'all';
        final matching = tasks.values.where((task) {
          final name = (task['name']! as String).toLowerCase();
          return (search.isEmpty || name.contains(search)) &&
              (project == 'all' || task['project'] == project);
        }).toList();
        return <String, Object?>{
          'tasks': matching,
          'fetchedAt': DateTime.now().toIso8601String(),
        };
      });
    }

    if (method == 'GET' && path.startsWith('/tasks/')) {
      final id = path.split('/').last;
      final task = tasks[id];
      if (task == null) {
        return error(404, 'Task $id not found');
      }
      return answer(detailLatency, () => task);
    }

    if (method == 'POST' && path == '/tasks') {
      return answer(writeLatency, () {
        final body = _body(options);
        final id = '${_nextId++}';
        final created = _task(
          id: id,
          name: body['name']! as String,
          project: body['project'] as String? ?? 'Inbox',
          priority: body['priority'] as String? ?? 'normal',
        );
        tasks[id] = created;
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
        return error(500, 'The server refused the write');
      }
      tasks[id]!['name'] = name;
      return answer(Duration.zero, () => tasks[id]!);
    }

    if (method == 'PUT' && path.endsWith('/reminder')) {
      final id = path.split('/')[2];
      final body = _body(options);
      final value = body['value']! as bool;
      return answer(writeLatency, () {
        final task = tasks[id]!;
        task['reminderPending'] = true;
        task['reminderTarget'] = value;
        Timer(confirmAfter, () {
          task['reminder'] = value;
          task['reminderTarget'] = null;
          task['reminderPending'] = false;
        });
        return task;
      });
    }

    if (method == 'DELETE' && path.startsWith('/tasks/')) {
      final id = path.split('/').last;
      if (writeLatency > Duration.zero) {
        await Future<void>.delayed(writeLatency);
      }
      _deleteAttempts += 1;
      // Every second delete fails, odd attempts first — deterministic, so the
      // demo needs no magic names.
      if (_deleteAttempts.isOdd) {
        return error(500, 'The server refused the delete — try again');
      }
      tasks.remove(id);
      return answer(Duration.zero, () => <String, Object?>{'id': id});
    }

    return error(404, 'Unknown route $method $path');
  }

  @override
  void close({bool force = false}) {}
}
