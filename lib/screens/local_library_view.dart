import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:novelty/local_library/work_meta_detector.dart';
import 'package:novelty/screens/local_author_works_page.dart';
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
      : works
            .where(
              (w) =>
                  w.title.toLowerCase().contains(q) ||
                  (w.author?.toLowerCase().contains(q) ?? false),
            )
            .toList();

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

/// ローカルタブの表示単位。
enum LocalViewMode {
  /// 作品ごと。
  works,

  /// 作者ごと。
  authors,
}

/// 作者ごとの作品のまとまり。
class AuthorGroup {
  /// コンストラクタ。
  const AuthorGroup({required this.key, required this.name, required this.works});

  /// グループ分けのキー（作者不明は空文字）。
  final String key;

  /// 表示名。
  final String name;

  /// この作者の作品。
  final List<LocalWork> works;

  /// 作者不明のグループか。
  bool get isUnknown => key.isEmpty;
}

/// 作者不明の作品をまとめるグループの表示名。
const unknownAuthorLabel = '作者不明';

/// 作品を作者ごとにまとめる。
///
/// 表記揺れ（全角/半角・空白）は同じ作者として扱い、名前順に並べる。
/// 作者不明は最後に置く。[query] は作者名で絞り込む。
List<AuthorGroup> groupByAuthor(List<LocalWork> works, {String query = ''}) {
  final byKey = <String, List<LocalWork>>{};
  final names = <String, String>{};
  for (final work in works) {
    final author = work.author;
    final key = author == null ? '' : WorkMetaDetector.authorKey(author);
    byKey.putIfAbsent(key, () => []).add(work);
    names.putIfAbsent(key, () => author ?? unknownAuthorLabel);
  }

  final q = query.trim().toLowerCase();
  final groups = [
    for (final entry in byKey.entries)
      if (q.isEmpty || names[entry.key]!.toLowerCase().contains(q))
        AuthorGroup(
          key: entry.key,
          name: names[entry.key]!,
          works: entry.value..sort((a, b) => a.title.compareTo(b.title)),
        ),
  ]..sort((a, b) {
      if (a.isUnknown != b.isUnknown) return a.isUnknown ? 1 : -1;
      // 正規化したキーで並べ、全角・半角の違いで順番がずれないようにする
      return a.key.compareTo(b.key);
    });
  return groups;
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
    final viewMode = useState(LocalViewMode.works);

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
    final groups = useMemoized(
      () => allWorks == null
          ? const <AuthorGroup>[]
          : groupByAuthor(allWorks, query: query.value),
      [allWorks, query.value],
    );
    final isAuthorMode = viewMode.value == LocalViewMode.authors;

    final toolbar = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                hintText: '作品名・作者名で検索',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => query.value = value,
            ),
          ),
          if (!isAuthorMode)
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
              final countText = isAuthorMode
                  ? '${groups.length} 人'
                  : '${works.length} / ${all.length} 件';
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 16, 4),
                    child: Row(
                      children: [
                        // 作品ごと／作者ごとの表示切り替え
                        SegmentedButton<LocalViewMode>(
                          segments: const [
                            ButtonSegment(
                              value: LocalViewMode.works,
                              label: Text('作品'),
                              icon: Icon(Icons.description_outlined),
                            ),
                            ButtonSegment(
                              value: LocalViewMode.authors,
                              label: Text('作者'),
                              icon: Icon(Icons.person_outline),
                            ),
                          ],
                          selected: {viewMode.value},
                          showSelectedIcon: false,
                          onSelectionChanged: (selection) =>
                              viewMode.value = selection.first,
                        ),
                        const Spacer(),
                        Text(
                          countText,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: isAuthorMode
                        ? _AuthorList(groups: groups, positions: positions)
                        : ListView.builder(
                            itemCount: works.length,
                            itemBuilder: (context, index) {
                              final work = works[index];
                              return LocalWorkTile(
                                work: work,
                                position: positions[work.id],
                                onTap: () =>
                                    unawaited(openLocalWork(context, work)),
                                onLongPress: () => unawaited(
                                  confirmDeleteLocalWork(context, ref, work),
                                ),
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

}

/// 作者ごとの一覧。
class _AuthorList extends StatelessWidget {
  const _AuthorList({required this.groups, required this.positions});

  final List<AuthorGroup> groups;
  final Map<String, ReadingPosition> positions;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final readCount = group.works
            .where((w) => positions.containsKey(w.id))
            .length;
        return ListTile(
          leading: Icon(
            group.isUnknown ? Icons.help_outline : Icons.person_outline,
          ),
          title: Text(group.name),
          subtitle: Text(
            readCount == 0
                ? '${group.works.length} 作品'
                : '${group.works.length} 作品・読みかけ $readCount',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LocalAuthorWorksPage(
                  authorKey: group.key,
                  authorName: group.name,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// ローカル作品の削除を確認し、承認されたら削除する。
Future<void> confirmDeleteLocalWork(
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

/// ローカル作品の1行表示。
class LocalWorkTile extends StatelessWidget {
  /// コンストラクタ。
  const LocalWorkTile({
    required this.work,
    required this.position,
    required this.onTap,
    this.onLongPress,
    this.showLastRead = false,
    this.showAuthor = true,
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

  /// 作者名を表示するか（作者別の画面では不要）。
  final bool showAuthor;

  @override
  Widget build(BuildContext context) {
    final pos = position;
    final author = work.author;
    final details = [
      if (showAuthor && author != null) author,
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
