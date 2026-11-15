import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:novelty/screens/local_text_reader_page.dart';
import 'package:novelty/utils/plain_text_novel_parser.dart';

/// ローカルライブラリの作品を開く。
Future<void> openLocalWork(BuildContext context, LocalWork work) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(builder: (_) => LocalWorkReaderPage(work: work)),
  );
}

/// ローカルライブラリの作品を読み込んで表示する画面。
///
/// 本文と読書位置の読み込みが終わってから読書画面を表示し、
/// 前回の位置から再開できるようにする。
class LocalWorkReaderPage extends HookConsumerWidget {
  /// コンストラクタ。
  const LocalWorkReaderPage({required this.work, super.key});

  /// 表示する作品。
  final LocalWork work;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final future = useMemoized(() async {
      final store = await ref.read(localLibraryStoreProvider.future);
      // 読書位置を先に読み込んでおく（復元に必要）
      await ref.read(readingPositionsProvider.future);
      final text = await store.readText(work.id);
      // 長編でもUIが固まらないよう別Isolateで解析する
      return parseInBackground(text);
    }, [work.id]);
    final snapshot = useFuture<List<NovelContentElement>>(future);

    if (snapshot.hasError) {
      return Scaffold(
        appBar: AppBar(title: Text(work.title)),
        body: Center(child: Text('読み込めませんでした: ${snapshot.error}')),
      );
    }
    final elements = snapshot.data;
    if (elements == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return LocalTextReaderPage(
      title: work.title,
      elements: elements,
      workId: work.id,
    );
  }
}

/// 本文を別Isolateで解析する。
///
/// Isolateへ渡すクロージャが画面の状態（ref や context）を
/// 巻き込まないよう、引数だけを受け取るトップレベル関数にしている。
Future<List<NovelContentElement>> parseInBackground(String text) {
  return Isolate.run(() => PlainTextNovelParser.parse(text));
}
