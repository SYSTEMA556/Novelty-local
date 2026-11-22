/// EPUB を、本棚のテキストに変換する（フォークで追加）。
///
/// EPUB の中身は、XHTML（ウェブページと同じ書き方）のファイルを zip で
/// まとめたもの。次の順に読んで、1つのテキストにつなげる。
/// 1. `META-INF/container.xml` から、目録（OPF）の場所を知る
/// 2. 目録から、題名・著者と、本文の読む順番（spine）を知る
/// 3. 本文の XHTML を順に読み、文字だけを取り出す
///
/// ルビ（`<ruby>漢字<rt>かんじ</rt></ruby>`）は、テキストの本棚と同じ
/// 「｜漢字《かんじ》」に書き換えるので、表示も読み上げもそのまま使える。
/// 段落・見出し・`<br>` は改行にする。挿絵は読まない。
///
/// 著作権保護（DRM）の掛かった EPUB は、中身が暗号化されていて読めない。
/// 同期的な関数なので、Isolate の中で呼ぶ前提。
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as p;

/// EPUB から取り出した中身。
class EpubText {
  /// コンストラクタ。
  const EpubText({required this.text, this.title, this.author});

  /// 本文（ルビは「｜漢字《かんじ》」の形）。
  final String text;

  /// 目録に書かれた題名。
  final String? title;

  /// 目録に書かれた著者。
  final String? author;
}

/// EPUB として読めなかったとき。
class EpubFormatException implements Exception {
  /// コンストラクタ。
  const EpubFormatException(this.message);

  /// 理由。
  final String message;

  @override
  String toString() => message;
}

/// [bytes]（EPUB ファイルの中身）を読む。
///
/// EPUB でない・暗号化されている・本文が無いときは [EpubFormatException]。
EpubText readEpub(List<int> bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Object {
    throw const EpubFormatException('EPUB（zip）として開けませんでした');
  }
  String? read(String name) {
    final file = archive.findFile(name);
    if (file == null) return null;
    return utf8.decode(file.content, allowMalformed: true);
  }

  final container = read('META-INF/container.xml');
  final opfPath = container == null
      ? null
      : RegExp('full-path="([^"]+)"').firstMatch(container)?.group(1);
  final opf = opfPath == null ? null : read(opfPath);
  if (opfPath == null || opf == null) {
    throw const EpubFormatException('EPUB の目録（OPF）が見つかりませんでした');
  }
  final base = p.posix.dirname(opfPath);

  // 目録の項目（id → ファイルの場所）
  final manifest = <String, String>{};
  for (final m in RegExp(r'<(?:[a-z]+:)?item\b[^>]*>').allMatches(opf)) {
    final tag = m[0]!;
    final id = _attr(tag, 'id');
    final href = _attr(tag, 'href');
    if (id != null && href != null) manifest[id] = href;
  }
  // 読む順番
  final spine = [
    for (final m in RegExp(r'<(?:[a-z]+:)?itemref\b[^>]*>').allMatches(opf))
      ?_attr(m[0]!, 'idref'),
  ];

  final parts = <String>[];
  for (final idref in spine) {
    final href = manifest[idref];
    if (href == null) continue;
    final path = p.posix.normalize(
      p.posix.join(base, Uri.decodeComponent(href.split('#').first)),
    );
    final xhtml = read(path);
    if (xhtml == null) continue;
    final text = xhtmlToText(xhtml);
    if (text.isNotEmpty) parts.add(text);
  }
  if (parts.isEmpty) {
    throw const EpubFormatException(
      '本文を読み取れませんでした（著作権保護の掛かった EPUB は読めません）',
    );
  }
  return EpubText(
    text: parts.join('\n\n'),
    title: _metadata(opf, 'title'),
    author: _metadata(opf, 'creator'),
  );
}

String? _attr(String tag, String name) {
  final m = RegExp('\\b$name\\s*=\\s*["\']([^"\']*)["\']').firstMatch(tag);
  return m == null ? null : _decodeEntities(m.group(1)!);
}

String? _metadata(String opf, String name) {
  final m = RegExp(
    '<dc:$name\\b[^>]*>([\\s\\S]*?)</dc:$name>',
  ).firstMatch(opf);
  final value = m == null ? null : _decodeEntities(m.group(1)!).trim();
  return value == null || value.isEmpty ? null : value;
}

String _decodeEntities(String s) => html.parseFragment(s).text ?? s;

// 前後で改行する要素
const _blocks = {
  'p', 'div', 'section', 'article', 'aside', 'header', 'footer', //
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'blockquote', 'tr', //
  'table', 'ul', 'ol', 'dl', 'dt', 'dd', 'figure', 'hr', 'pre',
};

// 読まない要素
const _skipped = {'script', 'style', 'head', 'title', 'rt', 'rp', 'img'};

/// XHTML の本文から文字を取り出す（ルビは「｜漢字《かんじ》」にする）。
String xhtmlToText(String xhtml) {
  final document = html.parse(xhtml);
  final body = document.body;
  if (body == null) return '';
  final out = StringBuffer();

  void newline() {
    final s = out.toString();
    if (s.isNotEmpty && !s.endsWith('\n')) out.write('\n');
  }

  void walk(dom.Node node) {
    if (node is dom.Text) {
      // XHTML の中の改行・字下げは、見た目の改行ではない
      // （改行と、その後ろの半角の字下げを消す。全角の字下げは本文なので残す）
      out.write(node.text.replaceAll(RegExp(r'[\r\n]+[ \t]*|\t'), ''));
      return;
    }
    if (node is! dom.Element) {
      node.nodes.forEach(walk);
      return;
    }
    final tag = node.localName ?? '';
    if (_skipped.contains(tag)) return;
    if (tag == 'br') {
      out.write('\n');
      return;
    }
    if (tag == 'ruby') {
      final base = StringBuffer();
      final reading = StringBuffer();
      for (final child in node.nodes) {
        if (child is dom.Element && child.localName == 'rt') {
          reading.write(child.text);
        } else if (child is dom.Element && child.localName == 'rp') {
          continue;
        } else {
          base.write(child.text);
        }
      }
      final b = base.toString().trim();
      final r = reading.toString().trim();
      out.write(r.isEmpty || b.isEmpty ? b : '｜$b《$r》');
      return;
    }
    final block = _blocks.contains(tag);
    if (block) newline();
    node.nodes.forEach(walk);
    if (block) newline();
  }

  body.nodes.forEach(walk);
  // 3行以上続く空行は1つにまとめる
  return out.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}
