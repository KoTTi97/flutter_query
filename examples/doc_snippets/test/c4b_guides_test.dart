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

  test('reachability: a probe from before a resubscribe is not delivered',
      () async {
    final link = StreamController<bool>.broadcast();
    final answers = <Completer<bool>>[];
    Future<bool> probe() {
      final answer = Completer<bool>();
      answers.add(answer);
      return answer.future;
    }

    final stream = reachability(link.stream, probe);
    final first = stream.listen((_) {});
    link.add(true);
    await pumpEventQueue();
    expect(answers, hasLength(1));
    await first.cancel();

    final seen = <bool>[];
    final second = stream.listen(seen.add);
    answers.single.complete(true);
    await pumpEventQueue();
    expect(seen, isEmpty, reason: 'nothing says the link is still up');

    await second.cancel();
    await link.close();
  });
}
