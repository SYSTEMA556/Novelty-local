import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/local_library/author_profiles.dart';
import 'package:novelty/local_library/kanji_reader.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:novelty/local_library/work_meta_detector.dart';
import 'package:novelty/screens/local_library_view.dart';
import 'package:novelty/screens/local_work_reader_page.dart';

/// 1人の作者の作品一覧画面。
class LocalAuthorWorksPage extends HookConsumerWidget {
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
    final profiles =
        ref.watch(authorProfilesProvider).value ?? AuthorProfiles.empty;
    // 名前を変えるとキーも変わるため、表示中の作者のキーを覚えておく
    final currentKey = useState(authorKey);

    // 削除や名前の変更に追従できるよう、毎回グループを引き直す
    final matched = groupByAuthor(
      works,
      profiles: profiles,
      reader: ref.watch(kanjiReaderProvider).value,
    ).where((g) => g.key == currentKey.value);
    final group = matched.isEmpty ? null : matched.first;
    final authorWorks = group?.works ?? const <LocalWork>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(group?.name ?? authorName, overflow: TextOverflow.ellipsis),
        actions: [
          if (group != null && !group.isUnknown)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '作者を編集',
              onPressed: () async {
                final newName = await showEditAuthorDialog(context, ref, group);
                if (newName != null) {
                  currentKey.value = WorkMetaDetector.authorKey(newName);
                }
              },
            ),
        ],
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
                      unawaited(showLocalWorkActions(context, ref, work)),
                );
              },
            ),
    );
  }
}
