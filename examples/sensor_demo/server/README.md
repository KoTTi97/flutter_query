# The sensor gateway

The dummy backend `sensor_demo` talks to, and the one its Playwright suite
starts. Node 23.6 or later (it runs the TypeScript directly), express, nothing
else. State is in memory, so restarting it resets the sensors.

```bash
npm install && npm run dev        # http://localhost:5174, restarts on edit
```

The route table is the header comment of [`server.ts`](server.ts):

| | |
|---|---|
| `GET /api/sensors` | the list, `?q=` filters by name |
| `GET /api/sensors/:id` | one sensor |
| `POST /api/sensors` | add one |
| `PUT /api/sensors/:id/name` | rename |
| `PUT /api/sensors/:id/matter-forwarding` | request a setting the device confirms later |
| `DELETE /api/sensors/:id` | remove one |

## Deliberately hostile

None of this is interesting against an instant backend that never fails, so
the gateway is slow and breakable on purpose. The latencies in
[`config.ts`](config.ts) are what a small embedded device actually cost —
~900 ms for a list, ~700 ms for a write — and each is an environment variable,
so you can sit inside a transient state for as long as you like:

```bash
LIST_LATENCY=6000 npm run dev     # stay in the loading skeletons
CONFIRM_AFTER=10000 npm run dev   # stay in the "wird bestätigt…" poll
```

Two failures are reachable from the UI, and both exist to make a rollback
visible rather than theoretical:

- renaming a sensor to exactly **`fail`** makes the write reject;
- **every second delete fails**, odd attempts first — so the first click shows
  the row spring back, and the retry on the same row goes through.

`PUT …/matter-forwarding` is the interesting one: it answers *accepted*, not
*done*, and the device applies the setting `CONFIRM_AFTER` milliseconds later.
That is the window a poll has to survive without overwriting the value the
user asked for — see the app's `queries.dart`.

## Where the fake backend fits

`../test/fake_gateway.dart` is an in-memory stand-in for this server, wired
into dio as an `HttpClientAdapter`, so the widget tests exercise the real app
with only the transport replaced. It mirrors these routes, these latencies and
these two scripted failures; when one side changes, the other has to.
