/// ローカル本棚の永続化層（フォークで追加）。
///
/// `<アプリの documents>/local_library/` 以下を唯一の保存先として扱う。
/// - `index.json` 作品一覧 / `texts/<id>.txt` 本文（UTF-8 に正規化済み）
/// - `positions.json` 読書位置・しおり / `rules.json` 作者の読み取りルール
/// - `authors.json` 作者の表示名・読み / `sources.json` 再スキャン用のフォルダ
/// - `playlist.json` 連続再生リスト / `text_options.json` 読み込み設定
///
/// 設計上の約束:
/// - 書き込みはすべて `_writeAtomically`（一時ファイル → rename）で、途中で
///   落ちても JSON が壊れない。
/// - 重い処理（ファイルの読み込み・文字コード判別・作者の推定）は
///   `Isolate.run` に渡す。渡すクロージャが呼び出し元の状態をつかまないよう、
///   必ずトップレベル関数（`_xxxInBackground`）を経由する。
/// - 作品 ID はファイル名の FNV ハッシュ（[LocalLibraryStore.idForFileName]）。
///   同じ名前のファイルは同じ作品として扱い、しおりを引き継ぐ。
/// - UI の状態は持たない。Riverpod 側（local_library_providers.dart）が包む。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:novelty/local_library/author_profiles.dart';
import 'package:novelty/local_library/folder_scan.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/local_library/meta_rules.dart';
import 'package:novelty/local_library/work_meta_detector.dart';
import 'package:path/path.dart' as p;

/// ローカルライブラリの保存先を管理するストア。
///
/// 既存のデータベースとは独立して、次の構成でファイルに保存する。
/// - `index.json`: 作品一覧
/// - `positions.json`: 読書位置（しおり）
/// - `rules.json`: 作者の読み取りルール
/// - `authors.json`: 作者名の変更・読み仮名
/// - `texts/<id>.txt`: 本文（UTF-8・BOMなしに正規化）
class LocalLibraryStore {
  /// コンストラクタ。
  LocalLibraryStore(this.rootDir);

  /// 保存先のルートディレクトリ。
  final Directory rootDir;

  File get _indexFile => File(p.join(rootDir.path, 'index.json'));

  File get _positionsFile => File(p.join(rootDir.path, 'positions.json'));

  File get _rulesFile => File(p.join(rootDir.path, 'rules.json'));

  File get _authorsFile => File(p.join(rootDir.path, 'authors.json'));

  /// 作者名の変更・読み仮名を読み込む。
  Future<AuthorProfiles> loadAuthorProfiles() async {
    if (!_authorsFile.existsSync()) return AuthorProfiles.empty;
    try {
      final json = jsonDecode(await _authorsFile.readAsString());
      return AuthorProfiles.fromJson(json as Map<String, dynamic>);
    } on FormatException {
      return AuthorProfiles.empty;
    }
  }

  /// 作者名の変更・読み仮名を保存する。
  Future<void> saveAuthorProfiles(AuthorProfiles profiles) =>
      _writeAtomically(_authorsFile, jsonEncode(profiles.toJson()));

  /// 本文の保存先ディレクトリ。
  Directory get textsDir => Directory(p.join(rootDir.path, 'texts'));

  /// ファイル名から作品IDを算出する。
  ///
  /// 同じファイル名なら常に同じIDになるため、重複取り込みの判定に使う。
  static String idForFileName(String fileName) {
    final bytes = utf8.encode(fileName);
    // FNV-1a（32bit）を前方・後方の2方向で計算して連結する
    var forward = 0x811c9dc5;
    var backward = 0x811c9dc5;
    for (var i = 0; i < bytes.length; i++) {
      forward = ((forward ^ bytes[i]) * 0x01000193) & 0xFFFFFFFF;
      backward =
          ((backward ^ bytes[bytes.length - 1 - i]) * 0x01000193) & 0xFFFFFFFF;
    }
    return forward.toRadixString(16).padLeft(8, '0') +
        backward.toRadixString(16).padLeft(8, '0');
  }

