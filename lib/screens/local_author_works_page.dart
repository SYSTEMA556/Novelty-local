import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:novelty/screens/local_library_view.dart';
import 'package:novelty/screens/local_work_reader_page.dart';

/// 1人の作者の作品一覧画面。
class LocalAuthorWorksPage extends ConsumerWidget {
  /// コンストラクタ。
  const LocalAuthorWorksPage({
    required this.authorKey,
    required this.authorName,
    super.key,
  });

  /// グループ分けのキー（作者不明は空文字）。
  final String authorKey;

  /// 表示名。
  final String authorName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final works = ref.watch(localWorksProvider).value ?? const <LocalWork>[];
    final positions =
        ref.watch(readingPositionsProvider).value ??
        const <String, ReadingPosition>{};

    // 削除などで一覧が変わっても追従できるよう、毎回グループを引き直す
    final group = groupByAuthor(works).where((g) => g.key == authorKey);
    final authorWorks = group.isEmpty ? const <LocalWork>[] : group.first.works;

    return Scaffold(
      appBar: AppBar(
        title: Text(authorName, overflow: TextOverflow.ellipsis),
      ),
      body: authorWorks.isEmpty
          ? const Center(child: Text('作品がありません'))
          : ListView.builder(
              itemCount: authorWorks.length,
              itemBuilder: (context, index) {
                final work = authorWorks[index];
                return LocalWorkTile(
                  work: work,
                  position: positions[work.id],
                  showAuthor: false,
                  onTap: () => unawaited(openLocalWork(context, work)),
                  onLongPress: () =>
                      unawaited(confirmDeleteLocalWork(context, ref, work)),
                );
              },
            ),
    );
  }
}
