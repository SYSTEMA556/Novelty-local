/// ローカル本棚の値オブジェクト（フォークで追加）。
///
/// すべて不変で、`fromJson` / `toJson` は欠けたキーに既定値を補う
/// （古い版で保存した JSON をそのまま読めるようにするため）。
library;

import 'package:flutter/foundation.dart';

/// ローカルライブラリに取り込んだ1作品（1テキストファイル）。
@immutable
class LocalWork {
  /// コンストラクタ。
  const LocalWork({
    required this.id,
    required this.title,
    required this.fileName,
    required this.charCount,
    required this.addedAt,
    this.author,
    this.metaVersion = currentMetaVersion,
    this.manualMeta = false,
    this.titleReading,
  });

  /// JSONから生成する。
  factory LocalWork.fromJson(Map<String, dynamic> json) {
    return LocalWork(
      id: json['id'] as String,
      title: json['title'] as String,
      fileName: json['fileName'] as String,
      charCount: json['charCount'] as int? ?? 0,
      addedAt: DateTime.fromMillisecondsSinceEpoch(json['addedAt'] as int),
      author: json['author'] as String?,
      // 作者機能より前に取り込んだ作品は 0（要読み取り）
      metaVersion: json['metaVersion'] as int? ?? 0,
      manualMeta: json['manualMeta'] as bool? ?? false,
      titleReading: json['titleReading'] as String?,
    );
  }

  /// 作品情報（作者など）の読み取り規則の版。
  ///
  /// 規則を改良したら上げる。これより古い作品は読み込み時に読み取り直す。
  // 2: 行の中の HTML タグ・青空文庫の注記を除いてから読み取る
  static const int currentMetaVersion = 2;

  /// 作品ID（ファイル名から算出する固定長の識別子）。
  final String id;

  /// 表示タイトル（拡張子を除いたファイル名）。
  final String title;

  /// 取り込み元のファイル名（重複判定に使用）。
  final String fileName;

  /// 本文の文字数。
  final int charCount;

  /// 取り込み日時。
  final DateTime addedAt;

  /// 作者名（読み取れなかった場合は null）。
  final String? author;

  /// 作品情報を読み取った規則の版。
  final int metaVersion;

  /// 作品名・作者を手で修正したか（再判定の対象外にする）。
  final bool manualMeta;

  /// 作品名の読み仮名（手で入れたもの。未設定なら辞書から推測する）。
  final String? titleReading;

  /// 作品名・作者を差し替えたコピーを返す。
  ///
  /// [manual] が true なら手修正として記録する。
  LocalWork withMeta({
    required String title,
    required String? author,
    bool manual = false,
  }) {
    return LocalWork(
      id: id,
      title: title,
      fileName: fileName,
      charCount: charCount,
      addedAt: addedAt,
      author: author,
      manualMeta: manual,
      titleReading: titleReading,
    );
  }

  /// 作品名の読み仮名を差し替えたコピーを返す（null で推測に戻す）。
  LocalWork withTitleReading(String? reading) {
    return LocalWork(
      id: id,
      title: title,
      fileName: fileName,
      charCount: charCount,
      addedAt: addedAt,
      author: author,
      metaVersion: metaVersion,
      manualMeta: manualMeta,
      titleReading: reading,
    );
  }

  /// JSONに変換する。
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'fileName': fileName,
    'charCount': charCount,
    'addedAt': addedAt.millisecondsSinceEpoch,
    'author': author,
    'metaVersion': metaVersion,
    'manualMeta': manualMeta,
    if (titleReading != null) 'titleReading': titleReading,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalWork &&
          id == other.id &&
          title == other.title &&
          fileName == other.fileName &&
          charCount == other.charCount &&
          addedAt == other.addedAt &&
          author == other.author &&
          metaVersion == other.metaVersion &&
          manualMeta == other.manualMeta &&
          titleReading == other.titleReading;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    fileName,
    charCount,
    addedAt,
    author,
    metaVersion,
    manualMeta,
    titleReading,
  );
}

/// 作品ごとの読書位置（しおり）。
///
/// 表示モード（横書き／縦書きスクロール／縦書きページめくり）ごとに
/// スクロール位置が異なるため、モード別に保持する。
@immutable
class ReadingPosition {
  /// コンストラクタ。
  const ReadingPosition({
    required this.offsets,
    required this.progress,
    required this.updatedAt,
    this.ttsOffset,
  });

  /// JSONから生成する。
  factory ReadingPosition.fromJson(Map<String, dynamic> json) {
    final rawOffsets = json['offsets'] as Map<String, dynamic>? ?? const {};
    return ReadingPosition(
      offsets: {
        for (final entry in rawOffsets.entries)
          entry.key: (entry.value as num).toDouble(),
      },
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
      ttsOffset: json['ttsOffset'] as int?,
    );
  }

  /// 表示モード → スクロール位置（ページめくりはページ番号）。
  final Map<String, double> offsets;

