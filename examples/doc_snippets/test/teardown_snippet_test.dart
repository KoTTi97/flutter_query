/// The testing guide's samples (`website/docs/guides/testing.md`), as tests
/// that run under `flutter test`: the teardown a first widget test needs, and
/// the harness that wraps it. The page and this file are kept identical, for
/// the reason `lib/doc_snippets.dart` gives — a sample nobody compiles rots.
///
/// The teardown is a documented snippet rather than an export of the package
/// (ADR-0002): `flutter_test` is a dev dependency of `query_kit_flutter`, so
/// nothing a test needs sits in an app's dependency graph.
library;

import 'package:doc_snippets/doc_snippets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

void main() {
  // -------------------------------------------------------------------------
  // guides/testing.md — the teardown every widget test needs
  // -------------------------------------------------------------------------

  testWidgets('the list loads', (tester) async {
    final client = QueryClient();
    await tester.pumpWidget(QueryClientProvider(
      client: client,
      child: const MaterialApp(home: TasksScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsOneWidget);

    // Let the widgets go, and the frame after them run.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    // Then the cache and its timers.
    client.clear();
    // A mutation the clear dropped fails a moment later and its callbacks
    // run then; let them, then clear what they wrote.
    await tester.pump();
    client.clear();
  });

  // -------------------------------------------------------------------------
  // guides/testing.md — the harness both examples wrap
  // -------------------------------------------------------------------------

  queryWidgetTest('the list loads', (tester, client) async {
    await tester.pumpWidget(QueryClientProvider(
      client: client,
      child: const MaterialApp(home: TasksScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsOneWidget);
  });
}

/// `testWidgets` plus the teardown a `QueryClient` needs.
void queryWidgetTest(
  String description,
  Future<void> Function(WidgetTester tester, QueryClient client) body, {
  QueryClient Function()? createClient,
}) {
  testWidgets(description, (tester) async {
    final client = (createClient ?? QueryClient.new)();
    try {
      await body(tester, client);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      client.clear();
      await tester.pump();
      client.clear();
    }
  });
}
