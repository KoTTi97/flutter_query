import 'dart:async';
import 'package:query_kit/query_kit.dart';
import 'package:query_kit/src/listener_registry.dart';
import 'package:test/test.dart';
import 'test_utils.dart';

void main() {
  testFakeAsync('direct constructors reject invalid restored payloads',
      (time) async {
    final client = testClient();
    final key = queryKey();
    expect(
        () => Query<int>(
              client: client,
              cache: client.queryCache,
              queryKey: key,
              options:
                  client.defaultQueryOptions(QueryOptions<int>(queryKey: key)),
              state: const QueryState<int>(
                  status: QueryStatus.success, hasData: true),
            ),
        throwsArgumentError);
    expect(
        () => Mutation<int, int, void>(
              client: client,
              cache: client.mutationCache,
              mutationId: 1,
              options: client.defaultMutationOptions(
                  MutationOptions<int, int, void>(
                      mutationFn: (value) => value)),
              state: const MutationState<int, int, void>(
                  status: MutationStatus.pending,
                  isPaused: true,
                  hasVariables: true),
            ),
        throwsArgumentError);
    expect(time.pendingTimers, 0);
    client.clear();
  });

  testFakeAsync('removing an unstarted restored scope head releases its waiter',
      (time) async {
    final client = QueryClient();
    final options = client.defaultMutationOptions<int, int, void>(
      MutationOptions<int, int, void>(
        scope: const MutationScope('record'),
        mutationFn: (value) => value,
      ),
    );
    final restored = client.mutationCache.build(client, options,
        state: const MutationState<int, int, void>(
          status: MutationStatus.pending,
          isPaused: true,
          hasVariables: true,
          variables: 1,
        ));
    final waiter = client.mutationCache.build(client, options);
    var completed = false;
    waiter.execute(2).then((_) => completed = true).ignore();
    await time.flushMicrotasks();
    expect(waiter.state.isPaused, isTrue);
    client.mutationCache.remove(restored);
    await time.flushMicrotasks();
    final status = waiter.state.status;
    client.clear();
    await time.flushMicrotasks();
    expect(completed, isTrue,
        reason: 'The only preceding scope entry is gone.');
    expect(status, MutationStatus.success);
  });

  testFakeAsync('sharing callback cannot overwrite a successor fetch status',
      (time) async {
    final client = QueryClient();
    final key = QueryKey(['sharing-reset']);
    final first = Completer<int>();
    final second = Completer<int>();
    var calls = 0;
    late QueryOptions<int> options;
    Future<int>? successor;
    options = QueryOptions<int>(
      queryKey: key,
      queryFn: (_) => ++calls == 1 ? first.future : second.future,
      structuralSharing: (previous, next) {
        if (next == 1) {
          client.queryCache.get<int>(key)!.reset();
          successor = client.query(options);
        }
        return next;
      },
    );
    final initial = client.query(options);
    first.complete(1);
    await time.flushMicrotasks();
    expect(calls, 2);
    final status = client.getQueryState<int>(key)!.fetchStatus;
    final joiner = client.query(options);
    final callsAfterJoin = calls;
    second.complete(2);
    await initial;
    await successor;
    await joiner;
    client.clear();
    expect(callsAfterJoin, 2,
        reason: 'A third caller must join the still-running successor.');
    expect(status, FetchStatus.fetching,
        reason: 'Successor transport is still pending after reset.');
  });

  testFakeAsync('removal during late initialData prevents removed query fetch',
      (time) async {
    final client = QueryClient();
    final key = QueryKey(['initial-remove']);
    final empty = client.queryCache.build(
        client, client.defaultQueryOptions(QueryOptions<int>(queryKey: key)));
    var calls = 0;
    final operation = client.query(QueryOptions<int>(
      queryKey: key,
      queryFn: (_) => ++calls,
      initialData: InitialData.compute(() {
        client.removeQueries();
        return 0;
      }),
    ));
    operation.ignore();
    await time.flushMicrotasks();
    expect(client.queryCache.queries, isEmpty);
    expect(empty.isRemoved, isTrue);
    expect(calls, 0, reason: 'Removal happened before transport was started.');
  });

  testFakeAsync('reset from mutation reattachment remains authoritative',
      (time) async {
    final client = QueryClient();
    final observer = MutationObserver<int, int, void>(
        client, MutationOptions(mutationFn: (value) => value));
    final unsubscribe = observer.subscribe((_) {});
    await observer.mutateAsync(1);
    unsubscribe();
    final stopCache = client.mutationCache.subscribe((event) {
      if (event is MutationObserverAdded) observer.reset();
    });
    final remove = observer.subscribe((_) {});
    final result = observer.currentResult;
    stopCache();
    remove();
    observer.destroy();
    client.clear();
    expect(result, isA<MutationIdle<int, int>>(),
        reason: 'reset detached this observer during its reattachment event.');
  });

  testFakeAsync('switch disposal cannot attach an observer after destroy',
      (time) async {
    final client = QueryClient();
    final a = QueryKey(['dispose-a']);
    final b = QueryKey(['dispose-b']);
    final observer = client.observe<int, int>(
        QueryObserverOptions(queryKey: a, enabled: Enabled.no));
    final off = observer.subscribe((_) {});
    final offCache = client.queryCache.subscribe((event) {
      if (event is QueryObserverRemoved && event.query.queryKey == a) {
        observer.destroy();
      }
    });
    observer.setOptions(QueryObserverOptions(queryKey: b, enabled: Enabled.no));
    final attached = observer.currentQuery.observers.length;
    offCache();
    observer.destroy();
    off();
    client.clear();
    expect(attached, 0);
  });

  testFakeAsync(
      'placeholder recovers after an abandoned failing selector preview',
      (time) async {
    final client = QueryClient();
    final a = QueryKey(['placeholder-a']);
    final b = QueryKey(['preview-b']);
    int select(int value) => value * 2;
    final options = QuerySelectOptions<int, int>(
        queryKey: a,
        enabled: Enabled.no,
        placeholderData: const PlaceholderData.value(3),
        select: select);
    final observer = client.observe<int, int>(options);
    expect(observer.currentResult.dataOrNull, 6);
    client.setQueryData<int>(b, 9);
    final preview = observer.getOptimisticResult(QuerySelectOptions<int, int>(
        queryKey: b,
        enabled: Enabled.no,
        select: (_) => throw StateError('preview only')));
    expect(preview.isError, isTrue);
    observer.setOptions(options);
    final result = observer.currentResult;
    observer.destroy();
    client.clear();
    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull, 6);
    expect(result.isPlaceholderData, isTrue);
  });

  testFakeAsync(
      'subscription handles distinguish remove and readd during notification',
      (time) async {
    final registry = ListenerRegistry<void Function()>();
    final calls = <String>[];
    late void Function() off;
    void second() => calls.add('second');
    registry.add(() {
      calls.add('first');
      off();
      registry.add(second);
    });
    off = registry.add(second);
    registry.notify((fn) => fn());
    expect(calls, ['first']);
    registry.clear();
    registry.add(second);
    off();
    expect(registry.length, 1);
  });
  testFakeAsync('nested key switch only attaches the final owned query',
      (time) async {
    final client = QueryClient();
    final a = QueryKey(['nested-a']);
    final b = QueryKey(['nested-b']);
    final c = QueryKey(['nested-c']);
    final observer = client.observe<int, int>(
        QueryObserverOptions(queryKey: a, enabled: Enabled.no));
    final off = observer.subscribe((_) {});
    final offCache = client.queryCache.subscribe((event) {
      if (event is QueryObserverRemoved && event.query.queryKey == a) {
        observer
            .setOptions(QueryObserverOptions(queryKey: c, enabled: Enabled.no));
      }
    });
    observer.setOptions(QueryObserverOptions(queryKey: b, enabled: Enabled.no));
    expect(observer.currentQuery.queryKey, c);
    final attachedKeys = client.queryCache
        .findAll()
        .where((q) => q.observers.contains(observer))
        .map((q) => q.queryKey)
        .toList();
    offCache();
    observer.destroy();
    off();
    client.clear();
    expect(attachedKeys, [c]);
  });

  testFakeAsync(
      'same-output previews retain distinct selector input provenance',
      (time) async {
    final client = QueryClient();
    final a = QueryKey(['memo-a']);
    final b = QueryKey(['memo-b']);
    final calls = <int>[];
    int select(int input) {
      calls.add(input);
      return input % 2;
    }

    client.setQueryData<int>(a, 1);
    client.setQueryData<int>(b, 3);
    final options = QuerySelectOptions<int, int>(
        queryKey: a, enabled: Enabled.no, select: select);
    final observer = client.observe<int, int>(options);
    final previewOptions = QuerySelectOptions<int, int>(
        queryKey: b, enabled: Enabled.no, select: select);
    observer.getOptimisticResult(previewOptions);
    observer.getOptimisticResult(previewOptions);
    observer.setOptions(options);
    expect(
        calls, [1, 3]); // Preview memo and committed memo remain independent.
    expect(observer.currentResult.dataOrNull, 1);
    observer.destroy();
    client.clear();
  });

  testFakeAsync('reset alone inside sharing remains authoritative',
      (time) async {
    final client = testClient();
    final key = QueryKey(['reset-alone']);
    final transport = Completer<int>();
    final result = client.query(QueryOptions<int>(
      queryKey: key,
      queryFn: (_) => transport.future,
      structuralSharing: (previous, next) {
        client.queryCache.get<int>(key)!.reset();
        return next;
      },
    ));
    transport.complete(1);
    await result;
    final state = client.getQueryState<int>(key)!;
    client.clear();
    expect(state.status, QueryStatus.pending,
        reason: 'reset restored the initial empty pending state');
    expect(state.hasData, isFalse);
    expect(state.fetchStatus, FetchStatus.idle);
  });

  testFakeAsync('removing active scope owner keeps its transport exclusive',
      (time) async {
    final client = testClient();
    final firstTransport = Completer<int>();
    final firstSettled = Completer<void>();
    final calls = <int>[];
    final options =
        client.defaultMutationOptions<int, int, void>(MutationOptions(
      scope: const MutationScope('active-owner'),
      mutationFn: (v) {
        calls.add(v);
        return v == 1 ? firstTransport.future : Future.value(v);
      },
      onSettled: (_, __, ___, v, ____) => v == 1 ? firstSettled.future : null,
    ));
    final first = client.mutationCache.build(client, options);
    final second = client.mutationCache.build(client, options);
    final a = first.execute(1);
    final b = second.execute(2);
    await time.flushMicrotasks();
    client.mutationCache.remove(first);
    await time.flushMicrotasks();
    expect(calls, [1]);
    firstTransport.complete(1);
    await time.flushMicrotasks();
    expect(calls, [1],
        reason: 'Scoped successor waits through removed owner callbacks');
    firstSettled.complete();
    await a;
    expect(await b, 2);
    expect(calls, [1, 2]);
    client.clear();
  });
}
