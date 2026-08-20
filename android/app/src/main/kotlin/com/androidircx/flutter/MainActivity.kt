package com.androidircx.flutter

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingNotificationAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        captureNotificationAction(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureNotificationAction(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FOREGROUND_SERVICE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "ensureReady" -> {
                        AndroidIrcxForegroundService.createNotificationChannels(this)
                        result.success(null)
                    }
                    "update" -> {
                        updateForegroundService(call.arguments)
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this, AndroidIrcxForegroundService::class.java))
                        result.success(null)
                    }
                    "openBatteryOptimizationSettings" -> {
                        result.success(openBatteryOptimizationSettings())
                    }
                    "consumePendingAction" -> {
                        val action = pendingNotificationAction
                        pendingNotificationAction = null
                        result.success(action)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("foreground_service_error", error.message, null)
            }
        }
    }

    private fun captureNotificationAction(intent: Intent?) {
        if (intent?.action == AndroidIrcxForegroundService.ACTION_DISCONNECT_ALL) {
            pendingNotificationAction = "disconnectAll"
        }
    }

    private fun updateForegroundService(arguments: Any?) {
        val payload = arguments as? Map<*, *> ?: emptyMap<String, Any?>()
        val activeNetworkCount = payload.intValue("activeNetworkCount")
        if (activeNetworkCount <= 0) {
            stopService(Intent(this, AndroidIrcxForegroundService::class.java))
            return
        }

        val networks = payload["networks"] as? List<*> ?: emptyList<Any?>()
        val networkNames = ArrayList(
            networks.mapNotNull { item ->
                val network = item as? Map<*, *> ?: return@mapNotNull null
                val phase = network["phase"] as? String ?: return@mapNotNull null
                if (!phase.keepsForegroundServiceRunning()) {
                    return@mapNotNull null
                }
                network["name"] as? String
            },
        )
        val intent = AndroidIrcxForegroundService.updateIntent(
            context = this,
            activeNetworkCount = activeNetworkCount,
            connectedNetworkCount = payload.intValue("connectedNetworkCount"),
            reconnectingNetworkCount = payload.intValue("reconnectingNetworkCount"),
            errorNetworkCount = payload.intValue("errorNetworkCount"),
            networkNames = networkNames,
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun openBatteryOptimizationSettings(): Boolean {
        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (intent.resolveActivity(packageManager) == null) {
            return false
        }
        startActivity(intent)
        return true
    }

    private fun Map<*, *>.intValue(key: String): Int {
        return (this[key] as? Number)?.toInt() ?: 0
    }

    private fun String.keepsForegroundServiceRunning(): Boolean {
        return this == "connecting" ||
            this == "registering" ||
            this == "authenticating" ||
            this == "connected" ||
            this == "reconnecting" ||
            this == "disconnecting"
    }

    companion object {
        private const val FOREGROUND_SERVICE_CHANNEL =
            "androidircx/foreground_connection_service"
    }
}