  /// 作品一覧を読み込む。
  ///
  /// 作者機能より前に取り込んだ作品があれば、本文冒頭から
  /// 作品名・作者を読み取り直して保存する（初回のみ）。
  Future<List<LocalWork>> loadWorks() async {
    if (!_indexFile.existsSync()) return [];
    final raw = await _indexFile.readAsString();
    // 5000件規模でもUIが固まらないよう別Isolateで解析する
    final works = await _decodeWorksInBackground(raw);
    if (works.every((w) => w.metaVersion >= LocalWork.currentMetaVersion)) {
      return works;
    }
    final rules = await loadRules();
    final migrated = await _refreshMetaInBackground(
      works,
      textsDir.path,
      rules,
      force: false,
    );
    await saveWorks(migrated);
    return migrated;
  }

  /// 作者の読み取りルールを読み込む（未保存なら初期設定）。
  Future<MetaRuleSet> loadRules() async {
    if (!_rulesFile.existsSync()) return MetaRuleSet.defaults;
    try {
      final json = jsonDecode(await _rulesFile.readAsString());
      return MetaRuleSet.fromJson(json as Map<String, dynamic>);
    } on FormatException {
      // 壊れていたら初期設定に戻す
      return MetaRuleSet.defaults;
    }
  }

  /// 作者の読み取りルールを保存する。
  Future<void> saveRules(MetaRuleSet rules) =>
      _writeAtomically(_rulesFile, jsonEncode(rules.toJson()));

  /// 手で修正した作品を除き、全作品の作品名・作者を読み取り直す。
  ///
  /// 変わった件数を返す。
  Future<int> redetectAll() async {
    final works = await loadWorks();
    final rules = await loadRules();
    final updated = await _refreshMetaInBackground(
      works,
      textsDir.path,
      rules,
      force: true,
    );
    var changed = 0;
    for (var i = 0; i < works.length; i++) {
      if (works[i].title != updated[i].title ||
          works[i].author != updated[i].author) {
        changed++;
      }
    }
    await saveWorks(updated);
    return changed;
  }

  /// 作品名・作者を手で修正する（以後の再判定の対象外になる）。
  Future<void> editWorkMeta(
    String id, {
    required String title,
    required String? author,
    String? titleReading,
  }) async {
    final works = await loadWorks();
    final index = works.indexWhere((w) => w.id == id);
    if (index < 0) return;
    final trimmed = author?.trim();
    final reading = titleReading?.trim();
    works[index] = works[index]
        .withMeta(
          title: title.trim(),
          author: trimmed == null || trimmed.isEmpty ? null : trimmed,
          manual: true,
        )
        .withTitleReading(reading == null || reading.isEmpty ? null : reading);
    await saveWorks(works);
  }

  /// 手修正を取り消し、現在のルールで読み取り直す。
  Future<void> resetWorkMeta(String id) async {
    final works = await loadWorks();
    final index = works.indexWhere((w) => w.id == id);
    if (index < 0) return;
    final rules = await loadRules();
    final unlocked = works[index].withMeta(
      title: works[index].title,
      author: works[index].author,
    );
    works[index] = (await _refreshMetaInBackground(
      [unlocked],
      textsDir.path,
      rules,
      force: true,
    )).single;
    await saveWorks(works);
  }

  /// 作品一覧を保存する。
  Future<void> saveWorks(List<LocalWork> works) async {
    final data = [for (final w in works) w.toJson()];
    final raw = await _encodeInBackground(data);
    await _writeAtomically(_indexFile, raw);
  }

  /// 本文を読み込む。
  Future<String> readText(String id) {
    return File(p.join(textsDir.path, '$id.txt')).readAsString();
  }

  /// 作品を削除する（本文・一覧・読書位置）。
  Future<void> deleteWorks(Set<String> ids) async {
    final works = await loadWorks();
    works.removeWhere((w) => ids.contains(w.id));
    await saveWorks(works);

    final positions = await loadPositions();
    positions.removeWhere((id, _) => ids.contains(id));
    await savePositions(positions);

    for (final id in ids) {
      final file = File(p.join(textsDir.path, '$id.txt'));
      if (file.existsSync()) await file.delete();
    }
  }

