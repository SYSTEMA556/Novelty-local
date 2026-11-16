import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:novelty/read_aloud/read_aloud_controller.dart';
import 'package:novelty/read_aloud/speech_document.dart';
import 'package:novelty/screens/settings/reader_settings_page.dart';
import 'package:novelty/utils/plain_text_novel_parser.dart';
import 'package:novelty/utils/settings_provider.dart';
import 'package:novelty/widgets/gesture_shield.dart';
import 'package:novelty/widgets/novel_content.dart';
import 'package:novelty/widgets/reader_navigation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
/// [workId] を指定すると、読書位置（しおり）を自動で保存・復元する。
class LocalTextReaderPage extends HookConsumerWidget {
  /// コンストラクタ。
  const LocalTextReaderPage({
    required this.title,
    required this.elements,
    this.workId,
    super.key,
  });

  /// 画面タイトル（ファイル名）。
  final String title;

  /// 表示する本文要素。
  final List<NovelContentElement> elements;

  /// ローカルライブラリの作品ID。null の場合は読書位置を保存しない。
  final String? workId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    // 本文に集中できるよう初期状態はAppBarを隠す
    final isAppBarVisible = useState(false);
    final settingsValue = settings.value;
    final isVertical = settingsValue?.isVertical ?? false;
    final mode = readingModeKey(
      isVertical: isVertical,
      isPageFlip: settingsValue?.isPageFlip ?? false,
    );

    // 読み上げ
    final positionsNotifier = ref.read(readingPositionsProvider.notifier);
    final document = useMemoized(
      () => SpeechDocument.fromElements(elements),
      [elements],
    );
    final readAloud = useMemoized(
      () => ReadAloudController(
        document: document,
        // 読み上げた位置を、次回「前回の続きから」読めるよう保存する
        onPositionChanged: (segment) {
          final id = workId;
          if (id == null) return;
          scheduleMicrotask(
            () => positionsNotifier.record(id, ttsOffset: segment.start),
          );
        },
      ),
      [document],
    );
    useEffect(() => readAloud.dispose, [readAloud]);
    useListenable(readAloud);
    useEffect(() {
      readAloud.setVoice(
        rate: settingsValue?.ttsRate ?? 0.5,
        pitch: settingsValue?.ttsPitch ?? 1,
      );
      return null;
    }, [readAloud, settingsValue?.ttsRate, settingsValue?.ttsPitch]);
    final speaking = readAloud.isActive ? readAloud.currentSegment : null;

    // 読み上げ中（一時停止中を含む）は画面を消さない
    useEffect(() {
      unawaited(_setWakelock(enabled: readAloud.isActive));
      return null;
    }, [readAloud.isActive]);
    useEffect(() => () => unawaited(_setWakelock(enabled: false)), const []);

    // 全体のどこにいるかの表示とシークバー
    final navigation = useMemoized(ReaderNavigation.new);
    useEffect(() => navigation.dispose, [navigation]);

    Widget body = NovelContentBody(
      workId: workId ?? 'local:$title',
      episode: 1,
      settings: settings,
      content: AsyncData(elements),
      highlightStart: speaking?.start,
      highlightEnd: speaking?.end,
      navigation: navigation,
    );

    final id = workId;
    if (id != null) {
      body = _BookmarkScope(workId: id, mode: mode, child: body);
    }

