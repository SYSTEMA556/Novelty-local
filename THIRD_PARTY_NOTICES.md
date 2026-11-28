# サードパーティのライセンス表記（Novelty-local）

このフォーク（Novelty-local）で追加した外部のソフトウェア・データのライセンスと利用規約をまとめます。
Novelty 本体のライセンスは [LICENSE](LICENSE)（PolyForm Noncommercial License 1.0.0）を見てください。

## クレジット

読み上げの声に VOICEVOX を使用しています。

- **VOICEVOX:四国めたん**
- **VOICEVOX:ずんだもん**
- **VOICEVOX:春日部つむぎ**
- **VOICEVOX:ナースロボ＿タイプＴ**
- **VOICEVOX:中部つるぎ**（追加したとき）
- **VOICEVOX:暁記ミタマ**（追加したとき）
- **VOICEVOX:里石ユカ（つぼみ）**（追加したとき）
- **VOICEVOX:九州そら**（追加したとき）
- **VOICEVOX:東北きりたん**（追加したとき）

アプリ内では、閲覧設定の声の選択肢（「VOICEVOX:四国めたん」など）と、
「ライセンス」画面にも表記しています。

## リポジトリと APK の関係

VOICEVOX の配布物（コア・ONNX Runtime・音声モデル・Open JTalk 辞書）は**このリポジトリには含めていません**。
GitHub Actions（`.github/workflows/ci.yml` の「Fetch VOICEVOX」）がビルドのたびに公式の配布元から取得し、
APK に同梱します。同梱しているものは次のとおりです。

