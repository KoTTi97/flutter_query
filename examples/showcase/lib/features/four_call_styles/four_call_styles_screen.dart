/// The binding's own story, with no upstream counterpart: one query — the
/// post list — read five ways at once, next to one mutation read two ways.
///
/// The four call styles are **equal alternatives**
/// (https://github.com/KoTTi97/flutter_query/issues/21): there is no default
/// and no recommendation, so this screen ranks nothing. It shows what each
/// one looks like, and that they all end up at the same cache entry — five
/// readers, one request, one set of data. The fifth card drops the binding
/// altogether and drives a bare `QueryObserver` from `client.observe(...)`,
/// which is what the other four are wrapped around.
///
/// Every card also counts its own builds. The four binding styles drop a
/// notification whose result they have already built — the first one, about
/// the fetch their own subscribe started, is exactly that — and a plain
/// `ListenableBuilder`, which has no value to compare, cannot; so card 4's
/// count can sit one ahead. From there the five move together: a refetch is
/// two builds everywhere, the fetch starting and the data landing.
///
/// The sixth card reads nothing at all. `QueryListener` is the other half of
/// the story — the four styles answer "what does this query show", the
/// listener answers "what should happen when it changes" — and it is the only
/// thing here that adds no observer: it borrows card 4's controller and never
/// disposes it. Three things it does are visible on the card. Nothing is
/// delivered on mount, so its first call is the first fetch landing, the
/// transition after it. Its `listenWhen` accepts a change of the posts
/// themselves and refuses a refetch that returns the same ones, however far
/// `dataUpdatedAt` and `fetchStatus` have moved. And a refused transition
/// still advances what the next comparison starts from, which is why the line
/// logged for a change during a refetch starts at the fetching state the
/// refusal saw and not at the state before the refetch. The child is handed
/// back unchanged: `child-builds` is still 1 after every button on the screen
/// has been pressed. The card's last two buttons write the cache twice, once
/// as two writes and once inside one `NotifyManager.shared.batch(...)`: the
/// app's client is built on the shared manager (`main.dart`), a batch holds
/// every notification until it ends, and a notification carries the
/// controller's *latest* value — so the listener hears two transitions from
/// the plain pair and one, straight to the second value, from the batched
/// pair.
///
/// The seventh card runs one mutation three ways — `MutationBuilder`,
/// `context.mutation`, and a `MutationController` read through a
/// `ListenableBuilder` — and the third has a `MutationListener` over it, the
/// mutation's counterpart of card 6: nothing on mount, one call per state
/// change, `idle->pending` and `pending->success`.
///
/// The eighth card is the same story for an infinite query: the builder is
/// on the `load-more` screen and the controller on `max-pages`, so here are
/// the other two — `context.infiniteQuery` in a `StatelessWidget` and
/// `watchInfiniteQuery` in a `QueryMixin`, both of which hand back the
/// *controller* because paging lives on it — next to the core's own
/// `client.observeInfinite(...)`. Three readers, one entry, `observers=3`;
/// `Load next` goes through the mixin's controller and all three show the
/// page. An `InfiniteQueryListener` borrows that controller and logs each
/// change of the page count.
///
/// Proofs (widget tests in `test/features/four_call_styles_test.dart`,
/// end-to-end in `e2e/tests/four_call_styles.spec.ts`): five readers make one
/// `GET /api/posts` and the strip says `observers=5`; a refetch through the
/// controller updates all five; either mutation button increments the counter
/// and the invalidation refetches it; leaving the screen releases every
/// observer, the hand-rolled ones included; the hand-rolled observer sees the
/// same result as the binding's readers after a refetch; the listener says
/// nothing on mount, one thing per change of the data, nothing at all for a
/// refetch that changes none of it, while its child builds once and never
/// again; two plain writes are two transitions and two batched ones are one;
/// the mutation listener hears `idle->pending` and `pending->success` and
/// nothing on mount; and the three infinite readers share one entry, `Load
/// next` reaches all three with one request, and the infinite listener logs
/// `none->1` then `1->2`.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/controls.dart';
import '../../shared/debug_strip.dart';
import '../../shared/fact_group.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';
import '../../shared/theme.dart';

const Feature fourCallStylesFeature = Feature(
  id: 'four-call-styles',
  title: 'Four call styles',
  summary: 'The same query through context, builder, mixin and controller.',
);

