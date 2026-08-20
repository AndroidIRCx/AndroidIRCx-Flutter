package com.androidircx.flutter

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
        if (activeNetworkCount <= 0) {
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
                payload.intValue("activeTransferCount"),
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

    private fun Map<*, *>.progressSummary(status: String): String {
        val totalBytes = longValueOrNull("totalBytes")
        val bytesTransferred = longValue("bytesTransferred")
        if (totalBytes != null && totalBytes > 0L) {
            val percent = ((bytesTransferred * 100L) / totalBytes).coerceIn(0L, 100L)
            return "$percent%"
        }
        if (bytesTransferred > 0L) {
            return "$bytesTransferred bytes"
        }
        return status
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
    }
}
