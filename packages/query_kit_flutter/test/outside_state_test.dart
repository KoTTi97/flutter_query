/// Options that read state outside the cache (#84): a rebuild hands the
/// observer its options again, and that re-evaluates an `Enabled.when` — so
/// the trigger is whatever already rebuilds the widget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'harness.dart';

void main() {
  for (final style in ['QueryBuilder', 'context.query']) {
    queryWidgetTest(
        '$style: polling paused by an outside flag resumes when the flag '
        'rebuilds the widget', (tester, client) async {
      final writing = ValueNotifier<bool>(false);
      addTearDown(writing.dispose);
      var fetches = 0;
      QueryObserverOptions<int> options() => QueryObserverOptions(
            queryKey: QueryKey(const ['status']),
            // A callback over outside state, not a value: the trap's shape.
            enabled: Enabled.when((_) => !writing.value),
            refetchInterval: const RefetchInterval.every(Duration(seconds: 1)),
            queryFn: (_) async => ++fetches,
          );
      await tester.pumpWidget(app(
          client,
          ValueListenableBuilder<bool>(
            valueListenable: writing,
            builder: (context, _, __) => style == 'QueryBuilder'
                ? QueryBuilder<int>(
                    options: options(),
                    builder: (context, result) =>
                        Text('n=${result.dataOrNull}'),
                  )
                : Builder(
                    builder: (context) =>
                        Text('n=${context.query(options()).dataOrNull}')),
          )));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(fetches, 2);

      writing.value = true;
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(fetches, 2, reason: 'paused');

      writing.value = false;
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(fetches, greaterThan(2), reason: 'resumed');
    });
  }
}
