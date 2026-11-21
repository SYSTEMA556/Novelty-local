import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/screens/local_library_view.dart';
import 'package:novelty/widgets/persistent_page_storage.dart';

void main() {
  LocalWork work(String id, String title, int addedMs, {String? author}) =>
      LocalWork(
        id: id,
        title: title,
        fileName: '$title.txt',
        charCount: 100,
        addedAt: DateTime.fromMillisecondsSinceEpoch(addedMs),
        author: author,
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

  group('作者での検索と作者別まとめ', () {
    final authored = [
      work('1', '海辺', 1, author: 'Ｅ・Ｓ・ガードナー'),
      work('2', '山道', 2, author: 'E・S・ガードナー'),
      work('3', '川辺', 3, author: '夏目漱石'),
      work('4', '無名', 4),
    ];

    test('作品一覧の検索は作者名にも当たる', () {
      final result = filterAndSortWorks(
        authored,
        const {},
        query: '漱石',
        sort: LocalSort.title,
      );
      expect(result.map((w) => w.id), ['3']);
    });

    test('表記揺れを同じ作者にまとめ、作者不明は最後に置く', () {
      final groups = groupByAuthor(authored);
      expect(groups.map((g) => g.name), [
        'Ｅ・Ｓ・ガードナー',
        '夏目漱石',
        unknownAuthorLabel,
      ]);
      expect(groups.first.works.map((w) => w.title), ['山道', '海辺']);
      expect(groups.last.isUnknown, isTrue);
    });

    test('作者名で絞り込める', () {
      final groups = groupByAuthor(authored, query: '夏目');
      expect(groups.map((g) => g.name), ['夏目漱石']);
    });
  });

  group('おすすめ順', () {
    final now = DateTime(2026, 11, 21);
    LocalWork added(String id, int daysAgo) => LocalWork(
      id: id,
      title: id,
      fileName: '$id.txt',
      charCount: 100,
      addedAt: now.subtract(Duration(days: daysAgo)),
    );
    ReadingPosition read(int daysAgo, double progress) => ReadingPosition(
      offsets: const {},
      progress: progress,
      updatedAt: now.subtract(Duration(days: daysAgo)),
    );

    test('最近読んだほど、読みかけほど上に来る', () {
      final result = filterAndSortWorks(
        [added('old', 100), added('reading', 100), added('done', 100)],
        {
          'old': read(30, 0.5),
          'reading': read(1, 0.5),
          'done': read(1, 1),
        },
        query: '',
        sort: LocalSort.picks,
        now: now,
      );
      expect(result.map((w) => w.id), ['reading', 'done', 'old']);
    });

    test('入れたばかりの未読は、しばらく読んでいない作品より上に来る', () {
      final result = filterAndSortWorks(
        [added('stale', 100), added('new', 0)],
        {'stale': read(21, 0.5)},
        query: '',
        sort: LocalSort.picks,
        now: now,
      );
      expect(result.map((w) => w.id), ['new', 'stale']);
    });

    test('点数は時間がたつほど下がる', () {
      final w = added('a', 0);
      expect(
        localPickScore(w, read(0, 0.5), now),
        greaterThan(localPickScore(w, read(7, 0.5), now)),
      );
      expect(localPickScore(w, read(7, 0.5), now), closeTo(75, 0.01));
    });
  });
}

