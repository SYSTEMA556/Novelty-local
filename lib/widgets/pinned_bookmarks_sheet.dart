/// 長押しで挟むしおり（フォークで追加）。
///
/// 1作品に3つまで、読書画面の本文を長押しして「今見ている所」に挟む。
/// 一覧では、その場所の冒頭30文字ほどと、全体の何%かで選ぶ。
/// 場所は本文の文字位置で持つので、縦書き・横書きを切り替えても同じ所へ戻れる。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:novelty/read_aloud/speech_document.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/web_pins.dart';

/// しおりの目印にする冒頭の文字数。
const pinnedSnippetLength = 30;

/// [document] の [segmentIndex] 番目の文から、しおりを作る。
PinnedBookmark pinnedBookmarkAt(
  SpeechDocument document,
  int segmentIndex, {
  DateTime? now,
}) {
  final segments = document.segments;
  final index = segmentIndex.clamp(0, segments.length - 1);
  final start = segments[index].start;
  // 冒頭の文字：その文から続けて、30文字ほどになるまでつなぐ
  final buffer = StringBuffer();
  for (var i = index; i < segments.length; i++) {
    buffer.write(segments[i].text.replaceAll(RegExp(r'\s+'), ''));
    if (buffer.length >= pinnedSnippetLength) break;
  }
  final text = buffer.toString();
  final snippet = text.length > pinnedSnippetLength
      ? '${text.substring(0, pinnedSnippetLength)}…'
      : text;
  return PinnedBookmark(
    offset: start,
    fraction: document.length == 0 ? 0 : start / document.length,
    snippet: snippet,
    createdAt: now ?? DateTime.now(),
  );
}

/// 今の場所にしおりを挟む。3つ埋まっていたら、どれと入れ替えるかを選ぶ。
Future<void> addPinnedBookmark(
  BuildContext context,
  WidgetRef ref, {
  required String workId,
  required SpeechDocument document,
  required int segmentIndex,
}) async {
  if (document.segments.isEmpty) return;
  unawaited(HapticFeedback.mediumImpact());
  final pin = pinnedBookmarkAt(document, segmentIndex);
  final notifier = ref.read(readingPositionsProvider.notifier);
  final pins = ref.read(readingPositionsProvider).value?[workId]?.pins ?? [];

  int? replaceIndex;
  if (pins.length >= ReadingPosition.maxPins) {
    replaceIndex = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('しおりは3つまでです。どれと入れ替えますか？'),
        children: [
          for (var i = 0; i < pins.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, i),
              child: _PinLabel(pin: pins[i]),
            ),
        ],
      ),
    );
    if (replaceIndex == null) return;
  }
  notifier.addPin(workId, pin, replaceIndex: replaceIndex);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('しおりを挟みました（${_percent(pin.fraction)}）'),
        action: SnackBarAction(
          label: '外す',
          onPressed: () => notifier.removePin(workId, pin),
        ),
      ),
    );
}

/// しおりの一覧で選んだこと。
enum PinAction {
  /// その場所を開く。
  open,

  /// その場所から読み上げる。
  readAloud,
}

/// しおりの一覧を出し、選んだしおりとすることを返す（閉じたら null）。
Future<(PinnedBookmark, PinAction)?> showPinnedBookmarksSheet(
  BuildContext context, {
  required String workId,
}) {
  return showModalBottomSheet<(PinnedBookmark, PinAction)>(
    context: context,
    useSafeArea: true,
    builder: (_) => _PinnedBookmarksSheet(workId: workId),
  );
}

class _PinnedBookmarksSheet extends ConsumerWidget {
  const _PinnedBookmarksSheet({required this.workId});

