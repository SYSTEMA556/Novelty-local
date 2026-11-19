import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/local_library/folder_scan.dart';
import 'package:novelty/local_library/local_library_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late Directory sourceDir;
  late LocalLibraryStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('folder_scan_test');
    sourceDir = Directory(p.join(tempDir.path, 'source'))..createSync();
    store = LocalLibraryStore(Directory(p.join(tempDir.path, 'library')));
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  File write(String name, String text, {DateTime? modified}) {
    final file = File(p.join(sourceDir.path, name))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(utf8.encode(text));
    if (modified != null) file.setLastModifiedSync(modified);
    return file;
  }

  group('planScan', () {
    ScannedFile f(String id, String sig) =>
        ScannedFile(path: '/x/$id.txt', id: id, signature: sig);

    test('新しい・書き換わった・変わらない・消えたを見分ける', () {
      final plan = planScan(
        [f('new', '1:1'), f('same', '2:2'), f('changed', '3:9')],
        {'same': '2:2', 'changed': '3:3', 'gone': '4:4'},
        {'same', 'changed', 'gone'},
      );
      expect(plan.toAdd.map((e) => e.id), ['new']);
      expect(plan.toUpdate.map((e) => e.id), ['changed']);
      expect(plan.unchanged, 1);
      expect(plan.missingIds, ['gone']);
    });

    test('目印の記録が無い取り込み済みの作品は、取り込み直さない', () {
      final plan = planScan([f('old', '1:1')], {}, {'old'});
      expect(plan.toUpdate, isEmpty);
      expect(plan.unchanged, 1);
    });
  });

  test('listFolder はサブフォルダの .txt も名前順に拾い、他は無視する', () {
    write('b.txt', 'b');
    write('sub/a.txt', 'a');
    write('memo.md', 'x');
    final files = listFolder(sourceDir.path);
    expect(files.map((e) => p.basename(e.path)), ['b.txt', 'a.txt']);
  });

  group('scanFolder', () {
    test('初回は取り込み、2回目は増えた分だけ追加する', () async {
      write('一.txt', '本文一');
      final first = await store.scanFolder(sourceDir.path);
      expect(first.added, 1);

      write('二.txt', '本文二');
      final second = await store.scanFolder(sourceDir.path);
      expect(second.added, 1);
      expect(second.skipped, 1);
      expect((await store.loadWorks()).length, 2);
      expect((await store.loadSources()).single.path, sourceDir.path);
    });

    test('書き換わったファイルは取り込み直し、しおりの ID はそのまま', () async {
      write('作品.txt', '短い', modified: DateTime(2026));
      await store.scanFolder(sourceDir.path);
      final id = (await store.loadWorks()).single.id;

      write('作品.txt', 'もっと長い本文になった', modified: DateTime(2026, 2));
      final result = await store.scanFolder(sourceDir.path);
      expect(result.updated, 1);
      final work = (await store.loadWorks()).single;
      expect(work.id, id);
      expect(work.charCount, 'もっと長い本文になった'.length);
      expect(await store.readText(id), 'もっと長い本文になった');
    });

    test('消えたファイルは数えるだけで、本棚からは消さない', () async {
      final file = write('消える.txt', '本文');
      await store.scanFolder(sourceDir.path);
      file.deleteSync();
      final result = await store.scanFolder(sourceDir.path);
      expect(result.missingIds, hasLength(1));
      expect(await store.loadWorks(), hasLength(1));
    });

    test('見つからないフォルダは知らせる', () async {
      final result = await store.scanFolder(p.join(tempDir.path, 'nothing'));
      expect(result.missingFolders, hasLength(1));
    });

    test('フォルダを忘れても作品は残る', () async {
      write('作品.txt', '本文');
      await store.scanFolder(sourceDir.path);
      await store.forgetSource(sourceDir.path);
      expect(await store.loadSources(), isEmpty);
      expect(await store.loadWorks(), hasLength(1));
    });
  });
}
