import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/local_library/epub_text.dart';

/// 小さな EPUB を組み立てる（テスト用の自作の文章）。
List<int> buildEpub(Map<String, String> chapters, {List<String>? order}) {
  final archive = Archive();
  void add(String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add(
    'META-INF/container.xml',
    [
      '<container><rootfiles>',
      '<rootfile full-path="OEBPS/content.opf"/>',
      '</rootfiles></container>',
    ].join(),
  );
  final ids = order ?? chapters.keys.toList();
  add(
    'OEBPS/content.opf',
    [
      '<package><metadata>',
      '<dc:title>試しの本 &amp; 続き</dc:title>',
      '<dc:creator>作者 太郎</dc:creator>',
      '</metadata><manifest>',
      for (final id in chapters.keys)
        '<item id="$id" href="text/$id.xhtml" media-type="x"/>',
      '</manifest><spine>',
      for (final id in ids) '<itemref idref="$id"/>',
      '</spine></package>',
    ].join(),
  );
  for (final e in chapters.entries) {
    add('OEBPS/text/${e.key}.xhtml', e.value);
  }
  return ZipEncoder().encode(archive);
}

void main() {
  test('目録の順に本文をつなぎ、題名と著者を読む', () {
    final epub = readEpub(
      buildEpub(
        {
          'b': '<html><body><p>二章の文。</p></body></html>',
          'a': '<html><body><h1>一章</h1><p>一章の文。</p></body></html>',
        },
        order: ['a', 'b'],
      ),
    );
    expect(epub.title, '試しの本 & 続き');
    expect(epub.author, '作者 太郎');
    expect(epub.text, '一章\n一章の文。\n\n二章の文。');
  });

  test('ルビは「｜漢字《かんじ》」に、br は改行にする', () {
    final text = xhtmlToText(
      [
        '<html><body><p><ruby>漢字<rp>(</rp><rt>かんじ</rt><rp>)</rp></ruby>',
        'を読む。<br/>次の行。</p></body></html>',
      ].join(),
    );
    expect(text, '｜漢字《かんじ》を読む。\n次の行。');
  });

  test('XHTML の中の改行や字下げは、本文の改行にしない', () {
    final text = xhtmlToText(
      '<html><body><p>前半の\n    続き。</p><img src="a.png"/></body></html>',
    );
    expect(text, '前半の続き。');
  });

  test('EPUB でないものは EpubFormatException', () {
    expect(
      () => readEpub(utf8.encode('ただのテキスト')),
      throwsA(isA<EpubFormatException>()),
    );
  });
}
