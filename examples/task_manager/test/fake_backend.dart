/// The tests' backend: the app's own [InMemoryBackend]
/// (`lib/demo/in_memory_backend.dart`), under the name every test file
/// already uses. Its latencies default to zero, so a test steps time itself.
///
/// The class lives in `lib/` because the documentation site embeds the app
/// running against it in the browser (`--dart-define=QK_BACKEND=inmemory`).
library;

import 'package:task_manager/demo/in_memory_backend.dart';

export 'package:task_manager/demo/in_memory_backend.dart';

typedef FakeBackend = InMemoryBackend;
