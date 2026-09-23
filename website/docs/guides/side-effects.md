---
title: Side effects
description: QueryListener, InfiniteQueryListener and MutationListener — navigation and snackbars on a transition, never on mount and never during a build.
---

{/* depth: todo */}
{/* demo: global-callbacks */}

# Side effects

A snackbar, a navigation or an analytics event belongs to a *change* in a
result, not to a build. Three widgets run a callback on one:

`QueryListener`, `InfiniteQueryListener` and `MutationListener` run a callback
on a controller they **borrow** — the owner still disposes it — and never
rebuild their `child`.

```dart snippet="guides/side-effects.md#listener"
Widget queryListenerSample(QueryController<Task, Task> task) =>
    QueryListener<Task, Task>(
      controller: task,
      listenWhen: (previous, next) => previous.errorOrNull != next.errorOrNull,
      listener: (context, result) => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task unreachable')),
      ),
      child: const SizedBox.shrink(),
    );
```

Two properties make these safe for navigation and snackbars, which is the whole
point of having them:

- **Nothing fires on mount** — only later transitions.
- **Callbacks are delivered off the build phase**, so a result that arrives
  mid-build reaches the listener after the frame.

A rejected `listenWhen` still advances the comparison state, so the next
callback sees the transition it actually followed. (That is the opposite of
`buildWhen`, where `previous` is what was last *built* — the two fields have
genuinely different jobs.)

For a side effect of every query or mutation in the app — one error toast for
all of them — use the caches' [global callbacks](global-callbacks.md) instead.
