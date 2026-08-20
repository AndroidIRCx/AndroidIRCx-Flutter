package com.androidircx.flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

class AndroidIrcxForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForegroundService()
            return START_NOT_STICKY
        }

        createNotificationChannels(this)
        val activeNetworkCount = intent?.getIntExtra(EXTRA_ACTIVE_NETWORK_COUNT, 0) ?: 0
        if (activeNetworkCount <= 0) {
            stopForegroundService()
            return START_NOT_STICKY
        }

        val connectedNetworkCount = intent?.getIntExtra(EXTRA_CONNECTED_NETWORK_COUNT, 0) ?: 0
        val reconnectingNetworkCount = intent?.getIntExtra(EXTRA_RECONNECTING_NETWORK_COUNT, 0) ?: 0
        val errorNetworkCount = intent?.getIntExtra(EXTRA_ERROR_NETWORK_COUNT, 0) ?: 0
        val networkNames = intent?.getStringArrayListExtra(EXTRA_NETWORK_NAMES).orEmpty()
        val activeTransferCount = intent?.getIntExtra(EXTRA_ACTIVE_TRANSFER_COUNT, 0) ?: 0
        val transferSummaries = intent?.getStringArrayListExtra(EXTRA_TRANSFER_SUMMARIES).orEmpty()

        val notification = buildConnectionNotification(
            activeNetworkCount = activeNetworkCount,
            connectedNetworkCount = connectedNetworkCount,
            reconnectingNetworkCount = reconnectingNetworkCount,
            errorNetworkCount = errorNetworkCount,
            networkNames = networkNames,
            activeTransferCount = activeTransferCount,
            transferSummaries = transferSummaries,
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        return START_STICKY
    }

    private fun buildConnectionNotification(
        activeNetworkCount: Int,
        connectedNetworkCount: Int,
        reconnectingNetworkCount: Int,
        errorNetworkCount: Int,
        networkNames: List<String>,
        activeTransferCount: Int,
        transferSummaries: List<String>,
    ): Notification {
        val launchIntent =
            packageManager.getLaunchIntentForPackage(packageName)
                ?: Intent(this, MainActivity::class.java)
        val launchPendingIntent = PendingIntent.getActivity(
            this,
            REQUEST_OPEN_APP,
            launchIntent,
            pendingIntentFlags(),
        )
        val disconnectAllPendingIntent = PendingIntent.getActivity(
            this,
            REQUEST_STOP,
            Intent(this, MainActivity::class.java)
                .setAction(ACTION_DISCONNECT_ALL)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            pendingIntentFlags(),
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_CONNECTION)
        } else {
            Notification.Builder(this)
        }

        val networkSummary = if (networkNames.isEmpty()) {
            "$activeNetworkCount active IRC network(s)"
        } else {
            networkNames.take(3).joinToString(", ")
        }
        val statusSummary =
            "$connectedNetworkCount connected, $reconnectingNetworkCount reconnecting, $errorNetworkCount errors"
        val transferCountSummary = if (activeTransferCount > 0) {
            "$activeTransferCount active transfer(s)"
        } else {
            null
        }
        val transferDetailSummary = transferSummaries.take(3).joinToString("\n")
        val bigText = listOfNotNull(
            networkSummary,
            statusSummary,
            transferCountSummary,
            transferDetailSummary.takeIf { it.isNotBlank() },
        ).joinToString("\n")
        val compactText = if (activeTransferCount > 0) {
            "$networkSummary - $activeTransferCount transfer(s)"
        } else {
            networkSummary
        }

        builder
            .setSmallIcon(R.drawable.ic_stat_androidircx)
            .setContentTitle(getString(R.string.notification_connection_title))
            .setContentText(compactText)
            .setStyle(Notification.BigTextStyle().bigText(bigText))
            .setContentIntent(launchPendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_SERVICE)
            .addAction(
                Notification.Action.Builder(
                    R.drawable.ic_stat_androidircx,
                    getString(R.string.notification_disconnect_all),
                    disconnectAllPendingIntent,
                ).build(),
            )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }

        return builder.build()
    }

    private fun stopForegroundService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    companion object {
        const val CHANNEL_CONNECTION = "irc_connection"
        const val CHANNEL_HIGHLIGHTS = "irc_highlights"
        const val CHANNEL_QUERIES = "irc_queries"
        const val CHANNEL_DCC_TRANSFERS = "irc_dcc_transfers"
        const val CHANNEL_MEDIA_TRANSFERS = "irc_media_transfers"
        const val CHANNEL_ERRORS = "irc_errors"
        const val ACTION_DISCONNECT_ALL = "com.androidircx.flutter.action.DISCONNECT_ALL"

        private const val ACTION_STOP = "com.androidircx.flutter.action.STOP_FOREGROUND"
        private const val ACTION_UPDATE = "com.androidircx.flutter.action.UPDATE_FOREGROUND"
        private const val EXTRA_ACTIVE_NETWORK_COUNT = "activeNetworkCount"
        private const val EXTRA_CONNECTED_NETWORK_COUNT = "connectedNetworkCount"
        private const val EXTRA_RECONNECTING_NETWORK_COUNT = "reconnectingNetworkCount"
        private const val EXTRA_ERROR_NETWORK_COUNT = "errorNetworkCount"
        private const val EXTRA_NETWORK_NAMES = "networkNames"
        private const val EXTRA_ACTIVE_TRANSFER_COUNT = "activeTransferCount"
        private const val EXTRA_TRANSFER_SUMMARIES = "transferSummaries"
        private const val NOTIFICATION_ID = 3101
        private const val REQUEST_OPEN_APP = 3102
        private const val REQUEST_STOP = 3103

        fun updateIntent(
            context: Context,
            activeNetworkCount: Int,
            connectedNetworkCount: Int,
            reconnectingNetworkCount: Int,
            errorNetworkCount: Int,
            networkNames: ArrayList<String>,
            activeTransferCount: Int,
            transferSummaries: ArrayList<String>,
        ): Intent {
            return Intent(context, AndroidIrcxForegroundService::class.java)
                .setAction(ACTION_UPDATE)
                .putExtra(EXTRA_ACTIVE_NETWORK_COUNT, activeNetworkCount)
                .putExtra(EXTRA_CONNECTED_NETWORK_COUNT, connectedNetworkCount)
                .putExtra(EXTRA_RECONNECTING_NETWORK_COUNT, reconnectingNetworkCount)
                .putExtra(EXTRA_ERROR_NETWORK_COUNT, errorNetworkCount)
                .putStringArrayListExtra(EXTRA_NETWORK_NAMES, networkNames)
                .putExtra(EXTRA_ACTIVE_TRANSFER_COUNT, activeTransferCount)
                .putStringArrayListExtra(EXTRA_TRANSFER_SUMMARIES, transferSummaries)
        }

        fun createNotificationChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                return
            }

            val notificationManager =
                context.getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannels(
                listOf(
                    channel(
                        CHANNEL_CONNECTION,
                        context.getString(R.string.notification_channel_connection),
                        context.getString(R.string.notification_channel_connection_description),
                        NotificationManager.IMPORTANCE_LOW,
                    ),
                    channel(
                        CHANNEL_HIGHLIGHTS,
                        context.getString(R.string.notification_channel_highlights),
                        context.getString(R.string.notification_channel_highlights_description),
                        NotificationManager.IMPORTANCE_DEFAULT,
                    ),
                    channel(
                        CHANNEL_QUERIES,
                        context.getString(R.string.notification_channel_queries),
                        context.getString(R.string.notification_channel_queries_description),
                        NotificationManager.IMPORTANCE_DEFAULT,
                    ),
                    channel(
                        CHANNEL_DCC_TRANSFERS,
                        context.getString(R.string.notification_channel_dcc_transfers),
                        context.getString(R.string.notification_channel_dcc_transfers_description),
                        NotificationManager.IMPORTANCE_LOW,
                    ),
                    channel(
                        CHANNEL_MEDIA_TRANSFERS,
                        context.getString(R.string.notification_channel_media_transfers),
                        context.getString(R.string.notification_channel_media_transfers_description),
                        NotificationManager.IMPORTANCE_LOW,
                    ),
                    channel(
                        CHANNEL_ERRORS,
                        context.getString(R.string.notification_channel_errors),
                        context.getString(R.string.notification_channel_errors_description),
                        NotificationManager.IMPORTANCE_HIGH,
                    ),
                ),
            )
        }

        private fun channel(
            id: String,
            name: String,
            description: String,
            importance: Int,
        ): NotificationChannel {
            return NotificationChannel(id, name, importance).apply {
                this.description = description
            }
        }

        private fun pendingIntentFlags(): Int {
            return PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else {
                    0
                }
        }
    }
}
