import 'package:flutter/material.dart';
import 'package:novelty/repositories/preferences_repository.dart';
import 'package:novelty/utils/reader_appearance.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_provider.g.dart';

@immutable
/// アプリケーションの設定を管理するクラス。
class AppSettings {
  /// コンストラクタ。
  const AppSettings({
    required this.themeMode,
    required this.fontSize,
    required this.lineHeight,
    required this.isVertical,
    required this.isIncognito,
    required this.isPageFlip,
    required this.isRubyEnabled,
    this.isOfflineMode = false,
    this.maxLineChars = 0,
    this.ttsRate = 0.5,
    this.ttsPitch = 1.0,
    this.ttsActing = 60,
    this.ttsNarrationVoice = '',
    this.ttsDialogueVoice = '',
    this.ttsPerformance = 0,
    this.colorTheme = ReaderColorTheme.system,
    this.tapZoneEnabled = false,
    this.tapZoneLayout = TapZoneLayout.sides,
    this.tapZoneSize = 30,
    this.tapZoneReversed = false,
    this.tapZoneDisablePrevious = false,
    this.tapZoneGuideOpacity = 0,
    this.bottomGuardPercent = 10,
    this.localGridEnabled = false,
    this.localGridColumns = 3,
    this.localGridShowNames = true,
    this.localGridSquare = false,
  });

  /// テーマモード (system, light, dark)。
  final ThemeMode themeMode;

  /// フォントサイズ。
  final double fontSize;

  /// 行間。
  final double lineHeight;

  /// 縦書き設定。
  final bool isVertical;

  /// シークレットモード (履歴を残さない)。
  final bool isIncognito;

  /// ページ送り設定 (true: ページ送り, false: スクロール)。
  final bool isPageFlip;

  /// ルビ（ふりがな）の表示設定。
  ///
  /// `true` の場合、ルビが表示されます（デフォルト）。
  /// `false` の場合、ルビは非表示になりベーステキストのみが表示されます。
  /// これにより、行間をより小さく設定することができます。
  final bool isRubyEnabled;

  /// オフラインモード設定。
  ///
  /// `true` の場合、ネットワーク通信を行わず、ダウンロード済みのコンテンツのみを利用します。
  final bool isOfflineMode;

  /// 1行の文字数の上限（0 なら制限なし）。
  ///
  /// 画面いっぱいだと1行が長すぎて読みにくい場合に、
  /// 縦書きは列の高さ、横書きは行の幅をこの文字数分に抑える。
  final int maxLineChars;

  /// 読み上げの速さ（0.1〜1.0。0.5 が標準）。
  final double ttsRate;

  /// 読み上げの声の高さ（0.5〜2.0。1.0 が標準）。
  final double ttsPitch;

  /// 読み上げの演技の強さ（%。0 なら感情を付けず淡々と読む）。
  final int ttsActing;

  /// 地の文を読む声の名前（空なら端末の標準の声）。
  final String ttsNarrationVoice;

  /// 台詞・心の声を読む声の名前（空なら地の文と同じ声）。
  final String ttsDialogueVoice;

  /// 読み上げのパフォーマンスモード（0: 標準、1: 全力、2: 充電中だけ全力）。
  final int ttsPerformance;

  /// 本文の色調。
  final ReaderColorTheme colorTheme;

  /// ページボタン（画面の端をタップしてページ送り）を使うか。
  final bool tapZoneEnabled;

  /// ページボタンの配置。
  final TapZoneLayout tapZoneLayout;

  /// ページボタンの帯の太さ（%）。
  final int tapZoneSize;

  /// ページボタンの次へ／前へを入れ替えるか。
  final bool tapZoneReversed;

  /// ページボタンの「前へ」を無効にするか。
  final bool tapZoneDisablePrevious;

  /// ページボタンの領域を本文の上に薄く表示する濃さ（%。0 で非表示）。
  final int tapZoneGuideOpacity;

