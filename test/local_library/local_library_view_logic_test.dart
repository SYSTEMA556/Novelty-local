import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/screens/local_library_view.dart';
import 'package:novelty/screens/local_text_reader_page.dart';

void main() {
  LocalWork work(String id, String title, int addedMs) => LocalWork(
    id: id,
    title: title,
    fileName: '$title.txt',
    charCount: 100,
    addedAt: DateTime.fromMillisecondsSinceEpoch(addedMs),
  );

  ReadingPosition readAt(int ms) => ReadingPosition(
    offsets: const {},
    progress: 0.5,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(ms),
  );

  final works = [work('a', 'いろは', 3), work('b', 'あいう', 1), work('c', 'かきく', 2)];

  group('filterAndSortWorks', () {
    test('タイトル順', () {
      final result = filterAndSortWorks(
        works,
        const {},
        query: '',
        sort: LocalSort.title,
      );
      expect(result.map((w) => w.title), ['あいう', 'いろは', 'かきく']);
    });

    test('追加順は新しいものが先', () {
      final result = filterAndSortWorks(
        works,
        const {},
        query: '',
        sort: LocalSort.added,
      );
      expect(result.map((w) => w.id), ['a', 'c', 'b']);
    });

    test('最近読んだ順は未読を後ろに回す', () {
      final result = filterAndSortWorks(
        works,
        {'b': readAt(10), 'c': readAt(20)},
        query: '',
        sort: LocalSort.recent,
      );
      expect(result.map((w) => w.id), ['c', 'b', 'a']);
    });

    test('タイトルの部分一致で絞り込む', () {
      final result = filterAndSortWorks(
        works,
        const {},
        query: 'ろ',
        sort: LocalSort.title,
      );
      expect(result.map((w) => w.id), ['a']);
    });
  });

  group('formatCharCount', () {
    test('1万字未満はそのまま、以上は万字表記', () {
      expect(formatCharCount(9999), '9999字');
      expect(formatCharCount(123456), '12.3万字');
    });
  });

  group('readingModeKey', () {
    test('表示モードごとに異なるキーになる', () {
      expect(readingModeKey(isVertical: false, isPageFlip: true), 'h');
      expect(readingModeKey(isVertical: true, isPageFlip: false), 'vs');
      expect(readingModeKey(isVertical: true, isPageFlip: true), 'vp');
    });
  });
}
