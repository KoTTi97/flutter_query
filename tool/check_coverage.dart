// Reads an lcov file and fails when its line coverage is below a floor.
//
//   dart run tool/check_coverage.dart <lcov.info> <floor-percent> [--files]
//
// The lcov file comes from `format_coverage --lcov --report-on=lib` (the
// core) or `flutter test --coverage` (the binding). `--files` prints one line
// per source file, lowest coverage first. Only `DA:` records are counted —
// a line with a hit count above zero is covered — so the figure is the same
// one `genhtml` would print, without depending on it.
import 'dart:io';

void main(List<String> args) {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.length != 2) {
    stderr.writeln(
      'usage: dart run tool/check_coverage.dart <lcov.info> <floor> [--files]',
    );
    exit(64);
  }
  final file = File(positional[0]);
  final floor = double.tryParse(positional[1]);
  if (!file.existsSync() || floor == null) {
    stderr.writeln('No lcov file at ${file.path}, or floor is not a number.');
    exit(64);
  }

  final perFile = parseLcov(file.readAsStringSync());
  var found = 0;
  var hit = 0;
  for (final counts in perFile.values) {
    found += counts.found;
    hit += counts.hit;
  }
  if (found == 0) {
    stderr.writeln('${file.path} records no lines.');
    exit(1);
  }

  if (args.contains('--files')) {
    final rows = perFile.entries.toList()
      ..sort((a, b) => a.value.percent.compareTo(b.value.percent));
    for (final row in rows) {
      stdout.writeln(
        '${row.value.percent.toStringAsFixed(1).padLeft(6)} %  '
        '${'${row.value.hit}/${row.value.found}'.padLeft(9)}  '
        '${_shortPath(row.key)}',
      );
    }
  }

  final percent = hit * 100 / found;
  stdout.writeln(
    '${file.path}: $hit / $found lines = ${percent.toStringAsFixed(2)} % '
    '(floor $floor %)',
  );
  if (percent < floor) {
    stderr.writeln('Line coverage fell below the floor.');
    exit(1);
  }
}

/// The path from `lib/` on, which is what a reader recognises.
String _shortPath(String path) {
  final at = path.lastIndexOf('lib/');
  return at < 0 ? path : path.substring(at);
}

/// Line counts of one source file.
class LineCounts {
  int found = 0;
  int hit = 0;

  double get percent => found == 0 ? 100 : hit * 100 / found;
}

/// Parses lcov text into per-file counts. A line listed twice (two test
/// isolates, say) counts once, and is covered if any record hit it.
Map<String, LineCounts> parseLcov(String text) {
  final lines = <String, Map<int, bool>>{};
  Map<int, bool>? current;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('SF:')) {
      current = lines.putIfAbsent(line.substring(3), () => {});
    } else if (line.startsWith('DA:') && current != null) {
      final parts = line.substring(3).split(',');
      final number = int.parse(parts[0]);
      final count = int.parse(parts[1]);
      current[number] = (current[number] ?? false) || count > 0;
    } else if (line == 'end_of_record') {
      current = null;
    }
  }
  return {
    for (final entry in lines.entries)
      entry.key: LineCounts()
        ..found = entry.value.length
        ..hit = entry.value.values.where((covered) => covered).length,
  };
}
