/// Port-only: the small additions the first integration asked for (#85) —
/// `QueryState.consecutiveErrorCount` and a typed mutation-state selection.
library;

import 'dart:async';

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  testFakeAsync(
      'consecutiveErrorCount counts failed fetches in a row, resets with '
      'fetched data, and can stop a poll', (time) async {
    final client = testClient();
    final key = queryKey();
    const second = Duration(seconds: 1);
    var failing = false;
    var fetches = 0;
    final observer = QueryObserver<int, int>(
        client,
        QueryObserverOptions(
          queryKey: key,
          retry: RetryPolicy.never,
          refetchInterval: RefetchInterval.dynamic((query) =>
              query.state.consecutiveErrorCount >= 3 ? null : second),
          queryFn: (_) async =>
              failing ? throw StateError('down ${++fetches}') : ++fetches,
        ));
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();
    int count() => client.getQueryState<int>(key)!.consecutiveErrorCount;
    expect(count(), 0);

    failing = true;
    await time.advance(second * 2);
    expect(count(), 2);
    failing = false;
    await time.advance(second);
    expect(count(), 0, reason: 'a success in between starts over');

    failing = true;
    await time.advance(second * 10);
    expect(count(), 3);
    expect(fetches, 1 + 2 + 1 + 3,
        reason: 'the poll stopped at three in a row');
    expect(client.getQueryState<int>(key)!.errorUpdateCount, 5);

    // Data written by hand is a guess, not an answer from the source: the
    // budget stands (second integration report, C).
    client.setQueryData<int>(key, 0);
    expect(count(), 3);

    unsubscribe();
    client.clear();
  });

  testFakeAsync('each retry is not a consecutive error; the settled fetch is',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final observer = QueryObserver<int, int>(
        client,
        QueryObserverOptions(
          queryKey: key,
          retry: const RetryPolicy.times(2),
          retryDelay: const RetryDelay.fixed(Duration(milliseconds: 1)),
          queryFn: (_) async => throw StateError('down'),
        ));
    final unsubscribe = observer.subscribe((_) {});
    await time.advance(const Duration(milliseconds: 5));
    final state = client.getQueryState<int>(key)!;
    expect(state.fetchFailureCount, 3);
    expect(state.consecutiveErrorCount, 1);
    unsubscribe();
    client.clear();
  });

  testFakeAsync(
      'MutationStateObserver.typed selects the mutations of one type, typed',
      (time) async {
    final client = testClient();
    final gate = Completer<void>();
    final renames = MutationObserver<void, String, void>(client,
        MutationOptions.simple(mutationFn: (String name) => gate.future));
    final toggles = MutationObserver<void, bool, void>(
        client, MutationOptions.simple(mutationFn: (bool on) => gate.future));
    final pendingNames = MutationStateObserver.typed(
      client,
      filters: const MutationFilters(status: MutationStatus.pending),
      select: (Mutation<Object?, String, Object?> mutation) =>
          mutation.state.variables!.toUpperCase(),
    );
    final seen = <List<String>>[];
    final unsubscribe = pendingNames.subscribe(seen.add);

    renames.mutate('kitchen');
    toggles.mutate(true);
    await time.flushMicrotasks();
    expect(pendingNames.currentResult, ['KITCHEN']);

    gate.complete();
    await time.flushMicrotasks();
    expect(pendingNames.currentResult, isEmpty);
    expect(seen.first, ['KITCHEN']);

    unsubscribe();
    renames.destroy();
    toggles.destroy();
    client.clear();
  });

  test('a typed selection keeps the caller\'s own predicate', () {
    final client = testClient();
    final (
      filters,
      _
    ) = typedMutationSelection<Object?, String, Object?, String>(
        MutationFilters(predicate: (_) => false), (m) => m.state.variables!);
    final observer = MutationObserver<void, String, void>(
        client, MutationOptions.simple(mutationFn: (String _) async {}));
    observer.mutate('x');
    expect(client.mutationCache.findAll(filters: filters), isEmpty);
    observer.destroy();
    client.clear();
  });
}