/// The one query all five readers share.
///
/// The `staleTime` is what makes "five readers, one request" hold no matter
/// which frame a card first builds in: a reader that subscribes after the
/// data is in joins it instead of starting a refetch of its own. It does not
/// stand in the way of the buttons — `refetch()` ignores staleness, and
/// `invalidateQueries` marks the entry stale explicitly.
QueryObserverOptions<List<Post>> postsQuery(ShowcaseApi api) =>
    QueryObserverOptions<List<Post>>(
      queryKey: ShowcaseKeys.posts,
      queryFn: (context) => api.posts(signal: context.signal),
      staleTime: const StaleTime.duration(Duration(minutes: 5)),
    );

/// The entry the mutation writes to, and the one it invalidates.
QueryKey get counterKey => QueryKey(const <Object?>['counter']);

/// Card 8's entry: cursor pages of the projects, this screen's own key so the
/// `load-more` and `max-pages` entries are untouched by what happens here.
QueryKey get stylesKey => QueryKey(const <Object?>['projects', 'styles']);

/// Ten projects a page; fresh for five minutes for the same reason as the
/// posts — three readers, one request, whichever frame each first builds in.
InfiniteQueryObserverOptions<ProjectSlice, int> stylesQuery(ShowcaseApi api) =>
    InfiniteQueryObserverOptions<ProjectSlice, int>(
      queryKey: stylesKey,
      initialPageParam: 0,
      pageFn: (context) => api.projectsFrom(
        context.pageParam,
        limit: 10,
        signal: context.signal,
      ),
      getNextPageParam: (page, _, __, ___) => page.nextId,
      staleTime: const StaleTime.duration(Duration(minutes: 5)),
    );

typedef ProjectPages = InfiniteData<ProjectSlice, int>;

/// How many pages a result holds, as the infinite listener's `listenWhen`
/// sees it: `none` before the first one.
String _pagesOf(QueryResult<ProjectPages> result) =>
    '${result.dataOrNull?.pages.length ?? 'none'}';

QueryObserverOptions<int> counterQuery(ShowcaseApi api) =>
    QueryObserverOptions<int>(
      queryKey: counterKey,
      queryFn: (context) => api.counter(signal: context.signal),
    );

/// One increment. `onSuccess` returns the invalidation's future, so the
/// mutation stays `pending` until the counter has refetched — upstream's
/// "return the promise" idiom, and the reason a success is never shown next
/// to a stale number.
MutationOptions<int, int, void> incrementMutation(
  ShowcaseApi api,
  QueryClient client,
) =>
    MutationOptions.simple<int, int>(
      mutationFn: (by) => api.increment(by: by),
      onSuccess: (_, __, ___) =>
          client.invalidateQueries(filters: QueryFilters(queryKey: counterKey)),
    );

/// How many times one card has built.
///
/// A counter per card, held by the screen rather than by the card, so the two
/// `StatelessWidget` readers can keep one as well.
class _Builds {
  int value = 0;

  int next() => ++value;
}

class FourCallStylesScreen extends StatefulWidget {
  const FourCallStylesScreen({super.key});

  @override
  State<FourCallStylesScreen> createState() => _FourCallStylesScreenState();
}

class _FourCallStylesScreenState extends State<FourCallStylesScreen> {
  late final ShowcaseApi _api;
  late final QueryClient _client;

  /// The controller behind card 4 — and behind the `Refetch` button, so the
  /// refetch provably goes through the controller and not through the client.
  late final QueryController<List<Post>, List<Post>> _controller;

  /// The mutation behind card 7's third panel, and under its listener.
  late final MutationController<int, int, void> _increment;

  final _Builds _contextBuilds = _Builds();
  final _Builds _builderBuilds = _Builds();
  final _Builds _mixinBuilds = _Builds();
  final _Builds _controllerBuilds = _Builds();
  final _Builds _observerBuilds = _Builds();

  /// The listener's child counts its builds like a card, and for the opposite
  /// reason: this one is supposed to stay at 1.
  final _Builds _listenerChildBuilds = _Builds();

