import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/providers/ranking_provider.dart';
import 'package:novelty/router/router.dart';
import 'package:novelty/sites/novel_site_registry.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/settings_provider.dart';
import 'package:novelty/widgets/novel_card.dart';
import 'package:novelty/widgets/novel_list_tile.dart';

/// ランキングリストを表示するウィジェット。
class RankingList extends HookConsumerWidget {
  /// コンストラクタ。
  const RankingList({
    required this.source,
    required this.rankingType,
    super.key,
  });

  /// 提供サイト（プロバイダ）。
  final NovelSource source;

  /// ランキングの種類。
  final String rankingType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // RankingNotifierから状態を取得
    final rankingState = ref.watch(rankingProvider(source, rankingType));

    // スクロール通知を監視するためのリスナー
    final scrollController = useScrollController();

    // 無限スクロールの検知
    // NotificationListenerを使用しても良いが、ScrollControllerで制御するほうが一般的
    // 下端に近づいたら次のページを読み込む
    useEffect(() {
      void onScroll() {
        if (!scrollController.hasClients) return;
        final maxScroll = scrollController.position.maxScrollExtent;
        final currentScroll = scrollController.offset;

        // 画面の高さの0.8倍手前で読み込み開始
        if (currentScroll >= (maxScroll * 0.8)) {
          unawaited(
            ref
                .read(rankingProvider(source, rankingType).notifier)
                .fetchNextPage(),
          );
        }
      }

      scrollController.addListener(onScroll);
      return () => scrollController.removeListener(onScroll);
    }, [scrollController]);

    // 初回ロード失敗時のリトライボタン
    if (rankingState.error != null && rankingState.novels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('読み込みに失敗しました'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                unawaited(
                  ref
                      .read(rankingProvider(source, rankingType).notifier)
                      .refresh(),
                );
              },
              child: const Text('リトライ'),
            ),
          ],
        ),
      );
    }

    if (rankingState.isLoading && rankingState.novels.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // カード表示（フォークで追加）
    final cardView =
        ref.watch(settingsProvider.select((s) => s.value?.rankingCardView)) ??
        false;
    if (cardView) {
      return RefreshIndicator(
        onRefresh: () async {
          await ref
              .read(rankingProvider(source, rankingType).notifier)
              .refresh();
        },
        child: GridView.builder(
          controller: scrollController,
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.72,
          ),
          itemCount:
              rankingState.novels.length +
              (rankingState.isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == rankingState.novels.length) {
              return const Center(child: CircularProgressIndicator());
            }
            return RankingCard(
              novel: rankingState.novels[index],
              rank: index + 1,
            );
          },
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(rankingProvider(source, rankingType).notifier).refresh();
      },
      child: ListView.builder(
        controller: scrollController,
        // アイテム数 + ローディングインジケータ（必要な場合）
        itemCount:
            rankingState.novels.length + (rankingState.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == rankingState.novels.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final novel = rankingState.novels[index];
          // 順位は現在のリストのインデックス + 1
          final rank = index + 1;

          return NovelListTile(
            item: novel,
            rank: rank,
            // enrichedData: ... ライブラリ状態が必要ならここで取得
          );
        },
      ),
    );
  }
}

/// ランキングの1作品のカード（フォークで追加）。
///
/// 背景の色はサイトとジャンルで決まる（同じジャンルは同じ色）。
class RankingCard extends StatelessWidget {
  /// コンストラクタ。
  const RankingCard({required this.novel, required this.rank, super.key});

  /// 作品。
  final NovelInfo novel;

  /// 順位。
  final int rank;

  @override
  Widget build(BuildContext context) {
    final site = defaultNovelSiteRegistry[novel.source]!;
    final genreId = novel.genreId;
    final genre = genreId == null
        ? null
        : site.genres.where((g) => g.id == genreId).firstOrNull?.name;
    final status = novel.novelType == 2
        ? '短編'
        : novel.end == 1
        ? '連載'
        : '完結';
    final episodes = novel.generalAllNo;
    final meta = [
      ?site.metaText(novel),
      if (novel.novelType != 2 && episodes != null) '全$episodes話',
    ].join('・');
    return NovelCard(
      title: novel.title ?? 'タイトルなし',
      colorSeed: '${novel.source.name}:${genreId ?? ''}',
      rank: rank,
      label: genre,
      blurb: novelCardBlurb(novel.story),
      badge: status,
      meta: meta.isEmpty ? null : meta,
      onTap: () {
        final workId = novel.workId ?? novel.ncode;
        if (workId == null) return;
        unawaited(
          NovelDetailRoute(
            source: novel.source.name,
            workId: workId,
          ).push(context),
        );
      },
    );
  }
}
