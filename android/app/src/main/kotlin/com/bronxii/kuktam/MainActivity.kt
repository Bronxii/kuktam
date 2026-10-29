package com.bronxii.kuktam

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

class MainActivity : FlutterActivity() {
    companion object {
        // Survives Activity recreation, but deliberately not process death.
        private val textShares = TextShareInbox()
        private val recipeFiles = RecipeFileInbox()
        private var recipeActivity = java.lang.ref.WeakReference<MainActivity>(null)
        private val recipeReader = java.util.concurrent.Executors.newSingleThreadExecutor()
    }
    private var familyChannel: MethodChannel? = null
    private var pendingFamilyLink: String? = null
    private var imagePicker: ImageImportPicker? = null
    private var imageChannel: MethodChannel? = null
    private var recipePicker: RecipeDocumentPicker? = null
    private var recipeChannel: MethodChannel? = null
    private var shareChannel: MethodChannel? = null
    private var exportChannel: MethodChannel? = null
    private var exportWriter: ExportDocumentWriter? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A restored Activity must not replay the launch share.
        if (savedInstanceState == null && !receiveFamilyLink(intent) && !receiveRecipe(intent)) receiveText(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (!receiveFamilyLink(intent) && !receiveRecipe(intent)) receiveText(intent)
    }

    private fun receiveFamilyLink(incoming: Intent): Boolean {
        if (incoming.action != Intent.ACTION_VIEW) return false
        val uri = incoming.data ?: return false
        if (uri.scheme != "https" && uri.scheme != "http") return false
        val raw = uri.toString()
        incoming.action = Intent.ACTION_MAIN
        incoming.data = null
        // One bounded volatile slot; Dart alone validates and authorizes routing.
        if (pendingFamilyLink == null && raw.length <= 256) {
            pendingFamilyLink = raw
            familyChannel?.invokeMethod("pending", null)
        } else {
            Toast.makeText(this, "Nyisd meg újra a meghívólinket az alkalmazásban.", Toast.LENGTH_LONG).show()
        }
        return true
    }

