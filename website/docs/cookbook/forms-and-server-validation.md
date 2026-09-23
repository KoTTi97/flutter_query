---
title: Forms and server validation
description: An edit form driven by a mutation — disabled while saving, the server's field errors next to the fields, the cache updated from the response, and the screen closed on success.
---

# Forms and server validation

An edit form for a product. The app checks what it can (a name is required, a
price is a number); the server checks the rest (the name is already taken) and
answers 422 with an error per field. While the save is on its way the fields
and the button are disabled; a refusal puts the server's message under the
field it concerns, and typing into that field clears it; any other failure
says so above the form; a success updates the cache and closes the screen. A
mutation already holds every piece of state this needs — pending, the error,
the saved product — so the form keeps none of its own.

## The finished code

The mutation, with what a successful save does to the cache:

```dart snippet="cookbook/forms-and-server-validation.md#mutation" title="lib/features/products/product_mutations.dart"
MutationOptions<Product, ProductDraft, void> saveProductMutation(
  QueryClient client,
  ProductApi api,
) =>
    MutationOptions.simple(
      mutationKey: QueryKey(const <Object?>['products', 'save']),
      mutationFn: api.save,
      onSuccess: (product, _, __) {
        // The response is the product as saved: the detail has it now …
        client.setQueryData<Product>(ProductKeys.detail(product.id), product);
        // … and every list may have changed order or membership.
        return client.invalidateQueries(
          filters: QueryFilters(queryKey: ProductKeys.lists),
        );
      },
    );
```

The form, reading the mutation through the `QueryMixin` methods:

```dart snippet="cookbook/forms-and-server-validation.md#form" title="lib/features/products/product_form_screen.dart"
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.initial});

  /// The product being edited, or `null` for a new one.
  final Product? initial;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> with QueryMixin {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name);
  late final TextEditingController _price = TextEditingController(
    text: widget.initial == null ? '' : '${widget.initial!.price / 100}',
  );

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final save = watchMutation(
      saveProductMutation(queryClient, ProductApiScope.of(context)),
    );
    final result = save.value;

    // The server's verdict, read off the mutation's state: no second copy
    // of it to keep in sync.
    final serverErrors = switch (result) {
      MutationError(error: ValidationException(:final fieldErrors)) =>
        fieldErrors,
      _ => const <String, String>{},
    };

    void submit() {
      if (!_form.currentState!.validate()) return;
      save.mutate(
        ProductDraft(
          id: widget.initial?.id,
          name: _name.text.trim(),
          price: (double.parse(_price.text) * 100).round(),
        ),
        callbacks: MutateCallbacks<Product, ProductDraft, void>(
          // Runs only while this screen still listens, so the context is
          // still in the tree.
          onSuccess: (product, _, __) => Navigator.of(context).pop(product),
        ),
      );
    }

    // Typing into a field the server refused clears the refusal.
    void edited(String _) {
      if (result.isError) save.reset();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'New product' : 'Edit product'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (result case MutationError(:final error)
                when error is! ValidationException)
              Text('Could not save: $error'),
            TextFormField(
              controller: _name,
              enabled: !result.isPending,
              onChanged: edited,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: serverErrors['name'],
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Required' : null,
            ),
            TextFormField(
              controller: _price,
              enabled: !result.isPending,
              onChanged: edited,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Price',
                errorText: serverErrors['price'],
              ),
              validator: (value) =>
                  double.tryParse(value ?? '') == null ? 'A number' : null,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: result.isPending ? null : submit,
              child: result.isPending
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
```

The `ValidationException` comes from the API client in
[Wiring dio or package:http](wiring-dio-and-http.md): a 422 whose body has an
`errors` map becomes one, field by field.

## How it works

1. **Two kinds of validation, two places.** The `Form`'s `validator`s check
   what the app can know, before anything is sent. The server's verdict comes
   back as the mutation's error and is shown through each field's
   `errorText`. The two never compete: a field with a client-side problem is
   never sent.