  @override
  void initState() {
    super.initState();
    // Neither lookup subscribes: the api and the client are fixed for the
    // life of the app, and a subscribing lookup is not allowed here anyway.
    _api = context.getInheritedWidgetOfExactType<ShowcaseScope>()!.api;
    _client = QueryClientProvider.read(context);
    _controller = QueryController.create(_client, postsQuery(_api));
    _increment = MutationController<int, int, void>(
      _client,
      incrementMutation(_api, _client),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _increment.dispose();
    super.dispose();
  }

  void _invalidate() => _client
      .invalidateQueries(filters: QueryFilters(queryKey: ShowcaseKeys.posts))
      .ignore();

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: fourCallStylesFeature,
        children: <Widget>[
          SectionCard(
            title: 'One entry, five readers',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'The library has four ways to read a query and no default: '
                  'they are equal alternatives, layered on one another, and '
                  'they mix freely inside one screen. Each card below reads '
                  'the same key with a reader of its own; what they share is '
                  'the entry in the cache, which the core deduplicates. The '
                  'strip says observers=5 and fetches=1.',
                ),
                const SizedBox(height: 8),
                const Text(
                  'The fifth card uses no binding at all: a QueryObserver '
                  'from client.observe(...), subscribed in initState and '
                  'destroyed in dispose. That is what the other four wrap.',
                ),
                const SizedBox(height: 12),
                Toolbar(
                  children: <Widget>[
                    ActionButton(
                      label: 'Refetch',
                      filled: true,
                      onPressed: () => _controller.refetch().ignore(),
                    ),
                    ActionButton(label: 'Invalidate', onPressed: _invalidate),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Refetch goes through card 4\'s controller; Invalidate '
                  'goes through the client. Either way one request goes out '
                  'and all five readers show the new data.',
                ),
              ],
            ),
          ),
          QueryDebugStrip(queryKey: ShowcaseKeys.posts, label: 'posts'),
          _ContextCard(builds: _contextBuilds),
          _BuilderCard(builds: _builderBuilds),
          _MixinCard(builds: _mixinBuilds),
          _ControllerCard(
            controller: _controller,
            builds: _controllerBuilds,
          ),
          _ObserverCard(builds: _observerBuilds),
          _ListenerCard(
            controller: _controller,
            client: _client,
            childBuilds: _listenerChildBuilds,
          ),
          _MutationCard(api: _api, client: _client, controller: _increment),
          QueryDebugStrip(queryKey: counterKey, label: 'counter'),
          _InfiniteCard(api: _api),
          QueryDebugStrip(queryKey: stylesKey, label: 'styles'),
        ],
      );
}

/// 1. `context.query` — the flattest of the four, and it works in a
/// `StatelessWidget`. Small on purpose: the rebuild is this widget, not the
/// screen.
class _ContextCard extends StatelessWidget {
  const _ContextCard({required this.builds});

  final _Builds builds;

  @override
  Widget build(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    final posts = context.query(postsQuery(api));

    return _ReaderCard(
      title: '1. context.query',
      code: 'context.query(postsQuery(api))',
      note: 'Read in build. The observer is this widget\'s, and it is '
          'released when the widget unmounts or stops reading the key.',
      name: 'context',
      result: posts,
      builds: builds.next(),
    );
  }
}

/// 2. `QueryBuilder` — the `StreamBuilder` shape: everything is in the tree,
/// and the rebuild is exactly this builder's subtree.
class _BuilderCard extends StatelessWidget {
  const _BuilderCard({required this.builds});

  final _Builds builds;

  @override
  Widget build(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    return QueryBuilder<List<Post>>(
      options: postsQuery(api),
      builder: (context, posts) => _ReaderCard(
        title: '2. QueryBuilder',
        code: 'QueryBuilder<List<Post>>(options: …, builder: …)',
        note: 'Takes buildWhen, the port\'s answer to notifyOnChangeProps — '
            'as context.query and watchQuery do since C49. This one does not '
            'use it, so it rebuilds like the rest.',
        name: 'builder',
        result: posts,
        builds: builds.next(),
      ),
    );
  }
}

/// 3. `QueryMixin` — flat like `context.query`, owned by the `State`. Reads
/// are identified by key and types, so there is no equivalent of the rules of
/// hooks.
class _MixinCard extends StatefulWidget {
  const _MixinCard({required this.builds});

  final _Builds builds;

  @override
  State<_MixinCard> createState() => _MixinCardState();
}

class _MixinCardState extends State<_MixinCard> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    final posts = watchQuery(postsQuery(api));

    return _ReaderCard(
      title: '3. QueryMixin',
      code: 'watchQuery(postsQuery(api))',
      note: 'Everything this State watches is disposed with it. A key read '
          'last build but not this one is released after the frame.',
      name: 'mixin',
      result: posts,
      builds: widget.builds.next(),
    );
  }
}

