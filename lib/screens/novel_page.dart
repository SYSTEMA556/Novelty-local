import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/models/episode.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/read_aloud/read_aloud_controller.dart';
import 'package:novelty/read_aloud/speech_document.dart';
import 'package:novelty/repositories/novel_repository.dart';
import 'package:novelty/screens/settings/reader_settings_page.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/settings_provider.dart';
import 'package:novelty/utils/web_reading_positions.dart';
import 'package:novelty/widgets/gesture_shield.dart';
import 'package:novelty/widgets/novel_content.dart';
import 'package:novelty/widgets/persistent_page_storage.dart';
import 'package:novelty/widgets/read_aloud_bar.dart';
import 'package:novelty/widgets/reader_navigation.dart';
import 'package:novelty/widgets/reader_position_bar.dart';

/// 小説のページを表示するウィジェット。
class NovelPage extends HookConsumerWidget {
  /// コンストラクタ。
  const NovelPage({
    required this.source,
    required this.workId,
    super.key,
    this.episode,
    this.revised,
  });

  /// 提供サイト（プロバイダ）。
  final NovelSource source;

  /// サイト共通の作品ID（なろうはNコード）。
  final String workId;

  /// 表示するエピソード番号。
  final int? episode;

  /// 改稿日時（指定された場合、キャッシュ判定に使用）
  final String? revised;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final novelInfoAsync = ref.watch(
      novelInfoWithCacheProvider(source, workId),
    );
    final initialEpisode = episode ?? 1;

    // 現在のエピソード番号をローカル状態で管理
    final currentEpisode = useState(initialEpisode);

    // 初回履歴追加フラグ（重複追加を防ぐ）
    final hasAddedInitialHistory = useRef(false);

    // AppBarの表示状態を管理（本文に集中できるよう初期状態は非表示）
    final isAppBarVisible = useState(false);

    // 話ごとの位置表示・シークバー（PageViewは前後の話を組み直すため、
    // 話の番号ごとに持ち、画面を閉じるときにまとめて片付ける）
    final navigations = useMemoized(() => <int, ReaderNavigation>{});
    useEffect(
      () => () {
        for (final navigation in navigations.values) {
          navigation.dispose();
        }
      },
      const [],
    );
    ReaderNavigation navigationFor(int ep) =>
        navigations.putIfAbsent(ep, ReaderNavigation.new);

    // 読み上げ（読み終えたら次の話へ進んで読み続ける）
    final readAloud = useState<ReadAloudController?>(null);
    final readingEpisode = useState<int?>(null);
    useListenable(readAloud.value);
    useEffect(() => () => readAloud.value?.dispose(), const []);
    final isReading = readAloud.value?.isActive ?? false;
    // 読み上げ中（一時停止中を含む）は画面を消さない
    useEffect(() {
      unawaited(setReaderWakelock(enabled: isReading));
      return null;
    }, [isReading]);
    useEffect(
      () => () => unawaited(setReaderWakelock(enabled: false)),
      const [],
    );
    final settingsValue = ref.watch(settingsProvider).value;
    useEffect(() {
      final controller = readAloud.value;
      if (controller != null) applyReadAloudSettings(controller, settingsValue);
      return null;
    }, [readAloud.value, settingsValue]);
    // 読み終えたときの処理（毎回最新の状態を見るよう ref で持つ）
    final advanceRef = useRef<VoidCallback?>(null);

    // 話の途中の位置は少し待ってまとめて保存するので、閉じるときに確定させる
    final webPositions = ref.read(webReadingPositionsProvider.notifier);
    useEffect(() => () => unawaited(webPositions.flush()), const []);

