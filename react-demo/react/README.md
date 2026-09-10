# React + TanStack Query reference demo

The reference the Flutter port had to match: a small sensor manager written
the way TanStack Query is meant to be written, against the gateway in
`../server`. Every cache behaviour the port claims — dedup across observers,
optimistic writes with rollback, polling that stops, invalidation of one key —
is visible here first, in the library itself, so the Dart side has something to
be wrong against. The UI is in German; the code and this document are not.

## Run

Two processes: the dummy gateway (shared with the Flutter demo) and Vite.

```bash
cd server && npm install && npm run dev   # gateway on :5174
```

```bash
cd react && npm install && npm run dev    # app on :5173
```

The app is on http://localhost:5173; Vite proxies `/api` to the gateway, so the
browser stays same-origin. The gateway (`../server`) is a standalone express
server with plain JSON endpoints — it exists as its own process precisely so
more than one client can share it. State is in memory, so restarting it resets
the sensors.

Type checking is a separate step (Vite only transpiles), and linting/formatting
is Biome:

```bash
npm run typecheck
npm run check      # biome lint + format + import sorting, with fixes
```

`npm run lint` and `npm run format` are the individual halves.

## The stack, and why each piece is here

| | |
|---|---|
| **express** (in `../server`) | The dummy gateway, standalone so the React and Flutter demos share one backend. Plain JSON over HTTP; the route table in `server/server.ts` is the contract. |
| **TanStack Query** | All server state: caching, invalidation, optimistic updates, rollback, polling, retries. |
| **zustand** | All client state: which screen is open, search text, menu expansion. Nothing the gateway owns is ever copied into it. |
| **axios** | The transport. Interceptors are the single choke point for headers, timing and error normalisation (the gateway's `{ message }` errors become the `Error` the UI renders). |
| **shadcn/ui** | The component layer — Radix primitives plus Tailwind, vendored into `src/components/ui/` rather than installed. |
| **react-hook-form** | The rename form. |
| **Biome** | Lint + format + import sorting in one binary. No ESLint, no Prettier. |
| **TypeScript 7** | The native Go port of the compiler. |

tRPC used to sit where `src/api.ts` now is. Replacing it costs the checked
contract — client types are now a copy by convention (`shared/types.ts`, hand
`api` functions, a `sensorKeys` key factory) — but it makes the demo's shape
identical to what the Flutter client builds against the same gateway, which is
the point of keeping it here. The layering survives the swap: **api.ts types
the call, axios carries it, TanStack Query decides whether it happens at all.**

### shadcn needs React 19

Worth knowing before doing this elsewhere: the current shadcn components are
written for React 19, where a function component receives `ref` as an ordinary
prop. On React 18 they silently half-work — React logs *"Function components
cannot be given refs"* and any Radix primitive using `asChild` (the dropdown
trigger here) never wires up, so **the menu simply does not open**. The fix is to
be on React 19, not to wrap each component in `forwardRef`; patching them would
be undone by the next `shadcn add`.

### Biome config

`biome.json` is close to stock: recommended rules plus the `react` domain,
single quotes, 100 columns. Two things needed setting explicitly —
`css.parser.tailwindDirectives`, or Tailwind 4's `@theme`/`@custom-variant`
syntax fails to parse; and note that `biome migrate` rewrites the deprecated
`rules.recommended: true` to **`preset: "none"`**, which silently disables every
rule. It should be `preset: "recommended"`.

The generated `src/components/ui/**` is linted and formatted along with
everything else, so `shadcn add` output gets reformatted to match. That is
intentional — the alternative is a permanently non-conforming corner of the
tree.

## TypeScript setup

Two configs, because the two halves target different runtimes:

- `tsconfig.json` — browser code. `moduleResolution: bundler`, and it must name
  its `types` explicitly: TS 7 defaults `types` to `[]` rather than
  auto-discovering, and its new `noUncheckedSideEffectImports` default would
  otherwise reject `import './index.css'`.
- `tsconfig.tools.json` — just the Vite config now. `nodenext`, plus
  `types: ["node"]`.

The gateway in `../server` has its own package and tsconfig, and **no build
step**: Node runs `server.ts` directly by stripping types. `erasableSyntaxOnly`
is on everywhere — it rejects syntax that type-stripping cannot handle (enums,
parameter properties) — and relative imports carry explicit `.ts` extensions for
the same reason.

`shared/types.ts` is the client's copy of the gateway's domain model
(`../server/types.ts` is the producing side). Every import of it is
`import type`, so it is erased before it reaches the browser.

Path aliases (`@/components/...`) are declared with `paths` alone — TypeScript 7
removed `baseUrl`, so the entries resolve relative to `tsconfig.json` itself.

## Deliberately hostile gateway

The gateway is slow (~900 ms list, ~700 ms writes), because none of this is
interesting against an instant backend.

Latencies are env-tunable if you want to sit inside a transient state:

```bash
LIST_LATENCY=6000 npm run dev   # stay in the loading skeletons
CONFIRM_AFTER=10000 npm run dev # stay in the "wird bestätigt…" poll
```

