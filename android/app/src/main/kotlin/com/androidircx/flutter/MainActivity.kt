package com.androidircx.flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
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

    override fun provideFlutterEngine(context: Context): FlutterEngine {
        return AndroidIrcxEngineManager.ensureEngine(context)
    }

    override fun shouldDestroyEngineWithHost(): Boolean {
        return false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        AndroidIrcxEngineManager.attachForegroundChannel(this, flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DCC_FILE_PICKER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFile" -> openDccFilePicker(result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SCREEN_SECURITY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    val secure = call.argument<Boolean>("secure") ?: false
                    runOnUiThread {
                        if (secure) {
                            window.setFlags(
                                WindowManager.LayoutParams.FLAG_SECURE,
                                WindowManager.LayoutParams.FLAG_SECURE,
                            )
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                    }
                    result.success(null)
                }
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
        AndroidIrcxEngineManager.captureNotificationAction(intent)
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

    companion object {
        private const val DCC_FILE_PICKER_CHANNEL = "androidircx/dcc_file_picker"
        private const val DCC_FILE_PICKER_REQUEST_CODE = 22070
        private const val SCREEN_SECURITY_CHANNEL = "androidircx/screen_security"
    }
}
