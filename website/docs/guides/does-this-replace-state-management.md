---
title: Does this replace state management?
description: Server state and client state are different problems — what moves into the cache, what stays in your state-management package, and how the two meet.
---

{/* depth: todo */}
{/* demo: four-call-styles */}

# Does this replace state management?

For the part of your state that came from a server, mostly yes. For the rest,
no — and it does not try to.

## Two kinds of state

**Server state** lives somewhere else. You hold a copy that can go out of
date, that someone else can change, and that has to be fetched, cached,
refreshed and invalidated. That is this library's whole job.

**Client state** is yours alone: which tab is open, what is typed into a form,
whether a panel is expanded, a theme, a draft. It is never stale, because
nothing else owns it.

Most apps built with `provider`, `riverpod` or `bloc` hold both kinds in one
place, and most of the code is the first kind — loading flags, error fields,
refresh logic, "is this cached yet". Moving that into queries usually leaves
a much smaller client state behind, often small enough for `setState` and an
`InheritedWidget`.

## What moves

- A repository or bloc whose job is "fetch, keep, refresh" becomes a query
  options function and a key.
- Loading, error and "refreshing" flags become the [query
  result](queries.md).
- Manual refresh-after-write becomes an
  [invalidation](invalidations-from-mutations.md).
- A cache you wrote yourself — with its expiry — becomes
  [`staleTime` and `gcTime`](caching.md).

## What stays

Form input, navigation state, selections, feature flags, anything the server
never sees. Keep those in whatever you use today.

## How the two meet

- **Client state picks the query.** A selected filter or page number goes into
  the query's **key**, and the query follows it; see [query
  keys](query-keys.md).
- **A query is a listenable.** A `QueryController` is a
  `ValueListenable<QueryResult<T>>`, so `provider`, `riverpod`, `bloc` and
  signals packages can wrap it with whatever they already offer for a
  listenable; see [four ways to read a
  query](reading-queries-in-widgets.md#querycontroller).
- **Nothing here needs another package**, and nothing here competes for the
  same job as one: the binding depends on Flutter alone.
