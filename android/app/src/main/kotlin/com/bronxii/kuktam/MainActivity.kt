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
    }
    private var shareChannel: MethodChannel? = null
    private var exportChannel: MethodChannel? = null
    private var exportWriter: ExportDocumentWriter? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A restored Activity must not replay the launch share.
        if (savedInstanceState == null) receiveText(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receiveText(intent)
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
        if (exportWriter?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
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
