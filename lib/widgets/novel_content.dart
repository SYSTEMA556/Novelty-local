import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/repositories/novel_repository.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/font_family.dart';
import 'package:novelty/utils/line_length.dart';
import 'package:novelty/utils/reader_appearance.dart';
import 'package:novelty/utils/settings_provider.dart';
import 'package:novelty/utils/tategaki_converter.dart';
import 'package:novelty/widgets/novel_content_view.dart';
import 'package:novelty/widgets/reader_navigation.dart';
import 'package:novelty/widgets/tap_zone_guide.dart';
import 'package:tategaki/tategaki.dart';

/// 小説のコンテンツを表示するウィジェット。
class NovelContent extends HookConsumerWidget {
  /// コンストラクタ。
  const NovelContent({
    required this.source,
    required this.workId,
    required this.episode,
    this.revised,
    this.isAppBarVisible = false,
    this.onMenuTap,
    this.onOverflow,
    this.navigation,
    this.highlightStart,
    this.highlightEnd,
    this.safeBottom = true,
    super.key,
  });

  /// 提供サイト（プロバイダ）。
  final NovelSource source;

  /// サイト共通の作品ID（なろうはNコード）。
  final String workId;

  /// 小説のエピソード番号
  final int episode;

  /// 改稿日時
  final String? revised;

  /// AppBarが表示されているかどうか。
  ///
  /// `true` の場合、上部のセーフエリアはAppBarが確保するため
  /// 本文側では上部のパディングを不要にする。
  /// `false` の場合、本文側で上部のセーフエリアを確保する。
  final bool isAppBarVisible;

  /// 本文の中央をタップしたときの処理（ページボタンを有効にする）。
  final VoidCallback? onMenuTap;

  /// ページボタンで話の端を越えようとしたときの処理（1: 次の話、-1: 前の話）。
  final ValueChanged<int>? onOverflow;

  /// 全体のどこにいるかの表示・シークバーでの移動（使わなければ null）。
  final ReaderNavigation? navigation;

  /// 背景色を付ける範囲の開始（本文位置。読み上げ中の文など）。
  final int? highlightStart;

  /// 背景色を付ける範囲の終了（本文位置、含まない）。
  final int? highlightEnd;

  /// 下のセーフエリアを本文側で取るか（下に別のバーを置く場合は false）。
  final bool safeBottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final contentAsync = ref.watch(
      novelContentProvider(
        source: source,
        workId: workId,
        episode: episode,
        revised: revised,
      ),
    );

    return SafeArea(
      top: !isAppBarVisible, // AppBarが表示されている場合は上は不要
      bottom: safeBottom,
      child: NovelContentBody(
        source: source,
        workId: workId,
        episode: episode,
        settings: settings,
        content: contentAsync,
        onMenuTap: onMenuTap,
        onOverflow: onOverflow,
        navigation: navigation,
        highlightStart: highlightStart,
        highlightEnd: highlightEnd,
      ),
    );
  }
}

/// 設定とコンテンツの状態に応じて表示を切り替えるウィジェット。
///
/// サイトから取得した本文だけでなく、ローカルのテキストファイルの
/// 表示にも再利用する。
class NovelContentBody extends HookWidget {
  /// コンストラクタ
  const NovelContentBody({
    required this.workId,
    required this.episode,
    required this.settings,
    required this.content,
    this.source,
    this.highlightStart,
    this.highlightEnd,
    this.navigation,
    this.onMenuTap,
    this.onOverflow,
    super.key,
  });

  /// 提供サイト（プロバイダ）。ローカルファイル表示時は null。
  final NovelSource? source;

  /// サイト共通の作品ID（なろうはNコード）。
  ///
  /// スクロール位置を保存するキーにも使用する。
  final String workId;

  /// 小説のエピソード番号
  final int episode;

  /// 設定の状態
  final AsyncValue<AppSettings> settings;

  /// コンテンツの状態
  final AsyncValue<List<NovelContentElement>> content;

  /// 背景色を付ける範囲の開始（本文位置。読み上げ中の文など）
  final int? highlightStart;

  /// 背景色を付ける範囲の終了（本文位置、含まない）
  final int? highlightEnd;

  /// 全体のどこにいるかの表示・シークバーでの移動（使わなければ null）
  final ReaderNavigation? navigation;