  /// 読書画面の下に空けておく、触っても何も起きない帯の高さ
  /// （画面の高さに対する%。0 で空けない）。フォークで追加。
  ///
  /// Android の戻る・ホームのボタンやジェスチャーを使うときに、
  /// 誤ってページが進んだりシークバーが動いたりしないようにする。
  final int bottomGuardPercent;

  /// ローカル作品の一覧をグリッドで表示するか。
  final bool localGridEnabled;

  /// グリッドの列数。
  final int localGridColumns;

  /// グリッドに名前を表示するか。
  final bool localGridShowNames;

  /// グリッドの各マスを正方形にするか。
  final bool localGridSquare;

  /// ページボタンの設定（使わない場合は null）。
  TapZoneConfig? get tapZoneConfig => tapZoneEnabled
      ? TapZoneConfig(
          layout: tapZoneLayout,
          sizePercent: tapZoneSize,
          reversed: tapZoneReversed,
          disablePrevious: tapZoneDisablePrevious,
        )
      : null;

  /// 設定をコピーするメソッド。
  AppSettings copyWith({
    ThemeMode? themeMode,
    double? fontSize,
    double? lineHeight,
    bool? isVertical,
    bool? isIncognito,
    bool? isPageFlip,
    bool? isRubyEnabled,
    bool? isOfflineMode,
    int? maxLineChars,
    double? ttsRate,
    double? ttsPitch,
    int? ttsActing,
    String? ttsNarrationVoice,
    String? ttsDialogueVoice,
    int? ttsPerformance,
    ReaderColorTheme? colorTheme,
    bool? tapZoneEnabled,
    TapZoneLayout? tapZoneLayout,
    int? tapZoneSize,
    bool? tapZoneReversed,
    bool? tapZoneDisablePrevious,
    int? tapZoneGuideOpacity,
    int? bottomGuardPercent,
    bool? localGridEnabled,
    int? localGridColumns,
    bool? localGridShowNames,
    bool? localGridSquare,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      isVertical: isVertical ?? this.isVertical,
      isIncognito: isIncognito ?? this.isIncognito,
      isPageFlip: isPageFlip ?? this.isPageFlip,
      isRubyEnabled: isRubyEnabled ?? this.isRubyEnabled,
      isOfflineMode: isOfflineMode ?? this.isOfflineMode,
      maxLineChars: maxLineChars ?? this.maxLineChars,
      ttsRate: ttsRate ?? this.ttsRate,
      ttsPitch: ttsPitch ?? this.ttsPitch,
      ttsActing: ttsActing ?? this.ttsActing,
      ttsNarrationVoice: ttsNarrationVoice ?? this.ttsNarrationVoice,
      ttsDialogueVoice: ttsDialogueVoice ?? this.ttsDialogueVoice,
      ttsPerformance: ttsPerformance ?? this.ttsPerformance,
      colorTheme: colorTheme ?? this.colorTheme,
      tapZoneEnabled: tapZoneEnabled ?? this.tapZoneEnabled,
      tapZoneLayout: tapZoneLayout ?? this.tapZoneLayout,
      tapZoneSize: tapZoneSize ?? this.tapZoneSize,
      tapZoneReversed: tapZoneReversed ?? this.tapZoneReversed,
      tapZoneDisablePrevious:
          tapZoneDisablePrevious ?? this.tapZoneDisablePrevious,
      tapZoneGuideOpacity: tapZoneGuideOpacity ?? this.tapZoneGuideOpacity,
      bottomGuardPercent: bottomGuardPercent ?? this.bottomGuardPercent,
      localGridEnabled: localGridEnabled ?? this.localGridEnabled,
      localGridColumns: localGridColumns ?? this.localGridColumns,
      localGridShowNames: localGridShowNames ?? this.localGridShowNames,
      localGridSquare: localGridSquare ?? this.localGridSquare,
    );
  }
}

