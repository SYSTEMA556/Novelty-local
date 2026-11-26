/// ライブラリの「しおり」タブ（フォークで追加）。
///
/// 長押しで挟んだしおりを、ローカルの本棚・なろう・カクヨムをまとめて
/// 新しい順に並べる。どこの作品かは小さな色付きの札で見分ける。
/// 押すとその場所を開き、🗣 でそこから読み上げる。
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
    required this.origin,
    required this.title,
    required this.snippet,
    required this.place,
    required this.createdAt,
    required this.open,
    required this.remove,
  });

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
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final row = rows[index];
        final theme = Theme.of(context);
        return ListTile(
          onTap: () => row.open(readAloud: false),
          title: Row(
            children: [
              _OriginChip(origin: row.origin),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  row.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(row.snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
              Text(row.place, style: theme.textTheme.bodySmall),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.record_voice_over_outlined),
                tooltip: 'ここから読み上げ',
                onPressed: () => row.open(readAloud: true),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '外す',
                onPressed: row.remove,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 出どころの小さな色付きの札。
class _OriginChip extends StatelessWidget {
  const _OriginChip({required this.origin});

  final PinOrigin origin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: origin.color.withValues(alpha: 0.12),
        border: Border.all(color: origin.color),
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
