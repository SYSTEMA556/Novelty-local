import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/local_library/local_library_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late Directory sourceDir;
  late LocalLibraryStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('local_library_test');
    sourceDir = Directory(p.join(tempDir.path, 'source'))..createSync();
    store = LocalLibraryStore(Directory(p.join(tempDir.path, 'library')));
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  String writeSource(String name, List<int> bytes) {
    final file = File(p.join(sourceDir.path, name))..writeAsBytesSync(bytes);
    return file.path;
  }

  group('idForFileName', () {
    test('同じファイル名なら同じID、異なれば異なるIDになる', () {
      final a1 = LocalLibraryStore.idForFileName('作品A.txt');
      final a2 = LocalLibraryStore.idForFileName('作品A.txt');
      final b = LocalLibraryStore.idForFileName('作品B.txt');
      expect(a1, a2);
      expect(a1, isNot(b));
      expect(a1, hasLength(16));
    });
  });

  group('importFiles', () {
    test('テキストを取り込み、一覧と本文を保存する', () async {
      final path = writeSource('吾輩は猫である.txt', utf8.encode('名前はまだ無い。'));

      final result = await store.importFiles([path]);

      expect(result.added, 1);
      expect(result.skipped, 0);
      expect(result.failedFiles, isEmpty);

      final works = await store.loadWorks();
      expect(works, hasLength(1));
      expect(works.single.title, '吾輩は猫である');
      expect(works.single.charCount, 8);
      expect(await store.readText(works.single.id), '名前はまだ無い。');
    });

    test('BOM付きUTF-8はBOMを除いて保存する', () async {
      final path = writeSource('bom.txt', [
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('本文'),
      ]);

      await store.importFiles([path]);

      final works = await store.loadWorks();
      expect(await store.readText(works.single.id), '本文');
    });

    test('取り込み済みのファイル名は飛ばす', () async {
      final path = writeSource('a.txt', utf8.encode('一回目'));
      await store.importFiles([path]);

      final result = await store.importFiles([path]);

      expect(result.added, 0);
      expect(result.skipped, 1);
      expect(await store.loadWorks(), hasLength(1));
    });

    test('UTF-8でないファイルは失敗として報告し、他は取り込む', () async {
      final bad = writeSource('sjis.txt', [0x94, 0x4C]);
      final good = writeSource('ok.txt', utf8.encode('読める'));

      final result = await store.importFiles([bad, good]);

      expect(result.added, 1);
      expect(result.failedFiles, ['sjis.txt']);
      expect((await store.loadWorks()).single.fileName, 'ok.txt');
    });

    test('バッチをまたいでも全件取り込み、進捗を通知する', () async {
      final paths = [
        for (var i = 0; i < 25; i++) writeSource('f$i.txt', utf8.encode('$i')),
      ];
      final progress = <int>[];

      final result = await store.importFiles(
        paths,
        batchSize: 10,
        onProgress: (done, total) => progress.add(done),
      );

      expect(result.added, 25);
      expect(progress, [10, 20, 25]);
      expect(await store.loadWorks(), hasLength(25));
    });
  });

  group('positions', () {
    test('読書位置を保存して読み戻せる', () async {
      final position = ReadingPosition(
        offsets: const {'h': 1234.5, 'vp': 3},
        progress: 0.4,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );

      await store.savePositions({'id1': position});
      final loaded = await store.loadPositions();

      expect(loaded['id1']!.offsets, {'h': 1234.5, 'vp': 3.0});
      expect(loaded['id1']!.progress, 0.4);
      expect(loaded['id1']!.updatedAt, position.updatedAt);
    });

    test('保存前は空', () async {
      expect(await store.loadPositions(), isEmpty);
    });
  });

  group('deleteWorks', () {
    test('本文・一覧・読書位置をまとめて削除する', () async {
      final path = writeSource('消す.txt', utf8.encode('本文'));
      await store.importFiles([path]);
      final id = (await store.loadWorks()).single.id;
      await store.savePositions({
        id: ReadingPosition(
          offsets: const {},
          progress: 0.5,
          updatedAt: DateTime.now(),
        ),
      });

      await store.deleteWorks({id});

      expect(await store.loadWorks(), isEmpty);
      expect(await store.loadPositions(), isEmpty);
      expect(
        File(p.join(store.textsDir.path, '$id.txt')).existsSync(),
        isFalse,
      );
    });
  });
}
