---
title: Normalised data or one key per entity
sidebar_label: Normalised vs per-entity keys
description: When to cache a list plus one entry per item, when to cache a map by id, and how to keep unchanged items' instances either way.
sidebar_position: 19
---

# Normalised data or one key per entity

**The problem.** A contacts app shows a list, a detail screen and a favourites
strip, and all three show the same contact. Coming from Redux or Apollo, the
natural move is to normalise: one map of contacts by id and screens that look
up what they need. query_kit caches per key, not per entity. Two questions
follow. How do the list and the detail stay in agreement? And does a row
rebuild when an unrelated contact changes?

**The recipe.** Both shapes work. Choose by where the data comes from:

| The API gives you | Cache it as | Why |
|---|---|---|
| A list endpoint and a detail endpoint | A list key plus one key per entity, the list seeding the details | Every screen reads what its endpoint returns. Invalidation works per key. |
| One endpoint answering entities by id | One key holding a `Map` by id, with a sharing hook | The server already normalised. Rows `select` their entity. |
| Entities by id *plus* an order | One key holding a class that implements `StructurallyShareable` | Same as the map, and the order survives. |

The cache does not normalise across keys. A contact that appears under two
keys is two copies. The recipes below keep those copies in agreement where
it matters, and keep rebuilds narrow in every case.

## One key per entity

```dart title="lib/data/contact_queries.dart" snippet="cookbook/normalised-vs-per-entity-keys.md#per-entity"
abstract final class ContactKeys {
  static final QueryKey all = QueryKey(<Object?>['contacts']);
  static final QueryKey list = all.append(<Object?>['list']);
  static final QueryKey byId = all.append(<Object?>['by-id']);

  static QueryKey detail(String id) => all.append(<Object?>['detail', id]);
}

QueryObserverOptions<List<Contact>> contactListQuery(QueryClient client) =>
    QueryObserverOptions(
      queryKey: ContactKeys.list,
      queryFn: (context) async {
        final contacts = await contactsApi.list(signal: context.signal);
        // Every contact is also an entry of its own, seeded fresh, so the
        // detail screen opens without a request and later list fetches
        // keep it current.
        for (final contact in contacts) {
          client.setQueryData<Contact>(ContactKeys.detail(contact.id), contact);
        }
        return contacts;
      },
    );

QueryObserverOptions<Contact> contactQuery(String id) => QueryObserverOptions(
      queryKey: ContactKeys.detail(id),
      queryFn: (context) => contactsApi.get(id, signal: context.signal),
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    );
```

The list fetch writes every contact into its own entry with `setQueryData`.
The detail screen then opens with data and no request. Each later list fetch
updates those entries, so the detail is at most as old as the last list.
After an edit, invalidate the contact's detail key and the list key, or
invalidate `ContactKeys.all` for both.

A seeded entry counts as fresh from the moment it is written. With the
detail's 30-second `staleTime`, opening a contact right after the list loads
costs nothing, and opening it later refetches as usual. To let the detail
show the list's copy without it counting as fresh, seed through
`initialData` with the list's `dataUpdatedAt` instead (see [Initial query
data](../guides/initial-query-data.md)).

## A map by id

Structural sharing keeps a `Map` whole when it is deeply equal and replaces
it whole otherwise. One changed contact would replace every contact's
instance. A `structuralSharing` hook shares entry by entry instead:

```dart title="lib/data/contact_queries.dart" snippet="cookbook/normalised-vs-per-entity-keys.md#share-by-id"
/// A structuralSharing hook for a normalised map: an unchanged contact keeps
/// the instance the cache already holds, and nothing changed at all keeps the
/// whole map.
Map<String, Contact> shareById(
  Map<String, Contact>? previous,
  Map<String, Contact> next,
) {
  if (previous == null) return next;
  var changed = previous.length != next.length;
  final shared = <String, Contact>{};
  for (final MapEntry(:key, :value) in next.entries) {
    final kept = previous[key];
    if (kept == value) {
      shared[key] = kept!;
    } else {
      shared[key] = value;
      changed = true;
    }
  }
  return changed ? shared : previous;
}

QueryObserverOptions<Map<String, Contact>> contactsByIdQuery() =>
    QueryObserverOptions(
      queryKey: ContactKeys.byId,
      queryFn: (context) async => <String, Contact>{
        for (final contact in await contactsApi.list(signal: context.signal))
          contact.id: contact,
      },
      structuralSharing: shareById,
    );
```

