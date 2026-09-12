/// Mutations: `mutate` and `mutateAsync` on one mutation, `reset`, the
/// sealed result's fields, the order the callbacks run in, `isMutating`,
/// `MutationScope`, and a mutation that outlives the widget that fired it.
/// Port-specific — the upstream docs page `guides/mutations.md` is the
/// reference, and this screen walks through it section by section.
///
/// The counter query and the main mutation are read through `QueryMixin`
/// (`watchQuery`, `watchMutation`); the scoped and unscoped pairs are
/// `MutationController`s created in `initState`. The main mutation uses
/// `MutationOptions.simple` — no `onMutate`, so the third type argument is
/// `void` — and says `retry: RetryPolicy.never` out loud, which is what a
/// mutation defaults to anyway: repeating a write is rarely safe.
///
/// Proofs (widget tests in `test/features/mutations_test.dart`, end-to-end in
/// `e2e/tests/mutations.spec.ts`): `mutate` shows `status=pending` while the
/// request is out, then `status=success` with `data=1`, and the invalidated
/// counter refetches to `counter=1`; `Reset` goes back to `status=idle`;
/// `mutateAsync` hands its value to the caller; a refused request ends in
/// `status=error` after exactly one POST; the six callback lines land in the
/// library's order; two scoped mutations send one request at a time while
/// two unscoped ones send both at once; a mutation fired just before its
/// reader unmounts still reaches the backend.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/cache_listener.dart';
import '../../shared/controls.dart';
import '../../shared/debug_strip.dart';
import '../../shared/fact_group.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/scope.dart';
import '../../shared/theme.dart';

const Feature mutationsFeature = Feature(
  id: 'mutations',
  title: 'Mutations',
  summary: 'mutate, mutateAsync, reset, callbacks, and scopes.',
);

/// The cache entry every mutation here invalidates.
QueryKey get counterKey => QueryKey(const <Object?>['counter']);

/// What one increment asks for. A record, so two requests with the same
/// fields are equal — the observer compares `variables` by value.
typedef Increment = ({int by, int? fail});

QueryObserverOptions<int> counterQuery(ShowcaseApi api) =>
    QueryObserverOptions<int>(
      queryKey: counterKey,
      queryFn: (context) => api.counter(signal: context.signal),
    );

/// The main mutation. `RetryPolicy.never` is the default for mutations;
/// it is written out because the screen makes a point of it. `onSuccess`
/// returns the invalidation's future, which the library awaits before it
/// reports success — upstream's "return the promise" idiom.
MutationOptions<int, Increment, void> incrementMutation(
  ShowcaseApi api,
  QueryClient client,
) =>
    MutationOptions.simple<int, Increment>(
      mutationFn: (request) =>
          api.increment(by: request.by, fail: request.fail),
      retry: RetryPolicy.never,
      onSuccess: (_, __, ___) =>
          client.invalidateQueries(filters: QueryFilters(queryKey: counterKey)),
    );

/// A mutation whose every option callback writes to [log], including
/// `onMutate` — so the full constructor, with a `String` as what `onMutate`
/// hands to the later callbacks.
MutationOptions<int, Increment, String> loggingMutation(
  ShowcaseApi api,
  QueryClient client,
  void Function(String line) log,
) =>
    MutationOptions<int, Increment, String>(
      mutationFn: (request) {
        log('mutationFn');
        return api.increment(by: request.by, fail: request.fail);
      },
      onMutate: (_) {
        log('onMutate');
        return 'from onMutate';
      },
      onSuccess: (_, __, ___) async {
        log('onSuccess (options)');
        await client.invalidateQueries(
          filters: QueryFilters(queryKey: counterKey),
        );
      },
      onError: (_, __, ___, ____) => log('onError (options)'),
      onSettled: (_, __, ___, ____, _____) => log('onSettled (options)'),
    );

/// An increment that takes a second on the backend, with or without a
/// scope. Two of these in the same scope run one after the other.
MutationOptions<int, Increment, void> slowIncrementMutation(
  ShowcaseApi api,
  QueryClient client, {
  MutationScope? scope,
}) =>
    MutationOptions.simple<int, Increment>(
      mutationFn: (request) =>
          api.increment(by: request.by, delay: const Duration(seconds: 1)),
      scope: scope,
      onSuccess: (_, __, ___) =>
          client.invalidateQueries(filters: QueryFilters(queryKey: counterKey)),
    );

class MutationsScreen extends StatefulWidget {
  const MutationsScreen({super.key});

  @override
  State<MutationsScreen> createState() => _MutationsScreenState();
}

class _MutationsScreenState extends State<MutationsScreen> {
  bool _away = false;

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: mutationsFeature,
        children: <Widget>[
          // One child, not one per card: the reader's cards come and go
          // together, and a single column is built in full.
          if (_away)
            _AwayView(onBack: () => setState(() => _away = false))
          else
            _Reader(onLeave: () => setState(() => _away = true)),
        ],
      );
}

