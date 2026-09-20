/// Regressions from the integrator's second report (BR64, against `87bc25b`).
/// PORTING_NOTES' "Second integration report" says what each one was.
library;

import 'dart:async';

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('A: a memo sees state the combiner captures, through keys', () {
    final client = testClient();
    QueryResult<T> of<T>(T value) {
      final key = queryKey();
      client.setQueryData<T>(key, value);
      return QueryObserver<T, T>(
              client, QueryObserverOptions(queryKey: key, enabled: Enabled.no))
          .currentResult;
    }

    final devices = of<List<String>>(const ['Küche', 'Bad']);
    final status = of<bool>(true);
    final memo = CombineMemo<List<String>>();
    var search = 'k';
    var runs = 0;
    List<String> combineNow() => (devices, status).combine(
          (list, online) {
            runs++;
            return [
              for (final name in list)
                if (name.toLowerCase().contains(search)) name,
            ];
          },
          memo: memo,
          keys: [search],
        ).dataOrNull!;

    expect(combineNow(), ['Küche']);
    expect(combineNow(), ['Küche']);
    expect(runs, 1, reason: 'equal keys, same sources: skipped');
    search = 'b';
    expect(combineNow(), ['Bad']);
    expect(runs, 2);
    client.clear();
  });

  testFakeAsync(
      'B: removing a running mutation lets its request settle, so its signal '
      'is not cancelled; cancel() is what cancels it', (time) async {
    final client = testClient();
    final signals = <QueryCancelToken>[];
    final observer = MutationObserver<int, void, void>(client, MutationOptions(
      mutationFnWithContext: (_, context) {
        signals.add(context.signal);
        return Future.delayed(const Duration(seconds: 1), () => 1);
      },
    ));
    Object? outcome;
    unawaited(observer.mutateAsync(null).then((value) {
      outcome = value;
    }, onError: (Object error) {
      outcome = error;
    }));
    await time.flushMicrotasks();
    client.mutationCache.clear();
    await time.advance(const Duration(seconds: 1));
    expect(outcome, 1, reason: 'the in-flight attempt still settles');
    expect(signals.single.isCancelled, isFalse);
    observer.destroy();
    client.clear();
  });

  testFakeAsync(
      'C: a manual write does not reset consecutiveErrorCount, and a '
      'cancelled fetch does not raise it', (time) async {
    final client = testClient();
    final key = queryKey();
    var hang = false;
    final observer = QueryObserver<int, int>(
        client,
        QueryObserverOptions(
          queryKey: key,
          retry: RetryPolicy.never,
          queryFn: (_) => hang
              ? Completer<int>().future
              : Future<int>.error(StateError('down')),
        ));
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();
    await observer.currentResult.refetch().then((_) {}, onError: (_) {});
    int count() => client.getQueryState<int>(key)!.consecutiveErrorCount;
    expect(count(), 2);

    // An optimistic patch says nothing about the device.
    client.setQueryData<int>(key, 7);
    expect(count(), 2);

    // Nor does a fetch that was cancelled.
    hang = true;
    unawaited(observer.currentResult.refetch().then((_) {}, onError: (_) {}));
    await time.flushMicrotasks();
    await client.cancelQueries(
        filters: QueryFilters(queryKey: key), revert: false);
    expect(client.getQueryState<int>(key)!.error, isA<CancelledError>());
    await time.flushMicrotasks();
    expect(count(), 2);

    unsubscribe();
    client.clear();
  });

  testFakeAsync('MutationOptions.simple takes a function with context',
      (time) async {
    final client = testClient();
    final observer = MutationObserver(
        client,
        MutationOptions.simple(
          mutationFnWithContext: (String name, context) async =>
              '$name ${context.signal.isCancelled}',
        ));
    expect(await observer.mutateAsync('a'), 'a false');
    observer.destroy();
    client.clear();
  });

  group('D: structural sharing and a value class that wraps a list', () {
    final before = _Devices([for (var i = 0; i < 25; i++) _Device(i, 'd$i')]);
    _Devices refetched({int? renamed}) => _Devices([
          for (var i = 0; i < 25; i++)
            _Device(i, i == renamed ? 'renamed' : 'd$i'),
        ]);
    int kept(_PlainDevices a, _PlainDevices b) => [
          for (var i = 0; i < 25; i++)
            if (identical(a.items[i], b.items[i])) i,
        ].length;

    test('a plain value class is a leaf: one changed element renews all', () {
      final plain = _PlainDevices(before.items);
      final next = _PlainDevices(refetched(renamed: 3).items);
      final shared = replaceEqualDeep<_PlainDevices>(plain, next);
      expect(shared, same(next));
      expect(kept(plain, shared), 0);
    });

    test('a StructurallyShareable is walked: 24 of 25 instances survive', () {
      final next = refetched(renamed: 3);
      final shared = replaceEqualDeep<_Devices>(before, next);
      expect(shared, isNot(same(before)));
      expect(kept(before, shared), 24);
      expect(shared.items[3].name, 'renamed');
    });

    test('an equal one is still shared whole, without asking it', () {
      final next = refetched();
      expect(replaceEqualDeep<_Devices>(before, next), same(before));
    });

    test('it is walked inside a list and through the cache too', () {
      final client = testClient();
      final key = queryKey();
      client
        ..setQueryData<List<_Devices>>(key, [before])
        ..setQueryData<List<_Devices>>(key, [refetched(renamed: 3)]);
      final cached = client.getQueryData<List<_Devices>>(key)!.single;
      expect(kept(before, cached), 24);
      client.clear();
    });

    test('a shareWith that returns stale data is an assertion in debug', () {
      expect(() => replaceEqualDeep<_Stale>(_Stale(1), _Stale(2)),
          throwsA(isA<AssertionError>()));
    });

    test('a shareWith that throws or returns the wrong type is ignored', () {
      final next = _Broken(1);
      expect(replaceEqualDeep<_Broken>(_Broken(2), next), same(next));
    });
  });
}

class _Device {
  const _Device(this.id, this.name);
  final int id;
  final String name;
  @override
  bool operator ==(Object other) =>
      other is _Device && other.id == id && other.name == name;
  @override
  int get hashCode => Object.hash(id, name);
}

class _PlainDevices {
  const _PlainDevices(this.items);
  final List<_Device> items;
  @override
  bool operator ==(Object other) =>
      other is _PlainDevices &&
      other.items.length == items.length &&
      [for (var i = 0; i < items.length; i++) other.items[i] == items[i]]
          .every((equal) => equal);
  @override
  int get hashCode => Object.hashAll(items);
}

class _Devices extends _PlainDevices
    implements StructurallyShareable<_Devices> {
  const _Devices(super.items);
  @override
  _Devices shareWith(_Devices previous) =>
      _Devices(replaceEqualDeep<List<_Device>>(previous.items, items));
}

class _Stale implements StructurallyShareable<_Stale> {
  _Stale(this.value);
  final int value;
  @override
  _Stale shareWith(_Stale previous) => previous;
}

class _Broken implements StructurallyShareable<_Broken> {
  _Broken(this.value);
  final int value;
  @override
  _Broken shareWith(_Broken previous) => throw StateError('no');
}
