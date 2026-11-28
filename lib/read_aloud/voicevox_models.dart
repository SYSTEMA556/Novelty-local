/// VOICEVOX の声のモデル（.vvm）の管理（フォークで追加）。
///
/// APK には 0.vvm（四国めたん・ずんだもん・春日部つむぎ）と
/// 11.vvm（ナースロボ＿タイプＴ）だけを入れ、ほかの声は設定画面から
/// 公式の配布元（GitHub の VOICEVOX/voicevox_vvm のリリース）へ取りに行く。
///
/// たとえるなら、本棚（APK）には定番の数冊だけを置き、読みたくなった本は
/// その都度、出版社の倉庫から取り寄せる仕組み。届いた本は封を確かめて
/// （SHA-256 で中身を照合して）から棚に並べる。
///
/// ダウンロードは Dart の HttpClient で行い、確かめと登録は Kotlin 側
/// （VoicevoxBridge.kt の installModel）が行う。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 声の種類の番号 → その声が入っている公式のモデルのファイル。
///
/// VOICEVOX/voicevox_vvm 0.17.1 の README の表から、このアプリで使う声だけを
/// 写したもの。
const voicevoxModelOfStyle = <int, String>{
  // 0.vvm: 四国めたん・ずんだもん・春日部つむぎ
  2: '0.vvm', 0: '0.vvm', 6: '0.vvm', 4: '0.vvm',
  3: '0.vvm', 1: '0.vvm', 7: '0.vvm', 5: '0.vvm',
  8: '0.vvm',
  // 2.vvm: 九州そら
  16: '2.vvm', 15: '2.vvm', 18: '2.vvm', 17: '2.vvm',
  // 5.vvm: 四国めたん・ずんだもん・九州そらのささやき・ヒソヒソ
  36: '5.vvm', 37: '5.vvm', 22: '5.vvm', 38: '5.vvm', 19: '5.vvm',
  // 11.vvm: ナースロボ＿タイプＴ
  47: '11.vvm', 48: '11.vvm', 49: '11.vvm', 50: '11.vvm',
  // 15.vvm: ずんだもんのヘロヘロ・なみだめ
  75: '15.vvm', 76: '15.vvm',
  // 18.vvm: 中部つるぎ
  94: '18.vvm', 95: '18.vvm', 96: '18.vvm', 97: '18.vvm', 98: '18.vvm',
  // 21.vvm: 東北きりたん
  108: '21.vvm',
  // 24.vvm: 暁記ミタマ・里石ユカ
  122: '24.vvm', 123: '24.vvm', 124: '24.vvm', 125: '24.vvm',
  126: '24.vvm',
};

/// 追加できる声のモデル。
@immutable
class VoicevoxModelPack {
  /// コンストラクタ。
  const VoicevoxModelPack({
    required this.file,
    required this.title,
    required this.description,
    required this.bytes,
    required this.sha256,
  });

  /// ファイル名（例: 18.vvm）。
  final String file;

  /// 表示名。
  final String title;

  /// 何が入っているか。
  final String description;

  /// 大きさ（バイト）。ダウンロードの進み具合と確かめに使う。
  final int bytes;

  /// 中身の SHA-256（公式の 0.17.1 のファイルを落として計算したもの）。
  final String sha256;

  /// 公式の配布元の場所。
  Uri get url => Uri.parse(
    'https://github.com/VOICEVOX/voicevox_vvm/releases/download/'
    '$voicevoxModelVersion/$file',
  );

  /// 大きさの表示（例: 62.5 MB）。
  String get sizeLabel => '${(bytes / 1000000).toStringAsFixed(1)} MB';
}

/// 声のモデルの版（APK に同梱しているコアと合わせる。ci.yml の VVM_VERSION）。
const voicevoxModelVersion = '0.17.1';

/// 設定画面から追加できる声のモデル。
const voicevoxModelPacks = [
  VoicevoxModelPack(
    file: '18.vvm',
    title: '中部つるぎ',
    description: 'ノーマル・怒り・ヒソヒソ・おどおど・絶望と敗北',
    bytes: 62519486,
    sha256:
        '33e5177ebbe1ec5829769c1017f1294641dbf22c43cd2af4896ae0738a14ed13',
  ),
  VoicevoxModelPack(
    file: '24.vvm',
    title: '暁記ミタマ・里石ユカ',
    description: 'ミタマ（ノーマル・怒り・哀しみ・ささやき）・ユカ（つぼみ）',
    bytes: 60024319,
    sha256:
        '3e62f5ce0ac345ed74c0e3bc9051cd99baaed37389e33f64195c9e0e49f34594',
  ),
  VoicevoxModelPack(
    file: '5.vvm',
    title: 'ささやき・ヒソヒソ',
    description: '四国めたん・ずんだもん・九州そらの、ささやきと心の声',
    bytes: 57611312,
    sha256:
        '67451cdbc3e473dba4d09c878903a656be9e7030cb5901155e5a51634ed8b318',
  ),
  VoicevoxModelPack(
    file: '15.vvm',
    title: 'ずんだもんの泣き声',
    description: 'ずんだもんのなみだめ（悲しみ）・ヘロヘロ',
    bytes: 67265793,
    sha256:
        'c29b0c0f8e332fcedc2a5de4b4426feb75fc9f587c314da99af8dbc964287221',
  ),
  VoicevoxModelPack(
    file: '2.vvm',
    title: '九州そら',
    description: 'ノーマル・あまあま・ツンツン',
    bytes: 59308683,
    sha256:
        '2eb9a67e3bce09a7f209eb21a56926fa94476352b6ce874c9acd8f465871a4f4',
  ),
  VoicevoxModelPack(
    file: '21.vvm',
    title: '東北きりたん',
    description: 'ノーマル',
    bytes: 63195138,
    sha256:
        'f6b937e953409a65f3d7609335a4dfd19fdd9458be27d988bdd8296034adfaf6',
  ),
];

