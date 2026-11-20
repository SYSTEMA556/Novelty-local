# Novelty-local

[![APK](https://img.shields.io/badge/APK-apk--latest-084887)](https://github.com/SYSTEMA556/Novelty-local/releases/tag/apk-latest)
[![CI](https://github.com/SYSTEMA556/Novelty-local/actions/workflows/ci.yml/badge.svg?branch=feat%2Flocal-text-file)](https://github.com/SYSTEMA556/Novelty-local/actions/workflows/ci.yml)
[![Upstream](https://img.shields.io/badge/upstream-L4Ph%2FNovelty-555)](https://github.com/L4Ph/Novelty)

「小説家になろう」「カクヨム」のビューアー [**Novelty**](https://github.com/L4Ph/Novelty) の、個人用の非公式フォークです。
元の機能はそのままに、**スマホの中のテキストファイルを本棚に並べて読む機能**と、**VOICEVOX での朗読**を足しています。

> [!IMPORTANT]
> - 元の Novelty とは別物です。このフォークの不具合を元のリポジトリに報告しないでください。
> - 元のリポジトリへ Pull Request は送りません。
> - Android 向けにだけ作って確かめています（arm64、Xiaomi の端末で動作を確認）。
> - 開発ブランチは `feat/local-text-file` です。

## 足した機能

| 分類 | 内容 |
|---|---|
| ローカル本棚 | .txt の取り込み（ファイル・フォルダ）、フォルダの再スキャン、作者・作品名の自動推定、あいうえお順・作者別の一覧、しおり |
| 文字コード | UTF-8 に加えて、Shift_JIS・EUC-JP・BOM の無い UTF-16 を判別して読む。元のファイルの UTF-8 化・本文の掃除・表記ゆれは選べる |
| 読み上げ | 端末の音声合成と VOICEVOX（四国めたん・ずんだもん・九州そら・東北きりたん）。台詞・地の文・感情を推定して読み分ける |
| 運転中 | 通知・ハンドルやイヤホンのボタン・Android Auto で操作、ナビや電話の間は一時停止、画面を消しても継続、作品をまたぐ連続再生 |
| 読書画面 | 位置バーとシークバー、話の途中の位置の記憶（Web 小説も）、色調・タップ領域の設定 |

## ドキュメント

| 読む人 | 文書 |
|---|---|
| 使う人 | [docs/novelty-local/README.md](docs/novelty-local/README.md) ― 機能・使い方・しくみを例え話つきで |
| 開発する人 | [docs/novelty-local/ARCHITECTURE.md](docs/novelty-local/ARCHITECTURE.md) ― モジュールの責務・保存形式・スレッド・CI |
| 設計の判断 | [docs/adr/](docs/adr/) ― 0001〜0002 は元の Novelty、0003 以降がこのフォーク |
| 用語 | [CONTEXT.md](CONTEXT.md) |
| ライセンス | [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) ― 同梱している外部のソフトウェア・データ |

## 入れ方

[リリース `apk-latest`](https://github.com/SYSTEMA556/Novelty-local/releases/tag/apk-latest) から `novelty-local.apk`（約 450MB）を落として入れます。
署名の鍵は固定しているので、新しい版を上から入れても本棚・しおり・設定は残ります。
元の Novelty（公式版）とは署名が違うため、上書きはできません。

## ビルド

```bash
git clone -b feat/local-text-file https://github.com/SYSTEMA556/Novelty-local.git
cd Novelty-local
flutter pub get
dart run build_runner build -d
flutter build apk --release
```

- VOICEVOX の部品はリポジトリに入れていません。CI が公式の配布物から取ってきて置きます。
  手元でビルドするときは、[ci.yml](.github/workflows/ci.yml) の「Fetch VOICEVOX」と同じように置いてください。

  | 部品 | 置き場所 |
  |---|---|
  | コア（Maven パッケージ） | `android/voicevox-maven/` |
  | ONNX Runtime | `android/app/src/main/jniLibs/arm64-v8a/` |
  | 辞書・声のモデル | `android/app/src/main/assets/voicevox/` |

  コアが無いと Kotlin のコンパイルが通りません。
- release 署名は `android/app/key.properties` を読みます。CI では Secret `ANDROID_KEYSTORE_BASE64` から作ります。
- `flutter analyze` は info も含めて 0 件、が CI の条件です（very_good_analysis）。

## 元の Novelty から増えた権限

| 権限 | 理由 |
|---|---|
| すべてのファイルへのアクセス（`MANAGE_EXTERNAL_STORAGE`） | フォルダを選んで .txt をまとめて取り込む・再スキャンする |
| フォアグラウンドサービス（メディア再生）・`WAKE_LOCK` | 画面を消しても読み上げを続ける |

カメラ・位置情報・連絡先・マイクは使いません。

## クレジットとライセンス

- アプリ本体は元の Novelty と同じ [PolyForm Noncommercial 1.0.0](LICENSE)、`packages/` は [MIT](packages/LICENSE) です。非商用に限ります。
- 読み上げの声：**VOICEVOX:四国めたん・VOICEVOX:ずんだもん・VOICEVOX:九州そら・VOICEVOX:東北きりたん**
- 漢字の読み：JMdict（[EDRDG](https://www.edrdg.org/)、CC BY-SA 4.0）
- そのほかは [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) を見てください。
- このフォークの追加・変更は、利用者の指示と確認のもとで AI の Claude（Anthropic）が書いています（コミットの `Co-Authored-By` 行）。

---

## 元の Novelty について

> 以下は元のリポジトリ [L4Ph/Novelty](https://github.com/L4Ph/Novelty) の説明です（見出しの深さだけ変えています）。
> 「最小限の権限」と「開発環境のセットアップ」は元の Novelty についての記述で、このフォークでは上の説明が優先します。

[![Release](https://img.shields.io/badge/Download-%E3%83%80%E3%82%A6%E3%83%B3%E3%83%AD%E3%83%BC%E3%83%89-084887)](https://github.com/L4Ph/Novelty/releases/latest)
[![Beta](https://img.shields.io/badge/Beta-%E5%8F%82%E5%8A%A0-0e34a0)](https://groups.google.com/g/novelty-app)

**モダンで、シンプルに。そして透明性高く。**

![縦書き読書画面](https://novelty.l4ph.moe/tategaki.webp)

「小説家になろう」「カクヨム」の作品を読むためにゼロから再設計された、Flutter製のクロスプラットフォーム小説ビューアーです。

### 概要

Noveltyは、最高の読書体験を提供するために開発された、**小説家になろう・カクヨムに対応**したクライアントアプリケーションです。
**オフラインファースト**の設計思想に基づき、ネットワーク接続が不安定な環境や圏外でも、保存されたライブラリからストレスなく読書を継続できます。

サイト抽象レイヤー（`NovelSource` / `NovelSite`）により、なろう・カクヨムを同じ操作感で利用でき、
将来のプロバイダ追加にも対応しています（[docs/architecture/multi_provider.md](docs/architecture/multi_provider.md)）。

複雑な要求や機能を削ぎ落とし、読書に集中できるシンプルさを追求しながら、現代の読書スタイルに求められる必須機能を備えています。

### 主な機能

### 読書体験の追求
*   **縦書き・横書きの完全対応**: 日本語の小説に最適な縦書き表示をサポートしています。好みに合わせて横書きへの切り替えも瞬時に行えます。
*   **詳細なカスタマイズ**: フォントサイズ、フォントの種類、行間などを自由に調整し、自分だけの最適な読書環境を構築できます。

### 快適な作品探索
*   **ランキング機能**: なろう・カクヨムの**プロバイダ切替**に対応。各サイトのランキング種別（日間・週間・月間など）から人気の作品を簡単に見つけられます。
*   **高度な検索**: キーワード、ジャンル、文字数、完結区分など、詳細な条件を指定して作品を検索可能です（なろう）。カクヨムはキーワード検索に対応しています。

### ライブラリとデータ管理
*   **オフライン閲覧**: 徹底したオフラインファースト設計により、作品を一度ダウンロードすれば、通信環境に依存せずいつでもどこでも読書を楽しめます。
*   **閲覧履歴の自動同期**: 読書の進捗は自動的に記録され、どこまで読んだかを忘れることはありません。
*   **バックアップと復元**: ライブラリや履歴データをファイルとしてエクスポート・インポートする機能を搭載しており、機種変更時も安心です。

### プライバシーとセキュリティ
*   **最小限の権限**: ユーザーのプライバシーを最大限尊重するため、**アプリケーションデータのバックアップおよび復元に必要なファイルアクセス権限以外、一切のデバイス権限（カメラ、位置情報、連絡先、マイクなど）を要求しません。**

### 技術スタック

本アプリケーションは、モダンで堅牢な技術選択に基づき開発されています。

*   **Framework**: Flutter
*   **Language**: Dart
*   **State Management**: Riverpod
*   **Routing**: GoRouter
*   **Database**: Drift (SQLite)
*   **API Client**: Dio
*   **CI/CD**: GitHub Actions

### 開発環境のセットアップ

### 前提条件
*   Flutter (stable channel)

### インストール手順

1.  **リポジトリのクローン**
    ```bash
    git clone https://github.com/L4Ph/Novelty.git
    cd Novelty
    ```


2.  **依存関係のインストール**
    ```bash
    flutter pub get
    ```

3.  **コード生成の実行**
    ```bash
    dart run build_runner build -d
    ```

### アプリケーションの実行

```bash
flutter run
```

### APIとドキュメント

本プロジェクトが利用するAPIや、データ構造に関するドキュメントはリポジトリ内に含まれています。

*   なろう小説API (小説情報・ランキング)
*   なろう小説HTML構造 (トップページ・本文ページ)

### コントリビューション

バグ報告、機能提案、プルリクエストなど、あらゆるコントリビューションを歓迎します。

### ライセンス

*   **アプリケーション本体**: [PolyForm Noncommercial 1.0.0](./LICENSE)
    *   非商用利用に限り、自由な再配布、改変を許可します。
*   **packagesディレクトリ**: [MIT License](./packages/LICENSE)
    *   商用利用を含む自由な利用が可能です。

---

*「小説家になろう」は株式会社ヒナプロジェクトの登録商標です。本アプリは非公式のクライアントアプリです。*
