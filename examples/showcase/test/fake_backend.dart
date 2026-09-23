/// The widget tests' backend: the app's own [InMemoryBackend]
/// (`lib/demo/in_memory_backend.dart`), seeded from `server/seed.json` on disk
/// and with no latency, so a test steps time itself.
///
/// The class lives in `lib/` because the documentation site's live demos run
/// the app against it in the browser (`--dart-define=QK_BACKEND=inmemory`);
/// what stays here is the part only a test may do — read the seed with
/// `dart:io` — and the name every test file already imports.
library;

import 'dart:convert';
import 'dart:io';

import 'package:showcase/demo/in_memory_backend.dart';

export 'package:showcase/demo/in_memory_backend.dart';

class FakeBackend extends InMemoryBackend {
  FakeBackend({super.latency}) : super(seed: seed());

  static Map<String, Object?>? _seed;

  /// `server/seed.json`, found from the package root or the repo root.
  static Map<String, Object?> seed() => _seed ??= () {
        for (final candidate in <String>[
          'server/seed.json',
          'examples/showcase/server/seed.json',
        ]) {
          final file = File(candidate);
          if (file.existsSync()) {
            return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
          }
        }
        throw StateError(
            'server/seed.json not found from ${Directory.current}');
      }();
}
