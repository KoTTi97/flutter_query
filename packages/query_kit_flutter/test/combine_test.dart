/// `combine` over a record of results (#82) needs nothing from the binding:
/// it is a function of what the four call styles already hand out. Proven
/// here for the two that differ in how several reads meet — reads in one
/// `build`, and controllers merged with `Listenable.merge`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'harness.dart';

QueryObserverOptions<String> _name(QueryKey key) => QueryObserverOptions(
      queryKey: key,
      queryFn: (_) async => 'BR64',
    );

QueryObserverOptions<int> _channels(QueryKey key, {bool fail = false}) =>
    QueryObserverOptions(
      queryKey: key,
      retry: RetryPolicy.never,
      queryFn: (_) async => fail ? throw StateError('down') : 4,
    );

Widget _show(CombinedResult<String> combined) => Text(switch (combined) {
      CombinedPending() => 'loading',
      CombinedError(:final error) => 'failed: $error',
      CombinedData(:final data) => data,
    });

void main() {
  queryWidgetTest('two context.query reads of different types combine',
      (tester, client) async {
    final name = QueryKey(const ['name']);
    final channels = QueryKey(const ['channels']);
    var builds = 0;
    await tester.pumpWidget(app(client, Builder(builder: (context) {
      builds++;
      return _show((
        context.query(_name(name)),
        context.query(_channels(channels)),
      ).combine((name, channels) => '$name x$channels'));
    })));
    expect(find.text('loading'), findsOneWidget);
    await tester.pump();
    expect(find.text('BR64 x4'), findsOneWidget);

    final settled = builds;
    client.setQueryData<int>(channels, 8);
    await tester.pump();
    expect(find.text('BR64 x8'), findsOneWidget);
    expect(builds, settled + 1);
  });

  queryWidgetTest('a source that fails with nothing to show is the error',
      (tester, client) async {
    await tester.pumpWidget(app(
        client,
        Builder(
            builder: (context) => _show((
                  context.query(_name(QueryKey(const ['name']))),
                  context.query(
                      _channels(QueryKey(const ['channels']), fail: true)),
                ).combine((name, channels) => '$name x$channels')))));
    await tester.pump();
    expect(find.textContaining('failed: Bad state: down'), findsOneWidget);
  });

  queryWidgetTest('two controllers combine under Listenable.merge',
      (tester, client) async {
    final name = QueryController<String, String>(
        client, _name(QueryKey(const ['name'])));
    final channels = QueryController<int, int>(
        client, _channels(QueryKey(const ['channels'])));
    addTearDown(name.dispose);
    addTearDown(channels.dispose);
    await tester.pumpWidget(app(
        client,
        ListenableBuilder(
          listenable: Listenable.merge([name, channels]),
          builder: (context, _) => _show((name.value, channels.value)
              .combine((name, channels) => '$name x$channels')),
        )));
    expect(find.text('loading'), findsOneWidget);
    await tester.pump();
    expect(find.text('BR64 x4'), findsOneWidget);
  });
}
