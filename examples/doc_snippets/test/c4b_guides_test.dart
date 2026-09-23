import 'dart:async';

import 'package:doc_snippets/c4b_guides.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reachability: a probe that answers after the link dropped is ignored',
      () async {
    final link = StreamController<bool>();
    final answers = <Completer<bool>>[];
    Future<bool> probe() {
      final answer = Completer<bool>();
      answers.add(answer);
      return answer.future;
    }

    final seen = <bool>[];
    final subscription = reachability(link.stream, probe).listen(seen.add);

    link.add(true);
    await pumpEventQueue();
    expect(answers, hasLength(1), reason: 'the link came up: one probe');

    link.add(false);
    await pumpEventQueue();
    expect(seen, [false]);

    answers.single.complete(true);
    await pumpEventQueue();
    expect(seen, [false], reason: 'the old probe must not report online');

    await subscription.cancel();
    await link.close();
  });

  test('reachability: online once the link is up and the probe answers',
      () async {
    final link = StreamController<bool>();
    final seen = <bool>[];
    final subscription =
        reachability(link.stream, () async => true).listen(seen.add);

    link.add(true);
    await pumpEventQueue();
    expect(seen, [true]);

    await subscription.cancel();
    await link.close();
  });

  test('reachability: rechecks faster than the probe still give answers',
      () async {
    final link = StreamController<bool>();
    Future<bool> slowProbe() =>
        Future.delayed(const Duration(milliseconds: 30), () => true);
    final seen = <bool>[];
    final subscription = reachability(link.stream, slowProbe,
            recheck: const Duration(milliseconds: 5))
        .listen(seen.add);

    link.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(seen, [true]);

    await subscription.cancel();
    await link.close();
  });

  test('reachability: a probe that hangs or throws counts as unreachable',
      () async {
    final link = StreamController<bool>();
    var calls = 0;
    Future<bool> badProbe() {
      calls++;
      return calls == 1
          ? Completer<bool>().future // never answers
          : Future<bool>.error(StateError('no route'));
    }

    final seen = <bool>[];
    final subscription = reachability(link.stream, badProbe,
            recheck: const Duration(milliseconds: 5),
            timeout: const Duration(milliseconds: 20))
        .listen(seen.add);

    link.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(seen, [false]);
    expect(calls, greaterThan(1),
        reason: 'a hung probe does not block rechecks');

    await subscription.cancel();
    await link.close();
  });

  test('reachability: nothing is probed after the listener leaves', () async {
    final link = StreamController<bool>();
    var calls = 0;
    final subscription = reachability(link.stream, () async {
      calls++;
      return true;
    }, recheck: const Duration(milliseconds: 5))
        .listen((_) {});

    link.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await subscription.cancel();
    final before = calls;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(calls, before);

    await link.close();
  });
}
