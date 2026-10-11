package com.bronxii.kuktam

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns
import java.io.IOException

/** Both entry points use the same provider metadata and bounded byte reader. */
object RecipeUriReader {
    fun read(resolver: ContentResolver, uri: Uri, mime: String?, requireName: Boolean): ByteArray {
        return RecipeDocumentRead.read(object : RecipeDocumentRead.Document {
            override fun displayName(): String? {
                try {
                    return resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                        val column = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (column >= 0 && it.moveToFirst()) it.getString(column) else null
                    }
                } catch (_: Exception) { throw IOException() }
            }
            override fun open() = resolver.openInputStream(uri) ?: throw IOException()
        }, uri.scheme, uri.path, mime, requireName)
    }
}
