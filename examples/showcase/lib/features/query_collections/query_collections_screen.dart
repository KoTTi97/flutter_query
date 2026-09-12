/// Query collections: a list of queries whose length and order change at
/// runtime. Port-specific — it is `QueriesObserver`, the homogeneous stand-in
/// for upstream's `useQueries` (the heterogeneous tuple and its `combine` step
/// are not ported; see PORTING_NOTES' divergence table).
///
/// `parallel-queries` is the fixed case: three controllers written side by
/// side. This screen is the case that needs a collection — the set of posts
/// on screen is data, not source code.
///
/// What the screen is built from: one `QueriesBuilder<Post, String>` over a
/// list of ids. `select` narrows each post to its title, so a refetch that
/// returns an equal post rebuilds nothing. Observers are reused by key **and
/// occurrence**, which is what makes the two interesting buttons honest:
/// reordering starts no request, and a second copy of an id gets its own
/// observer over the one shared cache entry.
///
/// The `Summary reader` switch adds the other shape: a `QueriesController`
/// over the same ids — the collection as a `ValueListenable`, for a widget
/// that is not a builder, here a `ready=n/m` line read through a
/// `ListenableBuilder`. It is a second collection, so every entry gains a
/// second observer, and `setQueries` follows the ids as the buttons change
/// them.
///
/// Proofs (widget tests in `test/features/query_collections_test.dart`,
/// end-to-end in `e2e/tests/query_collections.spec.ts`): opening fetches every
/// id once; `Reverse` reorders the results without a single new request;
/// adding an id fetches only the new one; removing one releases its observer;
/// a duplicate id shares the cache entry (`observers=2`, still one fetch);
/// the missing id fails alone while its neighbours keep their data; and the
/// summary reader, switched on, counts every member ready with a second
/// observer on each entry, follows an added id with one fetch shared by both
/// readers, and releases its observers when switched off.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/chrome.dart';
import '../../shared/debug_strip.dart';
import '../../shared/fact_group.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';

const Feature queryCollectionsFeature = Feature(
  id: 'query-collections',
  title: 'Query collections',
  summary: 'A list of queries that grows, shrinks and reorders at runtime.',
);

/// The id that is not in the seed: the backend answers 404, so one entry of
/// the collection fails while the rest are fine.
const int missingPostId = 999;

/// One member of the collection. `select` is what makes the collection
/// homogeneous in `String` while the cache still holds whole `Post`s.
QuerySelectOptions<Post, String> postTitleQuery(ShowcaseApi api, int id) =>
    QuerySelectOptions<Post, String>(
      queryKey: ShowcaseKeys.post(id),
      queryFn: (context) => api.post(id, signal: context.signal),
      select: (post) => post.title,
      retry: RetryPolicy.never,
    );

class QueryCollectionsScreen extends StatefulWidget {
  const QueryCollectionsScreen({super.key});

  @override
  State<QueryCollectionsScreen> createState() => _QueryCollectionsScreenState();
}

class _QueryCollectionsScreenState extends State<QueryCollectionsScreen> {
  static const List<int> _initial = <int>[1, 2, 3];

  List<int> _ids = _initial;
  int _nextId = 4;
  bool _summary = false;

  void _reverse() => setState(() => _ids = _ids.reversed.toList());

  void _add() => setState(() => _ids = <int>[..._ids, _nextId++]);

  void _removeLast() => setState(
      () => _ids = _ids.isEmpty ? _ids : _ids.sublist(0, _ids.length - 1));

  /// A second occurrence of an id already on screen: one cache entry, two
  /// observers, and still only the one fetch that entry already had.
  void _duplicateFirst() =>
      setState(() => _ids = _ids.isEmpty ? _ids : <int>[..._ids, _ids.first]);

  void _addMissing() => setState(() => _ids = <int>[..._ids, missingPostId]);

  void _reset() => setState(() {
        _ids = _initial;
        _nextId = 4;
      });