  /// 本文の中央（ページボタン以外）をタップしたときの処理。
  ///
  /// 指定するとページボタンが有効になる（読書画面で使う）。
  final VoidCallback? onMenuTap;

  /// ページボタンで端を越えて進もう（1）・戻ろう（-1）としたときの処理
  /// （Web小説で前後の話へ移るのに使う）。
  final ValueChanged<int>? onOverflow;

  @override
  Widget build(BuildContext context) {
    // テーマのbrightnessとテキストカラーの計算をメモ化
    final textColor = useMemoized(() {
      final brightness = Theme.of(context).brightness;
      return brightness == Brightness.dark ? Colors.white : Colors.black;
    }, [Theme.of(context).brightness]);

    // エピソード表示中は常にimmersiveStickyモードを設定
    useEffect(() {
      Future<void> setUiMode() async {
        try {
          // 縦書き・横書き問わず常にimmersiveStickyを使用
          await SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.immersiveSticky,
          );
        } on PlatformException catch (e, s) {
          // プラットフォームチャネルのエラーをログに出力
          debugPrint('Failed to set SystemUIMode: $e\n$s');
        }
      }

      // エピソード表示中は常にUIモードを設定
      unawaited(setUiMode());

      // クリーンアップ: ウィジェット破棄時はedgeToEdgeに戻す
      return () {
        unawaited(
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.edgeToEdge,
          ).catchError((Object e, StackTrace s) {
            debugPrint('Failed to reset SystemUIMode on dispose: $e\n$s');
          }),
        );
      };
    }, [settings]);

    // 縦書き要素への変換をメモ化する。
    // 同一のコンテンツ・ルビ設定なら同じリストインスタンスを返すことで、
    // TategakiText / TategakiTextPaged 側のレイアウトキャッシュが有効になる。
    final contentData = content.value;
    final settingsData = settings.value;
    final conversion = useMemoized(
      () => contentData == null
          ? null
          : TategakiConverter.convertWithOffsets(
              contentData,
              isRubyEnabled: settingsData?.isRubyEnabled ?? true,
            ),
      [contentData, settingsData?.isRubyEnabled],
    );
    final tategakiElements = conversion?.elements;
    // 外から渡されなければ自前で持つ（ページボタンでの移動に使う）
    final ownNavigation = useMemoized(ReaderNavigation.new);
    useEffect(() => ownNavigation.dispose, [ownNavigation]);
    final nav = navigation ?? ownNavigation
      ..tategakiElementCount = tategakiElements?.length ?? 0;

    // 読み上げ中の文などに付ける背景色
    final highlightColor = Theme.of(
      context,
    ).colorScheme.primaryContainer.withValues(alpha: 0.6);
    final hlStart = highlightStart;
    final hlEnd = highlightEnd;
    TategakiHighlight? tategakiHighlight;
    if (conversion != null && hlStart != null && hlEnd != null) {
      final range = conversion.elementRange(hlStart, hlEnd);
      tategakiHighlight = TategakiHighlight(
        start: range.start,
        end: range.end,
        color: highlightColor,
      );
    }

    return settings.when(
      data: (settingsData) {
        final body = content.when(
          data: (contentData) {
            // 小説本文は固定のバンドルフォント(源暎こぶり明朝)を使用する
            final textStyle = TextStyle(
              fontSize: settingsData.fontSize,
              color: settingsData.colorTheme.text ?? textColor,
              fontFamily: novelBodyFontFamily,
              height: settingsData.lineHeight,
            );

            // システムジェスチャーエリアを考慮したパディング計算
            // SafeAreaが既にpaddingを適用し、その上にsystemGestureInsetsを追加
            // デスクトップ環境ではsystemGestureInsetsが0なので、最低16pxを確保
            final systemGestureInsets = MediaQuery.of(
              context,
            ).systemGestureInsets;

            // 縦書きモード用（横スクロール）: 左右端のバックジェスチャー領域を確保
            final verticalModePadding = EdgeInsets.only(
              left: math.max(16, systemGestureInsets.left),
              right: math.max(16, systemGestureInsets.right),
              top: 16,
              bottom: 16,
            );

            // 1行の長さの上限（設定で制限している場合のみ）
            final lineLimit = lineExtentLimit(
              maxChars: settingsData.maxLineChars,
              fontSize: settingsData.fontSize,
            );

            // 横書きモード用（縦スクロール）: 下端のホームジェスチャー領域を確保
            final horizontalModePadding = EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: math.max(16, systemGestureInsets.bottom),
            );

            if (settingsData.isVertical) {
              final elements = tategakiElements!;

              if (settingsData.isPageFlip) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    // 列の高さを上限までに抑え、余りは下の余白にする
                    // （ページ全体はめくり操作を受け付けたままにするため、
                    // 領域は縮めずに余白で調整する）
                    final available =
                        constraints.maxHeight - verticalModePadding.vertical;
                    final extra =
                        available - clampLineExtent(available, lineLimit);
                    return DefaultTextStyle(
                      style: textStyle,
                      child: TategakiTextPaged(
                        key: PageStorageKey<String>(
                          'novel_paged_${workId}_$episode',
                        ),
                        elements,
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        highlight: tategakiHighlight,
                        controller: nav.pageController,
                        onPageCountChanged: (count) =>
                            nav.pageCount.value = count,
                        padding: verticalModePadding.copyWith(
                          bottom: verticalModePadding.bottom + extra,
                        ),
                      ),
                    );
                  },
                );
              }

              // スクロールモード: TategakiText が列単位の遅延レンダリングを行う
              // （ListView.builder による無限リスト）。スクロール位置は
              // PageStorageKey を介して TategakiText 内部の ListView に渡る。
              return Directionality(
                textDirection: TextDirection.rtl,
                child: Padding(
                  padding: verticalModePadding,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return DefaultTextStyle(
                        style: textStyle,
                        child: TategakiText(
                          elements,
                          key: PageStorageKey<String>(
                            'novel_vertical_${workId}_$episode',
                          ),
                          highlight: tategakiHighlight,
                          controller: nav.tategakiController,
                          onVisibleElementChanged: nav.onVisibleTategakiElement,
                          // 列の高さを上限までに抑える（上詰め）
                          height: clampLineExtent(
                            constraints.maxHeight,
                            lineLimit,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            }

            return SingleChildScrollView(
              key: PageStorageKey<String>(
                'novel_horizontal_${workId}_$episode',
              ),
              controller: nav.horizontalController,
              padding: horizontalModePadding,
              // 行の幅を上限までに抑え、画面の中央に置く
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: lineLimit ?? double.infinity,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: RepaintBoundary(
                      child: DefaultTextStyle(
                        style: textStyle,
                        child: NovelContentView(
                          elements: contentData,
                          isRubyEnabled: settingsData.isRubyEnabled,
                          highlightStart: highlightStart,
                          highlightEnd: highlightEnd,
                          highlightColor: highlightColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err')),
        );
        return _decorate(settingsData, nav, body);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }

  /// 色調の背景と、ページボタン（タップでのページ送り）を付ける。
  Widget _decorate(AppSettings settings, ReaderNavigation nav, Widget body) {
    var result = body;
    final menu = onMenuTap;
    if (menu != null) {
      final config = settings.tapZoneConfig;
      final guideOpacity = settings.tapZoneGuideOpacity / 100;
      result = LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (details) {
              final action =
                  config?.actionAt(
                    details.localPosition,
                    size,
                    isVertical: settings.isVertical,
                  ) ??
                  TapAction.menu;
              switch (action) {
                case TapAction.menu:
                  menu();
                case TapAction.next:
                case TapAction.previous:
                  final direction = action == TapAction.next ? 1 : -1;
                  final moved = nav.move(
                    direction,
                    isVertical: settings.isVertical,
                    isPageFlip: settings.isPageFlip,
                  );
                  if (!moved) onOverflow?.call(direction);
              }
            },
            child: Stack(
              children: [
                Positioned.fill(child: body),
                // ページボタンの場所を薄く示す（設定で濃さを 0 にすると非表示）
                if (config != null && guideOpacity > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: TapZoneGuide(
                        config: config,
                        isVertical: settings.isVertical,
                        opacity: guideOpacity,
                        showLabels: false,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
    }
    final background = settings.colorTheme.background;
    if (background != null) {
      result = ColoredBox(color: background, child: result);
    }
    return result;
  }
}
