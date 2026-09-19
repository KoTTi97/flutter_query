---
title: Troubleshooting
description: Symptom first — what you see, why it happens, and what to do instead.
---

# Troubleshooting

Symptom first. Most of these are upstream TanStack Query behaviour that this
port keeps on purpose, so the mechanism is worth knowing even once the fix is
in. The first entries come from the library's first integration into a real
app (2026-09-19); each says where it was learned.

## My polling never resumes after I paused it in a callback

**Symptom.** A `RefetchInterval.dynamic` (or an `Enabled.when`) reads state
from *outside the cache* — "is a write in flight", a connection flag, a
notifier — and returns "off" while it is set. The flag clears; polling stays
off.

**Mechanism.** Those callbacks are evaluated when **the query** has an event
— a fetch settling, data written — or when the observer is **handed its
options**, which every rebuild of the reading widget does. Nothing tells the
observer that your flag changed. If the widget does not rebuild when the flag
flips, the last answer — off — stands, and with polling off no query event
will come along to ask again. With a mutation it is sharper still:
`onSettled` runs while the mutation still counts as pending, so a callback
asked *then* still says "writing".

**Fix.** Make the flag rebuild the widget that reads the query — a
`ValueListenableBuilder`, a `ListenableBuilder`, a `MutationStateController`
for "a write is in flight", `setState`. The rebuild hands the observer its
options again and both callbacks are asked again. Outside widgets,
`observer.setOptions(options)` with the very same options does the same.

Better still, put outside state into the options as a **value**; then there
is no callback to go stale:

```dart snippet="reference/troubleshooting.md#pause-polling"
QueryObserverOptions<List<Task>> polledTasks({required bool writing}) =>
    QueryObserverOptions(
      queryKey: tasksKey,
      queryFn: (context) => api.listTasks(signal: context.signal),
      // A value, not a callback: the widget rebuilds when `writing` flips,
      // hands over new options, and the observer sees that they changed.
      refetchInterval: writing
          ? RefetchInterval.off
          : const RefetchInterval.every(Duration(seconds: 1)),
    );
```

Keep the callbacks for what they can see: the query's own state — "stop
polling once the job reports `done`".

Upstream differs in one detail here. It compares the old and the new `enabled`
*at the same instant*, so there even a rebuild does not help an `enabled`
callback over outside state: both sides see the same world. This port compares
against what the observer last saw.

*Learned in: the BR64 integration, where polling paused for a write never came
back.*

## I removed a device's queries and it is being fetched again

**Symptom.** `removeQueries` under a prefix, on disconnect. A moment later the
entries are back and requests go out to a device that is gone.

**Mechanism.** An observer owns a **key**, not an entry. While a widget that
reads the key is still mounted, its next options update, poll tick or an
optimistic rollback builds the entry again and fetches. Upstream does exactly
this.

**Fix.** Remove the readers before the entries: take the device's screens out
of the tree (or give their queries `Enabled.no`) and *then* cancel and remove.

```dart snippet="reference/troubleshooting.md#disconnect"
void disconnect(QueryClient client, QueryKey deviceKey) {
  final filters = QueryFilters(queryKey: deviceKey);
  client.cancelQueries(filters: filters).ignore();
  client.removeQueries(filters: filters);
}
```

If the order cannot be guaranteed, make the transport refuse: an API object
that is closed and throws an error your `retry` policy does not retry costs
one failed fetch instead of a request on the wire.

*Learned in: the BR64 integration's disconnect path.*

## The first of two writes lost its state and its callbacks

**Symptom.** Two `mutate` calls on one `MutationController`. The first one's
`isPending`, its result, and the `onSuccess`/`onError` passed *to that call*
never show up.

**Mechanism.** A mutation controller observes its **latest** run. A second
`mutate` moves it on, and per-call callbacks only fire for the run the
controller is still watching — also when the controller was disposed in
between. Callbacks on the **options** always run; they belong to the
mutation, not to who watches it. Upstream's `useMutation` is the same.

**Fix.** Side effects that must happen go in the options' callbacks. Feedback
for one particular write comes from awaiting `mutateAsync`. To show every
write in flight, not just the last, read the cache with a
`MutationStateController`.

## `QueryDataTypeError` for a list that "is" the right type

**Symptom.** A key holds a `List<Ingress>`; something reads it as
`List<EnOceanDeviceDto>`, or as a supertype's list, and gets a
`QueryDataTypeError` rather than data.

**Mechanism.** One key, one exact data type. The cache checks the type it is
asked for against what it holds instead of casting blindly, and a
`List<Sub>` is not accepted where the entry was created as `List<Base>` (or
the reverse) — see
[one type slot per query](https://github.com/KoTTi97/flutter_query/blob/main/docs/adr/0001-one-type-slot-for-plain-queries.md).

**Fix.** Give each type its own key, or store a wrapper type that says what
the entry is. Be careful with `updateQueriesData` over a prefix that spans
entries of different types: the updater's type argument has to fit every
entry it matches, so filter narrowly.

## A mutation that awaits another mutation never finishes

**Symptom.** Inside a mutation with a `MutationScope`, `await
other.mutateAsync(...)` — and `other` has the **same scope**. Both hang.

**Mechanism.** A scope runs its mutations one at a time. The inner one queues
behind the outer one, which is waiting for the inner one. By design, upstream
included, and there is no warning.

**Fix.** Give the inner mutation no scope (or a different one), or do the
inner work as a plain call inside the outer mutation function.

## My offline-tolerant app still pauses its writes

**Symptom.** `networkMode: NetworkMode.always` is set in the client's query
defaults — the app talks to a device on the local network — but mutations
still pause when the platform reports offline.

**Mechanism.** Queries and mutations have **separate** client defaults, as
upstream has. Each resolves option → its own client default → `online`.

**Fix.** Set `networkMode` in the mutation defaults as well.