@Riverpod(keepAlive: true)
/// アプリケーションの設定を提供するプロバイダー。
class Settings extends _$Settings {
  static const _themeModeKey = 'theme_mode';
  static const _fontSizeKey = 'font_size';
  static const _lineHeightKey = 'line_height';
  static const _isVerticalKey = 'is_vertical';
  static const _isIncognitoKey = 'is_incognito';
  static const _isPageFlipKey = 'is_page_flip';
  static const _isRubyEnabledKey = 'is_ruby_enabled';
  static const _isOfflineModeKey = 'is_offline_mode';
  static const _maxLineCharsKey = 'max_line_chars';
  static const _ttsRateKey = 'tts_rate';
  static const _ttsPitchKey = 'tts_pitch';
  static const _ttsActingKey = 'tts_acting';
  static const _ttsNarrationVoiceKey = 'tts_narration_voice';
  static const _ttsDialogueVoiceKey = 'tts_dialogue_voice';
  static const _ttsPerformanceKey = 'tts_performance';
  static const _colorThemeKey = 'reader_color_theme';
  static const _tapZoneEnabledKey = 'tap_zone_enabled';
  static const _tapZoneLayoutKey = 'tap_zone_layout';
  static const _tapZoneSizeKey = 'tap_zone_size';
  static const _tapZoneReversedKey = 'tap_zone_reversed';
  static const _tapZoneDisablePreviousKey = 'tap_zone_disable_previous';
  static const _tapZoneGuideOpacityKey = 'tap_zone_guide_opacity';
  static const _bottomGuardPercentKey = 'bottom_guard_percent';
  static const _localGridEnabledKey = 'local_grid_enabled';
  static const _localGridColumnsKey = 'local_grid_columns';
  static const _localGridShowNamesKey = 'local_grid_show_names';
  static const _localGridSquareKey = 'local_grid_square';

  /// 1行の文字数の上限として選べる最小値。
  static const int minLineChars = 15;

  /// 1行の文字数の上限として選べる最大値。
  static const int maxLineCharsLimit = 60;

  /// ルビ表示時の最小行間。
  ///
  /// ルビが重なることを防ぐための最小値。
  /// 理論値1.25に安全マージンを加えた値。
  static const double minLineHeightWithRuby = 1.3;

  /// ルビ非表示時の最小行間。
  ///
  /// ルビが非表示の場合、より詰まった表示が可能。
  static const double minLineHeightWithoutRuby = 1;

  PreferencesRepository? _repository;

  Future<PreferencesRepository> get _repo async {
    _repository ??= ref.read(preferencesRepositoryProvider);
    return _repository!;
  }

