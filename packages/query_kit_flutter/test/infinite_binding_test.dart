/// Infinite queries through the four call styles
/// (https://github.com/KoTTi97/flutter_query/issues/16): the paging half lives
/// on the controller, which is what every style hands back.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

final feedKey = QueryKey(<Object?>['feed']);

typedef Feed = InfiniteData<List<int>, int>;

InfiniteQueryObserverOptions<List<int>, int> feedQuery(
  List<int> fetched,
) =>
    InfiniteQueryObserverOptions<List<int>, int>(
      queryKey: feedKey,
      initialPageParam: 0,
      pageFn: (context) async {
        fetched.add(context.pageParam);
        return List<int>.generate(2, (i) => context.pageParam * 2 + i);
      },
      getNextPageParam: (lastPage, pages, lastParam, params) =>
          lastParam < 2 ? lastParam + 1 : null,
      staleTime: StaleTime.infinite,
    );

String render(InfiniteQueryController<List<int>, int, Feed> feed) {
  final pages = feed.value.dataOrNull?.pages ?? const <List<int>>[];
  return '${pages.expand((p) => p).join(',')}'
      '${feed.hasNextPage ? ' +' : ''}';
}

Widget app(QueryClient client, Widget child) => QueryClientProvider(
      client: client,
      observeAppLifecycle: false,
      child: MaterialApp(home: Scaffold(body: child)),
    );

class _Mixin extends StatefulWidget {
  const _Mixin(this.fetched);
  final List<int> fetched;
  @override
  State<_Mixin> createState() => _MixinState();
}

class _MixinState extends State<_Mixin> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final feed = watchInfiniteQuery(feedQuery(widget.fetched));
    return TextButton(
      onPressed: feed.fetchNextPage,
      child: Text(render(feed)),
    );
  }
}

class _Context extends StatelessWidget {
  const _Context(this.fetched);
  final List<int> fetched;
  @override
  Widget build(BuildContext context) {
    final feed = context.infiniteQuery(feedQuery(fetched));
    return TextButton(
      onPressed: feed.fetchNextPage,
      child: Text(render(feed)),
    );
  }
}

void main() {
  late QueryClient client;
  late List<int> fetched;

  setUp(() {
    client = QueryClient();
    fetched = <int>[];
  });

  Future<void> pagesThrough(
    WidgetTester tester,
    Widget child,
  ) async {
    try {
      await tester.pumpWidget(app(client, child));
      await tester.pump();
      expect(find.text('0,1 +'), findsOneWidget);
      expect(fetched, [0]);

      await tester.tap(find.byType(TextButton));
      await tester.pump();
      await tester.pump();
      expect(find.text('0,1,2,3 +'), findsOneWidget);

      await tester.tap(find.byType(TextButton));
      await tester.pump();
      await tester.pump();
      expect(find.text('0,1,2,3,4,5'), findsOneWidget);
      expect(fetched, [0, 1, 2]);
    } finally {
      await tester.pumpWidget(const SizedBox());
      client.clear();
    }
  }

  testWidgets('InfiniteQueryBuilder pages', (tester) async {
    await pagesThrough(
      tester,
      InfiniteQueryBuilder<List<int>, int, Feed>(
        options: feedQuery(fetched),
        builder: (_, feed) => TextButton(
          onPressed: feed.fetchNextPage,
          child: Text(render(feed)),
        ),
      ),
    );
  });

  testWidgets('QueryMixin.watchInfiniteQuery pages', (tester) async {
    await pagesThrough(tester, _Mixin(fetched));
  });

  testWidgets('context.infiniteQuery pages', (tester) async {
    await pagesThrough(tester, _Context(fetched));
  });

  testWidgets('InfiniteQueryController pages', (tester) async {
    final feed = InfiniteQueryController<List<int>, int, Feed>(
      client,
      feedQuery(fetched),
    );
    await pagesThrough(
      tester,
      ListenableBuilder(
        listenable: feed,
        builder: (_, __) => TextButton(
          onPressed: feed.fetchNextPage,
          child: Text(render(feed)),
        ),
      ),
    );
    feed.dispose();
  });
}
