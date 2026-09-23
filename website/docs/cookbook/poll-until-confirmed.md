---
title: Poll until a device confirms
sidebar_label: Poll until confirmed
description: A write the server accepts but a device confirms later, with the requested value shown at once, a poll that starts and stops itself, and a clear state for giving up.
sidebar_position: 16
---

# Poll until a device confirms

**The problem.** A switch in the app turns a relay on a smart-home device on
or off. The request goes to a server, and the server answers *accepted*
(often with HTTP 202) before the device has done anything. The device
confirms seconds later, or not at all if it is offline. The user must see
their choice at once and see that it is still pending. The app must learn
when it is confirmed without polling forever. And if the device never
answers, the switch must say so instead of spinning.

**The recipe.** Four parts, each doing one job:

- The **model** keeps what the device confirmed (`on`) separate from what was
  requested (`requestedOn`, `pendingSince`). A poll answer cannot overwrite
  the user's choice, because the two are different fields.
- The **query** polls with a `RefetchInterval.dynamic` that reads the data:
  half a second while a confirmation is outstanding, and nothing otherwise.
- The **mutation** writes the requested value optimistically and then writes
  the server's *accepted* answer into the cache. That write starts the poll.
- The **widget** shows four states: on, off, waiting, and gave up.

## The model

```dart title="lib/data/relay.dart" snippet="cookbook/poll-until-confirmed.md#model"
@immutable
class Relay {
  const Relay({
    required this.id,
    required this.on,
    this.requestedOn,
    this.pendingSince,
  });

  final String id;

  /// What the device last confirmed.
  final bool on;

  /// What a write asked for and the device has not confirmed; `null` when
  /// nothing is outstanding. A field of its own, so that a poll answer
  /// cannot overwrite the value the user just chose.
  final bool? requestedOn;

  /// When the server accepted a write the device has not confirmed yet.
  final DateTime? pendingSince;

  bool get isPending => pendingSince != null;

  /// What the switch shows: a requested value outranks the confirmed one.
  bool get shownOn => requestedOn ?? on;

  Relay copyWith({bool? requestedOn}) => Relay(
        id: id,
        on: on,
        requestedOn: requestedOn ?? this.requestedOn,
        pendingSince: pendingSince,
      );

  @override
  bool operator ==(Object other) =>
      other is Relay &&
      other.id == id &&
      other.on == on &&
      other.requestedOn == requestedOn &&
      other.pendingSince == pendingSince;

  @override
  int get hashCode => Object.hash(id, on, requestedOn, pendingSince);
}
```

## The query and when it polls

```dart title="lib/data/relay_queries.dart" snippet="cookbook/poll-until-confirmed.md#query"
const Duration confirmTimeout = Duration(seconds: 30);

QueryObserverOptions<Relay> relayQuery(String id) => QueryObserverOptions(
      queryKey: relayKey(id),
      queryFn: (context) => relayApi.get(id, signal: context.signal),
      refetchInterval: const RefetchInterval.dynamic(pollWhilePending),
      // A confirmation that lands while the user glances away still counts.
      refetchIntervalInBackground: true,
    );

/// Asked again after every poll: half a second while the device owes a
/// confirmation, and `null` — stop — once it has answered or given up.
Duration? pollWhilePending(Query<Object?> query) {
  final relay = query.state.data;
  if (relay is! Relay || !relay.isPending) return null;
  if (gaveUp(relay, query.state.consecutiveErrorCount)) return null;
  return const Duration(milliseconds: 500);
}

/// Five failed polls in a row, or no confirmation within [confirmTimeout].
bool gaveUp(Relay relay, int consecutiveErrors) =>
    consecutiveErrors >= 5 ||
    DateTime.now().difference(relay.pendingSince!) > confirmTimeout;
```

The function passed to `RefetchInterval.dynamic` is called again whenever the
query's state changes, for example when a fetch finishes or the key is
written. So the poll starts when the mutation writes a pending relay, stops
when a poll brings back a relay that is no longer pending, and stops when
`gaveUp` says so. `consecutiveErrorCount` counts failed fetches in a row and
a successful fetch resets it, so five unreachable polls stop it as surely as
the timeout does.

`refetchIntervalInBackground: true` keeps the poll running while the app is
not focused. A user who checks the physical device and comes back should find
the switch already confirmed.

## The write

```dart title="lib/data/relay_mutations.dart" snippet="cookbook/poll-until-confirmed.md#mutation"
typedef RelayWrite = ({String id, bool on});

MutationOptions<Relay, RelayWrite, Relay?> switchRelay(QueryClient client) =>
    MutationOptions<Relay, RelayWrite, Relay?>(
      mutationFn: (write) => relayApi.set(write.id, on: write.on),
      onMutate: (write) async {
        final key = relayKey(write.id);
        await client.cancelQueries(filters: QueryFilters(queryKey: key));
        final previous = client.getQueryData<Relay>(key);
        // The requested value, not the confirmed one — and no pendingSince:
        // polling starts when the server has accepted, not before.
        client.updateQueryData<Relay>(
          key,
          (relay) => relay?.copyWith(requestedOn: write.on),
        );
        return previous;
      },
      onError: (_, __, write, previous) {
        if (previous != null) {
          client.setQueryData<Relay>(relayKey(write.id), previous);
        }
      },
      // The answer says "pending": writing it is what starts the poll.
      onSuccess: (accepted, write, _) =>
          client.setQueryData<Relay>(relayKey(write.id), accepted),
    );
```

