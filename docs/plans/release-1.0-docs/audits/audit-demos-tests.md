# Audit: live demos, tests and coverage, naming and AI disclosure (2026-09-23)

Branch `release/1.0-docs` at `491ed27`. Nothing in the repository was edited.
One side effect was undone: the first `flutter build web` (without `--no-pub`)
ran `flutter pub get`, which rewrote the root `pubspec.lock`. It was restored
with `git checkout -- pubspec.lock` (see finding A-9). Build output and coverage
are all in the scratchpad (`web-js/`, `web-wasm/`, `tm-web/`, `cov/`). No
`coverage/` directory was created inside the repo: `dart test --coverage=<scratch>` and
`flutter test --coverage-path=<scratch>` both wrote straight to the scratchpad.
The packages' `.gitignore` does **not** ignore `coverage/`; only the two examples'
`.gitignore` files do.

---

## A. Interactive browser demos

### A-1. How the showcase picks its backend today

- `lib/main.dart`: `runApp(ShowcaseApp(api: ShowcaseApi(scenario: scenarioFromEnvironment())))`.
  `ShowcaseApp` already takes `api`, `client` and `initialRoute` as injected
  values. The widget tests use exactly this seam.
- `lib/shared/api.dart`: `ShowcaseApi({Dio? dio, String? baseUrl, scenario})`. With
  no `dio`, it builds one on `defaultBackendBaseUrl()`, which is
  `--dart-define=BACKEND`, else `10.0.2.2:5175` on Android, else
  `http://localhost:5175/api`. Every request carries `x-scenario`.
  `scenarioFromEnvironment()` reads `Uri.base.queryParameters['scenario']`,
  then `--dart-define=SCENARIO`.
- `lib/shared/scope.dart`: `ShowcaseScope` is an `InheritedWidget` that hands
  down `api` and `stats`. It has no knowledge of the backend.
- `test/harness.dart`: `Dio(BaseOptions(baseUrl: 'http://backend.test/api'))..httpClientAdapter = FakeBackend()`.
  So the whole app already runs against an in-memory `HttpClientAdapter`, and
  **the demo-mode switch is one `if` in `main()`**.

### A-2. Can `test/fake_backend.dart` run in the browser? Yes, with two small changes

| Dependency | Web-safe? | What to do |
|---|---|---|
| `package:flutter_test` | not imported by the fake (only by `harness.dart`) | nothing |
| `dart:io` | imported for **one** use: `File('server/seed.json')` in `FakeBackend.seed()` | move seed loading out. The lib backend takes `seed` as a parameter. The app loads `server/seed.json` as a Flutter asset (`rootBundle.loadString` in an async `main`), and the test helper keeps `File` |
| `package:clock` | web-safe, but a **dev_dependency** of the showcase | move it to `dependencies`. It is an example app, so #1's no-third-party rule for the published packages does not apply. `clock.now()` must stay because the widget tests' virtual time depends on it |
| `Timer` in `_wait` (latency, `?delay`) | web-safe | nothing. The fake owns its timers and `close()` cancels them |
| `dart:math` `Random(1)` for `errorRate` | web-safe | nothing |
| `dio` `HttpClientAdapter`, `ResponseBody.fromString` | platform-agnostic; setting `httpClientAdapter` replaces dio's browser adapter | nothing |
| scenario isolation | the fake keeps one world and ignores `x-scenario`; its four control routes (`reset`, `config`, `requests`) are implemented | this is fine in a browser: each iframe is its own app, with its own world |

The screens that call control routes (`retry`, `playground`, and
`invalidation-and-filters` through `configureScenario`) keep working because the
fake implements them.

The task manager's fake (`examples/task_manager/test/fake_backend.dart`)
imports only `dart:async`, `dart:convert` and `dio`, so it can move as is. It
seeds three tasks where the server seeds five. That difference is deliberate and
documented in the file, and it is harmless for a demo.

**Latency.** The fake defaults to zero, so no loading state would ever show.
The server's defaults are 300 ms for the showcase (`server/config.ts`
`DEFAULT_LATENCY`) and 900/350/700 ms for list/detail/write in the task manager.
Demo mode should construct the backend with those same values.

### A-3. The proposed demo-mode flag

`--dart-define=QK_BACKEND=inmemory` (a `const String.fromEnvironment`), so a
normal build tree-shakes the in-memory backend away. Files:

- **Move** `examples/showcase/test/fake_backend.dart` to
  `examples/showcase/lib/demo/in_memory_backend.dart`. Its public class becomes
  `InMemoryBackend({required Map<String, Object?> seed, Duration latency})`.
  Keep a thin `test/fake_backend.dart` that re-exports it and adds
  `static seed()` from `File`, so `harness.dart`,
  `backend_contract_test.dart` and every feature test stay untouched. The
  contract test then proves the *shipped* demo backend against the real
  server, not just a test double. That is an extra benefit of the move.
