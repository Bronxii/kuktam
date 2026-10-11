package com.bronxii.kuktam

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.MethodChannel

/** Explicit user selection, not a registered generic file handler. */
class RecipeDocumentPicker(private val activity: Activity) {
    companion object { const val REQUEST = 4173 }
    private var pending: MethodChannel.Result? = null
    fun open(result: MethodChannel.Result) {
        if (pending != null) { result.error("busy", "Picker busy", null); return }
        pending = result
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/*"
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf(RecipeFileInbox.MIME, "application/octet-stream", "application/json"))
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
            }, REQUEST)
        } catch (_: Exception) { pending = null; result.error("read", "Picker unavailable", null) }
    }
    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != REQUEST) return false
        val result = pending ?: return true
        if (code != Activity.RESULT_OK) { pending = null; result.success(null); return true }
        val uri = data?.data
        if (uri == null || !RecipeFileInbox.validScheme(uri.scheme)) {
            pending = null; result.error("read", "Document unavailable", null); return true
        }
        Thread {
            var bytes: ByteArray? = null
            var error: String? = null
            try {
                bytes = RecipeUriReader.read(activity.contentResolver, uri, null, true)
            } catch (_: RecipeDocumentRead.WrongFormat) { error = "format"
            } catch (_: RecipeFileInbox.TooLarge) { error = "size" }
              catch (_: Exception) { error = "read" }
            activity.runOnUiThread {
                if (pending === result) {
                    pending = null
                    if (error != null) result.error(error!!, "Document rejected", null) else result.success(bytes)
                }
            }
        }.start()
        return true
    }
    fun dispose() { pending?.error("read", "Picker interrupted", null); pending = null }
}
