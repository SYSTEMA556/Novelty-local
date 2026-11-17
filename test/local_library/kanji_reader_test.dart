import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/local_library/author_profiles.dart';
import 'package:novelty/local_library/kana_index.dart';
import 'package:novelty/local_library/kanji_reader.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/screens/local_library_view.dart';

// 本物の辞書と同じく、UTF-16 の順に並べてから渡す
KanjiReader _reader() => KanjiReader.fromTsv(
  ([
    '山\tやま',
    '山田\tやまだ',
    '山田風太郎\tやまだふうたろう',
    '自\tじ',
    '自業自得\tじごうじとく',
    '赤川\tあかがわ',
    '次郎\tじろう',
    '夏目\tなつめ',
    'Ｘ線\tえっくすせん',
  ]..sort()).join('\n'),
);

LocalWork _work(String id, String title, {String? author, String? reading}) =>
    LocalWork(
      id: id,
      title: title,
      fileName: '$title.txt',
      charCount: 0,
      addedAt: DateTime(2026),
      author: author,
      titleReading: reading,
    );

void main() {
  group('KanjiReader', () {
    test('一番長く一致する語の読みを使う', () {
      final reader = _reader();
      expect(reader.read('山田風太郎'), 'やまだふうたろう');
      expect(reader.read('山田'), 'やまだ');
      expect(reader.read('自業自得'), 'じごうじとく');
    });

    test('語をつないで読み、辞書にない文字はそのまま残す', () {
      final reader = _reader();
      expect(reader.read('赤川次郎'), 'あかがわじろう');
      expect(reader.read('自由'), 'じ由');
      expect(reader.read('ABCの山'), 'ABCのやま');
    });

    test('英字・数字で始まる語はかなに直さない', () {
      final reader = _reader();
      expect(reader.read('Ｘ線の山'), 'Ｘ線のやま');
      expect(KanaIndex.labelOf(reader.read('Ｘ線の山')), 'X');
      expect(reader.read('internet'), 'internet');
    });

    test('一致する語がない途中の文字でも次の語を探し直す', () {
      expect(_reader().read('山川'), 'やま川');
      expect(_reader().read('自業'), 'じ業');
    });

    test('辞書の語そのものを引ける', () {
      expect(_reader().lookup('夏目'), 'なつめ');
      expect(_reader().lookup('夏'), isNull);
    });
  });

  group('読みでの並べ替え', () {
    test('漢字の作品名も読みで「あ〜わ」に混ざる', () {
      final works = [
        _work('1', '自業自得'),
        _work('2', 'かもめ'),
        _work('3', '山'),
        _work('4', 'あさがお'),
      ];
      final sorted = filterAndSortWorks(
        works,
        const {},
        query: '',
        sort: LocalSort.title,
        reader: _reader(),
      );
      expect(sorted.map((w) => w.title), ['あさがお', 'かもめ', '自業自得', '山']);
      expect(KanaIndex.labelOf(workReading(sorted[2], _reader())), 'さ');
    });

    test('手で入れた読み仮名を推測より優先する', () {
      final work = _work('1', '山', reading: 'さん');
      expect(workReading(work, _reader()), 'さん');
    });

    test('ひらがなの読みでも検索できる', () {
      final result = filterAndSortWorks(
        [_work('1', '自業自得'), _work('2', '山')],
        const {},
        query: 'じごう',
        sort: LocalSort.title,
        reader: _reader(),
      );
      expect(result.map((w) => w.title), ['自業自得']);
    });

    test('作者も推測した読みで並び、読み仮名があればそちらを使う', () {
      final works = [
        _work('1', 'a', author: '山田風太郎'),
        _work('2', 'b', author: '赤川次郎'),
        _work('3', 'c', author: '夏目'),
      ];
      final groups = groupByAuthor(works, reader: _reader());
      expect(groups.map((g) => g.name), ['赤川次郎', '夏目', '山田風太郎']);
      expect(groups.first.guessedReading, 'あかがわじろう');
      expect(groups.first.indexLabel, 'あ');

      final profiles = AuthorProfiles.empty.edit(
        originalAuthors: {'夏目'},
        newName: '夏目',
        reading: 'わ',
      );
      final withReading = groupByAuthor(
        works,
        profiles: profiles,
        reader: _reader(),
      );
      expect(withReading.last.name, '夏目');
      expect(withReading.last.guessedReading, isNull);
    });
  });

  test('同梱の辞書を読み込める', () {
    final reader = parseKanjiReadings(
      File('assets/dict/readings.tsv.gz').readAsBytesSync(),
    );
    expect(reader.read('山田風太郎'), 'やまだふうたろう');
    expect(reader.read('自業自得'), 'じごうじとく');
    expect(KanaIndex.labelOf(reader.read('森村誠一')), 'ま');
  });
}
