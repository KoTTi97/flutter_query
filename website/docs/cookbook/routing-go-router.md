---
title: Routing with go_router
sidebar_label: Routing (go_router)
description: Derive query keys from path parameters, prefetch before a route opens, refetch when the user comes back, and read queries in dialogs.
sidebar_position: 14
---

# Routing with go_router

**The problem.** `/projects/p1` must open on a cold start from a deep link,
on a tap from the project list and on the back button. Each time it should
show project `p1` with no extra request when the data is fresh and no
spinner when it could have been avoided. When the user comes back to the
list after editing, the list should be current.

**The recipe.** The URL carries the *id* and the cache carries the *data*.
A screen takes its id from the route and reads its query from the id, so a
deep link and a tap produce the same screen. The navigation code can warm the
cache early and ask for a refresh on return. It never passes the data to the
screen as an argument.

## The screen reads by id

```dart title="lib/features/projects/project_screen.dart" snippet="cookbook/routing-go-router.md#screen"
class ProjectScreen extends StatelessWidget {
  const ProjectScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final project = context.query(projectQuery(id));
    return Scaffold(
      appBar: AppBar(title: Text(project.dataOrNull?.name ?? '')),
      body: switch (project) {
        QueryPending() => const Center(child: CircularProgressIndicator()),
        QueryError(:final error) => Center(child: Text('$error')),
        QuerySuccess(:final data) =>
          Center(child: Text('${data.openTasks} open tasks')),
      },
    );
  }
}
```

## The routes

This section targets **go_router 14 or later**. The route passes the path
parameter to the screen, and nothing else:

```dart title="lib/app/router.dart" snippet="prose-only: needs go_router 14+, which the snippet package may not depend on"
final router = GoRouter(
  observers: <NavigatorObserver>[routeObserver],
  routes: <RouteBase>[
    GoRoute(
      path: '/projects',
      builder: (context, state) => RefetchOnReturn(
        queryKey: ProjectKeys.all,
        child: ProjectListScreen(),
      ),
      routes: <RouteBase>[
        GoRoute(
          path: ':id',
          builder: (context, state) =>
              ProjectScreen(id: state.pathParameters['id']!),
        ),
      ],
    ),
  ],
);
```

Query parameters work the same way. A filter in the URL
(`state.uri.queryParameters['filter']`) is an input to the query's key, just
like a path parameter.

## Warm the cache before the route opens

A tap already knows which project comes next. Start the fetch before the
push. The screen's read then joins that fetch, or finds it finished:

```dart title="lib/features/projects/project_tile.dart" snippet="cookbook/routing-go-router.md#prefetch-on-tap"
class ProjectTile extends StatelessWidget {
  const ProjectTile(this.project, {super.key});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    return ListTile(
      title: Text(project.name),
      onTap: () {
        // Start the fetch before the route animates in; the screen's read
        // joins it, or finds it done.
        client.query(projectQuery(project.id)).ignore();
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ProjectScreen(id: project.id),
        ));
      },
    );
  }
}
```

With go_router, replace the `Navigator.push` with
`context.push('/projects/${project.id}')`. `client.query` returns the data,
and `.ignore()` is what makes the call a prefetch: a failure is dropped here
and the screen reports it when it reads. A second tap within the query's
`staleTime` fetches nothing. [Prefetching](../guides/prefetching.md) covers
the other places to start one.

## Refresh when the user comes back

A pushed route does not unmount the one below it. The list keeps its
observers, and nothing refetches it when the detail pops, because popping is
neither a focus change nor a remount. A `RouteAware` widget turns "the route
above me was popped" into a refetch of stale entries:

