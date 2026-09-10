/// The shipped test helper, tested the way a user's first widget test uses it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';
import 'package:query_kit_flutter/testing.dart';

void main() {
  queryWidgetTest('a query read in build, with no teardown of its own',
      (tester, client) async {
    await tester.pumpWidget(QueryClientProvider(
      client: client,
      observeAppLifecycle: false,
      child: MaterialApp(
        home: QueryBuilder<String>(
          options: QueryObserverOptions(
            queryKey: QueryKey(<Object?>['helper']),
            queryFn: (_) async => 'Sensor a',
          ),
          builder: (_, result) => Text(result.dataOrNull ?? 'loading'),
        ),
      ),
    ));
    expect(find.text('loading'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Sensor a'), findsOneWidget);
    // The gcTime timer this leaves behind is exactly what the helper exists
    // for: without its teardown the binding fails the test on a pending timer.
  });

  queryWidgetTest('createClient carries defaults through',
      (tester, client) async {
    final defaulted = client.defaultQueryOptions(
      QueryObserverOptions<String, String>(
        queryKey: QueryKey(<Object?>['defaults']),
      ),
    );
    expect(defaulted.gcTime, GcTime.never);
  },
      createClient: () => QueryClient(
            defaultOptions: const DefaultOptions(
              queries: QueryDefaults(gcTime: GcTime.never),
            ),
          ));
}
