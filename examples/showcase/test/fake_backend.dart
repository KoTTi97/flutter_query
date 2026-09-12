/// An in-memory stand-in for `server/server.ts`, wired into dio as an
/// [HttpClientAdapter].
///
/// The widget tests drive the *real* `ShowcaseApi` — its URLs, its JSON, its
/// error normalisation and its cancellation — against this instead of the
/// express process. Same routes in the same order, same seed data (it loads
/// `server/seed.json`), same fault chain (latency, `?delay`, `?fail`,
/// scripted `failNext`, `errorRate`) and the same control routes, so a
/// feature's widget tests run offline and deterministically. That the fake
/// really mirrors the server is what `backend_contract_test.dart` proves.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart';

/// One answered request, what the server's `GET /__scenario/:id/requests`
/// lists.
class LogEntry {
  const LogEntry(this.method, this.path, this.query, this.status);

  final String method;

  /// The full path, `/api/todos/1`, as the server logs it.
  final String path;
  final Map<String, String> query;
  final int status;

  Map<String, Object?> toJson() => <String, Object?>{
        'method': method,
        'path': path,
        'query': query,
        'at': clock.now().toUtc().toIso8601String(),
        'status': status,
      };

  @override
  String toString() => '$method $path → $status';
}

class _FailNext {
  _FailNext(this.method, this.path, this.count, this.status, this.message);

  final String method;
  final String path;
  int count;
  final int status;
  final String? message;

  bool matches(String method, String path) =>
      count > 0 &&
      this.method == method &&
      (this.path.endsWith('*')
          ? path.startsWith(this.path.substring(0, this.path.length - 1))
          : this.path == path);
}

typedef _Handler = FutureOr<_Reply> Function(
  Match match,
  RequestOptions options,
);

class _Reply {
  const _Reply(this.status, this.body);

  final int status;
  final Object? body;
}

class _Route {
  const _Route(this.method, this.pattern, this.handler, {this.control = false});

  final String method;
  final RegExp pattern;
  final _Handler handler;

  /// One of the scenario's own controls, which the server registers *before*
  /// its fault middleware: never delayed, failed or logged.
  final bool control;
}

class _HttpError implements Exception {
  const _HttpError(this.status, this.message);

  final int status;
  final String message;
}

class FakeBackend implements HttpClientAdapter {
  FakeBackend({this.latency = Duration.zero}) : _defaultLatency = latency {
    reset();
  }

  /// Applied to every request first, like the scenario's `latency`.
  Duration latency;

  /// What [reset] puts [latency] back to — this fake's `DEFAULT_LATENCY`,
  /// which is zero unless a caller asked for otherwise. The server restores
  /// its own default the same way, which is why the two differ after a reset
  /// and why every contract case sets the latency it wants.
  final Duration _defaultLatency;

  /// The share of requests that fail at random, like the scenario's.
  double errorRate = 0;

  /// The requests answered so far, like the server's log.
  final List<LogEntry> log = <LogEntry>[];

  late List<Map<String, Object?>> posts;
  late List<Map<String, Object?>> comments;
  late List<Map<String, Object?>> todos;
  List<Map<String, Object?>> ticks = <Map<String, Object?>>[];
  int counter = 0;
  int serial = 0;
  int projectCount = 0;

  final List<_FailNext> _failNext = <_FailNext>[];
  int _nextTodoId = 1;
  int _nextTickId = 1;
  Random _random = Random(1);
  final Set<Timer> _timers = <Timer>{};

  static Map<String, Object?>? _seed;

  /// `server/seed.json`, found from the package root or the repo root.
  static Map<String, Object?> seed() => _seed ??= () {
        for (final candidate in <String>[
          'server/seed.json',
          'examples/showcase/server/seed.json',
        ]) {
          final file = File(candidate);
          if (file.existsSync()) {
            return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
          }
        }
        throw StateError(
            'server/seed.json not found from ${Directory.current}');
      }();

  static List<Map<String, Object?>> _rows(String name) =>
      (seed()[name]! as List<Object?>)
          .map((row) => Map<String, Object?>.of(row! as Map<String, Object?>))
          .toList();