- `examples/showcase/pubspec.yaml`: move `clock` to `dependencies`, and add
  `assets: [server/seed.json]` (20 KB).
- `examples/showcase/lib/main.dart`:
  ```dart
  const _backend = String.fromEnvironment('QK_BACKEND'); // '' | 'inmemory'
  final embed = Uri.base.queryParameters['embed'] == '1';
  Future<void> main() async {
    WidgetsFlutterBinding.ensureInitialized();
    if (_e2e || Uri.base.queryParameters['semantics'] == '1') SemanticsBinding.instance.ensureSemantics();
    final api = _backend == 'inmemory'
        ? ShowcaseApi(dio: Dio(BaseOptions(baseUrl: 'http://demo.invalid/api'))
            ..httpClientAdapter = InMemoryBackend(seed: jsonDecode(await rootBundle.loadString('server/seed.json')), latency: const Duration(milliseconds: 300)),
            scenario: 'demo')
        : ShowcaseApi(scenario: scenarioFromEnvironment());
    runApp(ShowcaseApp(api: api, embed: embed));
  }
  ```
- `ShowcaseApp`/`ShowcaseScope`: add `bool embed` (or an `AppMode` value) to the
  scope so `FeatureScaffold` can read it.
- `lib/shared/feature_scaffold.dart`: in embed mode, use no back button
  (`automaticallyImplyLeading: false`), replace `scenario <id>` with a small
  "in-memory backend" pill, and keep the title and summary. Keep this minimal:
  a compact app bar is better than none because it names the feature inside
  the iframe.
- `lib/routes.dart` and `main.dart`: in embed mode, pass `onGenerateInitialRoutes` so
  that only the feature route is pushed. Flutter's default initial-route
  expansion pushes `/` under `/optimistic-updates`, which would let a user
  "back" out of the embedded demo into the catalogue. An unknown id in embed mode
  should render a short "unknown demo" notice rather than the catalogue.
- `lib/home_screen.dart`, `lib/main.dart`, `web/index.html`: the app's title is
  **"TanStack Query Showcase"**. That is TanStack's mark on an unaffiliated demo
  (see C). It should become "query_kit showcase". The title is asserted
  in 17 widget tests and 1 Playwright spec (`parallel_queries.spec.ts:122`).
- The same changes, smaller, apply to `examples/task_manager`: move the fake to
  `lib/demo/`, add the `QK_BACKEND` switch in `main()`, and add `?embed=1`. The
  task manager has no routes (it uses `home: _Home(...)`), so it embeds as one
  whole app, which is what an "acceptance demo" should be anyway.

### A-4. Deep links

The showcase already supports them. It uses the hash URL strategy, and
`initialRoute` is overridden by the URL hash on the web (`main.dart` doc). The
e2e suite opens every feature as `/?scenario=<id>#/<route>`
(`e2e/tests/fixtures.ts`). The query string sits **before** the hash, so it
survives navigation. An embed URL is therefore:

```
/flutter_query/demo/showcase/?embed=1#/optimistic-updates
```

Feature ids are single segments on purpose (`Feature.id` doc: nested paths
fall back to `/`). Route ids use dashes and directories use underscores
(`/optimistic-updates` → `lib/features/optimistic_updates/`), so "view source"
can be derived as `id.replaceAll('-', '_')`.

### A-5. Build size (measured, Flutter 3.38.8, macOS)

| Build | On disk | Main program | gzip -9 | brotli |
|---|---|---|---|---|
| showcase, `flutter build web --release` (JS) | 30 MB | `main.dart.js` 2.94 MB | 856 KB | 665 KB |
| showcase, `--wasm` | 33 MB | `main.dart.wasm` 2.60 MB (+ `main.dart.mjs` 31 KB, and the JS fallback `main.dart.js` 2.94 MB) | 968 KB | 756 KB |
| task_manager, JS | 30 MB | `main.dart.js` 2.60 MB | 761 KB | – |

Of the 30 MB, 26 MB is `canvaskit/`, which holds every renderer variant plus
4.3 MB of `*.symbols` files that are never downloaded. The build bundles it,
but by default the bootstrap loads CanvasKit from
`https://www.gstatic.com/flutter-canvaskit/<engineRevision>`
(`flutter_bootstrap.js` has `engineRevision` set and no `useLocalCanvasKit`).
`assets/NOTICES` is 1.3 MB but is fetched only by the licence page. The
Material icon font is tree-shaken from 1.6 MB to 9 KB.

