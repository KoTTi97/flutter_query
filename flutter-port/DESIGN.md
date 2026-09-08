# The Flutter Query Port — design doc

Porting TanStack Query's `query-core` to Dart, with a builder-first Flutter API
on top.

| | |
|---|---|
| **Status** | **Superseded as plan of record on 2026-09-08** by the wayfinder map ([GitHub issue #1](https://github.com/KoTTi97/flutter_query/issues/1)). Kept as prior art: D1–D13 and §14 are inputs the map's tickets re-decide, not decisions of the new plan. Implementation history in [PLAN.md](PLAN.md). |
| **Author** | Christian (with Claude) |
| **Date** | 2026-08-25 |
| **Upstream** | TanStack Query v5, `packages/query-core` |
| **MVP bar** | Flutter equivalent of the `react-demo` sensor app |

> This is the Markdown copy of the design doc that decisions **D1–D13** refer
> to. Those identifiers are cited throughout the source and the porting notes,
> so this file is the definition they point at. It was originally authored as a
> published artifact ([The Flutter Query
> Port](https://claude.ai/code/artifact/912c0a14-1562-472c-ba1e-4b8ebd182101));
> that artifact and this file should be kept in step, and **this file wins** if
> they disagree.
>
> §14 records where implementation has since amended the design. Read it
> alongside any decision you rely on.

## 1. Summary

We port the behavioral core of TanStack Query — cache, query state machine,
observer, retryer, mutations — from TypeScript to pure Dart, and ship a Flutter
binding with a builder-first, sealed-class API. The port is feasible and smaller
than the raw line count suggests: of ~7,300 lines in `query-core`, roughly 1,400
are TypeScript generics that get redesigned rather than translated, and another
~500 are JS-specific utilities that are replaced. The real core is about 4,000
lines of framework-free, well-factored OO code with clean layering.

The MVP has a concrete acceptance bar: **a Flutter equivalent of the internal
React sensor demo** (`react-demo/`) — the TanStack Query reference for the
sensor-domain rebuild — reproducing its behavior on the ported library (§3).

The differentiator over existing Dart packages in this space is **behavioral
fidelity, proven by porting the upstream test suite** (16,600 lines — larger
than the source itself). No existing port has done this.

## 2. Goals & non-goals

### Goals

- A pure-Dart `query_core` with upstream's semantics: request dedup, staleness,
  garbage collection, retries with offline pause, invalidation, optimistic
  mutations, stale-while-revalidate.
- A Flutter package with an idiomatic widget API (builders, sealed results,
  `InheritedWidget` provider) that maps observer lifetime onto widget lifetime
  exactly the way upstream maps it onto React mount/unmount.
- An MVP proven by a running Flutter port of the sensor demo, exercising every
  feature in the §3 checklist.
- Behavioral test coverage ported from upstream for every module we port.

### Non-goals

- 100% API parity. React-specific machinery (suspense, tracked props, SSR
  hydration, configurable render batching) is deliberately dropped or replaced.
- Infinite queries in the MVP. The demo doesn't use them; the behavior file is
  small and slots in post-MVP (§10).
- Persistence in v1. We keep the door open (see D12) but ship no serialization
  layer.
- A hooks-style API. Builders first; a `flutter_hooks` flavor can come later as
  a separate package.

## 3. MVP target: the sensor demo

The React demo (`react-demo/react/`) is a two-screen sensor manager against a
deliberately slow dummy gateway (~900 ms per list fetch, ~700 ms per write): an
**overview** with debounced search, room filter, refresh, create and delete; a
**detail screen** with an optimistic rename form and a Matter-forwarding switch
whose write is accepted immediately but confirmed by the device ~3 s later,
reconciled by a poll. A header badge derives "x of y connected" from the same
cache entry the list uses. The gateway has scripted failures — renaming to
`"fail"` rejects, every second delete fails — so both rollback paths are
demonstrable on demand.

Its cache design is the part worth reproducing faithfully: the list query owns
*which* sensors exist, a per-sensor query owns *what each one is*, the list's
`queryFn` seeds every per-sensor entry via `setQueryData`, and both the overview
rows and the detail screen observe the same per-sensor key — so one invalidation
updates both screens with a single refetch and zero cross-cache patching.

### Feature checklist

Every behavior in the demo, mapped to what the library must provide. This list
*is* the MVP feature scope:

| Demo behavior | Required library feature |
|---|---|
| Filter changes re-key the list | Observer swaps queries on key change (previous entry stays cached and GC-scheduled) |
| Debounced search, filters in the key | Keys containing maps/objects with deep equality and prefix matching (D3) |
| Header count derives from the list entry, no extra request | `select` with memoization; observer dedup on a shared key |
| List response seeds per-sensor entries, stamped fresh | `setQueryData` callable from inside a `queryFn` |
| Detail opened cold seeds from any cached list, inheriting its timestamp | `initialData` / `initialDataUpdatedAt` as functions; `getQueryState` exposing `dataUpdatedAt` |
| Confirmation poll while a write is pending, surviving loss of focus | `refetchInterval` as a function of the query; `refetchIntervalInBackground` |
| Optimistic rename with rollback; one invalidation updates row + detail | Mutation lifecycle (`onMutate`/`onError`/`onSettled`), `cancelQueries`, snapshot/rollback, `invalidateQueries`; per-call `mutate` callbacks; `mutation.reset()` |
| Matter switch: optimistic target field, accepted response written back, poll reconciles | `onSuccess` + `setQueryData`; no invalidation path |
| Optimistic delete across every filtered list, restored on failure | Filter-based bulk access: `getQueriesData` / `setQueriesData`; `removeQueries` |
| Skeleton only on first load; later refetches show a quiet spinner | `status` × `fetchStatus` orthogonality (`isPending` vs `isFetching`) |
| Manual refresh button; disabled while fetching | `refetch()` on the result; `isFetching` |
| Detail only fetches with a valid id; 45 s freshness window | `enabled`; `staleTime` |
| Error panels with retry; delete failure banner | Error surface on queries and mutations (`error`, `isError`) |

### Porting the demo app itself

- **Backend: the standalone dummy gateway, shared with the React demo.** The
  gateway lives at `react-demo/server/` as its own express process (port 5174,
  plain JSON, CORS open) — tRPC was removed precisely so both clients speak
  ordinary HTTP. Same latencies, same scripted failures (`"fail"` rename,
  every-second-delete, 3 s confirm delay), so React and Flutter behavior is
  comparable against identical backend behavior. The route table in `server.ts`
  is the contract.
- **Wire client:** six plain REST calls (GET `/api/sensors?search=&room=`,
  GET/POST/PUT/DELETE on `/api/sensors/:id…`) behind a typed repository
  interface — mirroring the React side's hand-typed `api.ts` + `sensorKeys` key
  factory, which is deliberately the same shape the Flutter client will use.
  dio's `CancelToken` plugs into the query `CancelToken` (D4), so
  `cancelQueries` genuinely aborts the HTTP request, as in the React demo.
  (Android emulators reach the host via `10.0.2.2`.)
- **Client state** (open screen, search text, room filter) stays in plain
  Flutter state (`ValueNotifier` / `StatefulWidget`) — the zustand of the demo,
  and the same lesson: client state does not live in the query cache.
- **tRPC's type inference** has no Dart equivalent; the demo port declares its
  keys and the repository interface by hand. Key-definition ergonomics beyond
  that are out of MVP scope.
- **One mobile nuance:** `refetchIntervalInBackground` means "keep polling while
  unfocused." On mobile the OS may suspend the process entirely; the guarantee
  is polling continues while the app is alive, and a refetch-on-resume covers
  the gap after suspension.

> **MVP acceptance:** the Flutter demo reproduces each row of this checklist
> observably — same optimistic flips, same rollbacks, same single-refetch
> reconciliation between row and detail — on the ported library, with the
> relevant upstream tests green.

## 4. Background

TanStack Query's own architecture makes this port tractable: the framework
adapters (React, Vue, Solid…) are thin layers over a framework-free core, and
the maintainer has said on GitHub that a Dart port should start by porting
`query-core`. That advice holds up against the source.

The space is crowded but unclaimed: `fquery`, `flutter_query` (pub.dev),
`cached_query`, and community "tanstack_query" packages all exist, yet none
became the ecosystem standard — Riverpod's `AsyncNotifier` absorbed much of the
demand. This tells us feasibility is not the hard part; fidelity and polish are.
Hence the test-suite strategy in §11.

## 5. Feasibility assessment

Verdict from a full read of the core modules: **doable, mostly mechanical**. The
layering translates directly:

| Module | What it is | Port difficulty |
|---|---|---|
| `QueryCache` (223 loc) | `Map<hash, Query>` plus an event stream | Trivial |
| `Query` (784 loc) | Reducer-driven state machine, GC, fetch orchestration, revert-on-cancel | Mechanical; futures piggyback like promises |
| `QueryObserver` (812 loc) | Stale timers, refetch intervals, fetch-on-mount decisions, `select` memoization, placeholder data | Mechanical; `Timer` replaces `setTimeout` |
| `Retryer` (237 loc) | Backoff loop, pause/continue on offline or unfocused | Direct; `Completer` replaces externally-resolved promise |
| `Mutation` (427 loc) | State machine plus the `onMutate`/`onError`/`onSettled` lifecycle | Direct |
| `infiniteQueryBehavior` (176 loc) | Pure logic over `{pages, pageParams}` | Direct (post-MVP) |
| `focusManager` / `onlineManager` | Pluggable event sources | Rewrite adapters: `AppLifecycleListener`, `connectivity_plus` |
| `notifyManager` (99 loc) | Notification batching/scheduling | Redesign for Flutter's build phase (D8) |

Two subtle behaviors that make TanStack Query *feel* right port cleanly and must
be preserved: fetch dedup via a shared retryer future (multiple observers
awaiting one in-flight fetch — the demo's rows, header and detail all rely on
it), and revert-on-cancel (state snapshot restored when a consumed cancellation
aborts a refetch, via `CancelledError.revert` — what makes the demo's
`cancelQueries`-before-patch idiom safe).

The work is not translation but a set of deliberate Dart redesigns where JS
semantics don't carry over. Those are the decisions in §6.

## 6. Design decisions

### D1 — No error type parameter; errors are `Object` + `StackTrace`

Upstream threads `TError` through five type parameters. We drop it:
`QueryState` stores `Object? error` and `StackTrace? stackTrace`.

**Why:** Dart's idiom is `catch (error, stackTrace)` — the trace is a separate
value that must be captured at the catch site or lost. Removing `TError`
collapses five type parameters to two with no loss Dart users would notice, and
preserving stack traces is table stakes for debuggability.

### D2 — "No data yet" is a `hasData` flag, not `undefined`

Upstream uses `undefined` = no data, `null` = valid data, and branches on
`data === undefined` throughout (staleness, mount decisions, placeholder logic).
Dart has one null. Internally, `QueryState` carries an explicit `hasData`
discriminator; the public result surface exposes plain `T? data`.

**Why:** The flag keeps the public API clean and matches the state the core
already tracks (`dataUpdateCount`). A bonus: where upstream needs a runtime
guard against `queryFn` returning `undefined`, Dart's `Future<T>` with
non-nullable `T` makes that a compile-time guarantee.

### D3 — `QueryKey` is a value type, not a raw list

A const-constructible class wrapping `List<Object?>`, with `==`/`hashCode` via
`DeepCollectionEquality` and a `partialMatch` method porting upstream's prefix
matching. Documented rule: primitives, lists, and maps only (or types with
stable value equality). The demo's filter objects in keys (`{search, room}`) are
the canonical use case.

**Why:** Dart list equality is identity — `['todos'] != ['todos']` — which makes
raw lists a footgun as cache keys. Upstream's `JSON.stringify`-with-sorted-keys
hash is replaced by a deep, map-order-insensitive hash.

### D4 — Cancellation via a consume-aware `CancelToken`

Dart futures can't be aborted, so `AbortSignal` becomes a `CancelToken` in the
query-function context (interoperable with dio's). Upstream marks the signal
"consumed" through a property getter and only reverts state on unmount-cancel if
the fetch actually observed the signal; we replicate this by materializing the
token lazily behind a getter method that sets the consumed flag.

**Why:** The consumed distinction is what lets non-cancellable fetches run to
completion and still populate the cache after the last observer unsubscribes —
behavior worth keeping exactly.

### D5 — Structural sharing off by default; change detection via `==`

`replaceEqualDeep` assumes plain JSON objects; Dart data is typed model classes,
so generic structural sharing is impossible. We rely on value equality
(freezed/Equatable) for "did the result change," and keep an optional
`structuralSharing: (prev, next) => next` hook.

**Why:** The observer's change check becomes field-wise `==` on a result class
(excluding function-valued fields like `refetch`) instead of
`shallowEqualObjects` — same effect, idiomatic mechanism.

### D6 — Drop tracked properties (`trackResult`)

Upstream uses a JS `Proxy` to record which result fields a component reads and
skip unneeded re-renders. No Proxy in Dart; we drop it.

**Why:** Flutter's rebuild economics differ — element rebuilds are cheap, and
`builder` scoping plus `select` give users equivalent explicit control.

### D7 — Sealed result classes — and `QueryError` keeps stale data

The result is a sealed hierarchy on `status` (`QueryPending` / `QuerySuccess` /
`QueryError`) with `fetchStatus` orthogonal (`isFetching`, `isRefetching`,
`isPaused` exposed on the variants). Critically, upstream's error reducer does
*not* clear `data`, so `QueryError` exposes `T? staleData`.

**Why:** Pattern matching gives compile-time exhaustiveness that upstream's
boolean flags can't. And a background-refetch failure while cached content is on
screen (`isRefetchError`) is the most common real-world error path — a sealed
design that drops data there would break stale-while-revalidate exactly where it
matters.

### D8 — Notification batching that respects Flutter's build phase

`notifyManager`'s configurable batching is replaced by microtask coalescing in
core. The widget layer additionally guards with
`SchedulerBinding.schedulerPhase`: a notification arriving mid-build defers to a
post-frame callback.

**Why:** A query update triggered synchronously during `build` (e.g. a rebuilt
widget's `setOptions` causing a fetch) must not produce "setState() called
during build." This is the classic bug in existing half-ports; it gets designed
out on day one.

### D9 — `Duration` everywhere; `staleTime` is a sealed type

All millisecond numbers become `Duration`. `staleTime: 'static'` becomes
`StaleDuration.static_` alongside `.zero`, `.infinity`, and `.duration(d)`.

**Why:** Magic strings and sentinel numbers are un-Dart-like; a sealed type is
exhaustive and self-documenting.

### D10 — Drop `timeoutManager` and `environmentManager`; use `clock`

Dart's `Timer` has none of the host-environment quirks the timer indirection
exists for, and `fake_async` intercepts timers at the zone level — so no
injectable timer layer is needed. No SSR means no `isServer`. Timestamps go
through the `clock` package for testability.

### D11 — Observer lifetime = widget `State` lifetime

Subscribe on first build, unsubscribe in `dispose`; unsubscribe starts the
`gcTime` clock.

**Why:** This is exactly upstream's React mount/unmount mapping, and it's what
makes `gcTime` and `refetchOnMount` behave identically to upstream without any
translation layer in users' mental model.

### D12 — No hydration in v1 — but the door stays open

`Query`'s constructor already accepts an initial `QueryState`; that is the
entire hook persistence needs. We keep `QueryState` publicly constructible and
ship nothing else. A later `query_persist` package with user-supplied
`toJson`/`fromJson` slots in without core changes.

**Why:** Offline-first persistence is *more* requested in Flutter than on the
web, but generic serialization needs per-type codecs — an opt-in layer, not
core.

### D13 — A systematic `.ignore()` policy for internal futures

Upstream sprinkles `promise.catch(noop)` because the retryer's promise
intentionally rejects even when nobody awaits it. In Dart, an unlistened failed
`Future` reports to the zone handler and fails tests. Every internally-held
future gets a deliberate `.ignore()`; the rule is enforced in review.

## 7. Package architecture

Two packages, mirroring upstream's own core/adapter split — the single most
important structural decision:

- **`query_core`** — pure Dart, zero Flutter imports. Cache, state machines,
  observers, retryer, managers. Testable with plain `dart test` + `fake_async`;
  usable from CLIs and servers.
- **Flutter binding package** (naming open, see §13) — `QueryClientProvider`,
  builders, the `AppLifecycleListener` focus adapter and `connectivity_plus`
  online adapter, build-phase-safe notification scheduling.
- **Demo app** — the Flutter sensor demo from §3, living in the repo as the
  reference example and dogfood.

Core keeps `focusManager`/`onlineManager` pluggable exactly as upstream does; the
binding installs the Flutter adapters at provider mount.

## 8. Core API

The imperative surface mirrors upstream so existing TanStack Query knowledge
transfers directly. The demo's cache choreography is the sizing exercise —
everything it calls is in the MVP surface:

```dart
final client = QueryClient(
  defaultOptions: DefaultOptions(
    queries: QueryOptions(
      staleTime: StaleDuration.duration(Duration(seconds: 45)),
    ),
  ),
);

// Imperative cache access — single entry
final sensor = client.getQueryData<Sensor>(QueryKey(['sensor', 'byId', id]));
client.setQueryData(QueryKey(['sensor', 'byId', id]), (old) => updated);
final state = client.getQueryState(QueryKey(['sensor', 'byId', id])); // dataUpdatedAt

// Filter-based bulk access — the demo's delete rollback needs these
final lists = client.getQueriesData<SensorListResponse>(
  QueryFilters(queryKey: QueryKey(['sensor', 'list'])),
);
client.setQueriesData<SensorListResponse>(
  QueryFilters(queryKey: QueryKey(['sensor', 'list'])),
  (old) => old?.copyWith(
    sensors: old.sensors.where((s) => s.id != removedId).toList(),
  ),
);

// Prefix-matched lifecycle operations
await client.cancelQueries(QueryFilters(queryKey: QueryKey(['sensor', 'byId', id])));
await client.invalidateQueries(QueryFilters(queryKey: QueryKey(['sensor', 'list'])));
client.removeQueries(QueryFilters(queryKey: QueryKey(['sensor', 'byId', id])));
```

Generics: two parameters at the observer layer — `TQueryData` (what `queryFn`
returns and the cache stores) and `TData` (post-`select`). The cache stores
`Query<dynamic>` and observers cast at the edge; using one key with two different
types is a runtime `TypeError` with a descriptive message naming the key.
Accepted and documented — Dart's sound runtime types make this strictly better
than upstream's silent `any` erasure.

Options objects use sentinel-aware `copyWith`/merge so "absent" and "explicitly
set" stay distinguishable through the three-level defaulting chain (client
defaults → key defaults → per-observer options), matching upstream's spread-merge
semantics. `initialData`/`initialDataUpdatedAt` accept functions (the demo's
cold-open seeding), and `refetchInterval` accepts a function of the query (the
demo's confirmation poll).

## 9. Widget API

Builder-first, because builders need no dependency and match Flutter's grain.
The canonical usage, shaped like the demo's list screen:

```dart
QueryBuilder<SensorListResponse>(
  queryKey: QueryKey(['sensors', 'list', {'search': search, 'room': room}]),
  queryFn: (ctx) => gateway.listSensors(filters, cancelToken: ctx.cancelToken),
  staleTime: StaleDuration.duration(Duration(seconds: 45)),
  builder: (context, result) => switch (result) {
    QueryPending() => const SensorListSkeleton(),
    QuerySuccess(:final data, :final isFetching) =>
      SensorList(data, refreshing: isFetching),
    QueryError(:final error, :final staleData) => staleData != null
      ? SensorList(staleData, banner: ErrorBanner(error))
      : ErrorView(error, onRetry: result.refetch),
  },
)
```

Mutations follow the standard lifecycle, exposed as a builder (or a controller
held in `State`) — this is the demo's rename, verbatim in shape, including
per-call callbacks and `reset()` for clearing a failed submit:

```dart
MutationBuilder<Sensor, RenameArgs>(
  mutationFn: (vars, ctx) => gateway.rename(vars.id, vars.name),
  onMutate: (vars) async {
    final key = QueryKey(['sensor', 'byId', vars.id]);
    await client.cancelQueries(QueryFilters(queryKey: key));
    final previous = client.getQueryData<Sensor>(key);
    client.setQueryData(key, (old) => old?.copyWith(name: vars.name));
    return previous; // rollback context
  },
  onError: (err, vars, previous) =>
    client.setQueryData(QueryKey(['sensor', 'byId', vars.id]), (_) => previous),
  onSettled: (d, e, vars, c) => client.invalidateQueries(
    QueryFilters(queryKey: QueryKey(['sensor', 'byId', vars.id]))),
  builder: (context, mutation) => RenameForm(
    busy: mutation.isPending,
    error: mutation.error,
    onEdit: mutation.reset,
    onSubmit: (name) => mutation.mutate(
      RenameArgs(id, name),
      onSuccess: (_) => formKey.currentState?.reset(),
    ),
  ),
)
```

Access to the client is `QueryClient.of(context)` via `QueryClientProvider` (an
`InheritedWidget`).

## 10. Scope

The MVP column is defined by the §3 checklist; nothing outside it ships in the
first cut.

| Feature | MVP | Notes |
|---|---|---|
| Cache, state machine, staleTime/gcTime | **Keep** | The core |
| Retries, backoff, offline pause (networkMode) | **Keep** | Retryer direct port; demo uses defaults, real app won't |
| Invalidation with prefix matching, filters | **Keep** | |
| Imperative cache access, incl. bulk: `get/setQueriesData`, `getQueryState`, `removeQueries`, `cancelQueries` | **Keep** | Demo delete-rollback and seeding depend on these |
| Refetch on resume / reconnect / interval; functional `refetchInterval`, `refetchIntervalInBackground`; `enabled` | **Keep** | Confirmation poll |
| Mutations with optimistic lifecycle, per-call callbacks, `reset()` | **Keep** | Three demo mutations exercise every path |
| `select`, functional `initialData(UpdatedAt)` | **Keep** | Header stats, cold-open seeding |
| Placeholder data / keepPreviousData | *Post-MVP* | Dropped from the demo along with tRPC; small observer-layer feature, easy fast-follow |
| Infinite queries | *Post-MVP* | 176 loc of pure logic; not used by the demo — first fast-follow |
| Persistence / hydration | *Post-MVP* | Door held open by D12 |
| Prefetching, mutation scopes, devtools overlay | *Post-MVP* | |
| Suspense flags, `trackResult`, SSR | ~~Drop~~ | React-specific |
| `queriesObserver` (useQueries), `streamedQuery`, experimental persister | ~~Drop~~ | Revisit on demand |
| Configurable notify batching | ~~Drop~~ | Replaced by D8 |

## 11. Testing strategy

This is the differentiator, so it is scoped as first-class work, not an add-on.
Upstream's `src/__tests__/` is 16,600 lines of behavioral tests — larger than the
source. We port the suites module-by-module, alongside each module:

- **Priority order:** `query.test`, `queryObserver.test`, `queryCache.test`,
  `mutation.test` — these pin the semantics that make TanStack Query feel right:
  fetch dedup, revert-on-cancel, stale timing, GC scheduling.
- **Tooling:** `fake_async` is a near-perfect analog of vitest's fake timers, so
  the timer-heavy tests port naturally; `clock` (D10) makes timestamp assertions
  deterministic.
- **Known deltas:** microtask-timing assertions need review where JS and Dart
  event-loop ordering differ; tests asserting on `undefined` data map to
  `hasData == false` (D2); dropped features' suites are skipped with a recorded
  rationale, not silently omitted.
- **Demo as integration suite:** integration tests run the demo's flows against
  the shared Node dummy gateway — optimistic flip, rollback on the scripted
  failures, poll-until-confirmed — end-to-end over the real library and the real
  wire. Fast widget tests stub the repository interface where a live server or
  real latencies would fight `fake_async`.

> **Acceptance bar for the MVP:** every §3 checklist row demonstrably working in
> the Flutter demo, the upstream test suites for kept features ported and green,
> and a written delta log for each intentionally changed behavior.

## 12. Build order

1. **`QueryKey` + hashing/matching + `Retryer`.** Small and self-contained;
   proves the `fake_async` test workflow before anything depends on it.
2. **`Query` + `QueryCache` + notification batching.** The state machine and
   revert-on-cancel semantics.
3. **`QueryObserver` + `QueryClient`.** Stale timers, refetch decisions (incl.
   functional intervals), `select`, placeholder/initialData, filters and bulk
   access, the facade.
4. **Mutations.** `Mutation`, `MutationCache`, observer, the optimistic
   lifecycle, per-call callbacks, `reset`.
5. **Flutter binding.** Provider, builders, lifecycle/connectivity adapters,
   build-phase safety.
6. **Demo app port.** The §3 sensor demo on the ported library, running against
   the shared Node dummy gateway, with integration tests over it. This milestone
   *is* the MVP release gate.

Each library step ships with its ported test suite. Rough effort: core + widget
layer is 2–4 focused weeks and on the order of 4–6k lines of Dart; the faithful
test port roughly doubles the calendar. Infinite queries follow as the first
post-MVP milestone.

## 13. Risks & open questions

| Risk | Mitigation |
|---|---|
| Crowded space; adoption is the hard part, not feasibility | Compete on fidelity (ported tests) and polish; compare fquery/cached_query APIs before finalizing names |
| Runtime type errors at the untyped cache boundary | Descriptive error naming the query key and both types; documented key-typing rule |
| Event-loop timing differences JS ↔ Dart breaking subtle dedup/cancel behavior | Port the timing-sensitive tests first (build order §12.1–.2); delta log for every adjusted assertion |
| Build-phase notification bugs in the widget layer | Designed out up front (D8) and covered by widget tests |
| Background polling suspended by mobile OS breaks the confirmation loop | Refetch-on-resume covers the gap; documented semantics (§3) |

### Open questions

- **Package naming.** `flutter_query` is already taken on pub.dev, as are
  several tanstack-adjacent names. Candidates need a check for availability and
  trademark courtesy (TanStack affiliation should not be implied without their
  blessing — or, better, ask about official affiliation via the GitHub
  discussion). **Still open.**
- **Upstream engagement.** Whether to build this as a community port or propose
  it under the TanStack umbrella (they list community adapters). Affects naming,
  repo location, and long-term maintenance. **Still open.**
- **Result equality mechanics.** Field-wise `==` excluding function members (D5)
  — settle whether results are freezed classes or hand-written with Equatable
  before step 3. **Settled:** hand-written `==`/`hashCode` on the sealed result
  classes, no code generation. See `query_result.dart`.
- **Typed key definitions.** tRPC gives the React demo inferred, compiler-checked
  keys. The MVP declares keys by hand; whether to offer a lightweight
  key-builder pattern (à la query-key-factory) is a post-MVP ergonomics
  question. **Still open.**

## 14. Amendments from implementation

Where building the thing changed the design. Each item supersedes the decision
it names; the code is the final word, and
[`packages/query_core/test/PORTING_NOTES.md`](packages/query_core/test/PORTING_NOTES.md)
records the test-level consequences.

**Found while planning (M0):**

1. **D4 refinement.** Upstream reverts unconditionally on an explicit
   `cancel(revert: true)` (e.g. from `cancelQueries`); the consumed-token flag
   only decides, on last-observer-removal, between a hard cancel and
   `cancelRetry()` (letting the fetch land in the cache). The port follows
   upstream, not the looser reading in D4's text.
2. **D3 refinement — no `queryHash` string.** Upstream keys its map by a hashed
   string and lets callers override `queryKeyHashFn`. The port drops both:
   `QueryKey` has deep value equality and *is* the map key. Two upstream
   `queryCache` tests about `queryHash` therefore have no counterpart.
3. **Observer-level `throwOnError` is dropped** (it feeds React error
   boundaries). It survives only as a *parameter* on `refetchQueries` /
   `invalidateQueries` / `resetQueries`, which is a different feature.
4. **`continue()` → `resume()`** on `Retryer` and `Mutation` — `continue` is a
   Dart keyword.
5. **The mutation context generic is `TOnMutateResult`**, and the state field is
   `onMutateResult`, not `context`. In Flutter, `context` means `BuildContext`
   to every reader.

**Found while implementing (M4–M6):**

6. **Neither observer extends `Subscribable`.** Dart forbids a class type
   parameter in a contravariant position of a superinterface, and `TData`
   appears in the listener's argument type. Both observers hand-roll the same
   subscribe/unsubscribe contract instead.
7. **`DefaultedQueryOptions` / `DefaultedMutationOptions` are distinct types,**
   replacing upstream's `_defaulted` boolean flag. Only the client can produce
   them, so nothing downstream can be handed half-resolved options. This also
   removes the need for upstream's short-circuit in `defaultQueryOptions`.
8. **Mutation scope is a plain `String?`,** not upstream's `{ id }` object.
9. **The function context carries no client.** Upstream's
   `QueryFunctionContext` / `MutationFunctionContext` include the `QueryClient`;
   the port omits it so `Query` and `Mutation` do not depend on the client. A
   function that needs the client closes over it.
10. **Mutation callbacks are `FutureOr<void>`,** where upstream types them as
    "returns anything, ignored". Dart cannot express that without warning on
    every non-returning `async` body, so a callback that needs to wait says so
    with `await` inside its body. The mutation still awaits the callback before
    settling — the behavior upstream's "callback return types" tests pin.
11. **A pending mutation's gc clock restarts on settle, rather than polling.**
    Upstream re-arms the gc timer each time it fires while a mutation is still
    pending. That is safe in a browser, which clamps `setTimeout(0)`; Dart does
    not clamp `Timer(Duration.zero)`, so with `gcTime: 0` the same code spins the
    event loop. The port restarts the clock in `Mutation.execute`'s `finally` —
    where `Query.fetch` already did it. Same outcome, no busy loop.

**Still true and worth re-reading before M7:** D8 (build-phase batching) and D11
(observer lifetime = `State` lifetime) are the two decisions the Flutter binding
is built on, and neither has been exercised yet — `query_core` installs the
default microtask flush and has no widget layer.
