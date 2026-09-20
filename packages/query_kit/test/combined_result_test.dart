/// Port-only: `combine` over a record of results (#82). Upstream's
/// `useQueries({combine})` cases are omitted with the option itself; these
/// pin the Dart shape that stands in for it.
library;

import 'dart:async';

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  testFakeAsync('pending until every source has data, then the combiner runs',
      (time) async {
    final client = testClient();
    final names = QueryObserver<List<String>, List<String>>(
        client,
        QueryObserverOptions(
            queryKey: queryKey(),
            queryFn: (_) => Future.delayed(
                const Duration(milliseconds: 10), () => ['a', 'b'])));
    final count = QueryObserver<int, int>(
        client,
        QueryObserverOptions(
            queryKey: queryKey(),
            queryFn: (_) =>
                Future.delayed(const Duration(milliseconds: 20), () => 2)));
    final unsubscribe = [names.subscribe((_) {}), count.subscribe((_) {})];

    CombinedResult<String> read() => (names.currentResult, count.currentResult)
        .combine((names, count) => '${names.join()}$count');

    expect(read(), isA<CombinedPending<String>>());
    expect(read().isFetching, isTrue);
    await time.advance(const Duration(milliseconds: 10));
    expect(read().isPending, isTrue, reason: 'one of two is not enough');
    await time.advance(const Duration(milliseconds: 10));
    final done = read();
    expect(done, isA<CombinedData<String>>());
    expect(done.dataOrNull, 'ab2');
    expect(done.isFetching, isFalse);
    expect(read(), done, reason: 'value equality, for a buildWhen');

    for (final u in unsubscribe) {
      u();
    }
    client.clear();
  });

  testFakeAsync(
      'a loading error wins over a pending source; retry refetches only the '
      'failed one', (time) async {
    final client = testClient();
    var failing = true;
    var goodFetches = 0;
    final bad = QueryObserver<int, int>(
        client,
        QueryObserverOptions(
            queryKey: queryKey(),
            retry: RetryPolicy.never,
            queryFn: (_) async => failing ? throw StateError('down') : 1));
    final good = QueryObserver<int, int>(
        client,
        QueryObserverOptions(
            queryKey: queryKey(),
            queryFn: (_) {
              goodFetches++;
              return Future.delayed(const Duration(milliseconds: 50), () => 2);
            }));
    final unsubscribe = [bad.subscribe((_) {}), good.subscribe((_) {})];
    CombinedResult<int> read() =>
        (bad.currentResult, good.currentResult).combine((a, b) => a + b);

    await time.flushMicrotasks();
    final failed = read();
    expect(failed, isA<CombinedError<int>>());
    expect((failed as CombinedError<int>).error, isStateError);
    expect(failed.isFetching, isTrue, reason: 'the other is still loading');

    await time.advance(const Duration(milliseconds: 50));
    failing = false;
    unawaited(read().retry());
    await time.flushMicrotasks();
    expect(read().dataOrNull, 3);
    expect(goodFetches, 1, reason: 'retry left the healthy source alone');

    for (final u in unsubscribe) {
      u();
    }
    client.clear();
  });

  testFakeAsync(
      'a failed refetch keeps the combined data and reports refetchError',
      (time) async {
    final client = testClient();
    var failing = false;
    final flaky = QueryObserver<int, int>(
        client,
        QueryObserverOptions(
            queryKey: queryKey(),
            retry: RetryPolicy.never,
            queryFn: (_) async => failing ? throw StateError('down') : 1));
    final steady = QueryObserver<int?, int?>(client,
        QueryObserverOptions(queryKey: queryKey(), queryFn: (_) => null));
    final unsubscribe = [flaky.subscribe((_) {}), steady.subscribe((_) {})];
    CombinedResult<String> read() =>
        (flaky.currentResult, steady.currentResult).combine((a, b) => '$a/$b');

    await time.flushMicrotasks();
    expect(read().dataOrNull, '1/null', reason: 'a null that is data counts');

    failing = true;
    unawaited(read().refetch());
    await time.flushMicrotasks();
    final after = read();
    expect(after, isA<CombinedData<String>>());
    expect(after.dataOrNull, '1/null');
    expect((after as CombinedData<String>).refetchError, isStateError);

    for (final u in unsubscribe) {
      u();
    }
    client.clear();
  });

  testFakeAsync(
      'a memo skips the combiner while the sources hold the same instances, '
      'and shares an equal result', (time) async {
    final client = testClient();
    final a = queryKey();
    final b = queryKey();
    client
      ..setQueryData<List<int>>(a, [1, 2])
      ..setQueryData<int>(b, 10);
    final first = QueryObserver<List<int>, List<int>>(client,
        QueryObserverOptions(queryKey: a, staleTime: StaleTime.infinite));
    final second = QueryObserver<int, int>(client,
        QueryObserverOptions(queryKey: b, staleTime: StaleTime.infinite));
    final unsubscribe = [first.subscribe((_) {}), second.subscribe((_) {})];
    final memo = CombineMemo<List<int>>();
    var runs = 0;
    CombinedResult<List<int>> read() =>
        (first.currentResult, second.currentResult).combine((list, offset) {
          runs++;
          return [for (final item in list) item + offset];
        }, memo: memo);

    final one = read().dataOrNull;
    expect(read().dataOrNull, same(one));
    expect(runs, 1);

    // An equal write is shared by the cache, so the source instance stays.
    client.setQueryData<List<int>>(a, [1, 2]);
    await time.flushMicrotasks();
    expect(read().dataOrNull, same(one));
    expect(runs, 1);

    // A real change runs the combiner again.
    client.setQueryData<int>(b, 20);
    await time.flushMicrotasks();
    expect(read().dataOrNull, [21, 22]);
    expect(runs, 2);

    // Without a memo it runs every time.
    (first.currentResult, second.currentResult).combine((list, offset) {
      runs++;
      return 0;
    });
    expect(runs, 3);
    for (final u in unsubscribe) {
      u();
    }
    client.clear();
  });

  test('every arity from two to six combines', () {
    final client = testClient();
    QueryResult<int> of(int value) {
      final key = queryKey();
      client.setQueryData<int>(key, value);
      return QueryObserver<int, int>(
              client, QueryObserverOptions(queryKey: key, enabled: Enabled.no))
          .currentResult;
    }

    final r = [for (var i = 1; i <= 6; i++) of(i)];
    expect((r[0], r[1]).combine((a, b) => a + b).dataOrNull, 3);
    expect((r[0], r[1], r[2]).combine((a, b, c) => a + b + c).dataOrNull, 6);
    expect(
        (r[0], r[1], r[2], r[3])
            .combine((a, b, c, d) => a + b + c + d)
            .dataOrNull,
        10);
    expect(
        (r[0], r[1], r[2], r[3], r[4])
            .combine((a, b, c, d, e) => a + b + c + d + e)
            .dataOrNull,
        15);
    expect(
        (r[0], r[1], r[2], r[3], r[4], r[5])
            .combine((a, b, c, d, e, f) => a + b + c + d + e + f)
            .dataOrNull,
        21);
    client.clear();
  });

  testFakeAsync(
      'an optional source neither blocks nor fails the combination, is still '
      'seen fetching, and is retried when the query behind it failed',
      (time) async {
    final client = testClient();
    var matterFetches = 0;
    var gatewayHasMatter = false;
    final devices = QueryObserver<List<String>, List<String>>(client,
        QueryObserverOptions(queryKey: queryKey(), queryFn: (_) => ['a']));
    final matter = QueryObserver<List<String>, List<String>>(
        client,
        QueryObserverOptions(
          queryKey: queryKey(),
          retry: RetryPolicy.never,
          queryFn: (_) {
            matterFetches++;
            return Future.delayed(const Duration(milliseconds: 10),
                () => gatewayHasMatter ? ['m'] : throw StateError('404'));
          },
        ));
    final unsubscribe = [devices.subscribe((_) {}), matter.subscribe((_) {})];
    CombinedResult<String> read() => (
          devices.currentResult,
          matter.currentResult.optional()
        ).combine((devices, matter) => '$devices+$matter');

    await time.flushMicrotasks();
    expect(read().dataOrNull, '[a]+null', reason: 'not waited for');
    expect(read().isFetching, isTrue, reason: 'but seen');

    await time.advance(const Duration(milliseconds: 10));
    expect(read(), isA<CombinedData<String>>(), reason: 'a 404 does not fail');
    expect(read().dataOrNull, '[a]+null');

    gatewayHasMatter = true;
    unawaited(read().retry());
    await time.advance(const Duration(milliseconds: 10));
    expect(matterFetches, 2);
    expect(read().dataOrNull, '[a]+[m]');
    expect(matter.currentResult.optional(), same(matter.currentResult),
        reason: 'with data it is the result itself');

    for (final u in unsubscribe) {
      u();
    }
    client.clear();
  });

  testFakeAsync('a list of results of one type combines by the same rules',
      (time) async {
    final client = testClient();
    var failing = true;
    final hosts = QueriesObserver<int, int>(client, [
      for (final host in [1, 2, 3])
        QueryObserverOptions(
          queryKey: queryKey(),
          retry: RetryPolicy.never,
          queryFn: (_) => Future.delayed(Duration(milliseconds: host * 10),
              () => host == 2 && failing ? throw StateError('down') : host),
        ),
    ]);
    final unsubscribe = hosts.subscribe((_) {});
    CombinedResult<int> read() => hosts.currentResult
        .combine((values) => values.fold(0, (sum, value) => sum + value));

    await time.advance(const Duration(milliseconds: 10));
    expect(read().isPending, isTrue);
    await time.advance(const Duration(milliseconds: 10));
    expect(read().isError, isTrue, reason: 'a real failure wins over pending');
    await time.advance(const Duration(milliseconds: 10));
    failing = false;
    unawaited(read().retry());
    await time.advance(const Duration(milliseconds: 20));
    expect(read().dataOrNull, 6, reason: 'every value, in order');

    expect(
        <QueryResult<int>>[].combine((values) => values.length).dataOrNull, 0,
        reason: 'an empty list is data');
    unsubscribe();
    hosts.destroy();
    client.clear();
  });

  testFakeAsync(
      'G: a list and the query it was derived from are one combination — the '
      "deriving query's failure is an error, not an empty list", (time) async {
    final client = testClient();
    var adapterDown = true;
    final adapter = QueryObserver<bool, bool>(
        client,
        QueryObserverOptions(
          queryKey: queryKey(),
          retry: RetryPolicy.never,
          queryFn: (_) async => adapterDown ? throw StateError('down') : true,
        ));
    final hosts = QueriesObserver<List<String>, List<String>>(client, [
      for (final host in ['h1', 'h2'])
        QueryObserverOptions(
            queryKey: queryKey(), queryFn: (_) async => ['$host-c']),
    ]);
    final unsubscribe = [adapter.subscribe((_) {}), hosts.subscribe((_) {})];
    CombinedResult<List<String>> read() => hosts.currentResult.combineWith(
        adapter.currentResult,
        (details, available) => available
            ? [for (final controllers in details) ...controllers]
            : const []);

    await time.flushMicrotasks();
    expect(read(), isA<CombinedError<List<String>>>());

    adapterDown = false;
    unawaited(read().retry());
    await time.flushMicrotasks();
    expect(read().dataOrNull, ['h1-c', 'h2-c']);

    // With no hosts at all the other source still decides.
    expect(
        <QueryResult<int>>[]
            .combineWith(adapter.currentResult, (values, ok) => ok)
            .dataOrNull,
        isTrue);
    expect(
        [hosts.currentResult.first]
            .combineWith2(adapter.currentResult, adapter.currentResult,
                (values, a, b) => values.single.single)
            .dataOrNull,
        'h1-c');

    for (final u in unsubscribe) {
      u();
    }
    hosts.destroy();
    client.clear();
  });
}
