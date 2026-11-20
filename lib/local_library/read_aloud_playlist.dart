/// 連続再生リスト（フォークで追加）。
///
/// 作品 ID の並びだけを `playlist.json` に持つ。本棚から消えた作品はリストに
/// 残っていても無視する（表示・再生の時点で取り除く）。
library;

import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/local_library/local_library_providers.dart';

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
