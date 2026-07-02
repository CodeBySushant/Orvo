package com.orvo.orvo

import android.content.Intent
import android.media.RingtoneManager
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null

    private var pendingDeleteResult: MethodChannel.Result? = null
    private val deleteRequestCode = 4821

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerSystemChannel(flutterEngine)
        registerWidgetChannel(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "orvo/equalizer")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "init" -> {
                            val sessionId = call.argument<Int>("sessionId")!!
                            releaseEffects()
                            val eq = Equalizer(0, sessionId)
                            equalizer = eq
                            bassBoost = BassBoost(0, sessionId)
                            val bands = (0 until eq.numberOfBands).map { i ->
                                mapOf(
                                    "index" to i,
                                    // getCenterFreq returns milliHertz
                                    "centerFreq" to eq.getCenterFreq(i.toShort()) / 1000,
                                    "level" to eq.getBandLevel(i.toShort()).toInt()
                                )
                            }
                            val presets = (0 until eq.numberOfPresets).map {
                                eq.getPresetName(it.toShort())
                            }
                            result.success(
                                mapOf(
                                    "minLevel" to eq.bandLevelRange[0].toInt(),
                                    "maxLevel" to eq.bandLevelRange[1].toInt(),
                                    "bands" to bands,
                                    "presets" to presets
                                )
                            )
                        }
                        "setEnabled" -> {
                            val enabled = call.argument<Boolean>("enabled")!!
                            equalizer?.enabled = enabled
                            bassBoost?.enabled =
                                enabled && (bassBoost?.roundedStrength ?: 0) > 0
                            result.success(null)
                        }
                        "setBandLevel" -> {
                            val band = call.argument<Int>("band")!!
                            val level = call.argument<Int>("level")!!
                            equalizer?.setBandLevel(band.toShort(), level.toShort())
                            result.success(null)
                        }
                        "usePreset" -> {
                            val preset = call.argument<Int>("preset")!!
                            val eq = equalizer
                            if (eq != null) {
                                eq.usePreset(preset.toShort())
                                val levels = (0 until eq.numberOfBands).map {
                                    eq.getBandLevel(it.toShort()).toInt()
                                }
                                result.success(levels)
                            } else {
                                result.success(emptyList<Int>())
                            }
                        }
                        "setBassBoost" -> {
                            val strength = call.argument<Int>("strength")!!
                            bassBoost?.setStrength(strength.toShort())
                            bassBoost?.enabled =
                                strength > 0 && (equalizer?.enabled ?: false)
                            result.success(null)
                        }
                        "release" -> {
                            releaseEffects()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("EQ_ERROR", e.message, null)
                }
            }
    }

    private fun registerSystemChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "orvo/system")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "share" -> {
                            val uri = Uri.parse(call.argument<String>("uri")!!)
                            val title = call.argument<String>("title") ?: "Song"
                            val send = Intent(Intent.ACTION_SEND).apply {
                                type = "audio/*"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                putExtra(Intent.EXTRA_TITLE, title)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(Intent.createChooser(send, title))
                            result.success(null)
                        }
                        "setRingtone" -> {
                            if (!Settings.System.canWrite(this)) {
                                result.success(
                                    mapOf("ok" to false, "needsPermission" to true)
                                )
                            } else {
                                val uri = Uri.parse(call.argument<String>("uri")!!)
                                RingtoneManager.setActualDefaultRingtoneUri(
                                    this, RingtoneManager.TYPE_RINGTONE, uri
                                )
                                result.success(
                                    mapOf("ok" to true, "needsPermission" to false)
                                )
                            }
                        }
                        "openWriteSettings" -> {
                            startActivity(
                                Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS)
                                    .setData(Uri.parse("package:$packageName"))
                            )
                            result.success(null)
                        }
                        "delete" -> {
                            val uri = Uri.parse(call.argument<String>("uri")!!)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                // Scoped storage: system confirmation dialog.
                                pendingDeleteResult?.success(false)
                                pendingDeleteResult = result
                                val pi = MediaStore.createDeleteRequest(
                                    contentResolver, listOf(uri)
                                )
                                startIntentSenderForResult(
                                    pi.intentSender, deleteRequestCode,
                                    null, 0, 0, 0
                                )
                            } else {
                                val rows = contentResolver.delete(uri, null, null)
                                result.success(rows > 0)
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("SYS_ERROR", e.message, null)
                }
            }
    }

    private fun registerWidgetChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "orvo/widget")
            .setMethodCallHandler { call, result ->
                try {
                    if (call.method == "update") {
                        OrvoWidgetProvider.push(
                            applicationContext,
                            call.argument<String>("title") ?: "Orvo",
                            call.argument<String>("artist") ?: "",
                            call.argument<Boolean>("playing") ?: false,
                            (call.argument<Number>("albumId") ?: -1).toLong()
                        )
                        result.success(null)
                    } else {
                        result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("WIDGET_ERROR", e.message, null)
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == deleteRequestCode) {
            pendingDeleteResult?.success(resultCode == RESULT_OK)
            pendingDeleteResult = null
        }
    }

    private fun releaseEffects() {
        equalizer?.release()
        equalizer = null
        bassBoost?.release()
        bassBoost = null
    }

    override fun onDestroy() {
        releaseEffects()
        super.onDestroy()
    }
}
