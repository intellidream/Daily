package com.intellidream.daily.network

import com.intellidream.daily.model.HealthTelemetryRecord
import com.intellidream.daily.model.VitalMetricRecord
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class HealthRemoteService(
    private val clientManager: SupabaseClientManager = SupabaseClientManager
) {
    suspend fun pushTelemetry(records: List<HealthTelemetryRecord>): Boolean = withContext(Dispatchers.IO) {
        try {
            if (records.isEmpty()) return@withContext true
            clientManager.client.postgrest["health_telemetry"].insert(records)
            true
        } catch (_: Exception) {
            false
        }
    }

    suspend fun fetchTelemetryBetween(
        userId: String,
        startTimeEpochMs: Long,
        endTimeEpochMs: Long
    ): List<HealthTelemetryRecord> = withContext(Dispatchers.IO) {
        try {
            clientManager.client.postgrest["health_telemetry"]
                .select {
                    filter {
                        eq("user_id", userId)
                        gte("start_time", startTimeEpochMs)
                        lte("start_time", endTimeEpochMs)
                    }
                }
                .decodeList<HealthTelemetryRecord>()
        } catch (_: Exception) {
            emptyList()
        }
    }

    suspend fun pushVitals(vitals: List<VitalMetricRecord>): Boolean = withContext(Dispatchers.IO) {
        try {
            if (vitals.isEmpty()) return@withContext true
            clientManager.client.postgrest["vitals"].upsert(vitals)
            true
        } catch (_: Exception) {
            false
        }
    }

    suspend fun fetchVitalsForDate(
        userId: String,
        date: String
    ): List<VitalMetricRecord> = withContext(Dispatchers.IO) {
        try {
            clientManager.client.postgrest["vitals"]
                .select {
                    filter {
                        eq("user_id", userId)
                        eq("date", date)
                    }
                }
                .decodeList<VitalMetricRecord>()
        } catch (_: Exception) {
            emptyList()
        }
    }

    suspend fun fetchVitalsBetween(
        userId: String,
        startDate: String,
        endDate: String
    ): List<VitalMetricRecord> = withContext(Dispatchers.IO) {
        try {
            clientManager.client.postgrest["vitals"]
                .select {
                    filter {
                        eq("user_id", userId)
                        gte("date", startDate)
                        lte("date", endDate)
                    }
                }
                .decodeList<VitalMetricRecord>()
        } catch (_: Exception) {
            emptyList()
        }
    }
}