  /// 読書位置を読み込む。
  Future<Map<String, ReadingPosition>> loadPositions() async {
    if (!_positionsFile.existsSync()) return {};
    final raw = await _positionsFile.readAsString();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final entry in json.entries)
        entry.key: ReadingPosition.fromJson(
          entry.value as Map<String, dynamic>,
        ),
    };
  }

  /// 読書位置を保存する。
  Future<void> savePositions(Map<String, ReadingPosition> positions) async {
    final raw = jsonEncode({
      for (final entry in positions.entries) entry.key: entry.value.toJson(),
    });
    await _writeAtomically(_positionsFile, raw);
  }

  /// テキストファイル群を取り込む。
  ///
  /// [batchSize] 件ずつ別Isolateで読み込み・コピーし、
  /// 1バッチ終わるごとに [onProgress] で進捗を通知する。
  /// 取り込み済み（同じファイル名）のものは飛ばす。
  Future<LocalImportResult> importFiles(
    List<String> paths, {
    void Function(int done, int total)? onProgress,
    int batchSize = 100,
  }) async {
    await textsDir.create(recursive: true);
    final works = await loadWorks();
    final rules = await loadRules();
    final convert = (await loadTextOptions()).convertSourceToUtf8;
    final knownIds = {for (final w in works) w.id};
    final textsPath = textsDir.path;

    var added = 0;
    var skipped = 0;
    var nonUtf8 = 0;
    var converted = 0;
    final failed = <String>[];

    for (var start = 0; start < paths.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, paths.length);
      final batch = paths.sublist(start, end);
      final known = Set<String>.of(knownIds);
      final results = await _importBatchInBackground(
        batch,
        textsPath,
        known,
        rules,
        convertSource: convert,
      );

      for (final result in results) {
        final work = result.work;
        if (result.nonUtf8) nonUtf8++;
        if (result.converted) converted++;
        if (work != null) {
          works.add(work);
          knownIds.add(work.id);
          added++;
        } else if (result.failedFileName != null) {
          failed.add(result.failedFileName!);
        } else {
          skipped++;
        }
      }
      onProgress?.call(end, paths.length);
    }

    if (added > 0) await saveWorks(works);
    return LocalImportResult(
      added: added,
      skipped: skipped,
      failedFiles: failed,
      nonUtf8: nonUtf8,
      converted: converted,
    );
  }

  File get _sourcesFile => File(p.join(rootDir.path, 'sources.json'));

  /// 取り込んだフォルダの一覧（再スキャン用）。
  Future<List<FolderSource>> loadSources() async {
    if (!_sourcesFile.existsSync()) return [];
    try {
      final list = jsonDecode(await _sourcesFile.readAsString()) as List;
      return [
        for (final item in list)
          FolderSource.fromJson(item as Map<String, dynamic>),
      ];
    } on FormatException {
      return [];
    }
  }

  Future<void> _saveSources(List<FolderSource> sources) => _writeAtomically(
    _sourcesFile,
    jsonEncode([for (final s in sources) s.toJson()]),
  );

  File get _textOptionsFile =>
      File(p.join(rootDir.path, 'text_options.json'));

  /// テキストの読み込み方の設定。
  Future<LocalTextOptions> loadTextOptions() async {
    if (!_textOptionsFile.existsSync()) return const LocalTextOptions();
    try {
      return LocalTextOptions.fromJson(
        jsonDecode(await _textOptionsFile.readAsString())
            as Map<String, dynamic>,
      );
    } on FormatException {
      return const LocalTextOptions();
    }
  }

  /// テキストの読み込み方の設定を保存する。
  Future<void> saveTextOptions(LocalTextOptions options) =>
      _writeAtomically(_textOptionsFile, jsonEncode(options.toJson()));

  File get _playlistFile => File(p.join(rootDir.path, 'playlist.json'));

  /// 連続再生リスト（作品 ID を再生する順に並べたもの）。
  Future<List<String>> loadPlaylist() async {
    if (!_playlistFile.existsSync()) return [];
    try {
      final list = jsonDecode(await _playlistFile.readAsString()) as List;
      return [for (final id in list) id as String];
    } on FormatException {
      return [];
    }
  }

  /// 連続再生リストを保存する。
  Future<void> savePlaylist(List<String> ids) =>
      _writeAtomically(_playlistFile, jsonEncode(ids));

  /// フォルダを再スキャンの対象から外す（本棚の作品はそのまま）。
  Future<void> forgetSource(String path) async {
    final sources = await loadSources()
      ..removeWhere((s) => s.path == path);
    await _saveSources(sources);
  }

  /// フォルダを取り込む・再スキャンする。
  ///
  /// - 本棚に無いファイルは追加する
  /// - 前回から中身が変わったファイルは取り込み直す（しおりはそのまま。
  ///   手で直した作者・作品名もそのまま）
  /// - 前回あったのに消えたファイルは数えるだけで、本棚からは消さない
  /// フォルダは再スキャンの対象として覚えておく。
  Future<LocalImportResult> scanFolder(
    String dirPath, {
    void Function(int done, int total)? onProgress,
    int batchSize = 100,
  }) async {
    if (!Directory(dirPath).existsSync()) {
      return LocalImportResult(
        added: 0,
        skipped: 0,
        failedFiles: const [],
        missingFolders: [dirPath],
      );
    }
    final sources = await loadSources();
    final index = sources.indexWhere((s) => s.path == dirPath);
    final previous = index < 0
        ? const <String, String>{}
        : sources[index].files;

    final files = await _listFolderInBackground(dirPath);
    final works = await loadWorks();
    final plan = planScan(files, previous, {for (final w in works) w.id});
    final total = plan.toAdd.length + plan.toUpdate.length;
    onProgress?.call(0, total);

    // 新しいファイルは、これまでの取り込みと同じ方法で追加する
    final added = plan.toAdd.isEmpty
        ? LocalImportResult.empty
        : await importFiles(
            [for (final f in plan.toAdd) f.path],
            onProgress: (done, _) => onProgress?.call(done, total),
            batchSize: batchSize,
          );

    // 中身が変わったファイルは本文を書き換え、文字数と作者・作品名を更新する
    final failed = <String>[...added.failedFiles];
    var updated = 0;
    var nonUtf8 = added.nonUtf8;
    var converted = added.converted;
    if (plan.toUpdate.isNotEmpty) {
      final current = await loadWorks();
      final byId = {for (var i = 0; i < current.length; i++) current[i].id: i};
      final rules = await loadRules();
      final textsPath = textsDir.path;
      await textsDir.create(recursive: true);
      final convert = (await loadTextOptions()).convertSourceToUtf8;
      for (var start = 0; start < plan.toUpdate.length; start += batchSize) {
        final end = (start + batchSize).clamp(0, plan.toUpdate.length);
        final batch = plan.toUpdate.sublist(start, end);
        final result = await _updateTextsInBackground(
          batch,
          textsPath,
          rules,
          convertSource: convert,
        );
        failed.addAll(result.failed);
        nonUtf8 += result.nonUtf8;
        converted += result.converted;
        for (final u in result.updated) {
          final i = byId[u.id];
          if (i == null) continue;
          final old = current[i];
          current[i] = LocalWork(
            id: old.id,
            title: old.manualMeta ? old.title : u.meta.title,
            fileName: old.fileName,
            charCount: u.charCount,
            addedAt: old.addedAt,
            author: old.manualMeta ? old.author : u.meta.author,
            manualMeta: old.manualMeta,
            titleReading: old.titleReading,
          );
          updated++;
        }
        onProgress?.call(plan.toAdd.length + end, total);
      }
      if (updated > 0) await saveWorks(current);
    }

    // 読めなかったファイルは目印を記録しない（次のスキャンで試し直す）
    final failedNames = failed.toSet();
    // UTF-8 に書き直したファイルは大きさ・日時が変わるので、目印を測り直す
    final touched = converted == 0
        ? const <String>{}
        : {for (final f in [...plan.toAdd, ...plan.toUpdate]) f.path};
    String signatureOf(ScannedFile f) {
      if (!touched.contains(f.path)) return f.signature;
      try {
        return fileSignature(File(f.path).statSync());
      } on Object {
        return f.signature;
      }
    }

    final source = FolderSource(
      path: dirPath,
      files: {
        for (final f in files)
          if (!failedNames.contains(p.basename(f.path))) f.id: signatureOf(f),
      },
      scannedAt: DateTime.now(),
    );
    if (index < 0) {
      sources.add(source);
    } else {
      sources[index] = source;
    }
    await _saveSources(sources);

    return LocalImportResult(
      added: added.added,
      skipped: plan.unchanged + added.skipped,
      failedFiles: failed,
      updated: updated,
      missingIds: plan.missingIds,
      nonUtf8: nonUtf8,
      converted: converted,
    );
  }

  /// 覚えているフォルダにある UTF-8 以外の元のファイルを、UTF-8 で書き直す。
  ///
  /// 本棚の中身はすでに UTF-8 なので変わらない。書き直したファイルの目印は
  /// 測り直すので、次の再スキャンで「書き換わった」とは扱わない。
  Future<({int converted, int nonUtf8})> convertSourcesToUtf8({
    void Function(int done, int total)? onProgress,
  }) async {
    final sources = await loadSources();
    var converted = 0;
    var nonUtf8 = 0;
    onProgress?.call(0, sources.length);
    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      if (Directory(source.path).existsSync()) {
        final result = await _convertFolderInBackground(source.path);
        converted += result.converted;
        nonUtf8 += result.nonUtf8;
        sources[i] = FolderSource(
          path: source.path,
          files: {
            ...source.files,
            for (final e in result.signatures.entries)
              if (source.files.containsKey(e.key)) e.key: e.value,
          },
          scannedAt: source.scannedAt,
        );
      }
      onProgress?.call(i + 1, sources.length);
    }
    await _saveSources(sources);
    return (converted: converted, nonUtf8: nonUtf8);
  }

  /// 覚えているフォルダをすべて再スキャンする。
  Future<LocalImportResult> rescanAll({
    void Function(String folder, int done, int total)? onProgress,
  }) async {
    var result = LocalImportResult.empty;
    for (final source in await loadSources()) {
      result += await scanFolder(
        source.path,
        onProgress: (done, total) => onProgress?.call(source.path, done, total),
      );
    }
    return result;
  }

  /// 一時ファイルに書いてから置き換え、書き込み途中で壊れないようにする。
  static Future<void> _writeAtomically(File file, String contents) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(file.path);
  }
}

