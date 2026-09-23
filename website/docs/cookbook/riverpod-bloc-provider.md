---
title: Next to Riverpod, Bloc or Provider
sidebar_label: Riverpod, Bloc, Provider
description: Keep server state in query_kit and app state in your state-management package, and connect the two through QueryController without keeping a second copy.
sidebar_position: 11
---

# Next to Riverpod, Bloc or Provider

**The problem.** The app already uses Riverpod, Bloc or Provider. Adding
query_kit seems to mean choosing: either the store holds the server data and
the cache is wasted, or the cache holds it and the store is left out. You want
both. The screen's filter, the selected tab and the form draft stay in the
store; the projects the server returned are cached, deduplicated and
refetched by query_kit; and a widget sees both.

**The recipe.** Split state by owner. Anything the server owns lives in the
query cache, under a key. Anything the app owns lives in your store. Where one
depends on the other, the store holds the *input* (a filter string) and
derives the query's options from it. It never holds a copy of the result.
Every package in this recipe connects through the same adapter:
`QueryController`, a `ChangeNotifier` and `ValueListenable<QueryResult>`
that follows one query while something listens to it.

[Does this replace state management?](../guides/does-this-replace-state-management.md)
explains the split. This page shows how to wire it up.

## The queries: one file, no package

The options are plain functions in `lib/data/project_queries.dart`. Every
integration below calls them, and so does every widget that reads a query
directly.

```dart title="lib/data/project_queries.dart" snippet="cookbook/riverpod-bloc-provider.md#queries"
QueryObserverOptions<Project> projectQuery(String id) => QueryObserverOptions(
      queryKey: ProjectKeys.detail(id),
      queryFn: (context) => projectApi.get(id, signal: context.signal),
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    );

QueryObserverOptions<List<Project>> projectsQuery(String filter) =>
    QueryObserverOptions(
      queryKey: ProjectKeys.list(filter),
      queryFn: (context) =>
          projectApi.list(filter: filter, signal: context.signal),
    );
```

## Without a package: a view model

This is the shape the three integrations below all share. The view model
owns a controller, the controller owns the subscription, and a filter change
is one `setOptions` call. The controller moves to the new key in place. The
old entry stays cached, so switching back shows it at once.

```dart title="lib/features/projects/projects_view_model.dart" snippet="cookbook/riverpod-bloc-provider.md#view-model"
class ProjectsViewModel extends ChangeNotifier {
  ProjectsViewModel(QueryClient client)
      : projects = QueryController.create(client, projectsQuery('open'));

  /// Server state: a listenable of its own, owned and disposed here.
  final QueryController<List<Project>, List<Project>> projects;

  /// Client state: this app's alone, and never stale.
  String _filter = 'open';
  String get filter => _filter;

  void showFilter(String filter) {
    if (filter == _filter) return;
    _filter = filter;
    // The key follows the filter; the controller switches entries in place.
    projects.setOptions(projectsQuery(filter));
    notifyListeners();
  }

  @override
  void dispose() {
    projects.dispose();
    super.dispose();
  }
}
```

The screen listens to both parts of the model: the filter, and the
controller's results.

```dart title="lib/features/projects/projects_page.dart" snippet="cookbook/riverpod-bloc-provider.md#view-model-screen"
@override
Widget build(BuildContext context) => ListenableBuilder(
      // Rebuilds for either kind of state: a new filter, or a new result.
      listenable: Listenable.merge(<Listenable>[model, model.projects]),
      builder: (context, _) => Column(
        children: <Widget>[
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment(value: 'open', label: Text('Open')),
              ButtonSegment(value: 'archived', label: Text('Archived')),
            ],
            selected: <String>{model.filter},
            onSelectionChanged: (selection) =>
                model.showFilter(selection.single),
          ),
          for (final project
              in model.projects.value.dataOrNull ?? const <Project>[])
            ListTile(title: Text(project.name)),
        ],
      ),
    );
```

The view model is created in a `State` with
`QueryClientProvider.read(context)` and disposed with it. [Dependency
injection](dependency-injection.md) covers where the client comes from.

## Riverpod

This section targets **Riverpod 3.x** (`flutter_riverpod` 3). The client is a
provider, so notifiers can reach it, and it is also handed to a
`QueryClientProvider`, so the widgets below it can read queries directly.

```dart title="lib/app/query_client.dart" snippet="prose-only: needs flutter_riverpod 3, which the snippet package may not depend on"
final queryClientProvider = Provider<QueryClient>((ref) {
  final client = QueryClient();
  ref.onDispose(client.clear);
  return client;
});

void main() {
  runApp(
    ProviderScope(
      child: Consumer(
        builder: (context, ref, child) => QueryClientProvider(
          client: ref.watch(queryClientProvider),
          child: child!,
        ),
        child: const ProjectsApp(),
      ),
    ),
  );
}
```

A query becomes a `Notifier` whose state is the controller's result. The
family argument arrives through the constructor, which is how Riverpod 3
passes it.

```dart title="lib/features/projects/project_notifier.dart" snippet="prose-only: needs flutter_riverpod 3, which the snippet package may not depend on"
final projectProvider = NotifierProvider.autoDispose
    .family<ProjectNotifier, QueryResult<Project>, String>(ProjectNotifier.new);

class ProjectNotifier extends Notifier<QueryResult<Project>> {
  ProjectNotifier(this.id);

  final String id;

  @override
  QueryResult<Project> build() {
    final controller = QueryController.create(
      ref.watch(queryClientProvider),
      projectQuery(id),
    );
    void publish() => state = controller.value;
    controller.addListener(publish); // subscribes, and fetches if needed
    ref.onDispose(() {
      controller.removeListener(publish);
      controller.dispose();
    });
    return controller.value;
  }

  Future<void> refresh() => ref
      .read(queryClientProvider)
      .invalidateQueries(filters: QueryFilters(queryKey: ProjectKeys.detail(id)));
}
```

