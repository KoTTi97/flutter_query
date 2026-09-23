---
title: Query keys
description: QueryKey as a value type, hierarchical keys and prefix matching, key factories, and the parts that do not compare the way you expect.
---

{/* depth: todo */}
{/* demo: invalidation-and-filters */}

# Query keys

The cache stores, shares, refetches and invalidates data by its key. A
`QueryKey` is a list of parts:

```dart snippet="quick-start.md#key"
final QueryKey tasksKey = QueryKey(<Object?>['tasks']);
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

- `['tasks']` — the whole list
- `['tasks', 'detail', id]` — one task
- `['tasks', 'list', 'done']` — the list, filtered

Otherwise two different requests share one cache entry, and one of them shows
the other's data.

## Hierarchy and prefixes

Keys are hierarchical. The bulk operations — [invalidation](query-invalidation.md),
`refetchQueries`, `removeQueries`, `cancelQueries` — match a key as a
**prefix** unless you pass `exact: true`, so invalidating `['tasks']` reaches
every list and every detail under it. See [filters](filters.md).

## Key factories

Build keys in one place, from the most general part down, so a prefix is
always a real parent:

```dart snippet="guides/query-keys.md#key-factory"
abstract final class TaskKeys {
  static final QueryKey all = QueryKey(<Object?>['tasks']);

  static QueryKey list({required String filter}) =>
      all.append(<Object?>['list', filter]);

  static QueryKey detail(String id) => all.append(<Object?>['detail', id]);
}
```

`key.append(parts)` returns a new key with the parts added at the end.
Invalidate `TaskKeys.all` after any write to tasks, `TaskKeys.detail(id)`
after a write to one.

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
