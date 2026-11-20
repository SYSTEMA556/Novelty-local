import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/read_aloud/reading_dictionary.dart';
import 'package:path/path.dart' as p;

void main() {
  const work = 'local:abc';

  test('登録した表記を読みに置き換える', () {
    final dict = ReadingDictionary([
      const ReadingRule(surface: '天音', reading: 'あまね'),
    ]);
    expect(dict.apply('天音は笑った。'), 'あまねは笑った。');
  });

  test('長い表記を先に置き換える', () {
    final dict = ReadingDictionary([
      const ReadingRule(surface: '天音', reading: 'あまね'),
      const ReadingRule(surface: '天音川', reading: 'あまねがわ'),
    ]);
    expect(dict.apply('天音川の天音'), 'あまねがわのあまね');
  });

  test('置き換えた読みを、さらに置き換えない', () {
    final dict = ReadingDictionary([
      const ReadingRule(surface: '甲', reading: 'おつ'),
      const ReadingRule(surface: 'おつ', reading: 'へい'),
    ]);
    expect(dict.apply('甲'), 'おつ');
  });

  test('作品だけの登録はその作品でだけ効き、全体の登録より優先する', () {
    final dict = ReadingDictionary([
      const ReadingRule(surface: '主', reading: 'あるじ'),
      const ReadingRule(surface: '主', reading: 'ぬし', scope: work),
    ]);
    expect(dict.apply('主', scope: work), 'ぬし');
    expect(dict.apply('主', scope: 'local:other'), 'あるじ');
    expect(dict.apply('主'), 'あるじ');
  });

  test('正規表現の記号もそのままの文字として扱う', () {
    final dict = ReadingDictionary([
      const ReadingRule(surface: 'A.I.', reading: 'エーアイ'),
    ]);
    expect(dict.apply('A.I.とABC'), 'エーアイとABC');
  });

  test('同じ範囲・同じ表記を登録すると読みを差し替え、保存して読み戻せる', () async {
    final dir = Directory.systemTemp.createTempSync('reading_dict_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File(p.join(dir.path, 'reader', 'dict.json'));

    final dict = ReadingDictionary();
    await dict.loadFrom(file);
    await dict.put(const ReadingRule(surface: '天音', reading: 'あまね'));
    await dict.put(const ReadingRule(surface: '天音', reading: 'あまお'));
    expect(dict.apply('天音'), 'あまお');
    expect(dict.rules, hasLength(1));

    final reloaded = ReadingDictionary();
    await reloaded.loadFrom(file);
    expect(reloaded.apply('天音'), 'あまお');

    await reloaded.remove(reloaded.rules.single);
    expect(reloaded.apply('天音'), '天音');
  });
}
