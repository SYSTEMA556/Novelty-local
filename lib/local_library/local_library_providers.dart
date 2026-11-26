/// ローカル本棚の Riverpod プロバイダ群（フォークで追加）。
///
/// [LocalLibraryStore] を包み、一覧・読書位置・ルール・作者情報・読み込み設定を
/// `AsyncNotifier` として公開する。状態の変更は「先にメモリ上の state を更新 →
/// ストアへ保存」の順で、画面はすぐに反映される（保存の失敗は次回の読み込みで
/// 元に戻る）。コード生成（riverpod_generator）は使わず手書きしている。
library;

import 'dart:async';
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/local_library/author_profiles.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/local_library/local_library_store.dart';
import 'package:novelty/local_library/meta_rules.dart';
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

  /// フォルダを取り込む・再スキャンする（フォルダは再スキャン用に覚えておく）。
  Future<LocalImportResult> scanFolder(
    String path, {
    void Function(int done, int total)? onProgress,
  }) async {
    final store = await ref.read(localLibraryStoreProvider.future);
    final result = await store.scanFolder(path, onProgress: onProgress);
    state = AsyncData(await store.loadWorks());
    return result;
  }

  /// 覚えているフォルダをすべて再スキャンする。
  Future<LocalImportResult> rescanAll({
    void Function(String folder, int done, int total)? onProgress,
  }) async {
    final store = await ref.read(localLibraryStoreProvider.future);
    final result = await store.rescanAll(onProgress: onProgress);
    state = AsyncData(await store.loadWorks());
    return result;
  }

  /// 覚えているフォルダの一覧。
  Future<List<String>> sources() async {
    final store = await ref.read(localLibraryStoreProvider.future);
    return [for (final s in await store.loadSources()) s.path];
  }

  /// フォルダを再スキャンの対象から外す。
  Future<void> forgetSource(String path) async {
    final store = await ref.read(localLibraryStoreProvider.future);
    await store.forgetSource(path);
  }

  /// 手修正した作品を除き、全作品の作者を読み取り直す。変わった件数を返す。
  Future<int> redetectAll() async {
    final store = await ref.read(localLibraryStoreProvider.future);
    final changed = await store.redetectAll();
    state = AsyncData(await store.loadWorks());
    return changed;
  }

  /// 作品名・作者を手で修正する。
  Future<void> editMeta(
    String id, {
    required String title,
    required String? author,
    String? titleReading,
  }) async {
    final store = await ref.read(localLibraryStoreProvider.future);
    await store.editWorkMeta(
      id,
      title: title,
      author: author,
      titleReading: titleReading,
    );
    state = AsyncData(await store.loadWorks());
  }

  /// 手修正を取り消し、自動判定に戻す。
  Future<void> resetMeta(String id) async {
    final store = await ref.read(localLibraryStoreProvider.future);
    await store.resetWorkMeta(id);
    state = AsyncData(await store.loadWorks());
  }

  /// 作品を削除し、一覧を更新する。
  Future<void> delete(Set<String> ids) async {
    final store = await ref.read(localLibraryStoreProvider.future);
    await store.deleteWorks(ids);
    state = AsyncData(await store.loadWorks());
    ref.invalidate(readingPositionsProvider);
  }
}

/// 作者名の変更・読み仮名。
final authorProfilesProvider =
    AsyncNotifierProvider<AuthorProfilesNotifier, AuthorProfiles>(
      AuthorProfilesNotifier.new,
    );

/// 作者名の変更・読み仮名を管理する。変更はすぐに保存する。
class AuthorProfilesNotifier extends AsyncNotifier<AuthorProfiles> {
  @override
  Future<AuthorProfiles> build() async {
    final store = await ref.watch(localLibraryStoreProvider.future);
    return store.loadAuthorProfiles();
  }

  /// 作者の名前・読み仮名を変更する。
  Future<void> edit({
    required Iterable<String> originalAuthors,
    required String newName,
    required String? reading,
  }) async {
    final current = state.value ?? AuthorProfiles.empty;
    final updated = current.edit(
      originalAuthors: originalAuthors,
      newName: newName,
      reading: reading,
    );
    state = AsyncData(updated);
    final store = await ref.read(localLibraryStoreProvider.future);
    await store.saveAuthorProfiles(updated);
  }
}

/// 作者の読み取りルール。
final metaRulesProvider = AsyncNotifierProvider<MetaRulesNotifier, MetaRuleSet>(
  MetaRulesNotifier.new,
);