// Isolateへ渡すクロージャが呼び出し元の状態を巻き込まないよう、
// 引数だけを受け取るトップレベル関数を経由する。
Future<List<ScannedFile>> _listFolderInBackground(String dirPath) =>
    Isolate.run(() => listFolder(dirPath));

Future<UpdateTextsResult> _updateTextsInBackground(
  List<ScannedFile> files,
  String textsDirPath,
  MetaRuleSet rules, {
  required bool convertSource,
}) => Isolate.run(
  () => updateTexts(
    files,
    textsDirPath,
    rules,
    convertSource: convertSource,
  ),
);

Future<ConvertFolderResult> _convertFolderInBackground(String dirPath) =>
    Isolate.run(() => convertFolderToUtf8(dirPath));

Future<List<LocalWork>> _decodeWorksInBackground(String raw) =>
    Isolate.run(() => decodeWorks(raw));

Future<String> _encodeInBackground(Object data) =>
    Isolate.run(() => jsonEncode(data));

Future<List<LocalWork>> _refreshMetaInBackground(
  List<LocalWork> works,
  String textsDirPath,
  MetaRuleSet rules, {
  required bool force,
}) => Isolate.run(
  () => refreshWorkMeta(works, textsDirPath, rules: rules, force: force),
);

Future<List<ImportItemResult>> _importBatchInBackground(
  List<String> paths,
  String textsDirPath,
  Set<String> knownIds,
  MetaRuleSet rules, {
  required bool convertSource,
}) => Isolate.run(
  () => importBatch(
    paths,
    textsDirPath,
    knownIds,
    rules: rules,
    convertSource: convertSource,
  ),
);

