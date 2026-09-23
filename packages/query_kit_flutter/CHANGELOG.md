# Changelog

## 1.0.0

First release. `query_kit_flutter` is the Flutter binding for
[`query_kit`](https://pub.dev/packages/query_kit), a Dart port of TanStack
Query, and re-exports it. It depends on Flutter, `meta` and `query_kit` and
on nothing else. From here on, a breaking change is a major version.

query_kit is an entirely AI-coded project: all code, tests and documentation
were written by AI coding agents (Anthropic's Claude). A human maintainer set
the goals and reviews releases, but did not write the code. It is a community
port, not affiliated with or endorsed by TanStack.

**Setup**

- `QueryClientProvider` places a `QueryClient` above the tree and mounts it;
  `QueryClientProvider.create` builds and owns one. `of`, `read` and
  `maybeOf` find it.
- The app lifecycle drives the client's focus state, so queries refetch when
  the app returns to the foreground; `inactive` is read per platform and
  `isAppShown` overrides the mapping.
- Connectivity is opt-in through `OnlineStatus.fixed` or
  `OnlineStatus.stream`; nothing is installed by default.

**Four equal ways to read a query**

- `context.query(options)` and `context.selectQuery` in any widget.
- `QueryBuilder` and `QuerySelectBuilder`, the `StreamBuilder` shape.
- `QueryMixin` on a `State`: `watchQuery`, `watchSelectQuery`,
  `watchInfiniteQuery`, `watchMutation`.
- `QueryController`, a `ValueListenable<QueryResult<T>>` that works without
  widgets and with any package that reads a listenable.

**Infinite queries and mutations** in the same four shapes:
`context.infiniteQuery`, `InfiniteQueryBuilder`, `watchInfiniteQuery`,
`InfiniteQueryController` (with paging on the controller), and
`context.mutation`, `MutationBuilder`, `watchMutation`, `MutationController`
(with `mutate`, `mutateAsync`, `reset` and `cancel`).

**Rebuilds**

- A widget rebuilds when its result changes. `select` narrows the data it
  sees; `buildWhen`, on every builder and every keyless read, decides when it
  rebuilds.
- Results that arrive during a build are delivered after the frame.

**Beside the four styles**

- `QueryListener`, `InfiniteQueryListener` and `MutationListener` for side
  effects (snackbars, navigation), with `listenWhen`.
- `QueriesBuilder` and `QueriesController` for a dynamic list of queries;
  `combine` over results of different types in every call style.
- `MutationStateController` (and `.typed`) for cache-wide mutation state,
  `IsFetchingController` for a global loading indicator.

**Testing**

- Controllers are testable without widgets. A widget test ends with a short
  teardown — take the tree down, `clear()` the client — documented in the
  README and the testing guide; nothing test-only is exported.

Requires Flutter 3.27 or later.