Failure paths are reachable from the UI:

- renaming a sensor to exactly **`fail`** makes the write reject;
- **every second delete fails**, odd attempts first — the first click shows the
  rollback, the retry on the same row goes through.

## Cache shape

The list query owns **which** sensors exist. A per-sensor query owns **what each
one is**. Both the overview rows and the detail screen read that same per-sensor
query, which is what makes the whole thing click:

- Renaming invalidates **one key** and both screens reconcile from one cheap
  refetch. There is no cross-cache patching to keep in sync.
- Mounting the rows costs nothing: the list response seeds every per-sensor
  cache, so the rows are already fresh and never fetch on mount.
- That seeding is also what keeps a list refresh authoritative — without it the
  rows would keep rendering their own cached copy and a refresh would not show
  through. (Verify: `curl -X PUT localhost:5174/api/sensors/1/name -H
  'content-type: application/json' -d '{"name":"Umbenannt"}'`, then hit
  Aktualisieren.)

Because the seeding has to happen for *every* observer of the list, the query
options are built once in `useSensorListOptions` and shared. Two observers on one
key with two different `queryFn`s is a coin flip over which one runs.

## Loading states

Three distinct states, deliberately not conflated:

| State | Treatment |
|---|---|
| First load, no data at all | Skeletons shaped like the real rows, so nothing shifts when data lands |
| Refetch of data already on screen | Everything stays rendered; a small spinner appears next to the timestamp and in the header |
| Filter change (new query key) | Back to the skeleton — `placeholderData: keepPreviousData` used to keep the previous results dimmed on screen; dropped along with tRPC to keep the surface the Flutter MVP has to match small |

The header's indicator is driven by `useIsFetching()`, which no component had to
be told about.

## Hook reuse

`AppHeader` is a sibling of the overview, mounted elsewhere in the tree, and it
gets the sensor list by asking for it — no prop drilling, no lifted state, and no
second request: it resolves to the same query key as the unfiltered overview
list and derives its own shape with `select`. Mount five more copies and there is
still one fetch. That is the property the current ViewModel wiring cannot offer.

## What each part demonstrates

| Try this | What it shows |
|---|---|
| Open a sensor | Renders instantly — the row and the detail share one cache entry, already populated |
| Rename, then hit „Alle Sensoren“ immediately | Row already shows the new name. Network shows the `PUT …/name` + one `GET /api/sensors/:id` and **no list refetch** |
| Rename to `fail` | Optimistic name reverts, error shown (`onMutate`/`onError` rollback) |
| Toggle Matter-Weiterleitung | Flips optimistically, shows „wird bestätigt…“, polls until the device confirms ~3 s later, then stops — and holds one value throughout |
| Type in the search box | One request per pause, not per keystroke |
| Sensor hinzufügen | Invalidates the list — membership is a list concern |
| Delete a sensor | Row disappears immediately, is restored with an error banner — deleting again succeeds |
| Open the header dropdown | Same data, different component, different shape, zero extra requests |

## Two details worth stealing

**The confirmation window needs its own field.** `matterForwardingTarget` holds
the value a write is trying to reach; `matterForwarding` stays the confirmed
one. Without that split there is nowhere to put the optimistic value except the
confirmed field, and every poll during the ~3 s confirmation window overwrites
it — the switch visibly flickers off→on→off→on. `examples/sensor_demo` carries
the same split for the same reason.

**Optimistic state must not start the poll.** Setting `pending` in `onMutate`
begins polling before the write has reached the gateway, so the first poll reads
pre-write state. The optimistic patch sets the target only; the *accepted*
response is what starts the poll.

## Why per-entity queries are safe here

This demo uses per-entity queries plus invalidation, which is the idiomatic
TanStack approach and the nicest DX. What makes it safe is the seeding above:
because every list response re-stamps all the per-sensor entries fresh, no row
ever fetches on mount and no row goes stale in isolation. Drop the seeding and
fifteen visible rows can produce fifteen requests the moment they mount —
which is exactly the failure a hand-rolled cache walks into, and the reason
`examples/showcase`'s `parallel-queries` screen puts a request counter on
screen.

(An earlier version of this demo also had tRPC's request batching as a second
safety net, collapsing a simultaneous fan-out into one HTTP request. That went
away with tRPC: the gateway is now plain HTTP, so the seeding is load-bearing.)

Open the TanStack devtools (bottom-right) to watch cache entries go
fresh → stale and see exactly which queries fetch.

## The point

`src/queries.ts` is ~230 lines including its comments, and contains the entire
caching, invalidation, optimistic-update, rollback and polling policy. That is
the surface a port has to reproduce, and
[`examples/sensor_demo/lib/src/queries.dart`](../../examples/sensor_demo/lib/src/queries.dart)
is the file it became — the same policy, key for key, which is what makes the
two comparable at all.

Note the deliberate divergence from web defaults in `src/main.tsx`:
`refetchOnWindowFocus` and `refetchOnReconnect` are off, because the gateway
this demo was written against was a small embedded device that could not take a
request storm. The Dart demo keeps the same setting for the same reason —
`RefetchOn.never` on both.
