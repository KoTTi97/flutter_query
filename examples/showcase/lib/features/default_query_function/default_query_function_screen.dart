/// Upstream's `default-query-function` example: no query on this screen
/// carries a `queryFn`. One function, registered once as a default for every
/// key under `['api', …]`, reads the request path out of the key and fetches
/// it, so a query is nothing but its key. The mutation twin,
/// `setMutationDefaults`, hands a mutation with only a `mutationKey` its
/// function the same way.
///
/// Upstream sets the function client-wide; here it is a per-key default on
/// the app's shared client, registered in `initState` and blanked again in
/// `dispose`, so no other screen sees it.
///
/// Proofs (widget tests in `test/features/default_query_function_test.dart`,
/// end-to-end in `e2e/tests/default_query_function.spec.ts`): three keyed
/// queries fetch exactly one request each and show parsed data; the defaults
/// panel reports `default queryFn=set`; a mutation with only a key posts once
/// and shows the new todo's id; leaving the screen blanks the defaults, after
/// which a query on the same key fails with `MissingQueryFunctionError`
/// instead of fetching; a key whose path has no post behind it shows the
/// backend's 404 message.
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

const Feature defaultQueryFunctionFeature = Feature(
  id: 'default-query-function',
  title: 'Default query function',
  summary: 'A query function derived from the key, set once as a default.',
  upstream: 'default-query-function',
);

/// The prefix the default query function is registered under.
QueryKey get apiPrefix => QueryKey(const <Object?>['api']);

/// The key for a GET of [path]. The key is the request: `['api', '/posts']`
/// is fetched by the default as `GET /api/posts`.
QueryKey apiKey(String path) => QueryKey(<Object?>['api', path]);

/// The key of the one mutation on this screen, and of its default.
QueryKey get createTodoKey =>
    QueryKey(const <Object?>['api', 'todos', 'create']);

/// The default: the path is the key's second part, and the JSON comes back
/// untyped — one function serves every key under the prefix, so it cannot
/// know the type; each query's `select` does.
QueryDefaults apiDefaults(ShowcaseApi api) => QueryDefaults(
      queryFn: (context) => api.getJson(
        context.queryKey.parts[1]! as String,
        signal: context.signal,
      ),
    );

/// The mutation twin: `createTodo` under the mutation's key, erased the same
/// way, so the mutation itself carries nothing but the key.
MutationDefaults createTodoDefaults(ShowcaseApi api) => MutationDefaults(
      mutationFn: (variables) => api.createTodo(variables! as String),
    );

// The queries. None takes the api: they have no function to close over.
// The selectors are top-level functions rather than closures, so the options
// built on every build compare equal and the parsed list is kept, not
// re-parsed into a fresh one per rebuild.

QueryObserverOptions<Object?, List<Post>> postsQuery() =>
    QueryObserverOptions<Object?, List<Post>>(
      queryKey: apiKey('/posts'),
      select: _parsePosts,
    );

QueryObserverOptions<Object?, Post> postQuery(int id) =>
    QueryObserverOptions<Object?, Post>(
      queryKey: apiKey('/posts/$id'),
      select: _parsePost,
    );

QueryObserverOptions<Object?, List<Comment>> commentsQuery(int postId) =>
    QueryObserverOptions<Object?, List<Comment>>(
      queryKey: apiKey('/posts/$postId/comments'),
      select: _parseComments,
    );

/// A key whose path has no post behind it. Every other option is still the
/// query's own: what the backend's 404 means is settled here, once, rather
/// than after the default backoff.
QueryObserverOptions<Object?, Post> missingPostQuery() =>
    QueryObserverOptions<Object?, Post>(
      queryKey: apiKey('/posts/999'),
      select: _parsePost,
      retry: RetryPolicy.never,
    );

MutationOptions<Todo, String, void> createTodoMutation() =>
    MutationOptions<Todo, String, void>(mutationKey: createTodoKey);

List<Post> _parsePosts(Object? json) => (json! as List<Object?>)
    .map((item) => Post.fromJson(item! as Map<String, Object?>))
    .toList();

Post _parsePost(Object? json) => Post.fromJson(json! as Map<String, Object?>);

List<Comment> _parseComments(Object? json) => (json! as List<Object?>)
    .map((item) => Comment.fromJson(item! as Map<String, Object?>))
    .toList();

class DefaultQueryFunctionScreen extends StatefulWidget {
  const DefaultQueryFunctionScreen({super.key});

  @override
  State<DefaultQueryFunctionScreen> createState() =>
      _DefaultQueryFunctionScreenState();
}

