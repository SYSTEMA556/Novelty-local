import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:novelty/read_aloud/read_aloud_controller.dart';
import 'package:novelty/read_aloud/speech_document.dart';
import 'package:novelty/screens/settings/reader_settings_page.dart';
import 'package:novelty/utils/plain_text_novel_parser.dart';
import 'package:novelty/utils/settings_provider.dart';
import 'package:novelty/widgets/gesture_shield.dart';
import 'package:novelty/widgets/novel_content.dart';
import 'package:novelty/widgets/persistent_page_storage.dart';
import 'package:novelty/widgets/read_aloud_bar.dart';
import 'package:novelty/widgets/reader_navigation.dart';
import 'package:novelty/widgets/reader_position_bar.dart';

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

  // 本文の掃除・表記ゆれの設定は本棚と同じものを使う
  if (!context.mounted) return;
  final options = await ProviderScope.containerOf(
    context,
    listen: false,
  ).read(localTextOptionsProvider.future).catchError(
    (Object _) => const LocalTextOptions(),
  );
  final List<NovelContentElement> elements;
  try {
    elements = PlainTextNovelParser.parse(
      PlainTextNovelParser.decode(bytes),
      clean: options.cleanMarkup,
      unifyWidth: options.unifyWidth,
    );
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

/// ローカルの作品を読み上げる [ReadAloudController] を作る。
///
/// 読み上げた位置は、次回「前回の続きから」読めるよう [positions] に保存する
/// （[workId] が null なら保存しない）。
ReadAloudController createLocalReadAloud({
  required SpeechDocument document,
  required String title,
  required ReadingPositionsNotifier positions,
  String? workId,
  String? author,
  String? announcement,
  VoidCallback? onCompleted,
}) {
  return ReadAloudController(
    document: document,
    mediaTitle: title,
    mediaSubtitle: author,
    announcement: announcement,
    onCompleted: onCompleted,
    onPositionChanged: (segment) {
      final id = workId;
      if (id == null) return;
      scheduleMicrotask(
        () => positions.record(id, ttsOffset: segment.start),
      );
    },
  );
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
    this.sharedReadAloud,
    super.key,
  });

  /// 画面タイトル（ファイル名）。
  final String title;

  /// 表示する本文要素。
  final List<NovelContentElement> elements;

  /// ローカルライブラリの作品ID。null の場合は読書位置を保存しない。
  final String? workId;

  /// 親が用意した読み上げ（連続再生で次の作品へ進むときに使う）。
  ///
  /// null ならこの画面で作り、閉じるときに片付ける。
  /// 親が用意したものは親が片付ける。
  final ReadAloudController? sharedReadAloud;

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
    final ownReadAloud = useMemoized(
      () => sharedReadAloud == null
          ? createLocalReadAloud(
              document: document,
              title: title,
              workId: workId,
              positions: positionsNotifier,
            )
          : null,
      [document, sharedReadAloud],
    );
    useEffect(() => ownReadAloud?.dispose, [ownReadAloud]);
    final readAloud = sharedReadAloud ?? ownReadAloud!;
    useListenable(readAloud);
    useEffect(() {
      applyReadAloudSettings(readAloud, settingsValue);
      return null;
    }, [readAloud, settingsValue]);
    final speaking = readAloud.isActive ? readAloud.currentSegment : null;

    // 読み上げ中（一時停止中を含む）は画面を消さない
    useEffect(() {
      unawaited(setReaderWakelock(enabled: readAloud.isActive));
      return null;
    }, [readAloud.isActive]);
    useEffect(
      () => () => unawaited(setReaderWakelock(enabled: false)),
      const [],
    );

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
      // 中央タップでバーの表示を切り替え、端のタップはページボタンにする
      onMenuTap: () => isAppBarVisible.value = !isAppBarVisible.value,
    );

    final id = workId;
    if (id != null) {
      body = _BookmarkScope(workId: id, mode: mode, child: body);
    }

    return Scaffold(
      // 本文の色調に合わせて、余白やバーの背景も同じ色にする
      backgroundColor: settingsValue?.colorTheme.background,
      appBar: isAppBarVisible.value
          ? AppBar(
              title: Text(title, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  icon: const Icon(Icons.record_voice_over_outlined),
                  tooltip: '読み上げ',
                  onPressed: () => unawaited(
                    _startReadAloud(
                      context,
                      ref,
                      readAloud,
                      navigation,
                      settingsValue,
                    ),
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
                  const SizedBox(height: ReaderPositionBar.height),
                ],
              ),
            ),
            // 縦書きモード時、ホームジェスチャーとの競合を防ぐ
            if (isVertical) const GestureShield(),
            // シークバーはシールドより上に置く（下に置くと指で動かせない）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: ReaderPositionBar(
                  navigation: navigation,
                  isVertical: isVertical,
                  isPageFlip: settingsValue?.isPageFlip ?? false,
                  textColor: settingsValue?.colorTheme.text,
                ),
              ),
            ),
            // 読み上げ中（一時停止中を含む）は操作ボタンを出す
            if (readAloud.isActive)
              Positioned(
                left: 16,
                right: 16,
                bottom: ReaderPositionBar.height + 8,
                child: SafeArea(
                  top: false,
                  child: ReadAloudBar(controller: readAloud),
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
    ReaderNavigation navigation,
    AppSettings? settings,
  ) async {
    final document = controller.document;
    if (document.segments.isEmpty) {
      showNothingToReadAloud(context);
      return;
    }
    if (controller.status == ReadAloudStatus.paused) {
      await controller.resume();
      return;
    }

    final id = workId;
    final ttsOffset = id == null
        ? null
        : ref.read(readingPositionsProvider).value?[id]?.ttsOffset;
    final fraction = navigation.currentFraction(
      isVertical: settings?.isVertical ?? false,
      isPageFlip: settings?.isPageFlip ?? false,
    );

    final choice = await showReadAloudStartSheet(context, [
      ReadAloudStartOption(
        icon: Icons.visibility_outlined,
        title: '今見ている辺りから',
        subtitle: '全体の${(fraction * 100).round()}%の位置',
        segmentIndex: document.segmentIndexAtProgress(fraction),
      ),
      if (ttsOffset != null)
        ReadAloudStartOption(
          icon: Icons.history,
          title: '前回読み上げた文から',
          segmentIndex: document.segmentIndexAt(ttsOffset),
        ),
      const ReadAloudStartOption(
        icon: Icons.first_page,
        title: '最初から',
        segmentIndex: 0,
      ),
    ]);
    if (choice == null) return;
    await controller.playFrom(choice);
  }
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
