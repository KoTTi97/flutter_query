---
title: Where the client lives
sidebar_label: Dependency injection
description: Create the QueryClient once, provide it with QueryClientProvider, reach it with of, maybeOf and read, and register it in get_it when code outside the tree needs it.
---

# Where the client lives

**The problem.** Every widget that reads a query needs *the* client: one
cache, created once. A repository, a push-notification handler or a
background sync may need it too, and those are not widgets. Tests need a
fresh client each time. Get this wrong and you have two caches that disagree,
or a cache that empties on every rebuild.

**The recipe.** The client belongs to a `QueryClientProvider` at the root of
the tree. Widgets reach it through the provider. Code outside the tree
receives the same instance through whatever you already use for injection,
and the tree is still wrapped in the provider.

## Let the provider own it

```dart title="lib/main.dart" snippet="cookbook/dependency-injection.md#create"
runApp(
  QueryClientProvider.create(
    create: () => QueryClient(defaultOptions: appDefaults),
    child: const ProjectsApp(),
  ),
);
```

`QueryClientProvider.create` calls `create` once and keeps the client for as
long as the provider is mounted. After the provider unmounts, it clears the
client. Rebuilding with a different `create` callback keeps the same client.
To replace the client, give the provider a new `key`.

The unnamed constructor, `QueryClientProvider(client: …)`, takes a client you
created yourself and **never** clears it. Use it when something else owns the
client: `main` itself, get_it, a Riverpod provider or a test.

Both constructors *mount* the client while they are in the tree. Mounting
makes app-lifecycle focus drive refetch-on-focus and defers notifications
that arrive during a build. Connectivity is added only if you pass
`onlineStatus` (see [Connectivity](../guides/connectivity.md)).

## Three ways to look it up

```dart title="lib/features/projects/project_card.dart" snippet="cookbook/dependency-injection.md#lookups"
class ProjectCard extends StatefulWidget {
  const ProjectCard({super.key, required this.id});

  final String id;

  @override
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard> {
  // `read`: no dependency, so it is allowed in initState and in callbacks.
  late final QueryController<Project, Project> project = QueryController.create(
    QueryClientProvider.read(context),
    projectQuery(widget.id),
  );

  @override
  void dispose() {
    project.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // `of`: in build, where depending on the provider is what you want.
    final client = QueryClientProvider.of(context);
    return ValueListenableBuilder(
      valueListenable: project,
      builder: (context, result, _) => ListTile(
        title: Text(result.dataOrNull?.name ?? '…'),
        onTap: () => client.invalidateQueries(
          filters: QueryFilters(queryKey: ProjectKeys.detail(widget.id)),
        ),
      ),
    );
  }
}
```

| Lookup | Subscribes? | Without a provider | Use in |
|---|---|---|---|
| `QueryClientProvider.of(context)` | yes | throws | `build` |
| `QueryClientProvider.maybeOf(context)` | yes | returns `null` | `build`, in widgets that can do without one |
| `QueryClientProvider.read(context)` | no | throws | `initState`, callbacks |

`maybeOf` is for code that has to work in an app without query_kit, such as a
design-system package:

```dart title="packages/design_system/lib/fetching_bar.dart" snippet="cookbook/dependency-injection.md#maybe-of"
/// From a shared design-system package: it shows a thin progress bar under a
/// QueryClientProvider, and nothing in an app that has none.
class FetchingBar extends StatelessWidget {
  const FetchingBar({super.key});

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.maybeOf(context);
    if (client == null) return const SizedBox.shrink();
    return _FetchingBar(client: client);
  }
}
```

## A client per signed-in user

A new key gives a new client. That is the whole implementation of "each user
starts with an empty cache":

```dart title="lib/app/signed_in_scope.dart" snippet="cookbook/dependency-injection.md#per-user"
class SignedInScope extends StatelessWidget {
  const SignedInScope({super.key, required this.userId, required this.child});

  final String userId;
  final Widget child;

  @override
  Widget build(BuildContext context) => QueryClientProvider.create(
        // Another user is another key: the old provider is disposed and its
        // client cleared, and the subtree starts over on an empty cache.
        key: ValueKey<String>(userId),
        create: () => QueryClient(defaultOptions: appDefaults),
        child: child,
      );
}
```

