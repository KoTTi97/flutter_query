---
title: Query keys
description: QueryKey as a value type, hierarchical keys and prefix matching, key factories, and the parts that do not compare the way you expect.
---

# Query keys

A cache needs a name for each thing it holds. Name two different requests
the same and one screen shows the other's data; name one request two ways and
it is fetched twice and invalidated half the time. Query keys are those
names, and most of what the cache does — sharing, refetching, invalidating —
it does by key.

A `QueryKey` is a list of parts, from the most general to the most specific:

```dart snippet="prose-only: the smallest key, shown before the factory that builds keys in the app"
final key = QueryKey(<Object?>['devices', 'detail', 'd1']);
```

## A value, not a string

A `QueryKey` is a **value type**: deep-frozen, and compared part by part.
Two keys built from equal parts *are* the same key, wherever they were built:

- strings, numbers, booleans and `null` compare with `==`;
- lists, maps and sets inside a key are compared deeply — `{'page': 1,
  'done': false}` and `{'done': false, 'page': 1}` are the same part;
- a `DateTime` part compares by instant, so UTC and local of one moment are
  one key;
- anything else compares with its own `==`, so a class used as a key part
  needs value equality.

There is no hashing function to configure. `key.debugString` is the readable
form, for logs.

## Everything the function depends on goes in the key

If the query function uses a variable, the key must contain it. A detail
query is keyed by its id; a filtered list by its filter:

- `['devices', 'list', {'room': null}]` — every device
- `['devices', 'list', {'room': 'kitchen'}]` — the kitchen's devices
- `['devices', 'detail', id]` — one device

Otherwise two different requests share one cache entry, and one of them shows
the other's data.

## Hierarchy and prefixes

Keys are hierarchical. The bulk operations — [invalidation](query-invalidation.md),
`refetchQueries`, `removeQueries`, `cancelQueries`, `resetQueries` — match a
key as a **prefix** unless you pass `exact: true`, so invalidating
`['devices']` reaches every list and every detail under it. See
[filters](filters.md).

A **map** part matches partially: a filter's map matches any key map that
holds the same entries, and more. So `['devices', 'list', {'room':
'kitchen'}]` in a filter reaches `['devices', 'list', {'room': 'kitchen',
'on': true}]` too. That is why filters go in a map rather than in positional
parts — a new filter field does not move the others.

## Key factories

Build keys in one place, from the most general part down, so a prefix is
always a real parent. In an app that is one file per data area, next to the
options functions that use it:

```dart snippet="guides/query-keys.md#device-keys"
// lib/data/device_keys.dart
abstract final class DeviceKeys {
  static final QueryKey all = QueryKey(<Object?>['devices']);

  static final QueryKey lists = all.append(<Object?>['list']);

  static QueryKey list({String? roomId}) => lists.append(<Object?>[
        <String, Object?>{'room': roomId},
      ]);

  static QueryKey detail(String id) => all.append(<Object?>['detail', id]);

  static QueryKey firmware(String id) =>
      detail(id).append(<Object?>['firmware']);
}
```

`key.append(parts)` returns a new key with the parts added at the end. The
firmware key sits *under* the device's detail key on purpose: invalidating one
device reaches its firmware as well. Each prefix then is an invalidation
target of its own:

```dart snippet="guides/query-keys.md#invalidate-by-prefix"
// One device: its detail, and its firmware, which sits under it.
await client.invalidateQueries(
  filters: QueryFilters(queryKey: DeviceKeys.detail(id)),
);

// Every device list, whatever room it is filtered by.
await client.invalidateQueries(
  filters: QueryFilters(queryKey: DeviceKeys.lists),
);

// Only the unfiltered list: the key exactly, nothing under it.
await client.invalidateQueries(
  filters: QueryFilters(queryKey: DeviceKeys.list(), exact: true),
);

// Everything about devices.
await client.invalidateQueries(
  filters: QueryFilters(queryKey: DeviceKeys.all),
);
```

The showcase's *invalidation and filters* screen holds a posts list, post
details on screen, and a post 3 that nobody observes. Press *Invalidate posts
prefix* and everything on screen under `[posts]` refetches while post 3 only turns
`isStale=true`; *Invalidate posts exactly* reaches the list alone, and
*Invalidate inactive too* refetches post 3 as well:

<LiveDemo feature="invalidation-and-filters" />

## One key, one data type

A key is bound to the type it was first used with; reading it as another type
throws `QueryDataTypeError`. Give data of a different shape a different key.
See [type safety in Dart](../dart-type-safety.md#one-key-one-exact-type).

## A record of a list is not a stable key part

A **record** compares its fields with their own `==`, and a `List`'s `==` is
identity. So a key part like `(ids: [1, 2],)` is new every time it is built,
never matches the key built from the same values again, and every read
fetches anew. Lists and maps as key *parts* are compared deeply; inside a
record they are not. Put the list in the key directly, or use a value class
with deep `==` and `hashCode`.

## Traps

- **A key that forgets a variable.** A key of `['devices']` for a function
  that filters by room makes every room share one entry. The rule has no
  exceptions: if `queryFn` reads it, the key holds it.
- **A key built from mutable state.** A key part is frozen when the key is
  built; mutate the list you passed in afterwards and the key does not
  change. Build the key from the current values each time.
- **Keys spelled in two places.** `['device', id]` in one file and
  `['devices', id]` in another are two entries and two requests. A factory
  makes that impossible.

:::note[In React Query]
Query keys are arrays hashed with `hashKey`. Here a `QueryKey` is a value
type compared part by part, with no hashing function to configure, and a
`queryKeyHashFn` does not exist. Prefix and partial map matching behave as
`partialMatchKey` does. See [differences from TanStack
Query](../reference/differences-from-tanstack.md).
:::
