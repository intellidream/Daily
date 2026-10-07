package com.intellidream.daily.network

import com.intellidream.daily.model.DailyHealthSummaryPayload
import com.intellidream.daily.model.DeviceSource
import com.intellidream.daily.model.HealthDailySummaryRecord
import com.intellidream.daily.model.HealthTelemetryRecord
import com.intellidream.daily.model.VitalMetricRecord
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
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
                clientManager.client.postgrest["health_telemetry"].upsert(chunk)
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
        // Deprecated: V3 architecture stores all data in health_telemetry and health_daily_summary
        true
    }

    suspend fun fetchVitalsForDate(
        userId: String,
        date: String
    ): List<VitalMetricRecord> = withContext(Dispatchers.IO) {
        // Deprecated: V3 architecture uses health_daily_summary
        emptyList()
    }

    suspend fun fetchVitalsBetween(
        userId: String,
        startDate: String,
        endDate: String
    ): List<VitalMetricRecord> = withContext(Dispatchers.IO) {
        // Deprecated: V3 architecture uses health_daily_summary
        emptyList()
    }

    suspend fun fetchDailySummary(
        userId: String,
        date: String
    ): DailyHealthSummaryPayload? = withContext(Dispatchers.IO) {
        try {
            val response = clientManager.client.postgrest["health_daily_summary"]
                .select {
                    filter {
                        eq("user_id", userId)
                        eq("local_date", date)
                    }
                    limit(1)
                }
                .decodeSingleOrNull<HealthDailySummaryRecord>()
            response?.summary
        } catch (e: Exception) {
            android.util.Log.e("HealthRemoteService", "Failed to fetch/decode daily summary for $date: ${e.message}", e)
            null
        }
    }

    suspend fun fetchDailySummariesBetween(
        userId: String,
        startDate: String,
        endDate: String
    ): List<HealthDailySummaryRecord> = withContext(Dispatchers.IO) {
        try {
            clientManager.client.postgrest["health_daily_summary"]
                .select {
                    filter {
                        eq("user_id", userId)
                        gte("local_date", startDate)
                        lte("local_date", endDate)
                    }
                    order("local_date", Order.ASCENDING)
                }
                .decodeList<HealthDailySummaryRecord>()
        } catch (e: Exception) {
            android.util.Log.e("HealthRemoteService", "Failed to fetch daily summaries between $startDate and $endDate: ${e.message}", e)
            emptyList()
        }
    }

    suspend fun triggerCanonicalEngine(
        userId: String,
        date: String = "",
        processDirty: Boolean = false
    ): Boolean = withContext(Dispatchers.IO) {
        if (userId.isEmpty() || userId == "local_user") return@withContext false
        try {
            val url = "${SupabaseClientManager.SUPABASE_URL}/functions/v1/health-engine"
            val conn = (java.net.URI.create(url).toURL().openConnection() as java.net.HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 5000
                readTimeout = 5000
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("apikey", SupabaseClientManager.SUPABASE_ANON_KEY)
                setRequestProperty("Authorization", "Bearer ${SupabaseClientManager.SUPABASE_ANON_KEY}")
                doOutput = true
            }
            val body = if (processDirty && date.isEmpty()) {
                """{"user_id":"$userId","process_dirty":true}"""
            } else if (processDirty) {
                """{"user_id":"$userId","date":"$date","process_dirty":true}"""
            } else {
                """{"user_id":"$userId","date":"$date"}"""
            }
            conn.outputStream.use { os ->
                os.write(body.toByteArray(Charsets.UTF_8))
            }
            val code = conn.responseCode
            conn.disconnect()
            code in 200..299
        } catch (_: Exception) {
            false
        }
    }
}