```dart title="lib/app/refetch_on_return.dart" snippet="cookbook/routing-go-router.md#refetch-on-return"
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

/// Refetches [queryKey]'s stale entries when the route it sits in becomes
/// visible again — when the route pushed over it is popped.
class RefetchOnReturn extends StatefulWidget {
  const RefetchOnReturn(
      {super.key, required this.queryKey, required this.child});

  final QueryKey queryKey;
  final Widget child;

  @override
  State<RefetchOnReturn> createState() => _RefetchOnReturnState();
}

class _RefetchOnReturnState extends State<RefetchOnReturn> with RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    QueryClientProvider.read(context)
        .refetchQueries(
          filters: QueryFilters(
            queryKey: widget.queryKey,
            type: QueryTypeFilter.active,
            stale: true,
          ),
        )
        .ignore();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

Register `routeObserver` on the navigator: `GoRouter(observers: [...])` as
above, `MaterialApp(navigatorObservers: [...])` without go_router. Each
`ShellRoute` has its own navigator and takes its own `observers:`.

The filter is `stale: true` and `type: active`. A list that is still fresh
is left alone, and entries no screen shows are not fetched.

## Dialogs and bottom sheets

A dialog is a route of its own. Give it a widget whose `build` reads the
query, so that the read belongs to the dialog's context:

```dart title="lib/features/projects/project_dialog.dart" snippet="cookbook/routing-go-router.md#dialog"
Future<void> showProjectDialog(BuildContext context, String id) =>
    showDialog<void>(
      context: context,
      // A widget of its own, reading through its own context: subscribed for
      // as long as the dialog is open, and rebuilt when the project changes.
      builder: (_) => ProjectDialog(id: id),
    );

class ProjectDialog extends StatelessWidget {
  const ProjectDialog({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final project = context.query(projectQuery(id));
    return AlertDialog(
      title: Text(project.dataOrNull?.name ?? '…'),
      content: Text('${project.dataOrNull?.openTasks ?? '–'} open tasks'),
    );
  }
}
```

Reading through the *caller's* `context` inside `builder: (_) => …` would
attach the read to the screen behind the dialog, and the dialog would not
rebuild when the data changes. The rule is that a read belongs to the element
whose `context` it goes through.

## Steps

1. Give every screen an id-shaped constructor (`ProjectScreen(id:)`) and let
   it read its own query.
2. In routes, pass only path and query parameters.
3. Prefetch in tap handlers, with `.ignore()`.
4. Wrap list screens in `RefetchOnReturn`, and register the observer on every
   navigator that shows one.

## Traps

- **Passing the object through `extra`.** `context.push(…, extra: project)`
  shows the copy made at tap time, even after an edit. It is also missing on a
  deep link and after a browser refresh, because `extra` is not part of the
  URL. Pass the id. To show the list's copy while the detail loads, seed the detail entry from the list
  (see [Initial query data](../guides/initial-query-data.md)).
- **Awaiting the prefetch.** `await client.query(…)` before navigating blocks
  the tap for the length of the request, and throws if the request fails. The
  point is to start early, not to wait.
- **Invalidating on every pop.** `invalidateQueries` in `didPopNext` refetches
  even fresh data, on every back gesture. Refetch what is stale.
- **A `redirect` that fetches.** A top-level `redirect` runs on every
  navigation. `client.getQueryData(...)` is cheap and synchronous there.
  `await client.query(...)` in a `redirect` holds up every route change until
  the request returns.

## Variations

- **Tabs with `StatefulShellRoute`.** Every branch keeps its screens mounted,
  so their queries stay observed. Refetch-on-focus and refetch-on-reconnect
  apply to all of them, shown or not. Give a heavy tab's query
  `refetchOnWindowFocus: RefetchOn.never` when that request is not worth
  making for a tab nobody is looking at, and pair it with `RefetchOnReturn`
  or a refetch when the tab is selected.
- **Scroll position on return.** A pushed route keeps the list below it
  alive, so popping needs nothing. For tabs, see
  [Scroll restoration](../guides/scroll-restoration.md).

## See it run

In the prefetching demo, press a row's prefetch button and then open that
post. It shows at once and costs no request. A post you open without
prefetching costs one.

<LiveDemo feature="prefetching" height={720} />

:::note[In React Query]
Router integrations there call `ensureQueryData` or `prefetchQuery` in a
route loader. go_router has no loaders, so the prefetch goes in the tap
handler, and `client.query(options)` covers `fetchQuery`, `prefetchQuery`
and `ensureQueryData` in one method. See [differences from TanStack
Query](../reference/differences-from-tanstack.md).
:::
