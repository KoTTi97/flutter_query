/// Test helpers, imported only from a test file.
///
/// ```dart
/// import 'package:query_kit_flutter/testing.dart';
///
/// void main() {
///   queryWidgetTest('the list loads', (tester, client) async {
///     await tester.pumpWidget(QueryClientProvider(
///       client: client,
///       child: const MaterialApp(home: SensorsScreen()),
///     ));
///     await tester.pumpAndSettle();
///     expect(find.text('Sensor a'), findsOneWidget);
///   });
/// }
/// ```
///
/// This library pulls in `flutter_test`, so import it from `test/` only —
/// never from `lib/`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';
import 'package:query_kit/query_kit.dart';

export 'package:query_kit/query_kit.dart' show QueryClient, DefaultOptions;

/// [testWidgets] for a tree with a [QueryClient] in it: builds a client for
/// the case, hands it to [body], and takes it down afterwards.
///
/// Why this exists. A `QueryClient` outlives the widget tree and owns the
/// `gcTime` timers of everything in its cache. Flutter's test binding asserts
/// that no timer is pending when the tree comes down — and it does that
/// *before* any `tearDown` runs, so clearing the client from one is already
/// too late. The end of a query widget test is therefore always the same
/// three steps: tear the tree down, let the frame after it run, then
/// `client.clear()`. Getting them wrong fails the test with a pending-timer
/// error that says nothing about queries, which is a poor first hour with any
/// library.
///
/// [createClient] builds the client — pass one to set `defaultOptions`. The
/// remaining arguments are [testWidgets]'s own and mean the same thing.
@isTest
void queryWidgetTest(
  String description,
  Future<void> Function(WidgetTester tester, QueryClient client) body, {
  QueryClient Function()? createClient,
  bool? skip,
  Timeout? timeout,
  bool semanticsEnabled = true,
  TestVariant<Object?> variant = const DefaultTestVariant(),
  dynamic tags,
}) {
  testWidgets(
    description,
    (tester) async {
      final client = (createClient ?? QueryClient.new)();
      try {
        await body(tester, client);
      } finally {
        await tearDownQueryClient(tester, client);
      }
    },
    skip: skip,
    timeout: timeout,
    semanticsEnabled: semanticsEnabled,
    variant: variant,
    tags: tags,
  );
}

/// The three steps [queryWidgetTest] ends with, for a test that builds its
/// own client or drives more than one.
///
/// Tears the tree down, lets the frame after it run — an observer released by
/// the unmount notifies there — and then clears [client], which cancels the
/// `gcTime` timers the test binding would otherwise refuse.
Future<void> tearDownQueryClient(
    WidgetTester tester, QueryClient client) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  client.clear();
}
