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
/// Proofs (widget tests in `test/features/query_collections_test.dart`,
/// end-to-end in `e2e/tests/query_collections.spec.ts`): opening fetches every
/// id once; `Reverse` reorders the results without a single new request;
/// adding an id fetches only the new one; removing one releases its observer;
/// a duplicate id shares the cache entry (`observers=2`, still one fetch);
/// the missing id fails alone while its neighbours keep their data.
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
        Semantics(
          container: true,
          explicitChildNodes: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'ids=${_ids.join(',')}',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
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