A widget watches it the usual way:
`final project = ref.watch(projectProvider(id));`, then switches on the
`QueryResult` as it would on anything else.

The Notifier is not the only option. `context.query(projectQuery(id))` works
inside a `ConsumerWidget` too, because the `QueryClientProvider` is above it.
Use a Notifier when other providers need the result. Read the query directly
when only the widget does.

## Bloc

This section targets **flutter_bloc 9** (bloc 9). Code written for version 8
is the same here. A `Cubit` wraps a controller and emits its results.

```dart title="lib/features/projects/project_cubit.dart" snippet="prose-only: needs flutter_bloc 9, which the snippet package may not depend on"
class ProjectCubit extends Cubit<QueryResult<Project>> {
  factory ProjectCubit(QueryClient client, String id) =>
      ProjectCubit._(QueryController.create(client, projectQuery(id)));

  ProjectCubit._(this._project) : super(_project.value) {
    _project.addListener(_publish);
  }

  final QueryController<Project, Project> _project;

  void _publish() => emit(_project.value);

  Future<void> refresh() => _project.refetch();

  @override
  Future<void> close() {
    _project
      ..removeListener(_publish)
      ..dispose();
    return super.close();
  }
}
```

```dart title="lib/features/projects/project_page.dart" snippet="prose-only: needs flutter_bloc 9, which the snippet package may not depend on"
BlocProvider(
  create: (context) =>
      ProjectCubit(QueryClientProvider.read(context), projectId),
  child: BlocBuilder<ProjectCubit, QueryResult<Project>>(
    builder: (context, project) => switch (project) {
      QueryPending() => const CircularProgressIndicator(),
      QueryError(:final error) => Text('$error'),
      QuerySuccess(:final data) => Text(data.name),
    },
  ),
)
```

`BlocProvider` calls `close()` when it unmounts, which disposes the
controller. A `QueryResult` has value equality, and a Cubit drops a state
equal to the current one, so an unchanged notification does not rebuild the
`BlocBuilder`.

## Provider

This section targets **provider 6**. `QueryController` is a `ChangeNotifier`,
so `ChangeNotifierProvider` provides it and disposes it without any adapter
code.

```dart title="lib/features/projects/project_page.dart" snippet="prose-only: needs provider 6, which the snippet package may not depend on"
ChangeNotifierProvider(
  create: (context) => QueryController.create(
    QueryClientProvider.read(context),
    projectQuery(projectId),
  ),
  child: const ProjectHeader(),
)

// Anywhere below:
final project = context.watch<QueryController<Project, Project>>().value;
```

## Steps

1. Write each query's options once, as a function of its inputs
   (`lib/data/…_queries.dart`).
2. Put one `QueryClientProvider` above the app, even when your package holds
   the client. The four built-in call styles need it.
3. For each query your store needs, create one `QueryController` in the
   store's unit (Notifier, Cubit, ChangeNotifierProvider). Dispose it
   together with that unit.
4. Keep only the inputs in the store. When an input changes, call
   `setOptions` with the new options. Do not copy the data into the store.

## Traps

- **Copying the result into the store.** A `state = controller.value` that
  also saves `data` in a second field creates two truths. The copy does not
  change when a background refetch does. Publish the `QueryResult` itself.
- **Forgetting `dispose`.** A controller that is still listened to keeps its
  query observed. The query then never goes stale in the "nobody is watching"
  sense, and it is never garbage collected. Every recipe above disposes the
  controller at the same point where its owner is disposed.
- **A second client.** A `QueryClient()` created inside a provider that
  rebuilds (a Riverpod provider that `watch`es something that changes, or a
  `create` that runs more than once) starts over with an empty cache. The
  client is created once, per app or [per signed-in
  user](sign-out-and-multi-account.md).
- **Mutations through the store.** A write can be a store method that calls
  `client.invalidateQueries(...)` afterwards, or a
  [mutation](../guides/mutations.md) read with `context.mutation`. Both are
  fine. Do not also apply the server's answer to the store yourself: the
  invalidation refetches it into the cache, and the controller publishes it.

## Variations

- **No store at all.** Many screens need none of this.
  [Reading queries in widgets](../guides/reading-queries-in-widgets.md) shows
  the four equal call styles, which read the cache directly.
- **A derived value only.** When the store needs one field of the result, pass
  `projectQuery(id).withSelect((p) => p.openTasks)` to
  `QueryController.create`. The controller then publishes the selected value,
  and [render optimisations](../guides/render-optimizations.md) explain when
  it notifies.

## See it run

The four call styles demo reads one cache entry through `context.query`,
`QueryBuilder`, `QueryMixin` and `QueryController`. The controller is the
adapter this whole page builds on. Press one style's *Increment* button and
watch the other readers update from the same entry.

<LiveDemo feature="four-call-styles" height={720} />

:::note[In React Query]
The same split applies there: server state in the cache, client state in
Redux, Zustand or context. `QueryController` corresponds to what
`useQuery` is built on (a `QueryObserver` that a framework subscribes to),
exposed as a Flutter `ValueListenable` so that any state package can listen
to it. See [differences from TanStack
Query](../reference/differences-from-tanstack.md).
:::