`onMutate` cancels any poll in flight first. A poll answer that left the
server before the write would otherwise land after the optimistic value and
remove `requestedOn`.

## The switch

```dart title="lib/features/relay/relay_switch.dart" snippet="cookbook/poll-until-confirmed.md#switch"
class RelaySwitch extends StatelessWidget {
  const RelaySwitch({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    final result = context.query(relayQuery(id));
    final write = context.mutation(switchRelay(client));

    final relay = result.dataOrNull;
    if (relay == null) {
      return ListTile(
        title: const Text('Relay'),
        subtitle: Text(result.isError ? 'Unreachable' : 'Loading…'),
      );
    }
    return SwitchListTile(
      title: const Text('Relay'),
      value: relay.shownOn,
      subtitle: Text(switch (relay) {
        Relay(isPending: false, on: true) => 'On',
        Relay(isPending: false) => 'Off',
        _ when gaveUp(relay, result.consecutiveErrorCount) =>
          'The device did not confirm',
        _ => 'Waiting for the device…',
      }),
      onChanged: write.value.isPending || relay.isPending
          ? null
          : (on) => write.mutate((id: id, on: on)),
    );
  }
}
```

The switch is disabled while a write is in flight and while the device owes
a confirmation, so a second tap cannot race the first.

## Steps

1. Make the server's answer say *pending*. A `pendingSince` timestamp is
   enough, and it gives the client a clock to time out against.
2. Keep requested and confirmed values in separate fields.
3. Poll with `RefetchInterval.dynamic`, returning `null` whenever there is
   nothing to wait for.
4. Write the accepted answer into the cache in `onSuccess`. Do not invalidate
   it, because the answer *is* the new state.
5. Decide when to give up (errors in a row, a deadline, or both) and show that
   state.

## Traps

- **One field for both values.** When the optimistic write sets `on: true`
  and a poll returns the device's `on: false`, the switch flickers back until
  the confirmation arrives. Separate fields prevent it.
- **A callback in `enabled` instead of the interval.** Turning the query off
  when nothing is pending also turns off every refetch on focus, mount and
  reconnect. The interval is the only thing that should change.
- **Trusting two clocks.** `gaveUp` compares the server's `pendingSince`
  with the device's clock, and a phone whose clock is off by a minute gives
  up at once or far too late. When that matters, let the server send the
  deadline or the seconds left instead of a timestamp, or time out from the
  moment the app received the accepted answer.
- **Giving up only on errors.** A device that stays offline does not make the
  server fail. The server keeps answering *pending*, so the error count stays
  at zero. The deadline catches that case.
- **Invalidating in `onSuccess`.** A refetch costs a request to get what the
  answer already contained, and until it returns, the cache holds the
  optimistic value without `pendingSince`, so the poll does not start.

## Variations

- **Let the user try again.** After giving up, the relay is still pending,
  so the switch stays disabled. Offer a *Check again* button that calls
  `client.refetchQueries(filters: QueryFilters(queryKey: relayKey(id)))`, or
  let the server expire the pending state so the next fetch clears it.
- **Many devices.** Every relay has its own key and its own interval. A device
  that confirms stops only its own poll.
- **Cancel the write.** When the server supports it, a cancel request is
  another mutation whose answer (no longer pending) is written the same way.
  The poll stops because the interval function sees `isPending == false`.
- **A push channel instead of polling.** When the device's confirmation
  arrives as an event, write it with `updateQueryData` as in [Realtime
  updates over a WebSocket](realtime-websockets.md). The poll stops as soon
  as the event clears the pending state, and it remains as a fallback for a
  lost event.

[Polling](../guides/polling.md) covers `refetchInterval` in general, and
[Optimistic updates](../guides/optimistic-updates.md) covers the
`onMutate`/`onError` pair.

## See it run

The task manager app uses this pattern for a task's reminder. Open a task and
flip *Reminder*: the switch moves at once and is marked `confirming`. The
demo's scheduler confirms after about three seconds, and the poll, every
half second, picks that up and stops.

<LiveDemo app="task_manager" height={720} />

:::note[In React Query]
This is `refetchInterval` as a function of the query, returning `false` to
stop. Here it returns a `Duration?`, with `null` meaning stop, and
`consecutiveErrorCount` is available on the query's state and on the result.
See [differences from TanStack
Query](../reference/differences-from-tanstack.md).
:::