    return Scaffold(
      appBar: isAppBarVisible.value
          ? AppBar(
              title: Text(title, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  icon: const Icon(Icons.record_voice_over_outlined),
                  tooltip: '読み上げ',
                  onPressed: () => unawaited(
                    _startReadAloud(context, ref, readAloud),
                  ),
                ),
                // 読みながら文字サイズ・行の長さなどを変えられるようにする
                IconButton(
                  icon: const Icon(Icons.tune),
                  tooltip: '閲覧設定',
                  onPressed: () => unawaited(
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ReaderSettingsPage(),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : null,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // 本文タップでAppBarの表示/非表示を切り替える
        onTap: () => isAppBarVisible.value = !isAppBarVisible.value,
        child: Stack(
          children: [
            SafeArea(
              top: !isAppBarVisible.value,
              // 本文に重ならないよう、下にページ表示・シークバーの場所を取る
              child: Column(
                children: [
                  Expanded(child: body),
                  _PositionBar(
                    navigation: navigation,
                    isVertical: isVertical,
                    isPageFlip: settingsValue?.isPageFlip ?? false,
                  ),
                ],
              ),
            ),
            // 縦書きモード時、ホームジェスチャーとの競合を防ぐ
            if (isVertical) const GestureShield(),
            // 読み上げ中（一時停止中を含む）は操作ボタンを出す
            if (readAloud.isActive)
              Positioned(
                left: 16,
                right: 16,
                bottom: _PositionBar.height + 8,
                child: SafeArea(
                  top: false,
                  child: _ReadAloudBar(controller: readAloud),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// どこから読み上げるかを選んで、読み上げを始める。
  Future<void> _startReadAloud(
    BuildContext context,
    WidgetRef ref,
    ReadAloudController controller,
  ) async {
    final document = controller.document;
    if (document.segments.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('読み上げる文がありません')));
      return;
    }
    if (controller.status == ReadAloudStatus.paused) {
      await controller.resume();
      return;
    }

    final id = workId;
    final position = id == null
        ? null
        : ref.read(readingPositionsProvider).value?[id];
    final ttsOffset = position?.ttsOffset;

    final choice = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('どこから読み上げますか？')),
            if (position != null)
              ListTile(
                leading: const Icon(Icons.bookmark_outline),
                title: const Text('今読んでいる辺りから'),
                subtitle: Text(
                  'しおりの位置（${(position.progress * 100).round()}%）の目安',
                ),
                onTap: () => Navigator.pop(
                  sheetContext,
                  document.segmentIndexAtProgress(position.progress),
                ),
              ),
            if (ttsOffset != null)
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('前回読み上げた文から'),
                onTap: () => Navigator.pop(
                  sheetContext,
                  document.segmentIndexAt(ttsOffset),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.first_page),
              title: const Text('最初から'),
              onTap: () => Navigator.pop(sheetContext, 0),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await controller.playFrom(choice);
  }
}

/// 画面を消さない設定を切り替える（失敗しても読書は続けられるため無視する）。
Future<void> _setWakelock({required bool enabled}) async {
  try {
    await WakelockPlus.toggle(enable: enabled);
  } on Object catch (e) {
    debugPrint('Failed to toggle wakelock: $e');
  }
}

/// 本文の下に出す、今のページ（位置）とシークバー。
class _PositionBar extends HookWidget {
  const _PositionBar({
    required this.navigation,
    required this.isVertical,
    required this.isPageFlip,
  });

  /// バーの高さ。
  static const double height = 48;

  final ReaderNavigation navigation;
  final bool isVertical;
  final bool isPageFlip;

  @override
  Widget build(BuildContext context) {
    final paged = isVertical && isPageFlip;
    final page = useValueListenable(navigation.currentPage);
    final pageCount = useValueListenable(navigation.pageCount);
    final progress = useValueListenable(navigation.progress);
    // 指で動かしている間の値（離したときに移動する）
    final dragging = useState<double?>(null);

    final double max;
    final double value;
    final String label;
    if (paged) {
      max = pageCount > 1 ? (pageCount - 1).toDouble() : 1;
      final current = (dragging.value ?? page.toDouble()).clamp(0.0, max);
      value = current;
      label = pageCount == 0
          ? ''
          : '${current.round() + 1} / $pageCount';
    } else {
      max = 1;
      value = (dragging.value ?? progress).clamp(0.0, 1.0);
      label = '${(value * 100).round()}%';
    }
    final enabled = !paged || pageCount > 1;

    return SizedBox(
      height: height,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(
            // 縦書きは右から左へ読み進めるため、シークバーも右から左にする
            child: Directionality(
              textDirection: isVertical ? TextDirection.rtl : TextDirection.ltr,
              child: Slider(
                value: value,
                max: max,
                divisions: paged && pageCount > 1 ? pageCount - 1 : null,
                label: label,
                onChanged: enabled ? (v) => dragging.value = v : null,
                onChangeEnd: enabled
                    ? (v) {
                        dragging.value = null;
                        if (paged) {
                          navigation.jumpToPage(v.round());
                        } else {
                          navigation.seek(v, isVertical: isVertical);
                        }
                      }
                    : null,
              ),
            ),
          ),
          SizedBox(
            width: 88,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// 読み上げ中に画面下に出す操作ボタン。
class _ReadAloudBar extends StatelessWidget {
  const _ReadAloudBar({required this.controller});

  final ReadAloudController controller;

  @override
  Widget build(BuildContext context) {
    final total = controller.document.segments.length;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(28),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            const SizedBox(width: 8),
            Text(
              '${controller.index + 1} / $total',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.skip_previous),
              tooltip: '前の文',
              onPressed: () => unawaited(controller.previous()),
            ),
            IconButton.filled(
              icon: Icon(controller.isPlaying ? Icons.pause : Icons.play_arrow),
              tooltip: controller.isPlaying ? '一時停止' : '再開',
              onPressed: () => unawaited(
                controller.isPlaying ? controller.pause() : controller.resume(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.skip_next),
              tooltip: '次の文',
              onPressed: () => unawaited(controller.next()),
            ),
            IconButton(
              icon: const Icon(Icons.stop),
              tooltip: '停止',
              onPressed: () => unawaited(controller.stop()),
            ),
          ],
        ),
      ),
    );
  }
}

/// 表示モードを読書位置の保存キーに変換する。
///
/// スクロール位置の意味がモードごとに異なるため、別々に保存する。
String readingModeKey({required bool isVertical, required bool isPageFlip}) {
  if (!isVertical) return 'h';
  return isPageFlip ? 'vp' : 'vs';
}

/// 配下のスクロール位置を読書位置として保存・復元するウィジェット。
///
/// Flutter のスクロールは位置を [PageStorage] に書き込み、
/// 生成時に読み戻す。その保存先を差し替えることで、
/// 本文ウィジェットに手を入れずに「続きから読む」を実現する。
class _BookmarkScope extends HookConsumerWidget {
  const _BookmarkScope({
    required this.workId,
    required this.mode,
    required this.child,
  });

  final String workId;
  final String mode;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(readingPositionsProvider.notifier);
    final modeRef = useRef(mode)..value = mode;

    final bucket = useMemoized(
      () => PersistentPageStorageBucket(
        initialValues: {
          ...?ref.read(readingPositionsProvider).value?[workId]?.offsets,
        },
        currentKey: () => modeRef.value,
        // スクロール処理の途中で状態を変えないよう、処理後に反映する
        onWrite: (key, value) => scheduleMicrotask(
          () => notifier.record(workId, mode: key, offset: value),
        ),
      ),
    );

    useEffect(() {
      // 開いた時点で「最近読んだ」作品として記録する
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifier.record(workId);
      });
      // 画面を閉じたら保留中の保存を確定させる
      return () => unawaited(notifier.flush());
    }, [workId]);

    return NotificationListener<ScrollEndNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        final max = metrics.maxScrollExtent;
        final progress = max <= 0 ? 1.0 : metrics.pixels / max;
        scheduleMicrotask(() => notifier.record(workId, progress: progress));
        return false;
      },
      child: PageStorage(bucket: bucket, child: child),
    );
  }
}

/// 読み書きを1つのキー（表示モード）に集約する [PageStorageBucket]。
///
/// 読書画面にはスクロール領域が1つしかないため、
/// 識別子は使わず表示モードごとに値を保持する。
@visibleForTesting
class PersistentPageStorageBucket extends PageStorageBucket {
  /// コンストラクタ。
  PersistentPageStorageBucket({
    required Map<String, double> initialValues,
    required this.currentKey,
    required this.onWrite,
  }) : _values = initialValues;

  final Map<String, double> _values;

  /// 現在の表示モードのキーを返す。
  final String Function() currentKey;

  /// 位置が書き込まれたときに呼ばれる。
  final void Function(String key, double value) onWrite;

  @override
  Object? readState(BuildContext context, {Object? identifier}) {
    return _values[currentKey()];
  }

  @override
  void writeState(BuildContext context, Object? data, {Object? identifier}) {
    if (data is! double) return;
    final key = currentKey();
    if (_values[key] == data) return;
    _values[key] = data;
    onWrite(key, data);
  }
}
