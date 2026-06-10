package app.phoneagent.phone_agent

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

class AgentRunForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForegroundCompat()
            return START_NOT_STICKY
        }

        val runId = intent?.getStringExtra(EXTRA_RUN_ID) ?: "agent-run"
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Phone Agent 正在运行"
        val detail = intent?.getStringExtra(EXTRA_DETAIL) ?: "正在处理当前会话"
        ensureNotificationChannel()
        val notification = buildNotification(title, detail, runId)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_STICKY
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(NotificationManager::class.java)
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) {
            return
        }
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Phone Agent 会话运行",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Phone Agent 在后台继续处理运行中的会话"
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(title: String, detail: String, runId: String): Notification {
        val launchIntent =
            packageManager.getLaunchIntentForPackage(packageName)
                ?: Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stopIntent = Intent(this, AgentRunForegroundService::class.java).apply {
            action = ACTION_STOP
            putExtra(EXTRA_RUN_ID, runId)
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle(title)
            .setContentText(detail)
            .setStyle(Notification.BigTextStyle().bigText(detail))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .addAction(0, "停止后台运行", stopPendingIntent)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "phone_agent_running_session"
        private const val NOTIFICATION_ID = 11001
        private const val ACTION_START = "app.phoneagent.phone_agent.agent_run.START"
        private const val ACTION_STOP = "app.phoneagent.phone_agent.agent_run.STOP"
        private const val EXTRA_RUN_ID = "run_id"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_DETAIL = "detail"

        fun start(context: Context, runId: String, title: String, detail: String) {
            val intent = Intent(context, AgentRunForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_RUN_ID, runId)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_DETAIL, detail)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, AgentRunForegroundService::class.java)
            context.stopService(intent)
        }
    }
}