/// 4. `QueryController` — a plain `ValueListenable`, so `ListenableBuilder`
/// reads it with nothing from this package involved.
///
/// The controller is the screen's, because the `Refetch` button up top drives
/// the same one.
class _ControllerCard extends StatelessWidget {
  const _ControllerCard({required this.controller, required this.builds});

  final QueryController<List<Post>, List<Post>> controller;
  final _Builds builds;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _ReaderCard(
          title: '4. QueryController',
          code: 'QueryController.create(client, postsQuery(api))',
          note: 'A ListenableBuilder rebuilds on every notification, '
              'because a Listenable carries no value to compare. That can '
              'leave this count one ahead of the other four, which drop a '
              'notification whose result they have already built.',
          name: 'controller',
          result: controller.value,
          builds: builds.next(),
        ),
      );
}

/// 5. The core on its own: a `QueryObserver` from `client.observe(...)`,
/// subscribed by hand and destroyed in `dispose`.
///
/// This is what the binding is a shell around — the same result, the same
/// cache entry, roughly twenty lines of bookkeeping the other four do for
/// you.
class _ObserverCard extends StatefulWidget {
  const _ObserverCard({required this.builds});

  final _Builds builds;

  @override
  State<_ObserverCard> createState() => _ObserverCardState();
}

class _ObserverCardState extends State<_ObserverCard> {
  late final QueryObserver<List<Post>, List<Post>> _observer;
  late final void Function() _unsubscribe;

  /// Guards the very first notification: `subscribe` can report on the spot,
  /// and a `setState` from `initState` is not allowed.
  bool _built = false;

  @override
  void initState() {
    super.initState();
    final api = context.getInheritedWidgetOfExactType<ShowcaseScope>()!.api;
    final client = QueryClientProvider.read(context);
    _observer = client.observe<List<Post>, List<Post>>(postsQuery(api));
    // Through the notify manager, the way every controller in the binding
    // does it: that is what puts the notification on the scheduler the
    // provider installed, so a result arriving mid-build lands after the
    // frame instead of inside it.
    _unsubscribe = _observer.subscribe(
      client.notifyManager.batchCalls<QueryResult<List<Post>>>((_) {
        if (_built && mounted) {
          setState(() {});
        }
      }),
    );
  }

  @override
  void dispose() {
    _unsubscribe();
    // The observer is not the subscription: without this it stays attached to
    // the query, and the entry never drops to zero observers.
    _observer.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _built = true;
    return _ReaderCard(
      title: '5. QueryObserver, no binding',
      code: 'client.observe(postsQuery(api)).subscribe(…)',
      note: 'The core alone. subscribe in initState, unsubscribe and destroy '
          'in dispose — miss the destroy and the entry keeps an observer '
          'forever.',
      name: 'observer',
      result: _observer.currentResult,
      builds: widget.builds.next(),
    );
  }
}

/// One reader's card: the same three facts everywhere, plus the line of code
/// that produced them.
class _ReaderCard extends StatelessWidget {
  const _ReaderCard({
    required this.title,
    required this.code,
    required this.note,
    required this.name,
    required this.result,
    required this.builds,
  });

  final String title;

  /// The call, in one line — what a reader compares the styles by.
  final String code;

  final String note;

  /// The group is `reader <name>`, in both test layers.
  final String name;

  final QueryResult<List<Post>> result;
  final int builds;

  @override
  Widget build(BuildContext context) {
    final posts = switch (result) {
      QueryPending() => 'posts=…',
      QueryError(staleData: null) => 'posts=error',
      QuerySuccess(:final data) ||
      QueryError(staleData: final data!) =>
        'posts=${data.length}',
    };

    return SectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(code, style: monoStyle),
          const SizedBox(height: 8),
          Text(note),
          const SizedBox(height: 8),
          FactGroup(
            name: 'reader $name',
            facts: <String>[
              posts,
              'status=${result.status.name}',
              'fetching=${result.isFetching}',
              'builds=$builds',
            ],
          ),
          if (result case QueryError(:final error)) ...<Widget>[
            const SizedBox(height: 8),
            Notice('$error', error: true),
          ],
        ],
      ),
    );
  }
}

