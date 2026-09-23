# Changelog

## 1.0.0

First release. `query_kit_flutter` is the Flutter binding for `query_kit`: a
`QueryClientProvider`, listenable controllers, builder widgets, a `State`
mixin and a `BuildContext` extension. It depends on Flutter, `meta` and
`query_kit` and on nothing else — `flutter pub deps` lists it as
`query_kit_flutter 1.0.0 [flutter meta query_kit]` — so a cache does not
bring a state-management package with it; hooks, signals and connectivity
stay yours to add.

**Four equal ways to read a query.** None is the default, and the
documentation names none:

- `context.query(options)` — flat, in a `StatelessWidget`, rebuilding only
  the widgets that read that key; `context.selectQuery` for a `select`.
- `QueryBuilder<TData>` and `QuerySelectBuilder<TQueryData, TData>` — the
  `StreamBuilder` shape, with `buildWhen`.
- `QueryMixin` on a `State` — `watchQuery`, `watchSelectQuery`,
  `watchInfiniteQuery`, `watchMutation`; entries are identified by key and
  types, not by call order.
- `QueryController` — a `ValueListenable<QueryResult<T>>`, the foundation
  the other three stand on, testable without widgets and usable with any
  package that reads a listenable.

The same four shapes exist for infinite queries (`context.infiniteQuery`,
`InfiniteQueryBuilder`, `watchInfiniteQuery`, `InfiniteQueryController`, with
paging on the controller) and for mutations (`context.mutation`,
`MutationBuilder`, `watchMutation`, `MutationController`). Beside them:
`QueryListener`, `InfiniteQueryListener` and `MutationListener` for side
effects delivered off the build phase; `QueriesBuilder` and
`QueriesController` for a list of queries; `MutationStateController` for
cache-wide mutation state; `IsFetchingController` for the number of queries
fetching, upstream's `useIsFetching`.

**Options and types** (ADR-0001)

- The plain entry points take `QueryObserverOptions<TData>`, the select entry
  points `QuerySelectOptions<TQueryData, TData>` with `select` required; the
  infinite entry points take either shape and infer every slot.
- A key-only literal with neither `queryFn` nor a type argument is refused by
  the controllers in debug builds with a message naming the cure;
  `strict-inference` in the app's `analysis_options.yaml` reports it at the
  literal.

**Lifecycle, focus and connectivity**

- The provider mounts the client it is given and unmounts it when it goes;
  `QueryClientProvider.create` builds, owns and `clear()`s one.
  `QueryClientProvider.maybeOf` for a widget that can do without.
- App lifecycle drives focus: `resumed` is focused, `hidden`, `paused` and
  `detached` are not, and `inactive` is read per platform — focused on iOS,
  Android and Fuchsia, unfocused on macOS, Windows and Linux. `isAppShown`
  overrides the mapping, and a changed one applies without a remount.
- Connectivity is opt-in: `onlineStatus` takes one `OnlineStatus` —
  `OnlineStatus.fixed(online)`, or `OnlineStatus.stream(changes, initial: …)`
  where `initial` says what a stream cannot before its first event.
  Nothing is installed by default. A broadcast stream always works; a
  single-subscription one only while exactly one provider listens once, and
  a second listen throws a `FlutterError` pointing to `asBroadcastStream()`.
  Taking `onlineStatus` away, or disposing the provider, puts its client back
  online; a failing `cancel()` of the subscription is reported through
  `FlutterError.reportError`.
- The first `resumed` after app start is not a focus change, so mounted
  queries do not refetch at startup.
- A result that arrives inside a build is delivered after the frame; outside
  one, at once.

**Rebuilds and results**

- A widget rebuilds when its result changes, compared whole — `fetchStatus`
  and `dataUpdatedAt` included — so a refetch returning equal data rebuilds
  with an unchanged `data`. `select` narrows the data; `buildWhen` on every
  read and every builder decides the rebuild, and its `previous` is the
  result last built.
- Every call style hands its options to the observer on every rebuild — the
  builders too, not only when the options object changes — so an
  `Enabled.when` over outside state pauses and resumes in all four (#84).
  Builders compare the *resolved* client: naming the provider's own client
  keeps a `MutationBuilder`'s state and a `QueriesBuilder`'s collection, and
  a client swap in the same frame as an options change fetches on the new
  client. `QueriesBuilder` builds once for one change of its list.
- A read inside a nested builder callback — a `ValueListenableBuilder`, a
  `LayoutBuilder`, a `ListView.builder` item — is additive to the enclosing
  reader: it does not release what the reader's own `build` read, and a key
  such a callback stops reading is released on the reader's next own build
  or disposal. Give a list item its own widget where release should follow
  the item.
- A listener delivers each notification whose value differs from the last
  one it saw; a batch of writes is one transition to the last value.
- A controller's `value` before its first listener is the optimistic result,
  what a first build sees.
- `mutate` and `mutateAsync` on a disposed `MutationController` still run the
  mutation through the cache: the options' callbacks run, nothing is
  attached, and the mutation is collected after its `gcTime`. On a live
  controller the per-call callbacks run whether or not anything listens.
- A `mutationKey` is a category, not a name: two mutation reads of one shape
  under one key in one build, without an `id`, are a debug assertion — give
  each an `id`.
- `QueryController.setOptions` and `InfiniteQueryController.setInfiniteOptions`
  keep nothing the observer refused.

**Asked for by the first real integration** (map #81)

- `MutationController.cancel()` fails the run being shown with a
  `CancelledError`; disposing a controller still does not cancel.
- `MutationStateController.typed` selects the mutations of one type, typed,
  for the controller's life — a later `setOptions` keeps the type.
- Results of different data types combine with the core's
  `(a, b).combine(…)` in every call style; an `Enabled.when` over outside
  state is re-evaluated by the rebuild that hands the options over again.
- A widget can say "gave up" from `result.consecutiveErrorCount`, which the
  core now carries on every `QueryResult`.

**Widget tests** (ADR-0002)

- Nothing is exported for tests; `flutter_test` is a dev dependency only. The
  teardown a `QueryClient` needs — tear the tree down, pump, `clear()`, pump
  once for a dropped mutation's callbacks, `clear()` again — is a documented
  snippet, the first section of the testing guide and of the README,
  compiled in the repository so it cannot rot. The binding's own suite and
  both example apps wrap that one shape.

Requires Flutter 3.27 or later; tested on 3.27.4 and 3.38.8.
