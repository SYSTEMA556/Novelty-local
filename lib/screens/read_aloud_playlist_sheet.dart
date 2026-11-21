/// 連続再生リストの画面（フォークで追加）。
///
/// ローカル本棚の作品と Web 小説を並べ、上から順に読み上げる。
/// 再生は画面を開かずに [PlaylistPlayer] が行うので、シートを閉じても、
/// 画面を消しても続く。操作は通知・車のボタンからもできる。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:novelty/local_library/read_aloud_playlist.dart';
import 'package:novelty/read_aloud/playlist_player.dart';
import 'package:novelty/repositories/novel_repository.dart';

/// 連続再生リストを見る・並べ替える・再生するシートを出す。
Future<void> showReadAloudPlaylistSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => const _PlaylistSheet(),
  );
}

class _PlaylistSheet extends ConsumerWidget {
  const _PlaylistSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keys = ref.watch(readAloudPlaylistProvider).value ?? const [];
    final works = {
      for (final w in ref.watch(localWorksProvider).value ?? <LocalWork>[])
        w.id: w,
    };
    // 本棚から消したローカルの作品・読めない鍵はリストに出さない
    final entries = [
      for (final key in keys)
        if (PlaylistEntry.parse(key) case final entry?)
          if (entry is! LocalPlaylistEntry || works.containsKey(entry.workId))
            entry,
    ];
    final notifier = ref.read(readAloudPlaylistProvider.notifier);
    final player = ref.read(playlistPlayerProvider.notifier);
    final nowPlaying = ref.watch(playlistPlayerProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        children: [
          ListTile(
            title: const Text('連続再生リスト'),
            subtitle: Text(
              entries.isEmpty
                  ? [
                      '本棚の作品は長押し、Web 小説は作品ページの ⋮ から',
                      '「連続再生リストに追加」で入れられます',
                    ].join()
                  : '${entries.length}作品・上から順に読み上げます',
            ),
            trailing: entries.isEmpty
                ? null
                : TextButton(
                    onPressed: () => unawaited(notifier.clear()),
                    child: const Text('空にする'),
                  ),
          ),
          if (nowPlaying != null)
            _NowPlayingCard(nowPlaying: nowPlaying)
          else if (entries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('1作目から再生'),
                  onPressed: () => unawaited(player.playFrom(entries.first)),
                ),
              ),
            ),
          const Divider(),
          Expanded(
            child: ReorderableListView.builder(
              scrollController: scrollController,
              itemCount: entries.length,
              // newIndex は、動かした作品を抜いたあとの並びでの位置
              onReorderItem: (oldIndex, newIndex) {
                final order = [for (final e in entries) e.key];
                final moved = order.removeAt(oldIndex);
                order.insert(newIndex.clamp(0, order.length), moved);
                unawaited(notifier.reorder(order));
              },
              itemBuilder: (context, index) {
                final entry = entries[index];
                final playing = nowPlaying?.entry.key == entry.key;
                return _EntryTile(
                  key: ValueKey(entry.key),
                  entry: entry,
                  index: index,
                  localWork: entry is LocalPlaylistEntry
                      ? works[entry.workId]
                      : null,
                  playing: playing,
                  onTap: () => unawaited(player.playFrom(entry)),
                  onRemove: () => unawaited(notifier.remove(entry.key)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 今読んでいる作品と、その操作。
class _NowPlayingCard extends ConsumerWidget {
  const _NowPlayingCard({required this.nowPlaying});

  final PlaylistNowPlaying nowPlaying;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(playlistPlayerProvider.notifier);
    final controller = nowPlaying.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nowPlaying.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (nowPlaying.subtitle case final subtitle?)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              Row(
                children: [
                  Text(
                    '${controller.index + 1} / '
                    '${controller.document.segments.length}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.replay_30),
                    tooltip: '30秒戻る',
                    onPressed: () =>
                        unawaited(controller.seekBySeconds(-30)),
                  ),
                  IconButton.filled(
                    icon: Icon(
                      controller.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    tooltip: controller.isPlaying ? '一時停止' : '再開',
                    onPressed: () => unawaited(
                      controller.isPlaying
                          ? controller.pause()
                          : controller.resume(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    tooltip: '次の作品へ',
                    onPressed: () => unawaited(player.skipToNextEntry()),
                  ),
                  IconButton(
                    icon: const Icon(Icons.stop),
                    tooltip: '連続再生をやめる',
                    onPressed: player.stop,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// リストの1件。Web 小説の題名は作品情報のキャッシュから引く。
class _EntryTile extends ConsumerWidget {
  const _EntryTile({
    required this.entry,
    required this.index,
    required this.playing,
    required this.onTap,
    required this.onRemove,
    this.localWork,
    super.key,
  });

  final PlaylistEntry entry;
  final int index;
  final LocalWork? localWork;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (String title, String? subtitle) = switch (entry) {
      LocalPlaylistEntry() => (
        localWork?.title ?? '（本棚にない作品）',
        localWork?.author,
      ),
      WebPlaylistEntry(:final source, :final workId) => () {
        final info = ref
            .watch(novelInfoWithCacheProvider(source, workId))
            .value;
        return (
          info?.title ?? workId,
          [source.label, ?info?.writer].join('・'),
        );
      }(),
    };
    return ListTile(
      leading: playing
          ? const Icon(Icons.graphic_eq)
          : Text('${index + 1}'),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      selected: playing,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            entry is WebPlaylistEntry
                ? Icons.public
                : Icons.description_outlined,
            size: 18,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'リストから外す',
            onPressed: onRemove,
          ),
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.drag_handle),
            ),
          ),
        ],
      ),
    );
  }
}