    private fun receiveRecipe(incoming: Intent): Boolean {
        if (!RecipeDocumentRead.routes(incoming.action, incoming.type)) return false
        val mime = incoming.type // Capture before consumption clears data/type.
        val uri = try {
            val primary = if (incoming.action == Intent.ACTION_VIEW) incoming.data
                else incoming.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)
            primary ?: incoming.clipData?.let { if (it.itemCount == 1) it.getItemAt(0).uri else null }
        } catch (_: RuntimeException) { null }
        // Consume this intent; Activity recreation must not re-enqueue it.
        incoming.action = Intent.ACTION_MAIN
        incoming.data = null
        incoming.removeExtra(Intent.EXTRA_STREAM)
        val id = recipeFiles.begin()
        if (id == null) { Toast.makeText(this, "Előbb fejezd be a várakozó receptimportokat.", Toast.LENGTH_LONG).show(); return true }
        recipeChannel?.invokeMethod("pending", null)
        if (uri == null || !RecipeFileInbox.validScheme(uri.scheme)) {
            recipeFiles.finish(id, null, "read")
            recipeChannel?.invokeMethod("pending", null)
            return true
        }
        val resolver = applicationContext.contentResolver
        recipeReader.execute {
            try {
                val bytes = RecipeUriReader.read(resolver, uri, mime, false)
                recipeFiles.finish(id, bytes, null)
            } catch (_: RecipeDocumentRead.WrongFormat) { recipeFiles.finish(id, null, "format") }
              catch (_: RecipeFileInbox.TooLarge) { recipeFiles.finish(id, null, "size") }
              catch (_: Exception) { recipeFiles.finish(id, null, "read") }
            recipeActivity.get()?.let { current -> current.runOnUiThread { current.recipeChannel?.invokeMethod("pending", null) } }
        }
        return true
    }

    private fun receiveText(incoming: Intent) {
        if (incoming.action != Intent.ACTION_SEND) return
        val result = try {
            textShares.receive(incoming.action, incoming.type,
                incoming.getCharSequenceExtra(Intent.EXTRA_TEXT))
        } catch (_: RuntimeException) { "invalid" }
        // Consume the Activity intent as well as the queue entry; no restart replay.
        incoming.removeExtra(Intent.EXTRA_TEXT)
        incoming.action = Intent.ACTION_MAIN
        if (result == "accepted") {
            shareChannel?.invokeMethod("pending", null)
        } else {
            val message = when (result) {
                "tooLarge" -> "Legfeljebb 20 000 karakter osztható meg."
                "full" -> "Előbb fejezd be a várakozó importokat, majd oszd meg újra a szöveget."
                else -> "A Kuktám jelenleg megosztott szöveget fogad."
            }
            Toast.makeText(this, message, Toast.LENGTH_LONG).show()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (imagePicker?.onActivityResult(requestCode, resultCode, data) == true) return
        if (recipePicker?.onActivityResult(requestCode, resultCode, data) == true) return
        if (exportWriter?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        familyChannel?.setMethodCallHandler(null)
        familyChannel = null
        pendingFamilyLink = null
        imageChannel?.setMethodCallHandler(null)
        imageChannel = null
        imagePicker?.dispose()
        imagePicker = null
        recipePicker?.dispose()
        recipePicker = null
        if (recipeActivity.get() === this) recipeActivity.clear()
        recipeChannel?.setMethodCallHandler(null)
        recipeChannel = null
        exportWriter?.dispose()
        exportWriter = null
        exportChannel?.setMethodCallHandler(null)
        exportChannel = null
        shareChannel?.setMethodCallHandler(null)
        shareChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        familyChannel = MethodChannel(messenger, "kuktam/family_links").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "take" && call.arguments == null) {
                    val value = pendingFamilyLink
                    pendingFamilyLink = null
                    result.success(value)
                } else result.notImplemented()
            }
        }
        recipeActivity = java.lang.ref.WeakReference(this)
        imagePicker = ImageImportPicker(this)
        imageChannel = MethodChannel(messenger, "kuktam/image_import").also { channel ->
            channel.setMethodCallHandler { call, result -> imagePicker!!.handle(call.method, call.arguments, result) }
        }
        recipePicker = RecipeDocumentPicker(this)
        recipeChannel = MethodChannel(messenger, "kuktam/recipe_file").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "take" && call.arguments == null) result.success(recipeFiles.take())
                else if (call.method == "pick" && call.arguments == null) recipePicker!!.open(result)
                else result.notImplemented()
            }
        }
        exportWriter = ExportDocumentWriter(this)
        exportChannel = MethodChannel(messenger, "kuktam/export_document").also { channel ->
            channel.setMethodCallHandler { call, result -> exportWriter!!.handle(call.method, call.arguments, result) }
        }
        shareChannel = MethodChannel(messenger, "kuktam/text_share").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "take" && call.arguments == null) {
                    result.success(textShares.take())
                } else result.notImplemented()
            }
        }
        MethodChannel(messenger, "kuktam/entitlement_durability",
            StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue())
            .setMethodCallHandler { call, result ->
                if (call.method != "flush" || call.arguments != null) {
                    result.notImplemented()
                } else {
                    try {
                        // commit waits for preceding SharedPreferences.apply writes.
                        // Only this dedicated cache namespace; no recipe/auth data.
                        val names = listOf("kuktam_entitlement",
                            "FlutterSecureKeyStorage:kuktam_entitlement",
                            "FlutterSecureStorageConfiguration:kuktam_entitlement")
                        val success = names.map {
                            applicationContext.getSharedPreferences(it, MODE_PRIVATE).edit().commit()
                        }.all { it }
                        if (success) result.success(null)
                        else result.error("storage-failure", "Cache write failed", null)
                    } catch (_: Exception) {
                        result.error("storage-failure", "Cache write failed", null)
                    }
                }
            }
    }
}
