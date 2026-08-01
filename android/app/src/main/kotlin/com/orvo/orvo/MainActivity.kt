package com.orvo.orvo

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import androidx.documentfile.provider.DocumentFile
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    private var pendingDeleteResult: MethodChannel.Result? = null
    private val deleteRequestCode = 4821

    // FIX (#10): SAF lyrics-folder picker (scoped storage blocks raw reads
    // of .lrc files owned by other apps on Android 11+).
    private var pendingFolderResult: MethodChannel.Result? = null
    private val lyricsFolderRequestCode = 4822

    // FEATURE (backup): SAF create/open document — lets the user save the
    // backup JSON straight into Google Drive (or Downloads, SD card…) via
    // the system picker, and pick it back for restore. No extra permissions.
    private var pendingCreateDocResult: MethodChannel.Result? = null
    private var pendingCreateDocContent: String? = null
    private val createDocRequestCode = 4823
    private var pendingOpenDocResult: MethodChannel.Result? = null
    private val openDocRequestCode = 4824

    // FEATURE (duplicate finder): batch delete — ONE system confirmation
    // dialog for all selected copies on Android 11+ instead of one per file.
    private var pendingBatchDeleteResult: MethodChannel.Result? = null
    private val batchDeleteRequestCode = 4825

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerSystemChannel(flutterEngine)
        registerWidgetChannel(flutterEngine)
        registerAppIconChannel(flutterEngine)

        // FIX (#1): the equalizer channel now delegates to the process-wide
        // AudioEffects holder instead of Activity-owned fields, so the EQ
        // survives the Activity being destroyed while playback continues in
        // the background service. onDestroy() no longer releases effects.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "orvo/equalizer")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "init" -> {
                            val sessionId = call.argument<Int>("sessionId")!!
                            result.success(AudioEffects.init(sessionId))
                        }
                        "setEnabled" -> {
                            AudioEffects.setEnabled(
                                call.argument<Boolean>("enabled")!!
                            )
                            result.success(null)
                        }
                        "setBandLevel" -> {
                            AudioEffects.setBandLevel(
                                call.argument<Int>("band")!!,
                                call.argument<Int>("level")!!
                            )
                            result.success(null)
                        }
                        "usePreset" -> {
                            result.success(
                                AudioEffects.usePreset(
                                    call.argument<Int>("preset")!!
                                )
                            )
                        }
                        "setBassBoost" -> {
                            AudioEffects.setBassBoost(
                                call.argument<Int>("strength")!!
                            )
                            result.success(null)
                        }
                        "release" -> {
                            AudioEffects.release()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("EQ_ERROR", e.message, null)
                }
            }
    }

    // -----------------------------------------------------------------------
    // FEATURE (app icon): Snapchat-style selectable launcher icon.
    //
    // All launcher entries are activity-aliases (.LauncherIcon1–5) targeting
    // MainActivity, which itself always stays enabled — an alias only works
    // while its target activity is enabled. Selecting an icon enables exactly
    // one alias and explicitly disables the rest. DONT_KILL_APP keeps the app
    // alive during the switch; the launcher refreshes the icon on its own
    // (some launchers take a few seconds or a home-screen revisit).
    // -----------------------------------------------------------------------

    private val iconCount = 5

    private fun launcherAlias(index: Int): ComponentName =
        ComponentName(this, "$packageName.LauncherIcon$index")

    private fun registerAppIconChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "orvo/appicon")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "set" -> {
                            val index =
                                (call.argument<Int>("index") ?: 1).coerceIn(1, iconCount)
                            val pm = packageManager
                            // Enable the chosen alias FIRST so a launcher
                            // entry always exists, then disable the others.
                            pm.setComponentEnabledSetting(
                                launcherAlias(index),
                                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                                PackageManager.DONT_KILL_APP
                            )
                            for (i in 1..iconCount) {
                                if (i == index) continue
                                pm.setComponentEnabledSetting(
                                    launcherAlias(i),
                                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                                    PackageManager.DONT_KILL_APP
                                )
                            }
                            result.success(null)
                        }
                        "current" -> {
                            val pm = packageManager
                            var current = 1
                            for (i in 1..iconCount) {
                                val state = pm.getComponentEnabledSetting(launcherAlias(i))
                                val enabled =
                                    state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                                        (i == 1 && state ==
                                            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT)
                                if (enabled) {
                                    current = i
                                    break
                                }
                            }
                            result.success(current)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("ICON_ERROR", e.message, null)
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
                        // FIX (#10): let the user pick a lyrics folder via
                        // the system folder picker; Orvo keeps a persistable
                        // read grant so .lrc files remain readable across
                        // restarts, even under scoped storage.
                        "pickLyricsFolder" -> {
                            pendingFolderResult?.success(null)
                            pendingFolderResult = result
                            val intent =
                                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                                    .addFlags(
                                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                                    )
                            startActivityForResult(
                                intent, lyricsFolderRequestCode
                            )
                        }
                        // Looks up "<baseName>.lrc" inside the granted tree
                        // (up to 3 folders deep) and returns its contents.
                        "readLyrics" -> {
                            val treeUri =
                                Uri.parse(call.argument<String>("treeUri")!!)
                            val baseName =
                                call.argument<String>("baseName")!!
                            Thread {
                                val text = readLyricsFromTree(treeUri, baseName)
                                runOnUiThread { result.success(text) }
                            }.start()
                        }
                        // FEATURE (backup): "Save as…" via the system picker.
                        // Google Drive appears as a destination when the
                        // Drive app is installed, so backups can go straight
                        // to the user's Drive.
                        "createDocument" -> {
                            val fileName =
                                call.argument<String>("fileName") ?: "orvo-backup.json"
                            val content = call.argument<String>("content") ?: ""
                            pendingCreateDocResult?.success(false)
                            pendingCreateDocResult = result
                            pendingCreateDocContent = content
                            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "application/json"
                                putExtra(Intent.EXTRA_TITLE, fileName)
                            }
                            startActivityForResult(intent, createDocRequestCode)
                        }
                        // FEATURE (backup): pick a backup file to restore.
                        "openDocument" -> {
                            pendingOpenDocResult?.success(null)
                            pendingOpenDocResult = result
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "*/*"
                                putExtra(
                                    Intent.EXTRA_MIME_TYPES,
                                    arrayOf(
                                        "application/json",
                                        "application/octet-stream",
                                        "text/plain"
                                    )
                                )
                            }
                            startActivityForResult(intent, openDocRequestCode)
                        }
                        // FEATURE (duplicate finder): delete several files in
                        // one scoped-storage request (single system dialog).
                        "deleteMany" -> {
                            @Suppress("UNCHECKED_CAST")
                            val uriStrings =
                                call.argument<List<String>>("uris") ?: emptyList()
                            if (uriStrings.isEmpty()) {
                                result.success(false)
                            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                pendingBatchDeleteResult?.success(false)
                                pendingBatchDeleteResult = result
                                val uris = uriStrings.map { Uri.parse(it) }
                                val pi = MediaStore.createDeleteRequest(
                                    contentResolver, uris
                                )
                                startIntentSenderForResult(
                                    pi.intentSender, batchDeleteRequestCode,
                                    null, 0, 0, 0
                                )
                            } else {
                                var deleted = 0
                                for (u in uriStrings) {
                                    try {
                                        deleted += contentResolver.delete(
                                            Uri.parse(u), null, null
                                        )
                                    } catch (_: Exception) {}
                                }
                                result.success(deleted > 0)
                            }
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
                            // FIX (#13): art comes as raw bytes now.
                            call.argument<ByteArray>("art")
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
        if (requestCode == lyricsFolderRequestCode) {
            val uri = data?.data
            if (resultCode == RESULT_OK && uri != null) {
                try {
                    contentResolver.takePersistableUriPermission(
                        uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                    )
                } catch (_: Exception) {}
                pendingFolderResult?.success(uri.toString())
            } else {
                pendingFolderResult?.success(null)
            }
            pendingFolderResult = null
        }
        // FEATURE (backup): write the JSON into the location the user chose
        // (Drive / Downloads / …). I/O runs off the main thread.
        if (requestCode == createDocRequestCode) {
            val uri = data?.data
            val content = pendingCreateDocContent
            val result = pendingCreateDocResult
            pendingCreateDocContent = null
            pendingCreateDocResult = null
            if (resultCode == RESULT_OK && uri != null && content != null) {
                Thread {
                    val ok = try {
                        contentResolver.openOutputStream(uri, "wt")?.use { out ->
                            out.write(content.toByteArray(Charsets.UTF_8))
                            out.flush()
                        } != null
                    } catch (_: Exception) {
                        false
                    }
                    runOnUiThread { result?.success(ok) }
                }.start()
            } else {
                result?.success(false)
            }
        }
        // FEATURE (backup): read the picked backup file back as text.
        if (requestCode == openDocRequestCode) {
            val uri = data?.data
            val result = pendingOpenDocResult
            pendingOpenDocResult = null
            if (resultCode == RESULT_OK && uri != null) {
                Thread {
                    val text = try {
                        contentResolver.openInputStream(uri)
                            ?.bufferedReader(Charsets.UTF_8)
                            ?.use { it.readText() }
                    } catch (_: Exception) {
                        null
                    }
                    runOnUiThread { result?.success(text) }
                }.start()
            } else {
                result?.success(null)
            }
        }
        // FEATURE (duplicate finder): batch delete confirmation result.
        if (requestCode == batchDeleteRequestCode) {
            pendingBatchDeleteResult?.success(resultCode == RESULT_OK)
            pendingBatchDeleteResult = null
        }
    }

    private fun readLyricsFromTree(treeUri: Uri, baseName: String): String? =
        try {
            val root = DocumentFile.fromTreeUri(this, treeUri)
            root?.let { findLrc(it, "$baseName.lrc", 0) }?.let { doc ->
                contentResolver.openInputStream(doc.uri)
                    ?.bufferedReader()
                    ?.use { it.readText() }
            }
        } catch (e: Exception) {
            null
        }

    private fun findLrc(
        dir: DocumentFile,
        fileName: String,
        depth: Int
    ): DocumentFile? {
        if (depth > 3) return null
        val children = dir.listFiles()
        children
            .firstOrNull { it.isFile && fileName.equals(it.name, ignoreCase = true) }
            ?.let { return it }
        for (child in children) {
            if (child.isDirectory) {
                findLrc(child, fileName, depth + 1)?.let { return it }
            }
        }
        return null
    }

    // NOTE: no onDestroy() override anymore — releasing the effects here was
    // bug #1 (EQ died when the UI closed while music kept playing).
}