/// 6. `QueryListener` — not a sixth way of reading the query, but the answer
/// to the other question: what should *happen* when it changes.
///
/// It borrows card 4's controller. Borrowing is the whole contract: the
/// listener never disposes it, adds no observer of its own — the strip still
/// says `observers=5` — and hands its child straight back, so no notification
/// it receives rebuilds anything below it.
class _ListenerCard extends StatefulWidget {
  const _ListenerCard({
    required this.controller,
    required this.client,
    required this.childBuilds,
  });

  final QueryController<List<Post>, List<Post>> controller;
  final QueryClient client;
  final _Builds childBuilds;

  @override
  State<_ListenerCard> createState() => _ListenerCardState();
}

class _ListenerCardState extends State<_ListenerCard> {
  /// The accepted transitions, oldest first, the last [_logLength] of them.
  final List<String> _log = <String>[];

  int _calls = 0;
  int _skips = 0;
  String _last = 'none';

  /// Where the transition currently being judged came from, written by
  /// [_dataChanged] for [_record] — the callback is handed the new result
  /// only, and the pair is what makes the line readable.
  String _from = 'none';

  static const int _logLength = 4;

  /// The listener's child, built once and kept.
  ///
  /// Every rebuild of this card hands `QueryListener` the same widget
  /// *instance*, so the element is reused and this subtree never builds
  /// again. That is what makes `child-builds` a proof rather than a
  /// coincidence: the counter would move if anything rebuilt it, and the card
  /// around it rebuilds on every call and every refusal below.
  late final Widget _child = _ListenerChild(builds: widget.childBuilds);

  /// A result as one word: the status, what the query is doing, and how much
  /// data there is. `fetchStatus` is in it on purpose — it is what shows that
  /// a refused transition still moved the comparison forward.
  static String _shape(QueryResult<List<Post>> result) {
    final data = result.dataOrNull;
    return '${result.status.name}/${result.fetchStatus.name}:'
        '${data == null ? 'none' : data.length}';
  }

  /// What this screen means by "the data changed": the posts, compared post
  /// by post. `dataUpdatedAt` moves every time a fetch lands and
  /// `fetchStatus` every time one starts; neither is a change of data, and a
  /// refetch that returns the same 30 posts is refused here.
  ///
  /// Every transition passes through this, accepted or not, which is why
  /// [_from] is written for all of them.
  bool _dataChanged(
    QueryResult<List<Post>> previous,
    QueryResult<List<Post>> next,
  ) {
    _from = _shape(previous);
    if (!_samePosts(previous.dataOrNull, next.dataOrNull)) {
      return true;
    }
    setState(() => _skips++);
    return false;
  }

  static bool _samePosts(List<Post>? previous, List<Post>? next) {
    if (previous == null || next == null) {
      return previous == null && next == null;
    }
    if (previous.length != next.length) {
      return false;
    }
    for (var i = 0; i < previous.length; i++) {
      if (previous[i] != next[i]) {
        return false;
      }
    }
    return true;
  }

  /// The side effect. A `setState` from here is safe — so would a `SnackBar`
  /// or a route push be — because the callback is delivered off the build
  /// phase even when the result changed while the tree was building.
  void _record(BuildContext context, QueryResult<List<Post>> next) {
    setState(() {
      _calls++;
      _last = '$_from->${_shape(next)}';
      _log.add('#$_calls $_last');
      if (_log.length > _logLength) {
        _log.removeAt(0);
      }
    });
  }

  /// A change of the data with nothing fetched for it: `/posts` is read-only,
  /// and a cache write is a change of data like any other. Refetch up top
  /// puts the dropped post back.
  void _drop() {
    widget.client.updateQueryData<List<Post>>(
      ShowcaseKeys.posts,
      (previous) =>
          previous == null || previous.isEmpty ? null : previous.sublist(1),
    );
  }

  /// Two writes, each delivered as it happens: two transitions.
  void _dropTwo() {
    _drop();
    _drop();
  }

  /// The same two writes inside one batch on the shared notify manager —
  /// the one the app's client was built on. Every notification is held until
  /// the batch ends, and a notification carries the controller's latest
  /// value, so the listener hears one transition, to the second value.
  void _dropTwoBatched() => NotifyManager.shared.batch(_dropTwo);

