import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/sites/novel_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() => db = AppDatabase.memory());
  tearDown(() async => db.close());

  // 作品情報と、ダウンロード済みの1話を入れる
  Future<void> addNovel(String id) async {
    await db
        .into(db.novels)
        .insert(
          NovelsCompanion(
            source: const Value(NovelSource.narou),
            workId: Value(id),
            title: Value('作品$id'),
          ),
        );
    await db
        .into(db.episodeContents)
        .insert(
          EpisodeContentsCompanion(
            source: const Value(NovelSource.narou),
            workId: Value(id),
            episodeId: const Value(1),
          ),
        );
  }

  Future<void> addHistory(String id) => db
      .into(db.readingHistory)
      .insert(
        ReadingHistoryCompanion(
          source: const Value(NovelSource.narou),
          workId: Value(id),
          viewedAt: const Value(0),
        ),
      );

  Future<Set<String>> novelIds() async => {
    for (final n in await db.select(db.novels).get()) n.workId,
  };

  test('ライブラリにも履歴にも無い作品だけを消す（既定）', () async {
    await addNovel('lib');
    await addNovel('hist');
    await addNovel('gone');
    await db.addToLibrary(NovelSource.narou, 'lib');
    await addHistory('hist');

    final result = await db.cleanUpUnusedNovels(keepHistory: true);

    expect(result.novels, 1);
    expect(result.episodes, 1);
    expect(result.history, 0);
    expect(await novelIds(), {'lib', 'hist'});
    expect(await db.select(db.episodeContents).get(), hasLength(2));
  });

  test('履歴だけの作品も消すと、その履歴も消える', () async {
    await addNovel('lib');
    await addNovel('hist');
    await db.addToLibrary(NovelSource.narou, 'lib');
    await addHistory('lib');
    await addHistory('hist');

    final result = await db.cleanUpUnusedNovels(keepHistory: false);

    expect(result.novels, 1);
    expect(result.history, 1);
    expect(await novelIds(), {'lib'});
    final history = await db.select(db.readingHistory).get();
    expect(history.map((h) => h.workId), ['lib']);
  });
}
