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
    );
  }

  /// 作品情報（作者など）の読み取り規則の版。
  ///
  /// 規則を改良したら上げる。これより古い作品は読み込み時に読み取り直す。
  static const int currentMetaVersion = 1;

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
          manualMeta == other.manualMeta;

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
    );
  }

  /// 表示モード → スクロール位置（ページめくりはページ番号）。
  final Map<String, double> offsets;

  /// 読み進めた割合（0.0〜1.0）。
  final double progress;

  /// 最後に読んだ日時。
  final DateTime updatedAt;

  /// JSONに変換する。
  Map<String, dynamic> toJson() => {
    'offsets': offsets,
    'progress': progress,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
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
  });

  /// 追加した件数。
  final int added;

  /// 取り込み済みのため飛ばした件数。
  final int skipped;

  /// 読み込めなかったファイル名（UTF-8でない等）。
  final List<String> failedFiles;
}
