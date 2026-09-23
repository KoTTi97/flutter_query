# API documentation audit — query_kit 1.0.0 / query_kit_flutter 1.0.0

Audited on 2026-09-23, branch `release/1.0-docs` @ `491ed27`. No repository file was edited.
Scratch artefacts: `dartdoc-query_kit/`, `dartdoc-query_kit_flutter/` (generated docs), `rows.json` (every public symbol with its rendered doc and flags), `jargon_all.txt` (every `///` block in `lib/` with internal-history tokens, private ones included), `pana-core.log`, `pana-flutter.log`.

## 1. Numbers

| | query_kit | query_kit_flutter (own, excl. re-export) |
|---|---|---|
| Public symbols in dartdoc index | 1004 | 193 (1196 incl. re-exported core) |
| — classes / mixins / extensions / enums / typedefs / functions | 133 / 0 / 7 / 7 / 21 / 2 | 18 / 1 / 1 / 0 / 2 / 0 |
| — constructors / methods / properties / constants | 120 / 273 / 419 / 21 | 20 / 70 / 80 / 0 |
| Symbols graded (own docs, overrides excluded) | 893 | 161 |
| Undocumented | 1 (`QueryCancelToken()` implicit constructor) | 0 |
| Auto-flagged short (≤ 8 words) or name-restating | 213 | 41 |
| Curated "genuinely weak" (section 3) | 54 | 22 |
| Rendered docs with internal history (review IDs, ticket links, dates, ADRs, pin) | **92 symbols / 275 tokens** | **22 symbols / 49 tokens** |
| Rendered docs leaning on "upstream"/TanStack/`.ts` names | 145 symbols | 12 symbols |
| All `///` blocks in `lib/` with internal history (incl. private + src library docs) | 215 blocks / 576 tokens, both packages |
| Symbols with a code example in their own doc | 16 | 10 |
| `dart doc --validate-links` | 0 warnings, 0 errors | 0 warnings, 0 errors |
| pana | 160/160 (docs 910/911 = 99.9 %) | 50/160 — **not meaningful**: resolution fails because `query_kit` is not yet on pub.dev; re-run after the core is published |
| `pub publish --dry-run` | 0 warnings, 454 KB | 0 warnings, 106 KB |

Most frequent internal tokens in rendered docs: `review` (90), dates `2026-09-10` (34) / `2026-09-12` (28) / `2026-09-23` (17) / `2026-09-09` (16), `ADR-0001` (9), `issues/17` (7), `C23` (6), `issues/16`, `issues/7` (5 each), then a long tail of `C8…C59`, `LIB-1..5`, `MU-01..03`, `AR-01..12`, `QE-02/03`, `API-02`, `DC-02..05`, `IN-01/02`, `L4-*`, `L5-*`, `R2-*`, `V-B-*`, `B2-*`, `second pass`, `first integration`, `#9743`, `50680b98c`.

## 2. Cross-cutting findings (priority order)

**P1-1 — Essential user-facing rules live in `src/` library docs, which pub.dev never renders.** Each package documents exactly one library (`query_kit.dart` / `query_kit_flutter.dart`); the `library;` doc comments at the top of the `src/*.dart` files are invisible on pub.dev (verified: the phrase "Not through a list's item-builder context" occurs nowhere in the generated output). Lost that way:
- `query_kit_flutter/lib/src/query_context.dart:1-92` — the whole contract of `context.query`: identity and `id`, **release** rules, "whose build", LayoutBuilder rules, dialogs/sheets, **the debug `FlutterError` for a `ListView.builder` item context**, "only in build", why there is no `client:`. `QueryContext.query` (l.137) and `QueryContext.mutation` (l.229) say "see the library doc" — a dead reference on pub.dev.
- `query_kit_flutter/lib/src/query_mixin.dart:1-41` — release rules and nested-builder/dialog caveats for `watchQuery`.
- `query_kit_flutter/lib/src/query_builder.dart:1-13`, `query_controller.dart:1-13`, `query_client_provider.dart:1-2`, `online_status.dart:1-2`.
- core: `option_values.dart:1-8` (why sealed option values, what "null means unset" is), `query_result.dart:1-4`, `combined_result.dart:1-7`, `query_key.dart:1-7`, `query_options.dart:1-8`, `infinite_query.dart:1-9`, `timers.dart:1-9`.
Fix: move this prose onto the class/extension/mixin docs (`QueryContext`, `QueryMixin`, `QueryBuilder`, `QueryController`, `StaleTime`/option family, `QueryResult`), or into dartdoc topics (`dartdoc_options.yaml` + `doc/*.md` categories) and link them; then strip the src library docs to one-line maintainer notes.

**P1-2 — Internal history in 114 rendered docs.** Review IDs, ticket URLs, dates, ADR numbers and "passes" are meaningless on pub.dev and date the API text. Worst offenders by symbol: the two library docs, `QueryClient.setQueryData`, `QueryClient.query`, `QueryObserver`, `Query`, `InfiniteQueryObserver`, `QueryKey`, `StructurallyShareable`, `replaceEqualDeep`, `noStructuralSharing`, `StructuralSharing`, `StaleTimeStatic`, `MutationScope`, `QueryDataTypeError`, `NotifyManager`, `OnlineManager`, `AppFocusManager`, `QueryCache.QueryCache.new` (C59 + issues/66), `MutationController.mutateAsync` (C18), `QueryContext.query` / `QueryMixin.watchQuery` (C49 + issues/55), `QueriesBuilder`, `OnlineStatus`, `IsFetchingController`, `QueryClientProvider.onlineStatus`. Rule for the rewrite: keep the *reason* in user terms, drop the provenance (`(ninth review, 2026-09-10, C23; final review, 2026-09-18, SURF-1)` → delete; `(https://github.com/.../issues/16)` → delete or replace by a sentence of rationale; `ADR-0001` → "because Dart cannot infer a type slot from `select`…"). Full list per file in section 5, every `///` hit (incl. non-rendered) in `jargon_all.txt`.

**P1-3 — The main entry points have the thinnest class docs and no examples.**
| symbol | where | doc today | missing |
|---|---|---|---|
| `QueryClient` | `query_kit/lib/src/query_client.dart:293` | "The cache's front door: everything imperative happens here." (8 words) | overview of what it owns (two caches, defaults, managers), lifecycle (`mount`/`unmount`/`clear`), the 5–6 methods users call most, a code example (create, `query`, `setQueryData`, `invalidateQueries`, `clear`) |
| `QueryObserver` | `query_observer.dart:32` | type-param rationale + issue link + ADR | what it is for, subscribe/`currentResult`/`setOptions`/`destroy` lifecycle, example |
| `QueryCache` / `MutationCache` | `query_cache.dart:149`, `mutation_cache.dart:87` | "Every query, keyed by [QueryKey]." / "Every mutation, in submission order." | when a user touches it (hooks `onError`… , `subscribe` for events, `find`/`findAll`), example of a global error hook |
| `MutationController` | `query_kit_flutter/lib/src/query_controller.dart:345` | "One mutation, as a [ValueListenable]." | sibling `QueryController`/`InfiniteQueryController` have examples; this one has none: create/mutate/dispose, per-call callbacks, `cancel`, what `dispose` does to a running mutation |
| `QueryContext` (extension) | `query_context.dart:103` | "Reading queries and mutations from a [BuildContext]." | the contract from P1-1; list of the four members; example |
| `QueryClientProvider` | `query_client_provider.dart:44` | long and good prose | no code example (`QueryClientProvider(client: …, child: MaterialApp(…))`, `.create`, `onlineStatus` with connectivity_plus) |
| `MutationObserver`, `InfiniteQueryObserver`, `QueriesObserver`, `MutationStateObserver`, `QueriesBuilder`, `QueriesController`, `QueryListener`, `IsFetchingController`, `MutationStateController`, `OnlineStatus` | various | prose only | one short example each |
| `query_kit` library doc | `query_kit/lib/query_kit.dart:1-16` | provenance + export policy + review IDs | what the package does, a 10-line quick start, pointers to `QueryClient`, `QueryOptions`, `QueryObserver`, `QueryResult`, `MutationOptions`; move the export policy to CONTRIBUTING/PORTING_NOTES |

**P2-1 — No dartdoc categories.** 151 top-level types land in one alphabetical list. The plumbing a user rarely needs — 13 `Query*Action` / `Mutation*Action` classes, 11 cache events, `QueryObserverRef`, `MutationObserverRef`, `FetchBehavior`, `FetchContext`, `FetchMore`, the `Defaulted*Options` — sits beside `QueryClient`. Add `{@category ...}` (e.g. Client, Queries, Mutations, Infinite queries, Options, Results, Cache events, Advanced/plumbing, Flutter) and a `dartdoc_options.yaml`.

**P2-2 — Sealed option-value families: base-class docs are one-liners.** `RefetchInterval` ("Polling." — 1 word, `option_values.dart:592`), `RetryPolicy` (`:296`, 6 words), `RetryDelay` (`:394`), `StaleTime` (`:17`), `GcTime` (`:153`), `Enabled` (`:212`), and their variant classes (`EnabledNo/Yes/When`, `RetryNever/Always/Times/When`, `RetryDelayFixed/Dynamic`, `RefetchOnNever/IfStale/Always/When`, `RefetchIntervalOff/Every/Dynamic`: "The X.y variant." 3–4 words). The constants/factories are documented well; the base class should name all spellings, the default, and show `staleTime: StaleTime.duration(Duration(minutes: 5))`. The src library doc of `option_values.dart` already explains the design — see P1-1.

**P2-3 — Cross-reference-only docs on infinite options.** `InfiniteQueryObserverOptionsBase.refetchOnWindowFocus/refetchOnReconnect/refetchInterval/refetchIntervalInBackground/retryOnMount/placeholderData` (`infinite_query.dart:420-439`) are just "[QueryObserverOptionsBase.x]." Acceptable as a link, but add the default and "every held page is refetched" (only `refetchOnMount` says so). Same for `InfiniteQueryBuilder/MutationBuilder/QuerySelectBuilder.options/client/buildWhen` ("See QueryBuilder.x.").

**P2-4 — "Upstream" as the sole explanation.** The mapping to TanStack names is a useful secondary note, but where it is the whole doc it fails a Dart user who never used TanStack: `QueryCache.onSuccess` ("Cache-wide hooks, upstream's `QueryCacheConfig`." — says nothing about what `onSuccess` does; `query_cache.dart:176`), `FetchOptions` (explains `initialPromise`/`experimental_prefetchInRender` that users never see; `query.dart:173`), `GcTime.defaultValue` / `RetryDelay.defaultValue` ("Upstream's default: …" — state the value as ours), `QueryClient.query` says upstream's `fetchQuery`… "are deprecated in favour of this one method" (`query_client.dart:822`) — in this package they never existed; reword as "replaces". Also "the port" in user docs (9 occurrences, e.g. `QueryOptions.structuralSharing`: "Unset, the port applies replaceEqualDeep").

**P3-1 — German strings in public examples.** `MutationBuilder` doc (`query_builder.dart:298-301`: `'Küche'`, `'Umbenennen'`) and `example/lib/main.dart:10` (`'Küche', 'Flur'`). pub.dev renders both; use English.

**P3-2 — Implicit constructor undocumented.** `QueryCancelToken()` (`cancel_token.dart:45`) — the only pana-reported gap; add an explicit documented constructor.

## 3. Curated weak docs (beyond the jargon)

