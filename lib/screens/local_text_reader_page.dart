import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/utils/plain_text_novel_parser.dart';
import 'package:novelty/utils/settings_provider.dart';
import 'package:novelty/widgets/gesture_shield.dart';
import 'package:novelty/widgets/novel_content.dart';

/// 端末内のテキストファイルを選択し、読書画面で開く。
///
/// キャンセル時は何もしない。読み込みに失敗した場合はSnackBarで通知する。
Future<void> openLocalTextFile(BuildContext context) async {
  final FilePickerResult? result;
  try {
    result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      dialogTitle: 'テキストファイルを選択',
      // パスを持たないプラットフォーム（Web等）でも読めるよう内容を直接受け取る
      withData: true,
    );
  } on Object catch (e) {
    if (context.mounted) _showError(context, 'ファイルを選択できませんでした: $e');
    return;
  }

  if (result == null || result.files.isEmpty) return;
  final picked = result.files.single;
  final bytes = picked.bytes;
  if (bytes == null) {
    if (context.mounted) _showError(context, 'ファイルを読み込めませんでした');
    return;
  }

  final List<NovelContentElement> elements;
  try {
    elements = PlainTextNovelParser.parse(PlainTextNovelParser.decode(bytes));
  } on UnsupportedTextEncodingException catch (e) {
    if (context.mounted) _showError(context, e.toString());
    return;
  } finally {
    // FilePickerのキャッシュは自動削除されないため、読み込み後に消去する
    unawaited(
      FilePicker.platform.clearTemporaryFiles().then<void>(
        (_) {},
        onError: (Object _) {},
      ),
    );
  }

  if (!context.mounted) return;
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (_) => LocalTextReaderPage(
        title: _stripExtension(picked.name),
        elements: elements,
      ),
    ),
  );
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _stripExtension(String name) {
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/// ローカルのテキストファイルを表示する読書画面。
///
/// 縦書き／横書き・ページめくり・ルビなどの閲覧設定は
/// サイトの小説と同じものが適用される。
class LocalTextReaderPage extends HookConsumerWidget {
  /// コンストラクタ。
  const LocalTextReaderPage({
    required this.title,
    required this.elements,
    super.key,
  });

  /// 画面タイトル（ファイル名）。
  final String title;

  /// 表示する本文要素。
  final List<NovelContentElement> elements;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    // 本文に集中できるよう初期状態はAppBarを隠す
    final isAppBarVisible = useState(false);
    final isVertical = settings.value?.isVertical ?? false;

    return Scaffold(
      appBar: isAppBarVisible.value
          ? AppBar(title: Text(title, overflow: TextOverflow.ellipsis))
          : null,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // 本文タップでAppBarの表示/非表示を切り替える
        onTap: () => isAppBarVisible.value = !isAppBarVisible.value,
        child: Stack(
          children: [
            SafeArea(
              top: !isAppBarVisible.value,
              child: NovelContentBody(
                workId: 'local:$title',
                episode: 1,
                settings: settings,
                content: AsyncData(elements),
              ),
            ),
            // 縦書きモード時、ホームジェスチャーとの競合を防ぐ
            if (isVertical) const GestureShield(),
          ],
        ),
      ),
    );
  }
}
