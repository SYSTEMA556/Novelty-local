package moe.l4ph.novelty

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    // VOICEVOX の読み上げ（フォークで追加）
    private var voicevox: VoicevoxBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        voicevox = VoicevoxBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        voicevox?.dispose()
        voicevox = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