    // 最初の履歴追加（novelInfoが読み込まれたら実行）
    useEffect(() {
      if (novelInfoAsync.hasValue && !hasAddedInitialHistory.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateHistory(ref, novelInfoAsync.value!, currentEpisode.value);
          hasAddedInitialHistory.value = true;
        });
      }
      return null;
    }, [novelInfoAsync.hasValue]);

    return novelInfoAsync.when(
      data: (novelInfo) {
        final totalEpisodes = novelInfo.generalAllNo ?? 1;
        final settings = ref.watch(settingsProvider);

        // PageViewのitemCountとinitialPageを動的に決定
        final itemCount = _getItemCount(currentEpisode.value, totalEpisodes);
        final initialPageIndex = _getInitialPage(currentEpisode.value);

        // 改稿日時マップを作成
        final episodeMap = useMemoized(() {
          // エピソードリストがnullの場合は空のMapを返す
          if (novelInfo.episodes == null) {
            return <int, String?>{};
          }
          return {
            for (final e in novelInfo.episodes!)
              if (e.index != null) e.index!: e.revised,
          };
        }, [novelInfo]);

        // 現在のエピソード番号が含まれるページを計算
        final currentPage = ((currentEpisode.value - 1) ~/ 100) + 1;

        // エピソードリストを監視
        final episodeListAsync = ref.watch(
          episodeListProvider(source, workId, currentPage),
        );

        // 現在のエピソードを取得
        final currentEpisodeData = episodeListAsync.maybeWhen(
          data: (episodes) {
            return episodes.firstWhere(
              (e) => e.index == currentEpisode.value,
              orElse: () => const Episode(),
            );
          },
          orElse: () => null,
        );

        // PageControllerをメモ化（itemCountが変わったときのみ再作成）
        final pageController = useMemoized(
          () => PageController(initialPage: initialPageIndex),
          [itemCount],
        );

        // itemCountが変わったらページ位置をリセット
        useEffect(() {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (pageController.hasClients) {
              final targetPage = _getInitialPage(currentEpisode.value);
              if (pageController.page?.round() != targetPage) {
                pageController.jumpToPage(targetPage);
              }
            }
          });
          return null;
        }, [itemCount]);

        String? revisedFor(int ep) =>
            (ep == episode && revised != null) ? revised : episodeMap[ep];

        Future<List<NovelContentElement>?> loadEpisode(int ep) async {
          try {
            return await ref.read(
              novelContentProvider(
                source: source,
                workId: workId,
                episode: ep,
                revised: revisedFor(ep),
              ).future,
            );
          } on Object catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('第$ep話を読み込めませんでした: $e')),
              );
            }
            return null;
          }
        }

        // 第 ep 話を [startAt] の文から読み上げる
        Future<void> startReading(
          int ep,
          int Function(SpeechDocument document) startAt,
        ) async {
          final elements = await loadEpisode(ep);
          if (elements == null) return;
          // 古い読み上げを先に止める（端末の音声合成は1つを共有するため）
          readAloud.value?.dispose();
          final document = SpeechDocument.fromElements(elements);
          final controller = ReadAloudController(
            document: document,
            onCompleted: () => advanceRef.value?.call(),
          );
          applyReadAloudSettings(controller, settingsValue);
          readAloud.value = controller;
          readingEpisode.value = ep;
          if (document.segments.isEmpty) {
            // 読む文が無い話（挿絵だけ等）は飛ばして次へ
            advanceRef.value?.call();
            return;
          }
          await controller.playFrom(startAt(document));
        }

        // 1話読み終えたら、画面も次の話へ送って続きを読む
        advanceRef.value = () {
          final ep = readingEpisode.value;
          if (ep == null || ep >= totalEpisodes) return;
          if (currentEpisode.value == ep && pageController.hasClients) {
            unawaited(
              pageController.nextPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              ),
            );
          }
          unawaited(startReading(ep + 1, (_) => 0));
        };

        // 読み上げボタン：一時停止中なら再開、それ以外は開始位置を選ぶ
        Future<void> onReadAloudPressed(AppSettings appSettings) async {
          final current = readAloud.value;
          if (current != null &&
              current.status == ReadAloudStatus.paused &&
              readingEpisode.value == currentEpisode.value) {
            await current.resume();
            return;
          }
          final ep = currentEpisode.value;
          final elements = await loadEpisode(ep);
          if (elements == null || !context.mounted) return;
          final document = SpeechDocument.fromElements(elements);
          if (document.segments.isEmpty) {
            showNothingToReadAloud(context);
            return;
          }
          final fraction = navigationFor(ep).currentFraction(
            isVertical: appSettings.isVertical,
            isPageFlip: appSettings.isPageFlip,
          );
          final choice = await showReadAloudStartSheet(context, [
            ReadAloudStartOption(
              icon: Icons.visibility_outlined,
              title: '今見ている辺りから',
              subtitle: 'この話の${(fraction * 100).round()}%の位置',
              segmentIndex: document.segmentIndexAtProgress(fraction),
            ),
            const ReadAloudStartOption(
              icon: Icons.first_page,
              title: 'この話の最初から',
              segmentIndex: 0,
            ),
          ]);
          if (choice == null) return;
          await startReading(ep, (_) => choice);
        }

        final speaking = isReading ? readAloud.value?.currentSegment : null;

        return settings.when(
          data: (settings) {
            return Scaffold(
              // 本文の色調に合わせて、余白の背景も同じ色にする
              backgroundColor: settings.colorTheme.background,
              appBar: isAppBarVisible.value
                  ? AppBar(
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      title: Text(
                        buildTitle(
                          novelInfo,
                          currentEpisode.value,
                          currentEpisodeData,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.record_voice_over_outlined),
                          tooltip: '読み上げ',
                          onPressed: () =>
                              unawaited(onReadAloudPressed(settings)),
                        ),
                        // 読みながら文字サイズ・色調などを変えられるようにする
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
              body: Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                // 本文タップでAppBarの表示/非表示を切り替える
                onTap: () {
                  isAppBarVisible.value = !isAppBarVisible.value;
                },
                child: Stack(
                  children: [
                    PageView.builder(
                      scrollDirection: settings.isVertical
                          ? Axis.vertical
                          : Axis.horizontal,
                      controller: pageController,
                      itemCount: itemCount,
                      onPageChanged: (index) {
                        _handlePageChanged(
                          index,
                          currentEpisode,
                          totalEpisodes,
                          pageController,
                          ref,
                          novelInfo,
                        );
                      },
                      itemBuilder: (context, index) {
                        final episodeNum = _getEpisodeNumber(
                          index,
                          currentEpisode.value,
                          totalEpisodes,
                        );

                        // 指定されたエピソードかつ改稿日時が指定されている場合はそちらを優先
                        // それ以外はNovelInfoから取得した改稿日時を使用
                        final revisedDate =
                            (episodeNum == episode && revised != null)
                            ? revised
                            : episodeMap[episodeNum];

                        return RepaintBoundary(
                          // 話ごとにスクロール位置を覚えて、次に開いたとき続きから
                          child: _EpisodeBookmarkScope(
                            positionKey: webEpisodeKey(
                              source,
                              workId,
                              episodeNum,
                            ),
                            mode: readingModeKey(
                              isVertical: settings.isVertical,
                              isPageFlip: settings.isPageFlip,
                            ),
                            child: NovelContent(
                            source: source,
                            workId: workId,
                            episode: episodeNum,
                            revised: revisedDate,
                            isAppBarVisible: isAppBarVisible.value,
                            // 下は位置表示のバーが場所を取る
                            safeBottom: false,
                            navigation: navigationFor(episodeNum),
                            // 読み上げ中の話にだけ、読んでいる文の色を付ける
                            highlightStart: episodeNum == readingEpisode.value
                                ? speaking?.start
                                : null,
                            highlightEnd: episodeNum == readingEpisode.value
                                ? speaking?.end
                                : null,
                            // 中央タップでバーの表示を切り替え、
                            // 端のタップはページボタンにする
                            onMenuTap: () =>
                                isAppBarVisible.value = !isAppBarVisible.value,
                            // 話の最後（最初）でさらに進む（戻る）と前後の話へ
                            onOverflow: (direction) => unawaited(
                              direction > 0
                                  ? pageController.nextPage(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      curve: Curves.easeOut,
                                    )
                                  : pageController.previousPage(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      curve: Curves.easeOut,
                                    ),
                            ),
                          ),
                          ),
                        );
                      },
                    ),
                    // 縦書きモード時、ホームジェスチャーとの競合を防ぐためシールドを表示
                    if (settings.isVertical) const GestureShield(),
                    // 読み上げ中（一時停止中を含む）は操作ボタンを出す
                    if (readAloud.value case final controller?
                        when controller.isActive)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 8,
                        child: ReadAloudBar(controller: controller),
                      ),
                  ],
                ),
              ),
                  ),
                  // 今の話の中のページ（位置）とシークバー
                  SafeArea(
                    top: false,
                    child: ReaderPositionBar(
                      key: ValueKey(currentEpisode.value),
                      navigation: navigationFor(currentEpisode.value),
                      isVertical: settings.isVertical,
                      isPageFlip: settings.isPageFlip,
                      textColor: settings.colorTheme.text,
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (e, s) => Scaffold(
            appBar: AppBar(),
            body: Center(child: Text('Error: $e')),
          ),
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, s) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('エラーが発生しました: $e'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('戻る'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateHistory(WidgetRef ref, NovelInfo novelInfo, int episode) {
    unawaited(
      ref
          .read(novelRepositoryProvider)
          .addToHistory(
            source: source,
            workId: workId,
            title: novelInfo.title ?? '',
            writer: novelInfo.writer ?? '',
            lastEpisode: episode,
          ),
    );
  }

  /// PageViewのアイテム数を決定する。
  ///
  /// - 1話だけの小説: 1ページ
  /// - 第1話（2話以上）: 2ページ（現在 + 次）
  /// - 最終話: 2ページ（前 + 現在）
  /// - 中間エピソード: 3ページ（前 + 現在 + 次）
  static int _getItemCount(int currentEpisode, int totalEpisodes) {
    if (totalEpisodes == 1) return 1;
    if (currentEpisode == 1) return 2;
    if (currentEpisode == totalEpisodes) return 2;
    return 3;
  }

  /// PageControllerの初期ページインデックスを決定する。
  ///
  /// - 第1話: 0（最初のページ）
  /// - それ以外: 1（中央のページ）
  static int _getInitialPage(int currentEpisode) {
    return currentEpisode == 1 ? 0 : 1;
  }

  /// PageViewのindexから実際のエピソード番号を計算する。
  static int _getEpisodeNumber(
    int index,
    int currentEpisode,
    int totalEpisodes,
  ) {
    if (totalEpisodes == 1) return 1;

    if (currentEpisode == 1) {
      // 第1話: [1話, 2話]
      return index + 1;
    }

    if (currentEpisode == totalEpisodes) {
      // 最終話: [totalEpisodes-1話, totalEpisodes話]
      return totalEpisodes - 1 + index;
    }

    // 中間エピソード: [current-1話, current話, current+1話]
    return currentEpisode - 1 + index;
  }

  /// ページ変更時の処理を行う。
  void _handlePageChanged(
    int index,
    ValueNotifier<int> currentEpisode,
    int totalEpisodes,
    PageController pageController,
    WidgetRef ref,
    NovelInfo novelInfo,
  ) {
    final current = currentEpisode.value;

    if (current == 1) {
      // 第1話から第2話へ移動
      if (index == 1 && totalEpisodes > 1) {
        currentEpisode.value = 2;
        _updateHistory(ref, novelInfo, 2);
      }
    } else if (current == totalEpisodes) {
      // 最終話から前のエピソードへ移動
      if (index == 0 && totalEpisodes > 1) {
        currentEpisode.value = totalEpisodes - 1;
        _updateHistory(ref, novelInfo, totalEpisodes - 1);
      }
    } else {
      // 中間エピソードの通常処理
      if (index == 0) {
        // 前のエピソードへ
        currentEpisode.value--;
        _updateHistory(ref, novelInfo, currentEpisode.value);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (pageController.hasClients) {
            pageController.jumpToPage(1);
          }
        });
      } else if (index == 2) {
        // 次のエピソードへ
        currentEpisode.value++;
        _updateHistory(ref, novelInfo, currentEpisode.value);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (pageController.hasClients) {
            pageController.jumpToPage(1);
          }
        });
      }
    }
  }

  /// AppBarに表示するタイトルを生成する。
  ///
  /// - 短編の場合: 小説タイトルのみ
  /// - 連載の場合: 「第X話 サブタイトル」または「第X話」
  @visibleForTesting
  static String buildTitle(
    NovelInfo novelInfo,
    int currentEpisodeNum,
    Episode? currentEpisode,
  ) {
    // 短編の場合はタイトルのみ
    if (novelInfo.novelType == 2) {
      return novelInfo.title ?? '';
    }

    // 連載の場合
    final subtitle = currentEpisode?.subtitle;

    // サブタイトルがある場合は「第X話 サブタイトル」
    // ない場合は「第X話」のみ
    if (subtitle != null && subtitle.isNotEmpty) {
      return '第$currentEpisodeNum話 $subtitle';
    } else {
      return '第$currentEpisodeNum話';
    }
  }
}

