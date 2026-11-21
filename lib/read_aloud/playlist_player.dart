/// 連続再生リストを、画面を開かずに読み上げる（フォークで追加）。
///
/// ローカル本棚の作品と Web 小説（なろう・カクヨム）を、リストの順に流す。
/// - ローカルの作品：前回の読み上げ位置（無ければ最初）から最後まで。
/// - Web 小説：最後に読んだ話の最初から、最終話まで話を送りながら。
///   話を進めるたびに閲覧履歴の「最後に読んだ話」も進める。
///
/// 読み込み・解析・読み上げの作成と開始は、すべてこのクラスの中
/// （画面の build の外）で行う。画面が消えている間（運転中など）は build が
/// 走らないため、画面に頼ると次の作品へ進めないから（ADR-0005）。
///
/// 読み上げは [ReadAloudController] なので、通知・車のボタン・ナビとの
/// 譲り合いは読書画面のときと同じように効く。読書画面で別の読み上げを
/// 始めると、こちらは止まる（端末の声は1つだけ）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:novelty/local_library/read_aloud_playlist.dart';
import 'package:novelty/models/episode.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/read_aloud/read_aloud_controller.dart';
import 'package:novelty/read_aloud/reading_dictionary.dart';
import 'package:novelty/read_aloud/speech_document.dart';
import 'package:novelty/repositories/novel_repository.dart';
import 'package:novelty/screens/local_text_reader_page.dart';
import 'package:novelty/screens/local_work_reader_page.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/settings_provider.dart';
import 'package:novelty/widgets/read_aloud_bar.dart';

/// 連続再生で今読んでいるもの。
@immutable
class PlaylistNowPlaying {
  /// コンストラクタ。
  const PlaylistNowPlaying({
    required this.entry,
    required this.title,
    required this.controller,
    this.subtitle,
  });

  /// リストのどの作品か。
  final PlaylistEntry entry;

  /// 作品名。
  final String title;

  /// 作者や「第N話 サブタイトル」。
  final String? subtitle;

  /// 読み上げ。
  final ReadAloudController controller;
}

/// 連続再生の再生係。
final playlistPlayerProvider =
    NotifierProvider<PlaylistPlayer, PlaylistNowPlaying?>(PlaylistPlayer.new);

/// 連続再生の再生係。今読んでいるもの（無ければ null）を状態に持つ。
class PlaylistPlayer extends Notifier<PlaylistNowPlaying?> {
  // 作るたびに増やし、古い読み込みの結果を捨てる
  int _generation = 0;

  @override
  PlaylistNowPlaying? build() {
    // 読み上げの設定（速さ・声など）を変えたら、今の読み上げにも反映する
    ref
      ..listen(settingsProvider, (_, next) {
        final controller = state?.controller;
        if (controller != null) applyReadAloudSettings(controller, next.value);
      })
      ..onDispose(() => state?.controller.dispose());
    return null;
  }

  /// [entry] から読み始める。
  ///
  /// [announcement] は最初に読む案内（「次は、〇〇」など）。
  Future<void> playFrom(PlaylistEntry entry, {String? announcement}) async {
    final generation = ++_generation;
    try {
      final next = switch (entry) {
        LocalPlaylistEntry() => await _prepareLocal(entry, announcement),
        WebPlaylistEntry() => await _prepareWeb(entry, announcement, null),
      };
      if (generation != _generation) {
        next?.controller.dispose();
        return;
      }
      if (next == null) {
        // 読めない作品（本棚から消えた・読む文が無い）は飛ばす
        await _advanceFrom(entry);
        return;
      }
      await _start(next);
    } on Object catch (e) {
      debugPrint('連続再生: ${entry.key} を読めませんでした: $e');
      if (generation == _generation) await _advanceFrom(entry);
    }
  }

  /// 止めて、連続再生を終える。
  void stop() {
    _generation++;
    state?.controller.dispose();
    state = null;
  }

  /// 画面で [finished] を読み終えたとき、リストの次の作品から続ける。
  Future<void> continueAfter(PlaylistEntry finished) {
    _generation++;
    return _advanceFrom(finished);
  }

  /// 今の作品を飛ばして、リストの次の作品へ。
  Future<void> skipToNextEntry() async {
    final current = state;
    if (current == null) return;
    await _advanceFrom(current.entry);
  }

  Future<void> _start(PlaylistNowPlaying next) async {
    final previous = state;
    state = next;
    // 前の読み上げは、次のものを作ってから片付ける
    // （通知を途切れさせず、画面が消えたままでも続けられるように）
    previous?.controller.dispose();
    final controller = next.controller;
    applyReadAloudSettings(controller, ref.read(settingsProvider).value);
    final start = _startIndexOf[controller] ?? 0;
    await controller.playFrom(start);
  }

  // 読み始める文の番号（作るときに決め、始めるときに使う）
  final _startIndexOf = Expando<int>();

  Future<void> _advanceFrom(PlaylistEntry finished) async {
    final keys = await ref.read(readAloudPlaylistProvider.future);
    final nextKey = nextInPlaylist(keys, finished.key);
    final nextEntry = nextKey == null ? null : PlaylistEntry.parse(nextKey);
    if (nextEntry == null) {
      // リストの最後まで読んだ
      stop();
      return;
    }
    final title = await _titleOf(nextEntry);
    await playFrom(
      nextEntry,
      announcement: title == null ? null : '次は、$title',
    );
  }

