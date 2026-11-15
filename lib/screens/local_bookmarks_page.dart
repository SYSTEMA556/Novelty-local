import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:novelty/screens/local_library_view.dart';
import 'package:novelty/screens/local_work_reader_page.dart';

/// しおり一覧画面。
///
/// 読みかけのローカル作品を最近読んだ順に並べ、続きから開けるようにする。
class LocalBookmarksPage extends ConsumerWidget {
  /// コンストラクタ。
  const LocalBookmarksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worksAsync = ref.watch(localWorksProvider);
    final positionsAsync = ref.watch(readingPositionsProvider);

    final works = worksAsync.value;
    final positions = positionsAsync.value;
    final error = worksAsync.error ?? positionsAsync.error;

    final Widget body;
    if (error != null) {
      body = Center(child: Text('読み込めませんでした: $error'));
    } else if (works == null || positions == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final byId = {for (final w in works) w.id: w};
      final entries = [
        for (final entry in positions.entries)
          if (byId.containsKey(entry.key)) entry,
      ]..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));

      body = entries.isEmpty
          ? const Center(child: Text('読みかけの作品はまだありません'))
          : ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final work = byId[entry.key]!;
                return LocalWorkTile(
                  work: work,
                  position: entry.value,
                  showLastRead: true,
                  onTap: () => unawaited(openLocalWork(context, work)),
                );
              },
            );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('しおり一覧')),
      body: body,
    );
  }
}
