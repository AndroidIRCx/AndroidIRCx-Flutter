package com.androidircx.flutter

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

object AndroidIrcxEngineManager {
    const val ENGINE_ID = "androidircx.foreground_engine"

    private const val FOREGROUND_SERVICE_CHANNEL =
        "androidircx/foreground_connection_service"
    private const val REQUEST_USER_NOTIFICATION_OPEN = 22071
    private const val USER_NOTIFICATION_BASE_ID = 42000

    private var pendingNotificationAction: String? = null

    @Synchronized
    fun ensureEngine(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        val cached = cache.get(ENGINE_ID)
        if (cached != null) {
            attachForegroundChannel(context, cached)
            return cached
        }

        val applicationContext = context.applicationContext
        val engine = FlutterEngine(applicationContext)
        GeneratedPluginRegistrant.registerWith(engine)
        attachForegroundChannel(applicationContext, engine)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault(),
        )
        cache.put(ENGINE_ID, engine)
        return engine
    }

    fun attachForegroundChannel(context: Context, flutterEngine: FlutterEngine) {
        val applicationContext = context.applicationContext
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FOREGROUND_SERVICE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "ensureReady" -> {
                        AndroidIrcxForegroundService.createNotificationChannels(
                            applicationContext,
                        )
                        result.success(null)
                    }
                    "update" -> {
                        updateForegroundService(applicationContext, call.arguments)
                        result.success(null)
                    }
                    "stop" -> {
                        applicationContext.stopService(
                            Intent(
                                applicationContext,
                                AndroidIrcxForegroundService::class.java,
                            ),
                        )
                        result.success(null)
                    }
                    "openBatteryOptimizationSettings" -> {
                        result.success(openBatteryOptimizationSettings(applicationContext))
                    }
                    "consumePendingAction" -> {
                        val action = pendingNotificationAction
                        pendingNotificationAction = null
                        result.success(action)
                    }
                    "showNotification" -> {
                        showUserNotification(applicationContext, call.arguments)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("foreground_service_error", error.message, null)
            }
        }
    }

    fun captureNotificationAction(intent: Intent?) {
        if (intent?.action == AndroidIrcxForegroundService.ACTION_DISCONNECT_ALL) {
            pendingNotificationAction = "disconnectAll"
        }
    }

    private fun updateForegroundService(context: Context, arguments: Any?) {
        val payload = arguments as? Map<*, *> ?: emptyMap<String, Any?>()
        val activeNetworkCount = payload.intValue("activeNetworkCount")
        val activeTransferCount = payload.intValue("activeTransferCount")
        if (activeNetworkCount <= 0 && activeTransferCount <= 0) {
            context.stopService(Intent(context, AndroidIrcxForegroundService::class.java))
            return
        }
        val transferSummaries = activeTransferSummaries(payload)

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
            context = context,
            activeNetworkCount = activeNetworkCount,
            connectedNetworkCount = payload.intValue("connectedNetworkCount"),
            reconnectingNetworkCount = payload.intValue("reconnectingNetworkCount"),
            errorNetworkCount = payload.intValue("errorNetworkCount"),
            networkNames = networkNames,
            activeTransferCount = maxOf(
                activeTransferCount,
                transferSummaries.size,
            ),
            transferSummaries = transferSummaries,
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    private fun activeTransferSummaries(payload: Map<*, *>): ArrayList<String> {
        val transfers = payload["transfers"] as? List<*> ?: return ArrayList()
        return ArrayList(
            transfers.mapNotNull { item ->
                val transfer = item as? Map<*, *> ?: return@mapNotNull null
                val status = transfer["status"] as? String ?: return@mapNotNull null
                if (!status.keepsTransferNotificationVisible()) {
                    return@mapNotNull null
                }

                val kind = when ((transfer["kind"] as? String)?.lowercase()) {
                    "dcc" -> "DCC"
                    "media" -> "Media"
                    else -> "Transfer"
                }
                val direction = (transfer["direction"] as? String)
                    ?.takeIf { it.isNotBlank() }
                    ?: "active"
                val peerNick = (transfer["peerNick"] as? String)
                    ?.takeIf { it.isNotBlank() }
                val fileName = (transfer["fileName"] as? String)
                    ?.takeIf { it.isNotBlank() }
                    ?: "file"
                val owner = if (peerNick == null) fileName else "$peerNick: $fileName"
                val progress = transfer.progressSummary(status)
                "$kind $direction: $owner - $progress"
            },
        )
    }

    private fun showUserNotification(context: Context, arguments: Any?) {
        AndroidIrcxForegroundService.createNotificationChannels(context)
        val payload = arguments as? Map<*, *> ?: return
        val title = (payload["title"] as? String)?.takeIf { it.isNotBlank() }
            ?: "AndroidIRCx"
        val body = (payload["body"] as? String)?.takeIf { it.isNotBlank() }
            ?: return
        val rawId = (payload["id"] as? String)?.takeIf { it.isNotBlank() }
            ?: "$title:$body"
        val channelId = notificationChannelId(payload["channelId"] as? String)
        val launchIntent =
            context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val contentIntent = PendingIntent.getActivity(
            context,
            REQUEST_USER_NOTIFICATION_OPEN,
            launchIntent,
            pendingIntentFlags(),
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, channelId)
        } else {
            Notification.Builder(context)
        }
        builder
            .setSmallIcon(R.drawable.ic_stat_androidircx)
            .setLargeIcon(
                BitmapFactory.decodeResource(context.resources, R.mipmap.ic_launcher),
            )
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setOnlyAlertOnce(false)
            .setCategory(notificationCategory(channelId))

        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(userNotificationId(rawId), builder.build())
    }

    private fun openBatteryOptimizationSettings(context: Context): Boolean {
        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (intent.resolveActivity(context.packageManager) == null) {
            return false
        }
        context.startActivity(intent)
        return true
    }

    private fun Map<*, *>.intValue(key: String): Int {
        return (this[key] as? Number)?.toInt() ?: 0
    }

    private fun Map<*, *>.longValue(key: String): Long {
        return (this[key] as? Number)?.toLong() ?: 0L
    }

    private fun Map<*, *>.longValueOrNull(key: String): Long? {
        return (this[key] as? Number)?.toLong()
    }

    private fun Map<*, *>.doubleValueOrNull(key: String): Double? {
        return (this[key] as? Number)?.toDouble()
    }

    private fun Map<*, *>.progressSummary(status: String): String {
        val totalBytes = longValueOrNull("totalBytes")
        val bytesTransferred = longValue("bytesTransferred")
        val parts = ArrayList<String>()
        if (totalBytes != null && totalBytes > 0L) {
            val percent = ((bytesTransferred * 100L) / totalBytes).coerceIn(0L, 100L)
            parts.add("$percent%")
        } else if (bytesTransferred > 0L) {
            parts.add("$bytesTransferred bytes")
        }

        val bytesPerSecond = doubleValueOrNull("bytesPerSecond")
        if (bytesPerSecond != null && bytesPerSecond.isFinite() && bytesPerSecond > 0.0) {
            parts.add("${formatByteRate(bytesPerSecond)}/s")
        }
        val etaSeconds = longValueOrNull("estimatedRemainingSeconds")
        if (etaSeconds != null && etaSeconds > 0L) {
            parts.add("ETA ${formatDuration(etaSeconds)}")
        }
        return parts.takeIf { it.isNotEmpty() }?.joinToString(", ") ?: status
    }

    private fun formatByteRate(bytes: Double): String {
        var value = bytes
        val units = arrayOf("B", "KB", "MB", "GB")
        var unitIndex = 0
        while (value >= 1024.0 && unitIndex < units.lastIndex) {
            value /= 1024.0
            unitIndex += 1
        }
        val rounded = if (value >= 10.0 || unitIndex == 0) {
            value.toLong().toString()
        } else {
            String.format("%.1f", value)
        }
        return "$rounded ${units[unitIndex]}"
    }

    private fun formatDuration(seconds: Long): String {
        if (seconds < 60L) {
            return "${seconds}s"
        }
        val minutes = seconds / 60L
        val remainingSeconds = seconds % 60L
        if (minutes < 60L) {
            return "${minutes}m ${remainingSeconds}s"
        }
        val hours = minutes / 60L
        val remainingMinutes = minutes % 60L
        return "${hours}h ${remainingMinutes}m"
    }

    private fun notificationChannelId(channelId: String?): String {
        return when (channelId) {
            AndroidIrcxForegroundService.CHANNEL_HIGHLIGHTS,
            AndroidIrcxForegroundService.CHANNEL_QUERIES,
            AndroidIrcxForegroundService.CHANNEL_DCC_TRANSFERS,
            AndroidIrcxForegroundService.CHANNEL_MEDIA_TRANSFERS,
            AndroidIrcxForegroundService.CHANNEL_ERRORS,
            AndroidIrcxForegroundService.CHANNEL_CONNECTION -> channelId
            else -> AndroidIrcxForegroundService.CHANNEL_CONNECTION
        }
    }

    private fun notificationCategory(channelId: String): String {
        return when (channelId) {
            AndroidIrcxForegroundService.CHANNEL_QUERIES,
            AndroidIrcxForegroundService.CHANNEL_HIGHLIGHTS -> Notification.CATEGORY_MESSAGE
            AndroidIrcxForegroundService.CHANNEL_ERRORS -> Notification.CATEGORY_ERROR
            AndroidIrcxForegroundService.CHANNEL_DCC_TRANSFERS,
            AndroidIrcxForegroundService.CHANNEL_MEDIA_TRANSFERS -> Notification.CATEGORY_PROGRESS
            else -> Notification.CATEGORY_STATUS
        }
    }

    private fun userNotificationId(rawId: String): Int {
        return USER_NOTIFICATION_BASE_ID + (rawId.hashCode() and 0x0fffffff)
    }

    private fun pendingIntentFlags(): Int {
        return PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
    }

    private fun String.keepsForegroundServiceRunning(): Boolean {
        return this == "connecting" ||
            this == "registering" ||
            this == "authenticating" ||
            this == "connected" ||
            this == "reconnecting" ||
            this == "disconnecting"
    }

    private fun String.keepsTransferNotificationVisible(): Boolean {
        return this == "offering" ||
            this == "connecting" ||
            this == "connected"
    }
}
