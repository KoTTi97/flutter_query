---
title: Realtime updates over a WebSocket
sidebar_label: Realtime and WebSockets
description: Let server events write to the cache or invalidate it, keep the socket's lifetime in one widget, and resynchronise after a reconnect.
---

# Realtime updates over a WebSocket

**The problem.** An order-tracking screen shows orders whose status changes
on the server: packing, shipped, delivered. The server pushes those changes
over a WebSocket. Polling every few seconds would waste requests and still be
late. But the screens already read orders through queries, and a second data
path from socket to widget would duplicate the loading, error and caching
logic.

**The recipe.** The socket does not feed widgets. It feeds **the cache**.
Every event becomes one of two cache operations:

- **Write** when the event carries the whole entity: `updateQueryData` puts
  it in place, and every reader of that key rebuilds with no request.
- **Invalidate** when the event only says *something changed*, or when the
  change affects entries the client cannot recompute (which lists contain the
  order, and in what position). Invalidation refetches what is on screen and
  marks the rest stale.

Queries stay the only way widgets read. The socket only keeps them current.

## The events

Parse the socket's frames into a sealed type, so that the handler below is an
exhaustive `switch`:

```dart title="lib/data/server_events.dart" snippet="cookbook/realtime-websockets.md#events"
sealed class ServerEvent {
  const ServerEvent();
}

/// An order changed, and the event carries all of it.
final class OrderChanged extends ServerEvent {
  const OrderChanged(this.order);

  final Order order;
}

/// An order is gone.
final class OrderRemoved extends ServerEvent {
  const OrderRemoved(this.id);

  final String id;
}

/// Events may have been missed — the socket reconnected.
final class Resync extends ServerEvent {
  const Resync();
}
```

## The query

```dart title="lib/data/order_queries.dart" snippet="cookbook/realtime-websockets.md#order-query"
QueryObserverOptions<Order> orderQuery(String id) => QueryObserverOptions(
      queryKey: OrderKeys.detail(id),
      queryFn: (context) => ordersApi.get(id, signal: context.signal),
      // The socket keeps it fresh. The stale time is only the safety net
      // for a socket that went quiet without anybody noticing.
      staleTime: const StaleTime.duration(Duration(minutes: 5)),
    );
```

With a socket keeping the entry current, `staleTime` no longer decides how
fresh the data is. It remains as a limit on how long a silent socket can go
unnoticed before a focus or a remount refetches anyway.

## Events into the cache

```dart title="lib/data/realtime_sync.dart" snippet="cookbook/realtime-websockets.md#sync"
class RealtimeSync {
  RealtimeSync(this.client);

  final QueryClient client;

  StreamSubscription<ServerEvent> listen(Stream<ServerEvent> events) =>
      events.listen(apply);

  void apply(ServerEvent event) {
    switch (event) {
      case OrderChanged(:final order):
        // The whole order is in the event: write it, unless the cache
        // already holds the same version or a newer one.
        client.updateQueryData<Order>(
          OrderKeys.detail(order.id),
          (cached) =>
              cached != null && cached.version >= order.version ? null : order,
        );
        // Which lists it belongs to, and where, is the server's business.
        client
            .invalidateQueries(filters: QueryFilters(queryKey: OrderKeys.lists))
            .ignore();
      case OrderRemoved(:final id):
        client
            .invalidateQueries(filters: QueryFilters(queryKey: OrderKeys.lists))
            .ignore();
        client
            .invalidateQueries(
                filters: QueryFilters(queryKey: OrderKeys.detail(id)))
            .ignore();
      case Resync():
        client
            .invalidateQueries(filters: QueryFilters(queryKey: OrderKeys.all))
            .ignore();
    }
  }
}
```

The version check matters. An event can arrive while a refetch of the same
order is in flight. Whichever lands last wins, and without the check an older
event could overwrite newer data. Returning `null` from the updater leaves the
cache untouched.

## The socket

This section targets **web_socket_channel 3**. The adapter turns frames into
`ServerEvent`s and reconnects when the socket closes. After every reconnect it
emits a `Resync`, because events sent while it was disconnected are lost.

