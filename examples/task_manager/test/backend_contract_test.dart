/// The backend's contract, run against the fake — and, when
/// `TASK_MANAGER_SERVER` names a running server (`http://localhost:5174/api`),
/// against that too.
///
/// One list of cases, two targets: that is what makes the fake trustworthy.
/// The acceptance suite drives the real app against `FakeBackend`, and every
/// one of its assertions is worth exactly as much as the fake's likeness to
/// `server/server.ts`. This file is where a drift shows — it found six
/// (https://github.com/KoTTi97/flutter_query/issues/54).
///
/// Where the two *deliberately* differ, the case says so and asserts the
/// difference rather than papering over it; the seed is the one such place.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/src/api.dart';
import 'package:task_manager/src/models.dart';

import 'fake_backend.dart';

/// One target's transport: the api the app uses, and the raw dio underneath
/// it.
///
/// The raw dio is here because two of the drifts live in bodies [TaskApi]'s
/// typed parameters cannot express — a `reminder` that is not a boolean, a
/// `name` that is absent. No app sends those; *some* client will, and the fake
/// has to answer them the way the server does or a test that provokes one is
/// testing fiction.
typedef Target = ({TaskApi api, Dio dio});

void main() {
  /// Runs every case against [connect]'s target.
  ///
  /// [seed] is what that target starts with — the one place the two disagree
  /// on purpose; see the two calls at the bottom of this file.
  void contract(
    String name,
    Target Function() connect, {
    required List<String> seed,
    Object? skip,
  }) {
    group(name, skip: skip, () {
      late TaskApi api;
      late Dio dio;

      setUp(() {
        final target = connect();
        api = target.api;
        dio = target.dio;
      });

      test('seed: the rows the app opens on', () async {
        final tasks = (await api.listTasks(TaskFilters.all)).tasks;
        expect(tasks.length, greaterThanOrEqualTo(seed.length));
        // The real server keeps one world for its whole process, so anything
        // an earlier case or an earlier run created is behind the seed.
        final seeded = tasks.take(seed.length).toList();
        expect(seeded.map((task) => task.name), seed);
        // What both seeds guarantee, which is all any screen depends on: the
        // ids are distinct, at least one row is unsynced (or the header's
        // count is meaningless) and more than one project exists (or the
        // project filter has nothing to filter).
        expect(seeded.map((task) => task.id).toSet(), hasLength(seed.length));
        expect(seeded.where((task) => !task.synced), isNotEmpty);
        expect(
          seeded.map((task) => task.project).toSet().length,
          greaterThan(1),
        );
      });

      test('list: search ignores case and surrounding space, project narrows',
          () async {
        final needle = _unique('Contract needle');
        final task = await api.createTask(name: needle, project: 'Contracts');

        Future<List<String>> idsFor(TaskFilters filters) async =>
            (await api.listTasks(filters))
                .tasks
                .map((task) => task.id)
                .toList();

        expect(await idsFor(TaskFilters(search: needle)), <String>[task.id]);
        expect(
          await idsFor(TaskFilters(search: needle.toUpperCase())),
          <String>[task.id],
        );
        expect(
          await idsFor(TaskFilters(search: '  $needle  ')),
          <String>[task.id],
        );
        expect(
          await idsFor(
            TaskFilters(search: needle, project: 'Contracts'),
          ),
          <String>[task.id],
        );
        expect(
          await idsFor(TaskFilters(search: needle, project: 'Admin')),
          isEmpty,
        );
      });

      test('create: the task the server makes, fields it owns included',
          () async {
        final name = _unique('Contract create');
        final created = await api.createTask(
          name: name,
          project: 'Contracts',
          priority: Priority.high,
        );
        expect(created.name, name);
        expect(created.project, 'Contracts');
        expect(created.priority, Priority.high);
        // Server-owned: a client cannot set these, and a new task starts at
        // the bottom of all of them.
        expect(created.progress, 0);
        expect(created.estimate, 1);
        expect(created.synced, isTrue);
        expect(created.reminder, isFalse);
        expect(created.reminderTarget, isNull);
        expect(created.reminderPending, isFalse);
        // It is really there, under an id nothing else has.
        expect((await api.getTask(created.id)).name, name);
      });

      test('create: the project defaults, an unknown priority becomes normal',
          () async {
        final created = await api.createTask(name: _unique('Contract default'));
        expect(created.project, 'Inbox');
        expect(created.priority, Priority.normal);

        final response = await dio.post<Map<String, Object?>>(
          '/tasks',
          data: <String, Object?>{
            'name': _unique('Contract priority'),
            'priority': 'urgent',
          },
        );
        expect(response.data!['priority'], 'normal');
      });

      test('create: an empty name is refused, and a missing one too', () async {
        await expectLater(
          api.createTask(name: '   '),
          throwsA(_refusedWith('Field "name" is missing or empty')),
        );
        expect(
          await _refusalOf(
            () => dio.post<Map<String, Object?>>(
              '/tasks',
              data: const <String, Object?>{'project': 'Contracts'},
            ),
          ),
          (status: 400, message: 'Field "name" is missing or empty'),
        );
      });

      test('detail: one task by id, 404 with a message for one that is gone',
          () async {
        final created = await api.createTask(name: _unique('Contract detail'));
        expect(await api.getTask(created.id), created);
        await expectLater(
          api.getTask('no-such-task'),
          throwsA(_refusedWith('Task not found')),
        );
      });

      test('rename: the name lands verbatim', () async {
        final created = await api.createTask(name: _unique('Contract rename'));
        final renamed = await api.renameTask(created.id, '  Spaced  ');
        expect(renamed.name, '  Spaced  ');
        expect((await api.getTask(created.id)).name, '  Spaced  ');
      });

      test('rename: "fail" is refused, and so is an empty name', () async {
        final created = await api.createTask(name: _unique('Contract refuse'));
        await expectLater(
          api.renameTask(created.id, 'fail'),
          throwsA(_refusedWith('The server refused the write')),
        );
        await expectLater(
          api.renameTask(created.id, '   '),
          throwsA(_refusedWith('Field "name" is missing or empty')),
        );
        // Neither refusal touched the stored name.
        expect((await api.getTask(created.id)).name, created.name);
      });

      test('rename: an unknown id is 404, not a broken write', () async {
        await expectLater(
          api.renameTask('no-such-task', 'Anything'),
          throwsA(_refusedWith('Task not found')),
        );
      });

      test('reminder: accepted pending, then confirmed by the scheduler',
          () async {
        final created =
            await api.createTask(name: _unique('Contract reminder'));
        final accepted = await api.setReminder(created.id, value: true);
        // The write is accepted, not applied: the target is recorded and the
        // confirmed field has not moved. That pair is the whole reason
        // `reminderTarget` exists.
        expect(accepted.reminderPending, isTrue);
        expect(accepted.reminderTarget, isTrue);
        expect(accepted.reminder, isFalse);
        expect(accepted.displayedReminder, isTrue);

        final confirmed = await _pollUntil(
          () => api.getTask(created.id),
          (task) => !task.reminderPending,
        );
        expect(confirmed.reminder, isTrue);
        expect(confirmed.reminderTarget, isNull);
      });

      test('reminder: a value that is not a boolean is refused', () async {
        final created = await api.createTask(name: _unique('Contract boolean'));
        const message = 'Field "value" is missing or not a boolean';
        expect(
          await _refusalOf(
            () => dio.put<Map<String, Object?>>(
              '/tasks/${created.id}/reminder',
              data: const <String, Object?>{'value': 'yes'},
            ),
          ),
          (status: 400, message: message),
        );
        expect(
          await _refusalOf(
            () => dio.put<Map<String, Object?>>(
              '/tasks/${created.id}/reminder',
              data: const <String, Object?>{},
            ),
          ),
          (status: 400, message: message),
        );
        // Nothing was scheduled by either refusal.
        expect((await api.getTask(created.id)).reminderPending, isFalse);
      });

      test('reminder: an unknown id is 404', () async {
        await expectLater(
          api.setReminder('no-such-task', value: true),
          throwsA(_refusedWith('Task not found')),
        );
      });

      test('delete: every second attempt is refused, the retry goes through',
          () async {
        final first = await api.createTask(name: _unique('Contract delete'));
        final second = await api.createTask(name: _unique('Contract delete'));
        await _deleteUntilItSucceeds(api, first.id);

        // A delete that succeeded leaves the script on an even count, so the
        // next attempt is the odd one it refuses.
        await expectLater(
          api.deleteTask(second.id),
          throwsA(_refusedWith('The server refused the delete — try again')),
        );
        expect(await api.deleteTask(second.id), second.id);
        await expectLater(
          api.getTask(second.id),
          throwsA(_refusedWith('Task not found')),
        );
      });

      test('delete: an unknown id is 404 and does not consume an attempt',
          () async {
        final task = await api.createTask(name: _unique('Contract missing'));
        await _deleteUntilItSucceeds(api, task.id);

        await expectLater(
          api.deleteTask('no-such-task'),
          throwsA(_refusedWith('Task not found')),
        );

        // The route refuses an id it does not have before the every-second
        // script sees the attempt — so the count is where it was, and the
        // next real delete is still the odd one. A fake that counted the
        // missing id instead would flip the parity every demo screen and
        // every test depends on.
        final another = await api.createTask(name: _unique('Contract missing'));
        await expectLater(
          api.deleteTask(another.id),
          throwsA(_refusedWith('The server refused the delete — try again')),
        );
        expect(await api.deleteTask(another.id), another.id);
      });
    });
  }

  // The seeds differ on purpose, and this is the record of it.
  //
  // The server's five rows are the demo's shop window: four projects, spread
  // progress, one unsynced row so the header's count is not "all of them".
  // The fake's three are a fixture for the acceptance suite: every row is
  // named for the case that uses it, and the list is short enough that a
  // `find.text` is unambiguous in a test viewport. Making either serve the
  // other's job would mean rewriting sixteen widget tests or shrinking the
  // demo, and no screen, query or end-to-end spec names a seed row — the
  // end-to-end suite creates its own tasks for exactly this reason. What both
  // guarantee is asserted above; the counts and names are not part of it.
  contract(
    'the fake',
    () {
      final dio = Dio(BaseOptions(baseUrl: 'http://backend.test/api'))
        ..httpClientAdapter = FakeBackend();
      return (api: TaskApi(dio: dio), dio: dio);
    },
    seed: const <String>[
      'Draft the changelog',
      'Book the venue',
      'Renew the domain',
    ],
  );

  final serverUrl = Platform.environment['TASK_MANAGER_SERVER'];
  contract(
    'the server',
    () {
      final dio = Dio(BaseOptions(baseUrl: serverUrl ?? ''));
      return (api: TaskApi(dio: dio), dio: dio);
    },
    seed: const <String>[
      'Write the release notes',
      'Reply to the design review',
      'Renew the domain',
      'Pick up the parcel',
      'Archive last quarter',
    ],
    skip: serverUrl == null ? 'TASK_MANAGER_SERVER is not set' : false,
  );

  // The fake has one thing the server does not: a lifetime inside the test
  // process.
  group('the fake alone', () {
    test('close() cancels the confirmation it scheduled', () async {
      final backend = FakeBackend(confirmAfter: const Duration(seconds: 1));
      final api = TaskApi(
        dio: Dio(BaseOptions(baseUrl: 'http://backend.test/api'))
          ..httpClientAdapter = backend,
      );
      final created = await api.createTask(name: 'Reminder');
      await api.setReminder(created.id, value: true);

      backend.close();
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      // Nothing ran after the close: the task is still waiting for a
      // scheduler that is gone. An adapter whose `close()` left the timer
      // running is a timer firing into a torn-down test — which is the one
      // thing the documented widget-test teardown (ADR-0002) cannot clean up,
      // because it is not the client's timer.
      final task = Task.fromJson(backend.tasks[created.id]!);
      expect(task.reminderPending, isTrue);
      expect(task.reminder, isFalse);
    });
  });
}

