import 'dart:async';

import 'package:flutter/material.dart';
import 'package:novelty/read_aloud/read_aloud_controller.dart';
import 'package:novelty/read_aloud/speech_direction.dart';
import 'package:novelty/read_aloud/speech_document.dart';
import 'package:novelty/utils/settings_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 画面を消さない設定を切り替える（失敗しても読書は続けられるため無視する）。
Future<void> setReaderWakelock({required bool enabled}) async {
  try {
    await WakelockPlus.toggle(enable: enabled);
  } on Object catch (e) {
    debugPrint('Failed to toggle wakelock: $e');
  }
}

/// 閲覧設定の読み上げの項目（速さ・高さ・演技・声）を [controller] に反映する。
void applyReadAloudSettings(
  ReadAloudController controller,
  AppSettings? settings,
) {
  String? voice(String? name) =>
      name == null || name.isEmpty ? null : name;
  controller.setVoice(
    rate: settings?.ttsRate ?? 0.5,
    pitch: settings?.ttsPitch ?? 1,
    acting: (settings?.ttsActing ?? 60) / 100,
    narrationVoice: voice(settings?.ttsNarrationVoice),
    dialogueVoice: voice(settings?.ttsDialogueVoice),
  );
}

/// 読み上げ中に画面下に出す操作ボタン。
class ReadAloudBar extends StatelessWidget {
  /// コンストラクタ。
  const ReadAloudBar({required this.controller, super.key});

  /// 読み上げの操作対象。
  final ReadAloudController controller;

  @override
  Widget build(BuildContext context) {
    final total = controller.document.segments.length;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(28),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${controller.index + 1} / $total',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                // 今の文をどう演じているか（演技を切っているときは出さない）
                if (controller.acting > 0)
                  if (controller.currentDirection case final direction?)
                    Text(
                      direction.emotion == SpeechEmotion.neutral
                          ? direction.role.label
                          : '${direction.role.label}・'
                                '${direction.emotion.label}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
              ],
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.skip_previous),
              tooltip: '前の文',
              onPressed: () => unawaited(controller.previous()),
            ),
            IconButton.filled(
              icon: Icon(controller.isPlaying ? Icons.pause : Icons.play_arrow),
              tooltip: controller.isPlaying ? '一時停止' : '再開',
              onPressed: () => unawaited(
                controller.isPlaying ? controller.pause() : controller.resume(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.skip_next),
              tooltip: '次の文',
              onPressed: () => unawaited(controller.next()),
            ),
            IconButton(
              icon: const Icon(Icons.stop),
              tooltip: '停止',
              onPressed: () => unawaited(controller.stop()),
            ),
          ],
        ),
      ),
    );
  }
}

/// 読み上げの開始位置の選択肢。
class ReadAloudStartOption {
  /// コンストラクタ。
  const ReadAloudStartOption({
    required this.icon,
    required this.title,
    required this.segmentIndex,
    this.subtitle,
  });

  /// アイコン。
  final IconData icon;

  /// 表示名。
  final String title;

  /// 補足。
  final String? subtitle;

  /// 読み始める文の番号。
  final int segmentIndex;
}

/// どこから読み上げるかを選ぶシートを出し、選ばれた文の番号を返す。
///
/// キャンセルなら null。
Future<int?> showReadAloudStartSheet(
  BuildContext context,
  List<ReadAloudStartOption> options,
) {
  return showModalBottomSheet<int>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('どこから読み上げますか？')),
          for (final option in options)
            ListTile(
              leading: Icon(option.icon),
              title: Text(option.title),
              subtitle: option.subtitle == null ? null : Text(option.subtitle!),
              onTap: () => Navigator.pop(sheetContext, option.segmentIndex),
            ),
        ],
      ),
    ),
  );
}

/// 読み上げる文が無いことを知らせる。
void showNothingToReadAloud(BuildContext context) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('読み上げる文がありません')));
}

/// [document] を見ている位置（全体の割合）から読むときの文の番号。
int segmentIndexForFraction(SpeechDocument document, double fraction) =>
    document.segmentIndexAtProgress(fraction);