/// Where the reader went: nothing here observes the counter or the
/// mutation, and the count still shows the run in flight.
class _AwayView extends StatelessWidget {
  const _AwayView({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => SectionCard(
        title: 'The reader is gone',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'The widget that called mutate has been unmounted. The '
              'MutationCache owns the mutation, so it still runs, still calls '
              'its option callbacks, and still invalidates the counter.',
            ),
            const SizedBox(height: 8),
            const Text('view=away', style: monoStyle),
            const SizedBox(height: 8),
            const _IsMutatingCount(),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: ActionButton(label: 'Back to reader', onPressed: onBack),
            ),
          ],
        ),
      );
}

/// Cards A to D. Unmounted whole by `Fire and leave`, which is the point of
/// card D.
class _Reader extends StatefulWidget {
  const _Reader({required this.onLeave});

  final VoidCallback onLeave;

  @override
  State<_Reader> createState() => _ReaderState();
}

class _ReaderState extends State<_Reader> with QueryMixin {
  late final ShowcaseApi _api;
  late final QueryClient _client;
  late final MutationController<int, Increment, void> _first;
  late final MutationController<int, Increment, void> _second;
  late final MutationController<int, Increment, void> _third;
  late final MutationController<int, Increment, void> _fourth;
  late final Listenable _pairs;

  bool _failNext = false;
  String? _asyncResult;
  final List<String> _log = <String>[];

