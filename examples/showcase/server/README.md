# The showcase backend

A dummy HTTP backend for the showcase app and its end-to-end tests. Node 23.6
or later (it runs the TypeScript directly), express, nothing else.

```bash
npm install && npm run dev        # http://localhost:5175, restarts on edit
```

The route table is the header comment of [`server.ts`](server.ts); the seed
data is [`seed.json`](seed.json), which the Flutter widget tests' fake backend
loads too, so both sides start from the same rows.

## Scenarios

Every request carries an `x-scenario` header naming a world of its own —
posts, todos, ticks, a counter, a request log and a fault configuration. A
world is seeded on first contact and dropped after fifteen idle minutes.
Requests without the header share the `default` world, which is what a human
in a browser gets.

That is what lets the Playwright suite run its tests in parallel against one
process: each test mints its own id, resets it, scripts the failures it wants,
and asserts on its own request log.

```bash
curl -X POST localhost:5175/api/__scenario/demo/reset
curl -X POST localhost:5175/api/__scenario/demo/config \
  -H 'content-type: application/json' \
  -d '{"latency":0,"failNext":[{"method":"PATCH","path":"/api/todos/*","count":1,"status":500}]}'
curl -H 'x-scenario: demo' -X PATCH localhost:5175/api/todos/1 \
  -H 'content-type: application/json' -d '{"done":true}'      # → 500 once
curl localhost:5175/api/__scenario/demo/requests
```

## Faults

Applied to every resource request, in this order:

1. the scenario's `latency` (300 ms unless configured — long enough to see a
   loading state, short enough not to slow a test suite);
2. `?delay=<ms>` on the request, on top — the app's own controls use this;
3. `?fail=<status>` on the request — the app asks to be refused;
4. the scenario's `failNext` scripts: the next `count` requests matching
   `method` and `path` (exact, or a prefix when the path ends in `*`) get
   `status`;
5. the scenario's `errorRate`: a seeded random share of requests fails with
   500 — seeded per scenario id, so the same scenario fails the same requests
   every run.

`LATENCY=3000 npm run dev` changes the default for every new scenario.
