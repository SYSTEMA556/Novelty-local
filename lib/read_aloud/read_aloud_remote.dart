/// 画面の外からの操作と割り込みを、読み上げの操作に置き換える（フォークで追加）。
///
/// 端末の API には触らない純粋な Dart で、テストで振る舞いを固定している。
/// 割り込み（ナビ・電話）で止めたときだけ、終わったら再開する。
/// ユーザー自身が止めた・他のアプリに音を取られたときは再開しない。
library;

import 'dart:async';

import 'package:novelty/read_aloud/read_aloud_controller.dart';

/// 画面の外からの読み上げ操作をまとめて受ける。
///
/// 通知・ロック画面・ハンドルやイヤホンのボタン・車の画面からの操作と、
/// ナビの案内・電話・Bluetooth の切断といった割り込みを、
/// 今読んでいる [controller] への操作に置き換える。
///
/// 端末の機能には触らないので、テストでそのまま確かめられる。
class ReadAloudRemote {
  ReadAloudController? _controller;

  // 割り込み（ナビ・電話）で止めたので、終わったら続きを読むか
  bool _resumeAfterInterruption = false;

  /// ボタン1回で戻る・進む秒数。
  static const seekSeconds = 30.0;

  /// 今つながっている読み上げ。
  ReadAloudController? get controller => _controller;

  /// 割り込みが終わるのを待っているか。
  bool get waitingForInterruption => _resumeAfterInterruption;

  /// [controller] を操作の対象にする（前の読み上げからは外れる）。
  void attach(ReadAloudController controller) {
    if (identical(_controller, controller)) return;
    _controller = controller;
    _resumeAfterInterruption = false;
  }

  /// [controller] が対象なら外す。外したら true。
  bool detach(ReadAloudController controller) {
    if (!identical(_controller, controller)) return false;
    _controller = null;
    _resumeAfterInterruption = false;
    return true;
  }

  /// 再生（一時停止・停止していた文の頭から）。
  Future<void> play() async {
    _resumeAfterInterruption = false;
    final c = _controller;
    if (c == null || c.isPlaying) return;
    await c.resume();
  }

  /// 一時停止。
  Future<void> pause() async {
    _resumeAfterInterruption = false;
    await _controller?.pause();
  }

  /// 再生と一時停止を切り替える（イヤホンのボタン1回など）。
  Future<void> togglePlay() =>
      (_controller?.isPlaying ?? false) ? pause() : play();

  /// 停止。
  Future<void> stop() async {
    _resumeAfterInterruption = false;
    await _controller?.stop();
  }

  /// 次の文へ。
  Future<void> next() async {
    await _controller?.next();
  }

  /// 前の文へ。
  Future<void> previous() async {
    await _controller?.previous();
  }

  /// 約30秒戻る（聞き逃したとき用）。
  Future<void> rewind() async {
    await _controller?.seekBySeconds(-seekSeconds);
  }

  /// 約30秒進む。
  Future<void> fastForward() async {
    await _controller?.seekBySeconds(seekSeconds);
  }

  /// ナビの案内・電話などで音を譲るとき。
  ///
  /// [mayResume] は、割り込みが終われば戻ってくる種類か
  /// （ナビ・電話は true、他の音楽アプリに切り替えたときは false）。
  Future<void> interruptionBegan({required bool mayResume}) async {
    final c = _controller;
    if (c == null || !c.isPlaying) return;
    _resumeAfterInterruption = mayResume;
    await c.pause();
  }

  /// 割り込みが終わったとき。止めたのが割り込みなら続きを読む。
  Future<void> interruptionEnded() async {
    final c = _controller;
    final shouldResume = _resumeAfterInterruption;
    _resumeAfterInterruption = false;
    if (c == null || !shouldResume) return;
    if (c.status == ReadAloudStatus.paused) await c.resume();
  }

  /// イヤホンが抜けた・車の Bluetooth が切れたとき（勝手に鳴らさないよう止める）。
  Future<void> becameNoisy() => pause();
}
