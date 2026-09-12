/// `getting-started/first-query.md`'s first sample: a whole entrypoint.
///
/// Its own file, and not a function in `doc_snippets.dart`, because a Dart
/// library holds one `main` and the page shows two roots — one handed a
/// client, one owning it ([app_root_owning_its_client.dart]). Showing the
/// entrypoint rather than a fragment is the point of the sample: the question
/// the page answers is *where the provider goes*.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'doc_snippets.dart';

// >>> getting-started/first-query.md#main
void main() {
  runApp(
    QueryClientProvider(
      client: QueryClient(),
      child: const MaterialApp(home: TasksScreen()),
    ),
  );
}
// <<<