  Future<String?> _titleOf(PlaylistEntry entry) async {
    try {
      switch (entry) {
        case LocalPlaylistEntry(:final workId):
          final works = await ref.read(localWorksProvider.future);
          return works.where((w) => w.id == workId).firstOrNull?.title;
        case WebPlaylistEntry(:final source, :final workId):
          final info = await ref.read(
            novelInfoWithCacheProvider(source, workId).future,
          );
          return info.title;
      }
    } on Object {
      return null;
    }
  }

  // ---- ローカル本棚の作品 ----

  Future<PlaylistNowPlaying?> _prepareLocal(
    LocalPlaylistEntry entry,
    String? announcement,
  ) async {
    final works = await ref.read(localWorksProvider.future);
    final work = works.where((w) => w.id == entry.workId).firstOrNull;
    if (work == null) return null;
    final store = await ref.read(localLibraryStoreProvider.future);
    final saved = await ref.read(readingPositionsProvider.future);
    final options = await ref.read(localTextOptionsProvider.future);
    final text = await store.readText(work.id);
    final elements = await parseInBackground(text, options: options);
    final document = SpeechDocument.fromElements(elements);
    if (document.segments.isEmpty) return null;
    final controller = createLocalReadAloud(
      document: document,
      title: work.title,
      author: work.author,
      workId: work.id,
      positions: ref.read(readingPositionsProvider.notifier),
      announcement: announcement,
      onCompleted: () => unawaited(_advanceFrom(entry)),
    );
    // 前回の続きから。最後まで読んだ作品なら最初から
    final ttsOffset = saved[work.id]?.ttsOffset;
    var start = ttsOffset == null ? 0 : document.segmentIndexAt(ttsOffset);
    if (start >= document.segments.length - 1) start = 0;
    _startIndexOf[controller] = start;
    return PlaylistNowPlaying(
      entry: entry,
      title: work.title,
      subtitle: work.author,
      controller: controller,
    );
  }

  // ---- Web 小説 ----

  Future<PlaylistNowPlaying?> _prepareWeb(
    WebPlaylistEntry entry,
    String? announcement,
    int? episode,
  ) async {
    final source = entry.source;
    final workId = entry.workId;
    final repository = ref.read(novelRepositoryProvider);
    final info = await ref.read(
      novelInfoWithCacheProvider(source, workId).future,
    );
    final total = info.generalAllNo ?? 1;
    // 指定が無ければ、最後に読んだ話から
    var ep =
        episode ??
        await repository.watchLastReadEpisode(source, workId).first ??
        1;
    ep = ep.clamp(1, total);

    // 読む文の無い話（挿絵だけなど）は飛ばす
    SpeechDocument? document;
    while (ep <= total) {
      final elements = await ref.read(
        novelContentProvider(source: source, workId: workId, episode: ep)
            .future,
      );
      document = SpeechDocument.fromElements(elements);
      if (document.segments.isNotEmpty) break;
      ep++;
    }
    if (document == null || document.segments.isEmpty) return null;

    final heading = await _episodeHeading(info, source, workId, ep);
    final title = info.title ?? heading;
    // 閲覧履歴の「最後に読んだ話」を進める（あとで画面で続きから読めるように）
    unawaited(
      repository.addToHistory(
        source: source,
        workId: workId,
        title: info.title ?? '',
        writer: info.writer ?? '',
        lastEpisode: ep,
      ),
    );
    final currentEp = ep;
    final controller = ReadAloudController(
      document: document,
      mediaTitle: title,
      mediaSubtitle: heading,
      dictionaryScope: ReadingDictionary.webScope(source.name, workId),
      // 作品の切り替わりなら「次は、〇〇」。話の切り替わりなら話の題
      announcement: announcement ?? (episode == null ? null : heading),
      onCompleted: () => unawaited(_nextEpisode(entry, currentEp, total)),
    );
    _startIndexOf[controller] = 0;
    return PlaylistNowPlaying(
      entry: entry,
      title: title,
      subtitle: heading,
      controller: controller,
    );
  }

  Future<void> _nextEpisode(
    WebPlaylistEntry entry,
    int finishedEpisode,
    int total,
  ) async {
    if (finishedEpisode >= total) {
      await _advanceFrom(entry);
      return;
    }
    final generation = ++_generation;
    try {
      final next = await _prepareWeb(entry, null, finishedEpisode + 1);
      if (generation != _generation) {
        next?.controller.dispose();
        return;
      }
      if (next == null) {
        await _advanceFrom(entry);
        return;
      }
      await _start(next);
    } on Object catch (e) {
      debugPrint('連続再生: 第${finishedEpisode + 1}話を読めませんでした: $e');
      if (generation == _generation) await _advanceFrom(entry);
    }
  }

  // 「第N話 サブタイトル」（短編なら作品名）
  Future<String> _episodeHeading(
    NovelInfo info,
    NovelSource source,
    String workId,
    int ep,
  ) async {
    if (info.novelType == 2) return info.title ?? '';
    Episode? episode;
    try {
      final episodes = await ref.read(
        episodeListProvider(source, workId, ((ep - 1) ~/ 100) + 1).future,
      );
      episode = episodes.where((e) => e.index == ep).firstOrNull;
    } on Object {
      // 目次が読めなくても読み上げは続ける
    }
    final subtitle = episode?.subtitle;
    return subtitle == null || subtitle.isEmpty
        ? '第$ep話'
        : '第$ep話 $subtitle';
  }
}
