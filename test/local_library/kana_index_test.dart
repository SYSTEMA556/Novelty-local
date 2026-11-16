import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/local_library/kana_index.dart';

void main() {
  group('labelOf', () {
    test('英字は大文字、全角英字も同じ見出し', () {
      expect(KanaIndex.labelOf('apple'), 'A');
      expect(KanaIndex.labelOf('Ｚｅｒｏ'), 'Z');
    });

    test('ひらがな・カタカナは行に振り分ける（濁音・小書きも含む）', () {
      expect(KanaIndex.labelOf('かなぎ'), 'か');
      expect(KanaIndex.labelOf('ガードナー'), 'か');
      expect(KanaIndex.labelOf('ぱん'), 'は');
      expect(KanaIndex.labelOf('ヴァイオリン'), 'あ');
      expect(KanaIndex.labelOf('ンジャメナ'), 'わ');
    });

    test('漢字は「漢」、数字・記号は「#」', () {
      expect(KanaIndex.labelOf('夏目漱石'), KanaIndex.kanjiLabel);
      expect(KanaIndex.labelOf('々木'), KanaIndex.kanjiLabel);
      expect(KanaIndex.labelOf('123'), KanaIndex.otherLabel);
      expect(KanaIndex.labelOf('「題」'), KanaIndex.otherLabel);
      expect(KanaIndex.labelOf(''), KanaIndex.otherLabel);
    });
  });

  group('compare', () {
    test('# → A〜Z → あ〜わ → 漢 の順に並ぶ', () {
      final items = ['漢字', 'かきく', '1番', 'Bob', 'あいう', 'カキク']
        ..sort(KanaIndex.compare);
      expect(items, ['1番', 'Bob', 'あいう', 'かきく', 'カキク', '漢字']);
    });

    test('カタカナとひらがなは同じ読みとして並ぶ', () {
      final items = ['かも', 'カベルネ', 'かなぎ']..sort(KanaIndex.compare);
      expect(items, ['かなぎ', 'カベルネ', 'かも']);
    });
  });

  test('orderOf は見出しの並び順を返す', () {
    expect(KanaIndex.orderOf('#'), lessThan(KanaIndex.orderOf('A')));
    expect(KanaIndex.orderOf('Z'), lessThan(KanaIndex.orderOf('あ')));
    expect(KanaIndex.orderOf('わ'), lessThan(KanaIndex.orderOf('漢')));
    expect(
      KanaIndex.orderOf('漢'),
      lessThan(KanaIndex.orderOf(KanaIndex.unknownLabel)),
    );
  });
}