  @override
  Widget build(BuildContext context) => SectionCard(
        title: '6. QueryListener, a side effect',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Not a sixth way of reading the query: a way of reacting to '
              'it. The listener borrows the controller card 4 holds — it '
              'never disposes it, and it adds no observer, so the strip '
              'above still says observers=5 — and returns its child '
              'unchanged, which is why child-builds below stays at 1 however '
              'often the query changes.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Nothing is delivered on mount, so the first call is the first '
              'fetch landing. listenWhen accepts a change of the posts and '
              'refuses everything else, and a refused transition still '
              'advances what the next comparison starts from — which is why '
              'a change during a fetch is logged from the fetching state.',
            ),
            const SizedBox(height: 8),
            const Text(
              'QueryListener(controller: …, listenWhen: …, listener: …, '
              'child: …)',
              style: monoStyle,
            ),
            const SizedBox(height: 12),
            Toolbar(
              children: <Widget>[
                ActionButton(label: 'Drop a post', onPressed: _drop),
                ActionButton(label: 'Drop two posts', onPressed: _dropTwo),
                ActionButton(
                  label: 'Drop two posts, batched',
                  onPressed: _dropTwoBatched,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Drop a post writes the cache directly, so the data genuinely '
              'changes and the listener has something to say. Refetch and '
              'Invalidate up top return the same 30 posts, and it says '
              'nothing about either. Drop two posts is two writes and two '
              'transitions; the batched pair runs inside '
              'NotifyManager.shared.batch — the app\'s client is built on '
              'the shared manager — which holds every notification until '
              'the batch ends, and a notification carries the latest value: '
              'one transition, straight to the second value.',
            ),
            const SizedBox(height: 12),
            SemanticsGroup(
              name: 'listener',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FactList(<String>[
                    'listener-calls=$_calls',
                    'listener-skips=$_skips',
                    'last=$_last',
                  ]),
                  const SizedBox(height: 4),
                  for (final line in _log) Text(line, style: monoStyle),
                  const SizedBox(height: 8),
                  QueryListener<List<Post>, List<Post>>(
                    controller: widget.controller,
                    listenWhen: _dataChanged,
                    listener: _record,
                    child: _child,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// The listener's child: handed back unchanged, and rebuilt by nothing the
/// controller does.
class _ListenerChild extends StatelessWidget {
  const _ListenerChild({required this.builds});

  final _Builds builds;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('child-builds=${builds.next()}', style: monoStyle),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'The child of the listener. It built once, on mount, and no '
              'transition above has touched it since.',
            ),
          ),
        ],
      );
}

/// 7. The same mutation through three of the styles, side by side, with the
/// counter it invalidates read through a fourth — and a `MutationListener`
/// over the controller-backed one.
class _MutationCard extends StatelessWidget {
  const _MutationCard({
    required this.api,
    required this.client,
    required this.controller,
  });

  final ShowcaseApi api;
  final QueryClient client;
  final MutationController<int, int, void> controller;

  @override
  Widget build(BuildContext context) => SectionCard(
        title: '7. One mutation, two styles',
        trailing: QueryBuilder<int>(
          options: counterQuery(api),
          builder: (context, counter) => Text(
            switch (counter) {
              QueryPending() => 'counter=…',
              QueryError(staleData: null) => 'counter=error',
              QuerySuccess(:final data) ||
              QueryError(staleData: final data!) =>
                'counter=$data',
            },
            style: monoStyle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Mutations have the same four shapes as queries, and a mutation '
              'is owned by the widget that asks for it — these three are '
              'separate runs of the same options. All invalidate the '
              'counter, and all stay pending until that refetch has landed, '
              'because onSuccess returns its future. The third is a '
              'MutationController read through a ListenableBuilder, with a '
              'MutationListener over it: the side-effect half for mutations, '
              'silent on mount and called once per state change.',
            ),
            const SizedBox(height: 12),
            _BuilderMutation(api: api, client: client),
            const SizedBox(height: 12),
            _ContextMutation(api: api, client: client),
            const SizedBox(height: 12),
            _ControllerMutation(controller: controller),
          ],
        ),
      );
}

/// The third style, with the listener: `MutationListener` borrows the
/// screen's controller, disposes nothing, and logs each transition as
/// `from->to` by status.
class _ControllerMutation extends StatefulWidget {
  const _ControllerMutation({required this.controller});

  final MutationController<int, int, void> controller;

  @override
  State<_ControllerMutation> createState() => _ControllerMutationState();
}

class _ControllerMutationState extends State<_ControllerMutation> {
  int _calls = 0;
  String _last = 'none';
  String _from = 'none';