  @override
  Future<AppSettings> build() async {
    final repo = await _repo;
    final themeModeIndex =
        await repo.getInt(_themeModeKey) ?? ThemeMode.system.index;
    final fontSize = await repo.getDouble(_fontSizeKey) ?? 16.0;
    final lineHeight = await repo.getDouble(_lineHeightKey) ?? 1.5;
    final isVertical = await repo.getBool(_isVerticalKey) ?? false;
    final isIncognito = await repo.getBool(_isIncognitoKey) ?? false;
    final isPageFlip = await repo.getBool(_isPageFlipKey) ?? false;
    final isRubyEnabled = await repo.getBool(_isRubyEnabledKey) ?? true;
    final isOfflineMode = await repo.getBool(_isOfflineModeKey) ?? false;
    final maxLineChars = await repo.getInt(_maxLineCharsKey) ?? 0;
    final ttsRate = await repo.getDouble(_ttsRateKey) ?? 0.5;
    final ttsPitch = await repo.getDouble(_ttsPitchKey) ?? 1.0;
    final ttsActing = await repo.getInt(_ttsActingKey) ?? 60;
    final ttsNarrationVoice =
        await repo.getString(_ttsNarrationVoiceKey) ?? '';
    final ttsDialogueVoice = await repo.getString(_ttsDialogueVoiceKey) ?? '';
    final ttsPerformance = await repo.getInt(_ttsPerformanceKey) ?? 0;
    final colorTheme = ReaderColorTheme.fromName(
      await repo.getString(_colorThemeKey),
    );
    final tapZoneEnabled = await repo.getBool(_tapZoneEnabledKey) ?? false;
    final tapZoneLayout = TapZoneLayout.fromName(
      await repo.getString(_tapZoneLayoutKey),
    );
    final tapZoneSize = await repo.getInt(_tapZoneSizeKey) ?? 30;
    final tapZoneReversed = await repo.getBool(_tapZoneReversedKey) ?? false;
    final tapZoneDisablePrevious =
        await repo.getBool(_tapZoneDisablePreviousKey) ?? false;
    final tapZoneGuideOpacity =
        await repo.getInt(_tapZoneGuideOpacityKey) ?? 0;
    final bottomGuardPercent = await repo.getInt(_bottomGuardPercentKey) ?? 10;
    final localGridEnabled = await repo.getBool(_localGridEnabledKey) ?? false;
    final localGridColumns = await repo.getInt(_localGridColumnsKey) ?? 3;
    final localGridShowNames =
        await repo.getBool(_localGridShowNamesKey) ?? true;
    final localGridSquare = await repo.getBool(_localGridSquareKey) ?? false;

    return AppSettings(
      themeMode: ThemeMode.values[themeModeIndex],
      fontSize: fontSize,
      lineHeight: lineHeight,
      isVertical: isVertical,
      isIncognito: isIncognito,
      isPageFlip: isPageFlip,
      isRubyEnabled: isRubyEnabled,
      isOfflineMode: isOfflineMode,
      maxLineChars: maxLineChars,
      ttsRate: ttsRate,
      ttsPitch: ttsPitch,
      ttsActing: ttsActing,
      ttsNarrationVoice: ttsNarrationVoice,
      ttsDialogueVoice: ttsDialogueVoice,
      ttsPerformance: ttsPerformance,
      colorTheme: colorTheme,
      tapZoneEnabled: tapZoneEnabled,
      tapZoneLayout: tapZoneLayout,
      tapZoneSize: tapZoneSize,
      tapZoneReversed: tapZoneReversed,
      tapZoneDisablePrevious: tapZoneDisablePrevious,
      tapZoneGuideOpacity: tapZoneGuideOpacity,
      bottomGuardPercent: bottomGuardPercent,
      localGridEnabled: localGridEnabled,
      localGridColumns: localGridColumns,
      localGridShowNames: localGridShowNames,
      localGridSquare: localGridSquare,
    );
  }

  /// 設定を1つ保存し、状態に反映する共通処理。
  Future<void> _save(
    String label,
    Future<bool> Function(PreferencesRepository repo) write,
    AppSettings Function(AppSettings current) apply,
  ) async {
    if (!state.hasValue) {
      throw StateError('Settings are not loaded');
    }
    try {
      final repo = await _repo;
      if (!await write(repo)) {
        throw Exception('Failed to save $label setting');
      }
      state = AsyncData(apply(state.value!));
    } catch (e, stackTrace) {
      debugPrint('Error saving $label setting: $e\nStack trace: $stackTrace');
      state = AsyncError(e, stackTrace);
      rethrow;
    }
  }

  /// 読み上げの演技の強さ・声を保存する（null の項目は変えない）。
  Future<void> setTtsActing({
    int? acting,
    String? narrationVoice,
    String? dialogueVoice,
  }) => _save(
    'tts acting',
    (repo) async =>
        (acting == null || await repo.setInt(_ttsActingKey, acting)) &&
        (narrationVoice == null ||
            await repo.setString(_ttsNarrationVoiceKey, narrationVoice)) &&
        (dialogueVoice == null ||
            await repo.setString(_ttsDialogueVoiceKey, dialogueVoice)),
    (s) => s.copyWith(
      ttsActing: acting,
      ttsNarrationVoice: narrationVoice,
      ttsDialogueVoice: dialogueVoice,
    ),
  );

  /// 読み上げのパフォーマンスモードを保存する。
  Future<void> setTtsPerformance(int mode) => _save(
    'tts performance',
    (repo) => repo.setInt(_ttsPerformanceKey, mode),
    (s) => s.copyWith(ttsPerformance: mode),
  );

  /// 本文の色調を設定する。
  Future<void> setColorTheme(ReaderColorTheme theme) => _save(
    'color theme',
    (repo) => repo.setString(_colorThemeKey, theme.name),
    (s) => s.copyWith(colorTheme: theme),
  );

