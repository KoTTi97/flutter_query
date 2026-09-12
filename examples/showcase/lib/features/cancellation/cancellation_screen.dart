/// Cancellation: the `signal` a query function is handed, what
/// `cancelQueries` does with it, and search-as-you-type as the everyday case.
///
/// Mirrors upstream's [Query Cancellation
/// guide](https://tanstack.com/query/latest/docs/framework/react/guides/query-cancellation)
/// rather than an example app; there is no `react/cancellation` example.
/// `ShowcaseApi.bridge` is the interop point the guide describes for axios:
/// `context.signal.onCancel(dioToken.cancel)`.
///
/// **What cancelling really does here** — checked against the core, not
/// assumed:
///
/// * `cancelQueries` always ends the fetch. The retryer is rejected with a
///   `CancelledError`, `revert: true` (the default) puts the state back to what
///   it was when the fetch started with `fetchStatus: idle`, and the fetch's
///   result — whenever it arrives — is dropped. A first fetch therefore goes
///   back to `status=pending`, not to an error.
/// * What the `signal` changes is whether the **transport** stops. Read it and
///   the HTTP request is aborted, so the backend never answers it and nothing
///   is logged there. Ignore it (the `Ignore the signal` switch) and the query
///   is still cancelled on the spot, but the request runs to completion at the
///   backend and only its answer is thrown away.
/// * The guide's "the data will still be available in the cache" is about the
///   *other* cancel: the one the core does by itself when the last observer
///   leaves. There, a query function that never read the signal has its retry
///   loop stopped and its in-flight request left alone, so its answer is
///   written; one that read the signal is cancelled with a revert. That is why
///   re-keying the search below already cancels the previous needle's fetch:
///   its last observer leaves and the signal was consumed. The explicit
///   `cancelQueries` in the debounce callback is what makes it a decision
///   rather than a side effect — and the only thing that would cancel a needle
///   another reader still holds.
///
/// Proofs (widget tests in `test/features/cancellation_test.dart`, end-to-end
/// in `e2e/tests/cancellation.spec.ts`): cancelling the slow fetch puts it
/// back to idle, counts one `signal.onCancel`, aborts the request and never
/// lets its answer land; a silent cancel does the same and reports no error;
/// restarting after a cancel loads all thirty posts; two keystrokes inside the
/// debounce window send one request, for the last needle; a keystroke after
/// the window cancels the needle in flight, leaving its entry pending and
/// idle; with `Ignore the signal` on, the request is not aborted — the backend
/// answers it — while the query is cancelled all the same; and leaving the
/// screen mid-fetch writes that answer to the cache when the signal was
/// ignored, but cancels and reverts when it was read.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/cache_listener.dart';
import '../../shared/chrome.dart';
import '../../shared/debug_strip.dart';
import '../../shared/fact_group.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';

const Feature cancellationFeature = Feature(
  id: 'cancellation',
  title: 'Cancellation',
  summary: 'A query cancelled is a request aborted.',
);

/// Long enough that a human can hit `Cancel` in the middle of it.
const Duration slowFetchDelay = Duration(seconds: 3);

/// Long enough that the next keystroke lands while the request is still out.
const Duration searchDelay = Duration(seconds: 1);

/// The window a keystroke waits before it becomes a needle.
const Duration searchDebounce = Duration(milliseconds: 300);

QueryKey get slowKey => QueryKey(const <Object?>['cancellation', 'slow']);

QueryKey searchKey(String needle) =>
    QueryKey(<Object?>['cancellation', 'search', needle]);

class CancellationScreen extends StatefulWidget {
  const CancellationScreen({super.key});

  @override
  State<CancellationScreen> createState() => _CancellationScreenState();
}

