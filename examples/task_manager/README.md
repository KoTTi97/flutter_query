# task_manager

A to-do app on `query_kit_flutter`, against the deliberately slow express
backend in [`server/`](server): optimistic writes, rollback, a poll that stops
when the server confirms, and one cache entry read by two screens.

> **The small app, not the catalogue.** [`examples/showcase/`](../showcase) has
> one screen per feature — 27 of them — and is where to look up how a
> particular thing is done. This is the other kind of example: *one ordinary
> app* that happens to need six of those features at once, so you can see how
> they compose. It was also the port's acceptance bar — the checklist below is
> what had to work before the port was called done.

## Running it

Start the backend (port 5174). It runs its TypeScript straight through Node's
type stripping, so it needs **Node 23.6 or later** (`.nvmrc` says 24, which is
what CI uses):

```bash
cd server && npm install && npm run dev
```

Then run the app. **iOS and web are generated** — for macOS or Android, run
`flutter create --platforms=macos,android .` first.

```bash
flutter run -d chrome                # web
flutter run                          # iOS: pick the simulator when asked
```

On the **web** the app talks to the backend across origins, which works because
the backend answers with `Access-Control-Allow-Origin: *` and allows the
`x-demo-client` header the client sends. A Flutter web build has no dev-server
proxy to hide behind, so it goes direct.

On the **simulator**, `localhost` is your Mac, so the default backend URL just
works.

On a **physical iPhone or iPad**, `localhost` is the device itself, so point it
at your Mac's address on the network — and expect iOS to ask once for local
network permission:

```bash
flutter run --dart-define=BACKEND=http://192.168.240.11:5174/api
```

(`ipconfig getifaddr en0` prints that address. An Android emulator needs no flag:
it reaches the host through `10.0.2.2`, which the app picks by itself.)

`ios/Runner/Info.plist` carries an `NSAllowsLocalNetworking` exception, because
the backend is plain HTTP and iOS blocks cleartext by default. It is scoped to
local networking — arbitrary loads stay off.

The backend is deliberately slow (~900 ms a list fetch, ~700 ms a write) and has
scripted failures: renaming a task to **`fail`** is rejected, and **every
second delete** fails. Both rollbacks are demonstrable on demand.

## What to look at

The whole cache policy is [`lib/src/queries.dart`](lib/src/queries.dart) — one
file. It opens with the client-wide defaults, `appDefaultOptions`: no refetch
on focus or reconnect and one retry, because a backend that takes ~900 ms to
answer should not be asked again every time the window regains focus. The shape
the rest sets up:

- the **list** query owns *which* tasks exist; a **per-task** query owns
  *what each one is*, and the list's query function seeds every per-task entry
  as it arrives;
- the overview rows and the detail screen read the **same** per-task query, so
  a rename invalidating one key updates both — no cross-cache patching;
- the header's "x of y synced" is `select` over the *same* cache entry the
  list uses: two widgets, two shapes, one request;
- the reminder switch writes its requested value to a separate field, so the
  confirmation poll cannot stomp it, and stops polling once the scheduler
  confirms.

## The feature checklist

One widget test per row (`test/acceptance_test.dart`), and every row is
something you can do in the running app:

| Try this | What it shows |
|---|---|
| Open a task | Renders instantly — the row and the detail share one cache entry, already populated |
| Rename, then go back to the overview immediately | The row already shows the new name; the wire shows the write plus one `GET /api/tasks/:id` and **no list refetch** |
| Rename to `fail` | The optimistic name reverts and the error is shown (`onMutate` snapshot, `onError` rollback) |
| Toggle the reminder | Flips optimistically, shows "Waiting for the scheduler…", polls until it confirms ~3 s later, then stops — and holds one value throughout |
| Type in the search box | One request per pause, not per keystroke |
| Add a task | Invalidates the list — membership is a list concern |
| Delete a task | The row disappears immediately and is restored with an error banner; deleting again succeeds |
| Open the header badge | Same cache entry, different widget, different shape, zero extra requests |

## The four call styles, one per screen