  /// ページボタンの設定をまとめて保存する。
  Future<void> setTapZone({
    required bool enabled,
    required TapZoneLayout layout,
    required int size,
    required bool reversed,
    required bool disablePrevious,
    required int guideOpacity,
  }) => _save(
    'tap zone',
    (repo) async =>
        await repo.setBool(_tapZoneEnabledKey, enabled) &&
        await repo.setString(_tapZoneLayoutKey, layout.name) &&
        await repo.setInt(_tapZoneSizeKey, size) &&
        await repo.setBool(_tapZoneReversedKey, reversed) &&
        await repo.setBool(_tapZoneDisablePreviousKey, disablePrevious) &&
        await repo.setInt(_tapZoneGuideOpacityKey, guideOpacity),
    (s) => s.copyWith(
      tapZoneEnabled: enabled,
      tapZoneLayout: layout,
      tapZoneSize: size,
      tapZoneReversed: reversed,
      tapZoneDisablePrevious: disablePrevious,
      tapZoneGuideOpacity: guideOpacity,
    ),
  );

  /// 読書画面の下に空けておく帯の高さ（%）を保存する。
  Future<void> setBottomGuardPercent(int percent) => _save(
    'bottom guard',
    (repo) => repo.setInt(_bottomGuardPercentKey, percent),
    (s) => s.copyWith(bottomGuardPercent: percent),
  );

  /// ローカル作品のグリッド表示の設定をまとめて保存する。
  Future<void> setLocalGrid({
    required bool enabled,
    required int columns,
    required bool showNames,
    required bool square,
  }) => _save(
    'local grid',
    (repo) async =>
        await repo.setBool(_localGridEnabledKey, enabled) &&
        await repo.setInt(_localGridColumnsKey, columns) &&
        await repo.setBool(_localGridShowNamesKey, showNames) &&
        await repo.setBool(_localGridSquareKey, square),
    (s) => s.copyWith(
      localGridEnabled: enabled,
      localGridColumns: columns,
      localGridShowNames: showNames,
      localGridSquare: square,
    ),
  );

  /// 読み上げの速さ・声の高さを設定するメソッド。
  Future<void> setTtsVoice({double? rate, double? pitch}) async {
    if (!state.hasValue) {
      throw StateError('Settings are not loaded');
    }

    try {
      final repo = await _repo;
      if (rate != null && !await repo.setDouble(_ttsRateKey, rate)) {
        throw Exception('Failed to save tts rate setting');
      }
      if (pitch != null && !await repo.setDouble(_ttsPitchKey, pitch)) {
        throw Exception('Failed to save tts pitch setting');
      }
      state = AsyncData(
        state.value!.copyWith(ttsRate: rate, ttsPitch: pitch),
      );
    } catch (e, stackTrace) {
      debugPrint('Error saving tts setting: $e\nStack trace: $stackTrace');
      state = AsyncError(e, stackTrace);
      rethrow;
    }
  }

  /// 1行の文字数の上限を設定するメソッド（0 なら制限なし）。
  Future<void> setMaxLineChars(int chars) async {
    if (!state.hasValue) {
      throw StateError('Settings are not loaded');
    }

    try {
      final repo = await _repo;
      final success = await repo.setInt(_maxLineCharsKey, chars);
      if (!success) {
        throw Exception('Failed to save max line chars setting');
      }
      state = AsyncData(state.value!.copyWith(maxLineChars: chars));
    } catch (e, stackTrace) {
      debugPrint(
        'Error saving max line chars setting: $e\nStack trace: $stackTrace',
      );
      state = AsyncError(e, stackTrace);
      rethrow;
    }
  }

  /// テーマモードを設定するメソッド。
  Future<void> setThemeMode(ThemeMode mode) async {
    if (!state.hasValue) {
      throw StateError('Settings are not loaded');
    }

    try {
      final repo = await _repo;
      final success = await repo.setInt(_themeModeKey, mode.index);
      if (!success) {
        throw Exception('Failed to save theme mode setting');
      }
      state = AsyncData(state.value!.copyWith(themeMode: mode));
    } catch (e, stackTrace) {
      debugPrint(
        'Error saving theme mode setting: $e\nStack trace: $stackTrace',
      );
      state = AsyncError(e, stackTrace);
      rethrow;
    }
  }