| 名前 | 版 | 配布元 | ライセンス・規約 |
|---|---|---|---|
| VOICEVOX CORE（Android 版） | 0.17.1 | [VOICEVOX/voicevox_core](https://github.com/VOICEVOX/voicevox_core) | MIT License |
| VOICEVOX ONNX Runtime（android-arm64） | 1.23.2 | [VOICEVOX/onnxruntime-builder](https://github.com/VOICEVOX/onnxruntime-builder) | VOICEVOX ONNX Runtime 利用規約（ONNX Runtime は MIT License） |
| VOICEVOX 音声モデル（0.vvm・11.vvm） | 0.17.1 | [VOICEVOX/voicevox_vvm](https://github.com/VOICEVOX/voicevox_vvm) | VOICEVOX 音声モデル利用規約・各音声ライブラリの規約 |
| Open JTalk 辞書（open_jtalk_dic_utf_8-1.11） | 1.11 | [r9y9/open_jtalk](https://github.com/r9y9/open_jtalk) | 修正 BSD ライセンス |

各規約は、次の点を満たして利用しています。

- 「アプリケーションに組み込んで再配布することができます」（音声モデル・ONNX Runtime 利用規約）
- 「VOICEVOX を利用したことがわかるクレジット表記」（上記のクレジット）
- 作成した音声の利用は、各音声ライブラリの規約に従う（下の「各音声ライブラリ」）

同梱のモデルには、選べる声のほかに同じファイルに入っている声（雨晴はう・櫻歌ミコ）も含まれますが、
アプリでは選べるようにしていません。

### あとから追加する声

次のモデルは APK に入れず、アプリの閲覧設定「声を追加する」から、利用者の端末が
公式の配布元（`https://github.com/VOICEVOX/voicevox_vvm/releases/download/0.17.1/<番号>.vvm`）
へ直接取りに行きます。届いたファイルは SHA-256 で公式のものと照合してから使います
（一覧と照合値は `lib/read_aloud/voicevox_models.dart`）。

| ファイル | 使う声 |
|---|---|
| 18.vvm | 中部つるぎ |
| 24.vvm | 暁記ミタマ・里石ユカ（同じファイルに夜語トバリも入っていますが選べません） |
| 5.vvm | 四国めたん・ずんだもん・九州そらのささやき・ヒソヒソ |
| 15.vvm | ずんだもんのなみだめ（同じファイルの青山龍星・もち子さん・小夜/SAYO は選べません） |
| 2.vvm | 九州そら |
| 21.vvm | 東北きりたん（同じファイルの東北ずん子・東北イタコ・猫使アル・猫使ビィは選べません） |

以前の版で同梱していた 2.vvm・5.vvm・15.vvm・21.vvm は、更新後も端末に残っていれば
そのまま「追加済み」として使い続けます。

---

## VOICEVOX 音声モデル 利用規約

（[VOICEVOX/voicevox_vvm の TERMS.txt](https://github.com/VOICEVOX/voicevox_vvm/blob/main/TERMS.txt) より、本アプリで使う部分）

### VOICEVOX 音声モデル 利用規約

#### 許諾内容

1. 商用・非商用問わず利用することができます
2. アプリケーションに組み込んで再配布することができます
3. 作成された音声を利用する際は、各音声ライブラリの規約に従ってください
4. 作成された音声の利用を他者に許諾する際は、当該他者に対し本許諾内容の 3 及び 4 の遵守を義務付けてください

#### 禁止事項

- 逆コンパイル・リバースエンジニアリング及びこれらの方法の公開すること
- 製作者または第三者に不利益をもたらす行為
- 公序良俗に反する行為

#### 免責事項

本ソフトウェアにより生じた損害・不利益について、製作者は一切の責任を負いません。

#### その他

ご利用の際は VOICEVOX を利用したことがわかるクレジット表記が必要です。

#### 四国めたん

四国めたんの音声ライブラリを用いて生成した音声は、
「VOICEVOX:四国めたん」とクレジットを記載すれば、商用・非商用で利用可能です。

利用規約の詳細は以下をご確認ください。
https://zunko.jp/con_ongen_kiyaku.html

#### ずんだもん

ずんだもんの音声ライブラリを用いて生成した音声は、
「VOICEVOX:ずんだもん」とクレジットを記載すれば、商用・非商用で利用可能です。

利用規約の詳細は以下をご確認ください。
https://zunko.jp/con_ongen_kiyaku.html

#### 春日部つむぎ

春日部つむぎの音声ライブラリを用いて生成した音声は、
「VOICEVOX:春日部つむぎ」とクレジットを記載すれば、商用・非商用で利用可能です。

利用規約の詳細は以下をご確認ください。
https://tsumugi-official.studio.site/rule

#### ナースロボ＿タイプＴ

ナースロボ＿タイプＴの音声ライブラリを用いて生成した音声は、
「VOICEVOX:ナースロボ＿タイプＴ」とクレジットを記載すれば、商用・非商用で利用可能です。

利用規約の詳細は以下をご確認ください。
https://www.krnr.top/rules

#### 中部つるぎ

中部つるぎの音声ライブラリを用いて生成した音声は、
「VOICEVOX:中部つるぎ」とクレジットを記載すれば、商用・非商用で利用可能です。

利用規約の詳細は以下をご確認ください。
https://zunko.jp/con_ongen_kiyaku.html

#### 暁記ミタマ

暁記ミタマの音声ライブラリを用いて生成した音声は、
「VOICEVOX:暁記ミタマ」とクレジットを記載すれば、商用・非商用で利用可能です。

利用規約の詳細は以下をご確認ください。
https://yogataritobari.studio.site/#rules

#### 里石ユカ

里石ユカ（つぼみ）の音声ライブラリを用いて生成した音声は、
「VOICEVOX:里石ユカ（つぼみ）」とクレジットを記載すれば、商用・非商用で利用可能です。

利用規約の詳細は以下をご確認ください。
https://satoishiyuka.wixsite.com/satoishi/kiyaku

#### 九州そら

九州そらの音声ライブラリを用いて生成した音声は、
「VOICEVOX:九州そら」とクレジットを記載すれば、商用・非商用で利用可能です。

利用規約の詳細は以下をご確認ください。
https://zunko.jp/con_ongen_kiyaku.html

#### 東北きりたん

東北きりたんの音声ライブラリを用いて生成した音声は、
「VOICEVOX:東北きりたん」とクレジットを記載すれば、商用・非商用で利用可能です。

利用規約の詳細は以下をご確認ください。
https://zunko.jp/con_ongen_kiyaku.html

---

## VOICEVOX ONNX Runtime 利用規約

（[VOICEVOX/onnxruntime-builder](https://github.com/VOICEVOX/onnxruntime-builder) の voicevox_onnxruntime-1.23.2 リリースより）

### VOICEVOX ONNX Runtime 利用規約

#### 許諾内容

1. 商用・非商用問わず利用することができます
2. アプリケーションに組み込んで再配布することができます
3. 作成された音声を利用する際は、各音声ライブラリの規約に従ってください
4. 作成された音声の利用を他者に許諾する際は、当該他者に対し本許諾内容の 3 及び 4 の遵守を義務付けてください

#### 禁止事項

- 逆コンパイル・リバースエンジニアリング及びこれらの方法の公開すること
- 製作者または第三者に不利益をもたらす行為
- 公序良俗に反する行為

#### 免責事項

本ソフトウェアにより生じた損害・不利益について、製作者は一切の責任を負いません。

#### その他

ご利用の際は VOICEVOX を利用したことがわかるクレジット表記が必要です。

---

## VOICEVOX CORE

```
Copyright (c) 2021 Hiroshiba Kazuyuki

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

---

## ONNX Runtime

VOICEVOX ONNX Runtime は [microsoft/onnxruntime](https://github.com/microsoft/onnxruntime) をもとにビルドされています。

```
MIT License

Copyright (c) Microsoft Corporation

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Open JTalk

```
/* ----------------------------------------------------------------- */
/*           The Japanese TTS System "Open JTalk"                    */
/*           developed by HTS Working Group                          */
/*           http://open-jtalk.sourceforge.net/                      */
/* ----------------------------------------------------------------- */
/*                                                                   */
/*  Copyright (c) 2008-2016  Nagoya Institute of Technology          */
/*                           Department of Computer Science          */
/*                                                                   */
/* All rights reserved.                                              */
/*                                                                   */
/* Redistribution and use in source and binary forms, with or        */
/* without modification, are permitted provided that the following   */
/* conditions are met:                                               */
/*                                                                   */
/* - Redistributions of source code must retain the above copyright  */
/*   notice, this list of conditions and the following disclaimer.   */
/* - Redistributions in binary form must reproduce the above         */
/*   copyright notice, this list of conditions and the following     */
/*   disclaimer in the documentation and/or other materials provided */
/*   with the distribution.                                          */
/* - Neither the name of the HTS working group nor the names of its  */
/*   contributors may be used to endorse or promote products derived */
/*   from this software without specific prior written permission.   */
/*                                                                   */
/* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND            */
/* CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,       */
/* INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF          */
/* MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE          */
/* DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS */
/* BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,          */
/* EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED   */
/* TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,     */
/* DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON */
/* ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,   */
/* OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY    */
/* OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE           */
/* POSSIBILITY OF SUCH DAMAGE.                                       */
/* ----------------------------------------------------------------- */
```

## mecab-naist-jdic（Open JTalk 辞書のもと）

```
Copyright (c) 2009, Nara Institute of Science and Technology, Japan.

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.
Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.
Neither the name of the Nara Institute of Science and Technology
(NAIST) nor the names of its contributors may be used to endorse or
promote products derived from this software without specific prior
written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Copyright (c) 2011-2017, The UniDic Consortium
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

 * Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

 * Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the
   distribution.

 * Neither the name of the UniDic Consortium nor the names of its
   contributors may be used to endorse or promote products derived
   from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

/* ----------------------------------------------------------------- */
/*           The Japanese TTS System "Open JTalk"                    */
/*           developed by HTS Working Group                          */
/*           http://open-jtalk.sourceforge.net/                      */
/* ----------------------------------------------------------------- */
/*                                                                   */
/*  Copyright (c) 2008-2016  Nagoya Institute of Technology          */
/*                           Department of Computer Science          */
/*                                                                   */
/* All rights reserved.                                              */
/*                                                                   */
/* Redistribution and use in source and binary forms, with or        */
/* without modification, are permitted provided that the following   */
/* conditions are met:                                               */
/*                                                                   */
/* - Redistributions of source code must retain the above copyright  */
/*   notice, this list of conditions and the following disclaimer.   */
/* - Redistributions in binary form must reproduce the above         */
/*   copyright notice, this list of conditions and the following     */
/*   disclaimer in the documentation and/or other materials provided */
/*   with the distribution.                                          */
/* - Neither the name of the HTS working group nor the names of its  */
/*   contributors may be used to endorse or promote products derived */
/*   from this software without specific prior written permission.   */
/*                                                                   */
/* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND            */
/* CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,       */
/* INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF          */
/* MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE          */
/* DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS */
/* BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,          */
/* EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED   */
/* TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,     */
/* DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON */
/* ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,   */
/* OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY    */
/* OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE           */
/* POSSIBILITY OF SUCH DAMAGE.                                       */
/* ----------------------------------------------------------------- */
```

---

## 読み仮名の辞書（JMdict / JMnedict / KANJIDIC2）

ローカル作品の並べ替えに使う `assets/dict/readings.tsv.gz` は、
Electronic Dictionary Research and Development Group（EDRDG）の JMdict・JMnedict・KANJIDIC2 をもとに作成しています
（作成手順：`tool/build_reading_dictionary.py`）。

These files are the property of the Electronic Dictionary Research and Development Group,
and are used in conformance with the Group's licence.
<https://www.edrdg.org/edrdg/licence.html>

Licensed under the Creative Commons Attribution-ShareAlike 4.0 International License (CC BY-SA 4.0).
<https://creativecommons.org/licenses/by-sa/4.0/>
