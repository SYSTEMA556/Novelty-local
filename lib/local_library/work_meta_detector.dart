import 'package:flutter/foundation.dart';
import 'package:novelty/local_library/meta_rules.dart';
import 'package:novelty/utils/plain_text_novel_parser.dart';

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

/// 読み取り結果と、採用されたルール。
@immutable
class DetectionResult {
  /// コンストラクタ。
  const DetectionResult(this.meta, this.rule, this.cleanedName);

  /// 読み取った作品情報。
  final WorkMeta meta;

  /// 採用されたルール（どれも当てはまらなければ null）。
  final MetaRule? rule;

  /// 除去パターンを適用した後のファイル名（拡張子なし）。
  final String cleanedName;
}

/// ファイル名と本文の冒頭から、作品名と作者名を読み取る。
///
/// [MetaRuleSet] のルールを上から順に試し、最初に当てはまったものを採用する。
/// どれも当てはまらなければ、除去パターン適用後のファイル名を作品名とする。
class WorkMetaDetector {
  WorkMetaDetector._();

  /// 解析に使う本文冒頭の文字数。
  static const int headLength = 3000;

  /// 作者名として認める最大文字数（誤判定防止）。
  static const int maxAuthorLength = 30;

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

  // ファイル名の「作者 区切り 作品」パターン
  static final _bracketPatterns = [
    RegExp(r'^\[(.+?)\]\s*(.+)$'),
    RegExp(r'^【(.+?)】\s*(.+)$'),
  ];
  static final _underscorePattern = RegExp(r'^(.+?)\s*[_＿]\s*(.+)$');
  static final _dashPattern = RegExp(r'^(.+?)\s*[-－]\s*(.+)$');

  /// 作品情報を読み取る。
  static WorkMeta detect({
    required String fileName,
    required String head,
    MetaRuleSet rules = MetaRuleSet.defaults,
  }) => detectDetailed(fileName: fileName, head: head, rules: rules).meta;

  /// 作品情報を読み取り、採用されたルールも返す（設定画面の試し欄用）。
  static DetectionResult detectDetailed({
    required String fileName,
    required String head,
    MetaRuleSet rules = MetaRuleSet.defaults,
  }) {
    final cleaned = cleanFileName(fileName, rules.strips);
    final lines = _headLines(head);

    for (final rule in rules.rules) {
      if (!rule.enabled) continue;
      final meta = _applyRule(rule, cleaned, lines);
      if (meta != null) return DetectionResult(meta, rule, cleaned);
    }
    return DetectionResult(WorkMeta(title: cleaned), null, cleaned);
  }

  /// 拡張子を外し、有効な除去パターンを適用したファイル名を返す。
  ///
  /// すべて取り除かれて空になる場合は、拡張子を外しただけの名前を返す。
  static String cleanFileName(String fileName, List<StripPattern> strips) {
    final base = _stripExtension(fileName);
    var cleaned = base;
    for (final strip in strips) {
      if (!strip.enabled) continue;
      final regex = _tryCompile(strip.pattern);
      if (regex == null) continue;
      cleaned = cleaned.replaceAll(regex, '');
    }
    cleaned = cleaned.trim();
    return cleaned.isEmpty ? base : cleaned;
  }

  static WorkMeta? _applyRule(
    MetaRule rule,
    String cleaned,
    List<String> lines,
  ) {
    switch (rule.builtin) {
      case BuiltinRule.yotogi:
        final meta = _detectYotogi(lines);
        if (meta == null) return null;
        return meta.title.isEmpty
            ? WorkMeta(title: cleaned, author: meta.author)
            : meta;
      case BuiltinRule.aozora:
        return _detectAozora(lines);
      case BuiltinRule.nameBracket:
        return _splitName(cleaned, _bracketPatterns);
      case BuiltinRule.nameUnderscore:
        return _splitName(cleaned, [_underscorePattern]);
      case BuiltinRule.nameDash:
        return _splitName(cleaned, [_dashPattern]);
      case null:
        return _applyCustom(rule, cleaned, lines);
    }
  }

  /// 自作ルールを適用する。
  ///
  /// 名前付きグループ `author`・`title` の値を使う。
  /// 作者も作品名も取れなければ当てはまらなかったものとみなす。
  static WorkMeta? _applyCustom(
    MetaRule rule,
    String cleaned,
    List<String> lines,
  ) {
    final regex = _tryCompile(rule.pattern, multiLine: true);
    if (regex == null) return null;
    final input = rule.target == RuleTarget.fileName
        ? cleaned
        : lines.join('\n');
    final match = regex.firstMatch(input);
    if (match == null) return null;

    String? group(String name) => match.groupNames.contains(name)
        ? match.namedGroup(name)?.trim()
        : null;

    final author = _normalizeAuthor(group('author'));
    final title = group('title');
    final hasTitle = title != null && title.isNotEmpty;
    if (author == null && !hasTitle) return null;
    return WorkMeta(title: hasTitle ? title : cleaned, author: author);
  }

  static RegExp? _tryCompile(String pattern, {bool multiLine = false}) {
    if (pattern.isEmpty) return null;
    try {
      return RegExp(pattern, multiLine: multiLine);
    } on FormatException {
      return null;
    }
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
    // 合同誌などで作者が多すぎるときは、最初の1人（主催者）を作者にする
    final normalized =
        _normalizeAuthor(author) ?? _normalizeAuthor(_firstName(author));
    if (normalized == null) return null;
    return WorkMeta(title: title.trim(), author: normalized);
  }

  static String? _firstName(String? authors) {
    if (authors == null) return null;
    for (final name in authors.split(RegExp(r'[\s、,，・]+'))) {
      if (name.isNotEmpty) return name;
    }
    return null;
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

  static WorkMeta? _splitName(String name, List<RegExp> patterns) {
    for (final pattern in patterns) {
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
        if (raw.trim().isNotEmpty && !_tagLine.hasMatch(raw))
          // 行の中のタグ（<img …> が並んだ行など）や注記も取り除く
          PlainTextNovelParser.cleanLine(raw).trim(),
    ].where((line) => line.isNotEmpty).toList();
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