**First load over the wire (Chromium, JS build):** about 0.86 MB of
`main.dart.js` + about 2.2 MB of `canvaskit/chromium/canvaskit.wasm`
(gzip) + the Roboto fallback font from fonts.gstatic.com, so **about 3.1 MB
compressed**. Other browsers take `canvaskit.wasm` at 2.85 MB gzip. Because both
iframes use the same URLs, a second iframe on the same page is served from the
cache. The size is why click-to-load is mandatory.

For deployment, use `--no-web-resources-cdn`, as the e2e build already does. It
adds no third-party request, pins the engine to the build, and makes Playwright
offline-deterministic. After the build, delete `canvaskit/**/*.symbols` and
the `skwasm*` files (unused by a JS build). The result is about 14 MB per app on
disk, well within GitHub Pages' limits (1 GB site, 100 MB per file). Both apps
could share one CanvasKit through `canvasKitBaseUrl` in a custom
`flutter_bootstrap.js`, but at this size that is an optimisation for later.

### A-6. `--wasm`

The build succeeds (`Wasm dry run succeeded` in the JS build too), and the
`--base-href` was honoured (`<base href="/flutter_query/demo/showcase/">`).
Caveat: GitHub Pages cannot send COOP/COEP headers, so the page is not
`crossOriginIsolated` and skwasm runs single-threaded. Browsers without WasmGC
fall back to the bundled `main.dart.js`. **Recommendation:** ship JS first,
with one code path, the one Playwright tests. `--wasm` is a later one-flag
experiment. The wasm program is larger here (968 KB gzip compared with 856 KB),
so size is not a reason to switch.

### A-7. Base href

The site is `url: https://kotti97.github.io`, `baseUrl: '/flutter_query/'`
(`website/docusaurus.config.ts`). Files under `website/static/demo/showcase/`
are served at `/flutter_query/demo/showcase/`, so:

```
flutter build web --release --no-pub --no-web-resources-cdn --pwa-strategy=none \
  --dart-define=QK_BACKEND=inmemory --base-href /flutter_query/demo/showcase/ \
  -o ../../website/static/demo/showcase
```

`--pwa-strategy=none` matters. A service worker registered under the docs origin
would cache the demo and serve a stale one after a deploy. The base href has to
change with `baseUrl` when the repo is renamed, so derive it from one variable
in the build script rather than hard-coding it twice.

### A-8. Proposed design

**Files to add or change**

| Path | What |
|---|---|
| `examples/showcase/lib/demo/in_memory_backend.dart` | moved fake (A-3) |
| `examples/showcase/test/fake_backend.dart` | thin re-export plus `File` seed |
| `examples/showcase/lib/main.dart`, `lib/shared/scope.dart`, `lib/shared/feature_scaffold.dart`, `lib/routes.dart` | `QK_BACKEND`, `?embed=1`, `?semantics=1`, the initial-routes rule |
| `examples/showcase/pubspec.yaml` | `clock` to dependencies, `server/seed.json` asset |
| `examples/task_manager/lib/demo/in_memory_backend.dart` and `lib/main.dart` | same, smaller |
| `examples/showcase/test/demo_mode_test.dart` | a widget test that boots `main`'s demo branch on `/optimistic-updates?embed=1`: no back button, the pill shown, data arrives |
| `tool/build_demos.sh` (or `.mjs`) | builds both apps into `website/static/demo/{showcase,task-manager}`, prunes `*.symbols` and `skwasm*`, and takes `BASE_URL` from one place |
| `.gitignore` | `/website/static/demo/` (D5: "never committed") |
| `website/src/components/LiveDemo/index.tsx` and `styles.module.css` | the component |
| `website/src/theme/MDXComponents.tsx` | registers `LiveDemo` globally, so a doc can use it without an import (the docs are `.md`, parsed as MDX by default in Docusaurus 3) |
| `website/docs/examples/*.md` | one page per demo (D4), each with `<LiveDemo feature="optimistic-updates" />` |
| `website/e2e/` (Playwright) | see below |

**`<LiveDemo>`** (`feature`, `app='showcase'`, `height=640`, `title?`):

- Before the click, it shows a static placeholder the size of the frame: a
  title, a one-line summary, "Run live demo (about 3 MB)", "Open full screen ↗",
  and "View source on GitHub ↗". No iframe exists yet, so no bytes are spent. An
  optional `poster` screenshot can be added later.
- After the click, it renders `<iframe src={useBaseUrl(`/demo/${app}/?embed=1#/${feature}`)} loading="lazy" title=… allow="clipboard-write" />`
  with a spinner overlay until `load` fires. Flutter paints only after its own
  boot, so this spinner covers the blank iframe.