A row reads its one contact with `select` and rebuilds only when that contact
changes:

```dart title="lib/features/contacts/contact_row.dart" snippet="cookbook/normalised-vs-per-entity-keys.md#row"
class ContactRow extends StatelessWidget {
  const ContactRow({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final contact = context.selectQuery(
      contactsByIdQuery().withSelect((byId) => byId[id]),
      // A refetch that leaves this contact alone rebuilds nothing here.
      buildWhen: (previous, current) =>
          previous.dataOrNull != current.dataOrNull,
    );
    return ListTile(title: Text(contact.dataOrNull?.name ?? '…'));
  }
}
```

`select` narrows what the row reads, and `buildWhen` narrows what it
rebuilds for. A result carries more than data (its fetch status, its update
time), so without `buildWhen` every refetch would still rebuild every row.
[Render optimisations](../guides/render-optimizations.md) explains the
difference.

## Entities plus an order

Many APIs answer `{ "byId": {…}, "order": [...] }`. A class holding both is
a leaf to structural sharing unless it takes part, and taking part is one
method:

```dart title="lib/data/contact_book.dart" snippet="cookbook/normalised-vs-per-entity-keys.md#contact-book"
/// The normalised shape many APIs answer with: entities by id, plus an order.
@immutable
class ContactBook implements StructurallyShareable<ContactBook> {
  const ContactBook({required this.byId, required this.order});

  final Map<String, Contact> byId;
  final List<String> order;

  // Asked only when the two are not equal: share what did not change.
  @override
  ContactBook shareWith(ContactBook previous) => ContactBook(
        byId: shareById(previous.byId, byId),
        order: replaceEqualDeep(previous.order, order),
      );

  @override
  bool operator ==(Object other) =>
      other is ContactBook &&
      mapEquals(other.byId, byId) &&
      listEquals(other.order, order);

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(byId.values),
        Object.hashAll(order),
      );
}
```

`shareWith` is only called when the two values are not equal. It reuses the
map hook for the entities and the default walk for the order, which keeps the
order list's instance when the order did not change.

## Steps

1. Follow the endpoints. A list endpoint and a detail endpoint suggest one
   key per entity. A by-id endpoint suggests a map.
2. Give every model `==` and `hashCode`. Without them no sharing works,
   because every fetch looks like a change.
3. For a map, add a `structuralSharing` hook. For a class, implement
   `StructurallyShareable`.
4. Read rows with `select` plus `buildWhen` on the selected value.

## Traps

- **Normalising client-side from list responses.** Building your own
  entity store from several queries' results moves the invalidation problem
  into your code. Seed per-entity keys instead, and let each key refetch.
- **A map without a hook.** It looks fine, because `==` still holds after an
  unrelated change. But every contact's instance is new, and anything that
  compares with `identical` (a memo, a list diff) sees everything as changed.
- **A hook that returns `previous` too eagerly.** `shareById` returns
  `previous` only when every entry and the length are unchanged. Returning it
  when something changed puts old data in the cache without any error.
- **`select` without `buildWhen`.** The row still rebuilds on every
  refetch, even though its contact did not change.

## Variations

- **An infinite list.** Each page is a list, and lists are shared element by
  element, so a refetched page keeps its unchanged contacts. Seeding per-item
  keys works from the page loop in the same way.
- **Optimistic edits.** With per-entity keys, update the detail key and the
  list's element in `onMutate`. With a map, update one entry. See [Optimistic
  updates](../guides/optimistic-updates.md).

## See it run

The basic demo is the per-entity shape: a list of posts, and one key per post
for the detail. Open a post and go back. Its row is marked `cached` because
its own key now has an entry. Leave it alone for ten seconds and the mark
goes, because that one entry was garbage collected while the list's entry
stayed.

<LiveDemo feature="basic" height={640} />

:::note[In React Query]
TanStack Query does not normalise either, and suggests the same two answers:
seed detail queries from the list, or accept a copy per key. A
`structuralSharing` function works the same way. The Dart-specific part is
that maps and classes are not walked member by member, so a map by id or a
wrapper class needs the hook or `StructurallyShareable`. See [differences
from TanStack Query](../reference/differences-from-tanstack.md).
:::
