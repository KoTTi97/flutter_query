# query_kit_flutter example

A runnable, one-file tour of the binding.

> query_kit is an entirely AI-coded project: all code, tests and
> documentation were written by AI coding agents (Anthropic's Claude). A human
> maintainer set the goals and reviews releases, but did not write the code.
> It is a community port of TanStack Query, not affiliated with or endorsed
> by TanStack.

[`lib/main.dart`](lib/main.dart) sets up a `QueryClientProvider`, reads one
query in more than one call style, and runs a mutation that invalidates it.
There is no server — the "API" is a delay and a list — so it runs as it is:

```bash
flutter run
```

For more, see the [documentation](https://kotti97.github.io/flutter_query/docs/overview)
and the two larger example apps in the repository:
[the showcase](https://github.com/KoTTi97/flutter_query/tree/main/examples/showcase),
one screen per feature, and
[the task manager](https://github.com/KoTTi97/flutter_query/tree/main/examples/task_manager),
one small whole app.
