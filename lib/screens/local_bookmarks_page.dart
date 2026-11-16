import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:novelty/screens/local_library_view.dart';
import 'package:novelty/screens/local_work_reader_page.dart';

/// しおり一覧画面。
///
/// 読みかけのローカル作品を最近読んだ順に並べ、続きから開けるようにする。
class LocalBookmarksPage extends StatelessWidget {
  /// コンストラクタ。
  const LocalBookmarksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('しおり一覧')),
      body: const LocalReadingHistoryList(),
    );
  }
}

/// 読んだことのあるローカル作品を、最近読んだ順に並べた一覧。
///
/// しおり一覧画面と、履歴画面の「ローカル」タブで使う。
class LocalReadingHistoryList extends ConsumerWidget {
  /// コンストラクタ。
  const LocalReadingHistoryList({this.allowDelete = false, super.key});

  /// 各行に履歴の削除ボタンを出すか。
  final bool allowDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worksAsync = ref.watch(localWorksProvider);
    final positionsAsync = ref.watch(readingPositionsProvider);
    final works = worksAsync.value;
    final positions = positionsAsync.value;
    final error = worksAsync.error ?? positionsAsync.error;

    if (error != null) {
      return Center(child: Text('読み込めませんでした: $error'));
    }
    if (works == null || positions == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final byId = {for (final w in works) w.id: w};
    final entries = [
      for (final entry in positions.entries)
        if (byId.containsKey(entry.key)) entry,
    ]..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));

    if (entries.isEmpty) {
      return const Center(child: Text('読んだローカル作品はまだありません'));
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final work = byId[entry.key]!;
        return LocalWorkTile(
          work: work,
          position: entry.value,
          showLastRead: true,
          onTap: () => unawaited(openLocalWork(context, work)),
          trailing: allowDelete
              ? IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '履歴から削除',
                  onPressed: () => ref
                      .read(readingPositionsProvider.notifier)
                      .forget(work.id),
                )
              : null,
        );
      },
    );
  }
}
