import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/local_library/author_profiles.dart';
import 'package:novelty/local_library/kana_index.dart';
import 'package:novelty/local_library/kanji_reader.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:novelty/local_library/read_aloud_playlist.dart';
import 'package:novelty/local_library/work_meta_detector.dart';
import 'package:novelty/screens/local_author_works_page.dart';
import 'package:novelty/screens/local_bookmarks_page.dart';
import 'package:novelty/screens/local_import.dart';
import 'package:novelty/screens/local_meta_rules_page.dart';
import 'package:novelty/screens/local_work_reader_page.dart';
import 'package:novelty/screens/read_aloud_playlist_sheet.dart';
import 'package:novelty/utils/settings_provider.dart';
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

/// 作品名の並べ替え用の読み。
///
/// 手で入れた読み仮名を優先し、なければ辞書（[reader]）で漢字を読む。
/// 辞書がなければ作品名そのもの（漢字は「漢」の行に入る）。
String workReading(LocalWork work, KanjiReader? reader) =>
    work.titleReading ?? reader?.read(work.title) ?? work.title;

/// 検索語と並び順を適用した作品一覧を返す。
///
/// 検索は作品名・読み・作者名（名前の変更を反映したもの）に当てる。
/// タイトル順は読みで「# → A〜Z → あ〜わ → 漢」の順に並べる。
List<LocalWork> filterAndSortWorks(
  List<LocalWork> works,
  Map<String, ReadingPosition> positions, {
  required String query,
  required LocalSort sort,
  AuthorProfiles profiles = AuthorProfiles.empty,
  KanjiReader? reader,
}) {
  final readings = <String, String>{};
  String readingOf(LocalWork w) =>
      readings[w.id] ??= workReading(w, reader);
  int byTitle(LocalWork a, LocalWork b) =>
      KanaIndex.compare(readingOf(a), readingOf(b));

  final q = query.trim().toLowerCase();
  bool matches(LocalWork w) {
    if (w.title.toLowerCase().contains(q)) return true;
    if (KanaIndex.sortKey(readingOf(w)).contains(KanaIndex.sortKey(q))) {
      return true;
    }
    final author = profiles.effectiveName(w.author);
    return author?.toLowerCase().contains(q) ?? false;
  }

  final result = q.isEmpty ? [...works] : works.where(matches).toList();

  switch (sort) {
    case LocalSort.title:
      result.sort(byTitle);
    case LocalSort.added:
      result.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    case LocalSort.recent:
      // 未読の作品は後ろ（タイトル順）に回す
      result.sort((a, b) {
        final pa = positions[a.id]?.updatedAt;
        final pb = positions[b.id]?.updatedAt;
        if (pa == null && pb == null) return byTitle(a, b);
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
    this.guessedReading,
  });

  /// グループ分けのキー（作者不明は空文字）。
  final String key;

  /// 表示名。
  final String name;

  /// 読み仮名（未設定なら null）。
  final String? reading;

  /// 辞書から推測した読み（読み仮名が未設定のときだけ。推測できなければ null）。
  final String? guessedReading;

  /// 並べ替えに使う読み。
  String get sortText => reading ?? guessedReading ?? name;

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
      isUnknown ? KanaIndex.unknownLabel : KanaIndex.labelOf(sortText);
}

/// 作者不明の作品をまとめるグループの表示名。
const unknownAuthorLabel = '作者不明';

/// 作品を作者ごとにまとめる。
///
/// 名前の変更（[profiles]）を反映し、表記揺れ（全角/半角・空白）は
/// 同じ作者として扱う。読み仮名があればそれで、なければ辞書（[reader]）で
/// 推測した読みで並べ、作者不明は最後に置く。
/// [query] は作者名・読み仮名で絞り込む。
List<AuthorGroup> groupByAuthor(
  List<LocalWork> works, {
  String query = '',
  AuthorProfiles profiles = AuthorProfiles.empty,
  KanjiReader? reader,
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
    final guessed = entry.key.isEmpty || reading != null
        ? null
        : reader?.read(name);
    final hit =
        q.isEmpty ||
        name.toLowerCase().contains(q) ||
        (reading?.toLowerCase().contains(q) ?? false) ||
        (guessed?.contains(KanaIndex.sortKey(q)) ?? false);
    if (!hit) continue;
    groups.add(
      AuthorGroup(
        key: entry.key,
        name: name,
        reading: reading,
        guessedReading: guessed,
        works: entry.value
          ..sort(
            (a, b) => KanaIndex.compare(
              workReading(a, reader),
              workReading(b, reader),
            ),
          ),
      ),
    );
  }
  return groups..sort((a, b) {
    if (a.isUnknown != b.isUnknown) return a.isUnknown ? 1 : -1;
    return KanaIndex.compare(a.sortText, b.sortText);
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
    // 漢字の読みの辞書（読み込み中・失敗時は null で、漢字は「漢」にまとめる）
    final reader = ref.watch(kanjiReaderProvider).value;

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
              reader: reader,
            ),
      [allWorks, positions, query.value, sort.value, profiles, reader],
    );
    final groups = useMemoized(
      () => allWorks == null
          ? const <AuthorGroup>[]
          : groupByAuthor(
              allWorks,
              query: query.value,
              profiles: profiles,
              reader: reader,
            ),
      [allWorks, query.value, profiles, reader],
    );
    final isAuthorMode = viewMode.value == LocalViewMode.authors;
    final appSettings = ref.watch(settingsProvider).value;
    final grid = appSettings != null && appSettings.localGridEnabled
        ? GridOptions(
            columns: appSettings.localGridColumns.clamp(2, 6),
            showNames: appSettings.localGridShowNames,
            square: appSettings.localGridSquare,
          )
        : null;

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
                case 'display':
                  unawaited(showLocalDisplayDialog(context, ref));
                case 'playlist':
                  unawaited(showReadAloudPlaylistSheet(context));
                case 'rescan':
                  unawaited(showRescanSheet(context, ref));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'playlist', child: Text('連続再生リスト')),
              PopupMenuItem(value: 'rescan', child: Text('取り込んだフォルダを再スキャン')),
              PopupMenuItem(value: 'display', child: Text('表示の設定（リスト／グリッド）')),
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
                        ? _AuthorList(
                            groups: groups,
                            positions: positions,
                            grid: grid,
                          )
                        : grid != null
                        ? GridIndexedList<LocalWork>(
                            items: works,
                            options: grid,
                            showIndex: sort.value == LocalSort.title,
                            labelOf: (work) =>
                                KanaIndex.labelOf(workReading(work, reader)),
                            tileBuilder: (context, work) => _WorkGridTile(
                              work: work,
                              position: positions[work.id],
                              showName: grid.showNames,
                              onTap: () =>
                                  unawaited(openLocalWork(context, work)),
                              onLongPress: () => unawaited(
                                showLocalWorkActions(context, ref, work),
                              ),
                            ),
                          )
                        : IndexedList(
                            itemCount: works.length,
                            // 見出しが意味を持つのはタイトル順のときだけ
                            showIndex: sort.value == LocalSort.title,
                            labelOf: (index) => KanaIndex.labelOf(
                              workReading(works[index], reader),
                            ),
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
  const _AuthorList({
    required this.groups,
    required this.positions,
    this.grid,
  });

  final List<AuthorGroup> groups;
  final Map<String, ReadingPosition> positions;
  final GridOptions? grid;

  void _open(BuildContext context, AuthorGroup group) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LocalAuthorWorksPage(
            authorKey: group.key,
            authorName: group.name,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gridOptions = grid;
    if (gridOptions != null) {
      return GridIndexedList<AuthorGroup>(
        items: groups,
        options: gridOptions,
        labelOf: (group) => group.indexLabel,
        tileBuilder: (context, group) => _GridTile(
          icon: group.isUnknown ? Icons.help_outline : Icons.person_outline,
          title: gridOptions.showNames ? group.name : null,
          subtitle: gridOptions.showNames
              ? '${group.works.length} 作品'
              : null,
          onTap: () => _open(context, group),
          onLongPress: group.isUnknown
              ? null
              : () => unawaited(showEditAuthorDialog(context, ref, group)),
        ),
      );
    }
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

/// グリッド表示の設定。
class GridOptions {
  /// コンストラクタ。
  const GridOptions({
    required this.columns,
    required this.showNames,
    required this.square,
  });

  /// 列数。
  final int columns;

  /// 名前を表示するか。
  final bool showNames;

  /// 各マスを正方形にするか。
  final bool square;
}

/// 右端のインデックス付きのグリッド。
///
/// インデックスで飛べるよう、1行ずつを [IndexedList] の項目として並べる
/// （見出しが行の途中から始まる場合は、その行へ飛ぶ）。
class GridIndexedList<T> extends StatelessWidget {
  /// コンストラクタ。
  const GridIndexedList({
    required this.items,
    required this.options,
    required this.labelOf,
    required this.tileBuilder,
    this.showIndex = true,
    super.key,
  });

  /// 並べる項目。
  final List<T> items;

  /// グリッドの設定。
  final GridOptions options;

  /// 項目の見出し。
  final String Function(T item) labelOf;

  /// マスを作る。
  final Widget Function(BuildContext context, T item) tileBuilder;

  /// インデックスを表示するか。
  final bool showIndex;

  @override
  Widget build(BuildContext context) {
    final columns = options.columns;
    final rowCount = (items.length + columns - 1) ~/ columns;
    return IndexedList(
      itemCount: rowCount,
      showIndex: showIndex,
      labelOf: (row) => labelOf(items[row * columns]),
      itemBuilder: (context, row) {
        final start = row * columns;
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < columns; c++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: start + c < items.length
                          ? (options.square
                                ? AspectRatio(
                                    aspectRatio: 1,
                                    child: tileBuilder(
                                      context,
                                      items[start + c],
                                    ),
                                  )
                                : tileBuilder(context, items[start + c]))
                          : const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// グリッドの1マス（アイコン＋名前）。
class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.icon,
    required this.onTap,
    this.title,
    this.subtitle,
    this.iconColor,
    this.progress,
    this.onLongPress,
  });

  final IconData icon;
  final Color? iconColor;
  final String? title;
  final String? subtitle;
  final double? progress;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleText = title;
    final subtitleText = subtitle;
    final progressValue = progress;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: iconColor),
              if (titleText != null) ...[
                const SizedBox(height: 6),
                Text(
                  titleText,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (subtitleText != null)
                Text(
                  subtitleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (progressValue != null) ...[
                const SizedBox(height: 4),
                LinearProgressIndicator(value: progressValue),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 作品のグリッドのマス。
class _WorkGridTile extends ConsumerWidget {
  const _WorkGridTile({
    required this.work,
    required this.position,
    required this.showName,
    required this.onTap,
    required this.onLongPress,
  });

  final LocalWork work;
  final ReadingPosition? position;
  final bool showName;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles =
        ref.watch(authorProfilesProvider).value ?? AuthorProfiles.empty;
    final pos = position;
    return _GridTile(
      icon: pos == null ? Icons.description_outlined : Icons.bookmark,
      iconColor: pos == null ? null : Theme.of(context).colorScheme.primary,
      title: showName ? work.title : null,
      subtitle: showName ? profiles.effectiveName(work.author) : null,
      progress: pos?.progress,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// ローカル作品一覧の表示設定ダイアログ（リスト／グリッド、列数など）。
Future<void> showLocalDisplayDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _LocalDisplayDialog(),
  );
}

class _LocalDisplayDialog extends HookConsumerWidget {
  const _LocalDisplayDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.read(settingsProvider).value;
    final grid = useState(current?.localGridEnabled ?? false);
    final columns = useState((current?.localGridColumns ?? 3).clamp(2, 6));
    final showNames = useState(current?.localGridShowNames ?? true);
    final square = useState(current?.localGridSquare ?? false);

    return AlertDialog(
      title: const Text('表示の設定'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('リスト'),
                  icon: Icon(Icons.view_list),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('グリッド'),
                  icon: Icon(Icons.grid_view),
                ),
              ],
              selected: {grid.value},
              showSelectedIcon: false,
              onSelectionChanged: (v) => grid.value = v.first,
            ),
            if (grid.value) ...[
              const SizedBox(height: 12),
              Text('列数: ${columns.value}'),
              Slider(
                value: columns.value.toDouble(),
                min: 2,
                max: 6,
                divisions: 4,
                label: '${columns.value}',
                onChanged: (v) => columns.value = v.round(),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('名前を表示'),
                value: showNames.value,
                onChanged: (v) => showNames.value = v ?? true,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('正方形'),
                value: square.value,
                onChanged: (v) => square.value = v ?? false,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(context);
            try {
              await ref
                  .read(settingsProvider.notifier)
                  .setLocalGrid(
                    enabled: grid.value,
                    columns: columns.value,
                    showNames: showNames.value,
                    square: square.value,
                  );
            } on Exception catch (e) {
              debugPrint('Failed to save grid settings: $e');
            }
          },
          child: const Text('確認'),
        ),
      ],
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
              decoration: InputDecoration(
                labelText: '読み仮名',
                hintText: group.guessedReading,
                helperText: group.guessedReading == null
                    ? '入れると右端の「あ〜わ」の正しい行に並びます'
                    : '空欄なら薄字の推測した読みで並びます。'
                          '違っていたら入れ直してください',
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
          _PlaylistToggleTile(work: work, sheetContext: sheetContext),
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

/// 作品を連続再生リストに入れる・外す項目。
class _PlaylistToggleTile extends ConsumerWidget {
  const _PlaylistToggleTile({required this.work, required this.sheetContext});

  final LocalWork work;
  final BuildContext sheetContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(readAloudPlaylistProvider).value ?? const [];
    final inList = ids.contains(work.id);
    final notifier = ref.read(readAloudPlaylistProvider.notifier);
    return ListTile(
      leading: Icon(inList ? Icons.playlist_remove : Icons.playlist_add),
      title: Text(inList ? '連続再生リストから外す' : '連続再生リストに追加'),
      subtitle: inList ? null : Text('いま${ids.length}作品・読み上げで順に流します'),
      onTap: () {
        Navigator.pop(sheetContext);
        unawaited(inList ? notifier.remove(work.id) : notifier.add(work.id));
      },
    );
  }
}

/// 作者・作品名の修正ダイアログ。保存すると再判定の対象外になる。
Future<void> showEditWorkMetaDialog(
  BuildContext context,
  WidgetRef ref,
  LocalWork work,
) async {
  final guessed = ref.read(kanjiReaderProvider).value?.read(work.title);
  final result = await showDialog<(String, String, String)>(
    context: context,
    builder: (_) => _EditWorkMetaDialog(work: work, guessedReading: guessed),
  );
  if (result == null) return;
  final (title, author, reading) = result;
  await ref
      .read(localWorksProvider.notifier)
      .editMeta(
        work.id,
        title: title,
        author: author,
        titleReading: reading,
      );
}

class _EditWorkMetaDialog extends HookWidget {
  const _EditWorkMetaDialog({required this.work, this.guessedReading});

  final LocalWork work;

  // 辞書から推測した作品名の読み（入力欄の薄字に出す）
  final String? guessedReading;

  @override
  Widget build(BuildContext context) {
    final title = useTextEditingController(text: work.title);
    final author = useTextEditingController(text: work.author ?? '');
    final reading = useTextEditingController(text: work.titleReading ?? '');
    useListenable(title);
    final titleEmpty = title.text.trim().isEmpty;

    return AlertDialog(
      title: const Text('作者・作品名を修正'),
      content: SingleChildScrollView(
        child: Column(
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
              controller: reading,
              decoration: InputDecoration(
                labelText: '作品名の読み仮名',
                hintText: guessedReading,
                helperText: '空欄なら辞書で推測した読みで並びます',
                helperMaxLines: 2,
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: titleEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  (title.text, author.text, reading.text),
                ),
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
    this.trailing,
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

  /// 右端に置くウィジェット（削除ボタンなど）。
  final Widget? trailing;

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
      trailing: trailing,
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
