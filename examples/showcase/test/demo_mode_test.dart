/// The app as the documentation site runs it: over the in-memory backend
/// (`--dart-define=QK_BACKEND=inmemory`, `lib/demo/`) and embedded one feature
/// at a time (`?embed=1`), plus the list of features the site's `<LiveDemo>`
/// knows — the catalogue's sixth set.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';
import 'package:showcase/demo/demo_mode.dart';
import 'package:showcase/home_screen.dart';
import 'package:showcase/main.dart';
import 'package:showcase/routes.dart';
import 'package:showcase/shared/api.dart';

import 'fake_backend.dart';

/// The site's copy of the catalogue, read by `<LiveDemo>`, by the build's
/// check that every `<LiveDemo feature>` in the docs exists, and by the site's
/// end-to-end suite. Regenerate it with
/// `UPDATE_SITE_FEATURES=1 flutter test test/demo_mode_test.dart`.
const String _siteFeatures =
    '../../website/src/components/LiveDemo/showcase-features.json';

void main() {
  test(
      'the demo build seeds from server/seed.json, the asset and the file '
      'being one and the same', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(await loadSeed(rootBundle), FakeBackend.seed());
  });

  test('the site lists exactly the catalogue, in its order', () {
    final expected = <Map<String, String>>[
      for (final entry in featureEntries)
        <String, String>{
          'id': entry.feature.id,
          'title': entry.feature.title,
          'summary': entry.feature.summary,
        },
    ];
    final file = File(_siteFeatures);
    if (Platform.environment['UPDATE_SITE_FEATURES'] == '1') {
      file.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(expected)}\n');
    }
    expect(
      jsonDecode(file.readAsStringSync()),
      expected,
      reason: '$_siteFeatures has drifted from lib/routes.dart; run '
          'UPDATE_SITE_FEATURES=1 flutter test test/demo_mode_test.dart',
    );
  });

  test('?theme= picks the colour scheme, and nothing else changes it', () {
    expect(
        themeModeFrom(const <String, String>{'theme': 'dark'}), ThemeMode.dark);
    expect(themeModeFrom(const <String, String>{'theme': 'light'}),
        ThemeMode.light);
    // No parameter, or one the app does not know: the light theme it always
    // had, which `main` falls back to.
    expect(themeModeFrom(const <String, String>{}), isNull);
    expect(themeModeFrom(const <String, String>{'theme': 'Dark'}), isNull);
    expect(themeModeFrom(const <String, String>{'embed': '1'}), isNull);
  });

  group('embedded over the in-memory backend', () {
    Future<QueryClient> open(WidgetTester tester, String route,
        {ThemeMode themeMode = ThemeMode.light}) async {
      final client = QueryClient(notifyManager: NotifyManager.shared);
      await tester.pumpWidget(ShowcaseApp(
        api: inMemoryApi(FakeBackend.seed()),
        client: client,
        initialRoute: route,
        embed: true,
        inMemory: true,
        themeMode: themeMode,
      ));
      return client;
    }

    Future<void> tearDown(WidgetTester tester, QueryClient client) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      client.clear();
      await tester.pump();
      client.clear();
    }

    testWidgets('one feature, no way back, and its data after the latency',
        (tester) async {
      final client = await open(tester, '/simple');
      try {
        await tester.pump();
        expect(find.text('Simple'), findsOneWidget);
        expect(find.byType(BackButton), findsNothing);
        expect(find.text('in-memory backend'), findsOneWidget);
        expect(find.text('scenario in-memory'), findsNothing);
        expect(find.text('Local development: setup guide'), findsNothing);

        await tester.pump(demoLatency);
        await tester.pumpAndSettle();
        expect(find.text('Local development: setup guide'), findsOneWidget);

        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        expect(navigator.canPop(), isFalse,
            reason: 'the catalogue must not sit beneath an embedded feature');
        expect(find.text(showcaseTitle), findsNothing);
      } finally {
        await tearDown(tester, client);
      }
    });

    testWidgets('dark when the site is dark', (tester) async {
      final client = await open(tester, '/simple', themeMode: ThemeMode.dark);
      try {
        await tester.pump();
        expect(Theme.of(tester.element(find.text('Simple'))).brightness,
            Brightness.dark);
        await tester.pump(demoLatency);
        await tester.pumpAndSettle();
      } finally {
        await tearDown(tester, client);
      }
    });

    testWidgets(
        'a route that is no feature, "/" included, is not the catalogue',
        (tester) async {
      final client = await open(tester, '/no-such-feature');
      try {
        await tester.pumpAndSettle();
        expect(find.text('Unknown demo'), findsOneWidget);
        expect(find.textContaining('"/no-such-feature"'), findsOneWidget);

        unawaited(tester
            .state<NavigatorState>(find.byType(Navigator))
            .pushNamed<void>('/'));
        await tester.pumpAndSettle();
        expect(find.text(showcaseTitle), findsNothing);
        expect(find.textContaining('"/"'), findsOneWidget);
      } finally {
        await tearDown(tester, client);
      }
    });
  });

  testWidgets('without embed the catalogue sits beneath a deep link',
      (tester) async {
    final client = QueryClient(notifyManager: NotifyManager.shared);
    final backend = FakeBackend();
    try {
      await tester.pumpWidget(ShowcaseApp(
        api: ShowcaseApi(
          dio: Dio(BaseOptions(baseUrl: 'http://backend.test/api'))
            ..httpClientAdapter = backend,
          scenario: 'widget-test',
        ),
        client: client,
        initialRoute: '/simple',
      ));
      await tester.pumpAndSettle();
      expect(find.text('scenario widget-test'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text(showcaseTitle), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      client.clear();
      await tester.pump();
      client.clear();
      backend.close();
    }
  });
}
