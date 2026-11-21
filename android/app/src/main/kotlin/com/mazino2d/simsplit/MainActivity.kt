package com.mazino2d.simsplit

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // R-9 AC5: one notification channel per category of crm/categories.yaml
        // (id = category id), named in the app's language. The app calls
        // createChannels on launch and when the language changes; creating an
        // existing channel only renames it and keeps the user's settings.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "simsplit/notifications")
            .setMethodCallHandler { call, result ->
                if (call.method != "createChannels") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                // Channels exist from Android 8 (API 26); older versions have none.
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val channels = call.arguments as? List<*> ?: emptyList<Any>()
                for (item in channels) {
                    val spec = item as? Map<*, *> ?: continue
                    val id = spec["id"] as? String ?: continue
                    val name = spec["name"] as? String ?: continue
                    val channel = NotificationChannel(id, name, NotificationManager.IMPORTANCE_DEFAULT)
                    channel.description = spec["description"] as? String
                    manager.createNotificationChannel(channel)
                }
                result.success(null)
            }
    }
}
