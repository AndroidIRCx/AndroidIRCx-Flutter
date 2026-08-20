package com.androidircx.flutter

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private var pendingNotificationAction: String? = null
    private var pendingDccFilePickerResult: MethodChannel.Result? = null

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
                    "showNotification" -> {
                        showUserNotification(call.arguments)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("foreground_service_error", error.message, null)
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DCC_FILE_PICKER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFile" -> openDccFilePicker(result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == DCC_FILE_PICKER_REQUEST_CODE) {
            val result = pendingDccFilePickerResult ?: return
            pendingDccFilePickerResult = null
            if (resultCode != Activity.RESULT_OK) {
                result.success(null)
                return
            }

            val uri = data?.data
            if (uri == null) {
                result.success(null)
                return
            }

            try {
                result.success(copyDccSendFileToCache(uri))
            } catch (error: Exception) {
                result.error("dcc_file_picker_error", error.message, null)
            }
            return
        }

        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun captureNotificationAction(intent: Intent?) {
        if (intent?.action == AndroidIrcxForegroundService.ACTION_DISCONNECT_ALL) {
            pendingNotificationAction = "disconnectAll"
        }
    }

    private fun openDccFilePicker(result: MethodChannel.Result) {
        if (pendingDccFilePickerResult != null) {
            result.error("dcc_file_picker_busy", "A file picker is already open.", null)
            return
        }

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
        if (intent.resolveActivity(packageManager) == null) {
            result.success(null)
            return
        }

        pendingDccFilePickerResult = result
        startActivityForResult(intent, DCC_FILE_PICKER_REQUEST_CODE)
    }

    private fun copyDccSendFileToCache(uri: Uri): String {
        val fileName = sanitizeDccFileName(displayNameForUri(uri))
        val directory = File(cacheDir, "dcc-send")
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("Unable to create DCC cache directory.")
        }

        val destination = File(
            directory,
            "${System.currentTimeMillis()}-$fileName",
        )
        val inputStream = contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("Unable to open selected file.")
        inputStream.use { input ->
            FileOutputStream(destination).use { output ->
                input.copyTo(output)
            }
        }
        return destination.absolutePath
    }

    private fun displayNameForUri(uri: Uri): String {
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) {
                    val name = cursor.getString(index)
                    if (!name.isNullOrBlank()) {
                        return name
                    }
                }
            }
        }
        return "dcc-send-file"
    }

    private fun sanitizeDccFileName(fileName: String): String {
        val sanitized = fileName.trim().map { char ->
            if (char.isLetterOrDigit() || char == '.' || char == '_' || char == '-') {
                char
            } else {
                '_'
            }
        }.joinToString("")
        return sanitized.ifEmpty { "dcc-send-file" }
    }

    private fun updateForegroundService(arguments: Any?) {
        val payload = arguments as? Map<*, *> ?: emptyMap<String, Any?>()
        val activeNetworkCount = payload.intValue("activeNetworkCount")
        val activeTransferCount = payload.intValue("activeTransferCount")
        if (activeNetworkCount <= 0 && activeTransferCount <= 0) {
            stopService(Intent(this, AndroidIrcxForegroundService::class.java))
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
            context = this,
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
            startForegroundService(intent)
        } else {
            startService(intent)
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

    private fun showUserNotification(arguments: Any?) {
        AndroidIrcxForegroundService.createNotificationChannels(this)
        val payload = arguments as? Map<*, *> ?: return
        val title = (payload["title"] as? String)?.takeIf { it.isNotBlank() }
            ?: "AndroidIRCx"
        val body = (payload["body"] as? String)?.takeIf { it.isNotBlank() }
            ?: return
        val rawId = (payload["id"] as? String)?.takeIf { it.isNotBlank() }
            ?: "$title:$body"
        val channelId = notificationChannelId(payload["channelId"] as? String)
        val launchIntent =
            packageManager.getLaunchIntentForPackage(packageName)
                ?: Intent(this, MainActivity::class.java)
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val contentIntent = PendingIntent.getActivity(
            this,
            REQUEST_USER_NOTIFICATION_OPEN,
            launchIntent,
            pendingIntentFlags(),
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(R.drawable.ic_stat_androidircx)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setOnlyAlertOnce(false)
            .setCategory(notificationCategory(channelId))

        val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(userNotificationId(rawId), builder.build())
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

    companion object {
        private const val FOREGROUND_SERVICE_CHANNEL =
            "androidircx/foreground_connection_service"
        private const val DCC_FILE_PICKER_CHANNEL = "androidircx/dcc_file_picker"
        private const val DCC_FILE_PICKER_REQUEST_CODE = 22070
        private const val REQUEST_USER_NOTIFICATION_OPEN = 22071
        private const val USER_NOTIFICATION_BASE_ID = 42000
    }
}