  bool _statusChanged(
    MutationResult<int, int> previous,
    MutationResult<int, int> next,
  ) {
    _from = previous.status.name;
    return previous.status != next.status;
  }

  void _record(BuildContext context, MutationResult<int, int> next) {
    setState(() {
      _calls++;
      _last = '$_from->${next.status.name}';
    });
  }

  @override
  Widget build(BuildContext context) => MutationListener<int, int, void>(
        controller: widget.controller,
        listenWhen: _statusChanged,
        listener: _record,
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) => _MutationPanel(
            code: 'MutationController(client, …) + MutationListener',
            name: 'controller',
            label: 'Increment (controller)',
            result: widget.controller.value,
            onPressed: () => widget.controller.mutate(1),
            extraFacts: <String>[
              'mutation-listener-calls=$_calls',
              'mutation-last=$_last',
            ],
          ),
        ),
      );
}

class _BuilderMutation extends StatelessWidget {
  const _BuilderMutation({required this.api, required this.client});

  final ShowcaseApi api;
  final QueryClient client;

  @override
  Widget build(BuildContext context) => MutationBuilder<int, int, void>(
        options: incrementMutation(api, client),
        builder: (context, increment) => _MutationPanel(
          code: 'MutationBuilder<int, int, void>(options: …)',
          name: 'builder',
          label: 'Increment (builder)',
          result: increment.value,
          onPressed: () => increment.mutate(1),
        ),
      );
}

class _ContextMutation extends StatelessWidget {
  const _ContextMutation({required this.api, required this.client});

  final ShowcaseApi api;
  final QueryClient client;

  @override
  Widget build(BuildContext context) {
    final increment = context.mutation(incrementMutation(api, client));
    return _MutationPanel(
      code: 'context.mutation(incrementMutation(api, client))',
      name: 'context',
      label: 'Increment (context)',
      result: increment.value,
      onPressed: () => increment.mutate(1),
    );
  }
}

/// One mutation reader: the call, the button, and the result's facts.
class _MutationPanel extends StatelessWidget {
  const _MutationPanel({
    required this.code,
    required this.name,
    required this.label,
    required this.result,
    required this.onPressed,
    this.extraFacts = const <String>[],
  });

  final String code;

  /// The group is `mutation <name>`, in both test layers.
  final String name;

  final String label;
  final MutationResult<int, int> result;
  final VoidCallback onPressed;

  /// More `key=value` texts for the same group — the listener's, on the
  /// third panel.
  final List<String> extraFacts;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(code, style: monoStyle),
          const SizedBox(height: 8),
          Toolbar(
            children: <Widget>[
              ActionButton(label: label, filled: true, onPressed: onPressed),
            ],
          ),
          const SizedBox(height: 8),
          FactGroup(
            name: 'mutation $name',
            facts: <String>[
              'status=${result.status.name}',
              if (result case MutationSuccess(:final data)) 'data=$data',
              if (result case MutationError(:final error)) 'error=$error',
              ...extraFacts,
            ],
          ),
        ],
      );
}

/// 8. The infinite shapes: one infinite entry read three ways, the two
/// styles the paging screens do not use plus the core's own observer, and an
/// `InfiniteQueryListener` over the mixin's controller.
class _InfiniteCard extends StatelessWidget {
  const _InfiniteCard({required this.api});

  final ShowcaseApi api;

  @override
  Widget build(BuildContext context) => SectionCard(
        title: '8. The infinite shapes',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'An infinite query has the same four styles. The builder is on '
              'the load-more screen and the controller on max-pages; here '
              'are the other two — context.infiniteQuery and '
              'watchInfiniteQuery, which hand back the controller because '
              'paging lives on it — next to the core\'s '
              'client.observeInfinite. Three readers, one entry: the strip '
              'below says observers=3 and fetches=1. Load next goes through '
              'the mixin\'s controller, and all three show the page. The '
              'InfiniteQueryListener borrows that same controller and logs '
              'each change of the page count.',
            ),
            const SizedBox(height: 12),
            _InfiniteContextReader(api: api),
            const SizedBox(height: 8),
            _InfiniteMixinReader(api: api),
            const SizedBox(height: 8),
            _InfiniteObserverReader(api: api),
          ],
        ),
      );
}

