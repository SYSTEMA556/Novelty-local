/// 読み上げを OS のメディアセッションにつなぐ（フォークで追加）。
///
/// audio_service（通知・ボタン・Android Auto・フォアグラウンドサービス）と
/// audio_session（音のフォーカス・Bluetooth の切断）を [ReadAloudRemote] に配線する。
/// - `androidStopForegroundOnPause: false`：一時停止中もサービスを保ち、
///   画面が消えたままでも割り込みのあとに再開できるようにする。
/// - 話・作品の切り替わりでは、45秒間「再生中」のまま待つ。いったん idle に
///   すると、画面が消えている間はフォアグラウンドサービスを再開できないため。
/// - 初期化に失敗しても読み上げ自体は動く（通知などが出ないだけ）。
library;

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:novelty/read_aloud/read_aloud_controller.dart';
import 'package:novelty/read_aloud/read_aloud_remote.dart';

/// 読み上げを、スマホの「音楽を流しているアプリ」として扱わせる（フォークで追加）。
///
/// これで次のことができるようになる。
/// - 通知・ロック画面に題名と操作ボタンを出す
/// - ハンドルのボタン・Bluetooth イヤホンのボタンで操作する
/// - 車の画面（Android Auto）に今読んでいる作品を出す
/// - ナビの案内・電話の間は止めて、終わったら続きを読む
/// - Bluetooth が切れたら止める
/// - 画面を消してもアプリが眠らされないようにする
///
/// たとえるなら、読み上げに「カーオーディオにつながる名札」を付ける係。
class ReadAloudMedia {
  ReadAloudMedia._();

  static final _remote = ReadAloudRemote();
  static _ReadAloudHandler? _handler;
  static AudioSession? _session;
  static Timer? _idleTimer;
  static bool _initStarted = false;

  // 読み終えてから次の話・作品が始まるまで、通知を出したままにする長さ。
  // 途中で消すと、画面を消している間は通知を出し直せないことがあるため。
  static const _handoffGrace = Duration(seconds: 45);

  /// アプリの起動時に1回呼ぶ。失敗しても読み上げ自体は使える。
  static Future<void> init() async {
    if (_initStarted) return;
    _initStarted = true;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      session.interruptionEventStream.listen(_onInterruption);
      session.becomingNoisyEventStream.listen(
        (_) => unawaited(_remote.becameNoisy()),
      );
      _session = session;
      _handler = await AudioService.init(
        builder: () => _ReadAloudHandler(_remote),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'moe.l4ph.novelty.read_aloud',
          androidNotificationChannelName: '読み上げ',
          // 一時停止中（ナビの案内中など）も通知を残し、アプリを眠らせない
          androidStopForegroundOnPause: false,
          fastForwardInterval: Duration(seconds: 30),
          rewindInterval: Duration(seconds: 30),
        ),
      );
      ReadAloudController.onStartedPlaying = _attach;
      ReadAloudController.onDisposed = _detach;
    } on Object catch (e) {
      debugPrint('読み上げの通知・車との連携を使えません: $e');
    }
  }

  static void _onInterruption(AudioInterruptionEvent event) {
    if (event.begin) {
      // ナビの案内（duck）・電話（pause）は終われば戻る。
      // 他のアプリが音楽を流し始めた（unknown）ときは戻らない
      unawaited(
        _remote.interruptionBegan(
          mayResume: event.type != AudioInterruptionType.unknown,
        ),
      );
    } else {
      unawaited(_remote.interruptionEnded());
    }
  }

  static void _attach(ReadAloudController controller) {
    _idleTimer?.cancel();
    final previous = _remote.controller;
    if (!identical(previous, controller)) {
      previous?.removeListener(_publish);
      _remote.attach(controller);
      controller.addListener(_publish);
    }
    // 他のアプリから音を取り戻す（ナビ・電話のあとに知らせてもらうため）
    unawaited(_session?.setActive(true).catchError((Object _) => false));
    _handler?.mediaItem.add(
      MediaItem(
        id: 'now-reading',
        title: controller.mediaTitle ?? '読み上げ',
        artist: controller.mediaSubtitle,
        album: 'Novelty',
      ),
    );
    _publish();
  }

  static void _detach(ReadAloudController controller) {
    controller.removeListener(_publish);
    final wasFinished = controller.finished;
    if (!_remote.detach(controller)) return;
    // 読み終えて次へ進むところなら、しばらく通知を残して待つ
    _scheduleIdle(wasFinished ? _handoffGrace : Duration.zero);
  }

  static void _publish() {
    final handler = _handler;
    final c = _remote.controller;
    if (handler == null || c == null) return;
    // 読み終えた直後は「次を準備中」として、再生中の扱いのままにする
    final playing = c.isPlaying || c.finished;
    handler.playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.rewind,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.fastForward,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.play,
          MediaAction.pause,
          MediaAction.playPause,
          MediaAction.stop,
          MediaAction.rewind,
          MediaAction.fastForward,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        // 通知を畳んだときは「戻る・再生/一時停止・進む」を出す
        androidCompactActionIndices: const [1, 2, 3],
        processingState: c.finished
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready,
        playing: playing,
      ),
    );
    if (c.status == ReadAloudStatus.stopped && !c.finished) {
      // 停止ボタンで止めたら通知を片付ける
      _scheduleIdle(const Duration(seconds: 2));
    } else if (c.finished) {
      _scheduleIdle(_handoffGrace);
    } else {
      _idleTimer?.cancel();
    }
  }

  static void _scheduleIdle(Duration delay) {
    _idleTimer?.cancel();
    _idleTimer = Timer(delay, () {
      final c = _remote.controller;
      if (c != null && c.isActive) return;
      _handler?.playbackState.add(PlaybackState());
      unawaited(_session?.setActive(false).catchError((Object _) => false));
    });
  }
}

/// 通知・ボタン・車の画面からの操作を受け取る。
class _ReadAloudHandler extends BaseAudioHandler {
  _ReadAloudHandler(this._remote);

  final ReadAloudRemote _remote;

  @override
  Future<void> play() => _remote.play();

  @override
  Future<void> pause() => _remote.pause();

  @override
  Future<void> stop() => _remote.stop();

  @override
  Future<void> skipToNext() => _remote.next();

  @override
  Future<void> skipToPrevious() => _remote.previous();

  @override
  Future<void> rewind() => _remote.rewind();

  @override
  Future<void> fastForward() => _remote.fastForward();

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.media:
        await _remote.togglePlay();
      case MediaButton.next:
        await _remote.next();
      case MediaButton.previous:
        await _remote.previous();
    }
  }

  // 車の画面の一覧には、今読んでいる作品だけを出す
  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    final item = mediaItem.value;
    if (parentMediaId != AudioService.browsableRootId || item == null) {
      return const [];
    }
    return [item.copyWith(playable: true)];
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) => _remote.play();
}
