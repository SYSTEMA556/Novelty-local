import 'dart:async';
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/local_library/local_library_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// ローカルライブラリのストア。
///
/// アプリのドキュメントディレクトリ配下 `local_library/` に保存する。
final localLibraryStoreProvider = FutureProvider<LocalLibraryStore>((
  ref,
) async {
  final docs = await getApplicationDocumentsDirectory();
  return LocalLibraryStore(Directory(p.join(docs.path, 'local_library')));
});

/// ローカル作品の一覧。
final localWorksProvider =
    AsyncNotifierProvider<LocalWorksNotifier, List<LocalWork>>(
      LocalWorksNotifier.new,
    );

/// ローカル作品の一覧を管理する。
class LocalWorksNotifier extends AsyncNotifier<List<LocalWork>> {
  @override
  Future<List<LocalWork>> build() async {
    final store = await ref.watch(localLibraryStoreProvider.future);
    return store.loadWorks();
  }

  /// テキストファイル群を取り込み、一覧を更新する。
  Future<LocalImportResult> importFiles(
    List<String> paths, {
    void Function(int done, int total)? onProgress,
  }) async {
    final store = await ref.read(localLibraryStoreProvider.future);
    final result = await store.importFiles(paths, onProgress: onProgress);
    state = AsyncData(await store.loadWorks());
    return result;
  }

  /// 作品を削除し、一覧を更新する。
  Future<void> delete(Set<String> ids) async {
    final store = await ref.read(localLibraryStoreProvider.future);
    await store.deleteWorks(ids);
    state = AsyncData(await store.loadWorks());
    ref.invalidate(readingPositionsProvider);
  }
}

/// 作品ごとの読書位置（しおり）。
final readingPositionsProvider =
    AsyncNotifierProvider<
      ReadingPositionsNotifier,
      Map<String, ReadingPosition>
    >(ReadingPositionsNotifier.new);

/// 読書位置を管理する。
///
/// スクロールのたびに書き込むと負荷が高いため、
/// 更新は即座に状態へ反映し、ファイル保存は少し待ってまとめて行う。
class ReadingPositionsNotifier
    extends AsyncNotifier<Map<String, ReadingPosition>> {
  Timer? _saveTimer;

  @override
  Future<Map<String, ReadingPosition>> build() async {
    final store = await ref.watch(localLibraryStoreProvider.future);
    return store.loadPositions();
  }

  /// 読書位置を更新する。
  ///
  /// [mode] は表示モード、[offset] はそのモードでのスクロール位置。
  /// [progress] は読み進めた割合（0.0〜1.0）。null の場合は前回値を維持する。
  void record(
    String workId, {
    String? mode,
    double? offset,
    double? progress,
  }) {
    final current = state.value;
    if (current == null) return;
    final previous = current[workId];
    final offsets = {...?previous?.offsets};
    if (mode != null && offset != null) offsets[mode] = offset;

    state = AsyncData({
      ...current,
      workId: ReadingPosition(
        offsets: offsets,
        progress: _clamp01(progress ?? previous?.progress ?? 0),
        updatedAt: DateTime.now(),
      ),
    });

    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () => unawaited(_flush()));
  }

  /// 保留中の読書位置をすぐに保存する。
  Future<void> flush() async {
    _saveTimer?.cancel();
    await _flush();
  }

  Future<void> _flush() async {
    final positions = state.value;
    if (positions == null) return;
    final store = await ref.read(localLibraryStoreProvider.future);
    await store.savePositions(positions);
  }
}

/// 0.0〜1.0 の範囲に収める。
double _clamp01(double value) {
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}