  /// フォントサイズを設定するメソッド。
  Future<void> setFontSize(double size) async {
    if (!state.hasValue) {
      throw StateError('Settings are not loaded');
    }

    try {
      final repo = await _repo;
      final success = await repo.setDouble(_fontSizeKey, size);
      if (!success) {
        throw Exception('Failed to save font size setting');
      }
      state = AsyncData(state.value!.copyWith(fontSize: size));
    } catch (e, stackTrace) {
      debugPrint(
        'Error saving font size setting: $e\nStack trace: $stackTrace',
      );
      state = AsyncError(e, stackTrace);
      rethrow;
    }
  }

  /// 行間を設定するメソッド。
  Future<void> setLineHeight(double height) async {
    if (!state.hasValue) {
      throw StateError('Settings are not loaded');
    }

    try {
      final repo = await _repo;
      final success = await repo.setDouble(_lineHeightKey, height);
      if (!success) {
        throw Exception('Failed to save line height setting');
      }
      state = AsyncData(state.value!.copyWith(lineHeight: height));
    } catch (e, stackTrace) {
      debugPrint(
        'Error saving line height setting: $e\nStack trace: $stackTrace',
      );
      state = AsyncError(e, stackTrace);
      rethrow;
    }
  }

  /// 縦書き設定を更新するメソッド。
  Future<void> setIsVertical({required bool isVertical}) async {
    if (!state.hasValue) {
      throw StateError('Settings are not loaded');
    }

    try {
      final repo = await _repo;
      final success = await repo.setBool(_isVerticalKey, isVertical);
      if (!success) {
        throw Exception('Failed to save vertical setting');
      }
      state = AsyncData(state.value!.copyWith(isVertical: isVertical));
    } catch (e, stackTrace) {
      debugPrint('Error saving vertical setting: $e\nStack trace: $stackTrace');
      state = AsyncError(e, stackTrace);
      rethrow;
    }
  }

  /// シークレットモードを設定するメソッド。
  Future<void> setIsIncognito({required bool isIncognito}) async {
    if (!state.hasValue) {
      throw StateError('Settings are not loaded');
    }

    try {
      final repo = await _repo;
      final success = await repo.setBool(
        _isIncognitoKey,
        isIncognito,
      );
      if (!success) {
        throw Exception('Failed to save incognito setting');
      }
      state = AsyncData(state.value!.copyWith(isIncognito: isIncognito));
    } catch (e, stackTrace) {
      debugPrint(
        'Error saving incognito setting: $e\nStack trace: $stackTrace',
      );
      state = AsyncError(e, stackTrace);
      rethrow;
    }
  }

  /// オフラインモードを設定するメソッド。
  Future<void> setIsOfflineMode({required bool isOfflineMode}) async {
    if (!state.hasValue) {
      throw StateError('Settings are not loaded');
    }

    try {
      final repo = await _repo;
      final success = await repo.setBool(
        _isOfflineModeKey,
        isOfflineMode,
      );
      if (!success) {
        throw Exception('Failed to save offline mode setting');
      }
      state = AsyncData(state.value!.copyWith(isOfflineMode: isOfflineMode));
    } catch (e, stackTrace) {
      debugPrint(
        'Error saving offline mode setting: $e\nStack trace: $stackTrace',
      );
      state = AsyncError(e, stackTrace);
      rethrow;
    }
  }

  /// ページ送り設定を更新するメソッド。
  Future<void> setIsPageFlip({required bool isPageFlip}) async {
    if (!state.hasValue) {
      throw StateError('Settings are not loaded');
    }

    try {
      final repo = await _repo;
      final success = await repo.setBool(_isPageFlipKey, isPageFlip);
      if (!success) {
        throw Exception('Failed to save page flip setting');
      }
      state = AsyncData(state.value!.copyWith(isPageFlip: isPageFlip));
    } catch (e, stackTrace) {
      debugPrint(
        'Error saving page flip setting: $e\nStack trace: $stackTrace',
      );
      state = AsyncError(e, stackTrace);
      rethrow;
    }
  }

