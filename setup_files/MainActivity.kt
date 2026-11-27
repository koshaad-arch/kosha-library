package com.koshagandhi.kosha_library

import android.app.Activity
import android.content.Intent
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Small file channel: pick a file (imports, restore) and save a file (backup). */
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var saveBytes: ByteArray? = null
    private val pickRequest = 4711
    private val saveRequest = 4712

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kosha/files").setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFile" -> {
                    pending?.success(null)
                    pending = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    }
                    @Suppress("DEPRECATION")
                    startActivityForResult(intent, pickRequest)
                }
                "saveFile" -> {
                    pending?.success(null)
                    pending = result
                    saveBytes = call.argument<ByteArray>("bytes")
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = call.argument<String>("mime") ?: "application/octet-stream"
                        putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "backup.json")
                    }
                    @Suppress("DEPRECATION")
                    startActivityForResult(intent, saveRequest)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRequest && requestCode != saveRequest) return
        val res = pending ?: return
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            res.success(null)
            return
        }
        try {
            if (requestCode == pickRequest) {
                var name = "file"
                contentResolver.query(uri, null, null, null, null)?.use { c ->
                    val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0 && c.moveToFirst()) name = c.getString(idx) ?: name
                }
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: ByteArray(0)
                res.success(hashMapOf("name" to name, "bytes" to bytes))
            } else {
                contentResolver.openOutputStream(uri)?.use { it.write(saveBytes ?: ByteArray(0)) }
                saveBytes = null
                res.success(true)
            }
        } catch (e: Exception) {
            res.error("file_failed", e.message, null)
        }
    }
}