  /// 読み進めた割合（0.0〜1.0）。
  final double progress;

  /// 最後に読んだ日時。
  final DateTime updatedAt;

  /// 最後に読み上げた文の位置（本文位置。読み上げたことが無ければ null）。
  final int? ttsOffset;

  /// JSONに変換する。
  Map<String, dynamic> toJson() => {
    'offsets': offsets,
    'progress': progress,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    if (ttsOffset != null) 'ttsOffset': ttsOffset,
  };
}

/// 取り込み処理の結果。
@immutable
class LocalImportResult {
  /// コンストラクタ。
  const LocalImportResult({
    required this.added,
    required this.skipped,
    required this.failedFiles,
    this.updated = 0,
    this.missingIds = const [],
    this.missingFolders = const [],
    this.nonUtf8 = 0,
    this.converted = 0,
  });

  /// 追加した件数。
  final int added;

  /// 取り込み済みのため飛ばした件数。
  final int skipped;

  /// 読み込めなかったファイル名（UTF-8でない等）。
  final List<String> failedFiles;

  /// 元のファイルが書き換わっていたため、取り込み直した件数（再スキャン）。
  final int updated;

  /// 元のフォルダから消えていた作品のID（再スキャン。本棚からは消していない）。
  final List<String> missingIds;

  /// 見つからなかった（消された・名前が変わった）フォルダ（再スキャン）。
  final List<String> missingFolders;

  /// UTF-8 以外（Shift_JIS など）として読んだ件数。
  final int nonUtf8;

  /// そのうち、元のファイルを UTF-8 に書き直した件数。
  final int converted;

  /// 結果をまとめる。
  LocalImportResult operator +(LocalImportResult other) => LocalImportResult(
    added: added + other.added,
    skipped: skipped + other.skipped,
    failedFiles: [...failedFiles, ...other.failedFiles],
    updated: updated + other.updated,
    missingIds: [...missingIds, ...other.missingIds],
    missingFolders: [...missingFolders, ...other.missingFolders],
    nonUtf8: nonUtf8 + other.nonUtf8,
    converted: converted + other.converted,
  );

  /// 何もしていない結果。
  static const empty = LocalImportResult(
    added: 0,
    skipped: 0,
    failedFiles: [],
  );
}

/// テキストの読み込み方の設定（フォークで追加）。
@immutable
class LocalTextOptions {
  /// コンストラクタ。
  const LocalTextOptions({
    this.convertSourceToUtf8 = false,
    this.cleanMarkup = true,
    this.unifyWidth = false,
    this.removeOcrNoise = false,
  });

  /// JSONから生成する。
  factory LocalTextOptions.fromJson(Map<String, dynamic> json) {
    return LocalTextOptions(
      convertSourceToUtf8: json['convertSourceToUtf8'] as bool? ?? false,
      cleanMarkup: json['cleanMarkup'] as bool? ?? true,
      unifyWidth: json['unifyWidth'] as bool? ?? false,
      removeOcrNoise: json['removeOcrNoise'] as bool? ?? false,
    );
  }

  /// 取り込むとき、UTF-8 以外の元のファイルを UTF-8 で書き直すか。
  final bool convertSourceToUtf8;

  /// 読むとき、HTML のタグや青空文庫の注記を消すか。
  final bool cleanMarkup;

  /// 読むとき、全角英数字を半角に、半角カナを全角にそろえるか。
  final bool unifyWidth;

  /// 読むとき、自炊した本の文字認識で崩れたルビ・傍点の行を消すか。
  final bool removeOcrNoise;

  /// JSONに変換する。
  Map<String, dynamic> toJson() => {
    'convertSourceToUtf8': convertSourceToUtf8,
    'cleanMarkup': cleanMarkup,
    'unifyWidth': unifyWidth,
    'removeOcrNoise': removeOcrNoise,
  };

  /// 一部を変えた設定を作る。
  LocalTextOptions copyWith({
    bool? convertSourceToUtf8,
    bool? cleanMarkup,
    bool? unifyWidth,
    bool? removeOcrNoise,
  }) => LocalTextOptions(
    convertSourceToUtf8: convertSourceToUtf8 ?? this.convertSourceToUtf8,
    cleanMarkup: cleanMarkup ?? this.cleanMarkup,
    unifyWidth: unifyWidth ?? this.unifyWidth,
    removeOcrNoise: removeOcrNoise ?? this.removeOcrNoise,
  );

  @override
  bool operator ==(Object other) =>
      other is LocalTextOptions &&
      other.convertSourceToUtf8 == convertSourceToUtf8 &&
      other.cleanMarkup == cleanMarkup &&
      other.unifyWidth == unifyWidth &&
      other.removeOcrNoise == removeOcrNoise;

  @override
  int get hashCode => Object.hash(
    convertSourceToUtf8,
    cleanMarkup,
    unifyWidth,
    removeOcrNoise,
  );
}
