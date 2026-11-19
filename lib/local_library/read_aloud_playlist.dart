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

  /// 並べ替える（[ReorderableListView] の番号の数え方に合わせる）。
  Future<void> move(int oldIndex, int newIndex) async {
    final ids = [..._ids];
    if (oldIndex < 0 || oldIndex >= ids.length) return;
    final item = ids.removeAt(oldIndex);
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    ids.insert(target.clamp(0, ids.length), item);
    await _set(ids);
  }

  /// 空にする。
  Future<void> clear() => _set(const []);
}
