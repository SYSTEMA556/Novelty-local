/// 本棚の作品を開く画面と、連続再生（フォークで追加）。
///
/// 次の作品の読み込みと読み上げの開始は build の外（コールバック）で行う。
/// 画面が消えている間は Flutter がフレームを作らず build が走らないため、
/// build の中で読み上げを作ると、運転中などに次の作品へ進めなくなる。
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:novelty/local_library/read_aloud_playlist.dart';
import 'package:novelty/read_aloud/playlist_player.dart';
import 'package:novelty/read_aloud/read_aloud_controller.dart';
import 'package:novelty/read_aloud/speech_direction.dart';
import 'package:novelty/read_aloud/speech_document.dart';
import 'package:novelty/screens/local_text_reader_page.dart';
import 'package:novelty/utils/plain_text_novel_parser.dart';
import 'package:novelty/utils/settings_provider.dart';
import 'package:novelty/widgets/read_aloud_bar.dart';

/// ローカルライブラリの作品を開く。
///
/// [autoPlay] なら、開いたらすぐ前回の続き（無ければ最初）から読み上げる。
///
/// [pin] を渡すと、しおりの場所を開く（[readFromPin] ならそこから読み上げる）。
Future<void> openLocalWork(
  BuildContext context,
  LocalWork work, {
  bool autoPlay = false,
  PinnedBookmark? pin,
  bool readFromPin = false,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (_) => LocalWorkReaderPage(
        work: work,
        autoPlay: autoPlay,
        pin: pin,
        readFromPin: readFromPin,
      ),
    ),
  );
}

/// 読み込んだ作品（本文と、その作品の読み上げ）。
class _LoadedWork {
  const _LoadedWork(this.work, this.elements, this.readAloud);

  final LocalWork work;
  final List<NovelContentElement> elements;
  final ReadAloudController readAloud;
}

/// ローカルライブラリの作品を読み込んで表示する画面。
///
/// 本文と読書位置の読み込みが終わってから読書画面を表示し、
/// 前回の位置から再開できるようにする。
///
/// 連続再生リストに入っている作品を読み上げで最後まで読むと、
/// リストの次の作品を読み込んで続けて読む。画面を消していても進めるよう、
/// 次の作品の読み込みと読み上げの開始は画面の組み立て（build）の外で行う。
class LocalWorkReaderPage extends HookConsumerWidget {
  /// コンストラクタ。
  const LocalWorkReaderPage({
    required this.work,
    this.autoPlay = false,
    this.pin,
    this.readFromPin = false,
    super.key,
  });

  /// 開いたら移るしおり。
  final PinnedBookmark? pin;

  /// しおりの場所から読み上げるか。
  final bool readFromPin;

  /// 表示する作品。
  final LocalWork work;

  /// 開いたらすぐ読み上げるか。
  final bool autoPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = useState<_LoadedWork?>(null);
    final error = useState<Object?>(null);
    // 最後に作った読み上げ（閉じるときに片付ける）
    final latest = useRef<ReadAloudController?>(null);
    useEffect(() => () => latest.value?.dispose(), const []);

    final positions = ref.read(readingPositionsProvider.notifier);
    // 読み終えたときの処理（作り直しても最新を呼べるよう ref に入れる）
    final continueRef = useRef<void Function(LocalWork finished)?>(null);

