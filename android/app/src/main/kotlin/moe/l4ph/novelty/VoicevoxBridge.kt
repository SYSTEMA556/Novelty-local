package moe.l4ph.novelty

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import jp.hiroshiba.voicevoxcore.blocking.Onnxruntime
import jp.hiroshiba.voicevoxcore.blocking.OpenJtalk
import jp.hiroshiba.voicevoxcore.blocking.Synthesizer
import jp.hiroshiba.voicevoxcore.blocking.VoiceModelFile
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.zip.ZipInputStream

/**
 * VOICEVOX（端末の中で声を作る音声合成）と Flutter をつなぐ橋渡し。
 *
 * - 声の部品（辞書・声のモデル）は APK の assets/voicevox に同梱し、
 *   初回だけアプリの保存領域へ展開する（コアはファイルの場所を指定して読むため）
 * - 声を作る処理は重いので専用のスレッドで1つずつ行い、
 *   次に読む文を先に作っておく（先読み）ことで文と文の間の待ちを減らす
 * - 作った声（WAV）は MediaPlayer で鳴らし、鳴り終わったら Flutter に知らせる
 */
class VoicevoxBridge(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL).also {
        it.setMethodCallHandler(this)
    }
    private val main = Handler(Looper.getMainLooper())

    // 声を作る専用スレッド（コアは1つずつ使う）
    private val synthesisThread: ExecutorService = Executors.newSingleThreadExecutor()

    // 結果を待つためのスレッド（メインスレッドを止めないため）
    private val waiters: ExecutorService = Executors.newCachedThreadPool()

    @Volatile private var synthesizer: Synthesizer? = null
    private var prepareFuture: Future<*>? = null

    // 作った声（または作っている途中）を、文と声の設定ごとに少しだけ残す
    private val cache = object : LinkedHashMap<String, Future<File>>(8, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Future<File>>): Boolean {
            val remove = size > CACHE_SIZE
            if (remove) {
                runCatching { if (eldest.value.isDone) eldest.value.get().delete() }
            }
            return remove
        }
    }

    private var player: MediaPlayer? = null
    private var playResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(
                mapOf("available" to hasBundledAssets(), "ready" to (synthesizer != null)),
            )
            "prepare" -> waitInBackground(result) { ensurePrepared(); true }
            "synthesize" -> {
                val request = SynthesisRequest.from(call)
                waitInBackground(result) { synthesize(request).get().absolutePath }
            }
            "prefetch" -> {
                val request = SynthesisRequest.from(call)
                // 準備が済んでいるときだけ先に作っておく（結果は待たない）
                if (synthesizer != null) synthesize(request)
                result.success(null)
            }
            "play" -> play(call.argument<String>("path")!!, result)
            "stop" -> {
                stopPlayback()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        stopPlayback()
        channel.setMethodCallHandler(null)
        synthesisThread.shutdownNow()
        waiters.shutdownNow()
    }

    // ---- 準備 ----

    private fun hasBundledAssets(): Boolean = runCatching {
        val files = context.assets.list(ASSET_DIR)?.toSet() ?: emptySet()
        files.contains(DICT_ZIP) && MODEL_FILES.all { files.contains(it) }
    }.getOrDefault(false)

    private fun ensurePrepared() {
        val future = synchronized(this) {
            prepareFuture ?: synthesisThread.submit { prepare() }.also { prepareFuture = it }
        }
        try {
            future.get()
        } catch (e: Exception) {
            // 失敗したら次の呼び出しでやり直せるようにする
            synchronized(this) { if (prepareFuture === future) prepareFuture = null }
            throw e
        }
    }

    private fun prepare() {
        if (synthesizer != null) return
        val root = File(context.filesDir, "voicevox").apply { mkdirs() }
        val dictDir = File(root, "dict")
        val dictMarker = File(dictDir, ".done")
        if (!dictMarker.exists()) {
            dictDir.deleteRecursively()
            dictDir.mkdirs()
            unzipAsset("$ASSET_DIR/$DICT_ZIP", dictDir)
            dictMarker.writeText("ok")
        }
        val modelFiles = MODEL_FILES.map { name ->
            val target = File(root, name)
            val expected = assetLength("$ASSET_DIR/$name")
            if (!target.exists() || (expected >= 0 && target.length() != expected)) {
                copyAsset("$ASSET_DIR/$name", target)
            }
            target
        }
        // 辞書は展開先の中のフォルダ（open_jtalk_dic_utf_8-1.11）を使う
        val dictPath = dictDir.listFiles()?.firstOrNull { it.isDirectory }?.absolutePath
            ?: dictDir.absolutePath

        val ort = Onnxruntime.loadOnce().perform()
        val synth = Synthesizer.builder(ort, OpenJtalk(dictPath))
            .cpuNumThreads(Runtime.getRuntime().availableProcessors().coerceIn(1, 8))
            .build()
        for (file in modelFiles) {
            VoiceModelFile(file.absolutePath).use { model ->
                synth.loadVoiceModel(model).perform()
            }
        }
        synthesizer = synth
        Log.i(TAG, "VOICEVOX ready")
    }

    private fun assetLength(path: String): Long = runCatching {
        context.assets.openFd(path).use { it.length }
    }.getOrDefault(-1L)

    private fun copyAsset(path: String, target: File) {
        val tmp = File(target.parentFile, target.name + ".tmp")
        context.assets.open(path).use { input ->
            tmp.outputStream().use { output -> input.copyTo(output, 1 shl 20) }
        }
        tmp.renameTo(target)
    }

    private fun unzipAsset(path: String, dir: File) {
        ZipInputStream(context.assets.open(path).buffered()).use { zip ->
            var entry = zip.nextEntry
            while (entry != null) {
                val out = File(dir, entry.name)
                // 展開先の外へ書き出さない
                if (!out.canonicalPath.startsWith(dir.canonicalPath)) {
                    throw SecurityException("bad zip entry: ${entry.name}")
                }
                if (entry.isDirectory) {
                    out.mkdirs()
                } else {
                    out.parentFile?.mkdirs()
                    out.outputStream().use { zip.copyTo(it, 1 shl 20) }
                }
                entry = zip.nextEntry
            }
        }
    }

    // ---- 声を作る ----

    private data class SynthesisRequest(
        val text: String,
        val styleId: Int,
        val speed: Double,
        val pitch: Double,
        val intonation: Double,
        val volume: Double,
    ) {
        val key: String get() = "$styleId|$speed|$pitch|$intonation|$volume|$text"

        companion object {
            fun from(call: MethodCall) = SynthesisRequest(
                text = call.argument<String>("text") ?: "",
                styleId = call.argument<Int>("styleId") ?: 2,
                speed = call.argument<Double>("speed") ?: 1.0,
                pitch = call.argument<Double>("pitch") ?: 0.0,
                intonation = call.argument<Double>("intonation") ?: 1.0,
                volume = call.argument<Double>("volume") ?: 1.0,
            )
        }
    }

    private fun synthesize(request: SynthesisRequest): Future<File> = synchronized(cache) {
        cache[request.key]?.let { return it }
        val future = synthesisThread.submit<File> {
            ensurePreparedOnSynthesisThread()
            val synth = synthesizer ?: throw IllegalStateException("VOICEVOX is not ready")
            val query = synth.createAudioQuery(request.text, request.styleId).apply {
                speedScale = request.speed
                pitchScale = request.pitch
                intonationScale = request.intonation
                volumeScale = request.volume
                prePhonemeLength = 0.05
                postPhonemeLength = 0.05
            }
            val wav = synth.synthesis(query, request.styleId).perform()
            File.createTempFile("vv", ".wav", context.cacheDir).apply { writeBytes(wav) }
        }
        cache[request.key] = future
        future
    }

    // 準備は同じスレッドで行うため、ここでは待たずにその場で行う
    private fun ensurePreparedOnSynthesisThread() {
        if (synthesizer == null) prepare()
    }

    // ---- 鳴らす ----

    private fun play(path: String, result: MethodChannel.Result) {
        stopPlayback()
        val mp = MediaPlayer()
        try {
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            mp.setDataSource(path)
            mp.setOnCompletionListener { finishPlayback(it, true) }
            mp.setOnErrorListener { p, what, extra ->
                Log.w(TAG, "playback error $what/$extra")
                finishPlayback(p, false)
                true
            }
            player = mp
            playResult = result
            mp.prepare()
            mp.start()
        } catch (e: Exception) {
            Log.w(TAG, "playback failed", e)
            mp.release()
            player = null
            playResult = null
            result.error("play", e.message, null)
        }
    }

    private fun finishPlayback(mp: MediaPlayer, completed: Boolean) {
        if (player !== mp) return
        player = null
        mp.release()
        playResult?.success(completed)
        playResult = null
    }

    private fun stopPlayback() {
        val mp = player ?: return
        runCatching { mp.stop() }
        finishPlayback(mp, false)
    }

    // ---- 補助 ----

    private fun waitInBackground(result: MethodChannel.Result, block: () -> Any?) {
        waiters.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: Throwable) {
                val cause = (e as? java.util.concurrent.ExecutionException)?.cause ?: e
                Log.w(TAG, "VOICEVOX failed", cause)
                main.post { result.error("voicevox", cause.toString(), null) }
            }
        }
    }

    companion object {
        private const val TAG = "VoicevoxBridge"
        const val CHANNEL = "novelty/voicevox"
        private const val ASSET_DIR = "voicevox"
        private const val DICT_ZIP = "open_jtalk_dic.zip"
        private const val CACHE_SIZE = 6

        // 0.vvm: 四国めたん（ノーマル・あまあま・ツンツン・セクシー）
        // 5.vvm: 四国めたん（ささやき・ヒソヒソ）
        private val MODEL_FILES = listOf("0.vvm", "5.vvm")
    }
}
