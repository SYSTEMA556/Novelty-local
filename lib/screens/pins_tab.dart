/// ライブラリの「しおり」タブ（フォークで追加）。
///
/// 長押しで挟んだしおりを、本ごとに1枚のカードにまとめて並べる
/// （ローカルの本棚・なろう・カクヨムをまとめて、最近挟んだ本から）。
/// カードの背景はローカルの本棚のグリッドと同じく本ごとの色で、
/// どこの作品かは小さな色付きの札で見分ける。カードの中の線には、
/// しおりが本のどの辺りにあるかを点で示す。
/// しおりを押すとその場所を開き、🗣 でそこから読み上げる。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:novelty/screens/local_work_reader_page.dart';
import 'package:novelty/screens/novel_page.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/web_pins.dart';
import 'package:novelty/widgets/novel_card.dart';
import 'package:novelty/widgets/pinned_bookmarks_sheet.dart';

/// しおりの出どころ。
enum PinOrigin {
  /// ローカルの本棚。
  local('ローカル', Color(0xFF2E7D32)),

  /// 小説家になろう。
  narou('なろう', Color(0xFF1565C0)),

  /// カクヨム。
  kakuyomu('カクヨム', Color(0xFFE65100));

  const PinOrigin(this.label, this.color);

  /// 札の文字。
  final String label;

  /// 札の色。
  final Color color;

  /// Web 小説のサイトから。
  static PinOrigin of(NovelSource source) => switch (source) {
    NovelSource.narou => narou,
    NovelSource.kakuyomu => kakuyomu,
  };
}

/// 一覧の1行（ローカルと Web をまとめて扱うため）。
class _PinRow {
  const _PinRow({
    required this.bookKey,
    required this.colorSeed,
    required this.timeline,
    required this.order,
    required this.origin,
    required this.title,
    required this.snippet,
    required this.place,
    required this.createdAt,
    required this.open,
    required this.remove,
  });

  // 同じ本のしおりをまとめるための鍵
  final String bookKey;
  // カードの背景色を決める文字列
  final String colorSeed;
  // 本全体のどの辺りか（0〜1。Web 小説は話の中の位置しか分からないので null）
  final double? timeline;
  // 本の中での並び順（ローカルは位置、Web 小説は話の番号＋話の中の位置）
  final double order;
  final PinOrigin origin;
  final String title;
  final String snippet;
  final String place;
  final DateTime createdAt;
  final void Function({required bool readAloud}) open;
  final VoidCallback remove;
}

/// ライブラリの「しおり」タブの中身。
class AllPinsView extends ConsumerWidget {
  /// コンストラクタ。
  const AllPinsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final works = {
      for (final w in ref.watch(localWorksProvider).value ?? <LocalWork>[])
        w.id: w,
    };
    final positions =
        ref.watch(readingPositionsProvider).value ??
        const <String, ReadingPosition>{};
    final webPins = ref.watch(webPinsProvider).value ?? const <WebPin>[];
    final positionsNotifier = ref.read(readingPositionsProvider.notifier);
    final webNotifier = ref.read(webPinsProvider.notifier);

    final rows = <_PinRow>[
      for (final entry in positions.entries)
        if (works[entry.key] case final work?)
          for (final pin in entry.value.pins)
            _PinRow(
              bookKey: 'local:${work.id}',
              colorSeed: 'local:${work.author ?? ''}',
              timeline: pin.fraction,
              order: pin.fraction,
              origin: PinOrigin.local,
              title: work.title,
              snippet: pin.snippet,
              place: pinPercent(pin.fraction),
              createdAt: pin.createdAt,
              open: ({required readAloud}) => unawaited(
                openLocalWork(
                  context,
                  work,
                  pin: pin,
                  readFromPin: readAloud,
                ),
              ),
              remove: () => positionsNotifier.removePin(work.id, pin),
            ),
      for (final pin in webPins)
        _PinRow(
          bookKey: 'web:${pin.source.name}:${pin.workId}',
          colorSeed: 'web:${pin.source.name}:${pin.workId}',
          timeline: null,
          order: pin.episode + pin.fraction.clamp(0.0, 0.999),
          origin: PinOrigin.of(pin.source),
          title: pin.title,
          snippet: pin.snippet,
          place: '第${pin.episode}話・${pinPercent(pin.fraction)}',
          createdAt: pin.createdAt,
          open: ({required readAloud}) => unawaited(
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute<void>(
                builder: (_) => NovelPage(
                  source: pin.source,
                  workId: pin.workId,
                  episode: pin.episode,
                  initialFraction: pin.fraction,
                  initialReadAloudOffset: readAloud ? pin.offset : null,
                ),
              ),
            ),
          ),
          remove: () => unawaited(webNotifier.remove(pin)),
        ),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'まだしおりはありません。\n読書画面で本文を長押しすると挟めます。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    // 本ごとにまとめる（最近挟んだ本から。本の中は場所の順）
    final books = <String, List<_PinRow>>{};
    for (final row in rows) {
      books.putIfAbsent(row.bookKey, () => []).add(row);
    }
    final cards = books.values.toList();
    for (final pins in cards) {
      pins.sort((a, b) => a.order.compareTo(b.order));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: cards.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _BookPinsCard(pins: cards[index]),
    );
  }
}

/// 1冊ぶんのしおりのカード。
class _BookPinsCard extends StatelessWidget {
  const _BookPinsCard({required this.pins});

  final List<_PinRow> pins;

  @override
  Widget build(BuildContext context) {
    final first = pins.first;
    final theme = Theme.of(context);
    final base = novelCardColor(first.colorSeed);
    final dark = HSLColor.fromColor(base).withLightness(0.16).toColor();
    const onCard = Colors.white;
    final dim = onCard.withValues(alpha: 0.75);
    final timeline = [
      for (final p in pins)
        if (p.timeline case final t?) t,
    ];

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [base, dark],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 札と題名
              Row(
                children: [
                  _OriginChip(origin: first.origin, onDark: true),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      first.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: onCard,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '🔖${pins.length}',
                      style: theme.textTheme.labelMedium?.copyWith(color: dim),
                    ),
                  ),
                ],
              ),
              // 本のどの辺りにしおりがあるか（ローカルの本だけ）
              if (timeline.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 8, 4),
                  child: _PinTimeline(points: timeline, color: onCard),
                ),
              const SizedBox(height: 4),
              for (final pin in pins)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => pin.open(readAloud: false),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 8),
                          child: Icon(Icons.bookmark, size: 18, color: dim),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pin.snippet,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: onCard,
                                  height: 1.4,
                                ),
                              ),
                              Text(
                                pin.place,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: dim,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.record_voice_over_outlined,
                            color: dim,
                            size: 20,
                          ),
                          tooltip: 'ここから読み上げ',
                          onPressed: () => pin.open(readAloud: true),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.close, color: dim, size: 20),
                          tooltip: '外す',
                          onPressed: pin.remove,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 本の長さを1本の線にし、しおりの場所に点を打つ。
class _PinTimeline extends StatelessWidget {
  const _PinTimeline({required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 2,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              for (final p in points)
                Positioned(
                  left: p.clamp(0.0, 1.0) * (width - 10),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 出どころの小さな色付きの札。
class _OriginChip extends StatelessWidget {
  const _OriginChip({required this.origin, this.onDark = false});

  final PinOrigin origin;

  // 暗いカードの上に置くときは、白地に色文字にする
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: onDark ? Colors.white : origin.color.withValues(alpha: 0.12),
        border: Border.all(color: onDark ? Colors.white : origin.color),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        origin.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: origin.color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