    Future<void> load(
      LocalWork target, {
      required bool play,
      String? announcement,
    }) async {
      try {
        final store = await ref.read(localLibraryStoreProvider.future);
        // 読書位置を先に読み込んでおく（復元に必要）
        final saved = await ref.read(readingPositionsProvider.future);
        final text = await store.readText(target.id);
        final options = await ref.read(localTextOptionsProvider.future);
        // 長編でもUIが固まらないよう、本文の解析と読み上げの下ごしらえ
        // （文の分割・演出の読み取り）をまとめて別Isolateで行う
        final prepared = await prepareInBackground(text, options: options);
        final elements = prepared.elements;
        if (!context.mounted) return;
        final document = prepared.document;
        final controller = createLocalReadAloud(
          document: document,
          directions: prepared.directions,
          title: target.title,
          author: target.author,
          workId: target.id,
          positions: positions,
          announcement: announcement,
          onCompleted: () => continueRef.value?.call(target),
        );
        applyReadAloudSettings(controller, ref.read(settingsProvider).value);
        final previous = latest.value;
        latest.value = controller;
        loaded.value = _LoadedWork(target, elements, controller);
        previous?.dispose();
        // しおりから「ここから読み上げ」で開いたとき
        final fromPin = pin;
        if (readFromPin && fromPin != null && target.id == work.id) {
          await controller.playFrom(document.segmentIndexAt(fromPin.offset));
          return;
        }
        if (!play || document.segments.isEmpty) return;
        // 前回の続きから。最後まで読んだ作品なら最初から
        final ttsOffset = saved[target.id]?.ttsOffset;
        var start = ttsOffset == null ? 0 : document.segmentIndexAt(ttsOffset);
        if (start >= document.segments.length - 1) start = 0;
        await controller.playFrom(start);
      } on Object catch (e) {
        if (context.mounted) error.value = e;
      }
    }

    // 連続再生リストに入っている作品なら、次の作品（ローカル・Web 小説の
    // どちらでも）を連続再生の係に渡して続ける。画面は今の作品のまま
    continueRef.value = (finished) {
      unawaited(() async {
        final playlist = await ref.read(readAloudPlaylistProvider.future);
        if (nextInPlaylist(playlist, finished.id) == null) return;
        await ref
            .read(playlistPlayerProvider.notifier)
            .continueAfter(LocalPlaylistEntry(finished.id));
      }());
    };

    useEffect(() {
      unawaited(load(work, play: autoPlay));
      return null;
    }, [work.id]);

    final current = loaded.value;
    if (error.value case final e?) {
      return Scaffold(
        appBar: AppBar(title: Text(current?.work.title ?? work.title)),
        body: Center(child: Text('読み込めませんでした: $e')),
      );
    }
    if (current == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return LocalTextReaderPage(
      // 作品が替わったら、しおり・表示位置を新しく作り直す
      key: ValueKey(current.work.id),
      title: current.work.title,
      elements: current.elements,
      workId: current.work.id,
      sharedReadAloud: current.readAloud,
      // しおりから開いたときは、その場所へ移る（最初の作品だけ）
      initialFraction: current.work.id == work.id ? pin?.fraction : null,
    );
  }
}

/// 本文を別Isolateで解析する。
///
/// Isolateへ渡すクロージャが画面の状態（ref や context）を
/// 巻き込まないよう、引数だけを受け取るトップレベル関数にしている。
///
/// [options] で、本文の掃除と表記ゆれをそろえるかを決める。
Future<List<NovelContentElement>> parseInBackground(
  String text, {
  LocalTextOptions options = const LocalTextOptions(),
}) {
  final clean = options.cleanMarkup;
  final unifyWidth = options.unifyWidth;
  final removeOcrNoise = options.removeOcrNoise;
  return Isolate.run(
    () => PlainTextNovelParser.parse(
      text,
      clean: clean,
      unifyWidth: unifyWidth,
      removeOcrNoise: removeOcrNoise,
    ),
  );
}

/// 本文の解析と、読み上げの下ごしらえの結果。
typedef PreparedText = ({
  List<NovelContentElement> elements,
  SpeechDocument document,
  List<SpeechDirection> directions,
});

/// 本文の解析・文の分割・演出の読み取りを、まとめて別Isolateで行う。
///
/// 数万文の長編では、文の分割と演出の読み取りだけでも画面が一瞬固まる
/// 重さになるため、本文の解析と一緒に裏で済ませる。
Future<PreparedText> prepareInBackground(
  String text, {
  LocalTextOptions options = const LocalTextOptions(),
}) {
  final clean = options.cleanMarkup;
  final unifyWidth = options.unifyWidth;
  final removeOcrNoise = options.removeOcrNoise;
  return Isolate.run(() {
    final elements = PlainTextNovelParser.parse(
      text,
      clean: clean,
      unifyWidth: unifyWidth,
      removeOcrNoise: removeOcrNoise,
    );
    final document = SpeechDocument.fromElements(elements);
    return (
      elements: elements,
      document: document,
      directions: SpeechDirector.direct(document),
    );
  });
}