The binding offers four equal ways to reach a query and recommends none, so this
app uses each where it genuinely fits — and, incidentally, proves they
interoperate:

| | where | why there |
|---|---|---|
| `QueryController` | the overview's list | the toolbar and the body are siblings that both need it |
| `context.query` | each task row | rows read different keys, and this rebuilds only the row whose task changed |
| `QueryMixin` | the detail screen | already stateful for the rename field; the query and both mutations go flat at the top of `build` |
| `QuerySelectBuilder` | the header badge | a leaf widget, so the builder stays visible in the tree |

## Tests

Two layers. The widget tests run the real app against an in-memory backend;
the end-to-end tests run the real *web build* in a real Chromium against the
real express backend.

```bash
flutter test
```

Sixteen widget tests — one per row of the MVP feature checklist, plus two
regressions found by review — running the real app, with its own client
defaults, against [`test/fake_backend.dart`](test/fake_backend.dart) — an
in-memory stand-in for [`server/server.ts`](server/server.ts) wired in as a dio
`HttpClientAdapter`. Only the transport is replaced: the app's own `TaskApi`,
its JSON, its error handling and its cancellation are all exercised. Pointing
the same app at the express backend is then a smoke test rather than a leap of
faith.

### The contract test

"An in-memory stand-in for the server" is a claim, and
[`test/backend_contract_test.dart`](test/backend_contract_test.dart) is what
checks it: fourteen cases, run against the fake, and — with the server running
and `TASK_MANAGER_SERVER` naming it — against the server too.

```bash
cd server && npm ci && npm run dev          # port 5174
```

```bash
TASK_MANAGER_SERVER=http://localhost:5174/api flutter test test/backend_contract_test.dart
```

Without the variable the server leg skips, so a plain `flutter test` still
passes; CI runs both legs in the `e2e` job. It exists because the two had
drifted apart in six places — a 404's wording, a non-boolean `reminder`, an
empty or missing `name`, a new task's server-owned fields, a search's
whitespace, and every write to an id the backend does not have — and every
widget test that touched one of those was asserting fiction
([#54](https://github.com/KoTTi97/flutter_query/issues/54)). Where the two
differ *deliberately* — the seed is three rows here and five on the server, for
reasons the case gives — the case asserts the difference instead of hiding it.

### End-to-end, in the browser

[`e2e/`](e2e/) is a [Playwright](https://playwright.dev) project. It starts the
express backend and a static server for the web build, opens the app in
Chromium and asserts on what a user sees — and on the wire: how many requests a
screen costs, that a refetch keeps the rows, that an optimistic rename shows
before the write returns, that the reminder poll stops once the scheduler
confirms, that a refused delete springs back, that an unreachable backend is
retried exactly once. Playwright can cut the network, which no widget test can.

Nothing in the suite asserts on a stopwatch. To prove that a write shows
*before* the backend answers, the test holds the request at the network layer
(`page.route`) and releases it once it has seen the optimistic patch: the
server has provably not replied, so there is no wall-clock budget to blow. A
timeout instead would be a guess about how fast the browser repaints and
republishes its semantics tree, and a busy machine makes that guess wrong now
and then.

Flutter web paints to a canvas, so the tests read the **semantics tree** — the
same tree a screen reader gets. The build under test switches it on from the
start (`--dart-define=E2E=true`, see `main.dart`); rows are groups named after
their task, buttons carry their tooltips, the switch is a `switch` with
`aria-checked`. Two things worth knowing when adding a test: the semantic
`<input>` of a text field mirrors its text only once the field has focus, so
click before you read or `fill`; and the list builds only the rows in view,
which is why the suite runs with a tall viewport and sweeps its own tasks off
the backend before and after.

```bash
cd e2e && npm ci && npx playwright install chromium   # once
npm run build                                          # flutter build web --dart-define=E2E=true
npm test                                               # or: npx playwright test --ui
```

The backend keeps one in-memory state per process and scripts "every second
delete fails", so the tests run one at a time, create the tasks they act on,
and never depend on the seed data or on each other. CI runs the same suite on
every push (`.github/workflows/ci.yml`, job `e2e`).
