import 'package:flutter_test/flutter_test.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/utils/plain_text_novel_parser.dart';

void main() {
  bool noise(String line) => PlainTextNovelParser.isOcrRubyNoise(line);

  group('崩れたルビ・傍点の行', () {
    test('記号の切れ端が間を空けて並ぶ行は消す', () {
      expect(noise('、　　　！　｜　　、　、'), isTrue);
      expect(noise('  ・   ・    ・  '), isTrue);
      expect(noise('ヽ'), isTrue);
    });

    test('2文字以下のかなが間を空けて3つ以上並ぶ行は消す', () {
      expect(noise('か　 ん　 じ'), isTrue);
      expect(noise('ルビ  ふ  り'), isTrue);
    });

    test('ふつうの文・台詞・三点リーダの行は残す', () {
      expect(noise('彼は空を見上げた。'), isFalse);
      expect(noise('「……」'), isFalse);
      expect(noise('……'), isFalse);
      expect(noise('――'), isFalse);
      expect(noise('・・・'), isFalse);
      expect(noise('！！'), isFalse);
      expect(noise('　'), isFalse);
      expect(noise('あ　い'), isFalse);
    });
  });

  test('設定を入れたときだけ、くずの行を本文から除く', () {
    const text = '一行目\n、　　！　｜\n二行目';
    String plain(List<NovelContentElement> elements) => [
      for (final e in elements)
        switch (e) {
          PlainText(:final text) => text,
          NewLine() => '/',
          _ => '',
        },
    ].join();
    expect(
      plain(PlainTextNovelParser.parse(text, removeOcrNoise: true)),
      '一行目/二行目',
    );
    expect(
      plain(PlainTextNovelParser.parse(text)),
      contains('｜'),
    );
  });
}