/// 作品一覧のJSONを解析する（Isolateから呼び出す）。
@visibleForTesting
List<LocalWork> decodeWorks(String raw) {
  final list = jsonDecode(raw) as List<dynamic>;
  return [
    for (final item in list) LocalWork.fromJson(item as Map<String, dynamic>),
  ];
}

/// 1ファイル分の取り込み結果。
@immutable
class ImportItemResult {
  /// 追加できた場合。
  const ImportItemResult.added(
    LocalWork this.work, {
    this.nonUtf8 = false,
    this.converted = false,
  }) : failedFileName = null;

  /// 取り込み済みのため飛ばした場合。
  const ImportItemResult.skipped()
    : work = null,
      failedFileName = null,
      nonUtf8 = false,
      converted = false;

  /// 読み込めなかった場合。
  const ImportItemResult.failed(String this.failedFileName)
    : work = null,
      nonUtf8 = false,
      converted = false;

  /// 追加した作品。
  final LocalWork? work;

  /// 読み込めなかったファイル名。
  final String? failedFileName;

  /// UTF-8 以外として読んだか。
  final bool nonUtf8;

  /// 元のファイルを UTF-8 に書き直したか。
  final bool converted;
}

/// テキストファイル群を読み込み、本文を保存先へコピーする。
///
/// 別Isolateで実行するためトップレベル関数にしている。
/// [knownIds] は取り込み済みのID集合で、同一バッチ内の重複も防ぐ。
@visibleForTesting
List<ImportItemResult> importBatch(
  List<String> paths,
  String textsDirPath,
  Set<String> knownIds, {
  MetaRuleSet rules = MetaRuleSet.defaults,
  bool convertSource = false,
}) {
  final now = DateTime.now();
  final results = <ImportItemResult>[];
  for (final path in paths) {
    final fileName = p.basename(path);
    final id = LocalLibraryStore.idForFileName(fileName);
    if (!knownIds.add(id)) {
      results.add(const ImportItemResult.skipped());
      continue;
    }
    try {
      final source = readSourceText(path, convertSource: convertSource);
      final text = source.text;
      File(p.join(textsDirPath, '$id.txt')).writeAsStringSync(text);
      final meta = metaOfSource(source, fileName, text, rules);
      results.add(
        ImportItemResult.added(
          LocalWork(
            id: id,
            title: meta.title,
            author: meta.author,
            fileName: fileName,
            charCount: text.length,
            addedAt: now,
          ),
          nonUtf8: source.nonUtf8,
          converted: source.converted,
        ),
      );
    } on Object {
      knownIds.remove(id);
      results.add(ImportItemResult.failed(fileName));
    }
  }
  return results;
}

