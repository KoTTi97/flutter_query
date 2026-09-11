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
            queryFn: (_) async => 'Task a',
          ),
          builder: (_, result) => Text(result.dataOrNull ?? 'loading'),
        ),
      ),
    ));
    expect(find.text('loading'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Task a'), findsOneWidget);
    // The gcTime timer this leaves behind is exactly what the helper exists
    // for: without its teardown the binding fails the test on a pending timer.
  });

  queryWidgetTest(
      'C11 an offline optimistic mutation left paused: its rollback runs '
      'after clear(), and the teardown still leaves nothing pending',
      (tester, client) async {
    final key = QueryKey(<Object?>['rollback']);
    client.setQueryData<int>(key, 1);
    client.onlineManager.setOnline(false);
    final mutation = MutationController<int, int, int>(
      client,
      MutationOptions(
        mutationFn: (value) => value,
        onMutate: (_) {
          final previous = client.getQueryData<int>(key)!;
          client.setQueryData<int>(key, 2);
          return previous;
        },
        // The canonical rollback: `setQueryData` re-creates the query — gc
        // timer included — when it runs after `clear()` emptied the cache.
        onError: (_, __, ___, previous) =>
            client.setQueryData<int>(key, previous!),
      ),
    );
    mutation.mutate(2);
    await tester.pump();
    expect(mutation.value.isPaused, isTrue);
    expect(client.getQueryData<int>(key), 2);
    mutation.dispose();
    // Left paused on purpose: the helper's teardown drops it, which fails it
    // with a CancelledError and runs the rollback a few microtasks after
    // `clear()`. Without the helper's second clear the binding fails this
    // test on the re-created query's pending gc timer.
  });

  queryWidgetTest('createClient carries defaults through',
      (tester, client) async {
    final defaulted = client.defaultQueryOptions(
      QueryObserverOptions<String>(
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
