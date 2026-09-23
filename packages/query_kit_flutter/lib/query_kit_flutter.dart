/// The Flutter binding for `query_kit`: server state in Flutter apps —
/// fetching, caching, background refetching, pagination and mutations —
/// without writing any of that by hand.
///
/// query_kit is an entirely AI-coded project: all code, tests and
/// documentation were written by AI coding agents (Anthropic's Claude). A
/// human maintainer set the goals and reviews releases, but did not write the
/// code.
///
/// An independent community port of TanStack Query, not affiliated with or
/// endorsed by TanStack.
///
/// The core's whole surface (`QueryClient`, the options, the results) is
/// re-exported, so this one import is enough:
///
/// ```dart
/// import 'package:query_kit_flutter/query_kit_flutter.dart';
/// ```
///
/// ## Quick start
///
/// **1. Provide a client** above everything that reads it, with a
/// [QueryClientProvider]:
///
/// ```dart
/// void main() {
///   runApp(
///     QueryClientProvider.create(
///       create: QueryClient.new,
///       child: const MaterialApp(home: TasksScreen()),
///     ),
///   );
/// }
/// ```
///
/// **2. Describe a query** — a key, and a function that fetches it:
///
/// ```dart
/// final tasksKey = QueryKey(<Object?>['tasks']);
///
/// QueryObserverOptions<List<Task>> tasksQuery() => QueryObserverOptions(
///       queryKey: tasksKey,
///       queryFn: (context) => api.listTasks(),
///       staleTime: const StaleTime.duration(Duration(seconds: 30)),
///     );
/// ```
///
/// **3. Read it**, and **4. change it with a mutation** that invalidates it.
/// This one reads in `build` with `context.query`; any of the four call
/// styles below reads the same options the same way:
///
/// ```dart
/// class TasksScreen extends StatelessWidget {
///   const TasksScreen({super.key});
///
///   @override
///   Widget build(BuildContext context) {
///     final client = QueryClientProvider.of(context);
///     final tasks = context.query(tasksQuery());
///     final add = context.mutation(
///       MutationOptions.simple(
///         mutationFn: api.addTask,
///         onSuccess: (_, __, ___) => client.invalidateQueries(
///           filters: QueryFilters(queryKey: tasksKey),
///         ),
///       ),
///     );
///     return Scaffold(
///       body: switch (tasks) {
///         QueryPending() => const Center(child: CircularProgressIndicator()),
///         QueryError(:final error) => Center(child: Text('$error')),
///         QuerySuccess(:final data) => ListView(
///             children: [for (final task in data) Text(task.name)],
///           ),
///       },
///       floatingActionButton: FloatingActionButton(
///         onPressed:
///             add.value.isPending ? null : () => add.mutate('New task'),
///         child: const Icon(Icons.add),
///       ),
///     );
///   }
/// }
/// ```
///
/// ## Four equal ways to read a query
///
/// There is no recommended default: the four styles are equal alternatives,
/// layered rather than competing — each is a thin shell over the one below —
/// and they mix freely inside one screen. Each covers plain queries, queries
/// with a `select`, infinite queries and mutations, and each takes a
/// `buildWhen` to narrow when it rebuilds.
///
/// * [QueryContext] — `context.query(...)` and `context.mutation(...)` in
///   `build`, in a `StatelessWidget`; only the widgets that read a query
///   rebuild when it changes.
/// * [QueryMixin] — `watchQuery(...)` and `watchMutation(...)` in a
///   `State`'s `build`, owned and disposed by that `State`.
/// * [QueryBuilder], [QuerySelectBuilder], [InfiniteQueryBuilder],
///   [MutationBuilder] — the `StreamBuilder` shape: everything visible in the
///   tree, and the rebuild is exactly the builder's subtree.
/// * [QueryController], [InfiniteQueryController], [MutationController] —
///   plain `ValueListenable`s, usable without widgets, in view models and
///   with `ValueListenableBuilder` or any state-management package that reads
///   a listenable.
///
/// Beside them: [QueryListener], [InfiniteQueryListener] and
/// [MutationListener] for side effects; [QueriesBuilder], [QueriesController],
/// [MutationStateController] and [IsFetchingController] for collections; and
/// [OnlineStatus] for connectivity. Nothing here needs a package beyond
/// Flutter.
///
/// Guides, recipes and the full reference: https://dualmeta-gmbh.github.io/query_kit/
library;

export 'package:query_kit/query_kit.dart';

export 'src/is_fetching_controller.dart';
export 'src/mutation_state_controller.dart';
export 'src/online_status.dart';
export 'src/queries_builder.dart';
export 'src/queries_controller.dart';
export 'src/query_builder.dart';
export 'src/query_client_provider.dart';
export 'src/query_context.dart' hide QueryScope, QueryScopeElement;
export 'src/query_controller.dart' hide ObservedState, observedStateOf;
export 'src/query_listener.dart';
export 'src/query_mixin.dart';
