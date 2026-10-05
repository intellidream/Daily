package com.intellidream.daily.health

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.intellidream.daily.DailyApp
import com.intellidream.daily.database.entity.HealthTelemetryEntity
import com.intellidream.daily.glance.WidgetUpdateHelper
import com.intellidream.daily.model.AuthSessionState
import kotlinx.coroutines.flow.firstOrNull
import java.util.Calendar
import java.util.Date
import java.util.concurrent.TimeUnit

class HealthSyncWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        try {
            val app = DailyApp.instance
            val state = app.authRepository.sessionState.firstOrNull()
            val uid = (state as? AuthSessionState.Authenticated)?.profile?.id
            if (uid.isNullOrEmpty() || uid == "guest") {
                return Result.success()
            }

            val healthRepo = app.healthRepository
            healthRepo.currentUserId = uid

            // If Health Connect is available and authorized, pull recent telemetry
            if (healthRepo.healthConnectManager.isAvailable && healthRepo.healthConnectManager.hasAnyPermissions()) {
                val today = Date()
                val cal = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -1) }
                val yesterday = cal.time

                val todayTelem = healthRepo.healthConnectManager.fetchTelemetryForDate(today, uid)
                val yesterdayTelem = healthRepo.healthConnectManager.fetchTelemetryForDate(yesterday, uid)

                val combined = (todayTelem + yesterdayTelem).distinctBy { it.externalId ?: it.id }
                if (combined.isNotEmpty()) {
                    app.dailyDatabase.healthTelemetryDao().insertRecords(
                        combined.map { HealthTelemetryEntity.fromRecord(it) }
                    )
                }
            }

            // Sync any unsynced telemetry and vitals to Supabase cloud
            healthRepo.syncUnsyncedTelemetry()
            healthRepo.syncUnsyncedVitals()

            // Refresh Glance widgets
            WidgetUpdateHelper.updateAllWidgets(applicationContext)

            return Result.success()
        } catch (e: Exception) {
            android.util.Log.w("HealthSyncWorker", "Periodic health sync encountered error", e)
            return Result.retry()
        }
    }

    companion object {
        private const val WORK_NAME = "HealthPeriodicSyncWorker"

        fun enqueuePeriodicSync(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val request = PeriodicWorkRequestBuilder<HealthSyncWorker>(
                repeatInterval = 1,
                repeatIntervalTimeUnit = TimeUnit.HOURS,
                flexTimeInterval = 15,
                flexTimeIntervalUnit = TimeUnit.MINUTES
            )
                .setConstraints(constraints)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )
        }
    }
}
