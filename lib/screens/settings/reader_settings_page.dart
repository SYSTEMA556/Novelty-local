import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/read_aloud/read_aloud_controller.dart';
import 'package:novelty/read_aloud/speech_document.dart';
import 'package:novelty/read_aloud/voicevox_engine.dart';
import 'package:novelty/read_aloud/voicevox_models.dart';
import 'package:novelty/utils/reader_appearance.dart';
import 'package:novelty/utils/settings_provider.dart';
import 'package:novelty/widgets/read_aloud_bar.dart';
import 'package:novelty/widgets/tap_zone_guide.dart';

/// 閲覧設定ページ
class ReaderSettingsPage extends ConsumerWidget {
  /// コンストラクタ
  const ReaderSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('閲覧設定'),
      ),
      body: settings.when(
        data: (data) => ListView(
          children: [
            _buildFontSection(context, ref, data),
            const Divider(),
            _buildLayoutSection(context, ref, data),
            const Divider(),
            _buildColorSection(context, ref, data),
            const Divider(),
            _buildTapZoneSection(context, ref, data),
            const Divider(),
            _buildReadAloudSection(context, ref, data),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
      ),
    );
  }

  Widget _buildFontSection(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'フォント',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ListTile(
          title: Text('サイズ: ${settings.fontSize.toStringAsFixed(1)}'),
          subtitle: Slider(
            value: settings.fontSize,
            min: 10,
            max: 30,
            divisions: 40,
            label: settings.fontSize.toStringAsFixed(1),
            onChanged: (value) async {
              try {
                await ref.read(settingsProvider.notifier).setFontSize(value);
              } on Exception catch (e, stackTrace) {
                debugPrint('Failed to save font size: $e\n$stackTrace');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('フォントサイズ設定の保存に失敗しました'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLayoutSection(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'レイアウト',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ListTile(
          title: Text('行間: ${settings.lineHeight.toStringAsFixed(1)}'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 警告メッセージ（スライダーの上）
              // 注: 通常のUI操作では発生しないが、古いバージョンからのアップデート時や
              // 設定データの移行時など、過渡的な状態で表示される可能性がある
              if (settings.isRubyEnabled &&
                  settings.lineHeight < Settings.minLineHeightWithRuby)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'ルビが重なる可能性があります',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              // スライダー
              Slider(
                value: settings.lineHeight,
                min: settings.isRubyEnabled
                    ? Settings.minLineHeightWithRuby
                    : Settings.minLineHeightWithoutRuby,
                max: 3,
                divisions: settings.isRubyEnabled ? 17 : 20,
                label: settings.lineHeight.toStringAsFixed(1),
                onChanged: (value) async {
                  try {
                    await ref
                        .read(settingsProvider.notifier)
                        .setLineHeight(value);
                  } on Exception catch (e, stackTrace) {
                    debugPrint('Failed to save line height: $e\n$stackTrace');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('行間設定の保存に失敗しました'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
        ..._buildLineLengthTiles(context, ref, settings),
        SwitchListTile(
          title: const Text('縦書き'),
          value: settings.isVertical,
          onChanged: (value) async {
            try {
              await ref
                  .read(settingsProvider.notifier)
                  .setIsVertical(isVertical: value);
            } on Exception catch (e, stackTrace) {
              debugPrint('Failed to save is vertical: $e\n$stackTrace');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('縦書き設定の保存に失敗しました'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
        ),
        if (settings.isVertical)
          SwitchListTile(
            title: const Text('ページ送り'),
            value: settings.isPageFlip,
            onChanged: (value) async {
              try {
                await ref
                    .read(settingsProvider.notifier)
                    .setIsPageFlip(isPageFlip: value);
              } on Exception catch (e, stackTrace) {
                debugPrint('Failed to save is page flip: $e\n$stackTrace');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('ページ送り設定の保存に失敗しました'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
        SwitchListTile(
          title: const Text('ルビを表示'),
          subtitle: const Text('オフにすると行間をより小さく設定できます'),
          value: settings.isRubyEnabled,
          onChanged: (value) async {
            try {
              await ref
                  .read(settingsProvider.notifier)
                  .setIsRubyEnabled(isRubyEnabled: value);
            } on Exception catch (e, stackTrace) {
              debugPrint('Failed to save is ruby enabled: $e\n$stackTrace');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('ルビ表示設定の保存に失敗しました'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
        ),
      ],
    );
  }

  /// 1行の文字数の上限（縦書きは列の高さ、横書きは行の幅）。
  List<Widget> _buildLineLengthTiles(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    Future<void> save(int chars) async {
      try {
        await ref.read(settingsProvider.notifier).setMaxLineChars(chars);
      } on Exception catch (e, stackTrace) {
        debugPrint('Failed to save max line chars: $e\n$stackTrace');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('1行の文字数の保存に失敗しました'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }

    final limited = settings.maxLineChars > 0;
    final chars = settings.maxLineChars
        .clamp(Settings.minLineChars, Settings.maxLineCharsLimit)
        .toDouble();
    return [
      SwitchListTile(
        title: const Text('1行の文字数を制限'),
        subtitle: Text(
          settings.isVertical
              ? '縦書きの1行（列）が画面いっぱいに伸びないようにします'
              : '横書きの1行が画面いっぱいに伸びないようにします',
        ),
        value: limited,
        onChanged: (value) => save(value ? 40 : 0),
      ),
      if (limited)
        ListTile(
          title: Text('1行の文字数: ${settings.maxLineChars} 字'),
          subtitle: Slider(
            value: chars,
            min: Settings.minLineChars.toDouble(),
            max: Settings.maxLineCharsLimit.toDouble(),
            divisions: Settings.maxLineCharsLimit - Settings.minLineChars,
            label: '${chars.round()} 字',
            onChanged: (value) => save(value.round()),
          ),
        ),
    ];
  }

  /// 読み上げ（速さ・声の高さ）。
  Widget _buildReadAloudSection(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    Future<void> save({double? rate, double? pitch}) async {
      try {
        await ref
            .read(settingsProvider.notifier)
            .setTtsVoice(rate: rate, pitch: pitch);
      } on Exception catch (e, stackTrace) {
        debugPrint('Failed to save tts voice: $e\n$stackTrace');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('読み上げ設定の保存に失敗しました'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }

    Future<void> saveActing({
      int? acting,
      String? narrationVoice,
      String? dialogueVoice,
    }) async {
      try {
        await ref
            .read(settingsProvider.notifier)
            .setTtsActing(
              acting: acting,
              narrationVoice: narrationVoice,
              dialogueVoice: dialogueVoice,
            );
      } on Exception catch (e, stackTrace) {
        debugPrint('Failed to save tts acting: $e\n$stackTrace');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('読み上げ設定の保存に失敗しました'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            '読み上げ',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ListTile(
          title: Text('速さ: ${(settings.ttsRate * 2).toStringAsFixed(1)} 倍'),
          subtitle: Slider(
            value: settings.ttsRate.clamp(0.1, 1.0),
            min: 0.1,
            divisions: 18,
            label: '${(settings.ttsRate * 2).toStringAsFixed(1)} 倍',
            onChanged: (value) => save(rate: value),
          ),
        ),
        ListTile(
          title: Text('声の高さ: ${settings.ttsPitch.toStringAsFixed(1)}'),
          subtitle: Slider(
            value: settings.ttsPitch.clamp(0.5, 2.0),
            min: 0.5,
            max: 2,
            divisions: 15,
            label: settings.ttsPitch.toStringAsFixed(1),
            onChanged: (value) => save(pitch: value),
          ),
        ),
        ListTile(
          title: Text('演技の強さ: ${settings.ttsActing}%'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Slider(
                value: settings.ttsActing.clamp(0, 100).toDouble(),
                max: 100,
                divisions: 10,
                label: '${settings.ttsActing}%',
                onChanged: (value) => saveActing(acting: value.round()),
              ),
              const Text(
                '台詞と地の文、「〜と叫んだ」「〜と囁いた」などの言葉、'
                '！や…から場面の感情を読み取り、文ごとに声の高さ・速さ・'
                '音量・間を変えます。0% にすると淡々と読みます。',
              ),
            ],
          ),
        ),
        _VoicePicker(
          narrationVoice: settings.ttsNarrationVoice,
          dialogueVoice: settings.ttsDialogueVoice,
          onNarrationChanged: (name) => saveActing(narrationVoice: name),
          onDialogueChanged: (name) => saveActing(dialogueVoice: name),
        ),
        _ActingPreview(settings: settings),
        ListTile(
          title: const Text('パフォーマンスモード（VOICEVOX）'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('標準')),
                  ButtonSegment(value: 1, label: Text('全力')),
                  ButtonSegment(value: 2, label: Text('充電中だけ全力')),
                ],
                selected: {settings.ttsPerformance.clamp(0, 2)},
                showSelectedIcon: false,
                onSelectionChanged: (value) => unawaited(
                  ref
                      .read(settingsProvider.notifier)
                      .setTtsPerformance(value.first),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                [
                  '標準：4コアまで使い、2文先まで声を作っておきます。',
                  '声のモデルは同時に2つまでにして、メモリを抑えます。',
                  '全力：全コアを優先度高めで使い、5文先まで作り溜めます。',
                  '声のモデルを多めに残すため、メモリを多く使い、',
                  '熱と電池の減りが増えます。',
                ].join(),
              ),
            ],
          ),
        ),
        const _VoicevoxDiagnosis(),
        const _VoicevoxModelList(),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            '声は端末の「テキスト読み上げ」の音声エンジンのものを使います。'
            '「ネット」と付いた声は通信が必要です。',
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showSaveError(BuildContext context, String what) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$whatの保存に失敗しました'),
        backgroundColor: Colors.red,
      ),
    );
  }

  /// 色調（背景色と文字色）。
  Widget _buildColorSection(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    Future<void> select(ReaderColorTheme theme) async {
      try {
        await ref.read(settingsProvider.notifier).setColorTheme(theme);
      } on Exception catch (e, stackTrace) {
        debugPrint('Failed to save color theme: $e\n$stackTrace');
        if (context.mounted) _showSaveError(context, '色調');
      }
    }

    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, '色調'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final theme in ReaderColorTheme.values)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => select(theme),
                  child: Column(
                    children: [
                      // 見本：その色調で「あ」を表示する
                      Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.background ?? scheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: settings.colorTheme == theme
                                ? scheme.primary
                                : scheme.outlineVariant,
                            width: settings.colorTheme == theme ? 3 : 1,
                          ),
                        ),
                        child: Text(
                          'あ',
                          style: TextStyle(
                            fontSize: 22,
                            color: theme.text ?? scheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        theme.label,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// ページボタン（画面の端をタップしてページ送り）。
  Widget _buildTapZoneSection(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    Future<void> save({
      bool? enabled,
      TapZoneLayout? layout,
      int? size,
      bool? reversed,
      bool? disablePrevious,
      int? guideOpacity,
    }) async {
      try {
        await ref
            .read(settingsProvider.notifier)
            .setTapZone(
              enabled: enabled ?? settings.tapZoneEnabled,
              layout: layout ?? settings.tapZoneLayout,
              size: size ?? settings.tapZoneSize,
              reversed: reversed ?? settings.tapZoneReversed,
              disablePrevious:
                  disablePrevious ?? settings.tapZoneDisablePrevious,
              guideOpacity: guideOpacity ?? settings.tapZoneGuideOpacity,
            );
      } on Exception catch (e, stackTrace) {
        debugPrint('Failed to save tap zone: $e\n$stackTrace');
        if (context.mounted) _showSaveError(context, 'ページボタン');
      }
    }

    final enabled = settings.tapZoneEnabled;
    final previewConfig = TapZoneConfig(
      layout: settings.tapZoneLayout,
      sizePercent: settings.tapZoneSize,
      reversed: settings.tapZoneReversed,
      disablePrevious: settings.tapZoneDisablePrevious,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, 'ページボタン'),
        SwitchListTile(
          title: const Text('画面の端をタップしてページ送り'),
          subtitle: const Text('中央のタップはこれまでどおりメニューを表示します'),
          value: enabled,
          onChanged: (value) => save(enabled: value),
        ),
        if (enabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 配置の選択
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final layout in TapZoneLayout.values)
                        InkWell(
                          onTap: () => save(layout: layout),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Icon(
                                  settings.tapZoneLayout == layout
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Flexible(child: Text(layout.label)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // 見本（縦書きなら縦書きの向きで表示する）
                Container(
                  width: 120,
                  height: 180,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  child: TapZoneGuide(
                    config: previewConfig,
                    isVertical: settings.isVertical,
                  ),
                ),
              ],
            ),
          ),
          CheckboxListTile(
            title: const Text('次へ・前へを入れ替える'),
            value: settings.tapZoneReversed,
            onChanged: (value) => save(reversed: value ?? false),
          ),
          CheckboxListTile(
            title: const Text('「前へ」を無効にする'),
            subtitle: const Text('その場所をタップするとメニューを表示します'),
            value: settings.tapZoneDisablePrevious,
            onChanged: (value) => save(disablePrevious: value ?? false),
          ),
          ListTile(
            title: Text('ボタンの太さ: ${settings.tapZoneSize}%'),
            subtitle: Slider(
              value: settings.tapZoneSize.clamp(10, 45).toDouble(),
              min: 10,
              max: 45,
              divisions: 35,
              label: '${settings.tapZoneSize}%',
              onChanged: (value) => save(size: value.round()),
            ),
          ),
          ListTile(
            title: Text(
              settings.tapZoneGuideOpacity == 0
                  ? '本文上の表示: なし'
                  : '本文上の表示の濃さ: ${settings.tapZoneGuideOpacity}%',
            ),
            subtitle: Slider(
              value: settings.tapZoneGuideOpacity.clamp(0, 60).toDouble(),
              max: 60,
              divisions: 12,
              label: '${settings.tapZoneGuideOpacity}%',
              onChanged: (value) => save(guideOpacity: value.round()),
            ),
          ),
        ],
        // 画面の下の、触っても何も起きない帯（フォークで追加）
        ListTile(
          title: Text(
            settings.bottomGuardPercent == 0
                ? '画面下の誤操作よけ: なし'
                : '画面下の誤操作よけ: 下から${settings.bottomGuardPercent}%',
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('戻る・ホームのボタンを押すときに、ページ送りやシークバーが反応しないようにします'),
              Slider(
                value: settings.bottomGuardPercent.clamp(0, 20).toDouble(),
                max: 20,
                divisions: 20,
                label: '${settings.bottomGuardPercent}%',
                onChanged: (value) => unawaited(
                  ref
                      .read(settingsProvider.notifier)
                      .setBottomGuardPercent(value.round()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 地の文・台詞の声を選ぶ欄（端末にある日本語の声から選ぶ）。
class _VoicePicker extends StatefulWidget {
  const _VoicePicker({
    required this.narrationVoice,
    required this.dialogueVoice,
    required this.onNarrationChanged,
    required this.onDialogueChanged,
  });

  final String narrationVoice;
  final String dialogueVoice;
  final ValueChanged<String> onNarrationChanged;
  final ValueChanged<String> onDialogueChanged;

  @override
  State<_VoicePicker> createState() => _VoicePickerState();
}

class _VoicePickerState extends State<_VoicePicker> {
  late final Future<(List<TtsVoice>, bool)> _voices = () async {
    final results = await Future.wait<Object>([
      availableJapaneseVoices(),
      VoicevoxBridge.isAvailable(),
    ]);
    final voicevox = results[1] as bool;
    if (voicevox) await VoicevoxModels.refresh();
    return (results[0] as List<TtsVoice>, voicevox);
  }();

  @override
  Widget build(BuildContext context) {
    // 声を追加・削除したら、選べる声の一覧を作り直す
    return ValueListenableBuilder<Set<String>?>(
      valueListenable: VoicevoxModels.installed,
      builder: (context, installed, _) => _build(context, installed),
    );
  }

  Widget _build(BuildContext context, Set<String>? installed) {
    return FutureBuilder<(List<TtsVoice>, bool)>(
      future: _voices,
      builder: (context, snapshot) {
        final (voices, voicevox) = snapshot.data ?? (const <TtsVoice>[], false);
        if (voices.length < 2 && !voicevox) return const SizedBox.shrink();
        return Column(
          children: [
            if (voicevox)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  [
                    'VOICEVOX の声は端末の中で声を作ります。',
                    '初めて使うときは準備に数十秒かかり、',
                    '読み始めにも少し時間がかかります。',
                  ].join(),
                ),
              ),
            _dropdown(
              title: '地の文の声',
              value: widget.narrationVoice,
              defaultLabel: '端末の標準',
              voices: voices,
              voicevox: voicevox,
              installed: installed,
              onChanged: widget.onNarrationChanged,
            ),
            _dropdown(
              title: '台詞の声',
              value: widget.dialogueVoice,
              defaultLabel: '地の文と同じ',
              voices: voices,
              voicevox: voicevox,
              installed: installed,
              onChanged: widget.onDialogueChanged,
            ),
          ],
        );
      },
    );
  }

  Widget _dropdown({
    required String title,
    required String value,
    required String defaultLabel,
    required List<TtsVoice> voices,
    required bool voicevox,
    required Set<String>? installed,
    required ValueChanged<String> onChanged,
  }) {
    // モデルが入っている声だけを選べるようにする
    final characters = [
      if (voicevox)
        for (final c in voicevoxCharacters)
          if (installed == null || installed.contains(c.model)) c,
    ];
    final known =
        value.isEmpty ||
        voices.any((v) => v.name == value) ||
        characters.any((c) => c.voice == value);
    return ListTile(
      title: Text(title),
      trailing: DropdownButton<String>(
        value: known ? value : '',
        onChanged: (name) {
          if (name != null) onChanged(name);
        },
        items: [
          DropdownMenuItem(value: '', child: Text(defaultLabel)),
          for (final c in characters)
              // クレジット表記を兼ねて「VOICEVOX:四国めたん」と出す
              DropdownMenuItem(value: c.voice, child: Text(c.credit)),
          for (var i = 0; i < voices.length; i++)
            DropdownMenuItem(
              value: voices[i].name,
              child: Text(
                '声${i + 1}${voices[i].needsNetwork ? '（ネット）' : ''}',
              ),
            ),
        ],
      ),
    );
  }
}

/// 演技の試し聞き。
class _ActingPreview extends StatefulWidget {
  const _ActingPreview({required this.settings});

  final AppSettings settings;

  @override
  State<_ActingPreview> createState() => _ActingPreviewState();
}

class _ActingPreviewState extends State<_ActingPreview> {
  ReadAloudController? _controller;

  static final _sample = SpeechDocument.fromElements([
    PlainText('彼女は窓の外を見た。'),
    NewLine(),
    PlainText('「やった！　ついに完成したのね！」'),
    PlainText('と、彼女は声を弾ませた。'),
    NewLine(),
    NewLine(),
    PlainText('「……でも、もう誰もいないの」'),
    NewLine(),
    PlainText('彼女は小さく呟いた。'),
    NewLine(),
    PlainText('「ふざけるな！　ここから出せ！」'),
    PlainText('と男が怒鳴った。'),
  ]);

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    final playing = _controller?.isActive ?? false;
    _controller?.dispose();
    _controller = null;
    if (playing) {
      setState(() {});
      return;
    }
    final controller = ReadAloudController(document: _sample)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    applyReadAloudSettings(controller, widget.settings);
    setState(() => _controller = controller);
    await controller.playFrom(0);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final active = controller?.isActive ?? false;
    final direction = active ? controller?.currentDirection : null;
    return ListTile(
      leading: Icon(active ? Icons.stop : Icons.play_arrow),
      title: Text(active ? '試し聞きを止める' : '演技を試し聞きする'),
      subtitle: direction == null
          ? const Text('いまの設定で、短い場面を読み上げます')
          : Text(
              '${direction.role.label}・${direction.emotion.label}'
              '（強さ ${(direction.intensity * 100).round()}%）',
            ),
      onTap: () => unawaited(_play()),
    );
  }
}

/// VOICEVOX の準備・診断（失敗したときは理由をそのまま見せる）。
class _VoicevoxDiagnosis extends StatefulWidget {
  const _VoicevoxDiagnosis();

  @override
  State<_VoicevoxDiagnosis> createState() => _VoicevoxDiagnosisState();
}

class _VoicevoxDiagnosisState extends State<_VoicevoxDiagnosis> {
  bool _running = false;
  String? _result;
  late final Future<bool> _available = VoicevoxBridge.isAvailable();

  Future<void> _run() async {
    setState(() {
      _running = true;
      _result = null;
    });
    final result = await VoicevoxEngine.diagnose();
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _available,
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        final result = _result;
        return ListTile(
          leading: _running
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.build_outlined),
          title: const Text('VOICEVOX の準備・診断'),
          subtitle: result == null
              ? const Text('声の部品を準備して、声を作る速さを測ります')
              : SelectableText(result),
          onTap: _running ? null : () => unawaited(_run()),
        );
      },
    );
  }
}

/// あとから追加できる VOICEVOX の声（公式の配布元から落とす）。
class _VoicevoxModelList extends StatefulWidget {
  const _VoicevoxModelList();

  @override
  State<_VoicevoxModelList> createState() => _VoicevoxModelListState();
}

class _VoicevoxModelListState extends State<_VoicevoxModelList> {
  late final Future<bool> _available = () async {
    final available = await VoicevoxBridge.isAvailable();
    if (available) await VoicevoxModels.refresh();
    return available;
  }();

  final _listenable = Listenable.merge([
    VoicevoxModels.installed,
    VoicevoxModels.downloading,
  ]);

  Future<void> _download(VoicevoxModelPack pack) async {
    try {
      await VoicevoxModels.download(pack);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${pack.title}の声を追加しました')),
      );
    } on VoicevoxDownloadCancelled {
      // やめたときは何も出さない
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('追加できませんでした：${describeVoicevoxError(e)}'),
        ),
      );
    }
  }

  Future<void> _remove(VoicevoxModelPack pack) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${pack.title}の声を消しますか？'),
        content: Text('${pack.sizeLabel} 空きます。あとでまた追加できます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('やめる'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('消す'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await VoicevoxModels.remove(pack);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('消せませんでした：${describeVoicevoxError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _available,
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        return ListenableBuilder(
          listenable: _listenable,
          builder: (context, _) => ExpansionTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('声を追加する'),
            subtitle: const Text('公式の配布元からダウンロードします（Wi-Fi 推奨）'),
            children: [
              for (final pack in voicevoxModelPacks) _tile(pack),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  '声は github.com/VOICEVOX/voicevox_vvm の公式ファイルを'
                  'そのまま使い、届いた中身を照合してから入れます。'
                  '利用規約とクレジットは「ライセンス」に載せています。',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(VoicevoxModelPack pack) {
    final progress = VoicevoxModels.downloading.value[pack.file];
    final added = VoicevoxModels.extra.value.contains(pack.file);
    final Widget trailing;
    if (progress != null) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              value: progress == 0 ? null : progress,
            ),
          ),
          IconButton(
            tooltip: 'やめる',
            icon: const Icon(Icons.close),
            onPressed: () => VoicevoxModels.cancel(pack),
          ),
        ],
      );
    } else if (added) {
      trailing = IconButton(
        tooltip: '消す',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => unawaited(_remove(pack)),
      );
    } else {
      trailing = IconButton(
        tooltip: 'ダウンロード',
        icon: const Icon(Icons.download),
        onPressed: () => unawaited(_download(pack)),
      );
    }
    return ListTile(
      title: Text(pack.title),
      subtitle: Text(
        [
          pack.description,
          if (progress != null)
            '${(progress * 100).round()}%（${pack.sizeLabel}）'
          else if (added)
            '追加済み（${pack.sizeLabel}）'
          else
            pack.sizeLabel,
        ].join('\n'),
      ),
      isThreeLine: true,
      trailing: trailing,
    );
  }
}