```dart title="lib/data/order_socket.dart" snippet="prose-only: needs web_socket_channel 3, which the snippet package may not depend on"
class OrderSocket {
  OrderSocket(this.uri);

  final Uri uri;
  final _events = StreamController<ServerEvent>.broadcast();
  WebSocketChannel? _channel;
  bool _closed = false;

  Stream<ServerEvent> get events => _events.stream;

  Future<void> connect({Duration backoff = const Duration(seconds: 1)}) async {
    var first = true;
    while (!_closed) {
      try {
        final channel = WebSocketChannel.connect(uri);
        await channel.ready;
        _channel = channel;
        if (!first) _events.add(const Resync());
        first = false;
        backoff = const Duration(seconds: 1);
        await for (final frame in channel.stream) {
          _events.add(parseEvent(jsonDecode(frame as String)));
        }
      } catch (_) {
        // Fall through to the reconnect below.
      }
      if (_closed) break;
      await Future<void>.delayed(backoff);
      backoff = backoff * 2 > const Duration(seconds: 30)
          ? const Duration(seconds: 30)
          : backoff * 2;
    }
  }

  Future<void> close() async {
    _closed = true;
    await _channel?.sink.close();
    await _events.close();
  }
}
```

`parseEvent` maps your server's JSON to the three event classes.

## Scope the subscription to the tree

One widget owns the subscription. It goes below the `QueryClientProvider`
and above every screen that shows orders:

```dart title="lib/app/live_orders.dart" snippet="cookbook/realtime-websockets.md#live-scope"
/// Keeps the cache in step with [events] for as long as it is mounted. Put it
/// below the QueryClientProvider and above the screens.
class LiveOrders extends StatefulWidget {
  const LiveOrders({super.key, required this.events, required this.child});

  final Stream<ServerEvent> events;
  final Widget child;

  @override
  State<LiveOrders> createState() => _LiveOrdersState();
}

class _LiveOrdersState extends State<LiveOrders> {
  late final StreamSubscription<ServerEvent> _subscription;

  @override
  void initState() {
    super.initState();
    _subscription =
        RealtimeSync(QueryClientProvider.read(context)).listen(widget.events);
  }

  @override
  void dispose() {
    _subscription.cancel().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

```dart title="lib/main.dart" snippet="prose-only: uses the OrderSocket above, which needs web_socket_channel 3"
final socket = OrderSocket(Uri.parse('wss://api.example.com/orders'));
socket.connect().ignore();

runApp(
  QueryClientProvider.create(
    create: QueryClient.new,
    child: LiveOrders(events: socket.events, child: const OrdersApp()),
  ),
);
```

## Steps

1. Parse frames into a sealed event type.
2. For each event, decide between writing and invalidating. Write only what
   the event fully describes. Invalidate the rest.
3. Guard writes with a version or timestamp from the server.
4. After a reconnect, invalidate everything the socket covers.
5. Subscribe in one widget below the provider and cancel in its `dispose`.

## Traps

- **Setting list data from an item event.** Inserting a changed order into
  every cached list means recomputing filters, sort order and paging on the
  client. Doing that wrong leaves lists that disagree with the server until
  the next refetch. Invalidate the lists instead: only the ones on screen
  refetch.
- **Forgetting the gap.** A socket that reconnects silently has missed events.
  Without the `Resync`, the cache stays wrong until each entry goes stale.
- **Writing entries nobody reads.** `updateQueryData` on a key with no entry
  creates one. That is harmless, because an unobserved entry is garbage
  collected after `gcTime`, and useful, because opening that order is then
  instant. To avoid it, return `null` when `cached` is `null`.
- **`staleTime: StaleTime.infinite` with a socket.** It looks right, since the
  socket keeps data fresh. But when the socket is down, nothing ever refetches.
  A finite stale time is the safety net.

## Variations

- **Events that carry only ids.** When an event says only "order 42 changed",
  invalidate `OrderKeys.detail('42')` as well as the lists. The detail
  refetches if it is on screen and is marked stale otherwise.
- **Server-sent events or Firebase.** Any `Stream<ServerEvent>` fits
  `LiveOrders`. The adapter is the only part that changes.
- **Pausing in the background.** Close the socket when the app is paused and
  open a new one on resume. Apply a `Resync` when it is open, so that whatever
  changed in the meantime is refetched.
- **Polling instead.** When the server cannot push, see
  [Polling](../guides/polling.md), or [Poll until
  confirmed](poll-until-confirmed.md) for a poll that stops by itself.

## See it run

The auto-refetching demo shows the alternative this recipe replaces: a query
polled on an interval. Pick an interval and watch the fetch count grow with
every poll, whether or not anything changed. *Add tick* shows the other path.
The write invalidates the list, so it refreshes at once, which is what an
event does here, with no request per interval.

<LiveDemo feature="auto-refetching" height={640} />

:::note[In React Query]
This is the pattern from TanStack's own WebSocket write-up: events call
`queryClient.setQueryData` or `invalidateQueries`, and the socket lives in one
effect near the root. `updateQueryData` is `setQueryData` with an updater
function. See [differences from TanStack
Query](../reference/differences-from-tanstack.md).
:::
