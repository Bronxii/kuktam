package com.bronxii.kuktam

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

/** Platform-only, temporary private copies. No URI crosses the channel. */
class ImageImportPicker(private val activity: Activity) {
    companion object { const val REQUEST = 4174 }
    private val root = File(activity.cacheDir, "kuktam_image_input").apply { mkdirs() }
    private val executor = java.util.concurrent.Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var remaining = 5
    private var maxBytes = 0L
    @Volatile private var disposed = false
    init {
        executor.execute {
            val now = System.currentTimeMillis()
            root.listFiles()?.take(100)?.filter { it.isFile && now - it.lastModified() > 86400000L }?.forEach { it.delete() }
        }
    }
    fun handle(method: String, arguments: Any?, result: MethodChannel.Result) {
        if (method == "release") {
            val ids = (arguments as? List<*>)?.filterIsInstance<String>() ?: emptyList()
            executor.execute {
                ids.filter { it.matches(Regex("[a-f0-9-]{36}")) }.forEach { File(root, "$it.input").delete() }
                activity.runOnUiThread { result.success(null) }
            }
            return
        }
        if (method != "pick") { result.notImplemented(); return }
        if (pending != null) { result.error("busy", "Picker busy", null); return }
        val args = arguments as? Map<*, *>
        remaining = (args?.get("remaining") as? Number)?.toInt() ?: 0
        maxBytes = (args?.get("maxBytes") as? Number)?.toLong() ?: 0
        if (!ImageInputCopy.validCount(0, remaining) || maxBytes <= 0) {
            result.error("limit", "Invalid limits", null); return
        }
        pending = result
        try {
            // Native Photo Picker API; no AndroidX upgrade or new dependency.
            val intent = if (Build.VERSION.SDK_INT >= 33) Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                type = "image/*"
                if (remaining > 1) putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, remaining)
            } else fallback()
            try { activity.startActivityForResult(intent, REQUEST) }
            catch (_: android.content.ActivityNotFoundException) { activity.startActivityForResult(fallback(), REQUEST) }
        } catch (_: Exception) { pending = null; result.error("read", "Picker unavailable", null) }
    }
    private fun fallback() = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
        addCategory(Intent.CATEGORY_OPENABLE)
        type = "image/*"
        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/jpeg", "image/png"))
        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, remaining > 1)
        putExtra(Intent.EXTRA_LOCAL_ONLY, true)
    }
    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != REQUEST) return false
        val result = pending ?: return true
        if (code != Activity.RESULT_OK) { pending = null; result.success(emptyList<Any>()); return true }
        val clip = data?.clipData
        val count = clip?.itemCount ?: if (data?.data != null) 1 else 0
        if (!ImageInputCopy.validCount(count, remaining)) {
            pending = null; result.error("limit", "Too many images", null); return true
        }
        val uris = if (clip != null) (0 until count).map { clip.getItemAt(it).uri } else listOfNotNull(data?.data)
        val limit = maxBytes
        executor.execute {
            val rows = uris.map { uri ->
                val id = UUID.randomUUID().toString()
                val file = File(root, "$id.input")
                val row = mutableMapOf<String, Any>("id" to id)
                try {
                    if (disposed || uri == null || uri.scheme != "content") throw java.io.IOException()
                    val mime = activity.contentResolver.getType(uri)
                    if (mime != null && mime != "image/jpeg" && mime != "image/png" && mime != "application/octet-stream") {
                        row["error"] = "format"
                    } else {
                        activity.contentResolver.openInputStream(uri).use { input ->
                            file.outputStream().use { output -> ImageInputCopy.copy(input, output, limit) }
                        }
                        row["path"] = file.absolutePath
                    }
                } catch (_: ImageInputCopy.TooLarge) { row["error"] = "size" }
                  catch (_: Exception) { row["error"] = "read" }
                if (row.containsKey("error")) file.delete()
                row
            }
            activity.runOnUiThread {
                if (!disposed && pending === result) { pending = null; result.success(rows) }
                else rows.forEach { File(root, "${it["id"]}.input").delete() }
            }
        }
        return true
    }
    fun dispose() {
        disposed = true
        pending?.error("read", "Picker interrupted", null); pending = null
        executor.shutdown()
    }
}
