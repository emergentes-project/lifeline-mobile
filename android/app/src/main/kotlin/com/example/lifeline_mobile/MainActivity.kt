package com.example.lifeline_mobile

import android.content.res.AssetManager
import android.os.Handler
import android.os.Looper
import android.os.Bundle
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val modelName = "gemma-4-E2B-it.litertlm"
    private val modelLength = 2588147712L
    private val modelSha256 = "181938105E0EEFD105961417E8DA75903EACDA102C4FCE9CE90F50B97139A63C"
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var engine: Engine? = null

    private val modelFile: File
        get() = File(filesDir, "models/$modelName")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        worker.execute {
            try {
                ensureModelInstalled()
            } catch (_: Exception) {
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lifeline/gemma4")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> {
                        val file = modelFile
                        result.success(mapOf(
                            "path" to file.absolutePath,
                            "installed" to ((file.isFile && file.length() == modelLength) || hasBundledModel()),
                            "ready" to (file.isFile && file.length() == modelLength),
                        ))
                    }
                    "load" -> runOnWorker(result) {
                        loadEngine()
                        null
                    }
                    "generate" -> runOnWorker(result) {
                        val prompt = call.argument<String>("prompt")
                            ?: throw IllegalArgumentException("Falta el texto de entrada")
                        val imagePath = call.argument<String>("imagePath")
                        val loaded = loadEngine()
                        val conversation = loaded.createConversation(
                            ConversationConfig(
                                systemInstruction = Contents.of(
                                    "Responde en español usando únicamente el contexto médico proporcionado. Si no hay evidencia suficiente, indícalo. No inventes diagnósticos, medicamentos ni dosis."
                                )
                            )
                        )
                        try {
                            if (imagePath == null) {
                                conversation.sendMessage(prompt).toString()
                            } else {
                                val image = File(imagePath)
                                if (!image.isFile) throw IllegalArgumentException("La imagen no existe")
                                conversation.sendMessage(
                                    Contents.of(Content.ImageFile(image.absolutePath), Content.Text(prompt))
                                ).toString()
                            }
                        } finally {
                            conversation.close()
                        }
                    }
                    "dispose" -> runOnWorker(result) {
                        engine?.close()
                        engine = null
                        null
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun loadEngine(): Engine {
        engine?.let { return it }
        ensureModelInstalled()
        val file = modelFile
        if (!file.isFile || file.length() != modelLength) {
            throw IllegalStateException("El modelo Gemma 4 E2B no está instalado o está incompleto")
        }
        val created = Engine(
            EngineConfig(
                modelPath = file.absolutePath,
                backend = Backend.CPU(),
                visionBackend = Backend.CPU(),
                cacheDir = cacheDir.absolutePath,
            )
        )
        created.initialize()
        engine = created
        return created
    }

    private fun hasBundledModel(): Boolean =
        try {
            assets.openFd(modelName).close()
            true
        } catch (_: Exception) {
            false
        }

    private fun ensureModelInstalled() {
        val destination = modelFile
        if (destination.isFile && destination.length() == modelLength) return
        if (!hasBundledModel()) {
            throw IllegalStateException("El APK no contiene el modelo Gemma 4 E2B")
        }
        if (filesDir.usableSpace < modelLength + 200_000_000L) {
            throw IllegalStateException("No hay espacio suficiente para instalar el modelo local")
        }
        val directory = destination.parentFile ?: throw IllegalStateException("Ruta del modelo inválida")
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("No se pudo preparar la carpeta del modelo")
        }
        val temporary = File(directory, "$modelName.partial")
        if (temporary.exists()) temporary.delete()
        val digest = MessageDigest.getInstance("SHA-256")
        try {
            assets.open(modelName, AssetManager.ACCESS_STREAMING).use { source ->
                FileOutputStream(temporary).use { target ->
                    val buffer = ByteArray(1024 * 1024)
                    while (true) {
                        val read = source.read(buffer)
                        if (read < 0) break
                        target.write(buffer, 0, read)
                        digest.update(buffer, 0, read)
                    }
                    target.fd.sync()
                }
            }
            val actualHash = digest.digest().joinToString("") { "%02X".format(it) }
            if (temporary.length() != modelLength || actualHash != modelSha256) {
                throw IllegalStateException("El modelo empaquetado está incompleto o dañado")
            }
            if (destination.exists() && !destination.delete()) {
                throw IllegalStateException("No se pudo reemplazar el modelo incompleto")
            }
            if (!temporary.renameTo(destination)) {
                throw IllegalStateException("No se pudo completar la instalación del modelo")
            }
        } finally {
            if (temporary.exists()) temporary.delete()
        }
    }

    private fun runOnWorker(result: MethodChannel.Result, action: () -> Any?) {
        worker.execute {
            try {
                val value = action()
                mainHandler.post { result.success(value) }
            } catch (error: Exception) {
                mainHandler.post { result.error("GEMMA4_ERROR", error.message, null) }
            }
        }
    }

    override fun onDestroy() {
        worker.execute { engine?.close() }
        worker.shutdown()
        super.onDestroy()
    }
}