  /// ルビ表示設定を更新するメソッド。
  ///
  /// ルビを有効にする場合、行間が [minLineHeightWithRuby] 未満であれば
  /// 自動的に [minLineHeightWithRuby] に調整します。
  /// これはルビが重なることを防ぐためです。
  ///
  /// 永続化処理は2段階で行われるため、2段階目が失敗した場合は
  /// 1段階目の変更をロールバックしてデータ整合性を保証します。
  Future<void> setIsRubyEnabled({required bool isRubyEnabled}) async {
    if (!state.hasValue) {
      throw StateError('Settings are not loaded');
    }

    try {
      final repo = await _repo;
      final originalIsRubyEnabled = state.value!.isRubyEnabled;

      // Phase 1: isRubyEnabled設定を保存
      final success = await repo.setBool(_isRubyEnabledKey, isRubyEnabled);
      if (!success) {
        throw Exception('Failed to save ruby enabled setting');
      }

      // Phase 1成功後の例外もロールバック対象
      AppSettings newSettings;
      try {
        newSettings = state.value!.copyWith(isRubyEnabled: isRubyEnabled);
      } catch (e, stackTrace) {
        debugPrint(
          'Failed to create new settings: $e\nStack trace: $stackTrace',
        );
        // Phase 1をロールバック
        await _rollbackIsRubyEnabled(repo, originalIsRubyEnabled);
        rethrow;
      }

      // Phase 2: 必要に応じて行間を調整（失敗時はロールバック）
      if (isRubyEnabled && newSettings.lineHeight < minLineHeightWithRuby) {
        final lineHeightSuccess = await repo.setDouble(
          _lineHeightKey,
          minLineHeightWithRuby,
        );
        if (!lineHeightSuccess) {
          // ロールバック: isRubyEnabledを元に戻す
          await _rollbackIsRubyEnabled(repo, originalIsRubyEnabled);
          throw Exception(
            'Failed to save line height setting. '
            'Ruby setting has been rolled back.',
          );
        }
        newSettings = newSettings.copyWith(lineHeight: minLineHeightWithRuby);
      }

      state = AsyncData(newSettings);
    } catch (e, stackTrace) {
      debugPrint(
        'Error saving ruby enabled setting: $e\nStack trace: $stackTrace',
      );
      state = AsyncError(e, stackTrace);
      rethrow;
    }
  }

  /// isRubyEnabledのロールバック処理。
  ///
  /// ロールバック処理自体が失敗した場合は、クリティカルエラーとして扱う。
  Future<void> _rollbackIsRubyEnabled(
    PreferencesRepository repo,
    bool originalValue,
  ) async {
    try {
      final rollbackSuccess = await repo.setBool(
        _isRubyEnabledKey,
        originalValue,
      );
      if (!rollbackSuccess) {
        debugPrint(
          'CRITICAL: Rollback failed - data may be in inconsistent state.',
        );
        throw Exception(
          'Failed to save line height and rollback failed. '
          'Settings may be inconsistent. Please restart the app.',
        );
      }
    } on Exception catch (rollbackError, rollbackStackTrace) {
      // Exceptionの場合はそのまま再スロー
      debugPrint(
        'CRITICAL: Rollback threw exception: $rollbackError\n'
        '$rollbackStackTrace',
      );
      throw Exception(
        'Failed to save line height and rollback threw exception. '
        'Settings are inconsistent. Please restart the app.',
      );
    }
  }
}

/// オフラインモードが有効かどうかを同期で取得するプロバイダー。
///
/// [settingsProvider] の値から派生し、取得中やエラー時は `false` を返す。
@riverpod
bool isOfflineMode(Ref ref) {
  return ref
      .watch(settingsProvider)
      .maybeWhen(
        data: (settings) => settings.isOfflineMode,
        orElse: () => false,
      );
}