  /// Back to the seed, like `POST /__scenario/:id/reset`.
  void reset() {
    posts = _rows('posts');
    comments = _rows('comments');
    todos = _rows('todos');
    ticks = <Map<String, Object?>>[];
    counter = 0;
    serial = 0;
    projectCount = seed()['projectCount']! as int;
    latency = _defaultLatency;
    errorRate = 0;
    _failNext.clear();
    log.clear();
    _random = Random(1);
    _nextTodoId = todos.fold<int>(
            0,
            (max, todo) =>
                max > (todo['id']! as int) ? max : todo['id']! as int) +
        1;
    _nextTickId = 1;
  }

  /// Scripts the next [count] requests matching [method] and [path] (exact,
  /// or a prefix when it ends in `*`) to answer [status].
  void failNext(
    String method,
    String path, {
    int count = 1,
    int status = 500,
    String? message,
  }) {
    _failNext
        .add(_FailNext(method.toUpperCase(), path, count, status, message));
  }

  /// How many logged requests match.
  int count(String method, Pattern path) => log
      .where((entry) =>
          entry.method == method &&
          (path is RegExp ? path.hasMatch(entry.path) : entry.path == path))
      .length;

  Map<String, Object?> _config() => <String, Object?>{
        'latency': latency.inMilliseconds,
        'errorRate': errorRate,
        'failNext': <Object?>[
          for (final entry in _failNext)
            <String, Object?>{
              'method': entry.method,
              'path': entry.path,
              'count': entry.count,
              'status': entry.status,
              if (entry.message != null) 'message': entry.message,
            },
        ],
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
    if (data is String && data.isNotEmpty) {
      return jsonDecode(data) as Map<String, Object?>;
    }
    return const <String, Object?>{};
  }

  Map<String, Object?> _project(int id) => <String, Object?>{
        'id': id,
        'name': 'Project $id',
        'fetchedAt': clock.now().toUtc().toIso8601String(),
      };

  Map<String, Object?> _requirePost(String id) =>
      posts.where((post) => post['id'] == int.tryParse(id)).firstOrNull ??
      (throw const _HttpError(404, 'Post not found'));

  Map<String, Object?> _requireTodo(String id) =>
      todos.where((todo) => todo['id'] == int.tryParse(id)).firstOrNull ??
      (throw const _HttpError(404, 'Todo not found'));

  static String _requireText(Map<String, Object?> body) {
    final text = body['text'];
    if (text is! String || text.trim().isEmpty) {
      throw const _HttpError(400, 'Field "text" is missing or empty');
    }
    return text.trim();
  }

  static int _intParam(RequestOptions options, String name, int fallback) =>
      int.tryParse('${options.queryParameters[name] ?? ''}') ?? fallback;