  @override
  Widget build(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    return FeatureScaffold(
      feature: queryCollectionsFeature,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.tonal(
                onPressed: _add,
                child: const Text('Add post'),
              ),
              OutlinedButton(
                onPressed: _ids.isEmpty ? null : _removeLast,
                child: const Text('Remove last'),
              ),
              OutlinedButton(
                onPressed: _ids.isEmpty ? null : _reverse,
                child: const Text('Reverse'),
              ),
              OutlinedButton(
                onPressed: _ids.isEmpty ? null : _duplicateFirst,
                child: const Text('Duplicate first'),
              ),
              OutlinedButton(
                onPressed: _addMissing,
                child: const Text('Add missing id'),
              ),
              TextButton(onPressed: _reset, child: const Text('Reset')),
            ],
          ),
        ),
        // The ids, as an exact text a test can read without counting cards.
        SemanticsGroup(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'ids=${_ids.join(',')}',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ),
        SwitchListTile(
          // No subtitle: it would fold into the switch's accessible name.
          title: const Text('Summary reader'),
          value: _summary,
          onChanged: (value) => setState(() => _summary = value),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'A QueriesController over the same ids: the collection as a '
            'ValueListenable, for a widget that is not a builder. A second '
            'collection is a second observer on every entry — and a second '
            'observer mounting on a stale entry refetches it once.',
          ),
        ),
        if (_summary)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SummaryReader(ids: _ids),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: QueriesBuilder<Post, String>(
            queries: <QuerySelectOptions<Post, String>>[
              for (final id in _ids) postTitleQuery(api, id),
            ],
            builder: (context, results) {
              if (results.isEmpty) {
                return const Notice('No queries in the collection.');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final (index, result) in results.indexed)
                    _CollectionRow(
                      position: index + 1,
                      id: _ids[index],
                      result: result,
                    ),
                ],
              );
            },
          ),
        ),
        // Strips for every id the screen can show, so a test can read the
        // observer count of an entry that has just been dropped as well.
        for (final id in <int>{..._ids, ..._initial, missingPostId})
          QueryDebugStrip(
            queryKey: ShowcaseKeys.post(id),
            label: 'post-$id',
          ),
      ],
    );
  }
}

/// The collection through a `QueriesController`: created once the client is
/// known, handed the new ids by `setQueries` whenever they change, read
/// through a `ListenableBuilder`, disposed with the widget.
class _SummaryReader extends StatefulWidget {
  const _SummaryReader({required this.ids});

  final List<int> ids;

  @override
  State<_SummaryReader> createState() => _SummaryReaderState();
}

class _SummaryReaderState extends State<_SummaryReader> {
  QueriesController<Post, String>? _controller;

  List<QuerySelectOptions<Post, String>> _queries(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    return <QuerySelectOptions<Post, String>>[
      for (final id in widget.ids) postTitleQuery(api, id),
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Created here, not in `initState`: the client is an inherited widget.
    final client = QueryClientProvider.of(context);
    if (_controller?.client != client) {
      _controller?.dispose();
      _controller = QueriesController<Post, String>(client, _queries(context));
    }
  }

  @override
  void didUpdateWidget(_SummaryReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ids != widget.ids) {
      _controller!.setQueries(_queries(context));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final results = controller.value;
        final ready = results.where((result) => result.isSuccess).length;
        final failed = results.where((result) => result.isError).length;
        return FactGroup(
          name: 'summary',
          facts: <String>[
            'ready=$ready/${results.length}',
            'failed=$failed',
          ],
        );
      },
    );
  }
}

/// One result of the collection, in the collection's own order.
class _CollectionRow extends StatelessWidget {
  const _CollectionRow({
    required this.position,
    required this.id,
    required this.result,
  });

  final int position;
  final int id;
  final QueryResult<String> result;

  @override
  Widget build(BuildContext context) => SectionCard(
        title: '#$position — post $id',
        trailing: switch (result) {
          QueryResult(isLoading: true) => const Pill('loading'),
          QueryResult(isRefetching: true) => const Pill('refreshing'),
          _ => const SizedBox.shrink(),
        },
        child: switch (result) {
          QueryPending() => const SkeletonBox(height: 20),
          QueryError(:final error, staleData: null) =>
            Notice('$error', error: true),
          QuerySuccess(:final data) ||
          QueryError(staleData: final data!) =>
            Text(data, style: Theme.of(context).textTheme.titleMedium),
        },
      );
}
