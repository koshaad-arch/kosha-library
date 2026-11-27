package com.koshagandhi.kosha_library

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Adds a tiny "pick a text file" channel used to import the Goodreads export. */
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private val pickRequest = 4711

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kosha/files").setMethodCallHandler { call, result ->
            if (call.method == "pickText") {
                pending?.success(null)
                pending = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                }
                @Suppress("DEPRECATION")
                startActivityForResult(intent, pickRequest)
            } else {
                result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRequest) return
        val res = pending ?: return
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            res.success(null)
            return
        }
        try {
            val text = contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) }
            res.success(text)
        } catch (e: Exception) {
            res.error("read_failed", e.message, null)
        }
    }
}
