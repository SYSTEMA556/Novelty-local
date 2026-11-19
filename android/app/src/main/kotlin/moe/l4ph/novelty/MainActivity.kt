package moe.l4ph.novelty

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

// 読み上げを通知・車のボタンで操作できるよう、audio_service の Activity を土台にする
// （フォークで変更）。この土台では、画面を閉じてもアプリの中身（FlutterEngine）は
// 残って読み上げを続けるので、VOICEVOX も画面ではなくアプリ全体で1つを持つ。
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        if (voicevoxMessenger !== messenger) {
            voicevox?.dispose()
            voicevox = VoicevoxBridge(applicationContext, messenger)
            voicevoxMessenger = messenger
        }
    }

    // メモリが足りなくなってきたら、VOICEVOX の声のモデルを外して空ける
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= TRIM_MEMORY_RUNNING_LOW) voicevox?.trimMemory(level)
    }

    companion object {
        // VOICEVOX の読み上げ（フォークで追加）。画面を作り直しても使い回す
        private var voicevox: VoicevoxBridge? = null
        private var voicevoxMessenger: Any? = null
    }
}