  final String workId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pins =
        ref.watch(readingPositionsProvider).value?[workId]?.pins ?? const [];
    final notifier = ref.read(readingPositionsProvider.notifier);
    return ListView(
      shrinkWrap: true,
      children: [
        const ListTile(
          title: Text('しおり'),
          subtitle: Text('本文を長押しすると、今見ている所に挟めます（3つまで）'),
        ),
        if (pins.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('まだしおりはありません'),
          ),
        for (final pin in pins)
          ListTile(
            leading: const Icon(Icons.bookmark),
            title: _PinLabel(pin: pin),
            onTap: () => Navigator.pop(context, (pin, PinAction.open)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.record_voice_over_outlined),
                  tooltip: 'ここから読み上げ',
                  onPressed: () =>
                      Navigator.pop(context, (pin, PinAction.readAloud)),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '外す',
                  onPressed: () => notifier.removePin(workId, pin),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// しおりの見出し（冒頭の文字と、全体の何%か）。
class _PinLabel extends StatelessWidget {
  const _PinLabel({required this.pin});

  final PinnedBookmark pin;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(pin.snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
        Text(_percent(pin.fraction), style: small),
      ],
    );
  }
}

String _percent(double fraction) => '${(fraction * 100).toStringAsFixed(1)}%';

// ---- Web 小説（なろう・カクヨム）のしおり ----

/// Web 小説の第 [episode] 話の今の場所にしおりを挟む。
/// 作品のしおりが3つ埋まっていたら、どれと入れ替えるかを選ぶ。
Future<void> addWebPin(
  BuildContext context,
  WidgetRef ref, {
  required NovelSource source,
  required String workId,
  required String title,
  required int episode,
  required SpeechDocument document,
  required int segmentIndex,
}) async {
  if (document.segments.isEmpty) return;
  unawaited(HapticFeedback.mediumImpact());
  final base = pinnedBookmarkAt(document, segmentIndex);
  final pin = WebPin(
    source: source,
    workId: workId,
    title: title,
    episode: episode,
    offset: base.offset,
    fraction: base.fraction,
    snippet: base.snippet,
    createdAt: base.createdAt,
  );
  final notifier = ref.read(webPinsProvider.notifier);
  await ref.read(webPinsProvider.future);
  final mine = notifier.pinsOf(source, workId);
  WebPin? replace;
  if (mine.length >= WebPin.maxPerWork) {
    if (!context.mounted) return;
    replace = await showDialog<WebPin>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('しおりは3つまでです。どれと入れ替えますか？'),
        children: [
          for (final p in mine)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, p),
              child: _WebPinLabel(pin: p),
            ),
        ],
      ),
    );
    if (replace == null) return;
  }
  await notifier.add(pin, replace: replace);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text('しおりを挟みました（第$episode話・${_percent(pin.fraction)}）'),
        action: SnackBarAction(
          label: '外す',
          onPressed: () => unawaited(notifier.remove(pin)),
        ),
      ),
    );
}

/// Web 小説の作品のしおりの一覧を出し、選んだしおりとすることを返す。
Future<(WebPin, PinAction)?> showWebPinsSheet(
  BuildContext context, {
  required NovelSource source,
  required String workId,
}) {
  return showModalBottomSheet<(WebPin, PinAction)>(
    context: context,
    useSafeArea: true,
    builder: (_) => _WebPinsSheet(source: source, workId: workId),
  );
}

class _WebPinsSheet extends ConsumerWidget {
  const _WebPinsSheet({required this.source, required this.workId});

  final NovelSource source;
  final String workId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(webPinsProvider);
    final notifier = ref.read(webPinsProvider.notifier);
    final pins = notifier.pinsOf(source, workId);
    return ListView(
      shrinkWrap: true,
      children: [
        const ListTile(
          title: Text('しおり'),
          subtitle: Text('本文を長押しすると、今見ている所に挟めます（3つまで）'),
        ),
        if (pins.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('まだしおりはありません'),
          ),
        for (final pin in pins)
          ListTile(
            leading: const Icon(Icons.bookmark),
            title: _WebPinLabel(pin: pin),
            onTap: () => Navigator.pop(context, (pin, PinAction.open)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.record_voice_over_outlined),
                  tooltip: 'ここから読み上げ',
                  onPressed: () =>
                      Navigator.pop(context, (pin, PinAction.readAloud)),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '外す',
                  onPressed: () => unawaited(notifier.remove(pin)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _WebPinLabel extends StatelessWidget {
  const _WebPinLabel({required this.pin});

  final WebPin pin;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(pin.snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
        Text('第${pin.episode}話・${_percent(pin.fraction)}', style: small),
      ],
    );
  }
}

/// しおりの割合の表し方（例：42.3%）。
String pinPercent(double fraction) => _percent(fraction);