- "Open full screen" links to the same URL without `embed=1` in a new tab, so a
  user can explore the whole catalogue.
- "View source" links to
  `https://github.com/KoTTi97/flutter_query/tree/main/examples/showcase/lib/features/${feature.replaceAll('-', '_')}`.
  The GitHub coordinates should come from `siteConfig.customFields` so the
  rename is one edit.
- When JavaScript is disabled or the static build is missing (`npm start`
  without demos), the placeholder stays and its note says how to build the
  demos.
- Accessibility: the button is a real `<button>`, and the iframe gets a
  `title`. Flutter's semantics tree is only built when enabled, so the embed URL
  should add `semantics=1`. That makes the demo screen-reader-usable and
  Playwright-readable at a small cost.

**CI (`.github/workflows/ci.yml`)**

- The `website` job gains a Flutter step: `subosito/flutter-action` (3.38.8),
  `flutter pub get`, `tool/build_demos.sh`, **then** `npm run build`. The demos
  land in `static/` before Docusaurus copies it, so `npm start` serves them
  locally too. The job's uploaded `website` artifact then contains the demos.
- The existing `gates` steps "demo web build" and "showcase web build" can switch to
  the demo-mode flags, or stay. A normal build still proves the real-backend
  configuration compiles.
- A new job, `website-e2e`, needs `website`: it downloads the artifact, serves
  `build/` under `/flutter_query/` (a static server with a prefix, or
  `npx docusaurus serve --dir build`), and runs Playwright.
- A `pages.yml` deploy workflow (`actions/upload-pages-artifact` +
  `actions/deploy-pages`, on `push: main`) may be *prepared*. Switching Pages
  on is the maintainer's call (plan D7).

**Playwright for embedded demos.** This follows the existing e2e conventions:
`examples/showcase/e2e` reads Flutter's semantics tree (`flt-semantics` nodes)
through `getByRole('group', { name })` and `getByText(exact)`, built with
`--dart-define=E2E=true` so that semantics are on from frame one.

- The iframe is same-origin, so use `page.frameLocator('iframe[title="…"]')` and
  then the same `group(frame, 'debug todos')` or `factIn` helpers. Import or
  copy `fixtures.ts`'s locator helpers and let them accept a `FrameLocator`.
- The embed URL carries `semantics=1`, so no special build is needed. Test
  exactly what ships.
- What *cannot* carry over: `Scenario` (there is no backend to query) and
  `holdRequest`/`page.route`. With no HTTP, requests never leave the page.
  Embedded-demo specs therefore assert only on what the screen publishes (its
  facts and debug strips), which is the showcase's rule anyway.
- Scope: one smoke spec per embedded demo. Load the doc page, click "Run live
  demo", wait for the feature's first fact (for example `status=success`), and
  perform one interaction (the optimistic add shows the row before
  `isPending` clears). Also check "Open full screen" (a new page at
  `?embed` absent, where the catalogue is reachable) and "View source" (an
  `href` equal to the expected GitHub path). One further test enumerates every
  `<LiveDemo feature>` in `website/docs/**` and asserts that each id is a
  showcase route. Alternatively, `catalogue_test.dart` can grow a sixth set,
  "embedded in the site". Either way, a renamed feature cannot silently break a
  doc page.
- The demo backend has latency and uses no clock-sensitive assertions, so the
  specs follow the "nothing asserts on a clock" rule.

### A-9. Findings on the way

1. **The root `pubspec.lock` is stale for the pinned SDK.** Any
   `flutter pub get` on Flutter 3.38.8 (which CI runs first) rewrites it:
   `characters` 1.4.1→1.4.0, `matcher` hash, and `js` 0.7.2 added. So a local
   `flutter build web` or `flutter test` without `--no-pub` dirties the
   tree. It was reverted here. Worth regenerating and committing with the
   pinned Flutter.
2. `examples/task_manager/sensor_demo.iml` and
   `ios/Flutter/Generated.xcconfig`/`flutter_export_environment.sh` still
   say `sensor_demo` with absolute paths. They are gitignored and untracked, so
   they are local leftovers only.
3. "TanStack Query Showcase" is the showcase's app title, window title
   (`web/index.html`), home-screen title, and appears in 18 test assertions.
   Rename it before the demos are public (see C).

---

## B. Tests

### B-1. Line coverage

Core: `dart test --coverage` into the scratchpad, then `format_coverage --lcov --report-on=lib`.
Binding: `flutter test --coverage --coverage-path=<scratch>`. Artefacts are in
`scratchpad/cov/` (`core.lcov`, `binding.lcov`, `*-report.txt`,
`core-uncovered.txt` with source context). The core figure counts only the
core's own tests. Code reached only through the binding's tests (for example
`QueriesObserver.getOptimisticResult`, which `QueriesController` calls) is
counted as uncovered.

