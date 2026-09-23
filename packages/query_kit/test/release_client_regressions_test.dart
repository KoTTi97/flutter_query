/// Regressions from the release review of 2026-09-23 — the client, the keys
/// and the managers. PORTING_NOTES' "Release review 2026-09-23 — client, keys
/// and mutations" has one row per finding.
library;

import 'dart:async';

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

final class _HashOnly {
  const _HashOnly(this.value);
  final int value;

  // Overrides `hashCode` and not `==`: never equal to a second instance.
  @override
  // ignore: hash_and_equals
  int get hashCode => value.hashCode;
}

void main() {
  testFakeAsync(
      'L5-1 updateQueryData and updateQueriesData accept what setQueryData '
      'accepts', (time) async {
    final client = testClient();
    final key = QueryKey(['k']);
    client.setQueryData<String?>(key, 'a');
    expect(client.setQueryData(key, 'b'), 'b');
    // The updater's parameter infers `String`; the entry is `String?`.
    expect(client.updateQueryData(key, (String? old) => '${old}c'), 'bc');
    expect(client.getQueryData<String?>(key), 'bc');
    expect(client.queryCache.peek(key)!.dataType, _typeOf<String?>());

    client.setQueryData<String?>(QueryKey(['k', 2]), 'x');
    final written = client.updateQueriesData<String>(
      (old) => '$old!',
      filters: QueryFilters(queryKey: key),
    );
    expect(written, [
      (key, 'bc!'),
      (QueryKey(['k', 2]), 'x!')
    ]);

    // Held data the updater cannot see as its type is still refused, before
    // anything is written.
    client.setQueryData<int>(QueryKey(['k', 3]), 1);
    expect(
      () => client.updateQueriesData<String>(
        (old) => 'y',
        filters: QueryFilters(queryKey: key),
      ),
      throwsA(isA<QueryDataTypeError>()),
    );
    expect(client.getQueryData<String?>(key), 'bc!');
    expect(
      () => client.updateQueryData(QueryKey(['k', 3]), (String? old) => 'z'),
      throwsA(isA<QueryDataTypeError>()),
    );

    // An entry with no data yet that cannot hold the updater's value: refused
    // before anything is written, not half-way through the batch.
    client.queryCache.build<int>(
      client,
      client.defaultQueryOptions(QueryOptions<int>(queryKey: QueryKey(['m']))),
    );
    client.setQueryData<String?>(QueryKey(['m', 1]), 'p');
    expect(
      () => client.updateQueriesData<String>(
        (old) => 'q',
        filters: QueryFilters(queryKey: QueryKey(['m'])),
      ),
      throwsA(isA<QueryDataTypeError>()),
    );
    expect(client.getQueryData<String?>(QueryKey(['m', 1])), 'p');

    // The error's cure names no particular method.
    final error = QueryDataTypeError(key, String, _typeOf<String?>());
    expect('$error', isNot(contains('setQueryData')));
    expect('$error', contains('<String?>'));
    client.clear();
  });

  testFakeAsync(
      'L5-2 a bare setQueryData(key, null) writes nothing, as upstream\'s '
      'undefined', (time) async {
    final client = testClient();
    final key = QueryKey(['k']);
    client.setQueryData<String?>(key, 'a');
    expect(client.setQueryData(key, null), isNull);
    expect(client.getQueryData<String?>(key), 'a');

    final fresh = QueryKey(['fresh']);
    client.setQueryData(fresh, null);
    expect(client.queryCache.peek(fresh), isNull);
    // Typed readers of the key are not poisoned by a Query<Null>.
    expect(client.getQueryData<String>(fresh), isNull);

    // A deliberate null write is still spelled with the nullable type.
    client.setQueryData<String?>(key, null);
    expect(client.getQueryState<String?>(key)!.hasData, isTrue);
    expect(client.getQueryData<String?>(key), isNull);
    client.clear();
  });

  testFakeAsync(
      'CORE-3 the setQueryData write-through path returns the stored, shared '
      'value', (time) async {
    final client = testClient();
    final key = queryKey();
    client.setQueryData<List<int>?>(key, <int>[1, 2]);
    final cached = client.getQueryData<List<int>?>(key);
    // Inferred `List<int>` against a `List<int>?` entry: the write-through.
    final returned = client.setQueryData(key, <int>[1, 2]);
    expect(identical(client.getQueryData<List<int>?>(key), cached), isTrue);
    expect(identical(returned, cached), isTrue);

    // A kept instance that is not a `TQueryData` — a `List<Object>` for a
    // `List<int>` write — cannot be returned as one: the argument comes back,
    // equal to what is stored.
    final wideKey = queryKey();
    client.setQueryData<List<Object>?>(wideKey, <Object>[1, 2]);
    final wide = client.getQueryData<List<Object>?>(wideKey);
    final narrow = <int>[1, 2];
    // Assigned first: inside `identical(…)` the type argument would infer
    // `Object?` from the context, and the kept instance is one of those.
    final List<int> written = client.setQueryData(wideKey, narrow);
    expect(identical(written, narrow), isTrue);
    expect(
        identical(client.getQueryData<List<Object>?>(wideKey), wide), isTrue);
    client.clear();
  });

  group('L5-3', () {
    test('a map key with value equality is accepted, a collection refused', () {
      expect(
          () => QueryKey([
                {(1, 2): 'a'}
              ]),
          returnsNormally);
      expect(
          QueryKey([
            {(1, 2): 'a'}
          ]),
          QueryKey([
            {(1, 2): 'a'}
          ]));
      expect(
        () => QueryKey([
          {
            [1]: 'a'
          }
        ]),
        throwsA(isA<AssertionError>()
            .having((e) => '${e.message}', 'message', contains('collection'))),
      );
    });

    test('records holding collections are documented, not caught', () {
      // A record is a leaf compared with its own `==`, which compares a list
      // field by identity. Dart cannot walk a record's fields generically, so
      // the assertion cannot see it; the class dartdoc says so.
      expect(QueryKey([(1, 2)]), QueryKey([(1, 2)]));
      expect(
          QueryKey([
                (1, [2])
              ]) ==
              QueryKey([
                (1, [2])
              ]),
          isFalse);
      // Nor a class overriding `hashCode` without `==`.
      expect(() => QueryKey([const _HashOnly(1)]), returnsNormally);
    });

    test('S3 a UTC and a local DateTime of the same instant are one key', () {
      final instant = DateTime.utc(2026, 9, 23, 12);
      final local = instant.toLocal();
      expect(QueryKey(['day', instant]), QueryKey(['day', local]));
      expect(QueryKey(['day', instant]).hashCode,
          QueryKey(['day', local]).hashCode);
      expect(
          QueryKey([
            'day',
            {'at': local}
          ]).matches(QueryKey([
            'day',
            {'at': instant}
          ])),
          isTrue);
      // The parts keep what was passed.
      expect(QueryKey(['day', local]).parts[1], same(local));
    });
  });

  testFakeAsync(
      'L5-4 isFetching and isMutating override the caller\'s status filter',
      (time) async {
    final client = testClient();
    final gate = Completer<int>();
    client
        .query(QueryOptions<int>(
            queryKey: QueryKey(['f']), queryFn: (_) => gate.future))
        .ignore();
    final mutationGate = Completer<int>();
    final mutation = MutationObserver<int, int, void>(
        client, MutationOptions(mutationFn: (_) => mutationGate.future));
    mutation.mutate(1);
    await time.flushMicrotasks();
    expect(
        client.isFetching(
            filters: const QueryFilters(fetchStatus: FetchStatus.idle)),
        1);
    expect(
        client.isMutating(
            filters: const MutationFilters(status: MutationStatus.success)),
        1);
    gate.complete(1);
    mutationGate.complete(1);
    await time.flushMicrotasks();
    mutation.destroy();
    client.clear();
  });

  testFakeAsyncGuarded(
      'S1 a focus or online setup that throws on reinstall does not leak the '
      'subscribing listener', (time, uncaught) async {
    var focusInstalls = 0;
    final focus = AppFocusManager()
      ..setEventListener((_) {
        if (++focusInstalls > 1) throw StateError('focus');
        return () {};
      });
    focus.subscribe((_) {})();
    expect(focus.hasListeners, isFalse);
    // The reinstall throws; the handle still comes back and removes.
    final focusHandle = focus.subscribe((_) {});
    expect(focus.hasListeners, isTrue);
    focusHandle();
    expect(focus.hasListeners, isFalse);

    var onlineInstalls = 0;
    final online = OnlineManager()
      ..setEventListener((_) {
        if (++onlineInstalls > 1) throw StateError('online');
        return () {};
      });
    online.subscribe((_) {})();
    final onlineHandle = online.subscribe((_) {});
    expect(online.hasListeners, isTrue);
    onlineHandle();
    expect(online.hasListeners, isFalse);

    expect(uncaught, [isA<StateError>(), isA<StateError>()]);
  });
}

Type _typeOf<T>() => T;
