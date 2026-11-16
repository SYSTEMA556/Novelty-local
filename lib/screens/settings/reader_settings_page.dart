import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/utils/reader_appearance.dart';
import 'package:novelty/utils/settings_provider.dart';
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
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            '声の種類や読み方は、端末の「テキスト読み上げ」設定'
            '（音声エンジン）に従います。',
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
      ],
    );
  }
}
