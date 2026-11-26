import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/web_pins.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('web_pins_test');
    WebPinsNotifier.fileOf = () async => File(p.join(dir.path, 'pins.json'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  WebPin pin(String workId, int episode, int minute) => WebPin(
    source: NovelSource.narou,
    workId: workId,
    title: '作品$workId',
    episode: episode,
    offset: 10,
    fraction: 0.5,
    snippet: '目印',
    createdAt: DateTime(2026, 1, 1, 0, minute),
  );

  test('1作品3つまで。4つ目はいちばん古いものと入れ替える', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(webPinsProvider.notifier);
    await container.read(webPinsProvider.future);
    await notifier.add(pin('a', 3, 1));
    await notifier.add(pin('a', 1, 2));
    await notifier.add(pin('a', 2, 3));
    await notifier.add(pin('b', 1, 4));
    await notifier.add(pin('a', 5, 5));

    final mine = notifier.pinsOf(NovelSource.narou, 'a');
    // 話の順に並び、最初に挟んだ第3話が外れている
    expect(mine.map((p) => p.episode), [1, 2, 5]);
    expect(notifier.pinsOf(NovelSource.narou, 'b'), hasLength(1));
  });

  test('保存して読み戻せる', () async {
    final first = ProviderContainer();
    await first.read(webPinsProvider.future);
    await first.read(webPinsProvider.notifier).add(pin('a', 2, 1));
    first.dispose();

    final second = ProviderContainer();
    addTearDown(second.dispose);
    final pins = await second.read(webPinsProvider.future);
    expect(pins.single.episode, 2);
    expect(pins.single.title, '作品a');
  });
}