/// 1話分の本文のスクロール位置を、話ごとに保存・復元する。
///
/// 本文ウィジェットのスクロール位置の保存先（[PageStorage]）を
/// 差し替えることで、アプリを閉じても話の途中から読めるようにする。
class _EpisodeBookmarkScope extends HookConsumerWidget {
  const _EpisodeBookmarkScope({
    required this.positionKey,
    required this.mode,
    required this.child,
  });

  final String positionKey;
  final String mode;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 保存済みの位置を読み終えたかどうか（読み込みはすぐ終わる）
    final loaded = ref.watch(
      webReadingPositionsProvider.select((value) => !value.isLoading),
    );
    final notifier = ref.read(webReadingPositionsProvider.notifier);
    final modeRef = useRef(mode)..value = mode;
    final bucket = useMemoized(
      () {
        final saved = ref.read(webReadingPositionsProvider).value;
        return PersistentPageStorageBucket(
          initialValues: {...?saved?[positionKey]?.offsets},
          currentKey: () => modeRef.value,
          // スクロール処理の途中で状態を変えないよう、処理後に反映する
          onWrite: (key, value) => scheduleMicrotask(
            () => notifier.record(positionKey, mode: key, offset: value),
          ),
        );
      },
      [positionKey, loaded],
    );
    // 読み込みが済んだら作り直して、保存済みの位置を反映させる
    return PageStorage(
      key: ValueKey(loaded),
      bucket: bucket,
      child: child,
    );
  }
}
