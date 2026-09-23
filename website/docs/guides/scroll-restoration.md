---
title: Scroll restoration
description: A list comes back where it was when its data is still cached — and what Flutter needs from you to put the scroll position back.
---

{/* depth: todo */}
{/* demo: load-more */}

# Scroll restoration

Coming back to a list is instant when its data is still in the cache: the
first build has the rows, so there is no spinner and no empty frame. That is
what makes restoring a scroll position possible at all — a position into a
list that is still loading has nothing to point at.

The data stays cached for `gcTime` after the list's screen goes — five
minutes by default; see [caching](caching.md). An
[infinite query](infinite-queries.md) keeps every page it had loaded, up to
`maxPages`.

## The position itself

The position is Flutter's, not the cache's:

- **Pushed routes** keep the route below alive, scroll position and all;
  popping back needs nothing.
- **Tabs and page views** that rebuild their children lose the position. Give
  the scrollable a `PageStorageKey`, and Flutter's `PageStorage` puts it back
  when the list is built again — with its rows, since they come from the
  cache.
- **Across app restarts**, Flutter's state restoration
  (`RestorationMixin`, `restorationId` on the scrollable) restores the
  position; the data comes from a fresh fetch, since the cache lives in
  memory.

A stale list refetches behind the restored position; structural sharing keeps
the unchanged rows' instances, so a row widget that compares its data can
skip the work.
