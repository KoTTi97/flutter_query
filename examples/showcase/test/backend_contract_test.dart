/// The backend's contract, run against the fake — and, when `SHOWCASE_SERVER`
/// names a running server (`http://localhost:5175/api`), against that too.
///
/// One list of cases, two targets: that is what makes the fake trustworthy.
/// A widget test that passes against the fake means nothing if the fake and
/// the server drifted apart; this file is where a drift shows.
library;

import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showcase/shared/api.dart';
import 'package:showcase/shared/models.dart';

import 'fake_backend.dart';

void main() {
  final seed = FakeBackend.seed();
  final firstPost =
      (seed['posts']! as List<Object?>).first as Map<String, Object?>;

  // Runs every case against [make]'s api, on a freshly reset scenario.
  void contract(String name, ShowcaseApi Function() make, {Object? skip}) {
    group(name, skip: skip, () {
      late ShowcaseApi api;

      setUp(() async {
        api = make();
        await api.resetScenario();
        await api.configureScenario(latency: Duration.zero);
      });

      test('posts: the seed, in order', () async {
        final posts = await api.posts();
        expect(posts, hasLength(30));
        expect(posts.first, Post.fromJson(firstPost));
      });

      test('post: one by id, 404 with a message otherwise', () async {
        expect(
            (await api.post(2)).title, 'Continuous integration: setup guide');
        await expectLater(
          api.post(999),
          throwsA(isA<BackendException>()
              .having((e) => e.status, 'status', 404)
              .having((e) => e.message, 'message', 'Post not found')),
        );
      });

      test('comments: three per post', () async {
        final comments = await api.comments(2);
        expect(comments, hasLength(3));
        expect(comments.map((c) => c.postId).toSet(), <int>{2});
      });

      test('search: by title, empty for an empty needle', () async {
        expect((await api.search('review')).map((p) => p.id), <int>[3]);
        expect((await api.search('  review  ')).map((p) => p.id), <int>[3]);
        expect(await api.search(''), isEmpty);
        expect(await api.search('   '), isEmpty);
      });

      test('missing ids: a 404 with a message on every route that takes one',
          () async {
        Matcher missing(String what) => throwsA(isA<BackendException>()
            .having((e) => e.status, 'status', 404)
            .having((e) => e.message, 'message', what));
        await expectLater(api.post(999), missing('Post not found'));
        await expectLater(api.comments(999), missing('Post not found'));
        await expectLater(
            api.updateTodo(999, text: 'ghost'), missing('Todo not found'));
        await expectLater(
            api.updateTodo(999, done: true), missing('Todo not found'));
        await expectLater(api.deleteTodo(999), missing('Todo not found'));
        // The id is checked first, so nothing was written on the way.
        expect(await api.todos(), hasLength(3));
      });

      test('todos: a rename, trimmed, and the text the backend refuses',
          () async {
        final created = await api.createTodo('  Contract  ');
        expect(created.text, 'Contract');
        expect((await api.updateTodo(created.id, text: '  Renamed  ')).text,
            'Renamed');
        // `done` was not mentioned, so the rename left it alone — and the
        // other way round.
        expect((await api.updateTodo(created.id, done: true)).text, 'Renamed');
        await expectLater(
          api.updateTodo(created.id, text: '   '),
          throwsA(isA<BackendException>()
              .having((e) => e.status, 'status', 400)
              .having((e) => e.message, 'message',
                  'Field "text" is missing or empty')),
        );
        final stored = (await api.todos()).last;
        expect(stored.text, 'Renamed');
        expect(stored.done, isTrue);
      });

      test('todos: create, update, delete, and the validation', () async {
        expect(await api.todos(), hasLength(3));
        final created = await api.createTodo('Contract');
        expect(created, const Todo(id: 4, text: 'Contract', done: false));
        final updated = await api.updateTodo(4, done: true);
        expect(updated.done, isTrue);
        expect(await api.deleteTodo(4), 4);
        expect(await api.todos(), hasLength(3));
        await expectLater(
          api.createTodo(' '),
          throwsA(isA<BackendException>()
              .having((e) => e.status, 'status', 400)
              .having((e) => e.message, 'message',
                  'Field "text" is missing or empty')),
        );
        await expectLater(
          api.updateTodo(999, done: true),
          throwsA(
              isA<BackendException>().having((e) => e.status, 'status', 404)),
        );
      });

      test('projects: pages of ten, a hundred in all', () async {
        final last = await api.projectsPage(9);
        expect(last.projects.map((p) => p.id),
            List<int>.generate(10, (i) => 90 + i));
        expect(last.hasMore, isFalse);
        expect((await api.projectsPage(0)).hasMore, isTrue);
        expect((await api.projectsPage(10)).projects, isEmpty);
        expect((await api.projectsPage(0, size: 25)).projects, hasLength(25));
      });

      test('projects: cursors in both directions', () async {
        final first = await api.projectsFrom(0);
        expect(first.items.map((p) => p.id), List<int>.generate(10, (i) => i));
        expect(first.nextId, 10);
        expect(first.previousId, isNull);
        final last = await api.projectsFrom(95);
        expect(last.items, hasLength(5));
        expect(last.nextId, isNull);
        expect(last.previousId, 85);
      });

      test('ticks: append, list, clear', () async {
        expect((await api.addTick()).id, 1);
        expect((await api.addTick()).id, 2);
        expect(await api.ticks(), hasLength(2));
        expect(await api.clearTicks(), 2);
        expect(await api.ticks(), isEmpty);
      });

      test('time: a serial that grows by one per call', () async {
        expect((await api.time()).serial, 1);
        expect((await api.time()).serial, 2);
      });

      test('counter: increments by one or by an amount', () async {
        expect(await api.increment(), 1);
        expect(await api.increment(by: 5), 6);
        expect(await api.counter(), 6);
      });

      test('getJson: a raw read of any path', () async {
        final json = await api.getJson('/posts/1');
        expect(json, isA<Map<String, Object?>>());
        expect((json! as Map<String, Object?>)['id'], 1);
      });

      test('?fail: the request asks to be refused', () async {
        await expectLater(
          api.time(fail: 503),
          throwsA(isA<BackendException>()
              .having((e) => e.status, 'status', 503)
              .having((e) => e.message, 'message', 'Requested: 503')),
        );
      });

      test('?fail: a status below 400 is a 500 all the same', () async {
        await expectLater(
          api.time(fail: 200),
          throwsA(isA<BackendException>()
              .having((e) => e.status, 'status', 500)
              .having((e) => e.message, 'message', 'Requested: 200')),
        );
        // The knob refuses ahead of the handler, so the world did not move.
        expect((await api.time()).serial, 1);
      });

      test('unknown route: a 404 that names it, and the faults in front of it',
          () async {
        await expectLater(
          api.getJson('/nope'),
          throwsA(isA<BackendException>()
              .having((e) => e.status, 'status', 404)
              .having(
                  (e) => e.message, 'message', 'Unknown route GET /api/nope')),
        );
        // It is logged like any other answered request.
        expect(
          (await api.scenarioRequests()).map((entry) =>
              '${entry['method']} ${entry['path']} ${entry['status']}'),
          <String>['GET /api/nope 404'],
        );
        // And the fault chain runs before it: the middleware that applies
        // the faults is registered ahead of the handler that answers 404.
        await api.configureScenario(failNext: const <FailNext>[
          FailNext(method: 'GET', path: '/api/nope', count: 1, status: 503),
        ]);
        await expectLater(
          api.getJson('/nope'),
          throwsA(isA<BackendException>()
              .having((e) => e.status, 'status', 503)
              .having((e) => e.message, 'message', 'Scripted failure 503')),
        );
      });

      test('failNext: the next matching requests fail, then it clears',
          () async {
        await api.configureScenario(failNext: const <FailNext>[
          FailNext(method: 'GET', path: '/api/todos*', count: 2, status: 500),
        ]);
        for (var i = 0; i < 2; i++) {
          await expectLater(
            api.todos(),
            throwsA(isA<BackendException>()
                .having((e) => e.status, 'status', 500)
                .having((e) => e.message, 'message', 'Scripted failure 500')),
          );
        }
        expect(await api.todos(), hasLength(3));
        // Other routes were never affected.
        expect((await api.time()).serial, 1);
      });

      test('failNext: an exact path, its own message, and the method it names',
          () async {
        await api.configureScenario(failNext: const <FailNext>[
          FailNext(
              method: 'GET',
              path: '/api/todo',
              count: 1,
              status: 409,
              message: 'Taken'),
        ]);
        // Without a trailing `*` the path is exact, so the near miss is
        // answered normally and the script is still armed.
        expect(await api.todos(), hasLength(3));
        await api.configureScenario(failNext: const <FailNext>[
          FailNext(
              method: 'DELETE',
              path: '/api/ticks',
              count: 1,
              status: 409,
              message: 'Taken'),
        ]);
        // The method is the other half of the match.
        expect(await api.ticks(), isEmpty);
        await expectLater(
          api.clearTicks(),
          throwsA(isA<BackendException>()
              .having((e) => e.status, 'status', 409)
              .having((e) => e.message, 'message', 'Taken')),
        );
        expect(await api.clearTicks(), 0);
      });

      test('config: what it echoes back, and what it refuses', () async {
        final config = await api.configureScenario(
          latency: Duration.zero,
          errorRate: 0,
          failNext: const <FailNext>[
            FailNext(
                method: 'get',
                path: '/api/todos',
                count: 3,
                status: 500,
                message: 'Taken'),
          ],
        );
        expect(config['latency'], 0);
        expect(config['errorRate'], 0);
        // The method is upper-cased on the way in; everything else is kept
        // as it was sent.
        expect(config['failNext'], <Object?>[
          <String, Object?>{
            'method': 'GET',
            'path': '/api/todos',
            'count': 3,
            'status': 500,
            'message': 'Taken',
          },
        ]);
        await expectLater(
          api.configureScenario(latency: const Duration(milliseconds: -1)),
          throwsA(isA<BackendException>()
              .having((e) => e.status, 'status', 400)
              .having(
                  (e) => e.message, 'message', 'latency: milliseconds ≥ 0')),
        );
        await expectLater(
          api.configureScenario(errorRate: 2),
          throwsA(isA<BackendException>()
              .having((e) => e.status, 'status', 400)
              .having((e) => e.message, 'message',
                  'errorRate: a number between 0 and 1')),
        );
        // A refused config changed nothing, and an empty one is a read.
        final unchanged = await api.configureScenario();
        expect(unchanged['latency'], 0);
        expect(unchanged['errorRate'], 0);
      });

      test('errorRate: one fails everything, zero nothing', () async {
        await api.configureScenario(errorRate: 1);
        await expectLater(
          api.time(),
          throwsA(isA<BackendException>().having(
              (e) => e.message, 'message', 'Failed at random (errorRate)')),
        );
        await api.configureScenario(errorRate: 0);
        expect((await api.time()).serial, 1);
      });

      test('?delay: waits on top of the latency', () async {
        final stopwatch = Stopwatch()..start();
        await api.time(delay: const Duration(milliseconds: 300));
        expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(280));
      });

      test('reset: back to the seed, answering with the id it was given',
          () async {
        await api.createTodo('Gone after reset');
        await api.increment();
        expect(await api.resetScenario(), api.scenario);
        expect(await api.todos(), hasLength(3));
        expect(await api.counter(), 0);
      });

      test('requests: the log, with query strings and statuses', () async {
        await api.posts();
        await expectLater(
            api.time(fail: 418), throwsA(isA<BackendException>()));
        final log = await api.scenarioRequests();
        expect(
          log.map((entry) =>
              '${entry['method']} ${entry['path']} ${entry['status']}'),
          <String>['GET /api/posts 200', 'GET /api/time 418'],
        );
        expect((log.last['query']! as Map<String, Object?>)['fail'], '418');
        expect(jsonDecode(jsonEncode(log)), log);
      });

      test('requests: DELETE empties the log and says how many went', () async {
        await api.posts();
        await api.time();
        expect(await api.scenarioRequests(), hasLength(2));
        expect(await api.clearScenarioRequests(), 2);
        expect(await api.scenarioRequests(), isEmpty);
        expect(await api.clearScenarioRequests(), 0);
        // Emptying the log is not a reset: the world it was logging is
        // untouched, and the control routes never entered it.
        expect((await api.time()).serial, 2);
        expect(
          (await api.scenarioRequests()).map((entry) => entry['path']),
          <String>['/api/time'],
        );
      });
    });
  }

  contract('the fake', () {
    final backend = FakeBackend();
    return ShowcaseApi(
      dio: Dio(BaseOptions(baseUrl: 'http://backend.test/api'))
        ..httpClientAdapter = backend,
      scenario: 'contract',
    );
  });

  final serverUrl = Platform.environment['SHOWCASE_SERVER'];
  contract(
    'the server',
    () => ShowcaseApi(
      baseUrl: serverUrl,
      scenario:
          'contract-${clock.now().microsecondsSinceEpoch.toRadixString(36)}',
    ),
    skip: serverUrl == null ? 'SHOWCASE_SERVER is not set' : false,
  );
}
