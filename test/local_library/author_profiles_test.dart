import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/local_library/author_profiles.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/screens/local_library_view.dart';

void main() {
  LocalWork work(String id, String title, String? author) => LocalWork(
    id: id,
    title: title,
    fileName: '$id.txt',
    charCount: 1,
    addedAt: DateTime.fromMillisecondsSinceEpoch(0),
    author: author,
  );

  group('AuthorProfiles', () {
    test('名前の変更は表記揺れも含めて元の作者に当たる', () {
      final profiles = AuthorProfiles.empty.edit(
        originalAuthors: ['ｸｼﾞﾗ'],
        newName: 'くじら',
        reading: null,
      );
      expect(profiles.effectiveName('ｸｼﾞﾗ'), 'くじら');
      expect(profiles.effectiveName('別の人'), '別の人');
      expect(profiles.effectiveName(null), isNull);
    });

    test('元の名前に戻すと変更を消す。読み仮名を空にすると消す', () {
      final renamed = AuthorProfiles.empty.edit(
        originalAuthors: ['山田'],
        newName: '山田太郎',
        reading: 'やまだたろう',
      );
      expect(renamed.readingOf('山田太郎'), 'やまだたろう');

      final restored = renamed.edit(
        originalAuthors: ['山田'],
        newName: '山田',
        reading: '',
      );
      expect(restored.renames, isEmpty);
      expect(restored.readingOf('山田'), isNull);
    });

    test('JSONに保存して読み戻せる', () {
      final profiles = AuthorProfiles.empty.edit(
        originalAuthors: ['a'],
        newName: 'b',
        reading: 'びー',
      );
      expect(AuthorProfiles.fromJson(profiles.toJson()), profiles);
    });
  });

  group('groupByAuthor と名前の変更', () {
    final works = [
      work('1', '海', 'クジラ'),
      work('2', '山', 'くじら'),
      work('3', '川', '夏目漱石'),
      work('4', '空', '芥川龍之介'),
    ];

    test('同じ名前に変えた作者は1人にまとまる', () {
      final profiles = AuthorProfiles.empty.edit(
        originalAuthors: ['クジラ'],
        newName: 'くじら',
        reading: null,
      );
      final groups = groupByAuthor(works, profiles: profiles);
      final kujira = groups.firstWhere((g) => g.name == 'くじら');
      expect(kujira.works.map((w) => w.id), unorderedEquals(['1', '2']));
      expect(kujira.originalAuthors, {'クジラ', 'くじら'});
    });

    test('読み仮名があれば、その行に並ぶ', () {
      final profiles = AuthorProfiles.empty
          .edit(
            originalAuthors: ['夏目漱石'],
            newName: '夏目漱石',
            reading: 'なつめそうせき',
          )
          .edit(
            originalAuthors: ['芥川龍之介'],
            newName: '芥川龍之介',
            reading: 'あくたがわりゅうのすけ',
          );
      final groups = groupByAuthor(works, profiles: profiles);
      expect(groups.map((g) => g.indexLabel).toList(), [
        'あ',
        'か',
        'か',
        'な',
      ]);
      expect(groups.first.name, '芥川龍之介');
    });

    test('読み仮名でも検索できる', () {
      final profiles = AuthorProfiles.empty.edit(
        originalAuthors: ['夏目漱石'],
        newName: '夏目漱石',
        reading: 'なつめそうせき',
      );
      final groups = groupByAuthor(works, query: 'なつめ', profiles: profiles);
      expect(groups.map((g) => g.name), ['夏目漱石']);
    });
  });
}
