package com.bronxii.kuktam

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
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
