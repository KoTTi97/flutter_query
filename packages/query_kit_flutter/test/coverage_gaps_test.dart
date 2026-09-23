/// Public behaviour no other case reached: controller members a user calls,
/// errors reported instead of thrown, the desktop platforms' lifecycle
/// mapping, a provider's client swapped under a live observer, and the sliver
/// side of the layout-builder rule. Each case names what it holds.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'harness.dart';

final _key = QueryKey(<Object?>['gap']);

QueryObserverOptions<String> _options(String value, {QueryKey? key}) =>
    QueryObserverOptions<String>(
      queryKey: key ?? _key,
      queryFn: (_) async => value,
    );

InfiniteQueryObserverOptions<List<int>, int> _pages({bool failNext = false}) =>
    InfiniteQueryObserverOptions<List<int>, int>(
      queryKey: QueryKey(<Object?>['pages']),
      initialPageParam: 0,
      retry: RetryPolicy.never,
      pageFn: (context) async {
        if (failNext && context.pageParam > 0) {
          throw StateError('page ${context.pageParam}');
        }
        return <int>[context.pageParam];
      },
      getNextPageParam: (lastPage, pages, lastParam, params) => lastParam + 1,
      getPreviousPageParam: (firstPage, pages, firstParam, params) =>
          firstParam > 0 ? firstParam - 1 : null,
    );

