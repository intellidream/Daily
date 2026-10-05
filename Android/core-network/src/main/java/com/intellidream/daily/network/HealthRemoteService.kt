package com.intellidream.daily.network

import com.intellidream.daily.model.DeviceSource
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
            val realRecords = records.filter {
                val dev = it.sourceDevice
                dev == null || !DeviceSource.from(dev).isVirtualEngine
            }
            if (realRecords.isEmpty()) return@withContext true
            
            for (chunk in realRecords.chunked(200)) {
                clientManager.client.postgrest["health_telemetry"].insert(chunk)
            }
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
            val startIso = java.time.Instant.ofEpochMilli(startTimeEpochMs).toString()
            val endIso = java.time.Instant.ofEpochMilli(endTimeEpochMs).toString()
            clientManager.client.postgrest["health_telemetry"]
                .select {
                    filter {
                        eq("user_id", userId)
                        gte("start_time", startIso)
                        lte("start_time", endIso)
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
            clientManager.client.postgrest["vitals"].upsert(vitals) {
                onConflict = "user_id,date,type"
            }
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
