---
title: Sign out and multiple accounts
sidebar_label: Sign out and multi-account
description: Give each signed-in user a fresh cache, empty it at sign-out without a refetch storm, warn about unsent writes, and keep several accounts apart in one client.
sidebar_position: 18
---

# Sign out and multiple accounts

**The problem.** Alice signs out and Bob signs in on the same phone. For a
moment, Bob's inbox shows Alice's messages from the cache. Or the sign-out
clears the cache while Alice's screens are still mounted, and they refetch
everything with a token that was just revoked, producing a burst of 401s.
Or a mail app shows several accounts at once and needs to forget one of them
without touching the rest.

**The recipe.** Tie the cache's lifetime to the session in the widget tree.
When the signed-in subtree goes away, its readers go first and the cache is
emptied after them. There are two ways to do that. Choose one:

- **A client per user** (preferred): a keyed `QueryClientProvider.create`.
  Another user is another key, so another client.
- **One client, cleared on the way out**: a shell widget that clears the
  shared client in its `dispose`.

Several accounts in one session is a different case. They share a client,
and each account's keys have a prefix of their own.

## The gate

The app's root decides between signed in and signed out from your session
state, wherever that is kept:

```dart title="lib/app/auth_gate.dart" snippet="cookbook/sign-out-and-multi-account.md#auth-gate"
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.userId});

  /// From your session state: `null` while nobody is signed in.
  final String? userId;

  @override
  Widget build(BuildContext context) => switch (userId) {
        null => const MaterialApp(home: SignInScreen()),
        final String id => SignedInScope(userId: id, child: const HomeApp()),
      };
}
```

## A client per user

`SignedInScope` is the keyed provider from [Dependency
injection](dependency-injection.md):

```dart snippet="excerpt: cookbook/dependency-injection.md#per-user"
Widget build(BuildContext context) => QueryClientProvider.create(
      key: ValueKey<String>(userId),
      create: () => QueryClient(defaultOptions: appDefaults),
      child: child,
    );
// …
```

At sign-out, `userId` becomes `null` and the gate builds the sign-in screen.
The signed-in subtree unmounts, children first, and the owned client is
cleared after its provider unmounts. At a switch from Alice to Bob, the new
key replaces the provider. Bob's screens mount on a new, empty client, and
Alice's screens are disposed, and then her client is cleared.

`clear()` empties both caches and cancels every fetch still in flight, so no
late answer lands in the cache after the user has gone.

## One client, cleared on the way out

When the client has to outlive the session (it is registered in get_it, or
code outside the tree holds it), clear it when the signed-in subtree goes:

```dart title="lib/app/signed_in_shell.dart" snippet="cookbook/sign-out-and-multi-account.md#shell"
/// Everything a signed-in user sees is below this widget, on a client the
/// whole app shares. When it goes, the user's cache goes with it.
class SignedInShell extends StatefulWidget {
  const SignedInShell({super.key, required this.child});

  final Widget child;

  @override
  State<SignedInShell> createState() => _SignedInShellState();
}

class _SignedInShellState extends State<SignedInShell> {
  late final QueryClient _client;

  @override
  void initState() {
    super.initState();
    // Looked up while mounted: in dispose, the ancestors are out of reach.
    _client = QueryClientProvider.read(context);
  }

  @override
  void dispose() {
    // Flutter disposes children before their parent, so every reader below
    // is gone and nothing refetches what this empties.
    _client.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

The order is Flutter's own: a `State`'s `dispose` runs after its children's.
When `clear()` runs, no reader is left to refetch. Clearing from the
sign-out button instead would empty the cache while the screens are still
mounted, and each of them would create its entry again, and fetch, at its
next rebuild, poll or focus change.

Put `SignedInShell` in the signed-in branch of the gate, under the provider
that holds the shared client.

## Unsent writes

A write still pending at sign-out is lost, because `clear()` removes it.
Ask first:

```dart title="lib/features/settings/sign_out_button.dart" snippet="cookbook/sign-out-and-multi-account.md#unsaved-writes"
/// Asks before signing out over writes that have not gone through.
Future<bool> mayDropWrites(BuildContext context) async {
  final writing = QueryClientProvider.read(context).isMutating();
  if (writing == 0) return true;
  final drop = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('$writing changes are not saved yet'),
      content: const Text('Sign out anyway? They will be lost.'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Stay'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  return drop ?? false;
}
```

`isMutating()` counts every pending mutation, including paused ones waiting
for the network. Call it before changing the session:
`if (await mayDropWrites(context)) session.signOut();`.

## Several accounts in one client

A mail app that shows two accounts at once keeps both in one cache, each
under its own prefix:

```dart title="lib/data/account_keys.dart" snippet="cookbook/sign-out-and-multi-account.md#account-keys"
abstract final class AccountKeys {
  static QueryKey account(String userId) =>
      QueryKey(<Object?>['account', userId]);

  static QueryKey inbox(String userId) =>
      account(userId).append(<Object?>['inbox']);
}

/// Forget one account, and keep the others this client holds.
void forgetAccount(QueryClient client, String userId) => client.removeQueries(
      filters: QueryFilters(queryKey: AccountKeys.account(userId)),
    );
```

Removing one account's prefix leaves the other's entries alone. As on
[Disconnecting a device](device-and-iot-disconnect.md), remove after that
account's screens are gone, or they will create their entries again.

## Steps

1. Keep the session (a user id, a token) in your own state and switch the
   tree on it.
2. Choose the lifetime: a keyed `QueryClientProvider.create` per user, or a
   `SignedInShell` that clears a shared client.
3. Check `isMutating()` before signing out.
4. For multiple accounts, put every key under an account prefix and remove
   by prefix.

## Traps

- **Clearing in the button's `onPressed`.** The screens are still mounted.
  Until they go, each reader shows its last result, and the next rebuild
  creates its entry again and fetches, usually with a token that is already
  invalid.
- **A user id outside the key.** With a client per user, keys do not need
  the user id, because the whole cache is theirs. With a shared client, a
  key without it serves Alice's data to Bob.
- **Persisted snapshots.** When you save queries to disk (see [Offline first,
  and surviving a restart](offline-first-and-persistence.md)), delete the
  snapshot at sign-out too, or the next launch restores the previous user's
  data.
- **Tokens in the query function only.** A token change does not refetch
  anything by itself. A per-user client resolves this, because the new user's
  queries run on a new client.

## Variations

- **Switching accounts without signing out.** Key the scope by the active
  account id. Each switch then starts a new, empty cache. To keep both
  accounts warm, use a shared client with account prefixes instead.
- **Keep public data across users.** Put public, per-app data (feature
  flags, a product catalogue) on a client outside the user scope, and
  personal data on the per-user one. A widget reads from the nearest
  provider, so pass the outer client explicitly to the reads that need it.

:::note[In React Query]
The advice there is `queryClient.clear()` at sign-out, or a new
`QueryClient` per user. Both apply here, and the widget tree adds what React
does not have: a `dispose` that runs after the children's, which is the right
moment to clear. See [differences from TanStack
Query](../reference/differences-from-tanstack.md).
:::