[Sign out and multiple accounts](sign-out-and-multi-account.md) builds the
rest of the flow around it.

## Code outside the tree: get_it

This section targets **get_it 8**. Register the instance, give it a
`dispose` that clears it, and hand the same instance to the provider:

```dart title="lib/main.dart" snippet="prose-only: needs get_it 8, which the snippet package may not depend on"
final getIt = GetIt.instance;

void main() {
  getIt.registerSingleton<QueryClient>(
    QueryClient(defaultOptions: appDefaults),
    dispose: (client) => client.clear(),
  );
  getIt.registerLazySingleton<ProjectRepository>(
    () => ProjectRepository(getIt<QueryClient>()),
  );

  runApp(
    QueryClientProvider(client: getIt<QueryClient>(), child: const ProjectsApp()),
  );
}
```

A repository can then call `client.query(...)`, `setQueryData` or
`invalidateQueries` on the cache that the screens read. For example, a push
handler that learns project `p1` changed calls
`getIt<QueryClient>().invalidateQueries(...)`, and every screen showing that
project refetches.

The same shape works with injectable, with a Riverpod `Provider<QueryClient>`
(see [Next to Riverpod, Bloc or Provider](riverpod-bloc-provider.md)) or with
a plain top-level `final`. The rule is one instance, handed to exactly one
`QueryClientProvider` at the root.

## Tests: a client per test

Nothing about a test client is special. Create it in the test, hand it to
the unnamed constructor, and end with the teardown from the [testing
guide](../guides/testing.md), because a client owns `gcTime` timers that
outlive the widget tree:

```dart title="test/project_screen_test.dart" snippet="cookbook/dependency-injection.md#test"
testWidgets('the project screen shows the project', (tester) async {
  // A client per test: nothing cached leaks from one test into the next.
  final client = QueryClient(
    defaultOptions: const DefaultOptions(
      queries: QueryDefaults(retry: RetryPolicy.never),
    ),
  );
  await tester.pumpWidget(QueryClientProvider(
    client: client,
    child: const MaterialApp(home: ProjectScreen(id: 'p1')),
  ));
  await tester.pumpAndSettle();
  expect(find.text('3 open tasks'), findsOneWidget);

  // The testing guide's teardown.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  client.clear();
  await tester.pump();
  client.clear();
});
```

Turning retries off in the test's defaults makes an error case fail at once
instead of after the retry backoff.

## Steps

1. Create the client in exactly one place: `QueryClientProvider.create`,
   `main`, or your injector's registration.
2. Wrap the app in one `QueryClientProvider`, even when an injector holds the
   client.
3. In widgets, use `of` in `build` and `read` everywhere else.
4. In tests, create a new client per test and tear it down.

## Traps

**A client in `build`.** This replaces the cache every time the root
rebuilds:

```dart title="lib/main.dart" snippet="cookbook/dependency-injection.md#never-in-build"
// Wrong: every rebuild makes a new client — a new, empty cache — and the
// screens below lose everything they had loaded.
@override
Widget build(BuildContext context) =>
    QueryClientProvider(client: QueryClient(), child: const ProjectsApp());
```

Use `QueryClientProvider.create`, or create the client once outside `build`.

- **`of` in `initState`.** It subscribes to the provider, and Flutter does
  not allow subscribing to an inherited widget from `initState`. `read` does
  not subscribe.
- **Two providers, two clients.** A nested `QueryClientProvider` with its own
  client hides the outer one from its subtree. That is right for a
  per-user scope and wrong by accident: a query invalidated through the outer
  client is not refetched below.
- **Expecting the unnamed constructor to clean up.** It does not clear a
  client it was given. Whoever created it clears it: get_it's `dispose`, the
  test's teardown, or your sign-out code.

:::note[In React Query]
This is `QueryClientProvider` and `useQueryClient()`. `of` corresponds to
`useQueryClient`, and `read` has no React counterpart because hooks cannot
run outside render. React's advice to create the client outside the
component, or once in state, is `QueryClientProvider.create` here. See
[differences from TanStack Query](../reference/differences-from-tanstack.md).
:::