  // The route table, in `server.ts` order. Control routes first, then the
  // resources; the fault chain in [fetch] skips the control routes.
  late final List<_Route> _routes = <_Route>[
    _Route('POST', RegExp(r'^/__scenario/([^/]+)/reset$'), (match, _) {
      reset();
      // The id the caller named, as `req.params.id` is on the server — not a
      // constant, or a client that reads it back learns nothing.
      return _Reply(200, <String, Object?>{'id': match[1]});
    }, control: true),
    _Route('POST', RegExp(r'^/__scenario/([^/]+)/config$'), (_, options) {
      final body = _body(options);
      // Each knob is validated exactly as the server validates it: a config
      // the server refuses with a 400 must not be one the fake quietly
      // applies, or a test that mis-sets a knob passes offline and fails in
      // the `e2e` leg.
      if (body.containsKey('latency')) {
        final ms = body['latency'];
        if (ms is! num || ms < 0) {
          throw const _HttpError(400, 'latency: milliseconds ≥ 0');
        }
        latency = Duration(milliseconds: ms.round());
      }
      if (body.containsKey('errorRate')) {
        final rate = body['errorRate'];
        if (rate is! num || rate < 0 || rate > 1) {
          throw const _HttpError(400, 'errorRate: a number between 0 and 1');
        }
        errorRate = rate.toDouble();
      }
      if (body.containsKey('failNext')) {
        final entries = body['failNext'];
        // No `ShowcaseApi` method can send a malformed entry — `FailNext` is
        // a typed record — so no contract case reaches this branch; it is
        // here because the alternative is a raw `TypeError` out of the
        // adapter where the server answers a sentence.
        if (entries is! List<Object?> ||
            entries.any((entry) =>
                entry is! Map<String, Object?> ||
                entry['method'] is! String ||
                entry['path'] is! String ||
                entry['count'] is! int ||
                entry['status'] is! int)) {
          throw const _HttpError(400,
              'failNext: a list of { method, path, count, status, message? }');
        }
        _failNext.clear();
        for (final entry in entries.cast<Map<String, Object?>>()) {
          failNext(
            entry['method']! as String,
            entry['path']! as String,
            count: entry['count']! as int,
            status: entry['status']! as int,
            message: entry['message'] as String?,
          );
        }
      }
      return _Reply(200, _config());
    }, control: true),
    _Route('GET', RegExp(r'^/__scenario/([^/]+)/requests$'), (_, __) {
      return _Reply(200, log.map((entry) => entry.toJson()).toList());
    }, control: true),
    _Route('DELETE', RegExp(r'^/__scenario/([^/]+)/requests$'), (_, __) {
      final cleared = log.length;
      log.clear();
      return _Reply(200, <String, Object?>{'cleared': cleared});
    }, control: true),
    _Route('GET', RegExp(r'^/posts$'), (_, __) => _Reply(200, posts)),
    _Route('GET', RegExp(r'^/posts/([^/]+)$'),
        (match, _) => _Reply(200, _requirePost(match[1]!))),
    _Route('GET', RegExp(r'^/posts/([^/]+)/comments$'), (match, _) {
      final post = _requirePost(match[1]!);
      return _Reply(
        200,
        comments.where((comment) => comment['postId'] == post['id']).toList(),
      );
    }),
    _Route('GET', RegExp(r'^/search$'), (_, options) {
      final needle =
          '${options.queryParameters['q'] ?? ''}'.trim().toLowerCase();
      return _Reply(
        200,
        needle.isEmpty
            ? const <Object?>[]
            : posts
                .where((post) =>
                    (post['title']! as String).toLowerCase().contains(needle))
                .toList(),
      );
    }),
    _Route('GET', RegExp(r'^/todos$'), (_, __) => _Reply(200, todos)),
    _Route('POST', RegExp(r'^/todos$'), (_, options) {
      final todo = <String, Object?>{
        'id': _nextTodoId++,
        'text': _requireText(_body(options)),
        'done': false,
      };
      todos.add(todo);
      return _Reply(201, todo);
    }),
    _Route('PATCH', RegExp(r'^/todos/([^/]+)$'), (match, options) {
      final todo = _requireTodo(match[1]!);
      final body = _body(options);
      if (body.containsKey('text')) {
        todo['text'] = _requireText(body);
      }
      if (body.containsKey('done')) {
        if (body['done'] is! bool) {
          throw const _HttpError(400, 'Field "done" is not a boolean');
        }
        todo['done'] = body['done'];
      }
      return _Reply(200, todo);
    }),
    _Route('DELETE', RegExp(r'^/todos/([^/]+)$'), (match, _) {
      final todo = _requireTodo(match[1]!);
      todos.remove(todo);
      return _Reply(200, <String, Object?>{'id': todo['id']});
    }),
    _Route('GET', RegExp(r'^/projects$'), (_, options) {
      final count = projectCount;
      if (options.queryParameters.containsKey('cursor')) {
        final cursor = max(0, _intParam(options, 'cursor', 0));
        final limit = max(1, _intParam(options, 'limit', 10));
        final ids = List<int>.generate(
            max(0, min(limit, count - cursor)), (i) => cursor + i);
        return _Reply(200, <String, Object?>{
          'items': ids.map(_project).toList(),
          'nextId': cursor + limit < count ? cursor + limit : null,
          'previousId': cursor > 0 ? max(0, cursor - limit) : null,
        });
      }
      final page = max(0, _intParam(options, 'page', 0));
      final size = max(1, _intParam(options, 'size', 10));
      final start = page * size;
      final ids = List<int>.generate(
          max(0, min(size, count - start)), (i) => start + i);
      return _Reply(200, <String, Object?>{
        'projects': ids.map(_project).toList(),
        'page': page,
        'hasMore': start + size < count,
      });
    }),
    _Route('GET', RegExp(r'^/ticks$'), (_, __) => _Reply(200, ticks)),
    _Route('POST', RegExp(r'^/ticks$'), (_, __) {
      final tick = <String, Object?>{
        'id': _nextTickId++,
        'at': clock.now().toUtc().toIso8601String(),
      };
      ticks.add(tick);
      return _Reply(201, tick);
    }),
    _Route('DELETE', RegExp(r'^/ticks$'), (_, __) {
      final cleared = ticks.length;
      ticks = <Map<String, Object?>>[];
      return _Reply(200, <String, Object?>{'cleared': cleared});
    }),
    _Route('GET', RegExp(r'^/time$'), (_, __) {
      serial += 1;
      return _Reply(200, <String, Object?>{
        'now': clock.now().toUtc().toIso8601String(),
        'serial': serial,
      });
    }),
    _Route('GET', RegExp(r'^/counter$'),
        (_, __) => _Reply(200, <String, Object?>{'value': counter})),
    _Route('POST', RegExp(r'^/counter/increment$'), (_, options) {
      final by = _body(options)['by'];
      counter += by is int ? by : 1;
      return _Reply(200, <String, Object?>{'value': counter});
    }),
  ];

