package com.example.expense_tracker

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "expense_tracker/notifications",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isEnabled" -> result.success(isListenerEnabled())
                "openSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(null)
                }
                "drain" -> result.success(ExpenseNotificationListener.drain(applicationContext))
                else -> result.notImplemented()
            }
        }
    }

    private fun isListenerEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        val me = ComponentName(this, ExpenseNotificationListener::class.java)
        return enabled.split(':').any {
            ComponentName.unflattenFromString(it) == me
        }
    }
}
