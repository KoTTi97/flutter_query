# sensor_demo

The React demo's sensor manager, rebuilt on `tanstack_query_flutter` — same
gateway, same cache policy, same scripted failures, so the two clients can be
put side by side.

## Running it

Start the gateway the React demo uses (port 5174):

```bash
cd ../../react-demo/server && npm install && npm run dev
```

```bash
flutter run -d macos     # or chrome, or an emulator
```

An Android emulator reaches the host through `10.0.2.2`, which the app picks by
itself. For a real device, point it at your machine:

```bash
flutter run --dart-define=GATEWAY=http://192.168.1.5:5174/api
```

The gateway is deliberately slow (~900 ms a list fetch, ~700 ms a write) and has
scripted failures: renaming a sensor to **`fail`** is rejected, and **every
second delete** fails. Both rollbacks are demonstrable on demand.

## What to look at

The whole cache policy is [`lib/src/queries.dart`](lib/src/queries.dart) — one
file, and worth comparing line for line with
`react-demo/react/src/queries.ts`. The shape it sets up:

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

```bash
flutter test
```

Fourteen widget tests, one per row of the MVP feature checklist, running the
real app against [`test/fake_gateway.dart`](test/fake_gateway.dart) — an
in-memory stand-in for `react-demo/server/server.ts` wired in as a dio
`HttpClientAdapter`. Only the transport is replaced: the app's own `SensorApi`,
its JSON, its error handling and its cancellation are all exercised. Pointing
the same app at the express gateway is then a smoke test rather than a leap of
faith.