/// ダウンロードを途中でやめたとき。
class VoicevoxDownloadCancelled implements Exception {
  @override
  String toString() => 'ダウンロードをやめました';
}

/// 入っている声のモデルの一覧と、追加・削除。
class VoicevoxModels {
  VoicevoxModels._();

  static const _channel = MethodChannel('novelty/voicevox');

  /// 入っているモデルのファイル名（同梱＋追加分）。まだ調べていなければ null。
  static final ValueNotifier<Set<String>?> installed = ValueNotifier(null);

  /// 追加したモデルのファイル名（消せるもの）。
  static final ValueNotifier<Set<String>> extra = ValueNotifier(const {});

  /// ダウンロード中のモデル → 進み具合（0〜1）。画面を離れても続ける。
  static final ValueNotifier<Map<String, double>> downloading = ValueNotifier(
    const {},
  );

  static final Set<String> _cancelled = {};
  static Future<void>? _refreshing;

  /// 入っているモデルを調べ直す（[force] でなければ一度だけ）。
  static Future<void> refresh({bool force = false}) {
    if (!force && _refreshing != null) return _refreshing!;
    return _refreshing = () async {
      try {
        _apply(await _channel.invokeMapMethod<String, Object?>('models'));
      } on Object catch (e) {
        // Android 以外・部品が無い・テスト環境では何もしない
        debugPrint('VOICEVOX のモデルを調べられませんでした: $e');
      }
    }();
  }

  static void _apply(Map<String, Object?>? info) {
    if (info == null) return;
    List<String> read(String key) =>
        (info[key] as List<Object?>? ?? const []).whereType<String>().toList();
    final added = read('extra').toSet();
    extra.value = added;
    installed.value = {...read('bundled'), ...added};
  }

  static void _setProgress(String file, double? value) {
    final next = Map.of(downloading.value);
    if (value == null) {
      next.remove(file);
    } else {
      next[file] = value;
    }
    downloading.value = next;
  }

  /// [pack] を公式の配布元から落として入れる。
  static Future<void> download(VoicevoxModelPack pack) async {
    if (downloading.value.containsKey(pack.file)) return;
    _cancelled.remove(pack.file);
    _setProgress(pack.file, 0);
    final client = HttpClient();
    File? part;
    try {
      final dir = await _channel.invokeMethod<String>('extraDir');
      if (dir == null) throw StateError('保存先が見つかりません');
      part = File('$dir/${pack.file}.part');
      final request = await client.getUrl(pack.url);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('配布元が ${response.statusCode} を返しました');
      }
      final sink = part.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          if (_cancelled.contains(pack.file)) throw VoicevoxDownloadCancelled();
          sink.add(chunk);
          received += chunk.length;
          _setProgress(pack.file, (received / pack.bytes).clamp(0.0, 1.0));
        }
      } finally {
        await sink.close();
      }
      if (received != pack.bytes) {
        throw const HttpException('ダウンロードが途中で切れました');
      }
      _apply(
        await _channel.invokeMapMethod<String, Object?>('installModel', {
          'path': part.path,
          'name': pack.file,
          'sha256': pack.sha256,
        }),
      );
    } finally {
      client.close(force: true);
      _setProgress(pack.file, null);
      _cancelled.remove(pack.file);
      if (part != null && part.existsSync()) {
        try {
          part.deleteSync();
        } on Object {
          // 消せなくても次のダウンロードで上書きする
        }
      }
    }
  }

  /// ダウンロードをやめる。
  static void cancel(VoicevoxModelPack pack) => _cancelled.add(pack.file);

  /// 追加した [pack] を消す。
  static Future<void> remove(VoicevoxModelPack pack) async {
    _apply(
      await _channel.invokeMapMethod<String, Object?>('removeModel', {
        'name': pack.file,
      }),
    );
  }
}