**query_kit: 3159 / 3511 lines = 89.97 %** (826 tests, all passed)

| % | lines | file |
|---|---|---|
| 39.3 | 24/61 | query_state.dart |
| 52.3 | 23/44 | mutation_options.dart |
| 64.0 | 126/197 | option_values.dart |
| 76.2 | 16/21 | cancel_token.dart |
| 76.5 | 39/51 | mutation_result.dart |
| 84.5 | 49/58 | query_result.dart |
| 84.7 | 265/313 | infinite_query.dart |
| 84.9 | 338/398 | query_client.dart |
| 87.6 | 247/282 | query_options.dart |
| 89.9 | 116/129 | combined_result.dart |
| 94.0 | 78/83 | queries_observer.dart |
| 94.6 | 35/37 | focus_manager.dart |
| 95.1 | 97/102 | structural_sharing.dart |
| 97.3 | 291/299 | query.dart |
| 97.4 | 113/116 | retryer.dart |
| 97.4 | 229/235 | mutation.dart |
| 97.5 | 158/162 | mutation_observer.dart |
| 98.0 | 48/49 | filters.dart |
| 98.0 | 97/99 | query_key.dart |
| 98.8 | 81/82 | query_cache.dart |
| 99.1 | 338/341 | query_observer.dart |
| 99.1 | 116/117 | mutation_cache.dart |
| 100 | – | hashing, infinite_query_observer, listener_registry, mutation_state_observer, notify_manager, online_manager, removable, subscribable, timers |

**query_kit_flutter: 837 / 859 lines = 97.44 %** (287 tests, all passed)

| % | lines | file |
|---|---|---|
| 92.9 | 117/126 | query_controller.dart |
| 95.3 | 41/43 | query_listener.dart |
| 96.3 | 183/190 | query_client_provider.dart |
| 97.4 | 111/114 | read_set.dart |
| 97.6 | 40/41 | queries_builder.dart |
| 100 | – | controller_lifetime, is_fetching_controller, mutation_state_controller, notify_gate, online_status, queries_controller, query_builder, query_context, query_mixin, read_entry, repeat_read |

The low percentages are mostly `==`/`hashCode`/`toString` on value classes. The
list below is what is **behaviour**, grouped by weight.

**Core: uncovered public-API behaviour worth a test**

1. **`QueryDefaults ==`/`hashCode`, `MutationDefaults ==`/`hashCode`,
   `DefaultOptions ==`/`hashCode`** (`query_client.dart` 146–182, 244–264,
   282–290). The code comment claims that "a `setQueryDefaults` with an equal
   value must not read as a change", but nothing exercises the equality it
   relies on. A missing field in `==` (the nine-places rule in CLAUDE.md) would
   go unnoticed.
2. **`QueryState ==`/`hashCode`/`toString`** (`query_state.dart` 231–271), and
   `isFetched` (168). `QueryState` is public, and `isFetched` is a public getter
   with zero hits. Value equality over 14 fields is untested, so a field added
   later but forgotten in `==` is invisible.
3. **`InfiniteQuerySelectOptions.copyWith`** (`infinite_query.dart` 771–805):
   the entire method, including its `_rejectQueryFn` and `_rejectPages` guards.
   `QuerySelectOptions.copyWith` (`query_options.dart` 895) is likewise never
   called, and `QueryOptions.copyWith` misses `retry` (504). The CLAUDE.md
   "nine places" hazard is precisely a field lost in `copyWith`. LIB-3's test
   covers `withSelect`, not these.
4. **Options `hashCode`**: `QueryOptions` (1043–1058), the observer options
   (1208–1218), `MutationOptions` (430–444), `PlaceholderData.*` (337–388),
   `MutationScope ==`/`hashCode` (52–59), and `InfiniteData.hashCode` (125–128).
   `==` is covered but `hashCode` is not, so the `==`/`hashCode` contract (equal
   implies same hash) is untested. That contract matters wherever options or
   data land in a `Set` or `Map`, or in `Object.hash` of a parent.
5. **Sealed option values `hashCode`** for every variant of `StaleTime`, `GcTime`,
   `Enabled`, `RetryPolicy`, `RetryDelay`, `RefetchOn` and `RefetchInterval`
   (`option_values.dart`), plus **`StaleTime.resolve(query)`** (63–64), a
   public method that is never called.
6. **`CancelToken.whenCancelled`** (54) and **`throwIfCancelled()`** (74–75).
   These are public cancellation APIs a `queryFn` author is told to use, and
   neither is ever called.
