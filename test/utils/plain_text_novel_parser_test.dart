import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/utils/plain_text_novel_parser.dart';

void main() {
  group('PlainTextNovelParser.decode', () {
    test('BOMなしUTF-8をデコードできる', () {
      final bytes = Uint8List.fromList(utf8.encode('吾輩は猫である'));
      expect(PlainTextNovelParser.decode(bytes), '吾輩は猫である');
    });

    test('BOM付きUTF-8はBOMを除いてデコードする', () {
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('猫')]);
      expect(PlainTextNovelParser.decode(bytes), '猫');
    });

    test('UTF-16LE（BOM付き）をデコードできる', () {
      // 「猫」= U+732B
      final bytes = Uint8List.fromList([0xFF, 0xFE, 0x2B, 0x73]);
      expect(PlainTextNovelParser.decode(bytes), '猫');
    });

    test('UTF-16BE（BOM付き）をデコードできる', () {
      final bytes = Uint8List.fromList([0xFE, 0xFF, 0x73, 0x2B]);
      expect(PlainTextNovelParser.decode(bytes), '猫');
    });

    test('UTF-8 で読めなければ Shift_JIS として読む', () {
      // 「車で物語を聴く。①ｶﾅ」の Shift_JIS（CP932）
      final bytes = Uint8List.fromList([
        142, 212, 130, 197, 149, 168, 140, 234, 130, 240, 146, 174, 130,
        173, 129, 66, 135, 64, 182, 197,
      ]);
      final result = PlainTextNovelParser.decodeDetailed(bytes);
      expect(result.text, '車で物語を聴く。①ｶﾅ');
      expect(result.encoding, 'Shift_JIS');
    });

    test('EUC-JP も読み分ける', () {
      // 「車で物語を聴く。ｶﾅ」の EUC-JP
      final bytes = Uint8List.fromList([
        188, 214, 164, 199, 202, 170, 184, 236, 164, 242, 196, 176, 164,
        175, 161, 163, 142, 182, 142, 197,
      ]);
      final result = PlainTextNovelParser.decodeDetailed(bytes);
      expect(result.text, '車で物語を聴く。ｶﾅ');
      expect(result.encoding, 'EUC-JP');
    });

    test('BOM の無い UTF-16 も読む', () {
      final bytes = Uint8List.fromList([
        for (final unit in 'Hello, world. 車'.codeUnits) ...[
          unit & 0xFF,
          unit >> 8,
        ],
      ]);
      expect(PlainTextNovelParser.decode(bytes), 'Hello, world. 車');
    });

    test('どの文字コードでもほとんど読めないものは例外を投げる', () {
      final bytes = Uint8List.fromList([
        for (var i = 0; i < 400; i++) [0x80, 0xFF, 0xFD][i % 3],
      ]);
      expect(
        () => PlainTextNovelParser.decode(bytes),
        throwsA(isA<UnsupportedTextEncodingException>()),
      );
    });
  });

  group('PlainTextNovelParser.parse', () {
    test('改行コードを統一し、行ごとにNewLineを挟む', () {
      final result = PlainTextNovelParser.parse('一行目\r\n二行目\r三行目\n');
      expect(result, [
        PlainText('一行目'),
        NewLine(),
        PlainText('二行目'),
        NewLine(),
        PlainText('三行目'),
      ]);
    });

    test('空行はNewLineの連続として保持する', () {
      final result = PlainTextNovelParser.parse('a\n\nb');
      expect(result, [PlainText('a'), NewLine(), NewLine(), PlainText('b')]);
    });

    test('全角縦棒によるルビを解析する', () {
      final result = PlainTextNovelParser.parse('彼は｜魔法使い《ウィザード》だ');
      expect(result, [
        PlainText('彼は'),
        RubyText('魔法使い', 'ウィザード'),
        PlainText('だ'),
      ]);
    });

    test('半角縦棒によるルビを解析する', () {
      final result = PlainTextNovelParser.parse('|Novelty《ノベルティ》');
      expect(result, [RubyText('Novelty', 'ノベルティ')]);
    });

    test('縦棒なしの場合は直前の連続した漢字を親文字にする', () {
      final result = PlainTextNovelParser.parse('ここは東京《とうきょう》です');
      expect(result, [
        PlainText('ここは'),
        RubyText('東京', 'とうきょう'),
        PlainText('です'),
      ]);
    });

    test('々を含む漢字列も親文字にする', () {
      final result = PlainTextNovelParser.parse('人々《ひとびと》');
      expect(result, [RubyText('人々', 'ひとびと')]);
    });

    test('直前が漢字でない《》はそのまま表示する', () {
      final result = PlainTextNovelParser.parse('ひらがな《かっこ》');
      expect(result, [PlainText('ひらがな《かっこ》')]);
    });

    test('《《》》は傍点として解析する', () {
      final result = PlainTextNovelParser.parse('これは《《重要》》です');
      expect(result, [
        PlainText('これは'),
        Kenten('重要', '﹅'),
        PlainText('です'),
      ]);
    });

    test('｜《 は 《 をそのまま表示する', () {
      final result = PlainTextNovelParser.parse('漢字｜《かっこ》');
      expect(result, [PlainText('漢字《かっこ》')]);
    });

    test('閉じ括弧がない縦棒は文字として扱う', () {
      final result = PlainTextNovelParser.parse('A｜B《C');
      expect(result, [PlainText('A｜B《C')]);
    });

    test('長すぎるルビは記法とみなさない', () {
      final longRuby = 'あ' * (PlainTextNovelParser.maxRubyLength + 1);
      final text = '漢字《$longRuby》';
      expect(PlainTextNovelParser.parse(text), [PlainText(text)]);
    });
  });

  group('HTML・青空文庫の注記を取り除く', () {
    test('タグだけの行は消し、行の中のタグも消す', () {
      const text = '<div class="info">\n本文<b>太字</b>です\n</div>\n次の行';
      expect(PlainTextNovelParser.cleanMarkup(text), '本文太字です\n次の行');
    });

    test('br は改行に、文字参照は文字に戻す', () {
      expect(
        PlainTextNovelParser.cleanMarkup('一行目<br>二行目 &lt;3 &amp; &#x41;'),
        '一行目\n二行目 <3 & A',
      );
    });

    test('元からある空行は残す', () {
      expect(PlainTextNovelParser.cleanMarkup('あ\n\nい'), 'あ\n\nい');
    });

    test('青空文庫の注記と冒頭の記号の説明を消す', () {
      const text =
          '題名\n作者\n'
          '-------------------------------------------------------\n'
          '【テキスト中に現れる記号について】\n'
          '《》：ルビ\n'
          '-------------------------------------------------------\n'
          '本文［＃「本文」に傍点］です\n'
          '［＃改ページ］\n'
          '続き';
      expect(
        PlainTextNovelParser.cleanMarkup(text),
        '題名\n作者\n本文です\n続き',
      );
    });

    test('記号の説明でない区切り線は残す', () {
      const text = 'あ\n----------\nい\n----------\nう';
      expect(PlainTextNovelParser.cleanMarkup(text), text);
    });

    test('不等号だけの文はタグとみなさない', () {
      expect(PlainTextNovelParser.cleanMarkup('1 < 2 > 0'), '1 < 2 > 0');
    });

    test('解析の前に取り除く', () {
      expect(PlainTextNovelParser.parse('<p>本文</p>'), [PlainText('本文')]);
    });
  });
}
