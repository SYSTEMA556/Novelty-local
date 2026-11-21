import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/local_library/local_library_store.dart';
import 'package:novelty/local_library/read_aloud_playlist.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:path/path.dart' as p;

void main() {
  test('nextInPlaylist は次の作品を返し、最後・無い作品なら null', () {
    expect(nextInPlaylist(['a', 'b', 'c'], 'a'), 'b');
    expect(nextInPlaylist(['a', 'b', 'c'], 'c'), isNull);
    expect(nextInPlaylist(['a', 'b'], 'x'), isNull);
  });

  test('連続再生リストを保存して読み戻せる', () async {
    final dir = Directory.systemTemp.createTempSync('playlist_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = LocalLibraryStore(Directory(p.join(dir.path, 'library')));
    expect(await store.loadPlaylist(), isEmpty);
    await store.savePlaylist(['b', 'a']);
    expect(await store.loadPlaylist(), ['b', 'a']);
  });

  group('PlaylistEntry', () {
    test('ローカルの作品は ID そのもの（前の版のリストもそのまま読める）', () {
      final entry = PlaylistEntry.parse('1a2b3c');
      expect(entry, isA<LocalPlaylistEntry>());
      expect((entry! as LocalPlaylistEntry).workId, '1a2b3c');
      expect(entry.key, '1a2b3c');
    });

    test('Web 小説は web:サイト:作品ID で、行き来できる', () {
      const entry = WebPlaylistEntry(NovelSource.kakuyomu, '1177354054');
      expect(entry.key, 'web:kakuyomu:1177354054');
      final parsed = PlaylistEntry.parse(entry.key)! as WebPlaylistEntry;
      expect(parsed.source, NovelSource.kakuyomu);
      expect(parsed.workId, '1177354054');
    });

    test('知らないサイト・壊れた鍵は読まない', () {
      expect(PlaylistEntry.parse('web:unknown:abc'), isNull);
      expect(PlaylistEntry.parse('web:narou'), isNull);
    });
  });
}
