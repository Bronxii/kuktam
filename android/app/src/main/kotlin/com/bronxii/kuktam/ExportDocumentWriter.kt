package com.bronxii.kuktam

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/** Outbound SAF only. No permissions, inbound sharing, or Firebase access. */
class ExportDocumentWriter(private val activity: Activity) {
    companion object { const val REQUEST = 4172 }
    private var chooser: MethodChannel.Result? = null
    private var selected: Uri? = null
    private var writing = false
    private var cancelled = AtomicBoolean(false)

    fun handle(method: String, args: Any?, result: MethodChannel.Result) {
        when (method) {
            "choose" -> {
                if (ExportDocumentContract.busy(chooser != null, writing, selected != null)) { result.error("busy", "Export busy", null); return }
                val map = args as? Map<*, *>
                val title = map?.get("title") as? String
                if (map?.size != 1 || !ExportCopy.validTitle(title)) { result.error("invalid", "Invalid export", null); return }
                cancelled = AtomicBoolean(false)
                chooser = result
                try {
                    activity.startActivityForResult(Intent(ExportDocumentContract.ACTION).apply {
                        addCategory(ExportDocumentContract.CATEGORY)
                        type = ExportCopy.MIME
                        putExtra(ExportDocumentContract.TITLE, title)
                    }, REQUEST)
                } catch (_: Exception) { chooser = null; result.error("unavailable", "Document picker unavailable", null) }
            }
            "write" -> {
                val uri = selected
                val map = args as? Map<*, *>
                val path = map?.get("path") as? String
                if (writing || uri == null || path == null || map.size != 1 || cancelled.get()) {
                    result.error("invalid", "No active export destination", null); return
                }
                val file: File
                val root: File
                try {
                    file = File(path).canonicalFile
                    root = File(activity.cacheDir, "kuktam_exports").canonicalFile
                } catch (_: Exception) { result.error("invalid", "Invalid export file", null); return }
                if (!file.path.startsWith(root.path + File.separator) || !file.isFile || !ExportCopy.validTitle(file.name)) {
                    result.error("invalid", "Invalid export file", null); return
                }
                writing = true
                val flag = cancelled
                Thread {
                    var success = false
                    try {
                        file.inputStream().use { input ->
                            (activity.contentResolver.openOutputStream(uri, "w") ?: throw IllegalStateException()).use { output ->
                                ExportCopy.copy(input, output, flag)
                            }
                        }
                        success = !flag.get()
                    } catch (_: Exception) { /* No payload/path logging. */ }
                    if (!success) remove(uri)
                    val completed = success
                    activity.runOnUiThread {
                        writing = false
                        selected = null
                        if (completed && !flag.get()) result.success(true)
                        else { remove(uri); result.error("write-failed", "Export write did not complete", null) }
                    }
                }.start()
            }
            "cancel" -> { cancel(); result.success(null) }
            else -> result.notImplemented()
        }
    }
    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != REQUEST) return false
        val pending = chooser
        chooser = null
        val uri = data?.data
        when (ExportDocumentContract.selection(cancelled.get(), pending != null, code == Activity.RESULT_OK, uri?.scheme)) {
            ExportDocumentContract.Selection.CANCELED -> { if (uri != null) remove(uri); pending?.success(false) }
            ExportDocumentContract.Selection.MISSING_URI -> pending?.error("missing-uri", "Document destination unavailable", null)
            ExportDocumentContract.Selection.SELECTED -> { selected = uri; pending?.success(true) }
        }
        return true
    }
    fun cancel() {
        cancelled.set(true)
        if (!writing) { selected?.let { remove(it) }; selected = null }
        // Retain outstanding chooser until its result, so a second picker cannot steal it.
    }
    fun dispose() {
        cancel()
        chooser?.error("interrupted", "Export interrupted", null)
        chooser = null
    }
    private fun remove(uri: Uri) {
        try { DocumentsContract.deleteDocument(activity.contentResolver, uri) } catch (_: Exception) { /* Provider may refuse cleanup. */ }
    }
}
