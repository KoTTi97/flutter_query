---
title: Cancelling mutations
description: mutationFnWithContext, the signal cancel() cancels, and why cancelling a write fails it rather than reverting it.
---

# Cancelling mutations

A firmware upload takes a minute; the user picks the wrong file and wants to
stop it. A long export should stop when the user closes its dialog. A write
can be cancelled — but what cancelling a write *means* is different from what
it means for a query, and this page is about that difference.

`mutationFn` takes the variables and nothing else. When the function needs to
know about its run — to abort its request, or to read what `onMutate` kept —
give `mutationFnWithContext` instead: the same function with a second
argument.

```dart snippet="guides/cancelling-mutations.md#function-context"
MutationOptions<Task, String, Task> renameWithContext(
        QueryClient client, String id) =>
    MutationOptions(
      onMutate: (name) {
        final before = client.getQueryData<Task>(taskKey(id))!;
        client.setQueryData<Task>(taskKey(id), before.copyWith(name: name));
        return before;
      },
      // The cache already says `name`. What it said before is in the context,
      // and so is the signal `cancel()` cancels.
      mutationFnWithContext: (name, context) => api.rename(
        id,
        name,
        from: context.onMutateResult?.name,
        signal: context.signal,
      ),
      onError: (_, __, ___, before) {
        if (before != null) client.setQueryData<Task>(taskKey(id), before);
      },
      onSettled: (_, __, ___, ____, _____) => client.invalidateQueries(
        filters: QueryFilters(queryKey: taskKey(id)),
      ),
    );
```

The context holds `client`, `meta` and `mutationKey`, as in TanStack Query,
and two more:

- **`onMutateResult`**, typed. `onMutate` runs *before* the function, so after
  an optimistic patch the cache no longer says what was there. A function that
  compares "before" with "wanted" and reads the cache will find no difference
  and send nothing. What `onMutate` kept is the answer.
- **`signal`**, cancelled by `cancel()` — on the controller, the observer or
  the `Mutation`.

## Cancelling is failing

`cancel()` fails the run with a `CancelledError`: no further retry, `onError`
and `onSettled` run, and the scope moves on. So the rollback you already wrote
rolls it back, and the invalidation you already wrote finds out what the
server really did — which nobody can know otherwise, because the request may
have arrived. That is why it is not the quiet return to the previous state
that cancelling a *query* is: a write has no previous state to return to.

- A function that honours the signal aborts its transport; one that does not
  runs on unobserved, and its result is discarded.
- `mutateAsync` throws that `CancelledError` at its call site like any other
  failure, so a `mutateAsync` nobody awaits needs a handler (or use `mutate`,
  which has the controller hold the error instead).
- Only `cancel()` cancels the signal: removing a mutation from the cache or
  disposing its controller leaves an attempt in flight to settle.
- A mutation that is paused, queued behind its scope or still in `onMutate`
  fails the same way without its function ever running. So does one restored
  `pending` from persistence that has not been resumed yet.
- Once the function has returned, `cancel()` does nothing: the write went
  through.

One function per mutation — both at once fails an assertion at the options
literal in a debug build, and is an `ArgumentError` when the client resolves
them in a release build — and a function registered with
`setMutationDefaults` has no context form.

## A firmware update, cancellable

The button starts the upload, turns into *Cancel update* while it runs, and
after a cancel offers to try again. The mutation passes its signal on to the
repository:

```dart snippet="guides/cancelling-mutations.md#upload"
MutationOptions<Device, Uint8List, void> firmwareUploadMutation(
  QueryClient client,
  String id,
) =>
    MutationOptions.simple(
      mutationFnWithContext: (image, context) =>
          devices.uploadFirmware(id, image, signal: context.signal),
      // Cancelled or not, ask the device what it is running now.
      onSettled: (_, __, ___, ____, _____) => client.invalidateQueries(
        filters: QueryFilters(queryKey: DeviceKeys.detail(id)),
      ),
    );

class FirmwareUpdateButton extends StatelessWidget {
  const FirmwareUpdateButton({
    super.key,
    required this.deviceId,
    required this.image,
  });

  final String deviceId;
  final Uint8List image;

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    final upload = context.mutation(firmwareUploadMutation(client, deviceId));
    return switch (upload.value) {
      MutationPending() => OutlinedButton(
          onPressed: upload.cancel,
          child: const Text('Cancel update'),
        ),
      MutationError(error: CancelledError()) => FilledButton(
          onPressed: () => upload.mutate(image),
          child: const Text('Update cancelled — try again'),
        ),
      _ => FilledButton(
          onPressed: () => upload.mutate(image),
          child: const Text('Install update'),
        ),
    };
  }
}
```

Cancelling fails the run, so `onSettled` still invalidates the device's
detail — the device may have received half an image and rebooted, or all of
it, and only asking it tells you which. The `CancelledError` in the result is
what lets the button tell "the user stopped it" from "it failed".

The repository hands the signal to its HTTP client. With dio, a `CancelToken`
bridges the two:

```dart snippet="prose-only: needs dio, which the docs package does not depend on"
// lib/data/device_repository.dart
Future<Device> uploadFirmware(
  String id,
  Uint8List image, {
  required QueryCancelToken signal,
}) async {
  final token = CancelToken();
  signal.onCancel(token.cancel);
  final response = await dio.put<Map<String, Object?>>(
    '/devices/$id/firmware',
    data: Stream.fromIterable([image]),
    options: Options(headers: {Headers.contentLengthHeader: image.length}),
    cancelToken: token,
  );
  return Device.fromJson(response.data!);
}
```

With the `http` package, send an `AbortableRequest` whose `abortTrigger`
completes from `signal.onCancel`. A repository that ignores the signal still
works: its request runs on unobserved, and whatever it returns is discarded.

The `mutation-cancel` screen holds each rename on the server for three
seconds. Type a new title, press *Rename*, then *Cancel* before the three
seconds are up: the result reads `error=cancelled`, the optimistic title
rolls back to the old one, and the refetch shows what the server kept.

<LiveDemo feature="mutation-cancel" />

:::note[In React Query]
TanStack Query cannot cancel a mutation: `useMutation` has no `cancel`, and
its `mutationFn` receives no signal. `mutationFnWithContext` and `cancel()`
are additions of this library, built so that a cancel runs the error path you
already wrote.
:::
