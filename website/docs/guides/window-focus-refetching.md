---
title: App focus refetching
description: How AppLifecycleState maps to focus per platform, what refetchOnWindowFocus does on a phone, bringing your own focus source, and refetchMinBackgroundDuration.
---

{/* depth: todo */}
{/* demo: focus-refetch */}

# App focus refetching

When the app comes back to the foreground, every active query whose data is
stale refetches. That is `refetchOnWindowFocus`, and its default is
`RefetchOn.ifStale`:

| `RefetchOn` | On focus |
|---|---|
| `RefetchOn.ifStale` | the default: refetch if the data is stale |
| `RefetchOn.always` | refetch even if the data is fresh |
| `RefetchOn.never` | do not refetch |
| `RefetchOn.when(fn)` | decide per query, when the app comes back |

Set it per query, or for every query in the client's `QueryDefaults`. The same
type drives `refetchOnMount` and `refetchOnReconnect`.

Focus is a client-wide state. `QueryClientProvider` sets it for you from the
app lifecycle while it is mounted; without a provider, nothing sets it — see
[the mount contract](../important-defaults.md#the-mount-contract).

## App lifecycle → focus

Every lifecycle state the app reports is mapped onto the client's focus state,
which is what makes `refetchOnWindowFocus` mean anything on a phone.

| `AppLifecycleState` | Focused? |
|---|---|
| `resumed` | yes |
| `inactive` | **it depends** — see below |
| `hidden`, `paused`, `detached` | no |

:::note[`inactive` means two different things]
On **iOS, Android and Fuchsia**, `inactive` is a transient interruption: the
notification shade, a system dialog, the app switcher. Treating those as
"unfocused" would refetch the world on the way back, so `inactive` counts as
focused there.

On **macOS, Windows and Linux**, `inactive` is *the window lost focus* — a
different window is in front. That is exactly the case
`refetchOnWindowFocus` is named after, so `inactive` counts as **unfocused**
there.

The seam is `isAppShown`, if your app disagrees with either reading.
:::

`isAppShown` is a function from `AppLifecycleState` to "focused"; pass your
own when your app reads a state differently from the platform default.

### Bringing your own focus source

The client's focus manager has a seam of its own,
`client.focusManager.setEventListener(...)`, for a focus source that is not the
app lifecycle. **It is an alternative to the provider's listener, not a layer
on top of it.** Both write through `setFocused`, so with both installed the
last writer wins and neither can see the other's verdict. If you install one,
turn the other off:

```dart snippet="guides/window-focus-refetching.md#own-focus-source"
QueryClientProvider(
  client: client,
  // The lifecycle listener and a setEventListener adapter are two sources
  // of focus for one manager. Pick one.
  observeAppLifecycle: false,
  child: const MyApp(),
)
```

This is the same division TanStack Query has: the browser's `visibilitychange`
listener is the built-in default, and `setEventListener` is what a React
Native app calls with `AppState`. Here the `AppLifecycleListener` is the
built-in default and `setEventListener` is yours.

### Suppressing pointless refetches

`QueryClient(focusManager: AppFocusManager(refetchMinBackgroundDuration: …))` ignores a focus refetch
after an absence too short to matter — a glance at the notification shade is
not a reason to refetch the world.

TanStack Query always refetches. The default is `Duration.zero`, which
behaves the same, and it never blocks paused work from resuming.

## See it running

The `focus-refetch` screen shows every `RefetchOn` value and
`refetchMinBackgroundDuration`; see [examples](../examples/index.md).
