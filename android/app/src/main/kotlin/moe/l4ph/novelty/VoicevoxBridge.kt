package moe.l4ph.novelty

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.BatteryManager
import android.os.Handler
import android.os.Looper
import android.os.Process
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

    // 作り直しに使う部品（使うスレッド数を変えるときに作り直す）
    private var onnxruntime: Onnxruntime? = null
    private var openJtalk: OpenJtalk? = null
    private var builtThreads = 0

    // 声の種類の番号 → その声が入っているモデルのファイル
    private val modelOfStyle = HashMap<Int, String>()

    // 読み込み済みのモデル（ファイル → ID）。使う声のモデルだけ読み込んでメモリを節約する
    private val loadedModels = LinkedHashMap<String, java.util.UUID>()

    /**
     * パフォーマンスモード。
     * 0: 標準（4コアまで使い、先読みは1文、モデルは使うものだけ読み込む）
     * 1: 全力（全コア・優先度高め・5文先まで作り溜め・全モデルを読み込んでおく）
     * 2: 充電中だけ全力
     */
    @Volatile private var performanceMode = 0

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
                waitInBackground(result) { synthesize(request, now = true).get().absolutePath }
            }
            "prefetch" -> {
                val request = SynthesisRequest.from(call)
                val ahead = call.argument<Int>("ahead") ?: 1
                // 準備が済んでいて、今のモードで作り溜める範囲のときだけ先に作る（待たない）
                if (synthesizer != null && ahead <= prefetchDepth()) {
                    synthesize(request, now = false)
                }
                result.success(null)
            }
            "configure" -> {
                performanceMode = call.argument<Int>("performance") ?: 0
                // 準備済みなら、スレッド数の変更や全モデルの読み込みを裏で行う
                if (synthesizer != null) synthesisThread.submit { applyPerformance() }
                result.success(mapOf("fullPower" to isFullPower()))
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
            step("辞書の展開") {
                dictDir.deleteRecursively()
                dictDir.mkdirs()
                unzipAsset("$ASSET_DIR/$DICT_ZIP", dictDir)
                dictMarker.writeText("ok")
            }
        }
        val modelFiles = MODEL_FILES.map { name ->
            val target = File(root, name)
            val expected = assetLength("$ASSET_DIR/$name")
            if (!target.exists() || (expected >= 0 && target.length() != expected)) {
                step("声のモデルのコピー（$name）") { copyAsset("$ASSET_DIR/$name", target) }
            }
            target
        }
        // 辞書は展開先の中のフォルダ（open_jtalk_dic_utf_8-1.11）を使う
        val dictPath = dictDir.listFiles()?.firstOrNull { it.isDirectory }?.absolutePath
            ?: dictDir.absolutePath

        onnxruntime = step("ONNX Runtime の読み込み") { Onnxruntime.loadOnce().perform() }
        openJtalk = step("辞書の読み込み（$dictPath）") { OpenJtalk(dictPath) }
        // どの声がどのモデルに入っているかだけ先に調べる（読み込みは使うときに行う）
        for (file in modelFiles) {
            step("声のモデルの確認（${file.name}）") {
                VoiceModelFile(file.absolutePath).use { model ->
                    for (character in model.metas) {
                        for (style in character.styles) {
                            modelOfStyle[style.id] = file.absolutePath
                        }
                    }
                }
            }
        }
        step("音声合成の準備") { build(desiredThreads()) }
        if (isFullPower()) loadAllModels()
        Log.i(TAG, "VOICEVOX ready")
    }

    // 指定したスレッド数でコアを作り、読み込み済みだったモデルを読み込み直す
    private fun build(threads: Int) {
        val synth = Synthesizer.builder(onnxruntime!!, openJtalk!!)
            .cpuNumThreads(threads)
            .build()
        val paths = loadedModels.keys.toList()
        loadedModels.clear()
        synthesizer = synth
        builtThreads = threads
        for (path in paths) loadModel(path)
        Log.i(TAG, "VOICEVOX built with $threads threads")
    }

    private fun loadModel(path: String) {
        if (loadedModels.containsKey(path)) return
        val synth = synthesizer ?: return
        step("声のモデルの読み込み（${File(path).name}）") {
            VoiceModelFile(path).use { model ->
                synth.loadVoiceModel(model).perform()
                loadedModels[path] = model.id
            }
        }
    }

    private fun loadAllModels() {
        for (path in modelOfStyle.values.toSet()) loadModel(path)
    }

    // 声の種類に必要なモデルを読み込む（標準では、使わない声のモデルは外してメモリを空ける）
    private fun ensureModelFor(styleId: Int) {
        val path = modelOfStyle[styleId]
            ?: throw IllegalArgumentException("声の種類 $styleId が見つかりません")
        if (loadedModels.containsKey(path)) {
            // 最近使った順に並べ直す
            loadedModels[path]?.let { loadedModels.remove(path); loadedModels[path] = it }
            return
        }
        if (!isFullPower()) {
            while (loadedModels.size >= MAX_LOADED_MODELS_STANDARD) {
                val (oldPath, oldId) = loadedModels.entries.first().toPair()
                runCatching { synthesizer?.unloadVoiceModel(oldId) }
                loadedModels.remove(oldPath)
            }
        }
        loadModel(path)
    }

    // ---- パフォーマンスモード ----

    private fun isCharging(): Boolean = runCatching {
        val status = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            ?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
    }.getOrDefault(false)

    private fun isFullPower(): Boolean =
        performanceMode == 1 || (performanceMode == 2 && isCharging())

    private fun prefetchDepth(): Int = if (isFullPower()) PREFETCH_FULL else 1

    // 標準は4コアまで（熱と電池を抑える）、全力は全コア
    private fun desiredThreads(): Int {
        val cores = Runtime.getRuntime().availableProcessors().coerceIn(1, 16)
        return if (isFullPower()) cores else cores.coerceAtMost(4)
    }

    // 合成スレッドで呼ぶ：スレッド数が変わっていれば作り直し、全力なら全モデルを読み込む
    private fun applyPerformance() {
        if (synthesizer == null) return
        runCatching {
            val threads = desiredThreads()
            if (threads != builtThreads) build(threads)
            if (isFullPower()) loadAllModels()
        }.onFailure { Log.w(TAG, "performance change failed", it) }
    }

    // 声を作るスレッドの優先度（全力のときは音声処理並みに上げる）
    private fun applyThreadPriority() {
        val priority = if (isFullPower()) {
            Process.THREAD_PRIORITY_AUDIO
        } else {
            Process.THREAD_PRIORITY_DEFAULT
        }
        runCatching { Process.setThreadPriority(priority) }
    }

    // どの段階で失敗したかが分かるよう、段階の名前を付けて投げ直す
    private fun <T> step(name: String, block: () -> T): T = try {
        block()
    } catch (e: Throwable) {
        throw RuntimeException("$name に失敗: $e", e)
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

    /**
     * 声を作る（同じ文・同じ設定なら、できているもの・作っている途中のものを使う）。
     *
     * [now] は「今すぐ読む文」。作り溜めに無かったとき（読み始め・移動した直後）は、
     * 並んでいるだけの古い先読みを取り消して、この文を先に作る。
     */
    private fun synthesize(request: SynthesisRequest, now: Boolean): Future<File> = synchronized(cache) {
        cache[request.key]?.let { return it }
        if (now) {
            val stale = cache.entries.filter { !it.value.isDone }.map { it.key }
            for (key in stale) {
                cache.remove(key)?.cancel(false)
            }
        }
        val future = synthesisThread.submit<File> {
            ensurePreparedOnSynthesisThread()
            applyThreadPriority()
            ensureModelFor(request.styleId)
            val synth = synthesizer ?: throw IllegalStateException("VOICEVOX is not ready")
            val query = step("読みの解析") {
                synth.createAudioQuery(request.text, request.styleId)
            }.apply {
                speedScale = request.speed
                pitchScale = request.pitch
                intonationScale = request.intonation
                volumeScale = request.volume
                prePhonemeLength = 0.05
                postPhonemeLength = 0.05
            }
            val wav = step("声の合成") { synth.synthesis(query, request.styleId).perform() }
            File.createTempFile("voicevox_", ".wav", context.cacheDir).apply { writeBytes(wav) }
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
            } catch (e: java.util.concurrent.CancellationException) {
                // 移動・停止で取り消された先読み。失敗ではないので null を返す
                main.post { result.success(null) }
            } catch (e: Throwable) {
                val cause = (e as? java.util.concurrent.ExecutionException)?.cause ?: e
                Log.w(TAG, "VOICEVOX failed", cause)
                // 原因の連鎖を短くまとめて Flutter 側に見せる
                val chain = generateSequence(cause) { it.cause }
                    .take(4)
                    .joinToString("\n← ") { it.toString() }
                main.post { result.error("voicevox", cause.message ?: cause.toString(), chain) }
            }
        }
    }

    companion object {
        private const val TAG = "VoicevoxBridge"
        const val CHANNEL = "novelty/voicevox"
        private const val ASSET_DIR = "voicevox"
        private const val DICT_ZIP = "open_jtalk_dic.zip"
        private const val CACHE_SIZE = 10
        private const val PREFETCH_FULL = 5

        // 標準モードで同時に読み込んでおくモデルの数（メモリを抑える）
        private const val MAX_LOADED_MODELS_STANDARD = 3

        // 0.vvm: 四国めたん・ずんだもん（ノーマル・あまあま・ツンツン・セクシー）
        // 2.vvm: 九州そら（ノーマル・あまあま・ツンツン・セクシー）
        // 5.vvm: 四国めたん・ずんだもん・九州そら（ささやき・ヒソヒソ）
        // 15.vvm: ずんだもん（ヘロヘロ・なみだめ）
        // 21.vvm: 東北きりたん（ノーマル）
        private val MODEL_FILES = listOf("0.vvm", "2.vvm", "5.vvm", "15.vvm", "21.vvm")
    }
}