/// 作者の読み取りルールを管理する。変更はすぐに保存する。
class MetaRulesNotifier extends AsyncNotifier<MetaRuleSet> {
  @override
  Future<MetaRuleSet> build() async {
    final store = await ref.watch(localLibraryStoreProvider.future);
    return store.loadRules();
  }

  /// ルール一式を差し替えて保存する。
  Future<void> save(MetaRuleSet rules) async {
    state = AsyncData(rules);
    final store = await ref.read(localLibraryStoreProvider.future);
    await store.saveRules(rules);
  }

  /// 初期設定に戻す。
  Future<void> resetToDefaults() => save(MetaRuleSet.defaults);
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
    int? ttsOffset,
  }) {
    final current = state.value;
    if (current == null) return;
    final previous = current[workId];
    // 同じ値の記録は捨てる（スクロールの通知などで同じ位置が何度も来るため。
    // 状態を作り直すと、本棚など読書位置を見ている画面がすべて作り直される）
    if (previous != null &&
        (mode == null ||
            offset == null ||
            previous.offsets[mode] == offset) &&
        (progress == null || _clamp01(progress) == previous.progress) &&
        (ttsOffset == null || ttsOffset == previous.ttsOffset)) {
      return;
    }
    final offsets = {...?previous?.offsets};
    if (mode != null && offset != null) offsets[mode] = offset;

    state = AsyncData({
      ...current,
      workId: ReadingPosition(
        offsets: offsets,
        progress: _clamp01(progress ?? previous?.progress ?? 0),
        updatedAt: DateTime.now(),
        ttsOffset: ttsOffset ?? previous?.ttsOffset,
        // 長押しで挟んだしおりは引き継ぐ
        pins: previous?.pins ?? const [],
      ),
    });

    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () => unawaited(_flush()));
  }

  /// しおりを挟む（フォークで追加）。
  ///
  /// すでに [ReadingPosition.maxPins] 個あるときは、[replaceIndex] 番目と
  /// 入れ替える（指定が無ければいちばん古いもの）。しおりは場所の順に並べる。
  void addPin(String workId, PinnedBookmark pin, {int? replaceIndex}) {
    final current = state.value;
    if (current == null) return;
    final previous =
        current[workId] ??
        ReadingPosition(
          offsets: const {},
          progress: pin.fraction,
          updatedAt: DateTime.now(),
        );
    final pins = [...previous.pins];
    if (pins.length >= ReadingPosition.maxPins) {
      var index = replaceIndex;
      if (index == null) {
        index = 0;
        for (var i = 1; i < pins.length; i++) {
          if (pins[i].createdAt.isBefore(pins[index!].createdAt)) index = i;
        }
      }
      pins.removeAt(index!);
    }
    pins
      ..add(pin)
      ..sort((a, b) => a.offset.compareTo(b.offset));
    _setPins(workId, previous, pins);
  }

  /// しおりを外す（フォークで追加）。
  void removePin(String workId, PinnedBookmark pin) {
    final previous = state.value?[workId];
    if (previous == null) return;
    _setPins(workId, previous, [...previous.pins]..remove(pin));
  }

  void _setPins(
    String workId,
    ReadingPosition previous,
    List<PinnedBookmark> pins,
  ) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData({...current, workId: previous.withPins(pins)});
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () => unawaited(_flush()));
  }

  /// 作品の読書位置（履歴）を消す。
  void forget(String workId) {
    final current = state.value;
    if (current == null || !current.containsKey(workId)) return;
    state = AsyncData({...current}..remove(workId));
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

/// テキストの読み込み方の設定（文字コードの変換・本文の掃除・表記ゆれ）。
final localTextOptionsProvider =
    AsyncNotifierProvider<LocalTextOptionsNotifier, LocalTextOptions>(
      LocalTextOptionsNotifier.new,
    );

/// テキストの読み込み方の設定を管理する。
class LocalTextOptionsNotifier extends AsyncNotifier<LocalTextOptions> {
  @override
  Future<LocalTextOptions> build() async {
    final store = await ref.watch(localLibraryStoreProvider.future);
    return store.loadTextOptions();
  }

  /// 設定を変えて保存する。
  Future<void> save(LocalTextOptions options) async {
    state = AsyncData(options);
    final store = await ref.read(localLibraryStoreProvider.future);
    await store.saveTextOptions(options);
  }
}