  /// Waits [duration] on a timer this fake owns, so [close] can cancel it and
  /// no test ends with a pending timer.
  Future<bool> _wait(Duration duration) {
    if (duration <= Duration.zero) {
      return Future<bool>.value(true);
    }
    final completer = Completer<bool>();
    late final Timer timer;
    timer = Timer(duration, () {
      _timers.remove(timer);
      completer.complete(true);
    });
    _timers.add(timer);
    return completer.future;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    final method = options.method.toUpperCase();
    final fullPath = '/api$path';
    final query = <String, String>{
      for (final entry in options.queryParameters.entries)
        entry.key: '${entry.value}',
    };

    // `cancelFuture` completes when dio's CancelToken is cancelled, which is
    // what a cancelled query does to the HTTP request.
    var cancelled = false;
    unawaited(cancelFuture?.then((_) => cancelled = true));

    final route = _routes
        .where((candidate) =>
            candidate.method == method && candidate.pattern.hasMatch(path))
        .firstOrNull;
    // What skips the log and the fault chain is *being* one of the four
    // control routes, not merely being spelled like one: the server
    // registers those four ahead of its fault middleware, and anything else
    // under `/api` — an unknown `/__scenario/…` path included — goes through
    // the middleware and is logged by it.
    final control = route?.control ?? false;

    ResponseBody reply(int status, Object? body) {
      if (!control) {
        log.add(LogEntry(method, fullPath, query, status));
      }
      return ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );
    }

    ResponseBody error(int status, String message) =>
        reply(status, <String, Object?>{'message': message});

    if (!control) {
      final delay = int.tryParse(query['delay'] ?? '') ?? 0;
      final wait = latency + Duration(milliseconds: max(0, delay));
      await _wait(wait);
      if (cancelled) {
        throw DioException.requestCancelled(
          requestOptions: options,
          reason: 'cancelled',
        );
      }
      if (query.containsKey('fail')) {
        final status = int.tryParse(query['fail']!) ?? 500;
        return error(
            status >= 400 ? status : 500, 'Requested: ${query['fail']}');
      }
      final scripted = _failNext
          .where((entry) => entry.matches(method, fullPath))
          .firstOrNull;
      if (scripted != null) {
        scripted.count -= 1;
        return error(scripted.status,
            scripted.message ?? 'Scripted failure ${scripted.status}');
      }
      if (errorRate > 0 && _random.nextDouble() < errorRate) {
        return error(500, 'Failed at random (errorRate)');
      }
    }

    // After the fault chain, as on the server: the unknown-route handler is
    // registered behind the middleware, so a scripted failure or an
    // `errorRate` answers a path that does not exist before its 404 does.
    if (route == null) {
      return error(404, 'Unknown route $method $fullPath');
    }

    try {
      final result =
          await route.handler(route.pattern.firstMatch(path)!, options);
      return reply(result.status, result.body);
    } on _HttpError catch (failure) {
      return error(failure.status, failure.message);
    }
  }

  @override
  void close({bool force = false}) {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }
}
