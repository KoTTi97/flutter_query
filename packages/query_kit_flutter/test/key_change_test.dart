/// A read whose key changes between builds.
///
/// Upstream's `useQuery` is one observer per call site, so a new key is
/// applied to the observer it already has — and that is what
/// `placeholderData: (previous) => previous` (upstream's `keepPreviousData`)
/// relies on: the observer remembers the last query that had data. Here the
/// mixin and `context.query` identify a read by its key unless it carries an
/// `id`; with an `id`, the observer follows the key. Found by the showcase's
/// `initial-and-placeholder` screen (2026-09-09), which switched a mixin read
/// between two posts and got a skeleton instead of the previous post.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'harness.dart';

QueryKey pageKey(int n) => QueryKey(<Object?>['page', n]);

QueryObserverOptions<String> pageQuery(int n) => QueryObserverOptions(
      queryKey: pageKey(n),
      queryFn: (_) => Future<String>.delayed(
        const Duration(milliseconds: 100),
        () => 'page $n',
      ),
      placeholderData: PlaceholderData.compute((previous, _) => previous),
    );

String describe(QueryResult<String> result) =>
    '${result.dataOrNull ?? 'none'} placeholder=${result.isPlaceholderData}';

class _ContextReader extends StatelessWidget {
  const _ContextReader(this.n, {this.id});

  final int n;
  final Object? id;

  @override
  Widget build(BuildContext context) =>
      Text(describe(context.query(pageQuery(n), id: id)));
}

class _MixinReader extends StatefulWidget {
  const _MixinReader(this.n, {this.id});

  final int n;
  final Object? id;

  @override
  State<_MixinReader> createState() => _MixinReaderState();
}

class _MixinReaderState extends State<_MixinReader> with QueryMixin {
  @override
  Widget build(BuildContext context) =>
      Text(describe(watchQuery(pageQuery(widget.n), id: widget.id)));
}

class _BuilderReader extends StatelessWidget {
  const _BuilderReader(this.n);

  final int n;

  @override
  Widget build(BuildContext context) => QueryBuilder<String>(
        options: pageQuery(n),
        builder: (_, result) => Text(describe(result)),
      );
}

void main() {
  for (final (name, reader) in <(String, Widget Function(int))>[
    ('context.query with an id', (n) => _ContextReader(n, id: 'page')),
    ('QueryMixin.watchQuery with an id', (n) => _MixinReader(n, id: 'page')),
    ('QueryBuilder', _BuilderReader.new),
  ]) {
    queryWidgetTest('$name keeps the previous page while the next one loads',
        (tester, client) async {
      await tester.pumpApp(client, reader(1));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('page 1 placeholder=false'), findsOneWidget);

      await tester.pumpApp(client, reader(2));
      await tester.pump();
      expect(find.text('page 1 placeholder=true'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('page 2 placeholder=false'), findsOneWidget);
      // One observer moved keys; none was left behind on the first.
      expect(
        client.queryCache
            .find(filters: QueryFilters(queryKey: pageKey(1)))!
            .observersCount,
        0,
      );
      expect(
        client.queryCache
            .find(filters: QueryFilters(queryKey: pageKey(2)))!
            .observersCount,
        1,
      );
    });
  }

  for (final (name, reader) in <(String, Widget Function(int))>[
    ('context.query', _ContextReader.new),
    ('QueryMixin.watchQuery', _MixinReader.new),
  ]) {
    queryWidgetTest('$name without an id treats a new key as a new read',
        (tester, client) async {
      await tester.pumpApp(client, reader(1));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      await tester.pumpApp(client, reader(2));
      await tester.pump();
      // A fresh observer has no previous data to show as a placeholder.
      expect(find.text('none placeholder=false'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('page 2 placeholder=false'), findsOneWidget);
    });
  }
}
