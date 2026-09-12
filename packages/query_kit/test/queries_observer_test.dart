/// Applicable cases from upstream queriesObserver.test.tsx at 50680b98c.
/// See PORTING_NOTES for API adaptations and omitted combine/suspense cases.
library;

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  late QueryClient client;
  late QueryObserverOptions<int> first;
  late QueryObserverOptions<int> second;

  void observerTest(String name, Future<void> Function(FakeTime) body) {
    testFakeAsync(name, (time) async {
      client = testClient()..mount();
      first = QueryObserverOptions(queryKey: queryKey(), queryFn: (_) => 1);
      second = QueryObserverOptions(queryKey: queryKey(), queryFn: (_) => 2);
      try {
        await body(time);
      } finally {
        client.unmount();
        client.clear();
      }
    });
  }

  List<int?> data(List<QueryResult<int>> results) =>
      results.map((r) => r.dataOrNull).toList();

  /// One `status/fetchStatus/data` string per result, so a whole sequence of
  /// snapshots reads as data in the failure message.
  List<List<String>> snapshots(List<List<QueryResult<int>>> sequence) =>
      sequence
          .map((results) => results
              .map((r) =>
                  '${r.status.name}/${r.fetchStatus.name}/${r.dataOrNull}')
              .toList())
          .toList();

  observerTest('should return an array with all query results', (time) async {
    final observer = QueriesObserver<int, int>(client, [first, second]);
    List<QueryResult<int>>? result;
    final unsubscribe = observer.subscribe((next) => result = next);
    await time.flushMicrotasks();
    unsubscribe();
    expect(data(result!), [1, 2]);
  });

  observerTest('should return current queries via getQueries', (time) async {
    final observer = QueriesObserver<int, int>(client, [first, second]);
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();
    expect(observer.observers.map((o) => o.currentQuery.queryKey),
        [first.queryKey, second.queryKey]);
    unsubscribe();
  });

  observerTest('should update when a query updates', (time) async {
    final observer = QueriesObserver<int, int>(client, [first, second]);
    final results = [observer.currentResult];
    final unsubscribe = observer.subscribe(results.add);
    await time.flushMicrotasks();
    client.setQueryData(second.queryKey, 3);
    unsubscribe();
    expect(results.length, 6);
    expect(results.map(data), [
      [null, null],
      [null, null],
      [null, null],
      [1, null],
      [1, 2],
      [1, 3]
    ]);
    expect(results.take(3).map((rs) => rs.map((r) => r.fetchStatus).toList()), [
      [FetchStatus.idle, FetchStatus.idle],
      [FetchStatus.fetching, FetchStatus.idle],
      [FetchStatus.fetching, FetchStatus.fetching],
    ]);
  });

  observerTest('should return current observers via getObservers',
      (time) async {
    final observer = QueriesObserver<int, int>(client, [first, second]);
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();
    expect(observer.observers, hasLength(2));
    expect(observer.observers, everyElement(isA<QueryObserver<int, int>>()));
    unsubscribe();
  });

  observerTest('should update when a query is removed', (time) async {
    final observer = QueriesObserver<int, int>(client, [first, second]);
    final results = [observer.currentResult];
    final unsubscribe = observer.subscribe(results.add);
    await time.flushMicrotasks();
    observer.setQueries([second]);
    expect(client.queryCache.get<int>(first.queryKey)!.isActive(), isFalse);
    expect(client.queryCache.get<int>(second.queryKey)!.isActive(), isTrue);
    expect(results.length, 6);
    expect(data(results.last), [2]);
    unsubscribe();
    expect(client.queryCache.get<int>(second.queryKey)!.isActive(), isFalse);
  });

  observerTest('should update when a query changed position', (time) async {
    final observer = QueriesObserver<int, int>(client, [first, second]);
    final results = [observer.currentResult];
    final unsubscribe = observer.subscribe(results.add);
    await time.flushMicrotasks();
    final previous = observer.observers;
    observer.setQueries([second, first]);
    unsubscribe();
    expect(results.length, 6);
    expect(data(results.last), [2, 1]);
    expect(observer.observers, [previous[1], previous[0]]);
  });

  observerTest('should not update when nothing has changed', (time) async {
    final observer = QueriesObserver<int, int>(client, [first, second]);
    final results = [observer.currentResult];
    final unsubscribe = observer.subscribe(results.add);
    await time.flushMicrotasks();
    final before = observer.currentResult;
    observer.setQueries([first.copyWith(), second.copyWith()]);
    unsubscribe();
    expect(results.length, 5);
    expect(observer.currentResult, same(before));
  });

  observerTest('should trigger all fetches when subscribed', (time) async {
    var calls1 = 0;
    var calls2 = 0;
    final observer = QueriesObserver<int, int>(client, [
      first.copyWith(queryFn: (_) {
        calls1++;
        return 1;
      }),
      second.copyWith(queryFn: (_) {
        calls2++;
        return 2;
      }),
    ]);
    expect(calls1 + calls2, 0);
    observer.subscribe((_) {})();
    expect(calls1, 1);
    expect(calls2, 1);
  });

  observerTest(
      'should not destroy the observer if there is still a subscription',
      (time) async {
    final observer = QueriesObserver<int, int>(client, [
      first.copyWith(queryFn: (_) => sleep(ms(20)).then((_) => 1)),
    ]);
    var calls1 = 0;
    var calls2 = 0;
    final unsubscribe1 = observer.subscribe((_) => calls1++);
    final unsubscribe2 = observer.subscribe((_) => calls2++);
    unsubscribe1();
    await time.advance(ms(20));
    expect(calls1, 1);
    expect(calls2, 1);
    unsubscribe2();
  });

  observerTest('should handle duplicate query keys in different positions',
      (time) async {
    var calls1 = 0;
    var calls2 = 0;
    final a = first.copyWith(queryFn: (_) {
      calls1++;
      return 1;
    });
    final b = second.copyWith(queryFn: (_) {
      calls2++;
      return 2;
    });
    final observer = QueriesObserver<int, int>(client, [a, b, a]);
    final results = [observer.currentResult];
    final unsubscribe = observer.subscribe(results.add);
    await time.flushMicrotasks();
    // The whole sequence, not just its endpoint. Upstream asserts six
    // results here and the port produces seven — its seed plus six
    // notifications, where upstream's is a seed plus five — because
    // upstream's third occurrence reports `idle` for one notification while
    // the key1 query it shares with the first occurrence is already
    // fetching, and every occurrence here reports its actual fetching state
    // (the divergence row in PORTING_NOTES). Asserting only the final data
    // let a regression anywhere in the duplicate-observer path pass, which
    // is the one path this case exists for (pre-release review, 2026-09-12).
    expect(snapshots(results), [
      ['pending/idle/null', 'pending/idle/null', 'pending/idle/null'],
      ['pending/fetching/null', 'pending/idle/null', 'pending/idle/null'],
      ['pending/fetching/null', 'pending/fetching/null', 'pending/idle/null'],
      [
        'pending/fetching/null',
        'pending/fetching/null',
        'pending/fetching/null'
      ],
      ['success/idle/1', 'pending/fetching/null', 'pending/fetching/null'],
      ['success/idle/1', 'pending/fetching/null', 'success/idle/1'],
      ['success/idle/1', 'success/idle/2', 'success/idle/1'],
    ]);
    expect(data(results.last), [1, 2, 1]);
    expect(
        results.last.every((r) => r.fetchStatus == FetchStatus.idle), isTrue);
    expect(calls1, 1);
    expect(calls2, 1);
    expect(identical(observer.observers[0], observer.observers[2]), isFalse);
    unsubscribe();
  });

  observerTest('should notify when results change during early return',
      (time) async {
    client.setQueryData(first.queryKey, 1);
    client.setQueryData(second.queryKey, 2);
    final observer = QueriesObserver<int, int>(client, [first, second]);
    final results = [observer.currentResult];
    final unsubscribe = observer.subscribe(results.add);
    final baseline = results.length;
    // A select is its own shape (ADR-0001), so a plain `copyWith` cannot add
    // one; the selecting twins are built from the plain options' fields.
    observer.setQueries([
      QuerySelectOptions<int, int>(
          queryKey: first.queryKey,
          queryFn: first.queryFn,
          select: (d) => d + 100),
      QuerySelectOptions<int, int>(
          queryKey: second.queryKey,
          queryFn: second.queryFn,
          select: (d) => d + 100),
    ]);
    await time.flushMicrotasks();
    expect(results.length, greaterThan(baseline));
    expect(data(results.last), [101, 102]);
    unsubscribe();
  });

  observerTest(
      'should subscribe to new observers when a query is added while subscribed',
      (time) async {
    final observer = QueriesObserver<int, int>(client, [first, second]);
    final results = <List<QueryResult<int>>>[];
    final unsubscribe = observer.subscribe(results.add);
    await time.flushMicrotasks();
    expect(data(results.last), [1, 2]);
    observer.setQueries([
      first,
      second,
      QueryObserverOptions(
          queryKey: queryKey(), queryFn: (_) => sleep(ms(10)).then((_) => 3))
    ]);
    await time.advance(ms(10));
    unsubscribe();
    expect(data(results.last), [1, 2, 3]);
  });
}