  @override
  void initState() {
    super.initState();
    // Neither lookup subscribes: the api and the client are fixed for the
    // life of the app, and a subscribing lookup is not allowed here anyway.
    _api = context.getInheritedWidgetOfExactType<ShowcaseScope>()!.api;
    _client = QueryClientProvider.read(context);
    const scope = MutationScope('counter');
    _first = MutationController<int, Increment, void>(
      _client,
      slowIncrementMutation(_api, _client, scope: scope),
    );
    _second = MutationController<int, Increment, void>(
      _client,
      slowIncrementMutation(_api, _client, scope: scope),
    );
    _third = MutationController<int, Increment, void>(
      _client,
      slowIncrementMutation(_api, _client),
    );
    _fourth = MutationController<int, Increment, void>(
      _client,
      slowIncrementMutation(_api, _client),
    );
    _pairs = Listenable.merge(<Listenable>[_first, _second, _third, _fourth]);
  }

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    _third.dispose();
    _fourth.dispose();
    super.dispose();
  }

  /// The next request: `fail: 500` once when the checkbox is on, which is
  /// then spent.
  Increment _nextRequest() {
    final request = (by: 1, fail: _failNext ? 500 : null);
    if (_failNext) {
      setState(() => _failNext = false);
    }
    return request;
  }

  Future<void> _incrementAsync(
    MutationController<int, Increment, void> mutation,
  ) async {
    final request = _nextRequest();
    setState(() => _asyncResult = null);
    try {
      final value = await mutation.mutateAsync(request);
      if (mounted) {
        setState(() => _asyncResult = 'mutateAsync result=$value');
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _asyncResult = 'mutateAsync threw=$error');
      }
    }
  }

  void _appendLog(String line) {
    // The option callbacks keep running after this reader is gone — that is
    // card D's point — so the guard is not academic. They run from the
    // mutation's own futures, never inside a build, so a plain setState is
    // safe otherwise.
    if (mounted) {
      setState(() => _log.add('${_log.length + 1} $line'));
    }
  }

  void _runWithCallbacks(
    MutationController<int, Increment, String> mutation,
  ) {
    setState(_log.clear);
    mutation.mutate(
      (by: 1, fail: null),
      callbacks: MutateCallbacks<int, Increment, String>(
        onSuccess: (_, __, ___) => _appendLog('onSuccess (call)'),
        onError: (_, __, ___, ____) => _appendLog('onError (call)'),
        onSettled: (_, __, ___, ____, _____) => _appendLog('onSettled (call)'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final counter = watchQuery(counterQuery(_api));
    final increment = watchMutation(
      incrementMutation(_api, _client),
      id: #increment,
    );
    final logging = watchMutation(
      loggingMutation(_api, _client, _appendLog),
      id: #logging,
    );
    final result = increment.value;

    final counterText = switch (counter) {
      QueryPending() => 'counter=…',
      QueryError() => 'counter=error',
      QuerySuccess(:final data) => 'counter=$data',
    };
    final facts = <String>[
      'status=${result.status.name}',
      'isPending=${result.isPending}',
      if (result case MutationSuccess(:final data)) 'data=$data',
      if (result case MutationError(:final error)) 'error=$error',
      'failureCount=${result.failureCount}',
      'submittedAt=${result.submittedAt == null ? 'none' : 'set'}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionCard(
          title: 'A. One mutation, both ways to fire it',
          trailing: Text(counterText, style: monoStyle),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'mutate fires and forgets; mutateAsync returns a future the '
                'caller awaits. Both run the same mutation, whose onSuccess '
                'returns the invalidateQueries future — so the mutation stays '
                'pending until the counter has refetched, and the screen '
                'never shows a success next to a stale number. retry is '
                'RetryPolicy.never, the default for mutations.',
              ),
              const SizedBox(height: 12),
              Toolbar(
                children: <Widget>[
                  ActionButton(
                    label: 'Increment (mutate)',
                    filled: true,
                    onPressed: () => increment.mutate(_nextRequest()),
                  ),
                  ActionButton(
                    label: 'Increment (mutateAsync)',
                    filled: true,
                    onPressed: () => _incrementAsync(increment),
                  ),
                  ActionButton(label: 'Reset', onPressed: increment.reset),
                ],
              ),
              const SizedBox(height: 8),
              FactGroup(name: 'mutation increment', facts: facts),
              if (_asyncResult != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(_asyncResult!, style: monoStyle),
              ],
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Fail next'),
                value: _failNext,
                onChanged: (value) =>
                    setState(() => _failNext = value ?? false),
              ),
              const Text(
                'Asks the backend to refuse the next request with a 500. '
                'With no retries, that first failure is the error.',
              ),
            ],
          ),
        ),
        QueryDebugStrip(queryKey: counterKey, label: 'counter'),
        SectionCard(
          title: 'B. Callback order',
          trailing: const _IsMutatingCount(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'The option callbacks run first, each awaited before the '
                'next; the callbacks passed to this one mutate call run once '
                'the result is in, and only while this widget still listens.',
              ),
              const SizedBox(height: 12),
              Toolbar(
                children: <Widget>[
                  ActionButton(
                    label: 'Run with callbacks',
                    filled: true,
                    onPressed: () => _runWithCallbacks(logging),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _LogPanel(_log),
            ],
          ),
        ),
        SectionCard(
          title: 'C. Scopes',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Mutations in the same MutationScope run one at a time: the '
                'second is pending from the start, paused, and its request '
                'is not sent until the first has settled. Without a scope, '
                'both requests go out together. Each takes a second on the '
                'backend.',
              ),
              const SizedBox(height: 12),
              Toolbar(
                children: <Widget>[
                  ActionButton(
                    label: 'Run two scoped',
                    filled: true,
                    onPressed: () {
                      _first.mutate((by: 1, fail: null));
                      _second.mutate((by: 1, fail: null));
                    },
                  ),
                  ActionButton(
                    label: 'Run two unscoped',
                    filled: true,
                    onPressed: () {
                      _third.mutate((by: 1, fail: null));
                      _fourth.mutate((by: 1, fail: null));
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: _pairs,
                builder: (context, _) => FactGroup(
                  name: 'mutation pairs',
                  facts: <String>[
                    'first=${_first.value.status.name}',
                    'second=${_second.value.status.name}',
                    'secondPaused=${_second.value.isPaused}',
                    'third=${_third.value.status.name}',
                    'fourth=${_fourth.value.status.name}',
                  ],
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'D. After the widget is gone',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Fires mutate and unmounts this reader in the same tap. The '
                'mutation belongs to the MutationCache, not to the widget: it '
                'runs to the end and invalidates the counter, which refetches '
                'when the reader comes back.',
              ),
              const SizedBox(height: 12),
              Toolbar(
                children: <Widget>[
                  ActionButton(
                    label: 'Fire and leave',
                    filled: true,
                    onPressed: () {
                      increment.mutate(_nextRequest());
                      widget.onLeave();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The callback log, one line per text.
class _LogPanel extends StatelessWidget {
  const _LogPanel(this.lines);

  final List<String> lines;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SemanticsGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (lines.isEmpty)
                const Text('log=empty', style: monoStyle)
              else
                for (final line in lines) Text(line, style: monoStyle),
            ],
          ),
        ),
      );
}

/// `isMutating=<n>`: how many mutations in the whole cache are pending, read
/// from the client on every mutation-cache event.
///
/// Subscribed to the cache directly rather than through `CacheStats`, which
/// only listens to the query cache. Rebuilt the way the debug strip is: an
/// event can arrive from inside a frame, when a rebuild has to wait for it
/// to end.
class _IsMutatingCount extends StatefulWidget {
  const _IsMutatingCount();

  @override
  State<_IsMutatingCount> createState() => _IsMutatingCountState();
}

class _IsMutatingCountState extends State<_IsMutatingCount>
    with PhaseSafeRebuild<_IsMutatingCount> {
  late final QueryClient _client;
  late final void Function() _unsubscribe;

  @override
  void initState() {
    super.initState();
    _client = QueryClientProvider.read(context);
    _unsubscribe = _client.mutationCache.subscribe((_) => scheduleRebuild());
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'client.isMutating()',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(width: 8),
          Text('isMutating=${_client.isMutating()}', style: monoStyle),
        ],
      );
}