class _DefaultQueryFunctionScreenState extends State<DefaultQueryFunctionScreen>
    with QueryMixin {
  /// Kept from `initState` for `dispose`, which may not look anything up.
  late final QueryClient _client;
  bool _fetchMissing = false;

  @override
  void initState() {
    super.initState();
    // Plain reads, not dependencies: a State may not depend on an inherited
    // widget before `initState` has completed, and neither the client nor
    // the api changes underneath a screen.
    _client = QueryClientProvider.read(context);
    final api = context.getInheritedWidgetOfExactType<ShowcaseScope>()!.api;
    _client.setQueryDefaults(apiPrefix, apiDefaults(api));
    _client.setMutationDefaults(createTodoKey, createTodoDefaults(api));
  }

  @override
  void dispose() {
    // Blanked rather than removed — the client has no "unset" — which comes
    // to the same: the next query under the prefix finds no `queryFn`.
    _client.setQueryDefaults(apiPrefix, const QueryDefaults());
    _client.setMutationDefaults(createTodoKey, const MutationDefaults());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final posts = watchSelectQuery<Object?, List<Post>>(postsQuery());
    final post = watchSelectQuery<Object?, Post>(postQuery(1));
    final comments = watchSelectQuery<Object?, List<Comment>>(commentsQuery(1));
    // Read only once asked for: the mixin releases a key a build stops
    // reading, and creates the observer the first time one reads it.
    final missing = _fetchMissing
        ? watchSelectQuery<Object?, Post>(missingPostQuery())
        : null;
    final create = watchMutation<Todo, String, void>(createTodoMutation());

    final client = queryClient;
    final queryDefault = client.getQueryDefaults(apiKey('/posts'))?.queryFn;
    final mutationDefault =
        client.getMutationDefaults(createTodoKey)?.mutationFn;

    return FeatureScaffold(
      feature: defaultQueryFunctionFeature,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Notice(
            'The key is the request: none of these queries has a queryFn, '
            "and the default registered for ['api', …] fetches the path it "
            'finds in the key.',
          ),
        ),
        SectionCard(
          title: 'Defaults on the client',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Asked for ${apiKey('/posts').debugString} and '
                '${createTodoKey.debugString}:',
              ),
              const SizedBox(height: 4),
              Text('default queryFn=${_setOrNone(queryDefault)}'),
              Text('default mutationFn=${_setOrNone(mutationDefault)}'),
            ],
          ),
        ),
        SectionCard(
          title: 'Posts',
          trailing: _fetchingPill(posts),
          child: _view<List<Post>>(
            posts,
            (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final item in data.take(5))
                  Text('#${item.id} ${item.title}'),
                if (data.length > 5) Text('… and ${data.length - 5} more'),
                const SizedBox(height: 4),
                Text('posts=${data.length}'),
              ],
            ),
          ),
        ),
        QueryDebugStrip(queryKey: apiKey('/posts'), label: 'posts'),
        SectionCard(
          title: 'Post #1',
          trailing: _fetchingPill(post),
          child: _view<Post>(
            post,
            (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  data.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(data.body),
              ],
            ),
          ),
        ),
        QueryDebugStrip(queryKey: apiKey('/posts/1'), label: 'post-1'),
        SectionCard(
          title: 'Comments on post #1',
          trailing: _fetchingPill(comments),
          child: _view<List<Comment>>(
            comments,
            (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final comment in data)
                  LabeledRow(comment.author, comment.text),
                const SizedBox(height: 4),
                Text('comments=${data.length}'),
              ],
            ),
          ),
        ),
        QueryDebugStrip(
          queryKey: apiKey('/posts/1/comments'),
          label: 'comments-1',
        ),
        SectionCard(
          title: 'A key with no post behind it',
          trailing: Tooltip(
            message: 'Fetch a missing post',
            child: OutlinedButton(
              onPressed: _fetchMissing
                  ? null
                  : () => setState(() => _fetchMissing = true),
              child: const Text('Fetch a missing post'),
            ),
          ),
          child: missing == null
              ? const Text(
                  "['api', '/posts/999'] goes through the same default; "
                  'the backend decides what it answers.',
                )
              : _view<Post>(missing, (data) => Text(data.title)),
        ),
        QueryDebugStrip(queryKey: apiKey('/posts/999'), label: 'post-999'),
        SectionCard(
          title: 'A mutation with only a key',
          trailing: Tooltip(
            message: 'Create a todo',
            child: FilledButton.tonal(
              onPressed: create.value.isPending
                  ? null
                  : () => create.mutate('Written by the default mutationFn'),
              child: const Text('Create a todo'),
            ),
          ),
          child: switch (create.value) {
            MutationIdle() => const Text(
                'The mutation carries its key and nothing else; its '
                'function is the default registered for that key.',
              ),
            MutationPending() => const Text('creating…'),
            MutationSuccess(:final data) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('new todo id=${data.id}'),
                  Text(data.text),
                ],
              ),
            MutationError(:final error) => Notice('$error', error: true),
          },
        ),
      ],
    );
  }

  static String _setOrNone(Object? function) =>
      function == null ? 'none' : 'set';

  static Widget? _fetchingPill(QueryResult<Object?> result) =>
      result.isFetching && !result.isPending ? const Pill('refreshing') : null;

  /// One query's states; the data goes through [body].
  static Widget _view<T>(QueryResult<T> result, Widget Function(T data) body) =>
      switch (result) {
        QueryPending() => const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SkeletonBox(height: 20, width: 240),
              SizedBox(height: 8),
              SkeletonBox(),
            ],
          ),
        QueryError(:final error, staleData: null) =>
          Notice('$error', error: true),
        QuerySuccess(:final data) ||
        QueryError(staleData: final T data) =>
          body(data),
      };
}
