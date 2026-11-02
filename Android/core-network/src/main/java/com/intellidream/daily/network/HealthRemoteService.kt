package com.intellidream.daily.network

import com.intellidream.daily.model.DailyHealthSummaryPayload
import com.intellidream.daily.model.DeviceSource
import com.intellidream.daily.model.HealthDailySummaryRecord
import com.intellidream.daily.model.HealthDailyVitalsRecord
import com.intellidream.daily.model.HealthIntradayHeartRateRecord
import com.intellidream.daily.model.HealthSleepSessionRecord
import com.intellidream.daily.model.HealthSourceRecord
import com.intellidream.daily.model.HealthTelemetryRecord
import com.intellidream.daily.model.VitalMetricRecord
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

class HealthRemoteService(
    private val clientManager: SupabaseClientManager = SupabaseClientManager
) {
    suspend fun pushTelemetry(records: List<HealthTelemetryRecord>): Boolean = withContext(Dispatchers.IO) {
        // Lean Architecture v2: legacy health_telemetry is retired (strictly 0 rows).
        true
    }

    suspend fun fetchTelemetryBetween(
        userId: String,
        startTimeEpochMs: Long,
        endTimeEpochMs: Long
    ): List<HealthTelemetryRecord> = withContext(Dispatchers.IO) {
        emptyList()
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
        if (!clientManager.ensureSessionReady()) return@withContext null
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
        if (!clientManager.ensureSessionReady()) return@withContext emptyList()
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
        clientManager.ensureSessionReady()
        try {
            val url = "${SupabaseClientManager.SUPABASE_URL}/functions/v1/health-engine"
            val body = if (processDirty && date.isEmpty()) {
                """{"user_id":"$userId","process_dirty":true}"""
            } else if (processDirty) {
                """{"user_id":"$userId","date":"$date","process_dirty":true}"""
            } else {
                """{"user_id":"$userId","date":"$date"}"""
            }
            val token = clientManager.currentAccessTokenOrAnonKey()
            val req = Request.Builder()
                .url(url)
                .header("Content-Type", "application/json")
                .header("apikey", SupabaseClientManager.SUPABASE_ANON_KEY)
                .header("Authorization", "Bearer $token")
                .post(body.toRequestBody("application/json".toMediaType()))
                .build()
            SupabaseClientManager.okHttpClient.newCall(req).execute().use { resp ->
                resp.code in 200..299
            }
        } catch (e: Exception) {
            android.util.Log.w("HealthRemoteService", "Failed to trigger canonical engine: ${e.message}")
            false
        }
    }

    suspend fun fetchSleepSessions(
        userId: String,
        date: String
    ): List<HealthSleepSessionRecord> = withContext(Dispatchers.IO) {
        if (!clientManager.ensureSessionReady()) return@withContext emptyList()
        try {
            clientManager.client.postgrest["health_sleep_sessions"]
                .select {
                    filter {
                        eq("user_id", userId)
                        eq("local_date", date)
                    }
                    order("source_priority", Order.ASCENDING)
                }
                .decodeList<HealthSleepSessionRecord>()
        } catch (e: Exception) {
            android.util.Log.w("HealthRemoteService", "Failed to fetch sleep sessions: ${e.message}")
            emptyList()
        }
    }

    suspend fun fetchSleepSessionsBetween(
        userId: String,
        startDate: String,
        endDate: String
    ): List<HealthSleepSessionRecord> = withContext(Dispatchers.IO) {
        if (!clientManager.ensureSessionReady()) return@withContext emptyList()
        try {
            clientManager.client.postgrest["health_sleep_sessions"]
                .select {
                    filter {
                        eq("user_id", userId)
                        gte("local_date", startDate)
                        lte("local_date", endDate)
                    }
                    order("local_date", Order.ASCENDING)
                    order("source_priority", Order.ASCENDING)
                }
                .decodeList<HealthSleepSessionRecord>()
        } catch (e: Exception) {
            android.util.Log.w("HealthRemoteService", "Failed to fetch sleep sessions between $startDate and $endDate: ${e.message}")
            emptyList()
        }
    }

    suspend fun fetchDailyVitals(
        userId: String,
        date: String
    ): List<HealthDailyVitalsRecord> = withContext(Dispatchers.IO) {
        if (!clientManager.ensureSessionReady()) return@withContext emptyList()
        try {
            clientManager.client.postgrest["health_daily_vitals"]
                .select {
                    filter {
                        eq("user_id", userId)
                        eq("local_date", date)
                    }
                }
                .decodeList<HealthDailyVitalsRecord>()
        } catch (e: Exception) {
            android.util.Log.w("HealthRemoteService", "Failed to fetch daily vitals: ${e.message}")
            emptyList()
        }
    }

    suspend fun fetchDailyVitalsBetween(
        userId: String,
        startDate: String,
        endDate: String
    ): List<HealthDailyVitalsRecord> = withContext(Dispatchers.IO) {
        if (!clientManager.ensureSessionReady()) return@withContext emptyList()
        try {
            clientManager.client.postgrest["health_daily_vitals"]
                .select {
                    filter {
                        eq("user_id", userId)
                        gte("local_date", startDate)
                        lte("local_date", endDate)
                    }
                    order("local_date", Order.ASCENDING)
                }
                .decodeList<HealthDailyVitalsRecord>()
        } catch (e: Exception) {
            android.util.Log.w("HealthRemoteService", "Failed to fetch daily vitals between $startDate and $endDate: ${e.message}")
            emptyList()
        }
    }

    suspend fun fetchIntradayHeartRate(
        userId: String,
        date: String
    ): List<HealthIntradayHeartRateRecord> = withContext(Dispatchers.IO) {
        if (!clientManager.ensureSessionReady()) return@withContext emptyList()
        try {
            clientManager.client.postgrest["health_intraday_heart_rate"]
                .select {
                    filter {
                        eq("user_id", userId)
                        eq("local_date", date)
                    }
                    order("bucket_minute", Order.ASCENDING)
                }
                .decodeList<HealthIntradayHeartRateRecord>()
        } catch (e: Exception) {
            android.util.Log.w("HealthRemoteService", "Failed to fetch intraday heart rate: ${e.message}")
            emptyList()
        }
    }

    suspend fun fetchHealthSources(
        userId: String
    ): List<HealthSourceRecord> = withContext(Dispatchers.IO) {
        if (!clientManager.ensureSessionReady()) return@withContext emptyList()
        try {
            clientManager.client.postgrest["health_sources"]
                .select {
                    filter {
                        eq("user_id", userId)
                    }
                    order("priority_sleep", Order.ASCENDING)
                }
                .decodeList<HealthSourceRecord>()
        } catch (e: Exception) {
            android.util.Log.w("HealthRemoteService", "Failed to fetch health sources: ${e.message}")
            emptyList()
        }
    }

    suspend fun pushSleepSession(session: HealthSleepSessionRecord): Boolean = withContext(Dispatchers.IO) {
        if (!clientManager.ensureSessionReady()) {
            android.util.Log.w("HealthRemoteService", "Skipping pushSleepSession: authenticated session not ready")
            return@withContext false
        }
        try {
            clientManager.client.postgrest["health_sleep_sessions"].upsert(session) {
                onConflict = "user_id,local_date,session_type,source_device_key"
            }
            true
        } catch (e: Exception) {
            android.util.Log.w("HealthRemoteService", "Failed to push sleep session: ${e.message}")
            false
        }
    }

    suspend fun pushDailyVitals(vitals: HealthDailyVitalsRecord): Boolean = withContext(Dispatchers.IO) {
        if (!clientManager.ensureSessionReady()) {
            android.util.Log.w("HealthRemoteService", "Skipping pushDailyVitals: authenticated session not ready")
            return@withContext false
        }
        try {
            clientManager.client.postgrest["health_daily_vitals"].upsert(vitals) {
                onConflict = "user_id,local_date,source_device_key"
            }
            true
        } catch (e: Exception) {
            android.util.Log.w("HealthRemoteService", "Failed to push daily vitals: ${e.message}")
            false
        }
    }

    suspend fun pushIntradayHeartRate(buckets: List<HealthIntradayHeartRateRecord>): Boolean = withContext(Dispatchers.IO) {
        if (buckets.isEmpty()) return@withContext true
        if (!clientManager.ensureSessionReady()) {
            android.util.Log.w("HealthRemoteService", "Skipping pushIntradayHeartRate: authenticated session not ready")
            return@withContext false
        }
        try {
            for (chunk in buckets.chunked(100)) {
                clientManager.client.postgrest["health_intraday_heart_rate"].upsert(chunk) {
                    onConflict = "user_id,local_date,source_device_key,bucket_minute"
                }
            }
            true
        } catch (e: Exception) {
            android.util.Log.w("HealthRemoteService", "Failed to push intraday heart rate buckets: ${e.message}")
            false
        }
    }

    suspend fun registerHealthSource(source: HealthSourceRecord): Boolean = withContext(Dispatchers.IO) {
        if (!clientManager.ensureSessionReady()) return@withContext false
        try {
            clientManager.client.postgrest["health_sources"].upsert(source) {
                onConflict = "id"
            }
            true
        } catch (e: Exception) {
            android.util.Log.w("HealthRemoteService", "Failed to register health source: ${e.message}")
            false
        }
    }
}

