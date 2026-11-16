import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/local_library/author_profiles.dart';
import 'package:novelty/local_library/kana_index.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:novelty/local_library/work_meta_detector.dart';
import 'package:novelty/screens/local_author_works_page.dart';
import 'package:novelty/screens/local_bookmarks_page.dart';
import 'package:novelty/screens/local_import.dart';
import 'package:novelty/screens/local_meta_rules_page.dart';
import 'package:novelty/screens/local_work_reader_page.dart';
import 'package:novelty/widgets/indexed_list.dart';

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
///
/// 検索は作品名と作者名（名前の変更を反映したもの）に当てる。
/// タイトル順は「# → A〜Z → あ〜わ → 漢」の順に並べる。
List<LocalWork> filterAndSortWorks(
  List<LocalWork> works,
  Map<String, ReadingPosition> positions, {
  required String query,
  required LocalSort sort,
  AuthorProfiles profiles = AuthorProfiles.empty,
}) {
  final q = query.trim().toLowerCase();
  bool matches(LocalWork w) {
    if (w.title.toLowerCase().contains(q)) return true;
    final author = profiles.effectiveName(w.author);
    return author?.toLowerCase().contains(q) ?? false;
  }

  final result = q.isEmpty ? [...works] : works.where(matches).toList();

  switch (sort) {
    case LocalSort.title:
      result.sort((a, b) => KanaIndex.compare(a.title, b.title));
    case LocalSort.added:
      result.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    case LocalSort.recent:
      // 未読の作品は後ろ（タイトル順）に回す
      result.sort((a, b) {
        final pa = positions[a.id]?.updatedAt;
        final pb = positions[b.id]?.updatedAt;
        if (pa == null && pb == null) {
          return KanaIndex.compare(a.title, b.title);
        }
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
  const AuthorGroup({
    required this.key,
    required this.name,
    required this.works,
    this.reading,
  });

  /// グループ分けのキー（作者不明は空文字）。
  final String key;

  /// 表示名。
  final String name;

  /// 読み仮名（未設定なら null）。
  final String? reading;

  /// この作者の作品。
  final List<LocalWork> works;

  /// 作者不明のグループか。
  bool get isUnknown => key.isEmpty;

  /// 判定された元の作者名（名前の変更前。重複なし）。
  Set<String> get originalAuthors => {
    for (final w in works)
      if (w.author != null) w.author!,
  };

  /// 右端のインデックスの見出し。
  String get indexLabel =>
      isUnknown ? KanaIndex.unknownLabel : KanaIndex.labelOf(reading ?? name);
}

/// 作者不明の作品をまとめるグループの表示名。
const unknownAuthorLabel = '作者不明';

/// 作品を作者ごとにまとめる。
///
/// 名前の変更（[profiles]）を反映し、表記揺れ（全角/半角・空白）は
/// 同じ作者として扱う。読み仮名があればそれで並べ、作者不明は最後に置く。
/// [query] は作者名・読み仮名で絞り込む。
List<AuthorGroup> groupByAuthor(
  List<LocalWork> works, {
  String query = '',
  AuthorProfiles profiles = AuthorProfiles.empty,
}) {
  final byKey = <String, List<LocalWork>>{};
  final names = <String, String>{};
  for (final work in works) {
    final author = profiles.effectiveName(work.author);
    final key = author == null ? '' : WorkMetaDetector.authorKey(author);
    byKey.putIfAbsent(key, () => []).add(work);
    names.putIfAbsent(key, () => author ?? unknownAuthorLabel);
  }

  final q = query.trim().toLowerCase();
  final groups = <AuthorGroup>[];
  for (final entry in byKey.entries) {
    final name = names[entry.key]!;
    final reading = entry.key.isEmpty ? null : profiles.readingOf(name);
    final hit =
        q.isEmpty ||
        name.toLowerCase().contains(q) ||
        (reading?.toLowerCase().contains(q) ?? false);
    if (!hit) continue;
    groups.add(
      AuthorGroup(
        key: entry.key,
        name: name,
        reading: reading,
        works: entry.value
          ..sort((a, b) => KanaIndex.compare(a.title, b.title)),
      ),
    );
  }
  return groups..sort((a, b) {
    if (a.isUnknown != b.isUnknown) return a.isUnknown ? 1 : -1;
    return KanaIndex.compare(a.reading ?? a.name, b.reading ?? b.name);
  });
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
    final profiles =
        ref.watch(authorProfilesProvider).value ?? AuthorProfiles.empty;
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
              profiles: profiles,
            ),
      [allWorks, positions, query.value, sort.value, profiles],
    );
    final groups = useMemoized(
      () => allWorks == null
          ? const <AuthorGroup>[]
          : groupByAuthor(allWorks, query: query.value, profiles: profiles),
      [allWorks, query.value, profiles],
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
          PopupMenuButton<String>(
            tooltip: 'その他',
            onSelected: (value) {
              switch (value) {
                case 'rules':
                  unawaited(
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LocalMetaRulesPage(),
                      ),
                    ),
                  );
                case 'redetect':
                  unawaited(runRedetectAll(context, ref));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rules', child: Text('作者の読み取りルール')),
              PopupMenuItem(value: 'redetect', child: Text('全作品の作者を再判定')),
            ],
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
                        : IndexedList(
                            itemCount: works.length,
                            // 見出しが意味を持つのはタイトル順のときだけ
                            showIndex: sort.value == LocalSort.title,
                            labelOf: (index) =>
                                KanaIndex.labelOf(works[index].title),
                            itemBuilder: (context, index) {
                              final work = works[index];
                              return LocalWorkTile(
                                work: work,
                                position: positions[work.id],
                                onTap: () =>
                                    unawaited(openLocalWork(context, work)),
                                onLongPress: () => unawaited(
                                  showLocalWorkActions(context, ref, work),
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
class _AuthorList extends ConsumerWidget {
  const _AuthorList({required this.groups, required this.positions});

  final List<AuthorGroup> groups;
  final Map<String, ReadingPosition> positions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IndexedList(
      itemCount: groups.length,
      labelOf: (index) => groups[index].indexLabel,
      itemBuilder: (context, index) {
        final group = groups[index];
        final readCount = group.works
            .where((w) => positions.containsKey(w.id))
            .length;
        final reading = group.reading;
        final counts = readCount == 0
            ? '${group.works.length} 作品'
            : '${group.works.length} 作品・読みかけ $readCount';
        return ListTile(
          leading: Icon(
            group.isUnknown ? Icons.help_outline : Icons.person_outline,
          ),
          title: Text(group.name),
          subtitle: Text(reading == null ? counts : '$reading・$counts'),
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
          onLongPress: group.isUnknown
              ? null
              : () => unawaited(showEditAuthorDialog(context, ref, group)),
        );
      },
    );
  }
}

/// 作者の名前・読み仮名の編集ダイアログ。
///
/// 保存した名前を返す（キャンセルなら null）。
/// 名前の変更はその作者の全作品に反映され、再判定しても失われない。
Future<String?> showEditAuthorDialog(
  BuildContext context,
  WidgetRef ref,
  AuthorGroup group,
) async {
  final result = await showDialog<(String, String)>(
    context: context,
    builder: (_) => _EditAuthorDialog(group: group),
  );
  if (result == null) return null;
  final (name, reading) = result;
  await ref
      .read(authorProfilesProvider.notifier)
      .edit(
        originalAuthors: group.originalAuthors,
        newName: name,
        reading: reading,
      );
  return name.trim();
}

class _EditAuthorDialog extends HookWidget {
  const _EditAuthorDialog({required this.group});

  final AuthorGroup group;

  @override
  Widget build(BuildContext context) {
    final name = useTextEditingController(text: group.name);
    final reading = useTextEditingController(text: group.reading ?? '');
    useListenable(name);
    final nameEmpty = name.text.trim().isEmpty;

    return AlertDialog(
      title: const Text('作者を編集'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: '作者名',
                errorText: nameEmpty ? '作者名を入力してください' : null,
                helperText: '他の作者と同じ名前にすると1人にまとまります',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reading,
              decoration: const InputDecoration(
                labelText: '読み仮名',
                helperText: '入れると右端の「あ〜わ」の正しい行に並びます',
                helperMaxLines: 2,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: nameEmpty
              ? null
              : () => Navigator.pop(context, (name.text, reading.text)),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 作品の長押しメニュー（作者・作品名の修正、自動判定に戻す、削除）。
Future<void> showLocalWorkActions(
  BuildContext context,
  WidgetRef ref,
  LocalWork work,
) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              work.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(work.fileName),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('作者・作品名を修正'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await showEditWorkMetaDialog(context, ref, work);
            },
          ),
          if (work.manualMeta)
            ListTile(
              leading: const Icon(Icons.auto_fix_high),
              title: const Text('自動判定に戻す'),
              subtitle: const Text('手で直した内容を取り消し、ルールで読み取り直します'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await ref.read(localWorksProvider.notifier).resetMeta(work.id);
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('削除'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await confirmDeleteLocalWork(context, ref, work);
            },
          ),
        ],
      ),
    ),
  );
}

/// 作者・作品名の修正ダイアログ。保存すると再判定の対象外になる。
Future<void> showEditWorkMetaDialog(
  BuildContext context,
  WidgetRef ref,
  LocalWork work,
) async {
  final result = await showDialog<(String, String)>(
    context: context,
    builder: (_) => _EditWorkMetaDialog(work: work),
  );
  if (result == null) return;
  final (title, author) = result;
  await ref
      .read(localWorksProvider.notifier)
      .editMeta(work.id, title: title, author: author);
}

class _EditWorkMetaDialog extends HookWidget {
  const _EditWorkMetaDialog({required this.work});

  final LocalWork work;

  @override
  Widget build(BuildContext context) {
    final title = useTextEditingController(text: work.title);
    final author = useTextEditingController(text: work.author ?? '');
    useListenable(title);
    final titleEmpty = title.text.trim().isEmpty;

    return AlertDialog(
      title: const Text('作者・作品名を修正'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: title,
            decoration: InputDecoration(
              labelText: '作品名',
              errorText: titleEmpty ? '作品名を入力してください' : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: author,
            decoration: const InputDecoration(
              labelText: '作者',
              helperText: '空欄にすると「作者不明」になります',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: titleEmpty
              ? null
              : () => Navigator.pop(context, (title.text, author.text)),
          child: const Text('保存'),
        ),
      ],
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
class LocalWorkTile extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = position;
    final profiles =
        ref.watch(authorProfilesProvider).value ?? AuthorProfiles.empty;
    final author = profiles.effectiveName(work.author);
    final details = [
      if (showAuthor && author != null) author,
      if (work.manualMeta) '手修正',
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
  final date = '${t.year}/${two(t.month)}/${two(t.day)}';
  return '$date ${two(t.hour)}:${two(t.minute)}';
}
