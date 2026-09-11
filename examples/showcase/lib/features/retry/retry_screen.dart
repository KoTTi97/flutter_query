/// `RetryPolicy` and `RetryDelay` on one query, with the failures scripted on
/// the backend: how many attempts a refused fetch costs, what the result says
/// between them, and how a first-load error differs from a refused refetch.
///
/// Port-specific; it illustrates upstream's *Query Retries* guide
/// (`docs/framework/react/guides/query-retries.md`). Upstream's
/// `retry: false | number | true | fn` is the sealed [RetryPolicy] here —
/// `never`, `times`, `always`, `when` — and `retryDelay: ms | fn` is
/// [RetryDelay]: `fixed`, `exponential`, and `dynamic` for a wait computed
/// from the attempt and what it threw; the guide's note that the error is the
/// result's `failureReason` until the last attempt is what the
/// `failureReason=` fact shows.
///
/// The reader is a `QueryController` created next to the api and read through
/// a `ListenableBuilder`, so a knob change reaches the live observer through
/// `setOptions` — and detaching it, then attaching a fresh one, is the mount
/// that `retryOnMount` decides about.
///
/// Proofs (widget tests in `test/features/retry_test.dart`, end-to-end in
/// `e2e/tests/retry.spec.ts`): with `never` one refused request is the error,
/// `failureCount=1` and `isLoadingError=true`; with `2 times` and two refusals
/// the failure count climbs 1 → 2 while the retries run and the third attempt
/// succeeds, three requests in all; with ten refusals the same policy ends in
/// `failureCount=3`, still three requests; `always` goes on past the third
/// failure and past a 404 until the eleventh attempt succeeds; a refused
/// *refetch* keeps the old serial on screen as `isRefetchError` with
/// `hasStaleData=true`; `when 5xx` retries a 503 and gives up on a 404 after
/// one request; an errored entry is refetched when a fresh reader mounts with
/// `retryOnMount` on and left alone when it is off; the exponential delay has
/// not reached its first retry at 400 ms, where the fixed 300 ms one already
/// has; and the dynamic delay waits four seconds after a 404 and 200 ms after
/// a 503, because it is computed from the error.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/debug_strip.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';
import '../../shared/theme.dart';

const Feature retryFeature = Feature(
  id: 'retry',
  title: 'Retry',
  summary: 'Retry policies and delays, and what the result shows meanwhile.',
);

/// This screen's own cache entry. Deliberately not `ShowcaseKeys.time`: the
/// scripted failures armed here would otherwise reach the entry the
/// `stale-and-gc` screen keeps.
QueryKey get retryTimeKey => QueryKey(const <Object?>['retry', 'time']);

/// Retry a server error up to three times, and never a 404 — the guide's
/// `retry: (failureCount, error) => …`, which is where a policy gets to look
/// at what was thrown.
///
/// A top-level function, not a closure: [RetryWhen] is compared by the
/// identity of its predicate, and an inline one would be a different value on
/// every build, so the segmented button would never find its own choice
/// selected.
bool _retryServerErrors(int failureCount, Object error, StackTrace _) =>
    failureCount < 3 && error is BackendException && (error.status ?? 0) >= 500;

const RetryPolicy _when5xx = RetryPolicy.when(_retryServerErrors);
const RetryDelay _fixed300 = RetryDelay.fixed(Duration(milliseconds: 300));

/// A wait computed from what the attempt threw — the guide's
/// `retryDelay: (attempt, error) => …`: a 404 is not going to change its mind
/// soon, so it waits four seconds; anything else is retried after 200 ms.
///
/// A top-level function for the same reason as [_retryServerErrors]:
/// [RetryDelayDynamic] compares by the identity of its function.
Duration _delayByStatus(int failureCount, Object error) =>
    error is BackendException && error.status == 404
        ? const Duration(seconds: 4)
        : const Duration(milliseconds: 200);

const RetryDelay _dynamic = RetryDelay.dynamic(_delayByStatus);

/// The screen's one query, with the three knobs the screen turns.
QueryObserverOptions<ServerTime> retryTimeQuery(
  ShowcaseApi api, {
  required RetryPolicy retry,
  required RetryDelay retryDelay,
  required bool retryOnMount,
}) =>
    QueryObserverOptions<ServerTime>(
      queryKey: retryTimeKey,
      queryFn: (context) => api.time(signal: context.signal),
      retry: retry,
      retryDelay: retryDelay,
      retryOnMount: retryOnMount,
    );

class RetryScreen extends StatefulWidget {
  const RetryScreen({super.key});

  @override
  State<RetryScreen> createState() => _RetryScreenState();
}

