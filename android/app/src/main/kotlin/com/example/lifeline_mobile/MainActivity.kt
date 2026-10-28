package com.example.lifeline_mobile

import android.os.Handler
import android.os.Looper
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
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var engine: Engine? = null

    private val modelFile: File
        get() = File(filesDir, "models/gemma-4-E2B-it.litertlm")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lifeline/gemma4")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> {
                        val file = modelFile
                        result.success(mapOf(
                            "path" to file.absolutePath,
                            "installed" to (file.isFile && file.length() == 2588147712L),
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
        val file = modelFile
        if (!file.isFile || file.length() != 2588147712L) {
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
