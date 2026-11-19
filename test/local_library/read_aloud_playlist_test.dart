import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/local_library/local_library_store.dart';
import 'package:novelty/local_library/read_aloud_playlist.dart';
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
}
