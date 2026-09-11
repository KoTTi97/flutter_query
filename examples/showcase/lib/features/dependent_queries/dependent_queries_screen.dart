/// Dependent queries: a query that waits for another's data, upstream's
/// `enabled` used the way its dependent-queries guide shows. Port-specific —
/// there is no `react` example for it; the guide is
/// `docs/framework/react/guides/dependent-queries.md`.
///
/// A chooser picks a post. The post's query exists only once a choice is
/// made; the comments' query exists alongside it but is `Enabled.when` the
/// post has data, so it starts `pending`/`idle`, turns `fetching` the moment
/// the post lands, and never runs in parallel with it. A "Pause comments"
/// checkbox forces `Enabled.no` regardless of the post, which is the other
/// way to hold a query back. Every query here is read with `context.query`.
///
/// Proofs (widget tests in `test/features/dependent_queries_test.dart`,
/// end-to-end in `e2e/tests/dependent_queries.spec.ts`): before a choice no
/// request goes out; choosing a post fetches it first and the comments once
/// afterwards, never before; pausing keeps the comments idle and disabled
/// even with the post in hand, and unpausing fetches them once; switching
/// posts re-keys both queries and keeps the old entries in the cache; clearing
/// the choice releases the observers.
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

const Feature dependentQueriesFeature = Feature(
  id: 'dependent-queries',
  title: 'Dependent queries',
  summary: 'A query that waits for another to have data.',
);

/// The post the comments depend on.
QueryObserverOptions<Post> postQuery(ShowcaseApi api, int id) =>
    QueryObserverOptions<Post>(
      queryKey: ShowcaseKeys.post(id),
      queryFn: (context) => api.post(id, signal: context.signal),
    );

/// The comments of a post. [enabled] is the whole point of the screen: the
/// caller decides when this query may run, and until then it sits
/// `pending`/`idle` without a request.
QueryObserverOptions<List<Comment>> commentsQuery(
  ShowcaseApi api,
  int postId, {
  required Enabled enabled,
}) =>
    QueryObserverOptions<List<Comment>>(
      queryKey: ShowcaseKeys.comments(postId),
      queryFn: (context) => api.comments(postId, signal: context.signal),
      enabled: enabled,
    );

class DependentQueriesScreen extends StatefulWidget {
  const DependentQueriesScreen({super.key});

  @override
  State<DependentQueriesScreen> createState() => _DependentQueriesScreenState();
}

class _DependentQueriesScreenState extends State<DependentQueriesScreen> {
  int? _chosen;
  bool _paused = false;

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: dependentQueriesFeature,
        children: <Widget>[
          SectionCard(
            title: 'Choose a post',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final id in const <int>[1, 2, 3])
                      _LabeledButton(
                        label: 'Choose post $id',
                        selected: _chosen == id,
                        onPressed: () => setState(() => _chosen = id),
                      ),
                    _LabeledButton(
                      label: 'Clear choice',
                      onPressed: _chosen == null
                          ? null
                          : () => setState(() => _chosen = null),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // No subtitle: a tile folds it into the checkbox's accessible
                // name, and the tests find the box by its title alone.
                CheckboxListTile(
                  title: const Text('Pause comments'),
                  contentPadding: EdgeInsets.zero,
                  value: _paused,
                  onChanged: (value) =>
                      setState(() => _paused = value ?? false),
                ),
                Text(
                  'Ticked, the comments query is Enabled.no whatever the post '
                  'says; unticked, it is Enabled.when the post has data.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          // The reads live in a widget of their own that is only in the tree
          // while a post is chosen. `context.query` releases a key a widget
          // stops reading, but a widget that stops reading altogether gives
          // the binding nothing to compare against; unmounting does.
          if (_chosen case final int id)
            _ChosenPost(id: id, pauseComments: _paused)
          else
            const SectionCard(
              title: 'Post',
              child: Text('Choose a post first.'),
            ),
        ],
      );
}

/// The two dependent queries for one post, read in `build`.
///
/// No `key` on purpose: when the choice changes, this same widget reads
/// different keys on its next build, and the binding lets the old observers
/// go after the frame — the old entries stay in the cache without a reader.
class _ChosenPost extends StatelessWidget {
  const _ChosenPost({required this.id, required this.pauseComments});

  final int id;
  final bool pauseComments;

  @override
  Widget build(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    final post = context.query(postQuery(api, id));
    // The dependency itself: the comments may run once the post has data.
    // The predicate is handed the comments query and ignores it; what it
    // closes over is this build's post result.
    final comments = context.query(commentsQuery(
      api,
      id,
      enabled: pauseComments
          ? Enabled.no
          : Enabled.when((_) => post.dataOrNull != null),
    ));
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionCard(
          title: 'Post #$id',
          trailing: post.isFetching ? const Pill('fetching') : null,
          child: switch (post) {
            QueryPending() => const SkeletonBox(height: 20, width: 240),
            QueryError(:final error, staleData: null) =>
              Notice('$error', error: true),
            QuerySuccess(:final data) ||
            QueryError(staleData: final data!) =>
              Text(data.title, style: theme.textTheme.titleLarge),
          },
        ),
        SectionCard(
          title: 'Comments',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (comments.isFetching) const Pill('fetching'),
              if (!comments.isEnabled) ...<Widget>[
                const SizedBox(width: 8),
                Pill(
                  pauseComments ? 'paused' : 'waiting for the post',
                  color: theme.colorScheme.tertiary,
                ),
              ],
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'comments enabled=${comments.isEnabled}',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
              switch (comments) {
                QueryPending(fetchStatus: FetchStatus.fetching) =>
                  const SkeletonBox(),
                QueryPending() => Text(
                    pauseComments
                        ? 'Paused: no request until the box is unticked.'
                        : 'Not started: the post has no data yet.',
                    style: theme.textTheme.bodySmall,
                  ),
                QueryError(:final error, staleData: null) =>
                  Notice('$error', error: true),
                QuerySuccess(:final data) ||
                QueryError(staleData: final data!) =>
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'comments count=${data.length}',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      for (final comment in data)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                comment.author,
                                style: theme.textTheme.labelLarge,
                              ),
                              Text(comment.text),
                            ],
                          ),
                        ),
                    ],
                  ),
              },
            ],
          ),
        ),
        QueryDebugStrip(queryKey: ShowcaseKeys.post(id), label: 'post-$id'),
        QueryDebugStrip(
          queryKey: ShowcaseKeys.comments(id),
          label: 'comments-$id',
        ),
      ],
    );
  }
}

/// A text button whose accessible name is exactly its label.
///
/// The label is the button's own semantics; the tooltip is hover-only. A
/// `Tooltip` that also reaches the semantics tree becomes a node of its own
/// *around* the button's — a `FilledButton` has no `tooltip` of its own to
/// place inside, the way an `IconButton` does — and the button underneath
/// it would be left without a name.
class _LabeledButton extends StatelessWidget {
  const _LabeledButton({
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: selected
            ? FilledButton(onPressed: onPressed, child: Text(label))
            : FilledButton.tonal(onPressed: onPressed, child: Text(label)),
      );
}