query_kit (54): `QueryClient` (class), `QueryObserver` (class — rationale, no purpose), `QueryCache`, `MutationCache`, `QueryCache.onSuccess`, `MutationFilters` (5 words), `QueryCacheEvent`, `DefaultOptions` (3 words), `MutationDefaults` (4 words, restates), `DefaultedQueryObserverOptions` (6 words), `RefetchInterval`, `RetryPolicy`, `RetryDelay`, `StaleTime`, `GcTime`, `Enabled`, the 16 one-line sealed variants, `InfinitePageFn` ("restates"), `MutationFn` (4 words), `BatchNotifyFunction`/`NotifyFunction`/`ScheduleFunction` (7 words each, no hint of when a user sets them), `CombineQueryResults2..5` (4 words each; `CombineQueryResults6` has the real text — move it to the first or into `CombinedResult`), `OptionalQueryResult` (7 words), `QueryClient.refetchQueries` (no filters/`cancelRefetch`/what "can actually fetch" means), `QueryClient.unmount`, `QueryObserver.refetch`, `QueryObserver.currentResult`, `InfiniteQueryObserver.fetchNextPage`/`fetchPreviousPage` (no `cancelRefetch`, no-next-page behaviour, return value), `AppFocusManager.setEventListener` / `OnlineManager.setEventListener` (no contract: setup receives a callback, returns a cleanup, previous cleanup is called), `Query.resetState`, `QueryDefaults.structuralSharing` (starts with "Erased for the same reason as queryFn" — no description of the option), `QueryCancelToken()` (empty).

query_kit_flutter (22): `MutationController` (class), `QueryContext` (extension), `MutationStateController` (8 words), `OnlineStatusFixed` (8 words), `QueriesController` (class: no example, no dispose rule), `QueryListener`/`InfiniteQueryListener`/`MutationListener` (9–10 words; no example, no "when is the callback called" — after frame? on first value?), `ListenWhen` typedef, `MutationBuilder.options`/`InfiniteQueryBuilder.options`/`QuerySelectBuilder.options` and the `client`/`buildWhen` "See QueryBuilder.x" set, `InfiniteQueryController.infiniteObserver` ("The observer underneath, typed."), `QueryMixin` (good example, but the release contract is in the invisible src library doc), `QueryContext.query`/`.mutation` (dead "see the library doc").

The remaining auto-flagged short docs are mostly fine: action/event field docs ("What the attempt threw.", "Creates the action."), `isPending`/`isError` getters, `Defaulted*Options.x` ("…, with the default applied."). They are listed per file in section 5 for completeness.

## 4. pub.dev landing

| | query_kit | query_kit_flutter |
|---|---|---|
| pubspec `description` | 171 chars (OK, 60–180), but ~70 chars spent on the affiliation disclaimer; the search snippet shows little of what the package does | 169 chars (OK); same trade-off |
| `topics` | `cache, state-management, query, tanstack-query, async` (5 = max). `query` is very generic; consider `data-fetching` or `networking` | same five; consider `flutter`-specific `widget`/`data-fetching` |
| `README.md` (242 / 509 lines) | Install is at line 61 and "A first query" at 70, after a 30-line disclaimer box and a porting-coverage table. Contains `PORTING_NOTES`, `ADR-0001`, `50680b98c`, `2026-09-12`, "FI / …" notes and a "Running the suite" section — maintainer material. Suggest: one-paragraph intro → install → first query → features → "Relationship to TanStack" (disclaimer + fidelity table) at the end | Good task-oriented structure, but **"Setting up" (the `QueryClientProvider`) is at line 349, after the four call styles** — move it right after Install. One `ADR-0001` reference (l.172). Relative links are absolute GitHub links (good) |
| `CHANGELOG.md` | 291 lines for a first release, written as a pre-release fix log: "Pre-release correctness fixes" and "Release review (2026-09-23)" describe bugs in code that was never published, with IDs `MU-01, QE-01, OB-01, AR-01/02/05/12, R2-1..4, R3-1, F1..F6, FI-05, ADR-0001/0003`, `50680b98c`, `2026-09-19/23`. A 1.0.0 entry should list what the package *offers* (the "Types and options"/"Client and cache"/"Mutations"/"Infinite queries"/"Beyond query-core" sections are good material) in ~40 lines; the fix history belongs in the repo | 173 lines; mostly feature-oriented and useful, but contains `(#84)`, `map #81` ("Asked for by the first real integration"), `ADR-0001`, `ADR-0002` |
| `example/` | `example/example.dart` — pure-Dart tour, fine (pub.dev shows it) | `example/lib/main.dart` (122 lines), runnable; German task names (`'Küche', 'Flur'`). `pubspec_overrides.yaml` correctly excluded by `.pubignore` |
| Archive | includes the whole `test/` (454 KB, e.g. `port_specifics_test.dart` 169 KB) — allowed, but consider `.pubignore` for `test/` to shrink it | includes `test/` (`review_regressions_test.dart` 157 KB) |

## 5. Per-file detail