/// One infinite reader's row: the call and its facts, in the group
/// `infinite <name>`.
class _InfiniteRow extends StatelessWidget {
  const _InfiniteRow({
    required this.code,
    required this.name,
    required this.result,
    this.extraFacts = const <String>[],
    this.trailing = const <Widget>[],
  });

  final String code;
  final String name;
  final QueryResult<ProjectPages> result;
  final List<String> extraFacts;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(code, style: monoStyle),
          const SizedBox(height: 4),
          SemanticsGroup(
            name: 'infinite $name',
            // Not a bare [FactGroup]: one card puts a button beside the facts,
            // and it belongs inside the group the test addresses.
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                FactList(<String>[
                  'pages=${_pagesOf(result)}',
                  'status=${result.status.name}',
                  ...extraFacts,
                ]),
                ...trailing,
              ],
            ),
          ),
        ],
      );
}

/// `context.infiniteQuery`, in a `StatelessWidget`.
class _InfiniteContextReader extends StatelessWidget {
  const _InfiniteContextReader({required this.api});

  final ShowcaseApi api;

  @override
  Widget build(BuildContext context) {
    final projects = context.infiniteQuery(stylesQuery(api));
    return _InfiniteRow(
      code: 'context.infiniteQuery(stylesQuery(api))',
      name: 'context',
      result: projects.value,
    );
  }
}

/// `watchInfiniteQuery`, in a `QueryMixin` — and the listener, which borrows
/// the controller the mixin hands back. The button pages through that same
/// controller.
class _InfiniteMixinReader extends StatefulWidget {
  const _InfiniteMixinReader({required this.api});

  final ShowcaseApi api;

  @override
  State<_InfiniteMixinReader> createState() => _InfiniteMixinReaderState();
}

class _InfiniteMixinReaderState extends State<_InfiniteMixinReader>
    with QueryMixin {
  int _calls = 0;
  String _last = 'none';
  String _from = 'none';

  /// A change of the page count, and nothing else: a page fetch starting
  /// moves `fetchStatus` and is refused here.
  bool _pagesChanged(
    QueryResult<ProjectPages> previous,
    QueryResult<ProjectPages> next,
  ) {
    _from = _pagesOf(previous);
    return _pagesOf(previous) != _pagesOf(next);
  }

  void _record(BuildContext context, QueryResult<ProjectPages> next) {
    setState(() {
      _calls++;
      _last = '$_from->${_pagesOf(next)}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final projects = watchInfiniteQuery(stylesQuery(widget.api));
    return InfiniteQueryListener<ProjectSlice, int, ProjectPages>(
      controller: projects,
      listenWhen: _pagesChanged,
      listener: _record,
      child: _InfiniteRow(
        code: 'watchInfiniteQuery(stylesQuery(api)) + InfiniteQueryListener',
        name: 'mixin',
        result: projects.value,
        extraFacts: <String>[
          'infinite-listener-calls=$_calls',
          'infinite-last=$_last',
        ],
        trailing: <Widget>[
          ActionButton(
            label: 'Load next',
            filled: true,
            onPressed: projects.hasNextPage && !projects.isFetchingNextPage
                ? () => projects.fetchNextPage().ignore()
                : null,
          ),
        ],
      ),
    );
  }
}

/// The core alone: an `InfiniteQueryObserver` from `client.observeInfinite`,
/// subscribed by hand and destroyed in `dispose`, like card 5.
class _InfiniteObserverReader extends StatefulWidget {
  const _InfiniteObserverReader({required this.api});

  final ShowcaseApi api;

  @override
  State<_InfiniteObserverReader> createState() =>
      _InfiniteObserverReaderState();
}

class _InfiniteObserverReaderState extends State<_InfiniteObserverReader> {
  late final InfiniteQueryObserver<ProjectSlice, int, ProjectPages> _observer;
  late final void Function() _unsubscribe;
  bool _built = false;

  @override
  void initState() {
    super.initState();
    final client = QueryClientProvider.read(context);
    _observer = client.observeInfinite(stylesQuery(widget.api));
    _unsubscribe = _observer.subscribe(
      client.notifyManager.batchCalls<QueryResult<ProjectPages>>((_) {
        if (_built && mounted) {
          setState(() {});
        }
      }),
    );
  }

  @override
  void dispose() {
    _unsubscribe();
    _observer.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _built = true;
    return _InfiniteRow(
      code: 'client.observeInfinite(stylesQuery(api)).subscribe(…)',
      name: 'observer',
      result: _observer.currentResult,
    );
  }
}
