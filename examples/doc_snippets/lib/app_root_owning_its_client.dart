/// `getting-started/first-query.md`'s second root: the provider builds the
/// client and `clear()`s it when the tree comes down.
///
/// A separate file for the reason [app_root.dart] gives — one `main` per
/// library — and the page shows the whole entrypoint again rather than a
/// dangling widget expression, so the two roots diff against each other the
/// way a reader compares them.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'doc_snippets.dart';

// >>> getting-started/first-query.md#main-owning-its-client
void main() {
  runApp(
    QueryClientProvider.create(
      create: QueryClient.new,
      child: const MaterialApp(home: TasksScreen()),
    ),
  );
}
// <<<
