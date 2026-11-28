import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/read_aloud/english_reading.dart';

void main() {
  // kanalizer の代わり（呼ばれた単語を記録して、決まった読みを返す）
  final asked = <String>[];
  Future<List<String>> fake(List<String> words) async {
    asked.addAll(words);
    return [
      for (final w in words)
        switch (w) {
          'kanalizer' => 'カナライザー',
          'alice' => 'アリス',
          'excalibur' => 'エクスカリバー',
          _ => '',
        },
    ];
  }

  setUp(asked.clear);

  test('辞書にある言葉は推測しない', () async {
    expect(
      await readEnglishAsKana('Hello, the world', infer: fake),
      'ハロー, ザ ワールド',
    );
    expect(asked, isEmpty);
  });

  test('大文字の略語は1文字ずつ読む', () async {
    expect(await readEnglishAsKana('AIとNPC', infer: fake), 'エーアイとエヌピーシー');
    expect(await readEnglishAsKana('Aランク', infer: fake), 'エーランク');
    expect(asked, isEmpty);
  });

  test('辞書に無い言葉は kanalizer で推測する', () async {
    expect(
      await readEnglishAsKana('聖剣Excaliburとkanalizer', infer: fake),
      '聖剣エクスカリバーとカナライザー',
    );
    expect(asked, ['excalibur', 'kanalizer']);
  });

  test('全角のアルファベットも読む', () async {
    expect(await readEnglishAsKana('ｔｈｅ　ＮＰＣ', infer: fake), 'ザ　エヌピーシー');
  });

  test("所有の 's は元の言葉に「ズ」を足す", () async {
    expect(await readEnglishAsKana("Alice's", infer: fake), 'アリスズ');
    expect(asked, ['alice']);
  });

  test('推測できなければ1文字ずつ、推測が使えなくても読む', () async {
    expect(await readEnglishAsKana('zqxw', infer: fake), 'ゼットキューエックスダブリュー');
    expect(
      await readEnglishAsKana(
        'qwerty',
        infer: (_) async => throw Exception('使えない'),
      ),
      spellEnglish('qwerty'),
    );
  });

  test('英語が無ければそのまま', () async {
    expect(await readEnglishAsKana('吾輩は猫である。', infer: fake), '吾輩は猫である。');
  });
}