class _CancellationScreenState extends State<CancellationScreen>
    with PhaseSafeRebuild<CancellationScreen> {
  final TextEditingController _text = TextEditingController();

  late QueryClient _client;
  late ShowcaseApi _api;

  /// How often the slow query's `signal.onCancel` ran — the proof that the
  /// token reached dio, since it is dio's `cancel` that sits next to it.
  int _cancels = 0;
  int _searchCancels = 0;

  /// With this on, the query function never touches `context.signal`, which is
  /// what makes a fetch uncancellable at the transport.
  bool _ignoreSignal = false;

  Timer? _debounce;
  String _needle = '';
  String? _previousNeedle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _client = QueryClientProvider.of(context);
    _api = ShowcaseScope.apiOf(context);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  /// `onCancel` callbacks run synchronously inside the cancel, which may be a
  /// button's tap, a post-frame observer release, or a cache event during a
  /// build — so the rebuild waits for the frame to end when there is one.
  void _bumpDuringAnyPhase(VoidCallback change) {
    change();
    scheduleRebuild();
  }

  // --- the slow query ------------------------------------------------------

  QueryObserverOptions<List<Post>> get _slowQuery =>
      QueryObserverOptions<List<Post>>(
        queryKey: slowKey,
        queryFn: (context) {
          if (_ignoreSignal) {
            // Deliberately never reads `context.signal`: the query then has no
            // way to stop dio, and the core knows it.
            return _api.posts(delay: slowFetchDelay);
          }
          final signal = context.signal;
          signal.onCancel(() => _bumpDuringAnyPhase(() => _cancels += 1));
          return _api.posts(signal: signal, delay: slowFetchDelay);
        },
        // Nothing here fails on purpose, and a retry chain would only blur
        // what the cancel did.
        retry: RetryPolicy.never,
      );

  void _cancelSlow() => _cancel(silent: false);

  /// A silent cancel dispatches no error into the query's state; the revert
  /// still happens, so the reader sees the entry as it was before the fetch.
  void _cancelSlowSilently() => _cancel(silent: true);

  void _cancel({required bool silent}) => _client
      .cancelQueries(
        filters: QueryFilters(queryKey: slowKey, exact: true),
        silent: silent,
      )
      .ignore();

  // --- search as you type --------------------------------------------------

  QueryObserverOptions<List<Post>> _searchQuery(String needle) =>
      QueryObserverOptions<List<Post>>(
        queryKey: searchKey(needle),
        // An empty box asks the backend nothing.
        enabled: needle.isEmpty ? Enabled.no : Enabled.yes,
        queryFn: (context) {
          final signal = context.signal;
          signal.onCancel(() => _bumpDuringAnyPhase(() => _searchCancels += 1));
          return _api.search(needle, signal: signal, delay: searchDelay);
        },
        retry: RetryPolicy.never,
      );

  void _onTyped(String value) {
    _debounce?.cancel();
    _debounce = Timer(searchDebounce, () => _commit(value.trim()));
  }

  /// The debounce window closed on [next]. The needle in flight is cancelled
  /// here, before the read is re-keyed: an explicit decision, at a moment the
  /// screen names, rather than the release the core would do anyway once the
  /// old key's last observer leaves in the rebuild below.
  void _commit(String next) {
    if (!mounted || next == _needle) {
      return;
    }
    final previous = _needle;
    if (previous.isNotEmpty) {
      _client
          .cancelQueries(
            filters: QueryFilters(queryKey: searchKey(previous), exact: true),
          )
          .ignore();
    }
    setState(() {
      _previousNeedle = previous.isEmpty ? null : previous;
      _needle = next;
    });
  }

  // --- the screen ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return FeatureScaffold(
      feature: cancellationFeature,
      children: <Widget>[
        _slowCard(small),
        QueryDebugStrip(queryKey: slowKey, label: 'slow'),
        _searchCard(small),
        QueryDebugStrip(queryKey: searchKey(_needle), label: 'search'),
        if (_previousNeedle case final String previous)
          QueryDebugStrip(queryKey: searchKey(previous), label: 'previous'),
      ],
    );
  }

  Widget _slowCard(TextStyle? small) {
    // Read in build, so the card rebuilds with the query's every state.
    final posts = context.query(_slowQuery);
    return SectionCard(
      title: 'Cancel by hand',
      trailing: posts.isFetching ? const Pill('fetching') : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'A three-second fetch of /api/posts. Cancelling reverts the entry '
            'to what it was when the fetch began and drops the answer; the '
            'signal decides whether the request itself is aborted.',
            style: small,
          ),
          const SizedBox(height: 12),
          // A row folds its buttons into one semantics node otherwise, and
          // each button is found by the name its label gives it.
          SemanticsGroup(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton(
                  onPressed:
                      posts.isFetching ? null : () => posts.refetch().ignore(),
                  child: const Text('Start slow fetch'),
                ),
                OutlinedButton(
                  onPressed: _cancelSlow,
                  child: const Text('Cancel'),
                ),
                OutlinedButton(
                  onPressed: _cancelSlowSilently,
                  child: const Text('Cancel silently'),
                ),
              ],
            ),
          ),
          // No subtitle: a tile folds one into the switch's accessible name.
          SwitchListTile(
            title: const Text('Ignore the signal'),
            contentPadding: EdgeInsets.zero,
            value: _ignoreSignal,
            onChanged: (value) => setState(() => _ignoreSignal = value),
          ),
          Text(
            'With it on the query function never reads context.signal, so dio '
            'is never told to stop: the backend answers the request in full '
            'and the query throws the answer away.',
            style: small,
          ),
          const SizedBox(height: 12),
          FactGroup(
            name: 'slow facts',
            dense: true,
            facts: <String>[
              'fetchStatus=${posts.fetchStatus.name}',
              'status=${posts.status.name}',
              'posts=${switch (posts.dataOrNull) {
                null => 'none',
                final List<Post> data => '${data.length}',
              }}',
              'cancels=$_cancels',
            ],
          ),
        ],
      ),
    );
  }

  Widget _searchCard(TextStyle? small) => SectionCard(
        title: 'Search as you type',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Every needle is a key of its own. A keystroke that closes the '
              '300 ms window cancels the needle still in flight and re-keys '
              'the read, so only the last one can arrive.',
              style: small,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              onChanged: _onTyped,
              decoration: const InputDecoration(
                labelText: 'Search posts',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            QueryBuilder<List<Post>>(
              options: _searchQuery(_needle),
              builder: (context, results) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FactGroup(
                    name: 'search facts',
                    dense: true,
                    facts: <String>[
                      'needle=${_needle.isEmpty ? 'none' : _needle}',
                      'searching=${results.isFetching}',
                      'results=${switch (results.dataOrNull) {
                        null => 'none',
                        final List<Post> data => '${data.length}',
                      }}',
                      'searchCancels=$_searchCancels',
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 160,
                    // Eager children in a scroll view: a lazy list would not
                    // build the rows a test has to find.
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (results.dataOrNull case final List<Post> data)
                            for (final post in data)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 2, horizontal: 4),
                                child: Text(post.title),
                              ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