/// A [BackendException] carrying exactly [message].
Matcher _refusedWith(String message) => isA<BackendException>()
    .having((error) => error.message, 'message', message);

/// What the wire said when it refused: the status and the `{ "message": … }`
/// body, or nulls where nothing that looks like a refusal came back.
///
/// This is the raw form, for the requests [TaskApi] cannot make.
Future<({int? status, String? message})> _refusalOf(
  Future<Response<Object?>> Function() request,
) async {
  try {
    await request();
    return (status: null, message: null);
  } on DioException catch (error) {
    final data = error.response?.data;
    return (
      status: error.response?.statusCode,
      message: data is Map && data['message'] is String
          ? data['message'] as String
          : null,
    );
  }
}

/// Drives the every-second-delete script to a known point: after a delete that
/// succeeded, the next attempt is the odd one and must be refused.
///
/// Both targets count attempts for the life of a process, so a case that wants
/// to see the refusal has to arrive at the right parity rather than assume it.
Future<void> _deleteUntilItSucceeds(TaskApi api, String id) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      await api.deleteTask(id);
      return;
    } on BackendException {
      // The scripted refusal; the retry is the point.
    }
  }
  fail('two delete attempts and $id is still there');
}

/// Reads until [done], or gives up.
///
/// The reminder scheduler is the one part of the contract that takes real
/// time — 300 ms in the fake, `CONFIRM_AFTER` (3 s by default) on the server —
/// so the case waits for the state rather than for a duration. No assertion
/// here reads a clock.
Future<T> _pollUntil<T>(
  Future<T> Function() read,
  bool Function(T value) done,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    final value = await read();
    if (done(value)) {
      return value;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('the backend never reached the state this case waits for');
}

int _counter = 0;

/// A name no other case and no earlier run against the same server can have
/// produced.
///
/// The wall clock on purpose: this file runs against a real process in real
/// time, so there is no `fake_async` zone for `package:clock` to belong to —
/// the same reason the fake stamps `fetchedAt` with [DateTime.now].
String _unique(String prefix) =>
    '$prefix ${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '${_counter++}';
