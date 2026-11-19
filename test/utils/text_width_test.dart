import 'package:flutter_test/flutter_test.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/utils/plain_text_novel_parser.dart';
import 'package:novelty/utils/text_width.dart';

void main() {
  test('全角英数字は半角、半角カナは濁点ごと全角にそろえる', () {
    expect(unifyTextWidth('ＡＢｃ１２３'), 'ABc123');
    expect(unifyTextWidth('ｶﾞｯｺｳﾊﾟﾝ'), 'ガッコウパン');
  });

  test('日本語の記号と全角スペースはそのまま', () {
    expect(unifyTextWidth('　本当！？（いや）'), '　本当！？（いや）');
  });

  group('PlainTextNovelParser.parse の設定', () {
    String plain(List<NovelContentElement> elements) => [
      for (final e in elements)
        switch (e) {
          PlainText(:final text) => text,
          NewLine() => '\n',
          _ => '',
        },
    ].join();

    test('掃除を切るとタグや注記をそのまま出す', () {
      const text = '一行目<br>［＃改ページ］二行目';
      expect(plain(PlainTextNovelParser.parse(text)), '一行目\n二行目');
      expect(
        plain(PlainTextNovelParser.parse(text, clean: false)),
        '一行目<br>［＃改ページ］二行目',
      );
    });

    test('表記ゆれをそろえる', () {
      expect(
        plain(PlainTextNovelParser.parse('ＳＦのﾛﾎﾞｯﾄ', unifyWidth: true)),
        'SFのロボット',
      );
    });
  });
}
