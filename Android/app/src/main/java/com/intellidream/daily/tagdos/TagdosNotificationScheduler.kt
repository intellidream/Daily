package com.intellidream.daily.tagdos

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.intellidream.daily.DailyApp
import com.intellidream.daily.MainActivity
import com.intellidream.daily.R
import com.intellidream.daily.model.TagDoStream
import java.util.Calendar

/**
 * 100% local daily notification scheduler for TagDoS streams and per-stream groups/clusters.
 * Zero network calls or background egress.
 */
object TagdosNotificationScheduler {
    const val CHANNEL_ID = "daily_tagdos_reminders"
    const val ACTION_FIRE_REMINDER = "com.intellidream.daily.ACTION_TAGDOS_REMINDER"
    const val EXTRA_STREAM_ID = "extra_tagdos_stream_id"
    const val EXTRA_CLUSTER_INDEX = "extra_tagdos_cluster_index"
    const val EXTRA_TITLE = "extra_tagdos_title"
    const val EXTRA_BODY = "extra_tagdos_body"

    private const val PREFS_NAME = "daily_tagdos_alarm_registry"
    private const val KEY_ACTIVE_REQ_CODES = "active_request_codes"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(NotificationManager::class.java) ?: return
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "TagDoS Reminders",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Daily checkpoint reminders for TagDoS streams and groups"
                    enableVibration(true)
                }
                nm.createNotificationChannel(channel)
            }
        }
    }

    fun rescheduleAll(context: Context, explicitStreams: List<TagDoStream>? = null) {
        val appContext = context.applicationContext
        ensureChannel(appContext)

        val alarmManager = appContext.getSystemService(AlarmManager::class.java) ?: return
        val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        // 1. Cancel any previously registered TagDoS alarms
        val oldCodes = prefs.getStringSet(KEY_ACTIVE_REQ_CODES, emptySet()).orEmpty()
        for (codeStr in oldCodes) {
            val reqCode = codeStr.toIntOrNull() ?: continue
            val cancelIntent = Intent(appContext, TagdosReminderReceiver::class.java).apply {
                action = ACTION_FIRE_REMINDER
            }
            val pending = PendingIntent.getBroadcast(
                appContext,
                reqCode,
                cancelIntent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            )
            if (pending != null) {
                alarmManager.cancel(pending)
                pending.cancel()
            }
        }

        val streams = explicitStreams
            ?: runCatching { DailyApp.instance.tagdosRepository.streams.value }.getOrDefault(emptyList())

        val newCodes = mutableSetOf<String>()
        val nowMs = System.currentTimeMillis()

        for (stream in streams) {
            // Stream-level daily reminder
            stream.streamReminder?.let { remEpoch ->
                val triggerAt = nextDailyTriggerMillis(remEpoch, nowMs)
                val reqCode = requestCodeFor(stream.id, -1)
                val title = "TagDoS · ${stream.displayTitle}"
                val driving = stream.drivingPill?.rawText
                val body = if (!driving.isNullOrBlank()) {
                    "Focus now: $driving (${stream.activePills.size} active tags)"
                } else {
                    "Check ${stream.displayTitle}"
                }
                scheduleAlarm(
                    context = appContext,
                    alarmManager = alarmManager,
                    reqCode = reqCode,
                    triggerAtMillis = triggerAt,
                    streamId = stream.id,
                    clusterIndex = -1,
                    title = title,
                    body = body
                )
                newCodes.add(reqCode.toString())
            }

            // Per-cluster daily reminders
            stream.clusters.forEachIndexed { cIdx, cluster ->
                cluster.reminderTime?.let { cRemEpoch ->
                    val triggerAt = nextDailyTriggerMillis(cRemEpoch, nowMs)
                    val reqCode = requestCodeFor(stream.id, cIdx)
                    val previewPills = (cluster.activePills.ifEmpty { cluster.pills })
                        .take(4)
                        .joinToString(" / ") { it.rawText }
                    val title = "TagDoS · ${stream.displayTitle}"
                    val body = if (previewPills.isBlank()) "Group reminder" else "Group: $previewPills"
                    scheduleAlarm(
                        context = appContext,
                        alarmManager = alarmManager,
                        reqCode = reqCode,
                        triggerAtMillis = triggerAt,
                        streamId = stream.id,
                        clusterIndex = cIdx,
                        title = title,
                        body = body
                    )
                    newCodes.add(reqCode.toString())
                }
            }
        }

        prefs.edit().putStringSet(KEY_ACTIVE_REQ_CODES, newCodes).apply()
    }

    private fun scheduleAlarm(
        context: Context,
        alarmManager: AlarmManager,
        reqCode: Int,
        triggerAtMillis: Long,
        streamId: String,
        clusterIndex: Int,
        title: String,
        body: String
    ) {
        val intent = Intent(context, TagdosReminderReceiver::class.java).apply {
            action = ACTION_FIRE_REMINDER
            putExtra(EXTRA_STREAM_ID, streamId)
            putExtra(EXTRA_CLUSTER_INDEX, clusterIndex)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
        }
        val pending = PendingIntent.getBroadcast(
            context,
            reqCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        runCatching {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pending)
        }
    }

    private fun nextDailyTriggerMillis(savedEpoch: Long, nowMs: Long): Long {
        val refCal = Calendar.getInstance().apply { timeInMillis = savedEpoch }
        val hour = refCal.get(Calendar.HOUR_OF_DAY)
        val minute = refCal.get(Calendar.MINUTE)

        val target = Calendar.getInstance().apply {
            timeInMillis = nowMs
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (target.timeInMillis <= nowMs + 2_000L) {
            target.add(Calendar.DAY_OF_YEAR, 1)
        }
        return target.timeInMillis
    }

    private fun requestCodeFor(streamId: String, clusterIndex: Int): Int {
        return ("tagdos:$streamId:$clusterIndex".hashCode() and 0x7FFFFFFF)
    }
}

class TagdosReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action == TagdosNotificationScheduler.ACTION_FIRE_REMINDER) {
            val streamId = intent.getStringExtra(TagdosNotificationScheduler.EXTRA_STREAM_ID).orEmpty()
            val clusterIndex = intent.getIntExtra(TagdosNotificationScheduler.EXTRA_CLUSTER_INDEX, -1)
            val title = intent.getStringExtra(TagdosNotificationScheduler.EXTRA_TITLE) ?: "TagDoS Reminder"
            val body = intent.getStringExtra(TagdosNotificationScheduler.EXTRA_BODY) ?: "Check your active tags"

            showNotification(context, streamId, clusterIndex, title, body)
            // Schedule next day's daily occurrence
            TagdosNotificationScheduler.rescheduleAll(context)
        } else if (
            action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_TIME_CHANGED ||
            action == Intent.ACTION_TIMEZONE_CHANGED
        ) {
            TagdosNotificationScheduler.rescheduleAll(context)
        }
    }

    private fun showNotification(
        context: Context,
        streamId: String,
        clusterIndex: Int,
        title: String,
        body: String
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) return
        }

        TagdosNotificationScheduler.ensureChannel(context)

        val deepLinkUri = buildString {
            append("daily://tagdos")
            if (streamId.isNotBlank()) {
                append("?streamId=").append(Uri.encode(streamId))
                if (clusterIndex >= 0) {
                    append("&clusterIndex=").append(clusterIndex)
                }
            }
        }

        val tapIntent = Intent(context, MainActivity::class.java).apply {
            action = "com.intellidream.daily.OPEN_TAGDOS_${streamId}_$clusterIndex"
            data = Uri.parse(deepLinkUri)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_TAGDOS)
        }
        val reqCode = ("notif:$streamId:$clusterIndex".hashCode() and 0x7FFFFFFF)
        val contentPending = PendingIntent.getActivity(
            context,
            reqCode,
            tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, TagdosNotificationScheduler.CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(contentPending)
            .build()

        runCatching {
            NotificationManagerCompat.from(context).notify(reqCode, notification)
        }
    }
}
