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
        expect(await api.search(''), isEmpty);
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

      test('reset: back to the seed', () async {
        await api.createTodo('Gone after reset');
        await api.increment();
        await api.resetScenario();
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
