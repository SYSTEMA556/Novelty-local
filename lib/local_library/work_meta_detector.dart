import 'package:flutter/foundation.dart';

/// テキストファイルから読み取った作品情報。
@immutable
class WorkMeta {
  /// コンストラクタ。
  const WorkMeta({required this.title, this.author});

  /// 作品名。
  final String title;

  /// 作者名（読み取れなかった場合は null）。
  final String? author;

  @override
  bool operator ==(Object other) =>
      other is WorkMeta && other.title == title && other.author == author;

  @override
  int get hashCode => Object.hash(title, author);

  @override
  String toString() => 'WorkMeta(title: $title, author: $author)';
}

/// ファイル名と本文の冒頭から、作品名と作者名を読み取る。
///
/// 次の順で判定し、最初に見つかったものを採用する。
/// 1. 夜伽形式：冒頭の `作者:〇〇` 行（作品名は `「〇〇」` 行）
/// 2. 青空文庫形式：冒頭の `作者名／訳者名訳` 行、または
///    区切り線（`-----`）より前の見出し行
/// 3. ファイル名：`作者_作品`・`作者-作品`・`[作者] 作品`・`【作者】作品`
///
/// 夜伽のファイル名の先頭にある `番号_日付_時刻_` は取り除く。
class WorkMetaDetector {
  WorkMetaDetector._();

  /// 解析に使う本文冒頭の文字数。
  static const int headLength = 3000;

  /// 作者名として認める最大文字数（誤判定防止）。
  static const int maxAuthorLength = 30;

  // 夜伽のファイル名の先頭：番号_YYYYMMDD_HHMM_
  static final _yotogiPrefix = RegExp(r'^\d+_\d{8}_\d{4}_');

  // 夜伽の情報欄の作者行
  static final _yotogiAuthor = RegExp(r'^\s*作者\s*[:：]\s*(.+?)\s*$');

  // 夜伽の情報欄の作品名行
  static final _bracketTitle = RegExp(r'^\s*「(.+)」\s*$');

  // 青空文庫の「作者／訳者訳」行
  static final _translatorLine = RegExp(r'^(.+?)\s*[／/]\s*.+訳\s*$');

  // 青空文庫の区切り線
  static final _separator = RegExp(r'^-{10,}\s*$');

  // HTMLタグだけの行（夜伽の <div> など）
  static final _tagLine = RegExp(r'^\s*</?[a-zA-Z][^>]*>\s*$');

  // ファイル名の「作者 区切り 作品」パターン（優先順）
  static final _filenamePatterns = [
    RegExp(r'^\[(.+?)\]\s*(.+)$'),
    RegExp(r'^【(.+?)】\s*(.+)$'),
    RegExp(r'^(.+?)\s*[_＿]\s*(.+)$'),
    RegExp(r'^(.+?)\s*[-－]\s*(.+)$'),
  ];

  /// 作品情報を読み取る。
  static WorkMeta detect({required String fileName, required String head}) {
    final baseName = _stripExtension(fileName);
    final isYotogi = _yotogiPrefix.hasMatch(baseName);
    final nameWithoutPrefix = baseName.replaceFirst(_yotogiPrefix, '');

    final lines = _headLines(head);

    final fromYotogi = _detectYotogi(lines);
    if (fromYotogi != null) {
      return WorkMeta(
        title: fromYotogi.title.isEmpty ? nameWithoutPrefix : fromYotogi.title,
        author: fromYotogi.author,
      );
    }

    final fromAozora = _detectAozora(lines);
    if (fromAozora != null) return fromAozora;

    // 夜伽の番号付きファイル名は作品名に区切り文字を含みうるため分割しない
    if (!isYotogi) {
      final fromName = _detectFromFileName(nameWithoutPrefix);
      if (fromName != null) return fromName;
    }
    return WorkMeta(title: nameWithoutPrefix);
  }

  /// 作者名をグループ分け用に正規化する。
  ///
  /// 全角英数字を半角に揃え、空白を取り除く
  /// （「Ｅ・Ｓ・ガードナー」と「E・S・ガードナー」を同じ作者として扱う）。
  static String authorKey(String author) {
    final buffer = StringBuffer();
    for (final rune in author.runes) {
      if (rune >= 0xFF01 && rune <= 0xFF5E) {
        buffer.writeCharCode(rune - 0xFEE0);
      } else if (rune == 0x3000 || rune == 0x20) {
        continue;
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString().toLowerCase();
  }

  static WorkMeta? _detectYotogi(List<String> lines) {
    // 情報欄は冒頭に集まっているため、最初の数行だけを見る
    final limit = lines.length < 8 ? lines.length : 8;
    String? author;
    var title = '';
    for (var i = 0; i < limit; i++) {
      final authorMatch = _yotogiAuthor.firstMatch(lines[i]);
      if (authorMatch != null) author ??= authorMatch.group(1);
      final titleMatch = _bracketTitle.firstMatch(lines[i]);
      if (titleMatch != null && title.isEmpty) title = titleMatch.group(1)!;
    }
    final normalized = _normalizeAuthor(author);
    if (normalized == null) return null;
    return WorkMeta(title: title.trim(), author: normalized);
  }

  static WorkMeta? _detectAozora(List<String> lines) {
    // 区切り線より前（なければ冒頭3行）を見出しとみなす
    final sepIndex = lines.indexWhere(_separator.hasMatch);
    final hasSeparator = sepIndex > 0 && sepIndex <= 8;
    final header = hasSeparator
        ? lines.sublist(0, sepIndex)
        : lines.take(3).toList();
    if (header.isEmpty) return null;

    // 「作者／訳者訳」の行があれば、その前半が作者
    for (var i = 0; i < header.length && i < 3; i++) {
      final match = _translatorLine.firstMatch(header[i]);
      if (match == null) continue;
      final author = _normalizeAuthor(match.group(1));
      if (author == null) continue;
      final titleLine = header.firstWhere(
        (line) => line != header[i],
        orElse: () => '',
      );
      if (titleLine.isEmpty) return null;
      return WorkMeta(title: titleLine, author: author);
    }

    // 区切り線がある青空文庫形式：先頭が作品名、末尾（訳者行を除く）が作者
    if (hasSeparator && header.length >= 2) {
      var authorIndex = header.length - 1;
      if (header[authorIndex].endsWith('訳') && header.length >= 3) {
        authorIndex--;
      }
      if (authorIndex < 1) return null;
      final author = _normalizeAuthor(header[authorIndex]);
      if (author == null) return null;
      return WorkMeta(title: header.first, author: author);
    }
    return null;
  }

  static WorkMeta? _detectFromFileName(String name) {
    for (final pattern in _filenamePatterns) {
      final match = pattern.firstMatch(name);
      if (match == null) continue;
      final author = _normalizeAuthor(match.group(1));
      final title = match.group(2)!.trim();
      if (author == null || title.isEmpty) continue;
      return WorkMeta(title: title, author: author);
    }
    return null;
  }

  /// 本文冒頭を、空行とタグだけの行を除いた行の一覧にする。
  static List<String> _headLines(String head) {
    final text = head.length > headLength
        ? head.substring(0, headLength)
        : head;
    return [
      for (final raw in text.split(RegExp(r'\r\n|\r|\n')))
        if (raw.trim().isNotEmpty && !_tagLine.hasMatch(raw)) raw.trim(),
    ];
  }

  static String? _normalizeAuthor(String? raw) {
    if (raw == null) return null;
    final author = raw.trim().replaceFirst(RegExp(r'\s*著$'), '');
    if (author.isEmpty || author.length > maxAuthorLength) return null;
    return author;
  }

  static String _stripExtension(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}
