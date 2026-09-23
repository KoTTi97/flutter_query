---
title: Network mode and offline
description: What queries and mutations do while the client believes it is offline — online, always and offlineFirst — how paused work shows on the result, and how it resumes.
---

# Network mode and offline

A phone loses its connection in a lift. What should the device list do? A
request that cannot leave the phone will fail, be retried three times with
backoff, and end as an error the user did not cause and cannot fix — unless
the query knows it is offline and waits instead.

`networkMode` says how a query or mutation treats the client's belief about
the network:

| `NetworkMode` | Offline, it… | For |
|---|---|---|
| `NetworkMode.online` | does not start; a retry does not continue. It **pauses** and resumes when the client is online again | the default: anything that needs the internet |
| `NetworkMode.always` | ignores connectivity: fetches, fails and retries as if online | work that needs no internet — a local database, a device on the home network |
| `NetworkMode.offlineFirst` | makes the first attempt anyway, and pauses a retry | a transport with a cache of its own that may answer offline |

"Offline" is what the client *believes*, and nothing is installed to tell it:
a client with no connectivity source believes it is online forever, and a
failed request is simply a failure. Giving it a source is the
[connectivity](connectivity.md) guide.

Try it: in the screen below, turn *Online* off, press *Refetch* and then
*Add todo*. Under `online` neither sends anything: the query shows
`fetchStatus=paused`, the mutation `isPaused=true`. Turn *Online* back on and
both go out by themselves. Switch *Network mode* to `always` and repeat — the
requests go out with *Online* off, and this demo's backend answers them: the
switch changes only what the client believes, not the network.

<LiveDemo feature="offline" height={640} />

## `online`: a paused query

Under the default mode, a query that would fetch while offline does not. Its
`fetchStatus` is `paused` and its result's `isPaused` is `true`:

- with no data yet, it stays a `QueryPending` — neither loading nor failed;
- with data, it stays a `QuerySuccess` showing that data.

Both cases deserve a word on screen, because a spinner that never ends and a
list that silently stopped updating look like bugs:

```dart snippet="guides/network-mode.md#paused-note"
String? offlineNote(QueryResult<List<Device>> devices) => switch (devices) {
      QueryPending(isPaused: true) => 'Waiting for a connection…',
      QuerySuccess(isPaused: true) => 'Offline — showing the last list loaded',
      _ => null,
    };
```

A retry is subject to the same rule: a fetch whose first attempt failed and
whose connection then dropped pauses between attempts instead of spending
them. When the client is online again, a mounted client continues every
paused fetch where it stopped — one request, not a fresh start — and then
refetches stale queries that have a reader, per `refetchOnReconnect` (a
`RefetchOn`, default `ifStale`).

## `always`: ignore connectivity

A smart-home app talks to two things: the vendor's cloud account, which needs
the internet, and a gateway on the home Wi-Fi, which answers whether or not
the router has an uplink. For the gateway, "offline" is the wrong question.
Defaults for a key prefix put every gateway query and mutation in `always`,
and leave the cloud ones `online`:

```dart snippet="guides/network-mode.md#local-devices"
// The gateway is on the home network: it answers whether or not the phone
// has a route to the internet. The cloud account's queries keep `online`.
void talkToTheGatewayOffline(QueryClient client) {
  client.setQueryDefaults(
    DeviceKeys.all,
    const QueryDefaults(networkMode: NetworkMode.always),
  );
  client.setMutationDefaults(
    DeviceKeys.all,
    const MutationDefaults(networkMode: NetworkMode.always),
  );
}
```

Key defaults match by prefix, so every query key under `['devices']` gets
them; a mutation gets them only when it carries a `mutationKey` under
`['devices']`.

**Queries and mutations have separate defaults.** A `networkMode` in the
query defaults does not reach mutations, and the other way round; an app
that means both sets both, as above — or for the whole client,
`DefaultOptions(queries: QueryDefaults(networkMode: …), mutations:
MutationDefaults(networkMode: …))`. Each resolves option → the defaults
registered for its key → the client's default → `online`.

Under `always`, `refetchOnReconnect` defaults to `never`: a query that never
waited for the network has nothing to catch up on when it returns.

## `offlineFirst`: try once

Some transports can answer without the network — an HTTP client with a disk
cache, a service worker on the web. For those, pausing before the first
attempt would hide data that is there:

```dart snippet="guides/network-mode.md#offline-first"
// The repository sits behind an HTTP cache that can answer from disk.
QueryObserverOptions<List<DeviceType>> cachedDeviceTypesQuery() =>
    QueryObserverOptions(
      queryKey: QueryKey(<Object?>['device-types']),
      queryFn: (context) => deviceRepository.types(signal: context.signal),
      networkMode: NetworkMode.offlineFirst,
    );
```

The first attempt runs even offline. If it fails, the retry after it pauses
until the client is online, as under `online`.

## Mutations offline

In the default `online` mode, a mutation started offline is not sent and not
failed. It is `pending` with `isPaused: true` — the UI can show the write as
queued — and it runs when the client is online again. Several writes made
offline are all started again at once, in the order they were made; to send
each only after the one before it has settled, give them a shared
[scope](mutation-scopes.md).

`client.resumePausedMutations()` is the manual door. A mounted client calls
it by itself when it comes back online, so it is rarely needed. It decides
per mutation: one that still cannot run (an `online` mutation while
offline) is left where it is, and the returned future does not wait for the
network.

A mutation that could run offline (`always`) but is queued behind a
[scope](mutation-scopes.md)-mate that cannot stays paused until that one
moves.

:::warning[Paused work lives in memory]
Paused queries and queued mutations belong to the running client. If the
operating system ends the app while they wait, they are gone — there is no
persistence layer in 1.0. A write that must survive a restart needs a queue
of your own, stored on the device.
:::

## Resuming needs a mounted client

Paused work resumes when the client *hears* that it is online, and it hears
only while mounted. `QueryClientProvider` mounts its client for you; a
pure-Dart client is mounted with `client.mount()`. See
[the mount contract](../important-defaults.md#the-mount-contract).

:::note[In React Query]
`networkMode` has the same three values and the same meaning, and a paused
query reports `fetchStatus: 'paused'`. The difference is in
`resumePausedMutations`: TanStack Query resumes nothing while offline, while
here each paused mutation is decided by its own network mode, so an `always`
mutation is resumed offline. See
[differences from TanStack Query](../reference/differences-from-tanstack.md).
:::
