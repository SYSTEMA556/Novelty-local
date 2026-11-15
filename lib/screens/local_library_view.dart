import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:novelty/screens/local_bookmarks_page.dart';
import 'package:novelty/screens/local_import.dart';
import 'package:novelty/screens/local_work_reader_page.dart';

/// ローカル作品の並び順。
enum LocalSort {
  /// タイトル順。
  title('タイトル順'),

  /// 追加が新しい順。
  added('追加順'),

  /// 最近読んだ順。
  recent('最近読んだ順');

  const LocalSort(this.label);

  /// 表示名。
  final String label;
}

/// 検索語と並び順を適用した作品一覧を返す。
List<LocalWork> filterAndSortWorks(
  List<LocalWork> works,
  Map<String, ReadingPosition> positions, {
  required String query,
  required LocalSort sort,
}) {
  final q = query.trim().toLowerCase();
  final result = q.isEmpty
      ? [...works]
      : works.where((w) => w.title.toLowerCase().contains(q)).toList();

  switch (sort) {
    case LocalSort.title:
      result.sort((a, b) => a.title.compareTo(b.title));
    case LocalSort.added:
      result.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    case LocalSort.recent:
      // 未読の作品は後ろ（タイトル順）に回す
      result.sort((a, b) {
        final pa = positions[a.id]?.updatedAt;
        final pb = positions[b.id]?.updatedAt;
        if (pa == null && pb == null) return a.title.compareTo(b.title);
        if (pa == null) return 1;
        if (pb == null) return -1;
        return pb.compareTo(pa);
      });
  }
  return result;
}

/// ライブラリ画面の「ローカル」タブ。
class LocalLibraryView extends HookConsumerWidget {
  /// コンストラクタ。
  const LocalLibraryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worksAsync = ref.watch(localWorksProvider);
    final positions =
        ref.watch(readingPositionsProvider).value ??
        const <String, ReadingPosition>{};
    final query = useState('');
    final sort = useState(LocalSort.title);

    final allWorks = worksAsync.value;
    final works = useMemoized(
      () => allWorks == null
          ? const <LocalWork>[]
          : filterAndSortWorks(
              allWorks,
              positions,
              query: query.value,
              sort: sort.value,
            ),
      [allWorks, positions, query.value, sort.value],
    );

    final toolbar = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'タイトルで検索',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => query.value = value,
            ),
          ),
          PopupMenuButton<LocalSort>(
            icon: const Icon(Icons.sort),
            tooltip: '並び替え',
            initialValue: sort.value,
            onSelected: (value) => sort.value = value,
            itemBuilder: (_) => [
              for (final s in LocalSort.values)
                PopupMenuItem(value: s, child: Text(s.label)),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.bookmarks_outlined),
            tooltip: 'しおり一覧',
            onPressed: () => unawaited(
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LocalBookmarksPage(),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '取り込み',
            onPressed: () => unawaited(showLocalImportSheet(context, ref)),
          ),
        ],
      ),
    );

    return Column(
      children: [
        toolbar,
        Expanded(
          child: worksAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('読み込めませんでした: $e')),
            data: (all) {
              if (all.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('ローカルの作品はまだありません'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('テキストファイルを取り込む'),
                        onPressed: () =>
                            unawaited(showLocalImportSheet(context, ref)),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${works.length} / ${all.length} 件',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: works.length,
                      itemBuilder: (context, index) {
                        final work = works[index];
                        return LocalWorkTile(
                          work: work,
                          position: positions[work.id],
                          onTap: () => unawaited(openLocalWork(context, work)),
                          onLongPress: () =>
                              unawaited(_confirmDelete(context, ref, work)),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    LocalWork work,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除の確認'),
        content: Text('"${work.title}"をローカルライブラリから削除しますか？\n'
            'しおりも削除されます（元のファイルは残ります）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(localWorksProvider.notifier).delete({work.id});
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('削除しました')));
    }
  }
}

/// ローカル作品の1行表示。
class LocalWorkTile extends StatelessWidget {
  /// コンストラクタ。
  const LocalWorkTile({
    required this.work,
    required this.position,
    required this.onTap,
    this.onLongPress,
    this.showLastRead = false,
    super.key,
  });

  /// 作品。
  final LocalWork work;

  /// 読書位置（未読なら null）。
  final ReadingPosition? position;

  /// タップ時の処理。
  final VoidCallback onTap;

  /// 長押し時の処理。
  final VoidCallback? onLongPress;

  /// 最終閲覧日時を表示するか。
  final bool showLastRead;

  @override
  Widget build(BuildContext context) {
    final pos = position;
    final details = [
      formatCharCount(work.charCount),
      if (pos != null) '${(pos.progress * 100).round()}%',
      if (pos != null && showLastRead) formatDateTime(pos.updatedAt),
    ].join('・');

    return ListTile(
      leading: Icon(
        pos == null ? Icons.description_outlined : Icons.bookmark,
        color: pos == null ? null : Theme.of(context).colorScheme.primary,
      ),
      title: Text(work.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(details),
          if (pos != null) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(value: pos.progress),
          ],
        ],
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// 文字数を「1.2万字」のように整形する。
String formatCharCount(int count) {
  if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万字';
  return '$count字';
}

/// 日時を `YYYY/MM/DD HH:mm` 形式に整形する。
String formatDateTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}/${two(t.month)}/${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