Line numbers are the declaration line (or the doc-comment start for library docs). "Jargon" = review/ticket/date/ADR/pin tokens in the **rendered** doc; rows marked short/restating are heuristic (≤ 8 words, or ≤ 2 words beyond the symbol's own name) and include acceptable cases.

### `query_kit/lib/query_kit.dart` — library doc (l.1-16)
Provenance ("Ported against upstream 50680b98c"), export policy ("close to upstream's index.ts", `*CacheRef`, `@internal`) and review IDs ("ninth review, 2026-09-10, C23", "fourth review, 2026-09-09"). This is the package landing page of the API docs. Rewrite as a user intro + quick start (P1-3).

### `query_kit_flutter/lib/query_kit_flutter.dart` — library doc (l.1-18)
Good shape (four call styles listed). Drop `https://github.com/KoTTi97/flutter_query/issues/21`; add a 10-line example (provider + one `context.query` + one `MutationController`), and link the per-style class docs that should absorb P1-1's content.

### `query_kit/lib/query_kit.dart` (auto-flagged: 1 jargon, 0 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 16 | `query_kit` | 50680b98c, review, 2026-09-10, C23, 2026-09-09 | Ported against upstream 50680b98c. |


### `query_kit/lib/src/cancel_token.dart` (auto-flagged: 1 jargon, 1 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 65 | `QueryCancelToken.onCancel` | review, 2026-09-10, C16 | …reported to the zone, never thrown into cancel's caller or into the query function registering it late (ninth review, 2026-09-10, C16).… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 45 | `QueryCancelToken.QueryCancelToken.new` | *(none)* |


### `query_kit/lib/src/combined_result.dart` (auto-flagged: 2 jargon, 17 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 73 | `CombinedResult.refetch` | review, 2026-09-23, LIB-5 | …efetch it once each, so a pull-to-refresh over both fetches it twice unless one of them passes false (release review, 2026-09-23, LIB-5).… |
| 188 | `CombineMemo` | 2026-09-20 | …ys: [search] — which is compared with == and re-runs the combiner when it differs (second integration report, 2026-09-20).… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 52 | `CombinedResult.isPending` | Whether this is a CombinedPending. |
| 55 | `CombinedResult.isError` | Whether this is a CombinedError. |
| 58 | `CombinedResult.hasData` | Whether this is a CombinedData. |
| 61 | `CombinedResult.dataOrNull` | The combined value, if there is one. |
| 121 | `CombinedError.error` | What the first failed source threw. |
| 124 | `CombinedError.stackTrace` | Where error was thrown. |
| 124 | `MutationError.stackTrace` | Where error was thrown. |
| 124 | `QueryError.stackTrace` | Where error was thrown. |
| 143 | `CombinedData.data` | The combiner's result. |
| 150 | `CombinedData.refetchErrorStackTrace` | The stack trace that came with refetchError. |
| 153 | `CombinedData.isPlaceholderData` | Whether any source is showing placeholderData. |
| 157 | `CombinedData.isStale` | Whether any source is stale. |
| 273 | `OptionalQueryResult` | A source a combination can do without. |
| 365 | `CombineQueryResults2` | combine over two results. |
| 377 | `CombineQueryResults3` | combine over three results. |
| 394 | `CombineQueryResults4` | combine over four results. |
| 412 | `CombineQueryResults5` | combine over five results. |


### `query_kit/lib/src/filters.dart` (auto-flagged: 1 jargon, 3 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 50 | `QueryFilters` | issues/17 | …ers matches everything — the same convention the options model uses (https://github.com/KoTTi97/flutter_query/issues/17).… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 63 | `QueryFilters.queryKey` | Matched as a prefix unless exact is set. |
| 145 | `MutationFilters` | Selects a set of mutations. |
| 159 | `MutationFilters.exact` | See QueryFilters.exact. |


### `query_kit/lib/src/focus_manager.dart` (auto-flagged: 1 jargon, 1 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 33 | `AppFocusManager` | issues/19, issues/60 | …s QueryClientProvider maps every AppLifecycleState onto it directly (https://github.com/KoTTi97/flutter_query/issues/19) — or through a setEventListener adapter of your o… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 94 | `AppFocusManager.setEventListener` | Replaces the source of focus events. |


### `query_kit/lib/src/infinite_query.dart` (auto-flagged: 8 jargon, 11 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 37 | `InfiniteData` | review, 2026-09-10, C20 | … be grown behind the observers' backs: getInfiniteQueryData(key)!.pages.add(…) throws UnsupportedError (ninth review, 2026-09-10, C20). The constructor wraps nothing: a c… |
| 51 | `InfiniteData.InfiniteData.new` | review, 2026-09-12, IN-01 | …'s observer loop and reported to the zone, naming nothing that could be traced back to the write (pre-release review, 2026-09-12, IN-01). The check costs the constructor … |
| 80 | `InfiniteData.flatten` | review, 2026-09-10, C20 | …entError naming its runtime type, checked up front rather than in the middle of a loop over the result (ninth review, 2026-09-10, C20). flatten() with no type argument fl… |
| 153 | `InfinitePageContext.InfinitePageContext.new` | API-02, 2026-09-12 | … a pageFn in a test, with a signalProvider that returns a token of the test's own — () => QueryCancelToken() (API-02, 2026-09-12).… |
| 194 | `PageParamFn` | issues/16 | …t — the reason a nullable TPageParam is a poor choice of param type (https://github.com/KoTTi97/flutter_query/issues/16).… |
| 274 | `InfiniteQueryOptions.pages` | IN-02, 2026-09-12 | …ries — until an observer's fetch reinstalls its own options with no count; upstream persists it the same way (IN-02, 2026-09-12).… |
| 380 | `InfiniteQueryObserverOptionsBase` | ADR-0001 | …se data is the InfiniteData the query holds, and InfiniteQuerySelectOptions, which requires a select over it (ADR-0001). InfiniteQueryObserver and the binding's infinite … |
| 630 | `InfiniteQueryObserverOptions.withSelect` | review, 2026-09-23, LIB-3 | …withSelect for the paged shape: these options with a select added and every other field carried over (release review, 2026-09-23, LIB-3).… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 71 | `InfiniteData.isEmpty` | Whether no page is held. |
| 169 | `InfinitePageContext.pageParam` | The param this page is being fetched with. |
| 187 | `InfinitePageFn` | Fetches one page. |
| 420 | `InfiniteQueryObserverOptionsBase.placeholderData` | QueryObserverOptionsBase.placeholderData, as an InfiniteData. |
| 427 | `InfiniteQueryObserverOptionsBase.refetchOnWindowFocus` | QueryObserverOptionsBase.refetchOnWindowFocus. |
| 430 | `InfiniteQueryObserverOptionsBase.refetchOnReconnect` | QueryObserverOptionsBase.refetchOnReconnect. |
| 433 | `InfiniteQueryObserverOptionsBase.refetchInterval` | QueryObserverOptionsBase.refetchInterval. |
| 436 | `InfiniteQueryObserverOptionsBase.refetchIntervalInBackground` | QueryObserverOptionsBase.refetchIntervalInBackground. |
| 439 | `InfiniteQueryObserverOptionsBase.retryOnMount` | QueryObserverOptionsBase.retryOnMount. |
| 844 | `FetchMore.FetchMore.new` | A fetch extending the pages in direction. |
| 847 | `FetchMore.direction` | Which end is being extended. |


### `query_kit/lib/src/infinite_query_observer.dart` (auto-flagged: 2 jargon, 7 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 31 | `InfiniteQueryObserver` | issues/16 | …t grow fields per query kind without every consumer paying for them (https://github.com/KoTTi97/flutter_query/issues/16). What the shape costs is paid in shouldNotify: a … |
| 46 | `InfiniteQueryObserver.infiniteOptions` | review, 2026-09-09 | …rect setOptions, and hasNextPage then asked the old getNextPageParam while the fetch used the new one (fourth review, 2026-09-09).… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 50 | `InfiniteQueryObserver.setInfiniteOptions` | Replaces the options — the typed convenience over setOptions. |
| 100 | `InfiniteQueryObserver.hasNextPage` | Whether fetchNextPage would fetch anything. |
| 104 | `InfiniteQueryObserver.hasPreviousPage` | Whether fetchPreviousPage would fetch anything. |
| 233 | `InfiniteQueryObserver.fetchNextPage` | Fetches the page after the ones already held. |
| 233 | `InfiniteQueryController.fetchNextPage` | Fetches the page after the ones already held. |
| 243 | `InfiniteQueryObserver.fetchPreviousPage` | Fetches the page before the ones already held. |
| 243 | `InfiniteQueryController.fetchPreviousPage` | Fetches the page before the ones already held. |


### `query_kit/lib/src/mutation.dart` (auto-flagged: 3 jargon, 20 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 48 | `MutationObserverRef` | review, 2026-09-10, C21 | …supported — MutationObserver is the one implementation, and the one member is @internal there and here (ninth review, 2026-09-10, C21).… |
| 565 | `Mutation.continueMutation` | review, 2026-09-10, C10, C12 | …ite. It used to be the retryer's transport future, which completes before the first callback is called (ninth review, 2026-09-10, C10). A mutation restored from persisten… |
| 665 | `Mutation.cancel` | review, 2026-09-23, L4-3, issues/83 | …s no run yet: it fails on the spot rather than waiting for the next resumePausedMutations to send it (release review, 2026-09-23, L4-3). With no run in flight this does n… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 153 | `MutationPendingAction.MutationPendingAction.new` | Creates the action for a run of variables. |
| 160 | `MutationPendingAction.variables` | What the mutation function is being called with. |
| 175 | `MutationSuccessAction.MutationSuccessAction.new` | Creates the action carrying data. |
| 178 | `MutationSuccess.data` | What the mutation function returned. |
| 178 | `MutationSuccessAction.data` | What the mutation function returned. |
| 186 | `MutationErrorAction.MutationErrorAction.new` | Creates the action for the error that settled the run. |
| 189 | `MutationErrorAction.error` | What the run finally failed with. |
| 192 | `MutationErrorAction.stackTrace` | Where it was thrown from. |
| 192 | `MutationFailedAction.stackTrace` | Where it was thrown from. |
| 192 | `QueryErrorAction.stackTrace` | Where it was thrown from. |
| 192 | `QueryFailedAction.stackTrace` | Where it was thrown from. |
| 199 | `MutationFailedAction.MutationFailedAction.new` | Creates the action for the attempt that just failed. |
| 205 | `MutationFailedAction.error` | What the attempt threw. |
| 205 | `QueryFailedAction.error` | What the attempt threw. |
| 215 | `MutationPauseAction.MutationPauseAction.new` | Creates the action. |
| 222 | `MutationContinueAction.MutationContinueAction.new` | Creates the action. |
| 293 | `MutationState.status` | Where the mutation is in its life. |
| 306 | `MutationState.errorStackTrace` | Where error was thrown from. |
| 332 | `MutationState.submittedAt` | When the current (or last) run was started. |
| 1022 | `MissingMutationFunctionError` | Thrown when a mutation runs without a mutationFn. |


### `query_kit/lib/src/mutation_cache.dart` (auto-flagged: 6 jargon, 7 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 100 | `MutationCache.MutationCache.new` | C59, issues/66 | …se when none is passed to it. Final, with no setter, for the reason QueryCache's constructor gives at length (C59, https://github.com/KoTTi97/flutter_query/issues/66): up… |
| 192 | `MutationCache.build` | review, 2026-09-10, C8, C12, 2026-09-12, MU-03, MU-02 | …fused with an ArgumentError in every build mode, as QueryCache.build refuses a data-less success state (ninth review, 2026-09-10, C8 and C12; the twin closed with the sam… |
| 256 | `MutationCache.remove` | review, DC-02, 2026-09-12, ADR-0003, MU-01 | …error callbacks run a few microtasks after the removal. Upstream lets the retryer run on, as before the third review this did too (DC-02, 2026-09-12). Removing a restored… |
| 319 | `MutationCache.clear` | ADR-0003, MU-01, 2026-09-12 | …ar() empties its set in one go. Destroying a restored scope head that never ran releases the scope's waiters (ADR-0003), and removing entries one at a time from a live li… |
| 356 | `QueryCache.notify` | review, 2026-09-09 | …ubscriber that threw on a failed action blew up the retryer's loop and left the fetch pending forever (fourth review, 2026-09-09).… |
| 389 | `MutationCache.resumePaused` | review, 2026-09-09, 2026-09-10, C4, C10, 2026-09-23, L4-4 | …Upstream gates the whole call on onlineManager.isOnline() in QueryClient.resumePausedMutations instead (fifth review, 2026-09-09; the gate was the start rule until the ni… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 31 | `MutationAdded.MutationAdded.new` | Creates the event for mutation. |
| 39 | `MutationRemoved.MutationRemoved.new` | Creates the event for mutation. |
| 58 | `MutationObserverAdded.MutationObserverAdded.new` | Creates the event for mutation and the observer that attached. |
| 70 | `MutationObserverRemoved.MutationObserverRemoved.new` | Creates the event for mutation and the observer that detached. |
| 73 | `MutationObserverRemoved.observer` | The observer that detached. Read-only from outside. |
| 73 | `QueryObserverRemoved.observer` | The observer that detached. Read-only from outside. |
| 88 | `MutationCache` | Every mutation, in submission order. |


### `query_kit/lib/src/mutation_options.dart` (auto-flagged: 6 jargon, 11 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 44 | `MutationScope` | review, 2026-09-23, LIB-1 | …nd the one case that asks for it — a snapshot taken at the turn — is served by rolling back per item (release review, 2026-09-23, LIB-1).… |
| 78 | `MutationFunctionContext` | issues/83 | … other two are this port's, asked for by its first real integration (https://github.com/KoTTi97/flutter_query/issues/83): onMutateResult — after an optimistic patch the c… |
| 365 | `DefaultedMutationOptions.onMutate` | review, 2026-09-10 | …rge in — unlike mutationFn, retry, retryDelay, networkMode, gcTime, scope and meta, which do have one (eighth review, 2026-09-10).… |
| 373 | `DefaultedMutationOptions.onSuccess` | review, 2026-09-10 | …rge in — unlike mutationFn, retry, retryDelay, networkMode, gcTime, scope and meta, which do have one (eighth review, 2026-09-10).… |
| 381 | `DefaultedMutationOptions.onError` | review, 2026-09-10 | …rge in — unlike mutationFn, retry, retryDelay, networkMode, gcTime, scope and meta, which do have one (eighth review, 2026-09-10).… |
| 389 | `DefaultedMutationOptions.onSettled` | review, 2026-09-10 | …rge in — unlike mutationFn, retry, retryDelay, networkMode, gcTime, scope and meta, which do have one (eighth review, 2026-09-10).… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 46 | `MutationScope.MutationScope.new` | Scopes with equal ids are the same scope. |
| 63 | `MutationFn` | What a mutation runs. |
| 90 | `MutationFunctionContext.client` | The client the mutation belongs to. |
| 93 | `MutationFunctionContext.meta` | MutationOptions.meta, with the default applied. |
| 96 | `MutationFunctionContext.mutationKey` | MutationOptions.mutationKey. |
| 156 | `MutateCallbacks.MutateCallbacks.new` | Any of the three may be left unset. |
| 348 | `DefaultedMutationOptions.mutationKey` | MutationOptions.mutationKey; there is no default. |
| 392 | `DefaultedMutationOptions.retry` | MutationOptions.retry, with the default applied. |
| 395 | `DefaultedMutationOptions.retryDelay` | MutationOptions.retryDelay, with the default applied. |
| 398 | `DefaultedMutationOptions.networkMode` | MutationOptions.networkMode, with the default applied. |
| 401 | `DefaultedMutationOptions.gcTime` | MutationOptions.gcTime, with the default applied. |


### `query_kit/lib/src/mutation_result.dart` (auto-flagged: 2 jargon, 9 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 67 | `MutationResult.isPaused` | review, 2026-09-23, L4-6 | …utationScope — a mutation queued behind another in its scope is pending with isPaused until its turn (release review, 2026-09-23, L4-6).… |
| 79 | `MutationResult.mutate` | review, 2026-09-10, C23 | …, callbacks) — MutationController.mutate(variables, callbacks) in the binding — with a MutateCallbacks (ninth review, 2026-09-10, C23).… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 82 | `MutationResult.mutateAsync` | Completes with the data, or throws. |
| 99 | `MutationResult.isIdle` | Whether this is a MutationIdle — upstream's isIdle. |
| 102 | `MutationResult.isPending` | Whether this is a MutationPending — upstream's isPending. |
| 105 | `MutationResult.isSuccess` | Whether this is a MutationSuccess — upstream's isSuccess. |
| 108 | `MutationResult.isError` | Whether this is a MutationError — upstream's isError. |
| 118 | `MutationResult.errorOrNull` | The error this result carries, if any. |
| 118 | `QueryResult.errorOrNull` | The error this result carries, if any. |
| 171 | `MutationIdle` | Nothing has been submitted yet. |
| 188 | `MutationPending` | In flight, or waiting for connectivity. |


### `query_kit/lib/src/mutation_state_observer.dart` (auto-flagged: 1 jargon, 4 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 73 | `MutationStateObserver.typed` | issues/85, review, 2026-09-23, L4-1 | …receiving them typed — no cast to get at state.variables. Port-only (https://github.com/KoTTi97/flutter_query/issues/85); upstream's useMutationState select is untyped to… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 26 | `MutationStateObserver.MutationStateObserver.new` | Creates a selection, readable immediately through currentResult. |
| 102 | `MutationStateObserver.hasListeners` | Whether the observer currently follows cache events. |
| 122 | `MutationStateObserver.subscribe` | Registers a listener without delivering an initial snapshot. |
| 169 | `MutationStateObserver.destroy` | Removes all listeners and releases the cache subscription. |


### `query_kit/lib/src/notify_manager.dart` (auto-flagged: 2 jargon, 6 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 34 | `NotifyManager` | issues/19 | …nd of listener calls. Two divergences from upstream, both decided on https://github.com/KoTTi97/flutter_query/issues/19: The default scheduler is scheduleMicrotask, not a… |
| 41 | `NotifyManager.shared` | review, 2026-09-09 | …stance, for batching across clients. Not the default: a client constructed without one creates its own (third review, 2026-09-09).… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 7 | `ScheduleFunction` | Schedules when a batch of notifications runs. |
| 10 | `NotifyFunction` | Wraps the delivery of a single notification. |
| 13 | `BatchNotifyFunction` | Wraps the delivery of a whole batch. |
| 82 | `NotifyManager.flush` | Delivers everything queued so far. |
| 102 | `NotifyManager.setNotifyFunction` | Replaces how a single notification is delivered. |
| 105 | `NotifyManager.setBatchNotifyFunction` | Replaces how a whole batch is delivered. |


### `query_kit/lib/src/online_manager.dart` (auto-flagged: 1 jargon, 2 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 22 | `OnlineManager` | issues/21, issues/5 | …kes an optional Stream<bool> and depends on no connectivity package (https://github.com/KoTTi97/flutter_query/issues/21); a connectivity_plus stream, which reports a link… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 68 | `OnlineManager.setEventListener` | Replaces the source of connectivity events. |
| 79 | `OnlineManager.setOnline` | Sets the online state by hand. |


### `query_kit/lib/src/option_values.dart` (auto-flagged: 5 jargon, 41 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 33 | `StaleTime.static` | DC-05, 2026-09-12 | …is an ordinary entry to refetchQueries and invalidateQueries, as upstream's isStatic reads the observers too (DC-05, 2026-09-12).… |
| 46 | `StaleTime.StaleTime.dynamic` | review, 2026-09-10 | …Keep compute cheap and free of side effects; it is a question about the query, not a place to do work (eighth review, 2026-09-10).… |
| 104 | `StaleTimeStatic` | 50680b98c, review, 2026-09-09 | …h polls a static query exactly as it polls any other — an interval is a request, not a trigger, and upstream (50680b98c) polls too; only refetchQueries filters static out… |
| 230 | `Enabled.no` | issues/17, review, 2026-09-12 | …works. It is also this port's only spelling of upstream's skipToken (https://github.com/KoTTi97/flutter_query/issues/17), and enabled: false is the meaning that wins wher… |
| 241 | `Enabled.Enabled.when` | review, 2026-09-10 | …nswers a question about the query, and anything else it does happens an unpredictable number of times (eighth review, 2026-09-10).… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 17 | `StaleTime` | How long fetched data stays fresh. |
| 21 | `StaleTime.StaleTime.duration` | Fresh for duration after it was fetched. |
| 80 | `StaleTimeDuration.StaleTimeDuration.new` | Fresh for duration. |
| 135 | `StaleTimeDynamic.StaleTimeDynamic.new` | Computes the stale time with compute. |
| 153 | `GcTime` | How long unused data stays in the cache. |
| 161 | `GcTime.never` | Never collected. |
| 164 | `GcTime.defaultValue` | Upstream's default: five minutes. |
| 182 | `GcTimeDuration.GcTimeDuration.new` | Collected after duration unobserved. |
| 185 | `GcTimeDuration.duration` | How long an unobserved query stays cached. |
| 212 | `Enabled` | Whether a query may run at all. |
| 253 | `EnabledYes` | The Enabled.yes variant. |
| 266 | `EnabledNo` | The Enabled.no variant. |
| 279 | `EnabledWhen` | The Enabled.when variant. |
| 281 | `EnabledWhen.EnabledWhen.new` | Enabled while predicate says so. |
| 296 | `RetryPolicy` | Whether a failed attempt is retried. |
| 304 | `RetryPolicy.always` | Retry forever — upstream's retry: true. |
| 332 | `RetryNever` | The RetryPolicy.never variant. |
| 345 | `RetryAlways` | The RetryPolicy.always variant. |
| 358 | `RetryTimes` | The RetryPolicy.times variant. |
| 360 | `RetryTimes.RetryTimes.new` | Retries until count attempts have failed. |
| 375 | `RetryWhen` | The RetryPolicy.when variant. |
| 377 | `RetryWhen.RetryWhen.new` | Retries while predicate says so. |
| 394 | `RetryDelay` | How long to wait before the next attempt. |
| 401 | `RetryDelay.defaultValue` | Upstream's default: min(1000 * 2^attempt, 30s). |
| 444 | `RetryDelayFixed` | The RetryDelay.fixed variant. |
| 446 | `RetryDelayFixed.RetryDelayFixed.new` | Waits delay before every retry. |
| 449 | `RetryDelayFixed.delay` | The wait between attempts. |
| 460 | `RetryDelayExponential` | The RetryDelay.exponential variant: min(base * 2^failureCount, maximum). |
| 485 | `RetryDelayDynamic` | The RetryDelay.dynamic variant. |
| 487 | `RetryDelayDynamic.RetryDelayDynamic.new` | Computes every wait with compute. |
| 535 | `RefetchOnNever` | The RefetchOn.never variant. |
| 548 | `RefetchOnIfStale` | The RefetchOn.ifStale variant. |
| 561 | `RefetchOnAlways` | The RefetchOn.always variant. |
| 574 | `RefetchOnWhen` | The RefetchOn.when variant. |
| 576 | `RefetchOnWhen.RefetchOnWhen.new` | Decides with compute each time the event fires. |
| 593 | `RefetchInterval` | Polling. |
| 620 | `RefetchIntervalOff` | The RefetchInterval.off variant. |
| 633 | `RefetchIntervalEvery` | The RefetchInterval.every variant. |
| 635 | `RefetchIntervalEvery.RefetchIntervalEvery.new` | Polls every interval. |
| 649 | `RefetchIntervalDynamic` | The RefetchInterval.dynamic variant. |
| 651 | `RefetchIntervalDynamic.RefetchIntervalDynamic.new` | Computes the interval with compute. |


### `query_kit/lib/src/queries_observer.dart` (auto-flagged: 1 jargon, 2 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 60 | `QueriesObserver.subscribe` | 2026-09-12, AR-02 | …he members subscribed before it are unsubscribed again and the listener is removed (pre-release verification, 2026-09-12, AR-02).… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 37 | `QueriesObserver.hasListeners` | Whether this collection has active subscribers. |
| 196 | `QueriesObserver.destroy` | Releases listeners and every underlying observer. |


### `query_kit/lib/src/query.dart` (auto-flagged: 10 jargon, 16 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 29 | `QueryObserverRef` | review, 2026-09-10, C21 | …e and on QueryObserver's overrides alike — calling one from outside the package is an analyzer warning (ninth review, 2026-09-10, C21).… |
| 103 | `FetchBehavior` | issues/16 | … into a loop over pages; nothing else does, and users never set one (https://github.com/KoTTi97/flutter_query/issues/16).… |
| 193 | `FetchOptions.retry` | review, 2026-09-09 | …so that the next invalidateQueries refetched an observer's retry: times(3) query with a single attempt (fifth review, 2026-09-09).… |
| 308 | `Query` | issues/7 | …key is a value type, and the select transform lives in the observer (https://github.com/KoTTi97/flutter_query/issues/7).… |
| 343 | `Query.dataType` | review, 2026-09-09 | …faultedQueryOptions<int?>, which its setOptions refused with a raw TypeError. One key, one exact type (fourth review, 2026-09-09).… |
| 516 | `Query.setState` | issues/17, review, 2026-09-10, 2026-09-12, QE-02 | … — the merge half of the door persistence and devtools come through (https://github.com/KoTTi97/flutter_query/issues/17). Restoring an entry that does not exist yet goes … |
| 542 | `Query.cancel` | review, 2026-09-10, 2026-09-12, C9 | …es its way out. Until then every read reports a fetch that is not happening, which is what idle fixes (eighth review, 2026-09-10; the "never loads again" it was written w… |
| 633 | `Query.isActive` | review, 2026-09-12, AR-04 | …ficationError out of isFetching, refetchQueries, invalidateQueries and every QueryFilters(type:) (pre-release review, 2026-09-12, AR-04).… |
| 672 | `Query.isStatic` | AR-04 | …ly fresh. Over a copy, for the reason isActive gives: isStaticForQuery resolves a StaleTime.dynamic callback (AR-04).… |
| 829 | `Query.fetch` | review, 2026-09-09 | …ounces first and installs after, and both of those ran the query function twice or not at all as asked (fifth review, 2026-09-09).… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 132 | `FetchContext.queryKey` | The key of the query being fetched. |
| 135 | `FetchContext.options` | The fully resolved options this fetch runs with. |
| 175 | `FetchOptions.FetchOptions.new` | Creates the overrides; all are unset by default. |
| 214 | `QueryFetchAction.meta` | What FetchOptions.meta carried in; becomes QueryState.fetchMeta. |
| 221 | `QueryFailedAction.QueryFailedAction.new` | Creates the action for the attempt that just failed. |
| 239 | `QuerySuccessAction.QuerySuccessAction.new` | Creates the action carrying data. |
| 243 | `QuerySuccessAction.data` | The new data, already passed through structural sharing. |
| 260 | `QueryErrorAction.QueryErrorAction.new` | Creates the action for the error that settled the fetch. |
| 263 | `QueryErrorAction.error` | What the fetch finally failed with. |
| 273 | `QueryPauseAction.QueryPauseAction.new` | Creates the action. |
| 280 | `QueryContinueAction.QueryContinueAction.new` | Creates the action. |
| 288 | `QueryInvalidateAction.QueryInvalidateAction.new` | Creates the action. |
| 296 | `QuerySetStateAction.QuerySetStateAction.new` | Creates the action carrying the replacement state. |
| 299 | `QuerySetStateAction.state` | The state the query now holds, verbatim. |
| 363 | `Query.resetState` | The state this query returns to on reset. |
| 1239 | `MissingQueryFunctionError.MissingQueryFunctionError.new` | Creates the error for queryKey. |


### `query_kit/lib/src/query_cache.dart` (auto-flagged: 5 jargon, 8 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 83 | `QueryObserverOptionsUpdated` | DC-04, 2026-09-12 | …dded on the new one, and then this event on the new query, exactly as upstream's observerOptionsUpdated does (DC-04, 2026-09-12).… |
| 113 | `QueryDataTypeError` | issues/7 | …e mismatch is always a bug, so it is loud rather than a silent null (https://github.com/KoTTi97/flutter_query/issues/7). It is thrown synchronously, from the call that re… |
| 173 | `QueryCache.QueryCache.new` | C59, issues/66 | …QueryClient constructs one of these when none is passed to it. The hooks are final, and that is the decision (C59, https://github.com/KoTTi97/flutter_query/issues/66). Up… |
| 223 | `QueryCache.build` | review, 2026-09-10, C8, 2026-09-12, QE-02 | … the state and fail in the next observer's constructor with type 'Null' is not a subtype of type 'int' (ninth review, 2026-09-10, C8). A restored QueryState.fetchStatus i… |
| 293 | `QueryCache.clear` | review, 2026-09-12, QE-03 | …on and this one belongs to a client. Call this directly and the removals are delivered unbatched (pre-release review, 2026-09-12, QE-03).… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 16 | `QueryCacheEvent` | Something happened to a query in the cache. |
| 29 | `QueryAdded.QueryAdded.new` | Creates the event for query. |
| 37 | `QueryRemoved.QueryRemoved.new` | Creates the event for query. |
| 58 | `QueryObserverAdded.QueryObserverAdded.new` | Creates the event for query and the observer that attached. |
| 71 | `QueryObserverRemoved.QueryObserverRemoved.new` | Creates the event for query and the observer that detached. |
| 96 | `QueryObserverResultsUpdated.QueryObserverResultsUpdated.new` | Creates the event for query. |
| 150 | `QueryCache` | Every query, keyed by QueryKey. |
| 176 | `QueryCache.onSuccess` | Cache-wide hooks, upstream's QueryCacheConfig. |


### `query_kit/lib/src/query_client.dart` (auto-flagged: 13 jargon, 7 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 64 | `QueryDefaults.queryFn` | issues/7 | …back the wrong type — the same bargain the cache's typed reads make (https://github.com/KoTTi97/flutter_query/issues/7).… |
| 69 | `QueryDefaults.structuralSharing` | review, 2026-09-12 | …is recognised here too, and reaches each query as its own typed opt-out — select output included (pre-release review, 2026-09-12, F4).… |
| 327 | `QueryClient.focusManager` | issues/19 | …Owned by the client rather than global, so tests are hermetic (https://github.com/KoTTi97/flutter_query/issues/19).… |
| 431 | `QueryClient.isFetching` | review, 2026-09-23, L5-4 | … QueryFilters.fetchStatus passed here is ignored rather than combined, so it cannot make the count 0 (release review, 2026-09-23, L5-4).… |
| 496 | `QueryClient.getQueriesData` | review, 2026-09-09 | …lds another type, as getQueryData does — a null there would read as "nothing cached" and hide the bug (fourth review, 2026-09-09).… |
| 531 | `QueryClient.setQueryData` | review, 2026-09-10, C23, 2026-09-18 | …s call creates — name it when seeding a key before its query exists: setQueryData<List<Todo>>(key, []) (ninth review, 2026-09-10, C23; final review, 2026-09-18, SURF-1). … |
| 598 | `QueryClient.updateQueryData` | issues/17, review, 2026-09-23, L5-1 | …etQueryData because Dart cannot overload on "a value or a function" (https://github.com/KoTTi97/flutter_query/issues/17). Returning null from updater leaves the cache unt… |
| 727 | `QueryClient.resetQueries` | 2026-09-12, AR-12 | …fyManager.batch(() => …) form throws synchronously from a Promise-returning method (pre-release verification, 2026-09-12, AR-12).… |
| 863 | `QueryClient.query` | issues/17, review, 2026-09-23, LIB-2, LIB-3 | …ery and ensureQueryData are deprecated in favour of this one method (https://github.com/KoTTi97/flutter_query/issues/17): to prefetch, ignore the future: client.query(opt… |
| 925 | `QueryClient.resumePausedMutations` | review, 2026-09-09, 2026-09-10, C10 | ….isOnline(), so an always mutation paused in the background was not resumed by a refocus while offline (fifth review, 2026-09-09). mount's listeners await this before the… |
| 962 | `QueryClient.clear` | review, 2026-09-10, C11, MU-01, 2026-09-12, QE-03 | …s the callbacks run and clears once more — the widget-test teardown the Flutter binding documents does (ninth review, 2026-09-10, C11). A mutation restored from persisten… |
| 1273 | `QueryClient.infiniteObserverOptions` | review, 2026-09-10 | …ns are refused there — and a documented path that nothing outside the package may take is not a path (seventh review, 2026-09-10). InfiniteQueryObserver.setInfiniteOption… |
| 1294 | `QueryClient.infiniteQuery` | issues/17 | …ensureInfiniteQueryData — .ignore() and staleTime: StaleTime.static (https://github.com/KoTTi97/flutter_query/issues/17). A typed convenience: an InfiniteQueryOptions car… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 85 | `MutationDefaults.retryDelay` | Default for retryDelay: the backoff between retries. |
| 85 | `QueryDefaults.retryDelay` | Default for retryDelay: the backoff between retries. |
| 188 | `MutationDefaults` | Type-agnostic mutation defaults. |
| 270 | `DefaultOptions` | Client-wide defaults. |
| 405 | `QueryClient.unmount` | Stops listening. Balanced with mount. |
| 788 | `QueryClient.refetchQueries` | Refetches every matching query that can actually fetch. |
| 1025 | `QueryClient.defaultQueryOptions` | Resolves options against the client and key defaults. |


### `query_kit/lib/src/query_key.dart` (auto-flagged: 1 jargon, 0 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 62 | `QueryKey` | review, 2026-09-10, C23, 2026-09-23 | …lds in Dart on every platform, so QueryKey([1]) and QueryKey([1.0]) are the same key — not a web quirk (ninth review, 2026-09-10, C23). Two DateTime parts compare by inst… |


### `query_kit/lib/src/query_observer.dart` (auto-flagged: 5 jargon, 3 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 32 | `QueryObserver` | issues/7, ADR-0001 | …ds (TQueryData) and what the consumer sees after select (TData). See https://github.com/KoTTi97/flutter_query/issues/7. Takes either options shape — a QueryObserverOption… |
| 84 | `QueryObserver.subscribe` | 2026-09-12, AR-02 | …t is registered and an observer that is attached, and the query is never collected (pre-release verification, 2026-09-12, AR-02).… |
| 343 | `QueryObserver.getOptimisticResult` | issues/15 | …widget's first build shows isLoading rather than a stale idle state (https://github.com/KoTTi97/flutter_query/issues/15).… |
| 513 | `QueryObserver.createResult` | issues/16 | …rotected rather than private so InfiniteQueryObserver can extend it (https://github.com/KoTTi97/flutter_query/issues/16).… |
| 792 | `QueryObserver.shouldNotify` | review, 2026-09-09 | …ver adds its paging flags this way, which are not part of the result and used to change without a word (fifth review, 2026-09-09).… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 176 | `QueryObserver.currentResult` | The most recently computed result. |
| 372 | `QueryObserver.refetch` | Refetches, completing with the result the refetch produced. |
| 372 | `QueryController.refetch` | Refetches, completing with the result the refetch produced. |


### `query_kit/lib/src/query_options.dart` (auto-flagged: 10 jargon, 26 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 36 | `QueryFunctionContext.QueryFunctionContext.new` | API-02, 2026-09-12 | …al: QueryCancelToken())) — and leave onSignalRead unset; it is how the query learns that signal was consumed (API-02, 2026-09-12).… |
| 78 | `QueryFunctionContext.signal` | review, 2026-09-12 | …al only once across repeated accesses). Here that is one call to _onSignalRead, not one per read (pre-release review, 2026-09-12, fidelity P11). A retry is a new context,… |
| 127 | `StructuralSharing` | issues/12, review, 2026-09-12 | …e — or to a function of your own to reconcile typed models yourself (https://github.com/KoTTi97/flutter_query/issues/12). A hook governs the cache write and unselected pl… |
| 156 | `noStructuralSharing` | review, 2026-09-12 | …selection of another type, so a hook of your own leaves the selection shared by the default walk (pre-release review, 2026-09-12, F4). A call rather than a function to pa… |
| 261 | `InitialDataCompute.compute` | #9743 | … data; once seeded or fetched it is never consulted again. That is upstream's Query.setOptions (TanStack/query#9743), and it is what lets a detail seed itself from a list… |
| 527 | `QueryObserverOptionsBase.toStringFields` | review, 2026-09-10, C23 | …int reads QueryOptions<int>(QueryKey(["a"]), staleTime: …) rather than Instance of 'QueryOptions<int>' (ninth review, 2026-09-10, C23). A subclass adds its own fields aft… |
| 527 | `QueryOptions.toStringFields` | review, 2026-09-10, C23 | …int reads QueryOptions<int>(QueryKey(["a"]), staleTime: …) rather than Instance of 'QueryOptions<int>' (ninth review, 2026-09-10, C23). A subclass adds its own fields aft… |
| 572 | `QueryObserverOptionsBase` | review, C1, ADR-0001 | … TData to dynamic — a Query<dynamic> in the cache that every typed reader of the key then tripped over (ninth review, C1; ADR-0001). This is what QueryObserver, QueryClie… |
| 791 | `QueryObserverOptions.withSelect` | review, 2026-09-23, LIB-3 | … without being written out again field by field — the spelled-out copy is where a field went missing (release review, 2026-09-23, LIB-3). final taskName = taskQuery(id).w… |
| 1177 | `DefaultedQueryObserverOptions.queryOptions` | review, C52, 2026-09-09 | …ery configurations, and the query they share would churn between them (read as dead weight once, by the ninth review's C52 — it is a projection, and it is load-bearing). … |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 224 | `InitialDataValue.InitialDataValue.new` | Seeds the cache with data. |
| 227 | `InitialDataValue.data` | The seed. |
| 327 | `PlaceholderDataKeepPrevious` | The PlaceholderData.keepPrevious variant, with no callback allocation. |
| 348 | `PlaceholderDataValue.PlaceholderDataValue.new` | Shows data until real data arrives. |
| 351 | `PlaceholderDataValue.data` | The placeholder. |
| 370 | `PlaceholderDataCompute.PlaceholderDataCompute.new` | Shows what compute returns, unless that is null. |
| 727 | `QueryObserverOptions.select` | Always null: a plain query has no projection. |
| 976 | `DefaultedQueryOptions.queryKey` | QueryOptions.queryKey. |
| 984 | `DefaultedQueryOptions.enabled` | QueryOptions.enabled, with the default applied. |
| 987 | `DefaultedQueryOptions.staleTime` | QueryOptions.staleTime, with the default applied. |
| 990 | `DefaultedQueryOptions.gcTime` | QueryOptions.gcTime, with the default applied. |
| 993 | `DefaultedQueryOptions.retry` | QueryOptions.retry, with the default applied. |
| 996 | `DefaultedQueryOptions.retryDelay` | QueryOptions.retryDelay, with the default applied. |
| 999 | `DefaultedQueryOptions.networkMode` | QueryOptions.networkMode, with the default applied. |
| 1002 | `DefaultedQueryOptions.initialData` | QueryOptions.initialData; there is no default. |
| 1005 | `DefaultedQueryOptions.initialDataUpdatedAt` | QueryOptions.initialDataUpdatedAt; there is no default. |
| 1012 | `DefaultedQueryOptions.structuralSharing` | QueryOptions.structuralSharing; null still means replaceEqualDeep. |
| 1018 | `DefaultedQueryOptions.behavior` | QueryOptions.behavior: set for infinite queries, null otherwise. |
| 1106 | `DefaultedQueryObserverOptions` | DefaultedQueryOptions plus the observer-only options. |
| 1141 | `DefaultedQueryObserverOptions.placeholderData` | QueryObserverOptionsBase.placeholderData; there is no default. |
| 1144 | `DefaultedQueryObserverOptions.refetchOnMount` | QueryObserverOptionsBase.refetchOnMount, with the default applied. |
| 1147 | `DefaultedQueryObserverOptions.refetchOnWindowFocus` | QueryObserverOptionsBase.refetchOnWindowFocus, with the default applied. |
| 1150 | `DefaultedQueryObserverOptions.refetchOnReconnect` | QueryObserverOptionsBase.refetchOnReconnect, with the default applied. |
| 1153 | `DefaultedQueryObserverOptions.refetchInterval` | QueryObserverOptionsBase.refetchInterval, with the default applied. |
| 1157 | `DefaultedQueryObserverOptions.refetchIntervalInBackground` | QueryObserverOptionsBase.refetchIntervalInBackground, with the default applied. |
| 1160 | `DefaultedQueryObserverOptions.retryOnMount` | QueryObserverOptionsBase.retryOnMount, with the default applied. |


### `query_kit/lib/src/query_result.dart` (auto-flagged: 1 jargon, 9 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 87 | `QueryResult.consecutiveErrorCount` | review, 2026-09-23, LIB-2 | …t: after such a write the result is a success while polling that stopped on this count stays stopped (release review, 2026-09-23, LIB-2).… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 74 | `QueryResult.failureStackTrace` | The stack trace that came with failureReason. |
| 122 | `QueryResult.isPending` | Whether this is a QueryPending — upstream's isPending. |
| 125 | `QueryResult.isSuccess` | Whether this is a QuerySuccess — upstream's isSuccess. |
| 128 | `QueryResult.isError` | Whether this is a QueryError — upstream's isError. |
| 139 | `QueryResult.isLoading` | The first load: pending and fetching. |
| 142 | `QueryResult.isRefetching` | A fetch over data that is already there. |
| 188 | `QueryPending` | Nothing has resolved yet. |
| 269 | `QueryError.error` | What the last attempt threw — upstream's error. |
| 275 | `QueryError.staleData` | The last good data, if there is any. |


### `query_kit/lib/src/query_state.dart` (auto-flagged: 2 jargon, 5 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 53 | `QueryState` | issues/12, issues/7, issues/17 | … sealing happens one layer up, in QueryResult, where users live. See https://github.com/KoTTi97/flutter_query/issues/12. hasData is the port's answer to upstream's two nu… |
| 135 | `QueryState.consecutiveErrorCount` | issues/85 | …: neither says anything about whether the source answers. Port-only (https://github.com/KoTTi97/flutter_query/issues/85): upstream's fetchFailureCount starts over with ev… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 22 | `FetchStatus` | What a query is doing right now. |
| 99 | `QueryState.hasData` | Whether data means anything. See the class doc. |
| 117 | `QueryState.errorStackTrace` | The stack trace that came with error. |
| 151 | `QueryState.fetchFailureStackTrace` | The stack trace that came with fetchFailureReason. |
| 162 | `QueryState.status` | What the query holds: pending, success or error. |


### `query_kit/lib/src/structural_sharing.dart` (auto-flagged: 2 jargon, 0 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 59 | `StructurallyShareable` | first integration, issues/86 | …element's instance: == downstream still holds, identical and everything built on it does not (measured by the first integration, 25 of 25 instances lost; https://github.c… |
| 126 | `replaceEqualDeep` | first integration, 2026-09-19, review, 2026-09-12, R2-1, R2-2, R2-4, AR-01, 2026-09-09, issues/12 | …eds the cache to hold a sealed list in that case has the static types to seal it in a structuralSharing hook (first integration, 2026-09-19, I1). A set is compared as a m… |


### `query_kit_flutter/lib/query_kit_flutter.dart` (auto-flagged: 1 jargon, 0 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 18 | `query_kit_flutter` | issues/21 | …ways to reach a query, none of which needs a package beyond Flutter (https://github.com/KoTTi97/flutter_query/issues/21): QueryController / InfiniteQueryController / Muta… |


### `query_kit_flutter/lib/src/controller_lifetime.dart` (auto-flagged: 0 jargon, 2 short/restating)

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 74 | `MutationController.isDisposed` | Whether dispose has run. |
| 74 | `QueryController.isDisposed` | Whether dispose has run. |


### `query_kit_flutter/lib/src/is_fetching_controller.dart` (auto-flagged: 1 jargon, 1 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 18 | `IsFetchingController` | review, 2026-09-18, B-1 | …ubscribed to the query cache only while something listens, and it notifies only when the count changes (final review, 2026-09-18, B-1). QueryClient.isFetching is the same… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 27 | `IsFetchingController.client` | The client whose queries are counted. |


### `query_kit_flutter/lib/src/mutation_state_controller.dart` (auto-flagged: 0 jargon, 3 short/restating)

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 11 | `MutationStateController` | Selected mutation values, subscribed only while something listens. |
| 14 | `MutationStateController.MutationStateController.new` | Creates a selection over client's mutation cache. |
| 46 | `MutationStateController.client` | The client whose mutations are selected. |


### `query_kit_flutter/lib/src/online_status.dart` (auto-flagged: 1 jargon, 5 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 36 | `OnlineStatus` | issues/10 | … this port — a sealed value type rather than a pair of half-answers (https://github.com/KoTTi97/flutter_query/issues/10), and null on the option itself is the only way to… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 59 | `OnlineStatusFixed` | The OnlineStatus.fixed variant: one value, no stream. |
| 61 | `OnlineStatusFixed.OnlineStatusFixed.new` | The client is online. |
| 64 | `OnlineStatusFixed.online` | Whether the network counts as reachable. |
| 85 | `OnlineStatusStream.OnlineStatusStream.new` | Follows changes from initial. |
| 99 | `OnlineStatusStream.initial` | What to assume until changes has said anything. |


### `query_kit_flutter/lib/src/queries_builder.dart` (auto-flagged: 1 jargon, 1 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 28 | `QueriesBuilder` | C49, issues/55, review, 2026-09-23, B2-4 | …ebuild decision is the controller's. The four call styles all take a predicate over the one result they read (C49, https://github.com/KoTTi97/flutter_query/issues/55); th… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 45 | `QueriesBuilder.client` | Explicit client; omission uses the nearest QueryClientProvider. |


### `query_kit_flutter/lib/src/queries_controller.dart` (auto-flagged: 0 jargon, 1 short/restating)

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 19 | `QueriesController.client` | The client all queries in this collection use. |


### `query_kit_flutter/lib/src/query_builder.dart` (auto-flagged: 3 jargon, 9 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 86 | `QueryBuilder` | ADR-0001 | …nt is the query's data type; it comes from queryFn's return type, or is written out as QueryBuilder<Task>(…) (ADR-0001). Use QuerySelectBuilder when the query needs a sel… |
| 120 | `QueryBuilder.buildWhen` | issues/15 | …the port's answer to upstream's notifyOnChangeProps, next to select (https://github.com/KoTTi97/flutter_query/issues/15). Given the result this widget last built from and… |
| 226 | `InfiniteQueryBuilder` | ADR-0001 | …initeQueryObserverOptions or InfiniteQuerySelectOptions — carries all three, and inference reads them off it (ADR-0001).… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 165 | `InfiniteQueryBuilder.options` | See QueryBuilder.options. |
| 165 | `MutationBuilder.options` | See QueryBuilder.options. |
| 165 | `QuerySelectBuilder.options` | See QueryBuilder.options. |
| 175 | `QuerySelectBuilder.buildWhen` | See QueryBuilder.buildWhen. |
| 179 | `InfiniteQueryBuilder.client` | See QueryBuilder.client. |
| 179 | `MutationBuilder.client` | See QueryBuilder.client. |
| 179 | `QuerySelectBuilder.client` | See QueryBuilder.client. |
| 256 | `InfiniteQueryBuilder.buildWhen` | See QueryBuilder.buildWhen. Compares the controller's results. |
| 334 | `MutationBuilder.buildWhen` | See QueryBuilder.buildWhen. Compares the mutation's results. |


### `query_kit_flutter/lib/src/query_client_provider.dart` (auto-flagged: 3 jargon, 0 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 109 | `QueryClientProvider.onlineStatus` | review, 2026-09-23, V-B-3, 2026-09-10, issues/60 | …later build, or when the provider leaves the tree: nothing is left to revise an offline verdict then (release review 2026-09-23, BIND-4). Only the last provider with a st… |
| 121 | `QueryClientProvider.observeAppLifecycle` | issues/60 | …stener is the seam for a focus source that is not the app lifecycle (https://github.com/KoTTi97/flutter_query/issues/60).… |
| 132 | `QueryClientProvider.isAppShown` | review, 2026-09-10 | …ride it for a platform whose conventions differ, or to switch focus refetching to a signal of your own (sixth review, 2026-09-10). The mapping given on the latest build i… |


### `query_kit_flutter/lib/src/query_context.dart` (auto-flagged: 3 jargon, 1 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 137 | `QueryContext.query` | C49, issues/55 | …narrow away — a background refetch moves fetchStatus and dataUpdatedAt, and both are inside QueryResult's == (C49, https://github.com/KoTTi97/flutter_query/issues/55). Ea… |
| 146 | `QueryContext.selectQuery` | ADR-0001 | …query for a query with a select: a QuerySelectOptions, whose required select anchors TData (ADR-0001).… |
| 229 | `QueryContext.mutation` | issues/67 | …ationObserver has already dropped the ones carrying an equal result (https://github.com/KoTTi97/flutter_query/issues/67).… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 104 | `QueryContext` | Reading queries and mutations from a BuildContext. |


### `query_kit_flutter/lib/src/query_controller.dart` (auto-flagged: 5 jargon, 4 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 101 | `QueryController.create` | ADR-0001, review, 2026-09-10 | …d one type argument names it — from queryFn's return type, or written out as QueryController.create<Task>(…) (ADR-0001). A static method rather than a named constructor b… |
| 172 | `QueryController.setOptions` | issues/22, review, 2026-09-23, B2-3 | …changed key switches the observed query without recreating anything (https://github.com/KoTTi97/flutter_query/issues/22). Deliberately does not notify: the observer notif… |
| 217 | `InfiniteQueryController` | issues/16, ADR-0001 | …enable, with the paging operations the sealed result does not carry (https://github.com/KoTTi97/flutter_query/issues/16). final feed = InfiniteQueryController(client, fee… |
| 388 | `MutationController.observer` | second pass, review, 2026-09-23, V-B-5 | …body listens to the per-call callbacks are dropped, as the core drops them for an observer without listeners (second pass of the release review 2026-09-23, V-B-5). Run mu… |
| 431 | `MutationController.mutateAsync` | review, 2026-09-10, C18 | …n observer, so the mutation stays in the cache for good; a disposed controller here does not come back (ninth review, 2026-09-10, C18). Hold the controller above the widg… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 108 | `MutationController.client` | The client the observer runs on. |
| 108 | `QueryController.client` | The client the observer runs on. |
| 245 | `InfiniteQueryController.infiniteObserver` | The observer underneath, typed. |
| 346 | `MutationController` | One mutation, as a ValueListenable. |


### `query_kit_flutter/lib/src/query_listener.dart` (auto-flagged: 1 jargon, 10 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 26 | `QueryListener.QueryListener.new` | review, 2026-09-10, C19 | …nable: two cache writes inside one notifyManager.batch are one transition to the second value, not two (ninth review, 2026-09-10, C19).… |

Short / name-restating docs (heuristic; judge per row — many field docs on action/event classes are acceptable):

| line | symbol | doc |
|---|---|---|
| 39 | `InfiniteQueryListener.InfiniteQueryListener.new` | Observes controller without disposing it or rebuilding child. |
| 71 | `InfiniteQueryListener.controller` | The borrowed controller, disposed by its owner. |
| 71 | `MutationListener.controller` | The borrowed controller, disposed by its owner. |
| 71 | `QueryListener.controller` | The borrowed controller, disposed by its owner. |
| 77 | `InfiniteQueryListener.listenWhen` | Filters transitions; omission accepts every changed result. |
| 77 | `MutationListener.listenWhen` | Filters transitions; omission accepts every changed result. |
| 77 | `QueryListener.listenWhen` | Filters transitions; omission accepts every changed result. |
| 80 | `InfiniteQueryListener.child` | Returned unchanged; controller events never rebuild this child. |
| 80 | `MutationListener.child` | Returned unchanged; controller events never rebuild this child. |
| 80 | `QueryListener.child` | Returned unchanged; controller events never rebuild this child. |


### `query_kit_flutter/lib/src/query_mixin.dart` (auto-flagged: 3 jargon, 0 short/restating)

Internal-history references in rendered docs:

| line | symbol | tokens | excerpt |
|---|---|---|---|
| 110 | `QueryMixin.watchQuery` | C49, issues/55 | …narrow away — a background refetch moves fetchStatus and dataUpdatedAt, and both are inside QueryResult's == (C49, https://github.com/KoTTi97/flutter_query/issues/55). Ea… |
| 119 | `QueryMixin.watchSelectQuery` | ADR-0001 | …watchQuery for a query with a select: a QuerySelectOptions, whose required select anchors TData (ADR-0001).… |
| 182 | `QueryMixin.watchMutation` | issues/67 | …ationObserver has already dropped the ones carrying an equal result (https://github.com/KoTTi97/flutter_query/issues/67).… |

## Appendix A — every `///` block in `lib/` with internal-history tokens

Includes private members, `@internal` members and `src/` library docs that pub.dev does not render; these still show in IDE hovers for users who jump to source, so they are lower priority but should follow the same rewrite. Format: `file:line (declaration) — tokens`.

```
query_kit/lib/query_kit.dart:1 (library;) — 50680b98c, review, 2026-09-10, C23, 2026-09-09
query_kit/lib/src/cancel_token.dart:1 (library;) — 50680b98c, issues/11
query_kit/lib/src/cancel_token.dart:56 (void onCancel(void Function() callback) {) — review, 2026-09-10, C16
query_kit/lib/src/combined_result.dart:1 (library;) — issues/82
query_kit/lib/src/combined_result.dart:66 (Future<void> refetch({bool cancelRefetch = true}) ) — review, 2026-09-23, LIB-5
query_kit/lib/src/combined_result.dart:167 (final class CombineMemo<T> {) — 2026-09-20
query_kit/lib/src/filters.dart:1 (library;) — 50680b98c
query_kit/lib/src/filters.dart:44 (final class QueryFilters {) — issues/17
query_kit/lib/src/filters.dart:205 (String describeFilters(String type, Map<String, Ob) — review, 2026-09-10, C23
query_kit/lib/src/focus_manager.dart:1 (library;) — 50680b98c
query_kit/lib/src/focus_manager.dart:15 (class AppFocusManager extends Subscribable<void Fu) — issues/19, issues/60
query_kit/lib/src/focus_manager.dart:62 (void onSubscribe() {) — review, 2026-09-23
query_kit/lib/src/hashing.dart:6 (int spreadHash(int hash) =>) — reviews, R3-1
query_kit/lib/src/infinite_query.dart:1 (library;) — 50680b98c, issues/16
query_kit/lib/src/infinite_query.dart:23 (final class InfiniteData<TPageData, TPageParam> {) — review, 2026-09-10, C20
query_kit/lib/src/infinite_query.dart:38 (InfiniteData({required this.pages, required this.p) — review, 2026-09-12, IN-01
query_kit/lib/src/infinite_query.dart:73 (Iterable<TItem> flatten<TItem>() {) — review, 2026-09-10, C20
query_kit/lib/src/infinite_query.dart:113 (bool operator ==(Object other) =>) — review, 2026-09-23, L3-2
query_kit/lib/src/infinite_query.dart:149 (InfinitePageContext({) — API-02, 2026-09-12
query_kit/lib/src/infinite_query.dart:190 (typedef PageParamFn<TPageData, TPageParam> = TPage) — issues/16
query_kit/lib/src/infinite_query.dart:260 (final int? pages;) — IN-02, 2026-09-12
query_kit/lib/src/infinite_query.dart:341 (FetchBehavior<InfiniteData<TPageData, TPageParam>>) — review, 2026-09-09
query_kit/lib/src/infinite_query.dart:370 (sealed class InfiniteQueryObserverOptionsBase<TPag) — ADR-0001
query_kit/lib/src/infinite_query.dart:627 (InfiniteQuerySelectOptions<TPageData, TPageParam, ) — review, 2026-09-23, LIB-3
query_kit/lib/src/infinite_query_observer.dart:1 (library;) — 50680b98c
query_kit/lib/src/infinite_query_observer.dart:22 (class InfiniteQueryObserver<TPageData, TPageParam,) — issues/16
query_kit/lib/src/infinite_query_observer.dart:40 (InfiniteQueryOptions<TPageData, TPageParam> get in) — review, 2026-09-09
query_kit/lib/src/infinite_query_observer.dart:163 (bool shouldNotify(QueryResult<TData>? previous, Qu) — review, 2026-09-09, 2026-09-10, C13
query_kit/lib/src/infinite_query_observer.dart:254 (bool hasNextPageOf<TPageData, TPageParam>() — review, 2026-09-10, C24
query_kit/lib/src/listener_registry.dart:1 (library;) — C50, issues/59
query_kit/lib/src/listener_registry.dart:7 (class ListenerRegistry<TListener extends Function>) — review, 2026-09-10, C6, 2026-09-09
query_kit/lib/src/mutation.dart:1 (library;) — 50680b98c
query_kit/lib/src/mutation.dart:42 (abstract interface class MutationObserverRef {) — review, 2026-09-10, C21
query_kit/lib/src/mutation.dart:82 (bool canRunMutation(Mutation<Object?, Object?, Obj) — review, 2026-09-23, L4-6
query_kit/lib/src/mutation.dart:228 (void validate() {) — review, 2026-09-12, MU-03, R2-3
query_kit/lib/src/mutation.dart:472 (MutationScope? get schedulingScope =>) — review, 2026-09-09
query_kit/lib/src/mutation.dart:543 (Future<void> continueMutation() {) — review, 2026-09-10, C10, C12
query_kit/lib/src/mutation.dart:584 (bool get canResume => _retryer != null) — review, 2026-09-10, C4, 2026-09-23, L4-4
query_kit/lib/src/mutation.dart:641 (void cancel() {) — review, 2026-09-23, L4-3, issues/83
query_kit/lib/src/mutation_cache.dart:1 (library;) — 50680b98c
query_kit/lib/src/mutation_cache.dart:91 (MutationCache({this.onMutate, this.onSuccess, this) — C59, issues/66
query_kit/lib/src/mutation_cache.dart:147 (final Set<Mutation<Object?, Object?, Object?>> _re) — review, 2026-09-23, third pass, V3-3
query_kit/lib/src/mutation_cache.dart:161 (Mutation<TData, TVariables, TOnMutateResult>) — review, 2026-09-10, C8, C12, 2026-09-12, MU-03, MU-02
query_kit/lib/src/mutation_cache.dart:237 (void remove(Mutation<Object?, Object?, Object?> mu) — review, DC-02, 2026-09-12, ADR-0003, MU-01
query_kit/lib/src/mutation_cache.dart:305 (void clear() {) — ADR-0003, MU-01, 2026-09-12
query_kit/lib/src/mutation_cache.dart:359 (Future<void> resumePaused() async {) — review, 2026-09-09, 2026-09-10, C4, C10, 2026-09-23, L4-4
query_kit/lib/src/mutation_cache.dart:443 (bool canRunMutation(Mutation<Object?, Object?, Obj) — review, 2026-09-23, L4-6
query_kit/lib/src/mutation_observer.dart:1 (library;) — 50680b98c
query_kit/lib/src/mutation_options.dart:1 (library;) — 50680b98c, issues/14
query_kit/lib/src/mutation_options.dart:16 (final class MutationScope {) — review, 2026-09-23, LIB-1
query_kit/lib/src/mutation_options.dart:66 (final class MutationFunctionContext<TOnMutateResul) — issues/83
query_kit/lib/src/mutation_options.dart:359 (final OnMutate<TVariables, TOnMutateResult>? onMut) — review, 2026-09-10
query_kit/lib/src/mutation_options.dart:367 (final OnMutationSuccess<TData, TVariables, TOnMuta) — review, 2026-09-10
query_kit/lib/src/mutation_options.dart:375 (final OnMutationError<TVariables, TOnMutateResult>) — review, 2026-09-10
query_kit/lib/src/mutation_options.dart:383 (final OnMutationSettled<TData, TVariables, TOnMuta) — review, 2026-09-10
query_kit/lib/src/mutation_result.dart:1 (library;) — issues/14
query_kit/lib/src/mutation_result.dart:59 (final bool isPaused;) — review, 2026-09-23, L4-6
query_kit/lib/src/mutation_result.dart:73 (final void Function(TVariables variables) mutate;) — review, 2026-09-10, C23
query_kit/lib/src/mutation_state_observer.dart:41 (static MutationStateObserver<TSelected> typed<TDat) — issues/85, review, 2026-09-23, L4-1
query_kit/lib/src/notify_manager.dart:1 (library;) — 50680b98c
query_kit/lib/src/notify_manager.dart:15 (class NotifyManager {) — issues/19
query_kit/lib/src/notify_manager.dart:38 (static final NotifyManager shared = NotifyManager() — review, 2026-09-09
query_kit/lib/src/online_manager.dart:1 (library;) — 50680b98c
query_kit/lib/src/online_manager.dart:14 (class OnlineManager extends Subscribable<void Func) — issues/21, issues/5
query_kit/lib/src/online_manager.dart:36 (void onSubscribe() {) — review, 2026-09-23
query_kit/lib/src/option_values.dart:1 (library;) — issues/10
query_kit/lib/src/option_values.dart:26 (static const StaleTime static = StaleTimeStatic();) — DC-05, 2026-09-12
query_kit/lib/src/option_values.dart:39 (const factory StaleTime.dynamic() — review, 2026-09-10
query_kit/lib/src/option_values.dart:94 (final class StaleTimeStatic extends StaleTime {) — 50680b98c, review, 2026-09-09
query_kit/lib/src/option_values.dart:219 (static const Enabled no = EnabledNo();) — issues/17, review, 2026-09-12
query_kit/lib/src/option_values.dart:232 (const factory Enabled.when(bool Function(Query<Obj) — review, 2026-09-10
query_kit/lib/src/queries_observer.dart:1 (library;) — 50680b98c
query_kit/lib/src/queries_observer.dart:53 (void Function() subscribe(void Function(List<Query) — 2026-09-12, AR-02
query_kit/lib/src/query.dart:1 (library;) — 50680b98c
query_kit/lib/src/query.dart:20 (abstract interface class QueryObserverRef {) — review, 2026-09-10, C21
query_kit/lib/src/query.dart:98 (abstract interface class FetchBehavior<TQueryData>) — issues/16
query_kit/lib/src/query.dart:186 (final RetryPolicy? retry;) — review, 2026-09-09
query_kit/lib/src/query.dart:302 (class Query<TQueryData> extends Removable {) — issues/7
query_kit/lib/src/query.dart:336 (Type get dataType => TQueryData;) — review, 2026-09-09
query_kit/lib/src/query.dart:374 (Completer<TQueryData>? _operation;) — review, 2026-09-09
query_kit/lib/src/query.dart:474 (bool canHold(Object? value) => value is TQueryData) — review, 2026-09-23, L5-1, V-C-7, 2026-09-18
query_kit/lib/src/query.dart:488 (void setState(QueryState<TQueryData> state) {) — issues/17, review, 2026-09-10, 2026-09-12, QE-02
query_kit/lib/src/query.dart:521 (Future<void> cancel({bool revert = false, bool sil) — review, 2026-09-10, 2026-09-12, C9
query_kit/lib/src/query.dart:624 (bool isActive() => List<QueryObserverRef>.of(_obse) — review, 2026-09-12, AR-04
query_kit/lib/src/query.dart:668 (bool isStatic() =>) — AR-04
query_kit/lib/src/query.dart:817 (Future<TQueryData> fetch({) — review, 2026-09-09
query_kit/lib/src/query.dart:996 (Future<void> _settle() — review, 2026-09-23, L1-1
query_kit/lib/src/query.dart:1078 (void _runCacheHook(void Function() hook) {) — review, 2026-09-10, C3
query_kit/lib/src/query_cache.dart:1 (library;) — 50680b98c
query_kit/lib/src/query_cache.dart:77 (final class QueryObserverOptionsUpdated extends Qu) — DC-04, 2026-09-12
query_kit/lib/src/query_cache.dart:99 (final class QueryDataTypeError implements Exceptio) — issues/7
query_kit/lib/src/query_cache.dart:152 (QueryCache({this.onSuccess, this.onError, this.onS) — C59, issues/66
query_kit/lib/src/query_cache.dart:199 (Query<TQueryData> build<TQueryData>() — review, 2026-09-10, C8, 2026-09-12, QE-02
query_kit/lib/src/query_cache.dart:286 (void clear() {) — review, 2026-09-12, QE-03
query_kit/lib/src/query_cache.dart:347 (void notify(QueryCacheEvent event) =>) — review, 2026-09-09
query_kit/lib/src/query_client.dart:1 (library;) — 50680b98c
query_kit/lib/src/query_client.dart:57 (final QueryFn<Object?>? queryFn;) — issues/7
query_kit/lib/src/query_client.dart:66 (final Object? Function(Object? previous, Object? n) — review, 2026-09-12
query_kit/lib/src/query_client.dart:325 (final AppFocusManager focusManager;) — issues/19
query_kit/lib/src/query_client.dart:385 (Future<void> _resumeThen(void Function() then) asy) — review, 2026-09-18, C-P3-2
query_kit/lib/src/query_client.dart:425 (int isFetching({QueryFilters filters = const Query) — review, 2026-09-23, L5-4
query_kit/lib/src/query_client.dart:490 (List<(QueryKey, TQueryData?)> getQueriesData<TQuer) — review, 2026-09-09
query_kit/lib/src/query_client.dart:511 (TQueryData setQueryData<TQueryData>() — review, 2026-09-10, C23, 2026-09-18
query_kit/lib/src/query_client.dart:586 (TQueryData? updateQueryData<TQueryData>() — issues/17, review, 2026-09-23, L5-1
query_kit/lib/src/query_client.dart:718 (Future<void> resetQueries({) — 2026-09-12, AR-12
query_kit/lib/src/query_client.dart:815 (Future<TQueryData> query<TQueryData>(QueryOptions<) — issues/17, review, 2026-09-23, LIB-2, LIB-3
query_kit/lib/src/query_client.dart:905 (Future<void> resumePausedMutations() => mutationCa) — review, 2026-09-09, 2026-09-10, C10
query_kit/lib/src/query_client.dart:927 (void clear() {) — review, 2026-09-10, C11, MU-01, 2026-09-12, QE-03
query_kit/lib/src/query_client.dart:1263 (QueryObserverOptionsBase<InfiniteData<TPageData, T) — review, 2026-09-10
query_kit/lib/src/query_client.dart:1283 (Future<InfiniteData<TPageData, TPageParam>>) — issues/17
query_kit/lib/src/query_key.dart:1 (library;) — 50680b98c, issues/8
query_kit/lib/src/query_key.dart:14 (final class QueryKey {) — review, 2026-09-10, C23, 2026-09-23
query_kit/lib/src/query_observer.dart:1 (library;) — 50680b98c
query_kit/lib/src/query_observer.dart:24 (class QueryObserver<TQueryData, TData> implements ) — issues/7, ADR-0001
query_kit/lib/src/query_observer.dart:71 (void Function() subscribe(QueryObserverListener<TD) — 2026-09-12, AR-02
query_kit/lib/src/query_observer.dart:337 (QueryResult<TData> getOptimisticResult() — issues/15
query_kit/lib/src/query_observer.dart:399 (static void _checkDataType<TQueryData, TData>() — review, 2026-09-09
query_kit/lib/src/query_observer.dart:508 (QueryResult<TData> createResult() — issues/16
query_kit/lib/src/query_observer.dart:783 (bool shouldNotify(QueryResult<TData>? previous, Qu) — review, 2026-09-09
query_kit/lib/src/query_observer.dart:910 (extension _RefetchRules on DefaultedQueryObserverO) — review, C53
query_kit/lib/src/query_options.dart:1 (library;) — 50680b98c, issues/10
query_kit/lib/src/query_options.dart:31 (QueryFunctionContext({) — API-02, 2026-09-12
query_kit/lib/src/query_options.dart:64 (QueryCancelToken get signal {) — review, 2026-09-12
query_kit/lib/src/query_options.dart:100 (typedef StructuralSharing<TQueryData> = TQueryData) — issues/12, review, 2026-09-12
query_kit/lib/src/query_options.dart:130 (StructuralSharing<TQueryData> noStructuralSharing<) — review, 2026-09-12
query_kit/lib/src/query_options.dart:251 (final TQueryData? Function() compute;) — #9743
query_kit/lib/src/query_options.dart:521 (Map<String, Object?> get toStringFields => <String) — review, 2026-09-10, C23
query_kit/lib/src/query_options.dart:553 (sealed class QueryObserverOptionsBase<TQueryData, ) — review, C1, ADR-0001
query_kit/lib/src/query_options.dart:783 (QuerySelectOptions<TData, R> withSelect<R>(SelectF) — review, 2026-09-23, LIB-3
query_kit/lib/src/query_options.dart:1162 (late final DefaultedQueryOptions<TQueryData> query) — review, C52, 2026-09-09
query_kit/lib/src/query_result.dart:1 (library;) — 50680b98c, issues/12
query_kit/lib/src/query_result.dart:79 (final int consecutiveErrorCount;) — review, 2026-09-23, LIB-2
query_kit/lib/src/query_state.dart:1 (library;) — 50680b98c
query_kit/lib/src/query_state.dart:35 (final class QueryState<TQueryData> {) — issues/12, issues/7, issues/17
query_kit/lib/src/query_state.dart:54 (void validate() {) — review, 2026-09-12, R2-3
query_kit/lib/src/query_state.dart:123 (final int consecutiveErrorCount;) — issues/85
query_kit/lib/src/removable.dart:1 (library;) — 50680b98c
query_kit/lib/src/removable.dart:11 (abstract class Removable {) — review, 2026-09-09
query_kit/lib/src/retryer.dart:1 (library;) — 50680b98c
query_kit/lib/src/retryer.dart:34 (bool canContinue(NetworkMode networkMode, OnlineMa) — review, 2026-09-10, C4
query_kit/lib/src/retryer.dart:146 (Future<TData> start() {) — review, 2026-09-09
query_kit/lib/src/retryer.dart:246 (bool _hook(void Function()? hook) {) — review, 2026-09-09
query_kit/lib/src/structural_sharing.dart:1 (library;) — 50680b98c
query_kit/lib/src/structural_sharing.dart:14 (abstract interface class StructurallyShareable<T> ) — first integration, issues/86
query_kit/lib/src/structural_sharing.dart:65 (T replaceEqualDeep<T>(Object? previous, T next, [i) — first integration, 2026-09-19, review, 2026-09-12, R2-1, R2-2, R2-4, AR-01, 2026-09-09, issues/12
query_kit/lib/src/structural_sharing.dart:282 (bool _equalDeep(Object? a, Object? b, int depth) {) — review, 2026-09-09
query_kit/lib/src/structural_sharing.dart:383 (int sharingBucketOf(Object? value, int depth) =>) — R3-1, review
query_kit/lib/src/subscribable.dart:1 (library;) — 50680b98c
query_kit/lib/src/subscribable.dart:8 (abstract class Subscribable<TListener extends Func) — C50, issues/59
query_kit/lib/src/timers.dart:1 (library;) — 50680b98c, review, 2026-09-09
query_kit/lib/src/timers.dart:30 (Duration ceilToMilliseconds(Duration duration) {) — review, 2026-09-09
query_kit_flutter/lib/query_kit_flutter.dart:1 (library;) — issues/21
query_kit_flutter/lib/src/controller_lifetime.dart:1 (library;) — C50, issues/59
query_kit_flutter/lib/src/controller_lifetime.dart:9 (class ControllerLifetime<S> {) — review, 2026-09-10
query_kit_flutter/lib/src/is_fetching_controller.dart:10 (class IsFetchingController extends ChangeNotifier) — review, 2026-09-18, B-1
query_kit_flutter/lib/src/mutation_state_controller.dart:49 (late final ControllerLifetime<List<TSelected>> _li) — C15, C50
query_kit_flutter/lib/src/notify_gate.dart:1 (library;) — C48, issues/57, C49, issues/55
query_kit_flutter/lib/src/online_status.dart:1 (library;) — issues/60
query_kit_flutter/lib/src/online_status.dart:7 (sealed class OnlineStatus {) — issues/10
query_kit_flutter/lib/src/queries_builder.dart:11 (class QueriesBuilder<TQueryData, TData> extends St) — C49, issues/55, review, 2026-09-23, B2-4
query_kit_flutter/lib/src/queries_builder.dart:52 (class _QueriesBuilderState<TQueryData, TData>) — C59, issues/66, issues/58
query_kit_flutter/lib/src/queries_builder.dart:97 (List<(QueryResult<TData>, QueryRefetch<TData>)>? _) — review, 2026-09-23, B2-4
query_kit_flutter/lib/src/query_builder.dart:1 (library;) — issues/21, C48, C59, issues/57
query_kit_flutter/lib/src/query_builder.dart:33 (Object get options;) — #84, review, 2026-09-23, issues/10
query_kit_flutter/lib/src/query_builder.dart:54 (mixin _QueryBuilderWidget<TQueryData, TData>) — C59
query_kit_flutter/lib/src/query_builder.dart:66 (class QueryBuilder<TData> extends StatefulWidget) — ADR-0001
query_kit_flutter/lib/src/query_builder.dart:111 (final BuildWhen<QueryResult<TData>>? buildWhen;) — issues/15
query_kit_flutter/lib/src/query_builder.dart:187 (class _QueryBuilderState<W extends _QueryBuilderWi) — C59
query_kit_flutter/lib/src/query_builder.dart:206 (class InfiniteQueryBuilder<TPageData, TPageParam, ) — ADR-0001
query_kit_flutter/lib/src/query_builder.dart:369 (abstract class _ControllerBuilderState<W extends _) — C48
query_kit_flutter/lib/src/query_client_provider.dart:1 (library;) — issues/22
query_kit_flutter/lib/src/query_client_provider.dart:87 (final OnlineStatus? onlineStatus;) — review, 2026-09-23, V-B-3, 2026-09-10, issues/60
query_kit_flutter/lib/src/query_client_provider.dart:111 (final bool observeAppLifecycle;) — issues/60
query_kit_flutter/lib/src/query_client_provider.dart:123 (final bool Function(AppLifecycleState state)? isAp) — review, 2026-09-10
query_kit_flutter/lib/src/query_client_provider.dart:223 (bool _released = false;) — fifth pass, V5-2
query_kit_flutter/lib/src/query_client_provider.dart:289 (static void _setFocused(QueryClient client, bool s) — review, 2026-09-23
query_kit_flutter/lib/src/query_client_provider.dart:323 (void _follow(OnlineStatus? onlineStatus) {) — review, 2026-09-09
query_kit_flutter/lib/src/query_client_provider.dart:374 (void _cancelOnline() {) — review, 2026-09-23, B1-2
query_kit_flutter/lib/src/query_client_provider.dart:403 (static void _releaseOnline(QueryClient client, {bo) — review, 2026-09-23, second pass, V-B-3
query_kit_flutter/lib/src/query_client_provider.dart:486 (static final Map<NotifyManager, ({ScheduleFunction) — review, 2026-09-10
query_kit_flutter/lib/src/query_context.dart:1 (library;) — issues/21, review, 2026-09-23, fourth pass, V4-5, V4-1, third pass, V3-1, V3-2
query_kit_flutter/lib/src/query_context.dart:105 (QueryResult<TData> query<TData>() — C49, issues/55
query_kit_flutter/lib/src/query_context.dart:144 (QueryResult<TData> selectQuery<TQueryData, TData>() — ADR-0001
query_kit_flutter/lib/src/query_context.dart:196 (MutationController<TData, TVariables, TOnMutateRes) — issues/67
query_kit_flutter/lib/src/query_context.dart:261 (class QueryScope extends InheritedWidget {) — C59, issues/66
query_kit_flutter/lib/src/query_context.dart:301 (final Map<Element, ReadSet> _readers = <Element, R) — C47, issues/56
query_kit_flutter/lib/src/query_context.dart:306 (final Set<Element> _detached = <Element>{};) — review, 2026-09-10
query_kit_flutter/lib/src/query_context.dart:327 (ReadSet readsFor(Element reader, String call) {) — V-B-2
query_kit_flutter/lib/src/query_controller.dart:1 (library;) — issues/21
query_kit_flutter/lib/src/query_controller.dart:22 (abstract interface class ObservedState {) — review, 2026-09-10
query_kit_flutter/lib/src/query_controller.dart:89 (static QueryController<TData, TData> create<TData>) — ADR-0001, review, 2026-09-10
query_kit_flutter/lib/src/query_controller.dart:160 (void setOptions(QueryObserverOptionsBase<TQueryDat) — issues/22, review, 2026-09-23, B2-3
query_kit_flutter/lib/src/query_controller.dart:203 (class InfiniteQueryController<TPageData, TPagePara) — issues/16, ADR-0001
query_kit_flutter/lib/src/query_controller.dart:379 (MutationObserver<TData, TVariables, TOnMutateResul) — second pass, review, 2026-09-23, V-B-5
query_kit_flutter/lib/src/query_controller.dart:413 (Future<TData> mutateAsync() — review, 2026-09-10, C18
query_kit_flutter/lib/src/query_controller.dart:493 (bool _debugDataTypeIsAnchored<TData>() => <Object?) — ADR-0001
query_kit_flutter/lib/src/query_listener.dart:18 (const QueryListener({) — review, 2026-09-10, C19
query_kit_flutter/lib/src/query_mixin.dart:1 (library;) — issues/21, review, 2026-09-23, fourth pass, V4-5
query_kit_flutter/lib/src/query_mixin.dart:69 (late final ReadSet _reads = ReadSet(rebuild: _rebu) — C47, issues/56
query_kit_flutter/lib/src/query_mixin.dart:86 (QueryResult<TData> watchQuery<TData>() — C49, issues/55
query_kit_flutter/lib/src/query_mixin.dart:117 (QueryResult<TData> watchSelectQuery<TQueryData, TD) — ADR-0001
query_kit_flutter/lib/src/query_mixin.dart:159 (MutationController<TData, TVariables, TOnMutateRes) — issues/67
query_kit_flutter/lib/src/query_mixin.dart:224 (void _reconcileClient() {) — review, 2026-09-10
query_kit_flutter/lib/src/read_entry.dart:1 (library;) — C48, issues/57, issues/21
query_kit_flutter/lib/src/read_entry.dart:62 (Object? _builtState;) — review, 2026-09-10
query_kit_flutter/lib/src/read_entry.dart:83 (bool _shouldRebuild() {) — review, 2026-09-09
query_kit_flutter/lib/src/read_set.dart:1 (library;) — issues/21, C47, issues/56, 2026-09-10, C48, issues/57, C49, issues/55, issues/67
query_kit_flutter/lib/src/read_set.dart:60 (typedef _MutationShape = () — third pass, V3-6, fourth pass, V4-3, fifth pass, V5-3
query_kit_flutter/lib/src/read_set.dart:71 (class ReadSet {) — review, 2026-09-23, V4-5, third pass, V3-1, V3-2, fourth pass, V4-1, second pass, V-B-1, V-B-2
query_kit_flutter/lib/src/read_set.dart:179 (bool _marked = false;) — fourth pass, V4-1
query_kit_flutter/lib/src/read_set.dart:185 (Constraints? _builtWith;) — fourth pass, V4-1
query_kit_flutter/lib/src/read_set.dart:197 (void beginBuild(int generation, Element reader) {) — fourth pass, V4-1
query_kit_flutter/lib/src/read_set.dart:313 (QueryResult<TData> readQuery<TQueryData, TData>() — ADR-0001
query_kit_flutter/lib/src/read_set.dart:511 (static Object? _byVariant(Object? option) =>) — fifth pass, V5-3
query_kit_flutter/lib/src/repeat_read.dart:8 (void debugCheckRepeatRead() — review, 2026-09-09```
