# sensor_demo

The React demo's sensor manager, rebuilt on `query_kit_flutter` — same
gateway, same cache policy, same scripted failures, so the two clients can be
put side by side.

> **The legacy example.** This app was the port's acceptance bar: one screen
> pair, one cache policy, the React demo's behaviours reproduced. It stays as
> it is. The example that shows *every* feature, each with widget tests and
> end-to-end tests, is [`examples/showcase/`](../showcase); start there.

## Running it

Start the gateway the React demo uses (port 5174). It runs its TypeScript
straight through Node's type stripping, so it needs **Node 23.6 or later**
(`.nvmrc` says 24, which is what CI uses):

```bash
cd ../../react-demo/server && npm install && npm run dev
```

Then run the app. **iOS and web are generated** — for macOS or Android, run
`flutter create --platforms=macos,android .` first.

```bash
flutter run -d chrome                # web
flutter run                          # iOS: pick the simulator when asked
```

On the **web** the app talks to the gateway across origins, which works because
the gateway answers with `Access-Control-Allow-Origin: *` and allows the
`x-demo-client` header the client sends. (The React demo avoids the question
entirely by proxying `/api` through Vite; a Flutter web build has no such proxy,
so it goes direct.)

On the **simulator**, `localhost` is your Mac, so the default gateway URL just
works.

On a **physical iPhone or iPad**, `localhost` is the device itself, so point it
at your Mac's address on the network — and expect iOS to ask once for local
network permission:

```bash
flutter run --dart-define=GATEWAY=http://192.168.240.11:5174/api
```

(`ipconfig getifaddr en0` prints that address. An Android emulator needs no flag:
it reaches the host through `10.0.2.2`, which the app picks by itself.)

`ios/Runner/Info.plist` carries an `NSAllowsLocalNetworking` exception, because
the gateway is plain HTTP and iOS blocks cleartext by default. It is scoped to
local networking — arbitrary loads stay off.

The gateway is deliberately slow (~900 ms a list fetch, ~700 ms a write) and has
scripted failures: renaming a sensor to **`fail`** is rejected, and **every
second delete** fails. Both rollbacks are demonstrable on demand.

## What to look at

The whole cache policy is [`lib/src/queries.dart`](lib/src/queries.dart) — one
file, and worth comparing line for line with
`react-demo/react/src/queries.ts`. It opens with the client-wide defaults,
`demoDefaultOptions`, the twin of `main.tsx`'s `defaultOptions`: no refetch on
focus or reconnect and one retry, because the gateway cannot take a request
storm. The shape the rest sets up:

- the **list** query owns *which* sensors exist; a **per-sensor** query owns
  *what each one is*, and the list's query function seeds every per-sensor entry
  as it arrives;
- the overview rows and the detail screen read the **same** per-sensor query, so
  a rename invalidating one key updates both — no cross-cache patching;
- the header's "x von y verbunden" is `select` over the *same* cache entry the
  list uses: two widgets, two shapes, one request;
- the Matter switch writes its requested value to a separate field, so the
  confirmation poll cannot stomp it, and stops polling when the device confirms.

## The four call styles, one per screen

The binding offers four equal ways to reach a query and recommends none, so this
app uses each where it genuinely fits — and, incidentally, proves they
interoperate:

| | where | why there |
|---|---|---|
| `QueryController` | the overview's list | the toolbar and the body are siblings that both need it |
| `context.query` | each sensor row | rows read different keys, and this rebuilds only the row whose sensor changed |
| `QueryMixin` | the detail screen | already stateful for the rename field; the query and both mutations go flat at the top of `build` |
| `QuerySelectBuilder` | the header badge | a leaf widget, so the builder stays visible in the tree |

## Tests

Two layers. The widget tests run the real app against an in-memory gateway;
the end-to-end tests run the real *web build* in a real Chromium against the
real express gateway.

```bash
flutter test
```

Fifteen widget tests — one per row of the MVP feature checklist, plus a
regression found by review — running the real app, with its own client
defaults, against [`test/fake_gateway.dart`](test/fake_gateway.dart) — an
in-memory stand-in for `react-demo/server/server.ts` wired in as a dio
`HttpClientAdapter`. Only the transport is replaced: the app's own `SensorApi`,
its JSON, its error handling and its cancellation are all exercised. Pointing
the same app at the express gateway is then a smoke test rather than a leap of
faith.

### End-to-end, in the browser

[`e2e/`](e2e/) is a [Playwright](https://playwright.dev) project. It starts the
express gateway and a static server for the web build, opens the app in
Chromium and asserts on what a user sees — and on the wire: how many requests a
screen costs, that a refetch keeps the rows, that an optimistic rename shows
before the write returns, that the Matter poll stops once the device confirms,
that a refused delete springs back, that an unreachable gateway is retried
exactly once. Playwright can cut the network, which no widget test can.

Nothing in the suite asserts on a stopwatch. To prove that a write shows
*before* the gateway answers, the test holds the request at the network layer
(`page.route`) and releases it once it has seen the optimistic patch: the
server has provably not replied, so there is no wall-clock budget to blow. A
timeout instead would be a guess about how fast the browser repaints and
republishes its semantics tree, and a busy machine makes that guess wrong now
and then.

Flutter web paints to a canvas, so the tests read the **semantics tree** — the
same tree a screen reader gets. The build under test switches it on from the
start (`--dart-define=E2E=true`, see `main.dart`); rows are groups named after
their sensor, buttons carry their tooltips, the switch is a `switch` with
`aria-checked`. Two things worth knowing when adding a test: the semantic
`<input>` of a text field mirrors its text only once the field has focus, so
click before you read or `fill`; and the list builds only the rows in view,
which is why the suite runs with a tall viewport and sweeps its own sensors off
the gateway before and after.

```bash
cd e2e && npm ci && npx playwright install chromium   # once
npm run build                                          # flutter build web --dart-define=E2E=true
npm test                                               # or: npx playwright test --ui
```

The gateway keeps one in-memory state per process and scripts "every second
delete fails", so the tests run one at a time, create the sensors they act on,
and never depend on the seed data or on each other. CI runs the same suite on
every push (`.github/workflows/ci.yml`, job `e2e`).
