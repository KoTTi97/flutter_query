/// The catalogue's five sets, compared — the one thing `routes.dart` cannot
/// prove about itself.
///
/// A feature exists five times over: as a directory under `lib/features/`, as
/// a row of [featureEntries], as `test/features/<id>_test.dart`, as
/// `e2e/tests/<id>.spec.ts`, and as a row of the README's table. Nothing but a
/// habit held them level, and the review counted 26/26/26/26 by hand (C59,
/// https://github.com/KoTTi97/flutter_query/issues/66). It is 28 now, and the
/// screen that made it 28 is exactly the drift this file is here to catch: a
/// feature added to four of the five is a silent hole — the catalogue entry
/// with no end-to-end spec, the screen nobody routes to — and `onGenerateRoute`
/// answering an unknown name with the home screen is what makes the last of
/// those look like a working app.
///
/// The sets are read off the filesystem rather than generated from one list on
/// purpose: generating them would make the five agree by construction and
/// prove nothing about the two written in TypeScript and Markdown, which no
/// Dart declaration can reach.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showcase/home_screen.dart';
import 'package:showcase/routes.dart';

void main() {
  final Directory root = _packageRoot();

  /// The catalogue, in the order the home screen lists it.
  final List<String> catalogue =
      featureEntries.map((entry) => entry.feature.id).toList();

  test('every catalogue id is one kebab-case segment, and unique', () {
    for (final id in catalogue) {
      expect(id, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')),
          reason: '"$id" is not a single kebab-case segment; a route with a '
              'second segment falls back to "/" in Flutter\'s initial-route '
              'expansion (see Feature.id)');
    }
    expect(catalogue.toSet(), hasLength(catalogue.length),
        reason: 'two entries share an id, so one route can never be reached');
    expect(
      featureEntries.map((entry) => entry.feature.route).toList(),
      catalogue.map((id) => '/$id').toList(),
    );
  });

  test('one directory under lib/features per catalogue entry', () {
    expect(_directories(root, 'lib/features'), _snakeCase(catalogue));
    for (final id in catalogue) {
      final dir = _snake(id);
      expect(
        File('${root.path}/lib/features/$dir/${dir}_screen.dart').existsSync(),
        isTrue,
        reason: 'lib/features/$dir/${dir}_screen.dart is missing',
      );
    }
  });

  test('one widget-test file per catalogue entry', () {
    expect(
      _files(root, 'test/features', '_test.dart'),
      _snakeCase(catalogue),
      reason: 'a screen with no widget tests, or tests for a screen the '
          'catalogue does not list',
    );
  });

  test('one end-to-end spec per catalogue entry', () {
    expect(
      _files(root, 'e2e/tests', '.spec.ts'),
      _snakeCase(catalogue),
      reason: 'a screen with no end-to-end spec, or a spec for a screen the '
          'catalogue does not list',
    );
  });

  test('one README row per catalogue entry, in the catalogue order', () {
    final rows = RegExp(r'^\| `([a-z0-9-]+)` \|', multiLine: true)
        .allMatches(File('${root.path}/README.md').readAsStringSync())
        .map((match) => match.group(1)!)
        .toList();
    expect(rows, catalogue,
        reason: "the README's table is the catalogue written a second time; "
            'it lists the same features in the same order');
  });

  testWidgets('every route reaches its own screen', (tester) async {
    final BuildContext context = await _aContext(tester);
    for (final id in catalogue) {
      final screen = _screenAt(context, '/$id');
      expect('${screen.runtimeType}', _screenClass(id),
          reason: '/$id is routed to a $screen');
    }
    // Distinct classes, not just distinctly named: two entries built from one
    // screen would mean a feature nobody can open.
    final types = <Type>{
      for (final id in catalogue) _screenAt(context, '/$id').runtimeType,
    };
    expect(types, hasLength(catalogue.length));
  });

  testWidgets('an unknown name reaches the catalogue, and keeps its name',
      (tester) async {
    final BuildContext context = await _aContext(tester);
    // Deliberate, and now the only thing the fallback can hide: a name the
    // catalogue does not have comes from outside the app — a typed or stale
    // deep link — because every name the app itself pushes is a
    // `Feature.route`, which the tests above pin to a screen. The catalogue is
    // where such a link belongs, and the settings are kept so the route the
    // navigator reports is still the one that was asked for (C59, #66).
    expect(_screenAt(context, '/nope'), isA<HomeScreen>());
    expect(_screenAt(context, '/'), isA<HomeScreen>());
    expect(_screenAt(context, null), isA<HomeScreen>());
    expect(onGenerateRoute(const RouteSettings(name: '/nope')).settings.name,
        '/nope');
  });
}

/// The widget `onGenerateRoute` builds for [name], without mounting it.
Widget _screenAt(BuildContext context, String? name) {
  final route = onGenerateRoute(RouteSettings(name: name));
  return (route as MaterialPageRoute<Object?>).builder(context);
}

/// A live [BuildContext] to build a screen with. The screens are never
/// mounted: what is under test is which widget the route produces.
Future<BuildContext> _aContext(WidgetTester tester) async {
  late BuildContext context;
  await tester.pumpWidget(Builder(builder: (inner) {
    context = inner;
    return const SizedBox();
  }));
  return context;
}

/// `stale-and-gc` → `StaleAndGcScreen`, the name every screen class has.
String _screenClass(String id) =>
    '${id.split('-').map((word) => word[0].toUpperCase() + word.substring(1)).join()}Screen';

String _snake(String id) => id.replaceAll('-', '_');

List<String> _snakeCase(List<String> ids) => (ids.map(_snake).toList()..sort());

List<String> _directories(Directory root, String path) {
  final dir = Directory('${root.path}/$path');
  expect(dir.existsSync(), isTrue, reason: '$path is missing');
  return (dir
      .listSync()
      .whereType<Directory>()
      .map((entry) => entry.uri.pathSegments[entry.uri.pathSegments.length - 2])
      .toList()
    ..sort());
}

List<String> _files(Directory root, String path, String suffix) {
  final dir = Directory('${root.path}/$path');
  expect(dir.existsSync(), isTrue, reason: '$path is missing');
  return (dir
      .listSync()
      .whereType<File>()
      .map((entry) => entry.uri.pathSegments.last)
      .where((name) => name.endsWith(suffix))
      .map((name) => name.substring(0, name.length - suffix.length))
      .toList()
    ..sort());
}

/// The showcase's own directory, whatever the test was started from.
Directory _packageRoot() {
  var dir = Directory.current;
  for (var up = 0; up < 5; up++) {
    if (Directory('${dir.path}/lib/features').existsSync() &&
        File('${dir.path}/pubspec.yaml').existsSync()) {
      return dir;
    }
    dir = dir.parent;
  }
  fail('the showcase package was not found from ${Directory.current.path}; '
      'run this suite from examples/showcase');
}
