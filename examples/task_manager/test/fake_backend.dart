/// An in-memory stand-in for `server/server.ts`, wired into dio as
/// an [HttpClientAdapter].
///
/// The tests drive the *real* `TaskApi` — its URLs, its JSON, its error
/// normalisation and its cancellation — against this instead of the express
/// process. Same routes, same scripted failures ("fail" rejects a rename, every
/// second delete fails, a reminder write is confirmed later), so the acceptance
/// suite runs offline and deterministically. Pointing the same app at the real
/// backend is then a smoke test, not a leap of faith.
///
/// "Same" is a claim, and `backend_contract_test.dart` is what checks it: one
/// list of cases run against this and against the express process. It found
/// six places where the two had drifted apart
/// (https://github.com/KoTTi97/flutter_query/issues/54), so every rule below
/// that mirrors one in `server/server.ts` names it. The seed is the one thing
/// the two differ on deliberately — see [tasks].
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// The priorities `server/types.ts` declares. Anything else is 'normal'.
const List<String> _priorities = <String>['low', 'normal', 'high'];

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

  /// The rows a test opens on.
  ///
  /// Three, where `server/db.ts` seeds five, and named differently — the one
  /// place this fake and the server diverge on purpose. These are a fixture:
  /// every row is named for the case that uses it and the list is short enough
  /// that a `find.text` is unambiguous in a test viewport. The server's five
  /// are a shop window. No screen, query or end-to-end spec names a seed row,
  /// so nothing depends on the two agreeing; the contract test asserts what
  /// they do share and records the difference.
  final Map<String, Map<String, Object?>> tasks =
      <String, Map<String, Object?>>{
    '1': _task(
      id: '1',
      name: 'Draft the changelog',
      project: 'Website',
      progress: 40,
      estimate: 1.5,
    ),
    '2': _task(
      id: '2',
      name: 'Book the venue',
      project: 'Errands',
      priority: 'high',
      progress: 40,
      estimate: 1.5,
    ),
    '3': _task(
      id: '3',
      name: 'Renew the domain',
      project: 'Admin',
      priority: 'low',
      progress: 40,
      estimate: 1.5,
      synced: false,
    ),
  };

  /// Every request the app has made, in order — the demo's own request log.
  final List<String> requests = <String>[];

  int _deleteAttempts = 0;
  int _nextId = 4;

  /// The reminder confirmations this backend still owes, so [close] can take
  /// them back.
  final Set<Timer> _confirmations = <Timer>{};

  /// One task, with the fields the server owns at the values `makeTask` in
  /// `server/db.ts` gives them: a new task starts at the bottom of all of
  /// them, and only the seed above overrides any.
  static Map<String, Object?> _task({
    required String id,
    required String name,
    required String project,
    String priority = 'normal',
    int progress = 0,
    double estimate = 1,
    bool synced = true,
  }) =>
      <String, Object?>{
        'id': id,
        'name': name,
        'priority': priority,
        'project': project,
        'progress': progress,
        'estimate': estimate,
        'synced': synced,
        'reminder': false,
        'reminderTarget': null,
        'reminderPending': false,
      };

  /// The name a write may set, or null when the body carries none.
  ///
  /// `requireName` in `server/server.ts`: a missing name, a name that is not a
  /// string and a name that is only whitespace are all 400 — and the name that
  /// survives is the one that was sent, untrimmed.
  static String? _name(Map<String, Object?> body) {
    final name = body['name'];
    return name is String && name.trim().isNotEmpty ? name : null;
  }

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
        // Trimmed, like the server's `String(req.query.search ?? '').trim()`.
        final search = (options.queryParameters['search'] as String? ?? '')
            .trim()
            .toLowerCase();
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
        // The server's `requireTask` says this and only this — an id in the
        // text would be a message no screen could match on.
        return error(404, 'Task not found');
      }
      return answer(detailLatency, () => task);
    }

    if (method == 'POST' && path == '/tasks') {
      final body = _body(options);
      final name = _name(body);
      if (writeLatency > Duration.zero) {
        await Future<void>.delayed(writeLatency);
      }
      if (name == null) {
        return error(400, 'Field "name" is missing or empty');
      }
      return answer(Duration.zero, () {
        final id = '${_nextId++}';
        final priority = body['priority'];
        final created = _task(
          id: id,
          name: name,
          project: body['project'] as String? ?? 'Inbox',
          // A priority the server does not know becomes 'normal' there, so it
          // does here: `PRIORITIES.includes(...)`.
          priority:
              _priorities.contains(priority) ? priority! as String : 'normal',
        );
        tasks[id] = created;
        return created;
      }, status: 201);
    }

    if (method == 'PUT' && path.endsWith('/name')) {
      final id = path.split('/')[2];
      final name = _name(_body(options));
      if (writeLatency > Duration.zero) {
        await Future<void>.delayed(writeLatency);
      }
      // The server checks the task before the body, and refuses a write to an
      // id it does not have rather than breaking on it.
      final task = tasks[id];
      if (task == null) {
        return error(404, 'Task not found');
      }
      if (name == null) {
        return error(400, 'Field "name" is missing or empty');
      }
      if (name.trim().toLowerCase() == 'fail') {
        return error(500, 'The server refused the write');
      }
      // Verbatim, spaces included: the server stores what it was sent and only
      // the *check* above trims.
      task['name'] = name;
      return answer(Duration.zero, () => task);
    }

    if (method == 'PUT' && path.endsWith('/reminder')) {
      final id = path.split('/')[2];
      final value = _body(options)['value'];
      if (writeLatency > Duration.zero) {
        await Future<void>.delayed(writeLatency);
      }
      final task = tasks[id];
      if (task == null) {
        return error(404, 'Task not found');
      }
      // A value that is not a boolean is a 400 on the server, not a crash:
      // `typeof value !== 'boolean'`.
      if (value is! bool) {
        return error(400, 'Field "value" is missing or not a boolean');
      }
      return answer(Duration.zero, () {
        task['reminderPending'] = true;
        task['reminderTarget'] = value;
        // The scheduler's timer belongs to this backend, so [close] can cancel
        // it. An unowned one outlives the test that scheduled it and fires
        // into a torn-down tree — a timer no documented teardown can reach,
        // because it is not the client's.
        late final Timer confirmation;
        confirmation = Timer(confirmAfter, () {
          _confirmations.remove(confirmation);
          task['reminder'] = value;
          task['reminderTarget'] = null;
          task['reminderPending'] = false;
        });
        _confirmations.add(confirmation);
        return task;
      });
    }

    if (method == 'DELETE' && path.startsWith('/tasks/')) {
      final id = path.split('/').last;
      if (writeLatency > Duration.zero) {
        await Future<void>.delayed(writeLatency);
      }
      // `requireTask` runs before the script does, so an id the backend does
      // not have never consumes an attempt — which is what keeps the parity
      // below the deterministic thing the demo relies on.
      if (!tasks.containsKey(id)) {
        return error(404, 'Task not found');
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

    // Deliberately *not* what express answers here (its own HTML 404): no
    // route the app has reaches this, and a sentence naming the method and
    // path is what a typo in a test needs to see. The contract test asserts
    // nothing about it for the same reason.
    return error(404, 'Unknown route $method $path');
  }

  /// Gives back every confirmation still owed.
  ///
  /// dio calls this from `Dio.close()`; a test can call it directly. Either
  /// way nothing this backend scheduled runs afterwards.
  @override
  void close({bool force = false}) {
    for (final confirmation in _confirmations) {
      confirmation.cancel();
    }
    _confirmations.clear();
  }
}