void main() {
  group('controller members', () {
    queryWidgetTest('QueryController.refetch completes with the new result',
        (tester, client) async {
      var fetches = 0;
      final controller = QueryController<String, String>(
        client,
        QueryObserverOptions<String>(
          queryKey: _key,
          queryFn: (_) async => 'v${++fetches}',
        ),
      );
      addTearDown(controller.dispose);
      controller.addListener(() {});
      await tester.pump();
      expect(controller.value.dataOrNull, 'v1');

      QueryResult<String>? refetched;
      unawaited(controller.refetch().then((r) => refetched = r));
      await tester.pump();
      expect(refetched?.dataOrNull, 'v2');
      expect(controller.value.dataOrNull, 'v2');
    });

    queryWidgetTest('InfiniteQueryController reports each paging flag',
        (tester, client) async {
      final controller =
          InfiniteQueryController<List<int>, int, InfiniteData<List<int>, int>>(
              client, _pages(failNext: true));
      addTearDown(controller.dispose);
      controller.addListener(() {});
      await tester.pump();

      expect(controller.hasNextPage, isTrue);
      expect(controller.hasPreviousPage, isFalse,
          reason: 'the first page is param 0, before which there is none');
      expect(controller.isRefetching, isFalse);
      expect(controller.isRefetchError, isFalse);
      expect(controller.isFetchNextPageError, isFalse);
      expect(controller.isFetchPreviousPageError, isFalse);

      unawaited(controller.fetchNextPage().then((_) {}, onError: (_) {}));
      await tester.pump();
      expect(controller.isFetchNextPageError, isTrue);
      expect(controller.isFetchPreviousPageError, isFalse);
      expect(controller.isRefetchError, isFalse,
          reason: 'a failed page is not a failed refetch of the held ones');
    });

    queryWidgetTest('MutationController.reset goes back to idle',
        (tester, client) async {
      final controller = MutationController<int, int, void>(
        client,
        MutationOptions<int, int, void>(mutationFn: (v) async => v * 2),
      );
      addTearDown(controller.dispose);
      controller.mutate(2);
      await tester.pump();
      expect(controller.value.dataOrNull, 4);

      controller.reset();
      expect(controller.value.isIdle, isTrue);
    });
  });

  queryWidgetTest(
      'a QueryListener whose listener throws reports it to FlutterError '
      'and keeps listening', (tester, client) async {
    final controller =
        QueryController<String, String>(client, _options('first'));
    addTearDown(controller.dispose);
    final heard = <String?>[];
    await tester.pumpApp(
      client,
      QueryListener<String, String>(
        controller: controller,
        listener: (_, result) {
          heard.add(result.dataOrNull);
          if (result.dataOrNull == 'boom') throw StateError('listener');
        },
        child: const SizedBox(),
      ),
    );
    await tester.pump();
    heard.clear();

    client.setQueryData<String>(_key, 'boom');
    await tester.pump();
    expect(tester.takeException(), isStateError);

    client.setQueryData<String>(_key, 'after');
    await tester.pump();
    expect(heard, <String?>['boom', 'after']);
  });

  group('the provider', () {
    queryWidgetTest(
        'an onlineStatus stream error is reported, and the stream is '
        'still followed', (tester, client) async {
      final online = StreamController<bool>.broadcast();
      addTearDown(online.close);
      await tester.pumpWidget(app(
        client,
        const Text('hi'),
        onlineStatus: OnlineStatus.stream(online.stream, initial: true),
      ));

      online.addError(StateError('radio'));
      await tester.pump();
      expect(tester.takeException(), isStateError);

      online.add(false);
      await tester.pump();
      expect(client.onlineManager.isOnline(), isFalse);
    });

    for (final platform in <TargetPlatform>[
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      queryWidgetTest(
          'without isAppShown, inactive is unfocused on ${platform.name}',
          (tester, client) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await tester.pumpWidget(
              app(client, const Text('hi'), observeAppLifecycle: true));
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await tester.pump();
          expect(client.focusManager.isFocused(), isTrue);

          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          await tester.pump();
          expect(client.focusManager.isFocused(), isFalse);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    queryWidgetTest('a swapped-in client observes the app lifecycle',
        (tester, client) async {
      final second = tester.adopt(QueryClient());
      await tester
          .pumpWidget(app(client, const Text('hi'), observeAppLifecycle: true));
      await tester
          .pumpWidget(app(second, const Text('hi'), observeAppLifecycle: true));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      expect(second.focusManager.isFocused(), isFalse);
      // Back through inactive, the one way to resumed the teardown takes.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
    });

    testWidgets(
        'QueryClientProvider.read with no provider says what is '
        'missing', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }));
      expect(
        () => QueryClientProvider.read(context),
        throwsA(isA<FlutterError>().having((e) => e.message, 'message',
            contains('No QueryClientProvider found'))),
      );
    });
  });

  queryWidgetTest(
      'a QueriesBuilder not rebuilt by its parent follows a provider '
      'that swaps its client', (tester, client) async {
    final second = tester.adopt(QueryClient());
    client.setQueryData<String>(_key, 'from first');
    second.setQueryData<String>(_key, 'from second');
    // One widget instance for both frames: its element is not updated, so
    // the swap reaches it through its dependency on the provider alone.
    final builder = QueriesBuilder<String, String>(
      queries: <QueryObserverOptions<String>>[
        QueryObserverOptions<String>(
          queryKey: _key,
          queryFn: (_) async => 'fetched',
          staleTime: StaleTime.infinite,
        ),
      ],
      builder: (_, results) => Text('${results.single.dataOrNull}'),
    );
    Widget tree(QueryClient c) => app(c, builder);
    await tester.pumpWidget(tree(client));
    expect(find.text('from first'), findsOneWidget);

    await tester.pumpWidget(tree(second));
    await tester.pump();
    expect(find.text('from second'), findsOneWidget);
  });

  group('context reads', () {
    queryWidgetTest(
        'a SliverLayoutBuilder reader is subscribed and rebuilt by '
        'what it reads', (tester, client) async {
      client.setQueryData<String>(_key, 'one');
      await tester.pumpApp(
        client,
        CustomScrollView(slivers: <Widget>[
          SliverLayoutBuilder(builder: (context, constraints) {
            final result = context.query(QueryObserverOptions<String>(
              queryKey: _key,
              queryFn: (_) async => 'fetched',
              staleTime: StaleTime.infinite,
            ));
            return SliverToBoxAdapter(child: Text('${result.dataOrNull}'));
          }),
        ]),
      );
      expect(find.text('one'), findsOneWidget);

      client.setQueryData<String>(_key, 'two');
      await tester.pump();
      expect(find.text('two'), findsOneWidget);

      // A resize hands the sliver new constraints: the rule's other proof.
      tester.view.physicalSize = const Size(900, 700);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pump();
      expect(find.text('two'), findsOneWidget);
    });

    queryWidgetTest(
        'reading the same infinite query twice in one build hands back one '
        'controller', (tester, client) async {
      final seen = <Object>[];
      await tester.pumpApp(
        client,
        Builder(builder: (context) {
          final first = context.infiniteQuery(_pages());
          final second = context.infiniteQuery(_pages());
          seen
            ..add(first)
            ..add(second);
          return Text('${second.value.dataOrNull?.pages.length}');
        }),
      );
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      expect(identical(seen[0], seen[1]), isTrue);
    });
  });
}
