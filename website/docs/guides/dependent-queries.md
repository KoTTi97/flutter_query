---
title: Dependent queries
description: A query that needs another query's result waits with enabled — the pattern in each call style, Enabled.yes, Enabled.no and Enabled.when, and why it is still a waterfall.
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

# Dependent queries

Some requests need the answer to another one first. A smart-home app knows
which home to show only once it has the signed-in account; the devices of that
home cannot be asked for before. Started too early, the second request goes
out with a `null` id — a 404, a retry loop, an error on screen for a moment
that was never really an error.

A query that needs the result of another must not run until that result is
there. `enabled` holds it back, and the value it waits for goes in its key:

```dart snippet="guides/dependent-queries.md#home-devices"
QueryObserverOptions<List<Device>> homeDevicesQuery(String? homeId) =>
    QueryObserverOptions(
      // The value the query waits for is part of its key.
      queryKey: DeviceKeys.all.append(<Object?>['home', homeId]),
      queryFn: (context) =>
          repository.homeDevices(homeId!, signal: context.signal),
      // No home yet: nothing to ask the server.
      enabled: homeId == null ? Enabled.no : Enabled.yes,
    );
```

Read the first query and hand what it gave you — or `null` — to the second.
While the home id is `null`, the second query is `pending` and not fetching
(`fetchStatus: idle`). When the account lands, the reader rebuilds with an id,
the options change, and the second query starts.

<Tabs groupId="call-style">
<TabItem value="context" label="context.query">

```dart snippet="guides/dependent-queries.md#screen"
@override
Widget build(BuildContext context) {
  final account = context.query(accountQuery());
  // null until the account is there — and until then, this one waits.
  final devices = context.query(
    homeDevicesQuery(account.dataOrNull?.homeId),
  );

  return switch ((account, devices)) {
    (QueryError(:final error), _) ||
    (_, QueryError(:final error)) =>
      Center(child: Text('Could not load your home: $error')),
    (_, QuerySuccess(:final data)) => DeviceListView(data),
    _ => const Center(child: CircularProgressIndicator()),
  };
}
```

</TabItem>
<TabItem value="builder" label="QueryBuilder">

```dart snippet="guides/dependent-queries.md#builder"
Widget myHome() => QueryBuilder<Account>(
      options: accountQuery(),
      builder: (context, account) => QueryBuilder<List<Device>>(
        // Rebuilt with the account's home once it is there.
        options: homeDevicesQuery(account.dataOrNull?.homeId),
        builder: (context, devices) => homeView(account, devices),
      ),
    );
```

</TabItem>
<TabItem value="mixin" label="QueryMixin">

```dart snippet="guides/dependent-queries.md#mixin"
class _MyHomeMixinState extends State<MyHomeMixin> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final account = watchQuery(accountQuery());
    final devices = watchQuery(homeDevicesQuery(account.dataOrNull?.homeId));

    return homeView(account, devices);
  }
}
```

</TabItem>
<TabItem value="controller" label="QueryController">

```dart snippet="guides/dependent-queries.md#controller"
class _MyHomeControllersState extends State<MyHomeControllers> {
  late final QueryController<Account, Account> _account;
  late final QueryController<List<Device>, List<Device>> _devices;

  @override
  void initState() {
    super.initState();
    final client = QueryClientProvider.read(context);
    _account = QueryController.create(client, accountQuery());
    _devices = QueryController.create(
      client,
      homeDevicesQuery(_account.value.dataOrNull?.homeId),
    );
    // No build to re-run the options: when the account changes, hand the
    // devices controller its new ones.
    _account.addListener(_followAccount);
  }

  void _followAccount() {
    _devices.setOptions(homeDevicesQuery(_account.value.dataOrNull?.homeId));
  }

  @override
  void dispose() {
    _account.removeListener(_followAccount);
    _account.dispose();
    _devices.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[_account, _devices]),
        builder: (context, _) => homeView(_account.value, _devices.value),
      );
}
```

A controller has no build that re-creates its options, so the dependency is
spelled out: a listener on the first controller hands the second its new
options through `setOptions`.

</TabItem>
</Tabs>

Why the home id belongs in the key: without it, the waiting query and the
running one would be the same cache entry, and a user who switches homes
would see the first home's devices under the second's name until the refetch
lands.

The showcase's *dependent queries* screen loads a post's comments only once
the post is there. Press *Choose post 1*: until the post lands, the
*Comments* card shows *waiting for the post* and `comments enabled=false`,
then it fetches. Tick *Pause comments* and choose another post: the card
says *Paused: no request until the box is unticked.*

<LiveDemo feature="dependent-queries" />

## `Enabled`

| | |
|---|---|
| `Enabled.yes` | the default: the query fetches on its own |
| `Enabled.no` | it never fetches on its own |
| `Enabled.when((query) => …)` | decided per query each time it matters |

`Enabled.yes` and `Enabled.no` are constants, not constructors. A predicate
given to `Enabled.when` is asked often; keep it cheap and free of side
effects. It is asked again each time the reader's options are applied —
every build for `context.query` and `watchQuery`, a rebuild by its parent for
a builder widget, a `setOptions` for a controller — so it may read state
outside the query, a setting or a feature flag, and that is when a change is
picked up.

A disabled query that already has data keeps it and stays `success`. See
[disabling queries](disabling-queries.md) for everything a disabled query
still does.

## Dependent queries are a waterfall

The second request cannot start before the first has answered. That is
inherent to the data, but it is still two round trips; if the server can
answer both at once — an `/me/home/devices` endpoint — one query beats two.
And if the first value is known earlier than the first query answers — the
home id is in the login response — seed it with `setQueryData` or put it in
the route, and the second query starts at once. See [request
waterfalls](request-waterfalls.md).

## Traps

- **A `!` without `enabled`.** `homeId!` in the query function is safe only
  because the query is disabled while `homeId` is `null`. Drop the
  `enabled` and the function throws on its first run.
- **A spinner for a query that is not running.** A disabled query is pending
  and idle. Match on `isFetching` or on the first query's state when "not
  started" deserves its own message, as the showcase does.
- **An error from the first query leaves the second pending for ever.** Show
  the first query's error — the screen above matches either failure first.

:::note[In React Query]
The same pattern as `enabled: !!userId` in TanStack Query. `enabled` takes
`Enabled.yes`, `Enabled.no` or `Enabled.when(…)` instead of a boolean or a
function, and there is no `skipToken` — `Enabled.no` covers it. See
[differences from TanStack Query](../reference/differences-from-tanstack.md).
:::
