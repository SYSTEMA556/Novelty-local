package moe.l4ph.novelty

import android.util.Log

/**
 * 英単語のつづりからカタカナの読みを推測する kanalizer（VOICEVOX 製・MIT）の入口。
 *
 * 本体は Rust（native/kanalizer_jni）で、CI が libkanalizer_jni.so を作って APK に入れる。
 * .so が無いビルド（手元で Rust を入れずにビルドしたときなど）では [available] が false になり、
 * Dart 側はアルファベットを1文字ずつ読む。
 */
object Kanalizer {
    private const val TAG = "Kanalizer"

    val available: Boolean by lazy {
        runCatching { System.loadLibrary("kanalizer_jni") }
            .onFailure { Log.w(TAG, "kanalizer is not bundled", it) }
            .isSuccess
    }

    // 推測できなかった単語は空文字になる
    @JvmStatic
    private external fun convertAll(words: Array<String>): Array<String>?

    /** [words]（a〜z の小文字）をまとめて推測する。使えなければ空文字の列。 */
    @Synchronized
    fun convert(words: List<String>): List<String> {
        if (!available || words.isEmpty()) return words.map { "" }
        return runCatching { convertAll(words.toTypedArray())?.toList() }
            .onFailure { Log.w(TAG, "convert failed", it) }
            .getOrNull() ?: words.map { "" }
    }
}