/// 作品名・作者を本文冒頭から読み取り直す。
///
/// 手で修正した作品は常に対象外。[force] が false なら、
/// 古い規則で取り込んだ作品だけを読み取り直す。
/// 別Isolateで実行するためトップレベル関数にしている。
@visibleForTesting
List<LocalWork> refreshWorkMeta(
  List<LocalWork> works,
  String textsDirPath, {
  MetaRuleSet rules = MetaRuleSet.defaults,
  bool force = false,
}) {
  return [
    for (final work in works)
      // EPUB は目録の題名・著者を使うので、ファイル名から読み直さない
      if (work.manualMeta ||
          work.fileName.toLowerCase().endsWith('.epub') ||
          (!force && work.metaVersion >= LocalWork.currentMetaVersion))
        work
      else
        _refreshOne(work, textsDirPath, rules),
  ];
}

LocalWork _refreshOne(LocalWork work, String textsDirPath, MetaRuleSet rules) {
  // 冒頭の解析に必要な分だけ読む（UTF-8は1文字最大4バイト）
  const headBytes = WorkMetaDetector.headLength * 4;
  final file = File(p.join(textsDirPath, '${work.id}.txt'));
  var head = '';
  if (file.existsSync()) {
    final raf = file.openSync();
    try {
      head = utf8.decode(raf.readSync(headBytes), allowMalformed: true);
    } finally {
      raf.closeSync();
    }
  }
  final meta = WorkMetaDetector.detect(
    fileName: work.fileName,
    head: head,
    rules: rules,
  );
  return work.withMeta(title: meta.title, author: meta.author);
}
