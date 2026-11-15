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

    test('UTF-8として不正なバイト列は例外を投げる', () {
      // Shift_JIS の「猫」(0x94 0x4C)
      final bytes = Uint8List.fromList([0x94, 0x4C]);
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
}
