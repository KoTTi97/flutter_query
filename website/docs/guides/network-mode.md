---
title: Network mode and offline
description: What a query or mutation does while the client believes it is offline — online, always and offlineFirst — and how paused work resumes.
---

{/* depth: todo */}
{/* demo: offline */}

# Network mode and offline

`NetworkMode` decides what a query does when the client believes it is
offline:

| | |
|---|---|
| `NetworkMode.online` | the default: do not fetch; a query with nothing cached stays `pending` with `fetchStatus: paused` |
| `NetworkMode.always` | fetch regardless — for a query that does not need the network at all |
| `NetworkMode.offlineFirst` | try once, then pause instead of retrying — for a cache-backed transport that may answer offline |

A paused query shows `isPaused` on its result (see [queries](queries.md)), and
it continues by itself when the client learns it is online again — as long as
the client is mounted, which `QueryClientProvider` does for you.

What "offline" means is up to you: nothing is installed by default, and the
client believes it is online until something says otherwise. See
[connectivity](connectivity.md).

## Mutations

In the default `online` mode, a **mutation** started offline is **paused**,
not failed.
`client.resumePausedMutations()` releases paused mutations, and a mounted
client does it itself when the online manager flips back.

A mutation that could run offline (`NetworkMode.always`) but is queued behind
a [scope](mutation-scopes.md)-mate that cannot stays paused until the scope
moves; `resumePausedMutations()` does not wait for it.

## Queries and mutations have separate defaults

`networkMode` set in the client's query defaults does not reach mutations.
An app that talks to a device on the local network, and so should ignore the
platform's connectivity, sets it in both:

- `DefaultOptions(queries: QueryDefaults(networkMode: …))`
- `DefaultOptions(mutations: MutationDefaults(networkMode: …))`

Each resolves option → the defaults registered for its key → its own client
default → `online`.