7. **Error paths never taken**:
   - `QueriesObserver.setQueries` throwing
     `ArgumentError('requires select when data types differ')` (`queries_observer.dart` 125).
   - `AppFocusManager(refetchMinBackgroundDuration: negative)` throwing (`focus_manager.dart` 38).
     Its `onFocus()` path is also never taken (105).
   - `MutationCache.add` of a removed mutation, a `StateError` (`mutation_cache.dart` 231).
   - `QueryClient._resumeThen` catching a throw from `resumePausedMutations`
     into the zone (`query_client.dart` 400).
   - `defaultMutationOptions` with both functions (1233). This is reachable only
     in release builds, because a debug assert fires first. It needs a
     `--no-enable-asserts` run to cover.
   - `QueryDataTypeError.toString` for a default with no key (`query_cache.dart` 132).
   - The "no queryFn" and "no mutationFn" error texts (`query.dart` 1244–1246,
     `mutation.dart` 1030–1032). Their messages are user-facing and asserted
     nowhere.
8. **Race branches in the retryer**: `_isRetryCancelled` becoming true after the
   policy ran (354, 365), and `_isRetryCancelledImmediately` after `onFail`
   (376). These are cancel-during-retry-decision windows.
9. `Query.fetch` superseded while removed or without an operation (859–860),
   the `QuerySuccessAction || QuerySetStateAction` reducer arm (1203),
   `QueryObserver` with a custom `structuralSharing` function on a *select*
   result (674), an error status with a null error (717), `QueryKey` containing
   a `Set` (`query_key.dart` 246–247: a set's description is sorted, and that
   ordering feeds the key's hash, so set-valued keys are untested), and
   `hashDeep` on `TypedData` and `InfiniteData` (`structural_sharing.dart`
   409–419).
10. `Mutation.meta` (487) and `MutationObserver.options` (82–83) are public
    getters with no hits. `CombinedResult.hasData` (58) and
    `InfiniteData.isEmpty` (71) are the same.

**Binding: uncovered public-API behaviour**

- `QueryController.refetch()` (178–179). The mutation and infinite variants are
  covered.
- `InfiniteQueryController.hasPreviousPage`, `isFetchNextPageError`,
  `isFetchPreviousPageError`, `isRefetching`, `isRefetchError` (308–334). All
  are public getters with zero hits in the binding. They are one-line
  delegates, but they are exactly the fields a direct controller user reads.
- `MutationController.reset()` (460).
- `QueryListener` reporting a throwing listener to `FlutterError` (121–126).
- `QueryClientProvider`:
  - The `_missingProvider()` throw on the non-dependent lookup path (163).
  - An `onlineStatus` stream error reported through `FlutterError` (344–345).
  - The `isAppShown` default on windows and linux (481–482). Tests run on the
    host platform, so only the macOS branch runs here.
  - Re-observing app lifecycle when the client changes with
    `observeAppLifecycle` (610).
  - A `dispose` after release (661).
- `QueriesBuilder` disposing its controller when the client changes (126).
- `read_set.dart`: a `RenderSliver`'s constraints as the layout-builder
  signal (266) and the `StateError` fallback (269). This is the V4 rule's
  sliver arm. Also the infinite repeat-read `before` value (364).

### B-2. Test inventory (counted by running, 2026-09-23)

| Suite | Count | Runs where |
|---|---|---|
| core `packages/query_kit` | **826** pass (VM); CLAUDE.md says 822 compiled to JS | `gates`, `floors`; `--platform chrome` in `gates` |
| binding `packages/query_kit_flutter` | **287** pass | `gates`, `floors` (VM only) |
| showcase widget `examples/showcase/test` | **247** pass, 25 skipped (the contract cases against the real server, which need `SHOWCASE_SERVER`) | `gates`, `floors`; contract vs real in `e2e` |
| showcase e2e `examples/showcase/e2e/tests` | **177** `test(` in 30 specs | `e2e` matrix |
| task_manager widget | **32** pass, 14 skipped (real-server contract cases) | `gates`, `floors`; contract vs real in `e2e` |
| task_manager e2e | **10** | `e2e` matrix |
| doc_snippets | **9** pass | `gates`, `floors` |

### B-3. What is missing

1. **No `integration_test` anywhere.** No package or example depends on it. The
   only "whole stack in a real app" evidence is Playwright against a web build.
   Nothing runs the binding on a real Flutter engine on a device or desktop
   target (iOS/Android/macOS): app lifecycle, real `Timer`s, platform
   `isAppShown` defaults. The cheapest option, once the in-memory backend is in
   `lib/`, is `examples/showcase/integration_test/` driving 3–5 features with
   `flutter test integration_test -d macos` (or `-d chrome`) against
   `QK_BACKEND=inmemory`. It needs no server, so it fits CI on a macOS runner.
2. **The binding never runs compiled to the web.** The core runs
   `--platform chrome` because "two reviews found bugs only a JavaScript
   runtime shows", but the binding has no `flutter test --platform chrome`
   leg. Only the examples' Playwright suites touch the binding on JS, and not
   on wasm at all.
3. **No leak testing.** The binding is all about the release of listeners and
   observers (V3/V4 passes), yet nothing uses `leak_tracker`
   (`LeakTesting.settings.withTrackedAll()` in `flutter_test_config.dart`), which
   `flutter_test` ships.
4. **No value-object contract tests.** Items 1–5 of B-1 are one missing family:
   a table test per public value class (`==` ⇔ `hashCode`, `copyWith`
   round-trips every field, `toString` includes every field). This family
   would also mechanically guard the "an option field costs nine places" rule
   in CLAUDE.md.
5. **No property-based or fuzz tests** for `QueryKey` hashing and partial
   matching, or for `replaceEqualDeep`/structural sharing (maps, sets,
   `TypedData`, `InfiniteData`, sealed lists). These are the areas where review
   rounds found hashing defects.
6. **No performance or scale tests**: 1k queries in the cache, 100 observers on
   one key, `QueriesBuilder` over a long list, rebuild counts at scale. The
   showcase counts rebuilds per screen, but nothing guards a regression in
   complexity.
7. **No release-mode (`--no-enable-asserts`) run.** At least one documented
   branch (`defaultMutationOptions` REL-12) exists only for release builds.
8. **No golden tests.** That is fine: the showcase's semantics-tree assertions
   are the project's stated alternative. Nothing is missing here unless visual
   regressions become a concern for the embedded demos.
9. **No coverage gate in CI**, and neither package ignores `coverage/`. If
   coverage is added, add `coverage/` to the root `.gitignore`.

---

## C. Naming and AI disclosure

### C-1. Old names

The grep excluded `query/`, `reference-projects/`, `node_modules`, `build`,
`.dart_tool`, `.git` and `.docusaurus`. It covered `flutter_query`,
`Flutter Query`, `flutter-query`, `query_core`, `flutter-port`,
`tanstack_query`, `sensor_demo` and "TanStack Query Showcase". It found 369
matches in about 140 files.

**(1) Repo URL. Keep until the repo is renamed; GitHub redirects afterwards.**
Almost all matches in code are `https://github.com/KoTTi97/flutter_query/issues/NN`
in dartdoc: about 60 across `packages/*/lib/src/*.dart` and the library files,
and they ship to pub.dev. Others:

- `packages/*/pubspec.yaml` (`repository`, `issue_tracker`)
- the READMEs' issue and blob links
- `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md:39`,
  `.github/ISSUE_TEMPLATE/{config,bug_report}.yml`
- `scripts/release.sh:190` (`REPO=`)
- `website/docusaurus.config.ts` 86, 118, and `editUrl`
- `website/src/pages/index.tsx:180`
- the docs pages' links
- test files and the showcase and task_manager `lib/` issue references

Two items tied to the repo name that are not plain URLs:

- `website/docusaurus.config.ts:14,16`: `baseUrl: '/flutter_query/'` and
  `projectName: 'flutter_query'`. **Line 74** hard-codes
  `/flutter_query/docs/project/credits` inside the announcement bar HTML, where
  `baseUrl` does not reach. It will break silently on a rename. Build it from a
  constant.
- `website/README.md:10,105` (the local URL and the Pages URL), and
  `website/docs/getting-started/installation.md:63,67`
  (`path: ../flutter_query/packages/...`, the checkout directory name).
- `CLAUDE.md:316,321` (`--repo KoTTi97/flutter_query`). This is correct as long
  as the repo keeps its name.

**(2) Prose names that should become query_kit**

- `README.md:1`: `# flutter_query`. This is the repo's front page heading.
- `CLAUDE.md:1`: `# flutter_query — working notes for agents`.
- **"TanStack Query Showcase"** (not the old name, but a naming defect worse than
  one): `examples/showcase/lib/main.dart:99`, `lib/home_screen.dart:17`,
  `web/index.html:26,32`; asserted in 17 widget tests
  (`test/features/*_test.dart`) and `e2e/tests/parallel_queries.spec.ts:122`.
  It should become "query_kit showcase". The affiliation research
  (`docs/research/package-naming-and-affiliation.md`) argues against using
  TanStack's name as a product title.
- `examples/task_manager/sensor_demo.iml` and `ios/Flutter/Generated.xcconfig`:
  the old app name, but untracked and ignored. They are local only, so there is
  nothing to change in git.

**(3) Historical record. Leave as is.**

- `packages/query_kit/test/PORTING_NOTES.md` (91 matches)
- `docs/research/*` (about 110)
- `docs/decisions/binding-api-shape.md`
- `docs/adr/000{1,2}` (ticket URLs)
- `CLAUDE.md:368–375` (`query_core`, `flutter-port/` as history)
- `examples/task_manager/test/acceptance_test.dart:6` (`git show 69c71d4:flutter-port/DESIGN.md`)
- `tool/rename_packages.dart:12`
- `docs/plans/release-1.0-docs/README.md:22`

### C-2. AI authorship: what exists today

There is already a strong disclosure. None of it names the model or vendor,
and the plan's D2 wording ("Anthropic's Claude") is not used anywhere yet. The
only file mentioning Claude or Anthropic is the untracked
`docs/plans/release-1.0-docs/README.md`. 68 of 79 commits carry
`Co-Authored-By: Claude`.

| Place | Today |
|---|---|
| root `README.md` | yes. Lines 38–48: "this is an AI-written project … written by AI agents", and it names CLAUDE.md. It sits below the fold, after the affiliation paragraph |
| `packages/query_kit/README.md` | yes. Lines 27–31, a blockquote near the top (pub.dev landing) |
| `packages/query_kit_flutter/README.md` | yes. Lines 28–32, same |
| `packages/*/pubspec.yaml` `description` | **no**. It carries the affiliation disclaimer only (169 and 167 chars; pub.dev's limit is 180) |
| `packages/*/CHANGELOG.md` 1.0.0 | **no** |
| `website/src/pages/index.tsx` | yes. Line 101 tagline "written by AI" and lines 186–190 "AI-written project" |
| `website/docs/intro.md` | yes. Lines 28–30 in the `:::danger Read this first` box |
| site-wide announcement bar | yes. `docusaurus.config.ts:74`, not closeable: "… and <b>written by AI</b>" |
| footer copyright | yes. `docusaurus.config.ts:124`: "Written by AI." |
| `website/docs/project/credits.md` | yes. The "It was written by AI" section (61–80) with a `:::warning` |
| `CONTRIBUTING.md` | yes. Line 10: "this repository was written by AI agents" |
| library dartdoc (`lib/query_kit.dart`, `lib/query_kit_flutter.dart`; pub.dev API landing) | **no**. The affiliation line only |
| `packages/query_kit_flutter/example` (pub.dev "Example" tab), `packages/query_kit/example/example.dart` | **no** |
| `examples/showcase/README.md`, `examples/task_manager/README.md` | **no** |
| `SECURITY.md` | **no**. This matters: a security reporter should know that no human wrote the code |
| the in-app demo (once embedded) | **no**. Suggest the embed pill or placeholder carry "AI-coded" |

### C-3. Where the disclosure must appear for release, with the gap to close

1. Root README: move the disclosure **to the top**, next to the affiliation
   note, and use the D2 wording (name Claude).
2. Both package READMEs: already at the top. Align the wording with D2. The
   current text says "a human in the loop only rarely", while D2 says "reviews
   releases". Pick one; they must not contradict.
3. **Both pubspec descriptions: add it.** Short forms that fit under 180:
   - "Dart port of TanStack Query's query-core: caching, refetching, staleness
     and mutations, no Flutter needed. AI-coded community port, not affiliated
     with TanStack." (161)
   - "Flutter binding for query_kit: provider, controllers, builders, State
     mixin, context.query. AI-coded community port, not affiliated with
     TanStack." (146)
4. **Both CHANGELOGs' 1.0.0 entry: add one sentence.**
5. Site landing page: present already. Update it to the D2 wording.
6. Site intro: present already. Update the wording.
7. Announcement bar: present already. Fix the hard-coded `/flutter_query/` link
   (C-1).
8. CONTRIBUTING.md: present already. Update the wording.
9. **Both library-level dartdocs: add one paragraph** after the affiliation
   line. This is the first thing a pub.dev API-docs reader sees.
10. **Examples' READMEs** (showcase, task_manager, the binding's shipped
    example): add a line, as D2 lists "the examples' READMEs".
11. **`SECURITY.md`: add a line.**
12. The live-demo placeholder/pill: one phrase.

One wording risk: several places say "nine **external** deep-dive reviews".
Per CLAUDE.md and memory, those reviews were also run by agents. "External"
can read as human third-party review, so it should say "independent
agent-run reviews" or similar. The occurrences are `README.md:46`, both package READMEs (lines 30–31),
`index.tsx:190`, `fidelity.md:64` and `credits.md:86`.
