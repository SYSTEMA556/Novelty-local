import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:novelty/local_library/read_aloud_playlist.dart';
import 'package:novelty/screens/local_work_reader_page.dart';

/// 連続再生リストを見る・並べ替える・再生するシートを出す。
///
/// 作品を長押し →「連続再生リストに追加」で入れた作品を、
/// 読み上げで上から順に続けて流す（運転中などに）。
Future<void> showReadAloudPlaylistSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _PlaylistSheet(parentContext: context),
  );
}

class _PlaylistSheet extends ConsumerWidget {
  const _PlaylistSheet({required this.parentContext});

  // シートを閉じたあとに作品を開くための、シートの外側の context
  final BuildContext parentContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(readAloudPlaylistProvider).value ?? const [];
    final works = {
      for (final w in ref.watch(localWorksProvider).value ?? <LocalWork>[])
        w.id: w,
    };
    // 本棚から消した作品はリストに出さない
    final items = [for (final id in ids) ?works[id]];
    final notifier = ref.read(readAloudPlaylistProvider.notifier);

    void playFrom(LocalWork work) {
      Navigator.pop(context);
      if (!parentContext.mounted) return;
      unawaited(openLocalWork(parentContext, work, autoPlay: true));
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        children: [
          ListTile(
            title: const Text('連続再生リスト'),
            subtitle: Text(
              items.isEmpty
                  ? '作品を長押し →「連続再生リストに追加」で入れられます'
                  : '${items.length}作品・上から順に読み上げます',
            ),
            trailing: items.isEmpty
                ? null
                : TextButton(
                    onPressed: () => unawaited(notifier.clear()),
                    child: const Text('空にする'),
                  ),
          ),
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('1作目から再生'),
                  onPressed: () => playFrom(items.first),
                ),
              ),
            ),
          const Divider(),
          Expanded(
            child: ReorderableListView.builder(
              scrollController: scrollController,
              itemCount: items.length,
              // newIndex は、動かした作品を抜いたあとの並びでの位置
              onReorderItem: (oldIndex, newIndex) {
                // 本棚から消えた作品はここで落とす
                final order = [for (final w in items) w.id];
                final moved = order.removeAt(oldIndex);
                order.insert(newIndex.clamp(0, order.length), moved);
                unawaited(notifier.reorder(order));
              },
              itemBuilder: (context, index) {
                final work = items[index];
                return ListTile(
                  key: ValueKey(work.id),
                  leading: Text('${index + 1}'),
                  title: Text(
                    work.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: work.author == null ? null : Text(work.author!),
                  onTap: () => playFrom(work),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'リストから外す',
                        onPressed: () => unawaited(notifier.remove(work.id)),
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
              },
            ),
          ),
        ],
      ),
    );
  }
}
