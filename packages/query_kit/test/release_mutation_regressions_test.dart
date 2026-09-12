import 'dart:async';
import 'dart:collection';
import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';
import 'test_utils.dart';

void main() {
  testFakeAsync('MU1 earlier-built scope mutation starts concurrently',
      (time) async {
    final client = testClient();
    final gates = [Completer<int>(), Completer<int>()];
    final started = <int>[];
    Mutation<int, int, void> build() => client.mutationCache.build(
        client,
        client.defaultMutationOptions(MutationOptions<int, int, void>(
            scope: const MutationScope('s'),
            mutationFn: (v) {
              started.add(v);
              return gates[v].future;
            })));
    final a = build();
    final b = build();
    final bf = b.execute(1);
    await time.flushMicrotasks();
    final af = a.execute(0);
    await time.flushMicrotasks();
    expect(started, [1], reason: '0 must wait until 1 settles');
    gates[1].complete(1);
    gates[0].complete(0);
    await Future.wait([af, bf]);
    client.clear();
  });

  testFakeAsync('MU2 MutationAdded reentrancy misroutes per-call callbacks',
      (time) async {
    final client = testClient();
    final called = <String>[];
    final observer = MutationObserver<int, int, void>(
        client, MutationOptions(mutationFn: (v) => v));
    observer.subscribe((_) {});
    var reentered = false;
    final unsub = client.mutationCache.subscribe((event) {
      if (event is MutationAdded && !reentered) {
        reentered = true;
        observer.mutate(2,
            callbacks: MutateCallbacks(
                onSuccess: (d, v, c) => called.add('inner:$d:$v')));
      }
    });
    await observer.mutateAsync(1,
        callbacks:
            MutateCallbacks(onSuccess: (d, v, c) => called.add('outer:$d:$v')));
    await time.flushMicrotasks();
    expect(called, ['inner:2:2']);
    expect(observer.currentResult.variables, 2);
    expect(
        client.mutationCache.mutations.map((m) => m.observers.length), [0, 1]);
    unsub();
    observer.destroy();
    await time.advance(const Duration(minutes: 6));
    expect(client.mutationCache.mutations, isEmpty);
    client.clear();
  });

  testFakeAsync(
      'MU3 networkMode update causes resume to await unresumable retryer',
      (time) async {
    final client = testClient();
    client.onlineManager.setOnline(false);
    final observer = MutationObserver<int, int, void>(client,
        MutationOptions(mutationFn: (v) => v, networkMode: NetworkMode.online));
    final future = observer.mutateAsync(1);
    future.ignore();
    await time.flushMicrotasks();
    observer.setOptions(
        MutationOptions(mutationFn: (v) => v, networkMode: NetworkMode.always));
    var resumed = false;
    unawaited(client.resumePausedMutations().then((_) => resumed = true));
    await time.flushMicrotasks();
    expect(resumed, true);
    expect(observer.currentResult.isPaused, true);
    client.onlineManager.setOnline(true);
    await client.resumePausedMutations();
    await future;
    observer.destroy();
    client.clear();
  });

  testFakeAsync('MU4 duplicate add leaves destroyed mutation cached after GC',
      (time) async {
    final client = testClient();
    final m = client.mutationCache.build(
        client,
        client.defaultMutationOptions(MutationOptions<int, int, void>(
            gcTime: GcTime.duration(ms(1)), mutationFn: (v) => v)));
    client.mutationCache.add(m);
    await m.execute(1);
    await time.advance(ms(10));
    expect(client.mutationCache.mutations, isEmpty);
    await time.advance(const Duration(days: 1));
    expect(client.mutationCache.mutations, isEmpty);
    client.clear();
  });

  testFakeAsync(
      'MU5 mutation selection emits old snapshot after reentrant clear',
      (time) async {
    final client = testClient();
    final observer = MutationStateObserver<int>(client, select: (_) => 1);
    observer.subscribe((result) {
      if (result.isNotEmpty) client.mutationCache.clear();
    });
    final received = <List<int>>[];
    observer.subscribe(received.add);
    client.mutationCache.build(
        client,
        client.defaultMutationOptions(
            MutationOptions<int, int, void>(mutationFn: (v) => v)));
    expect(observer.currentResult, isEmpty);
    expect(received, [<int>[]]);
    observer.destroy();
    client.clear();
  });

  testFakeAsync('MU6 retry options update ignored by active retryer',
      (time) async {
    final client = testClient();
    var attempts = 0;
    final first = Completer<int>();
    final observer = MutationObserver<int, int, void>(
        client,
        MutationOptions(
            mutationFn: (v) {
              attempts++;
              return first.future;
            },
            retry: RetryPolicy.never));
    final f = observer.mutateAsync(1);
    f.ignore();
    observer.setOptions(MutationOptions(
        mutationFn: (v) {
          attempts++;
          return v;
        },
        retry: const RetryTimes(1),
        retryDelay: RetryDelay.fixed(Duration.zero)));
    first.completeError(StateError('first'));
    await time.flushMicrotasks();
    expect(attempts, 1);
    expect(observer.currentResult.isError, true);
    observer.destroy();
    client.clear();
  });

  testFakeAsync('MU8 scope overlap uses only observer and cache subscriptions',
      (time) async {
    final client = testClient();
    final gate = Completer<int>();
    final started = <int>[];
    final options = MutationOptions<int, int, void>(
        scope: const MutationScope('record'),
        mutationFn: (v) {
          started.add(v);
          return gate.future;
        });
    final a = MutationObserver<int, int, void>(client, options);
    final b = MutationObserver<int, int, void>(client, options);
    var fired = false;
    final unsub = client.mutationCache.subscribe((event) {
      if (event is MutationAdded && !fired) {
        fired = true;
        b.mutate(2);
      }
    });
    final future = a.mutateAsync(1);
    await time.flushMicrotasks();
    expect(started, [2],
        reason: 'the outer transport must wait for the inner one');
    gate.complete(1);
    await future;
    await time.flushMicrotasks();
    unsub();
    a.destroy();
    b.destroy();
    client.clear();
  });

  testFakeAsync(
      'MU9 restored null variables bypass validation and strand pause',
      (time) async {
    final client = testClient();
    expect(
        () => client.mutationCache.build<int, int, void>(
            client,
            client.defaultMutationOptions(
                MutationOptions<int, int, void>(mutationFn: (v) => v)),
            state: const MutationState<int, int, void>(
                status: MutationStatus.pending,
                hasVariables: true,
                isPaused: true)),
        throwsArgumentError);
    await client.resumePausedMutations();
    expect(client.mutationCache.mutations, isEmpty);
    client.clear();
  });

  testFakeAsync(
      'MU10 mutation key supports immutable nested multisets and prefixes',
      (time) async {
    final inner = <int>[1];
    final map = <String, Object?>{'id': 1, 'tags': inner};
    final key = QueryKey(['items', map]);
    final initialHash = key.hashCode;
    inner.add(2);
    map['id'] = 2;
    expect(
        key,
        QueryKey([
          'items',
          {
            'tags': [1],
            'id': 1
          }
        ]));
    expect(key.hashCode, initialHash);
    expect(
        key.matches(QueryKey([
          'items',
          {'id': 1.0}
        ])),
        true);
    expect(
        key.matches(QueryKey([
          'items',
          {'missing': null}
        ])),
        false);
    final one = QueryKey([
      {
        [1],
        [1],
        [2]
      }
    ]);
    final two = QueryKey([
      {
        [2],
        [1],
        [1]
      }
    ]);
    final three = QueryKey([
      {
        [1],
        [2],
        [2]
      }
    ]);
    expect(one, two);
    expect(one.hashCode, two.hashCode);
    expect(one == three, false);
    expect(() => (key.parts[1] as Map)['id'] = 3, throwsUnsupportedError);
  });

  testFakeAsync('MU11 structural sharing retains valid runtime types',
      (time) async {
    expect(replaceEqualDeep<double>(1, 1.0), isA<double>());
    final doubles = replaceEqualDeep<List<double>>(<int>[1], <double>[1.0]);
    expect(doubles, isA<List<double>>());
    expect(doubles.single, isA<double>());
    final nested = replaceEqualDeep<List<List<double>>>(<List<int>>[
      [1]
    ], <List<double>>[
      [1.0]
    ]);
    expect(nested.single.single, isA<double>());
    final view = UnmodifiableListView<int>([2]);
    expect(replaceEqualDeep<UnmodifiableListView<int>>([1], view), same(view));
    final nulls = <String, int?>{'a': null};
    expect(replaceEqualDeep<Map<String, int?>>(nulls, {'b': null}),
        isNot(same(nulls)));
    expect(
        replaceEqualDeep<Map<String, int?>>(nulls, {'a': null}), same(nulls));
  });

  testFakeAsync(
      'MU12 ordinary scope optimistic contexts await settled callback',
      (time) async {
    final client = testClient();
    final calls = <String>[];
    final transport = Completer<int>();
    final settled = Completer<void>();
    final a = MutationObserver<int, int, String>(
        client,
        MutationOptions(
            scope: const MutationScope('s'),
            onMutate: (v) {
              calls.add('optimistic:$v');
              return 'context:$v';
            },
            mutationFn: (v) {
              calls.add('transport:$v');
              return transport.future;
            },
            onSettled: (d, e, s, v, c) {
              calls.add('settled:$c');
              return settled.future;
            }));
    final b = MutationObserver<int, int, String>(
        client,
        MutationOptions(
            scope: const MutationScope('s'),
            onMutate: (v) {
              calls.add('optimistic:$v');
              return 'context:$v';
            },
            mutationFn: (v) {
              calls.add('transport:$v');
              return v;
            }));
    final af = a.mutateAsync(1);
    final bf = b.mutateAsync(2);
    await time.flushMicrotasks();
    expect(calls, ['optimistic:1', 'transport:1', 'optimistic:2']);
    transport.complete(1);
    await time.flushMicrotasks();
    expect(calls.last, 'settled:context:1');
    expect(b.currentResult.isPaused, true);
    settled.complete();
    await Future.wait([af, bf]);
    expect(calls.last, 'transport:2');
    a.destroy();
    b.destroy();
    client.clear();
  });
}
