/// 連続再生リスト（フォークで追加）。
///
/// 作品の鍵の並びだけを `playlist.json` に持つ。
/// - ローカル本棚の作品：作品 ID そのもの（例：`1a2b3c4d`）
/// - Web 小説：`web:<サイト>:<作品 ID>`（例：`web:narou:n1234ab`）
///
/// 本棚から消えた作品はリストに残っていても無視する（表示・再生の時点で取り除く）。
/// Web 小説の題名は保存せず、表示のときに作品情報のキャッシュから引く。
library;

import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:novelty/sites/novel_source.dart';

/// 連続再生リストの1件。
sealed class PlaylistEntry {
  const PlaylistEntry();

  /// 保存に使う鍵から作る。読めない鍵は null。
  static PlaylistEntry? parse(String key) {
    if (!key.startsWith('web:')) return LocalPlaylistEntry(key);
    final parts = key.split(':');
    if (parts.length < 3) return null;
    final source = NovelSource.values.where((s) => s.name == parts[1]);
    if (source.isEmpty) return null;
    return WebPlaylistEntry(source.first, parts.sublist(2).join(':'));
  }

  /// 保存に使う鍵。
  String get key;
}

/// ローカル本棚の作品。
final class LocalPlaylistEntry extends PlaylistEntry {
  /// コンストラクタ。
  const LocalPlaylistEntry(this.workId);

  /// 本棚の作品 ID。
  final String workId;

  @override
  String get key => workId;
}

/// Web 小説（なろう・カクヨム）の作品。
final class WebPlaylistEntry extends PlaylistEntry {
  /// コンストラクタ。
  const WebPlaylistEntry(this.source, this.workId);

  /// サイト。
  final NovelSource source;

  /// サイトでの作品 ID（なろうなら ncode）。
  final String workId;

  @override
  String get key => 'web:${source.name}:$workId';
}

/// 連続再生リストで [currentId] の次に読む作品の ID。
///
/// [currentId] がリストに無い・最後の作品なら null。
String? nextInPlaylist(List<String> ids, String currentId) {
  final index = ids.indexOf(currentId);
  if (index < 0 || index + 1 >= ids.length) return null;
  return ids[index + 1];
}

/// 連続再生リスト（ローカル本棚の作品を、読み上げで順に流すための並び）。
final readAloudPlaylistProvider =
    AsyncNotifierProvider<ReadAloudPlaylistNotifier, List<String>>(
      ReadAloudPlaylistNotifier.new,
    );

/// 連続再生リストを管理する。変えるたびにファイルへ保存する。
class ReadAloudPlaylistNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final store = await ref.watch(localLibraryStoreProvider.future);
    return store.loadPlaylist();
  }

  Future<void> _set(List<String> ids) async {
    state = AsyncData(List.unmodifiable(ids));
    final store = await ref.read(localLibraryStoreProvider.future);
    await store.savePlaylist(ids);
  }

  List<String> get _ids => state.value ?? const [];

  /// 末尾に加える（すでにあれば何もしない）。
  Future<void> add(String id) async {
    await future;
    if (_ids.contains(id)) return;
    await _set([..._ids, id]);
  }

  /// まとめて末尾に加える（すでにある作品は飛ばす）。
  Future<void> addAll(Iterable<String> ids) async {
    await future;
    final next = [..._ids];
    for (final id in ids) {
      if (!next.contains(id)) next.add(id);
    }
    await _set(next);
  }

  /// リストから外す。
  Future<void> remove(String id) async {
    await future;
    await _set([..._ids]..remove(id));
  }

  /// 並べ替えたリストで置き換える。
  Future<void> reorder(List<String> ids) => _set(ids);

  /// 空にする。
  Future<void> clear() => _set(const []);
}
