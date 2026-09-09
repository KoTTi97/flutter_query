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
/// Proofs (widget tests in `test/features/four_call_styles_test.dart`,
/// end-to-end in `e2e/tests/four_call_styles.spec.ts`): five readers make one
/// `GET /api/posts` and the strip says `observers=5`; a refetch through the
/// controller updates all five; either mutation button increments the counter
/// and the invalidation refetches it; leaving the screen releases all five
/// observers, the hand-rolled one included; and the hand-rolled observer sees
/// the same result as the binding's readers after a refetch.
library;

import 'package:flutter/material.dart';
import 'package:tanstack_query_flutter/tanstack_query_flutter.dart';

import '../../shared/api.dart';
import '../../shared/debug_strip.dart';
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

const TextStyle _mono = TextStyle(fontFamily: 'monospace', fontSize: 13);

/// The one query all five readers share.
///
/// The `staleTime` is what makes "five readers, one request" hold no matter
/// which frame a card first builds in: a reader that subscribes after the
/// data is in joins it instead of starting a refetch of its own. It does not
/// stand in the way of the buttons — `refetch()` ignores staleness, and
/// `invalidateQueries` marks the entry stale explicitly.
QueryObserverOptions<List<Post>, List<Post>> postsQuery(ShowcaseApi api) =>
    QueryObserverOptions<List<Post>, List<Post>>(
      queryKey: ShowcaseKeys.posts,
      queryFn: (context) => api.posts(signal: context.signal),
      staleTime: const StaleTime.duration(Duration(minutes: 5)),
    );

/// The entry the mutation writes to, and the one it invalidates.
QueryKey get counterKey => QueryKey(const <Object?>['counter']);

QueryObserverOptions<int, int> counterQuery(ShowcaseApi api) =>
    QueryObserverOptions<int, int>(
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

  final _Builds _contextBuilds = _Builds();
  final _Builds _builderBuilds = _Builds();
  final _Builds _mixinBuilds = _Builds();
  final _Builds _controllerBuilds = _Builds();
  final _Builds _observerBuilds = _Builds();

  @override
  void initState() {
    super.initState();
    // Neither lookup subscribes: the api and the client are fixed for the
    // life of the app, and a subscribing lookup is not allowed here anyway.
    _api = context.getInheritedWidgetOfExactType<ShowcaseScope>()!.api;
    _client = QueryClientProvider.read(context);
    _controller = QueryController.of(_client, postsQuery(_api));
  }

  @override
  void dispose() {
    _controller.dispose();
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
                _Toolbar(
                  children: <Widget>[
                    _Action(
                      label: 'Refetch',
                      filled: true,
                      onPressed: () => _controller.refetch().ignore(),
                    ),
                    _Action(label: 'Invalidate', onPressed: _invalidate),
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
          _MutationCard(api: _api, client: _client),
          QueryDebugStrip(queryKey: counterKey, label: 'counter'),
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
        note: 'The only style with buildWhen, the port\'s answer to '
            'notifyOnChangeProps. This one does not use it, so it rebuilds '
            'like the rest.',
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
          code: 'QueryController.of(client, postsQuery(api))',
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

  /// The semantics group is `reader <name>`, the widget key `reader-<name>`.
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
          Text(code, style: _mono),
          const SizedBox(height: 8),
          Text(note),
          const SizedBox(height: 8),
          Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'reader $name',
            child: Wrap(
              key: ValueKey<String>('reader-$name'),
              spacing: 12,
              runSpacing: 4,
              children: <Widget>[
                Text(posts, style: _mono),
                Text('status=${result.status.name}', style: _mono),
                Text('fetching=${result.isFetching}', style: _mono),
                Text('builds=$builds', style: _mono),
              ],
            ),
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

/// 6. The same mutation through two of the styles, side by side, with the
/// counter it invalidates read through a third.
class _MutationCard extends StatelessWidget {
  const _MutationCard({required this.api, required this.client});

  final ShowcaseApi api;
  final QueryClient client;

  @override
  Widget build(BuildContext context) => SectionCard(
        title: '6. One mutation, two styles',
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
            style: _mono,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Mutations have the same four shapes as queries, and a mutation '
              'is owned by the widget that asks for it — these two are '
              'separate runs of the same options. Both invalidate the '
              'counter, and both stay pending until that refetch has landed, '
              'because onSuccess returns its future.',
            ),
            const SizedBox(height: 12),
            _BuilderMutation(api: api, client: client),
            const SizedBox(height: 12),
            _ContextMutation(api: api, client: client),
          ],
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
  });

  final String code;

  /// The semantics group is `mutation <name>`, the widget key
  /// `mutation-<name>`.
  final String name;

  final String label;
  final MutationResult<int, int> result;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(code, style: _mono),
          const SizedBox(height: 8),
          _Toolbar(
            children: <Widget>[
              _Action(label: label, filled: true, onPressed: onPressed),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'mutation $name',
            child: Wrap(
              key: ValueKey<String>('mutation-$name'),
              spacing: 12,
              runSpacing: 4,
              children: <Widget>[
                Text('status=${result.status.name}', style: _mono),
                if (result case MutationSuccess(:final data))
                  Text('data=$data', style: _mono),
                if (result case MutationError(:final error))
                  Text('error=$error', style: _mono),
              ],
            ),
          ),
        ],
      );
}

/// A row of buttons, each its own semantics node.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        explicitChildNodes: true,
        child: Wrap(spacing: 8, runSpacing: 8, children: children),
      );
}

/// A button named by its label — the accessible name a test clicks by. The
/// tooltip is for hovering humans and stays out of the semantics tree, so the
/// name is the label and nothing else.
class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: filled
            ? FilledButton.tonal(onPressed: onPressed, child: Text(label))
            : OutlinedButton(onPressed: onPressed, child: Text(label)),
      );
}