2. **The field errors are derived, not stored.** `serverErrors` is a pattern
   match on the mutation's result: a `MutationError` whose error is a
   `ValidationException` yields its map, anything else an empty one. There is
   no `setState` that could miss a case.
3. **Typing clears the refusal.** `edited` calls `save.reset()` when the result
   is an error, which takes the mutation back to idle — and the derived
   `serverErrors` with it.
4. **Pending disables the form.** `result.isPending` turns off the fields and
   the button and puts a spinner in the button. A double tap cannot save
   twice.
5. **The response updates the cache.** The server answers with the product as
   saved. `onSuccess` in the options writes it to the detail entry, so the
   detail screen behind the form shows the new name without a request, and
   invalidates every list, whose order or membership may have changed. It
   returns the invalidation's future, so the mutation stays pending until the
   lists have refetched — the screen closes on current data.
6. **Closing is a per-call callback.** `onSuccess` in `MutateCallbacks` runs
   after the options' `onSuccess`, and only while this screen still listens to
   the mutation. If the user has already left, it does not run, and there is
   no `Navigator` call on a context that is gone.

## Awaiting instead of callbacks

When the code that saves is not the widget that reads the mutation — a button
elsewhere, or a view model — `mutateAsync` returns the saved product or
throws:

```dart snippet="cookbook/forms-and-server-validation.md#mutate-async" title="lib/features/products/save_and_report.dart"
Future<void> saveAndReport(
  MutationController<Product, ProductDraft, void> save,
  ProductDraft draft,
  ScaffoldMessengerState messenger,
) async {
  try {
    final product = await save.mutateAsync(draft);
    messenger.showSnackBar(SnackBar(content: Text('Saved ${product.name}')));
  } on ValidationException {
    // The form shows these next to the fields; nothing to add here.
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('Could not save: $error')));
  }
}
```

`mutate` never throws, which is why the form uses it; `mutateAsync` does, so
every call needs the `try`.

## Traps

- **A mutation's error stays until something clears it.** Without the `reset`
  in `edited`, the server's "name is taken" would sit under the field while the
  user types a new name. `reset` is also how a form clears an error it showed
  when it is reopened with the same mutation.
- **Do not keep the server errors in state.** Copying them into a field in
  `onError` means a second copy that has to be cleared on every retry, reset
  and reopening. Read them off the result.
- **Do not navigate from the options' `onSuccess`.** It runs even when the form
  is gone, and it has no `BuildContext`. The cache update belongs there; the
  navigation belongs in the call's callbacks.
- **The global error toast would fire too.** With the
  [global error snackbar](global-error-snackbar.md) installed, its mutation
  handler skips a `ValidationException` — the form shows it — but toasts every
  other failure. The form's own "Could not save" line then duplicates it; keep
  one of the two.
- **Mutations are not retried by default.** A save that failed on a timeout
  fails at once. That is on purpose: repeating a write is rarely safe. Opt in
  with `retry:` on the options for an idempotent `PUT`.

## Variations

- **Optimistic save.** For an edit that should appear before the server
  confirms it — a rename in place, a toggle — see
  [Optimistic updates](../guides/optimistic-updates.md).
- **A create form.** The same screen with `initial: null`: the draft has no id,
  the API client sends a `POST`, and the list invalidation brings the new
  product into the lists.
- **Another call style.** The same mutation reads through a
  `MutationController` held by a view model, or through `context.mutation` or a
  `MutationBuilder` in a stateless widget.

:::note[In React Query]
`useMutation` gives the same state: `isPending`, `error`, `reset`. Form
libraries like React Hook Form hold the client-side validation; here that is
Flutter's own `Form`, and the server's field errors are matched off the
mutation's sealed result.
:::

## See also

- [Mutations](../guides/mutations.md) — `mutate`, `mutateAsync`, the callbacks
  and the order they run in.
- [Updates from mutation responses](../guides/updates-from-mutation-responses.md)
  — writing the response into the cache.
- [Invalidations from mutations](../guides/invalidations-from-mutations.md) —
  what to invalidate after a write.
