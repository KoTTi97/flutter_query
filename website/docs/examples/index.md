---
title: Examples
description: Every feature as a live screen you can run in the browser, one whole small app that composes them, and the package's one-file example.
---

import ExampleGrid from '@site/src/components/ExampleGrid'

# Examples

Each page below is one screen of the showcase app: what it demonstrates, a
live demo that runs in your browser against an in-memory backend (nothing is
downloaded until you press *Run*), what to try in it, and the source of the
screen, taken from the compiled file. Every screen draws its cache entries'
state as it changes, so you can watch what the library does, not just what the
widget shows.

A demo is a Flutter web app in a frame, and it behaves like one: clicking
outside it and back in is a window focus change, so a stale query refetches
on the way back in, as it would in your app. A `fetches=` count a page
promises can therefore be one higher if you clicked away in between.

## Whole apps

- **[Task manager](./task-manager.mdx)**: one ordinary small app, a to-do
  list against a slow backend that fails on cue. Where the showcase lets you
  look a feature up, this shows how six of them compose: a list two widgets
  share, a detail screen, optimistic writes with rollback, and a reminder that
  is accepted before it is confirmed.
- **[One-file tour](./one-file-tour.mdx)**: the package's own example, a
  provider, one query read two ways and a mutation, in a single file with no
  server.

## Basics

<ExampleGrid ids={['simple', 'basic', 'four-call-styles']} />

## Queries

<ExampleGrid
  ids={[
    'default-query-function',
    'dependent-queries',
    'parallel-queries',
    'query-collections',
    'combine',
    'initial-and-placeholder',
    'select-and-sharing',
  ]}
/>

## Paging

<ExampleGrid ids={['pagination', 'load-more', 'max-pages']} />

## Mutations

<ExampleGrid ids={['mutations', 'optimistic-updates', 'mutation-cancel', 'mutation-state']} />

## Cache

<ExampleGrid ids={['prefetching', 'stale-and-gc', 'invalidation-and-filters', 'playground', 'cache-inspector']} />

## Network

<ExampleGrid ids={['auto-refetching', 'retry', 'cancellation', 'offline', 'focus-refetch']} />

## Advanced

<ExampleGrid ids={['build-when', 'global-callbacks', 'diagnostics']} />

## Running them yourself

Both apps live in the repository with a small backend each. The showcase:

```bash
cd examples/showcase/server && npm install && npm run dev
```

```bash
cd examples/showcase && flutter run -d chrome
```

The task manager runs on the web and iOS:

```bash
cd examples/task_manager/server && npm install && npm run dev
```

```bash
cd examples/task_manager && flutter run -d chrome
```

Either app also runs with no server, as the live demos do:
`flutter run -d chrome --dart-define=QK_BACKEND=inmemory`.

How all of them are tested, from widget tests to a browser suite against the
real backend, is on [how the examples are built](../project/examples.md).