class _RetryScreenState extends State<RetryScreen> {
  static const List<(String, RetryPolicy)> _retries = <(String, RetryPolicy)>[
    ('never', RetryPolicy.never),
    ('2 times', RetryPolicy.times(2)),
    ('always', RetryPolicy.always),
    ('when 5xx', _when5xx),
  ];

  static const List<(String, RetryDelay)> _delays = <(String, RetryDelay)>[
    ('300 ms', _fixed300),
    ('exponential', RetryDelay.defaultValue),
    ('dynamic', _dynamic),
  ];

  static const List<(String, int)> _statuses = <(String, int)>[
    ('503', 503),
    ('404', 404),
  ];

  static const List<(String, int)> _counts = <(String, int)>[
    ('0', 0),
    ('2', 2),
    ('10', 10),
  ];

  RetryPolicy _retry = RetryPolicy.never;
  RetryDelay _delay = _fixed300;
  int _status = 503;
  int _failNext = 0;
  bool _retryOnMount = true;

  /// What the backend was last told to refuse, as the `armed=` fact.
  String _armed = 'none';

  late final ShowcaseApi _api;
  late final QueryClient _client;
  bool _initialised = false;

  /// The reader, or null while detached. Built in [didChangeDependencies]
  /// rather than `initState` because the api and the client are inherited.
  QueryController<ServerTime, ServerTime>? _reader;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialised) {
      _initialised = true;
      _api = ShowcaseScope.apiOf(context);
      _client = QueryClientProvider.of(context);
      _reader = QueryController.create<ServerTime>(_client, _options);
    }
  }

  @override
  void dispose() {
    _reader?.dispose();
    super.dispose();
  }

  QueryObserverOptions<ServerTime> get _options => retryTimeQuery(
        _api,
        retry: _retry,
        retryDelay: _delay,
        retryOnMount: _retryOnMount,
      );

  /// A changed knob reaches the live reader through `setOptions`; a detached
  /// one picks it up on the next attach.
  void _applyOptions() {
    setState(() {
      _reader?.setOptions(_options);
    });
  }

  void _attach() {
    setState(() {
      // A new controller is a new observer, and subscribing it is a mount —
      // which is the moment `retryOnMount` decides.
      _reader = QueryController.create<ServerTime>(_client, _options);
    });
  }

  void _detach() {
    setState(() {
      _reader?.dispose();
      _reader = null;
    });
  }

  /// Tells the backend to refuse the next `_failNext` reads of `/api/time`.
  ///
  /// A count of zero still sends the script: it replaces whatever was armed
  /// before, which is how the screen disarms.
  Future<void> _arm() async {
    final count = _failNext;
    final status = _status;
    String armed;
    try {
      await _api.configureScenario(
        failNext: <FailNext>[
          FailNext(
            method: 'GET',
            path: '/api/time',
            count: count,
            status: status,
          ),
        ],
      );
      armed = count == 0 ? 'none' : '$count@$status';
    } on Object {
      armed = 'failed';
    }
    if (mounted) {
      setState(() => _armed = armed);
    }
  }

  /// One knob: its name, and a segmented button in a named semantics group,
  /// so a test can pick this knob's `2` apart from another's.
  Widget _knob<T extends Object>(
    BuildContext context, {
    required String name,
    required String semanticsKey,
    required List<(String, T)> choices,
    required T selected,
    required ValueChanged<T> onChanged,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(name, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          // Scrolls sideways rather than overflowing on a narrow phone.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: semanticsKey,
              child: SegmentedButton<T>(
                key: ValueKey<String>(semanticsKey),
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: <ButtonSegment<T>>[
                  for (final (label, value) in choices)
                    ButtonSegment<T>(value: value, label: Text(label)),
                ],
                selected: <T>{selected},
                onSelectionChanged: (selection) => onChanged(selection.single),
              ),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final reader = _reader;
    final small = Theme.of(context).textTheme.bodySmall;
    return FeatureScaffold(
      feature: retryFeature,
      children: <Widget>[
        SectionCard(
          title: 'Server time',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                tooltip: 'Refetch',
                onPressed: reader?.refetch,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Detach reader',
                onPressed: reader == null ? null : _detach,
                icon: const Icon(Icons.visibility_off),
              ),
              IconButton(
                tooltip: 'Attach reader',
                onPressed: reader == null ? _attach : null,
                icon: const Icon(Icons.visibility),
              ),
            ],
          ),
          child: reader == null
              ? const _Reading(
                  facts: <String>['reader=detached'],
                  child: Text(
                    'No reader. Attaching a fresh one is a mount: with '
                    'Retry on mount off an errored entry is left alone.',
                  ),
                )
              : ListenableBuilder(
                  listenable: reader,
                  builder: (context, _) => _reading(context, reader.value),
                ),
        ),
        QueryDebugStrip(queryKey: retryTimeKey, label: 'time'),
        SectionCard(
          title: 'Policy',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _knob<RetryPolicy>(
                context,
                name: 'Retry',
                semanticsKey: 'retry',
                choices: _retries,
                selected: _retry,
                onChanged: (value) {
                  _retry = value;
                  _applyOptions();
                },
              ),
              const SizedBox(height: 4),
              Text(
                '2 times means one attempt plus two retries — the count a '
                'policy is asked about is how many attempts had already '
                'failed, so it starts at 0. always retries until an attempt '
                'succeeds, whatever the error. when 5xx retries a server '
                'error up to three times and gives up on a 404 at once.',
                style: small,
              ),
              const SizedBox(height: 8),
              _knob<RetryDelay>(
                context,
                name: 'Delay',
                semanticsKey: 'delay',
                choices: _delays,
                selected: _delay,
                onChanged: (value) {
                  _delay = value;
                  _applyOptions();
                },
              ),
              const SizedBox(height: 4),
              Text(
                'exponential is the default: one second, two, four, capped at '
                'thirty. The delay is computed before the failure is counted, '
                'so the first retry waits one second. dynamic is computed '
                'from the attempt and its error: four seconds after a 404, '
                '200 ms after anything else.',
                style: small,
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Scripted failures',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'armed=$_armed',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () => _arm().ignore(),
                child: const Text('Arm'),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _knob<int>(
                context,
                name: 'Fail the next',
                semanticsKey: 'fail-next',
                choices: _counts,
                selected: _failNext,
                onChanged: (value) => setState(() => _failNext = value),
              ),
              const SizedBox(height: 8),
              _knob<int>(
                context,
                name: 'Status',
                semanticsKey: 'status',
                choices: _statuses,
                selected: _status,
                onChanged: (value) => setState(() => _status = value),
              ),
              const SizedBox(height: 4),
              Text(
                'Arm hands the script to the backend; Refetch then spends it. '
                'Zero disarms whatever was armed before.',
                style: small,
              ),
            ],
          ),
        ),
        SectionCard(
          // Not "Retry on mount": that is the switch's own name, and two
          // texts alike would be two nodes a test cannot tell apart.
          title: 'Mounting an errored entry',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SwitchListTile(
                // No subtitle: it would become part of the switch's
                // accessible name, and the explanation is below instead.
                title: const Text('Retry on mount'),
                value: _retryOnMount,
                onChanged: (value) {
                  _retryOnMount = value;
                  _applyOptions();
                },
              ),
              Text(
                'Only an entry that ended in an error with no data is '
                'affected: with the switch on a fresh reader fetches again, '
                'with it off the error stands until something asks for it.',
                style: small,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reading(BuildContext context, QueryResult<ServerTime> time) {
    final data = time.dataOrNull;
    final failed = time is QueryError<ServerTime> ? time : null;
    return _Reading(
      facts: <String>[
        'reader=attached',
        'status=${time.status.name}',
        'fetchStatus=${time.fetchStatus.name}',
        'failureCount=${time.failureCount}',
        'failureReason=${time.failureReason ?? 'none'}',
        'isLoadingError=${failed?.isLoadingError ?? false}',
        'isRefetchError=${failed?.isRefetchError ?? false}',
        'hasStaleData=${failed?.hasStaleData ?? false}',
        'serial=${data?.serial ?? 'none'}',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          switch (time) {
            QueryPending() => const SkeletonBox(width: 200),
            QueryError(:final error, staleData: null) =>
              Notice('$error', error: true),
            QuerySuccess(:final data) ||
            QueryError(staleData: final data!) =>
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (time case QueryError(:final error)) ...<Widget>[
                    Notice('Refetch failed: $error', error: true),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Server time #${data.serial}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (time.isFetching) const Pill('refreshing'),
                    ],
                  ),
                ],
              ),
          },
          if (time.isError) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              // The result's own `refetch`, which is what an error state is
              // expected to offer; it ignores `enabled` and `staleTime`.
              child: TextButton(
                onPressed: time.refetch,
                child: const Text('Retry now'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What the reader shows, and its own facts as `key=value` texts in a
/// semantics group of their own, so a test tells the reader's `status=` apart
/// from the strip's.
class _Reading extends StatelessWidget {
  const _Reading({required this.facts, required this.child});

  final List<String> facts;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          child,
          const SizedBox(height: 8),
          Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'reader',
            child: Wrap(
              key: const ValueKey<String>('reader-facts'),
              spacing: 12,
              children: <Widget>[
                for (final fact in facts)
                  Text(
                    fact,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
}
