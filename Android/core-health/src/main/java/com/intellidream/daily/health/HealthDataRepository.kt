package com.intellidream.daily.health

import android.content.Context
import com.intellidream.daily.database.DailyDatabase
import com.intellidream.daily.database.dao.HealthDailySummaryDao
import com.intellidream.daily.database.dao.HealthTelemetryDao
import com.intellidream.daily.database.dao.VitalMetricDao
import com.intellidream.daily.database.entity.HealthDailySummaryEntity
import com.intellidream.daily.database.entity.HealthTelemetryEntity
import com.intellidream.daily.database.entity.VitalMetricEntity
import com.intellidream.daily.model.BreathingProtocol
import com.intellidream.daily.model.CanonicalCardiovascularSummary
import com.intellidream.daily.model.DailyHealthSummaryPayload
import com.intellidream.daily.model.DailyMetricTrendPoint
import com.intellidream.daily.model.DeviceColorPalette
import com.intellidream.daily.model.DeviceSource
import com.intellidream.daily.model.HealthDailySummaryRecord
import com.intellidream.daily.model.HealthDailyVitalsRecord
import com.intellidream.daily.model.HealthIntradayHeartRateRecord
import com.intellidream.daily.model.HealthSleepSessionRecord
import com.intellidream.daily.model.HealthSourceRecord
import com.intellidream.daily.model.HealthMetricType
import com.intellidream.daily.model.HealthSubTab
import com.intellidream.daily.model.HealthTelemetryRecord
import com.intellidream.daily.model.HeartRateZone
import com.intellidream.daily.model.HourlyStepBucket
import com.intellidream.daily.model.IntradayHeartRatePoint
import com.intellidream.daily.model.MonkeyMood
import com.intellidream.daily.model.NapSession
import com.intellidream.daily.model.SleepAIContext
import com.intellidream.daily.model.SleepActionableTip
import com.intellidream.daily.model.SleepRecoveryVerdict
import com.intellidream.daily.model.SleepSession
import com.intellidream.daily.model.IntradayStressPoint
import com.intellidream.daily.model.StressAnalysisResult
import com.intellidream.daily.model.StressLevel
import com.intellidream.daily.model.VitalMetricRecord
import com.intellidream.daily.network.HealthRemoteService
import com.intellidream.daily.network.SupabaseClientManager
import io.github.jan.supabase.postgrest.query.filter.FilterOperator
import io.github.jan.supabase.realtime.PostgresAction
import io.github.jan.supabase.realtime.RealtimeChannel
import io.github.jan.supabase.realtime.channel
import io.github.jan.supabase.realtime.postgresChangeFlow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.UUID
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.round

/**
 * Result data class for daily steps calculation.
 */
data class DailyStepsResult(
    val totalSteps: Int,
    val hourlyBuckets: List<HourlyStepBucket>,
    val activeCalories: Double,
    val sourceDeviceUsed: String? = null
)

/**
 * Central Health Data Repository for Android DayOne.
 * 1:1 architectural parity with iOS DailyCore's HealthDataService.
 * Coordinates Health Connect, Room SQLite local cache, Supabase cloud sync,
 * clustering, cardiovascular curve generation, and 7-day trend points.
 */
class HealthDataRepository(
    private val context: Context,
    private val telemetryDao: HealthTelemetryDao,
    private val vitalsDao: VitalMetricDao,
    private val summaryDao: HealthDailySummaryDao = DailyDatabase.getDatabase(context).healthDailySummaryDao(),
    private val remoteService: HealthRemoteService = HealthRemoteService(),
    val healthConnectManager: HealthConnectManager = HealthConnectManager(context),
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
) {
    private var activeLoadJob: kotlinx.coroutines.Job? = null
    private var isSyncingHistory: Boolean = false
    private val lastEngineInvocation = java.util.concurrent.ConcurrentHashMap<String, Long>()
    private val lastEnginePayloadFingerprint = java.util.concurrent.ConcurrentHashMap<String, String>()
    private var lastKnownTodayStart: Long = getStartOfDay(System.currentTimeMillis())
    private var realtimeChannel: RealtimeChannel? = null
    private var realtimeDebounceJob: kotlinx.coroutines.Job? = null
    @Volatile private var pendingRealtimeSourcesRefresh: Boolean = false
    @Volatile private var lastLocalUploadCompletedAtMs: Long = 0L
    @Volatile private var lastSourcesFetchAtMs: Long = 0L
    private val lastUploadedSleepFpByDate = java.util.concurrent.ConcurrentHashMap<String, String>()
    private val lastUploadedVitalsFpByDate = java.util.concurrent.ConcurrentHashMap<String, String>()
    private val lastUploadedHrFpByDate = java.util.concurrent.ConcurrentHashMap<String, String>()
    private val registeredSourceIdsInSession = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()

    private data class TrendsRemoteCacheEntry(
        val cacheKey: String,
        val fetchedAtMs: Long,
        val summaries: List<HealthDailySummaryRecord>,
        val sleep: List<HealthSleepSessionRecord>,
        val vitals: List<HealthDailyVitalsRecord>
    )
    @Volatile private var trendsRemoteCache: TrendsRemoteCacheEntry? = null

    var currentUserId: String = "local_user"
        set(value) {
            val changed = field != value
            field = value
            if (changed) {
                trendsRemoteCache = null
                lastSourcesFetchAtMs = 0L
                registeredSourceIdsInSession.clear()
                lastUploadedSleepFpByDate.clear()
                lastUploadedVitalsFpByDate.clear()
                lastUploadedHrFpByDate.clear()
            }
            if (changed && value != "local_user") {
                setupRealtimeSubscription()
                loadDataForSelectedDate(forceRefresh = true)
                scope.launch {
                    syncMissingHistoricalDataIfNeeded()
                }
            }
        }

    // MARK: - Published State

    private val _activeSubTab = MutableStateFlow(HealthSubTab.OVERVIEW)
    val activeSubTab: StateFlow<HealthSubTab> = _activeSubTab.asStateFlow()

    private val _selectedDate = MutableStateFlow(getStartOfDay(System.currentTimeMillis()))
    val selectedDate: StateFlow<Long> = _selectedDate.asStateFlow()

    private val _selectedDeviceSource = MutableStateFlow<DeviceSource?>(null)
    val selectedDeviceSource: StateFlow<DeviceSource?> = _selectedDeviceSource.asStateFlow()

    private val _selectedDeviceFilter = MutableStateFlow<String?>(null)
    val selectedDeviceFilter: StateFlow<String?> = _selectedDeviceFilter.asStateFlow()

    private val _availableSources = MutableStateFlow<List<DeviceSource>>(emptyList())
    val availableSources: StateFlow<List<DeviceSource>> = _availableSources.asStateFlow()

    private val _availableDevices = MutableStateFlow<List<String>>(emptyList())
    val availableDevices: StateFlow<List<String>> = _availableDevices.asStateFlow()

    private val _configurableSources = MutableStateFlow<List<HealthSourceRecord>>(emptyList())
    val configurableSources: StateFlow<List<HealthSourceRecord>> = _configurableSources.asStateFlow()

    private val _isSavingPriorityOrder = MutableStateFlow(false)
    val isSavingPriorityOrder: StateFlow<Boolean> = _isSavingPriorityOrder.asStateFlow()

    val hasCustomDevicePriority: Boolean
        get() = _configurableSources.value.any { it.isCustomPriority }

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    // Sleep
    private val _primarySleepSession = MutableStateFlow<SleepSession?>(null)
    val primarySleepSession: StateFlow<SleepSession?> = _primarySleepSession.asStateFlow()

    private val _allSleepSessions = MutableStateFlow<List<SleepSession>>(emptyList())
    val allSleepSessions: StateFlow<List<SleepSession>> = _allSleepSessions.asStateFlow()

    private val _daytimeNaps = MutableStateFlow<List<NapSession>>(emptyList())
    val daytimeNaps: StateFlow<List<NapSession>> = _daytimeNaps.asStateFlow()

    private val _sleepRecoveryVerdict = MutableStateFlow<SleepRecoveryVerdict?>(null)
    val sleepRecoveryVerdict: StateFlow<SleepRecoveryVerdict?> = _sleepRecoveryVerdict.asStateFlow()

    private val _sleepActionableTips = MutableStateFlow<List<SleepActionableTip>>(emptyList())
    val sleepActionableTips: StateFlow<List<SleepActionableTip>> = _sleepActionableTips.asStateFlow()

    private val _sleepAIContext = MutableStateFlow<SleepAIContext?>(null)
    val sleepAIContext: StateFlow<SleepAIContext?> = _sleepAIContext.asStateFlow()

    // Heart Rate & Zones
    private val _intradayHeartRate = MutableStateFlow<List<IntradayHeartRatePoint>>(emptyList())
    val intradayHeartRate: StateFlow<List<IntradayHeartRatePoint>> = _intradayHeartRate.asStateFlow()

    private val _heartRateZones = MutableStateFlow<Map<HeartRateZone, Int>>(emptyMap())
    val heartRateZones: StateFlow<Map<HeartRateZone, Int>> = _heartRateZones.asStateFlow()

    private val _averageBpm = MutableStateFlow(0.0)
    val averageBpm: StateFlow<Double> = _averageBpm.asStateFlow()

    private val _latestBpm = MutableStateFlow<Double?>(null)
    val latestBpm: StateFlow<Double?> = _latestBpm.asStateFlow()

    private val _latestBpmAt = MutableStateFlow<Long?>(null)
    val latestBpmAt: StateFlow<Long?> = _latestBpmAt.asStateFlow()

    private val _latestBpmSource = MutableStateFlow<String?>(null)
    val latestBpmSource: StateFlow<String?> = _latestBpmSource.asStateFlow()

    private val _minBpm = MutableStateFlow(0.0)
    val minBpm: StateFlow<Double> = _minBpm.asStateFlow()

    private val _maxBpm = MutableStateFlow(0.0)
    val maxBpm: StateFlow<Double> = _maxBpm.asStateFlow()

    private val _restingBpm = MutableStateFlow(0.0)
    val restingBpm: StateFlow<Double> = _restingBpm.asStateFlow()

    // Activity
    private val _hourlySteps = MutableStateFlow<List<HourlyStepBucket>>(emptyList())
    val hourlySteps: StateFlow<List<HourlyStepBucket>> = _hourlySteps.asStateFlow()

    private val _totalStepsToday = MutableStateFlow(0)
    val totalStepsToday: StateFlow<Int> = _totalStepsToday.asStateFlow()

    private val _stepsSourceDevice = MutableStateFlow<String?>(null)
    val stepsSourceDevice: StateFlow<String?> = _stepsSourceDevice.asStateFlow()

    private val _totalActiveCalories = MutableStateFlow(0.0)
    val totalActiveCalories: StateFlow<Double> = _totalActiveCalories.asStateFlow()

    // Stress & Autonomic Nervous System
    private val _currentStressScore = MutableStateFlow(35)
    val currentStressScore: StateFlow<Int> = _currentStressScore.asStateFlow()

    private val _currentStressLevel = MutableStateFlow(StressLevel.CALM)
    val currentStressLevel: StateFlow<StressLevel> = _currentStressLevel.asStateFlow()

    private val _stressAnalysis = MutableStateFlow<StressAnalysisResult?>(null)
    val stressAnalysis: StateFlow<StressAnalysisResult?> = _stressAnalysis.asStateFlow()

    private val _intradayStress = MutableStateFlow<List<IntradayStressPoint>>(emptyList())
    val intradayStress: StateFlow<List<IntradayStressPoint>> = _intradayStress.asStateFlow()

    // Vitals Grid & Trends
    private val _currentVitals = MutableStateFlow<Map<HealthMetricType, VitalMetricRecord>>(emptyMap())
    val currentVitals: StateFlow<Map<HealthMetricType, VitalMetricRecord>> = _currentVitals.asStateFlow()

    private val _historicalTrends = MutableStateFlow<Map<HealthMetricType, List<DailyMetricTrendPoint>>>(emptyMap())
    val historicalTrends: StateFlow<Map<HealthMetricType, List<DailyMetricTrendPoint>>> = _historicalTrends.asStateFlow()

    private val _canonicalSummary = MutableStateFlow<DailyHealthSummaryPayload?>(null)
    val canonicalSummary: StateFlow<DailyHealthSummaryPayload?> = _canonicalSummary.asStateFlow()

    private val jsonSerializer = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    // In-memory cache
    private var cachedTelemetry: List<HealthTelemetryRecord> = emptyList()
    private var cachedVitals: List<VitalMetricRecord> = emptyList()

    // Lean Cache for Selected Date
    private var cachedLeanSleepSessions: List<HealthSleepSessionRecord> = emptyList()
    private var cachedLeanDailyVitals: List<HealthDailyVitalsRecord> = emptyList()
    private var cachedLeanIntradayHeartRate: List<HealthIntradayHeartRateRecord> = emptyList()
    private var cachedLeanSources: List<HealthSourceRecord> = emptyList()

    private val isoDateFormatter = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())

    private var periodicActiveSyncJob: kotlinx.coroutines.Job? = null

    init {
        performDatabaseMaintenance()
        startActiveSyncLoop()
        if (currentUserId != "local_user") {
            loadDataForSelectedDate(forceRefresh = true)
            setupRealtimeSubscription()
        }
    }

    private fun checkMidnightRolloverIfNeeded(): Boolean {
        val currentTodayStart = getStartOfDay(System.currentTimeMillis())
        if (currentTodayStart != lastKnownTodayStart) {
            val wasViewingPreviousToday = (_selectedDate.value == lastKnownTodayStart)
            lastKnownTodayStart = currentTodayStart
            if (wasViewingPreviousToday) {
                _selectedDate.value = currentTodayStart
                cachedLeanSleepSessions = emptyList()
                cachedLeanDailyVitals = emptyList()
                cachedLeanIntradayHeartRate = emptyList()
                return true
            }
        }
        return false
    }

    fun startActiveSyncLoop() {
        periodicActiveSyncJob?.cancel()
        periodicActiveSyncJob = scope.launch(Dispatchers.IO) {
            while (isActive) {
                val intervalMs = if (realtimeChannel != null) 15 * 60 * 1000L else 5 * 60 * 1000L
                delay(intervalMs)
                if (currentUserId != "local_user") {
                    val rolledOver = checkMidnightRolloverIfNeeded()
                    val isToday = isSameDay(_selectedDate.value, System.currentTimeMillis())
                    if (rolledOver || isToday) {
                        loadDataForSelectedDate(forceRefresh = true)
                    }
                }
            }
        }
    }

    fun stopActiveSyncLoop() {
        periodicActiveSyncJob?.cancel()
        periodicActiveSyncJob = null
    }

    private fun performDatabaseMaintenance() {
        scope.launch(Dispatchers.IO) {
            try {
                val cutoff = System.currentTimeMillis() - 2 * 24 * 3600 * 1000L // 48h retention
                telemetryDao.deleteTelemetryBefore(cutoff)
                val hrCutoff = System.currentTimeMillis() - 24 * 3600 * 1000L
                val db = DailyDatabase.getDatabase(context).openHelper.writableDatabase
                db.execSQL("DELETE FROM health_telemetry WHERE type = 'heart_rate' AND start_time < $hrCutoff")
                // Purge any legacy compound/obfuscated device strings cached prior to canonical v2 unification
                db.execSQL("DELETE FROM health_telemetry WHERE source_device LIKE '% - %' OR source_device_key LIKE '% - %'")
                db.execSQL("DELETE FROM vitals WHERE source_device LIKE '% - %' OR source_device IN ('Canonical', 'Mac', 'Windows', 'Biometric Engine', 'Daily Biometric Engine')")
                db.execSQL("DELETE FROM health_daily_summary_cache WHERE summary_version < $CURRENT_SUMMARY_CACHE_VERSION")
                val cacheCutoff = System.currentTimeMillis() - 14 * 24 * 3600 * 1000L
                summaryDao.deleteOldCache(cacheCutoff)
                db.execSQL("VACUUM")
                android.util.Log.d("HealthDataRepository", "Database maintenance completed (48h retention + canonical v2 cleanup + VACUUM)")
            } catch (e: Exception) {
                android.util.Log.w("HealthDataRepository", "Database maintenance warning", e)
            }
        }
    }

    private var realtimeJob: kotlinx.coroutines.Job? = null
    private var lastRealtimeSummaryFetchMs: Long = 0L

    private fun setupRealtimeSubscription() {
        if (currentUserId == "local_user") return
        realtimeJob?.cancel()
        realtimeDebounceJob?.cancel()
        val targetUserId = currentUserId
        realtimeJob = scope.launch(Dispatchers.IO) {
            try {
                runCatching { realtimeChannel?.unsubscribe() }
                realtimeChannel = null

                SupabaseClientManager.ensureSessionReady()
                val channel = SupabaseClientManager.client.channel("health_realtime_sub_${targetUserId}")
                val summaryFlow = channel.postgresChangeFlow<PostgresAction>(schema = "public") {
                    table = "health_daily_summary"
                    filter("user_id", FilterOperator.EQ, targetUserId)
                }.map { "health_daily_summary" }
                val vitalsFlow = channel.postgresChangeFlow<PostgresAction>(schema = "public") {
                    table = "health_daily_vitals"
                    filter("user_id", FilterOperator.EQ, targetUserId)
                }.map { "health_daily_vitals" }
                val sleepFlow = channel.postgresChangeFlow<PostgresAction>(schema = "public") {
                    table = "health_sleep_sessions"
                    filter("user_id", FilterOperator.EQ, targetUserId)
                }.map { "health_sleep_sessions" }
                val sourcesFlow = channel.postgresChangeFlow<PostgresAction>(schema = "public") {
                    table = "health_sources"
                    filter("user_id", FilterOperator.EQ, targetUserId)
                }.map { "health_sources" }

                channel.subscribe()
                realtimeChannel = channel

                merge(summaryFlow, vitalsFlow, sleepFlow, sourcesFlow).collect { tableName ->
                    val now = System.currentTimeMillis()
                    // Suppress self-echoes from our own lean sleep/vitals uploads (health-engine summary notification follows if anything changed)
                    if ((tableName == "health_sleep_sessions" || tableName == "health_daily_vitals") &&
                        now - lastLocalUploadCompletedAtMs < 10_000L
                    ) {
                        return@collect
                    }

                    if (tableName == "health_sources") {
                        pendingRealtimeSourcesRefresh = true
                    }

                    val debounceMs = if (tableName == "health_sources") 1_500L else 5_000L
                    realtimeDebounceJob?.cancel()
                    realtimeDebounceJob = scope.launch(Dispatchers.IO) {
                        delay(debounceMs)
                        val refreshSources = pendingRealtimeSourcesRefresh
                        pendingRealtimeSourcesRefresh = false
                        lastRealtimeSummaryFetchMs = System.currentTimeMillis()
                        android.util.Log.d("HealthDataRepository", "Coalesced Realtime update ($tableName): silently refreshing")
                        fetchRemoteSummarySilentlyForSelectedDate(forceSourcesRefresh = refreshSources)
                    }
                }
            } catch (e: Exception) {
                realtimeChannel = null
                android.util.Log.w("HealthDataRepository", "Realtime subscription exception", e)
            }
        }
    }

    /**
     * Silently fetches the latest canonical summary and lean health records for the selected date from Supabase
     * without triggering local telemetry collection, uploading telemetry, toggling isLoading,
     * or re-invoking health-engine (1:1 parity with iOS fetchRemoteSummarySilentlyForSelectedDate).
     */
    fun fetchRemoteSummarySilentlyForSelectedDate(forceSourcesRefresh: Boolean = false) {
        if (currentUserId == "local_user") return
        scope.launch(Dispatchers.IO) {
            val targetEpochMs = _selectedDate.value
            val targetDate = Date(targetEpochMs)
            val dateKey = isoDateFormatter.format(targetDate)
            val nowMs = System.currentTimeMillis()
            val isToday = isSameDay(targetEpochMs, nowMs)
            val isWithinIntradayRetention = (getStartOfDay(nowMs) - getStartOfDay(targetEpochMs)) <= 8L * 86_400_000L
            val shouldFetchSources = forceSourcesRefresh || cachedLeanSources.isEmpty() || (nowMs - lastSourcesFetchAtMs) > 15 * 60 * 1000L

            try {
                coroutineScope {
                    val summaryDeferred = async {
                        try { remoteService.fetchDailySummary(currentUserId, dateKey) } catch (e: Exception) { null }
                    }
                    val sleepDeferred = async {
                        try { remoteService.fetchSleepSessions(currentUserId, dateKey) } catch (e: Exception) { emptyList() }
                    }
                    val vitalsDeferred = async {
                        try { remoteService.fetchDailyVitals(currentUserId, dateKey) } catch (e: Exception) { emptyList() }
                    }
                    val hrDeferred = async {
                        if (isWithinIntradayRetention) {
                            try { remoteService.fetchIntradayHeartRate(currentUserId, dateKey) } catch (e: Exception) { emptyList() }
                        } else emptyList()
                    }
                    val sourcesDeferred = async {
                        if (shouldFetchSources) {
                            try { remoteService.fetchHealthSources(currentUserId) } catch (e: Exception) { emptyList() }
                        } else emptyList()
                    }

                    val remoteSummary = summaryDeferred.await()
                    val remoteSleep = sleepDeferred.await()
                    val remoteVitals = vitalsDeferred.await()
                    val remoteHr = hrDeferred.await()
                    val remoteSources = sourcesDeferred.await()

                    val hostName = healthConnectManager.getHostPhoneName()
                    val localSleep = if (isToday && cachedTelemetry.isNotEmpty()) {
                        val cluster = SleepClusteringEngine.clusterSleep(targetDate, cachedTelemetry.filter { it.isSleep || it.isSleepStage })
                        buildLeanSleepSessionRecords(cluster.primarySession, cluster.naps, dateKey, currentUserId, hostName, cluster.allSessions)
                    } else emptyList()
                    val localVitals = if (isToday && cachedTelemetry.isNotEmpty()) {
                        buildLeanDailyVitalsRecords(cachedTelemetry, dateKey, currentUserId, hostName)
                    } else emptyList()
                    val localHr = if (isToday && cachedTelemetry.isNotEmpty()) {
                        groupIntradayHeartRateIntoBuckets(cachedTelemetry, currentUserId, dateKey)
                    } else emptyList()

                    cachedLeanSleepSessions = mergeLeanSleepSessions(remote = remoteSleep, local = localSleep)
                    cachedLeanDailyVitals = mergeLeanDailyVitals(remote = remoteVitals, local = localVitals)
                    cachedLeanIntradayHeartRate = mergeLeanIntradayHr(remote = remoteHr, local = localHr)

                    if (remoteSources.isNotEmpty()) {
                        cachedLeanSources = remoteSources
                        lastSourcesFetchAtMs = System.currentTimeMillis()
                    }

                    if (remoteSummary != null && !remoteSummary.isEmpty()) {
                        if (_canonicalSummary.value != remoteSummary) {
                            val entity = HealthDailySummaryEntity(
                                id = "summary_${currentUserId}_$dateKey",
                                userId = currentUserId,
                                dateKey = dateKey,
                                summaryVersion = CURRENT_SUMMARY_CACHE_VERSION,
                                payloadJson = jsonSerializer.encodeToString(remoteSummary),
                                computedAt = System.currentTimeMillis(),
                                sourceDevicePrimary = remoteSummary.sources.firstOrNull()
                            )
                            summaryDao.upsertSummary(entity)
                            withContext(Dispatchers.Main) {
                                _canonicalSummary.value = remoteSummary
                            }
                        }
                    }

                    withContext(Dispatchers.Main) {
                        rebuildAvailableSourcesForCurrentDate()
                        reapplyCurrentDeviceFilter()
                    }
                    loadHistoricalTrends(targetDate)
                }
            } catch (e: Exception) {
                android.util.Log.w("HealthDataRepository", "Could not silently fetch remote health data: ${e.message}")
            }
        }
    }

    // MARK: - Navigation Actions

    fun setActiveSubTab(tab: HealthSubTab) {
        _activeSubTab.value = tab
    }

    fun jumpToToday() {
        changeDate(System.currentTimeMillis())
    }

    fun nextDay() {
        val cal = Calendar.getInstance().apply {
            timeInMillis = _selectedDate.value
            add(Calendar.DAY_OF_YEAR, 1)
        }
        val todayStart = getStartOfDay(System.currentTimeMillis())
        if (cal.timeInMillis <= todayStart) {
            changeDate(cal.timeInMillis)
        }
    }

    fun prevDay() {
        val cal = Calendar.getInstance().apply {
            timeInMillis = _selectedDate.value
            add(Calendar.DAY_OF_YEAR, -1)
        }
        changeDate(cal.timeInMillis)
    }

    fun changeDate(newDateMillis: Long) {
        val normalized = getStartOfDay(newDateMillis)
        if (normalized == _selectedDate.value) return
        _selectedDate.value = normalized
        cachedLeanSleepSessions = emptyList()
        cachedLeanDailyVitals = emptyList()
        cachedLeanIntradayHeartRate = emptyList()
        loadDataForSelectedDate(forceRefresh = false)
    }

    fun setDeviceFilter(source: DeviceSource?) {
        if (_selectedDeviceSource.value == source) return
        _selectedDeviceSource.value = source
        _selectedDeviceFilter.value = source?.displayName
        reapplyCurrentDeviceFilter()
        scope.launch {
            loadHistoricalTrends(Date(_selectedDate.value))
        }
    }

    fun setDeviceFilter(device: String?) {
        val canonSource = if (!device.isNullOrEmpty()) DeviceSource.from(device) else null
        val canonName = canonSource?.displayName
        if (_selectedDeviceFilter.value == canonName) return
        _selectedDeviceFilter.value = canonName
        _selectedDeviceSource.value = canonSource
        reapplyCurrentDeviceFilter()
        scope.launch {
            loadHistoricalTrends(Date(_selectedDate.value))
        }
    }

    // MARK: - Smart Refresh
    private var lastRefreshTimestamp: Long = 0L

    fun refreshIfStale() {
        if (currentUserId == "local_user") return
        val rolledOver = checkMidnightRolloverIfNeeded()
        val now = System.currentTimeMillis()
        val isToday = isSameDay(_selectedDate.value, now)
        val staleThreshold = if (isToday) 5 * 60 * 1000L else 60 * 60 * 1000L
        if (rolledOver || now - lastRefreshTimestamp > staleThreshold) {
            lastRefreshTimestamp = now
            loadDataForSelectedDate(forceRefresh = true)
        } else {
            loadDataForSelectedDate(forceRefresh = false)
        }
    }

    // MARK: - Data Fetching & Processing

    fun loadDataForSelectedDate(forceRefresh: Boolean = false) {
        if (!forceRefresh && activeLoadJob?.isActive == true) {
            return
        }
        activeLoadJob?.cancel()
        activeLoadJob = scope.launch {
            val targetEpochMs = _selectedDate.value
            val targetDate = Date(targetEpochMs)
            val dateKey = isoDateFormatter.format(targetDate)
            val isToday = isSameDay(targetEpochMs, System.currentTimeMillis())

            // 0. Check in-memory summary + lean cache for exact selected date
            val hasLeanForDate = cachedLeanDailyVitals.any { it.localDate == dateKey } ||
                    cachedLeanSleepSessions.any { it.localDate == dateKey }
            if (!forceRefresh && _canonicalSummary.value?.date == dateKey && _canonicalSummary.value?.isEmpty() == false && hasLeanForDate) {
                if (!isToday) {
                    rebuildAvailableSourcesForCurrentDate()
                    reapplyCurrentDeviceFilter()
                    loadHistoricalTrends(targetDate)
                    return@launch
                }
            }

            // 1. Check Room local database cache for canonical summary (<10ms) for instant paint
            var hasValidCachedSummary = false
            val cachedSummaryEntity = withContext(Dispatchers.IO) {
                summaryDao.getSummary(currentUserId, dateKey)
            }
            if (!forceRefresh && cachedSummaryEntity != null && cachedSummaryEntity.summaryVersion == CURRENT_SUMMARY_CACHE_VERSION) {
                try {
                    val payload = jsonSerializer.decodeFromString<DailyHealthSummaryPayload>(cachedSummaryEntity.payloadJson)
                    if (!payload.isEmpty()) {
                        hasValidCachedSummary = true
                        if (_canonicalSummary.value != payload) {
                            applyCanonicalSummary(payload, dateKey)
                        }
                        if (!isToday && hasLeanForDate) {
                            rebuildAvailableSourcesForCurrentDate()
                            reapplyCurrentDeviceFilter()
                            loadHistoricalTrends(targetDate)
                            return@launch
                        }
                    }
                } catch (e: Exception) {
                    android.util.Log.w("HealthDataRepository", "Failed to deserialize cached summary", e)
                }
            }

            val shouldShowLoading = !hasValidCachedSummary && _canonicalSummary.value == null
            if (shouldShowLoading) {
                _isLoading.value = true
            }

            try {
                // 2. Concurrently fetch Supabase lean data, canonical summary and local Health Connect
                val localTelemetryDeferred = async(Dispatchers.IO) {
                    if (healthConnectManager.isAvailable && healthConnectManager.hasAnyPermissions()) {
                        healthConnectManager.fetchTelemetryForDate(targetDate, currentUserId)
                    } else {
                        emptyList()
                    }
                }

                val remoteSummaryDeferred = async(Dispatchers.IO) {
                    if (currentUserId != "local_user") {
                        withTimeoutOrNull(5000L) {
                            remoteService.fetchDailySummary(currentUserId, dateKey)
                        }
                    } else {
                        null
                    }
                }

                val remoteSleepDeferred = async(Dispatchers.IO) {
                    if (currentUserId != "local_user") {
                        remoteService.fetchSleepSessions(currentUserId, dateKey)
                    } else {
                        emptyList()
                    }
                }

                val remoteVitalsDeferred = async(Dispatchers.IO) {
                    if (currentUserId != "local_user") {
                        remoteService.fetchDailyVitals(currentUserId, dateKey)
                    } else {
                        emptyList()
                    }
                }

                val nowMs = System.currentTimeMillis()
                val isWithinIntradayRetention = (getStartOfDay(nowMs) - getStartOfDay(targetEpochMs)) <= 8L * 86_400_000L
                val shouldFetchSources = cachedLeanSources.isEmpty() || (nowMs - lastSourcesFetchAtMs) > 15 * 60 * 1000L

                val remoteHrDeferred = async(Dispatchers.IO) {
                    if (currentUserId != "local_user" && isWithinIntradayRetention) {
                        remoteService.fetchIntradayHeartRate(currentUserId, dateKey)
                    } else {
                        emptyList()
                    }
                }

                val remoteSourcesDeferred = async(Dispatchers.IO) {
                    if (currentUserId != "local_user" && shouldFetchSources) {
                        remoteService.fetchHealthSources(currentUserId)
                    } else {
                        emptyList()
                    }
                }

                val localTelemetry = localTelemetryDeferred.await()
                val remoteSummary = remoteSummaryDeferred.await()
                val remoteSleep = remoteSleepDeferred.await()
                val remoteVitals = remoteVitalsDeferred.await()
                val remoteHr = remoteHrDeferred.await()
                val remoteSources = remoteSourcesDeferred.await()

                val hostName = healthConnectManager.getHostPhoneName()
                val localLeanSleep = if (localTelemetry.isNotEmpty()) {
                    val cluster = SleepClusteringEngine.clusterSleep(targetDate, localTelemetry.filter { it.isSleep || it.isSleepStage })
                    buildLeanSleepSessionRecords(cluster.primarySession, cluster.naps, dateKey, currentUserId, hostName, cluster.allSessions)
                } else emptyList()
                val localLeanVitals = if (localTelemetry.isNotEmpty()) {
                    buildLeanDailyVitalsRecords(localTelemetry, dateKey, currentUserId, hostName)
                } else emptyList()
                val localLeanHr = if (localTelemetry.isNotEmpty()) {
                    groupIntradayHeartRateIntoBuckets(localTelemetry, currentUserId, dateKey)
                } else emptyList()

                cachedLeanSleepSessions = mergeLeanSleepSessions(remote = remoteSleep, local = localLeanSleep)
                cachedLeanDailyVitals = mergeLeanDailyVitals(remote = remoteVitals, local = localLeanVitals)
                cachedLeanIntradayHeartRate = mergeLeanIntradayHr(remote = remoteHr, local = localLeanHr)
                if (remoteSources.isNotEmpty()) {
                    cachedLeanSources = remoteSources
                    lastSourcesFetchAtMs = System.currentTimeMillis()
                }

                if (localTelemetry.isNotEmpty()) {
                    cachedTelemetry = localTelemetry
                    withContext(Dispatchers.IO) {
                        telemetryDao.insertRecords(localTelemetry.map { HealthTelemetryEntity.fromRecord(it) })
                    }
                    if (currentUserId != "local_user") {
                        scope.launch(Dispatchers.IO) {
                            syncTelemetryToSupabase(localTelemetry)
                        }
                    }
                }

                // 3. Apply canonical summary + unified lean tables
                if (remoteSummary != null && !remoteSummary.isEmpty()) {
                    if (_canonicalSummary.value != remoteSummary) {
                        withContext(Dispatchers.IO) {
                            val entity = HealthDailySummaryEntity(
                                id = "summary_${currentUserId}_$dateKey",
                                userId = currentUserId,
                                dateKey = dateKey,
                                summaryVersion = CURRENT_SUMMARY_CACHE_VERSION,
                                payloadJson = jsonSerializer.encodeToString(remoteSummary),
                                computedAt = System.currentTimeMillis(),
                                sourceDevicePrimary = remoteSummary.sources.firstOrNull()
                            )
                            summaryDao.upsertSummary(entity)
                        }
                        _canonicalSummary.value = remoteSummary
                    }
                } else if (remoteSummary != null && remoteSummary.isEmpty()) {
                    if (currentUserId != "local_user" && (cachedLeanSleepSessions.isNotEmpty() || cachedLeanDailyVitals.isNotEmpty() || cachedLeanIntradayHeartRate.isNotEmpty())) {
                        triggerCanonicalEngineIfNeeded(dateKey)
                    }
                }

                if ((remoteSummary != null && !remoteSummary.isEmpty()) ||
                    cachedLeanSleepSessions.isNotEmpty() ||
                    cachedLeanDailyVitals.isNotEmpty() ||
                    cachedLeanIntradayHeartRate.isNotEmpty()
                ) {
                    rebuildAvailableSourcesForCurrentDate()
                    reapplyCurrentDeviceFilter()
                    loadHistoricalTrends(targetDate)
                    return@launch
                }

                // 4. Fallback to on-device provisional calculation if remote canonical summary is absent or offline
                val cal = Calendar.getInstance().apply {
                    timeInMillis = targetEpochMs
                    add(Calendar.HOUR_OF_DAY, -6)
                }
                val windowStart = cal.timeInMillis
                val windowEnd = targetEpochMs + (24 * 3600 * 1000L)

                val telemetry = mutableListOf<HealthTelemetryRecord>()
                telemetry.addAll(localTelemetry)

                val localEntities = withContext(Dispatchers.IO) {
                    telemetryDao.getTelemetryBetweenSync(currentUserId, windowStart, windowEnd)
                }
                telemetry.addAll(localEntities.map { it.toRecord() })

                val localVitals = withContext(Dispatchers.IO) {
                    vitalsDao.getVitalsForDateSync(currentUserId, dateKey).map { it.toRecord() }
                }

                val deduped = deduplicateTelemetry(telemetry)
                if (deduped.isNotEmpty() || localVitals.isNotEmpty()) {
                    cachedTelemetry = deduped
                    cachedVitals = localVitals
                    updateDevicesAndSources()
                    processDataForCurrentDate()
                    loadHistoricalTrends(targetDate)
                }

                if (currentUserId != "local_user" && deduped.isNotEmpty()) {
                    triggerCanonicalEngineIfNeeded(dateKey)
                }
            } catch (e: Exception) {
                android.util.Log.e("HealthDataRepository", "Error loading health data", e)
            } finally {
                if (shouldShowLoading) {
                    _isLoading.value = false
                }
            }
        }
    }

    // MARK: - Lean Merge & Date-Scoped Canonical Sources

    private fun mergeLeanSleepSessions(
        remote: List<HealthSleepSessionRecord>,
        local: List<HealthSleepSessionRecord>
    ): List<HealthSleepSessionRecord> {
        if (local.isEmpty()) return remote
        if (remote.isEmpty()) return local
        val map = LinkedHashMap<String, HealthSleepSessionRecord>()
        for (r in remote) {
            val canon = DeviceSource.from(r.sourceDeviceKey).displayName
            val key = "${r.sessionType}_$canon"
            val existing = map[key]
            if (existing == null || r.durationSeconds >= existing.durationSeconds) {
                map[key] = r
            }
        }
        for (l in local) {
            val canon = DeviceSource.from(l.sourceDeviceKey).displayName
            val key = "${l.sessionType}_$canon"
            val existing = map[key]
            if (existing == null ||
                (l.stages.isNotEmpty() && existing.stages.isEmpty()) ||
                l.durationSeconds > existing.durationSeconds
            ) {
                map[key] = l
            }
        }
        return map.values.toList()
    }

    private fun mergeLeanDailyVitals(
        remote: List<HealthDailyVitalsRecord>,
        local: List<HealthDailyVitalsRecord>
    ): List<HealthDailyVitalsRecord> {
        if (local.isEmpty() && remote.isEmpty()) return emptyList()
        val map = LinkedHashMap<String, HealthDailyVitalsRecord>()
        for (r in (remote + local)) {
            val src = DeviceSource.from(r.sourceDeviceKey)
            if (src.isVirtualEngine) continue
            val canon = src.displayName
            val prev = map[canon]
            if (prev != null) {
                val mergedSteps = maxOf(prev.steps, r.steps)
                val mergedKcal = maxOf(prev.activeKcal, r.activeKcal)
                val mergedHourly = if (r.steps >= prev.steps && !r.hourlySteps.isNullOrEmpty()) {
                    r.hourlySteps
                } else {
                    prev.hourlySteps ?: r.hourlySteps
                }

                val (mergedLatestHr, mergedLatestHrAt) = when {
                    prev.latestHeartRate != null && r.latestHeartRate != null -> {
                        val pTs = parseIsoToEpochMs(prev.latestHrAt ?: prev.updatedAt) ?: 0L
                        val rTs = parseIsoToEpochMs(r.latestHrAt ?: r.updatedAt) ?: 0L
                        if (rTs >= pTs) Pair(r.latestHeartRate, r.latestHrAt ?: prev.latestHrAt)
                        else Pair(prev.latestHeartRate, prev.latestHrAt ?: r.latestHrAt)
                    }
                    prev.latestHeartRate == null && r.latestHeartRate != null -> Pair(r.latestHeartRate, r.latestHrAt)
                    prev.latestHeartRate != null && r.latestHeartRate == null -> Pair(prev.latestHeartRate, prev.latestHrAt)
                    else -> Pair(null, prev.latestHrAt ?: r.latestHrAt)
                }

                val mergedTsMap = (prev.vitalsTimestamps ?: emptyMap()).toMutableMap()
                r.vitalsTimestamps?.forEach { (k, v) ->
                    val oldTs = parseIsoToEpochMs(mergedTsMap[k])
                    val newTs = parseIsoToEpochMs(v)
                    if (oldTs == null || (newTs != null && newTs >= oldTs)) {
                        mergedTsMap[k] = v
                    }
                }

                val mergedSpo2 = if (prev.spo2 != null && r.spo2 != null) {
                    val pD = parseIsoToEpochMs(prev.vitalsTimestamps?.get("spo2") ?: prev.updatedAt) ?: 0L
                    val rD = parseIsoToEpochMs(r.vitalsTimestamps?.get("spo2") ?: r.updatedAt) ?: 0L
                    if (rD >= pD) r.spo2 else prev.spo2
                } else {
                    r.spo2 ?: prev.spo2
                }

                val mergedWeight = if (prev.weightKg != null && r.weightKg != null) {
                    val pD = parseIsoToEpochMs(prev.vitalsTimestamps?.get("weight") ?: prev.updatedAt) ?: 0L
                    val rD = parseIsoToEpochMs(r.vitalsTimestamps?.get("weight") ?: r.updatedAt) ?: 0L
                    if (rD >= pD) r.weightKg else prev.weightKg
                } else {
                    r.weightKg ?: prev.weightKg
                }

                val mergedUpdatedAt = run {
                    val pU = parseIsoToEpochMs(prev.updatedAt)
                    val rU = parseIsoToEpochMs(r.updatedAt)
                    if (pU != null && rU != null) {
                        if (rU >= pU) r.updatedAt else prev.updatedAt
                    } else {
                        r.updatedAt ?: prev.updatedAt
                    }
                }

                map[canon] = HealthDailyVitalsRecord(
                    id = prev.id,
                    userId = r.userId,
                    localDate = r.localDate,
                    sourceDeviceKey = canon,
                    hostDeviceName = r.hostDeviceName ?: prev.hostDeviceName,
                    steps = mergedSteps,
                    activeKcal = mergedKcal,
                    restingHeartRate = r.restingHeartRate ?: prev.restingHeartRate,
                    spo2 = mergedSpo2,
                    respiratoryRate = r.respiratoryRate ?: prev.respiratoryRate,
                    skinTempCelsius = r.skinTempCelsius ?: prev.skinTempCelsius,
                    weightKg = mergedWeight,
                    hrvSdnnNightly = r.hrvSdnnNightly ?: prev.hrvSdnnNightly,
                    hrvRmssdNightly = r.hrvRmssdNightly ?: prev.hrvRmssdNightly,
                    hourlySteps = mergedHourly,
                    latestHeartRate = mergedLatestHr,
                    latestHrAt = mergedLatestHrAt,
                    vitalsTimestamps = mergedTsMap.takeIf { it.isNotEmpty() },
                    updatedAt = mergedUpdatedAt
                )
            } else {
                map[canon] = r.copy(sourceDeviceKey = canon)
            }
        }
        return map.values
            .filter { it.hasSignal }
            .sortedBy { effectivePriorityRank(it.sourceDeviceKey) }
    }

    private fun mergeLeanIntradayHr(
        remote: List<HealthIntradayHeartRateRecord>,
        local: List<HealthIntradayHeartRateRecord>
    ): List<HealthIntradayHeartRateRecord> {
        if (local.isEmpty()) return remote
        if (remote.isEmpty()) return local
        val map = LinkedHashMap<String, HealthIntradayHeartRateRecord>()
        for (r in remote) {
            val src = DeviceSource.from(r.sourceDeviceKey)
            if (src.isVirtualEngine) continue
            val canon = src.displayName
            val key = "${canon}_${r.bucketMinute}"
            map[key] = r.copy(sourceDeviceKey = canon)
        }
        for (l in local) {
            val src = DeviceSource.from(l.sourceDeviceKey)
            if (src.isVirtualEngine) continue
            val canon = src.displayName
            val key = "${canon}_${l.bucketMinute}"
            val existing = map[key]
            if (existing == null || l.sampleCount >= existing.sampleCount) {
                map[key] = l.copy(
                    sourceDeviceKey = canon,
                    bpmMin = if (existing != null) minOf(existing.bpmMin, l.bpmMin) else l.bpmMin,
                    bpmMax = if (existing != null) maxOf(existing.bpmMax, l.bpmMax) else l.bpmMax,
                    sampleCount = if (existing != null) maxOf(existing.sampleCount, l.sampleCount) else l.sampleCount
                )
            }
        }
        return map.values.sortedBy { it.bucketMinute }
    }

    fun effectivePriorityRank(deviceName: String?): Int =
        resolveEffectivePriorityRank(deviceName, cachedLeanSources)

    private fun rebuildConfigurableSources() {
        val uid = cachedLeanSources.firstOrNull()?.userId ?: currentUserId
        val byCanonical = LinkedHashMap<DeviceSource, HealthSourceRecord>()

        for (s in cachedLeanSources) {
            val src = DeviceSource.from(s.displayName)
            if (src.isVirtualEngine || src is DeviceSource.Manual) continue
            val cleanId = canonicalSourceId(src, src.displayName)
            val normalizedRank = resolveEffectivePriorityRank(src.displayName, listOf(s))
            val existing = byCanonical[src]
            if (existing != null) {
                if ((s.isCustomPriority && !existing.isCustomPriority) || s.id == cleanId) {
                    byCanonical[src] = s.copy(
                        displayName = src.displayName,
                        hostDeviceName = s.hostDeviceName ?: existing.hostDeviceName,
                        prioritySleep = normalizedRank,
                        priorityActivity = normalizedRank,
                        isCustomPriority = s.isCustomPriority || existing.isCustomPriority,
                        color = s.color ?: existing.color
                    )
                }
            } else {
                byCanonical[src] = s.copy(
                    displayName = src.displayName,
                    prioritySleep = normalizedRank,
                    priorityActivity = normalizedRank,
                    color = s.color ?: DeviceColorPalette.getColorForSource(src.displayName)
                )
            }
        }

        for (src in _availableSources.value) {
            if (src.isVirtualEngine || src is DeviceSource.Manual) continue
            if (!byCanonical.containsKey(src)) {
                val disp = src.displayName
                val sid = canonicalSourceId(src, disp)
                byCanonical[src] = HealthSourceRecord(
                    id = sid,
                    userId = uid,
                    platform = if (src is DeviceSource.AppleWatch || src is DeviceSource.HealthKit) "iOS" else "Android",
                    deviceKind = when {
                        src is DeviceSource.Oura -> "ring"
                        src.isWearable -> "watch"
                        else -> "phone"
                    },
                    displayName = disp,
                    prioritySleep = src.sortPriority,
                    priorityActivity = src.sortPriority,
                    isCustomPriority = false,
                    color = DeviceColorPalette.getColorForSource(disp)
                )
            }
        }

        _configurableSources.value = byCanonical.values.sortedWith(
            compareBy<HealthSourceRecord> { minOf(it.prioritySleep, it.priorityActivity) }
                .thenBy { it.displayName }
        )
    }

    suspend fun moveDevicePriority(index: Int, direction: Int) {
        val list = _configurableSources.value.toMutableList()
        val newIndex = index + direction
        if (index !in list.indices || newIndex !in list.indices) return
        val moved = list.removeAt(index)
        list.add(newIndex, moved)

        val updated = list.mapIndexed { idx, item ->
            val rank = idx + 1
            item.copy(
                prioritySleep = rank,
                priorityActivity = rank,
                isCustomPriority = true
            )
        }
        withContext(Dispatchers.Main) {
            _configurableSources.value = updated
            cachedLeanSources = updated
            rebuildAvailableSourcesForCurrentDate()
            reapplyCurrentDeviceFilter()
        }
        saveDevicePriorityOrder(updated.map { it.id })
    }

    suspend fun saveDevicePriorityOrder(orderedIds: List<String>) {
        if (orderedIds.isEmpty() || currentUserId == "local_user") return
        _isSavingPriorityOrder.value = true
        try {
            val ok = remoteService.saveHealthSourcePriorities(orderedIds)
            if (ok) {
                trendsRemoteCache = null
                val fresh = remoteService.fetchHealthSources(currentUserId)
                if (fresh.isNotEmpty()) {
                    cachedLeanSources = fresh
                    lastSourcesFetchAtMs = System.currentTimeMillis()
                }
                withContext(Dispatchers.Main) {
                    rebuildConfigurableSources()
                    rebuildAvailableSourcesForCurrentDate()
                    reapplyCurrentDeviceFilter()
                }
                val dateKey = isoDateFormatter.format(Date(_selectedDate.value))
                triggerCanonicalEngineIfNeeded(
                    dateKey = dateKey,
                    fingerprint = "priority_${orderedIds.joinToString(",")}",
                    force = true
                )
            }
        } finally {
            _isSavingPriorityOrder.value = false
        }
    }

    suspend fun resetDevicePriorityOrder() {
        if (currentUserId == "local_user") return
        _isSavingPriorityOrder.value = true
        try {
            val ok = remoteService.resetHealthSourcePriorities()
            if (ok) {
                trendsRemoteCache = null
                val fresh = remoteService.fetchHealthSources(currentUserId)
                cachedLeanSources = fresh
                lastSourcesFetchAtMs = System.currentTimeMillis()
                withContext(Dispatchers.Main) {
                    rebuildConfigurableSources()
                    rebuildAvailableSourcesForCurrentDate()
                    reapplyCurrentDeviceFilter()
                }
                val dateKey = isoDateFormatter.format(Date(_selectedDate.value))
                triggerCanonicalEngineIfNeeded(
                    dateKey = dateKey,
                    fingerprint = "priority_reset_${System.currentTimeMillis() / 1000}",
                    force = true
                )
            }
        } finally {
            _isSavingPriorityOrder.value = false
        }
    }

    private fun rebuildAvailableSourcesForCurrentDate() {
        val srcSet = LinkedHashSet<DeviceSource>()
        for (s in cachedLeanSleepSessions) {
            if (s.durationSeconds <= 0) continue
            val src = DeviceSource.from(s.sourceDeviceKey)
            if (!src.isVirtualEngine) srcSet.add(src)
        }
        for (v in cachedLeanDailyVitals) {
            if (!v.hasSignal) continue
            val src = DeviceSource.from(v.sourceDeviceKey)
            if (!src.isVirtualEngine) srcSet.add(src)
        }
        for (h in cachedLeanIntradayHeartRate) {
            if (h.bpmAvg <= 30 || h.sourceDeviceKey.isEmpty()) continue
            val src = DeviceSource.from(h.sourceDeviceKey)
            if (!src.isVirtualEngine) srcSet.add(src)
        }
        if (srcSet.isEmpty() && cachedLeanSleepSessions.isEmpty() && cachedLeanDailyVitals.isEmpty() && cachedLeanIntradayHeartRate.isEmpty()) {
            val summarySources = _canonicalSummary.value?.sources.orEmpty()
            for (raw in summarySources) {
                val src = DeviceSource.from(raw)
                if (!src.isVirtualEngine) srcSet.add(src)
            }
        }
        val sortedSources = srcSet.toList().sortedWith(
            compareBy<DeviceSource> { effectivePriorityRank(it.displayName) }.thenBy { it.displayName }
        )
        _availableSources.value = sortedSources
        _availableDevices.value = sortedSources.map { it.displayName }
        rebuildConfigurableSources()

        // Auto-reset device filter to All Devices if previously selected device has no data on this date
        val selectedSrc = _selectedDeviceSource.value
        val selectedFilter = _selectedDeviceFilter.value
        if (selectedSrc != null && !sortedSources.contains(selectedSrc)) {
            _selectedDeviceSource.value = null
            _selectedDeviceFilter.value = null
        } else if (!selectedFilter.isNullOrEmpty()) {
            val canon = DeviceSource.from(selectedFilter)
            if (!sortedSources.contains(canon)) {
                _selectedDeviceSource.value = null
                _selectedDeviceFilter.value = null
            }
        }
    }

    fun applyLeanSleepSessions(rows: List<HealthSleepSessionRecord>) {
        cachedLeanSleepSessions = rows
        val filter = _selectedDeviceFilter.value
        val candidateRows = if (!filter.isNullOrEmpty()) {
            val targetCanon = DeviceSource.from(filter).displayName
            rows.filter { DeviceSource.from(it.sourceDeviceKey).displayName == targetCanon }
        } else {
            rows
        }

        if (candidateRows.isEmpty()) {
            _primarySleepSession.value = null
            _allSleepSessions.value = emptyList()
            _daytimeNaps.value = emptyList()
            _sleepRecoveryVerdict.value = null
            _sleepActionableTips.value = emptyList()
            _sleepAIContext.value = null
            return
        }

        val sortedPrimaryCandidates = candidateRows
            .filter { it.sessionType != "nap" }
            .sortedWith(
                compareByDescending<HealthSleepSessionRecord> { it.isUserSelected }
                    .thenByDescending { it.hasGranularSleepStages }
                    .thenBy { effectivePriorityRank(it.sourceDeviceKey) }
                    .thenByDescending { it.durationSeconds }
            )

        val mapped = sortedPrimaryCandidates.map { it.toSleepSession() }
        val primary = mapped.firstOrNull()

        val naps = candidateRows.filter { it.sessionType == "nap" }.map { r ->
            NapSession(
                id = r.id,
                startTime = r.startTime,
                endTime = r.endTime,
                durationSeconds = r.durationSeconds.toDouble(),
                sourceDevice = DeviceSource.from(r.sourceDeviceKey).displayName
            )
        }

        _primarySleepSession.value = primary
        _allSleepSessions.value = mapped
        _daytimeNaps.value = naps

        if (primary != null) {
            val vitalsMap = _currentVitals.value
            val rhr = vitalsMap[HealthMetricType.RESTING_HEART_RATE]?.value ?: _restingBpm.value.takeIf { it > 0 }
            val hrv = vitalsMap[HealthMetricType.HRV_SDNN]?.value ?: vitalsMap[HealthMetricType.HRV_RMSSD]?.value
            val analysis = SleepAnalysisEngine.analyze(
                session = primary,
                nocturnalRestingBpm = rhr,
                nocturnalHrvMs = hrv
            )
            _sleepRecoveryVerdict.value = analysis.verdict
            _sleepActionableTips.value = analysis.tips
            _sleepAIContext.value = analysis.aiContext
        } else {
            _sleepRecoveryVerdict.value = null
            _sleepActionableTips.value = emptyList()
            _sleepAIContext.value = null
        }
    }

    fun applyLeanDailyVitals(vitals: List<HealthDailyVitalsRecord>) {
        cachedLeanDailyVitals = vitals
        val filter = _selectedDeviceFilter.value
        val nowMs = System.currentTimeMillis()
        val dateStr = isoDateFormatter.format(Date(_selectedDate.value))

        fun populateVitalsRow(
            map: MutableMap<HealthMetricType, VitalMetricRecord>,
            row: HealthDailyVitalsRecord,
            canon: String,
            overwrite: Boolean
        ) {
            val defaultTs = parseIsoToEpochMs(row.updatedAt) ?: nowMs
            fun tsForKey(key: String): Long = parseIsoToEpochMs(row.vitalsTimestamps?.get(key)) ?: defaultTs
            fun setMetric(type: HealthMetricType, value: Double, unit: String, ts: Long) {
                if (overwrite || !map.containsKey(type)) {
                    map[type] = VitalMetricRecord(
                        userId = row.userId,
                        type = type.rawKey,
                        value = value,
                        unit = unit,
                        date = row.localDate,
                        sourceDevice = canon,
                        createdAt = ts
                    )
                }
            }
            row.latestHeartRate?.takeIf { it in 30..240 }?.let {
                setMetric(HealthMetricType.HEART_RATE, it.toDouble(), "bpm", parseIsoToEpochMs(row.latestHrAt) ?: defaultTs)
            }
            row.restingHeartRate?.takeIf { it > 0 }?.let {
                setMetric(HealthMetricType.RESTING_HEART_RATE, it.toDouble(), "bpm", tsForKey("rhr"))
            }
            row.spo2?.takeIf { it > 0 }?.let {
                setMetric(HealthMetricType.OXYGEN_SATURATION, it, "%", tsForKey("spo2"))
            }
            row.respiratoryRate?.takeIf { it > 0 }?.let {
                setMetric(HealthMetricType.RESPIRATORY_RATE, it, "br/min", tsForKey("resp"))
            }
            row.skinTempCelsius?.let {
                setMetric(HealthMetricType.BODY_TEMPERATURE, it, "°C", tsForKey("temp"))
            }
            row.weightKg?.takeIf { it > 0 }?.let {
                setMetric(HealthMetricType.WEIGHT, it, "kg", tsForKey("weight"))
            }
            row.hrvSdnnNightly?.takeIf { it > 0 }?.let {
                setMetric(HealthMetricType.HRV_SDNN, it, "ms", tsForKey("hrv_sdnn"))
            }
            row.hrvRmssdNightly?.takeIf { it > 0 }?.let {
                setMetric(HealthMetricType.HRV_RMSSD, it, "ms", tsForKey("hrv_rmssd"))
            }
            if (row.activeKcal > 0) {
                setMetric(HealthMetricType.ACTIVE_ENERGY, row.activeKcal, "kcal", defaultTs)
            }
        }

        if (!filter.isNullOrEmpty()) {
            val targetCanon = DeviceSource.from(filter).displayName
            val matching = vitals.filter { DeviceSource.from(it.sourceDeviceKey).displayName == targetCanon }
            val exact = matching.maxByOrNull { it.steps } ?: matching.firstOrNull()
            if (exact == null) {
                _hourlySteps.value = emptyList()
                _totalStepsToday.value = 0
                _totalActiveCalories.value = 0.0
                _stepsSourceDevice.value = targetCanon
                _restingBpm.value = 0.0
                _currentVitals.value = emptyMap()
                return
            }

            _hourlySteps.value = exact.hourlySteps ?: emptyList()
            _totalStepsToday.value = exact.steps
            _totalActiveCalories.value = if (exact.activeKcal > 0) exact.activeKcal else if (exact.steps > 0) (exact.steps * 0.042).round(1) else 0.0
            _stepsSourceDevice.value = targetCanon
            _restingBpm.value = (exact.restingHeartRate ?: 0).toDouble()

            val map = mutableMapOf<HealthMetricType, VitalMetricRecord>()
            populateVitalsRow(map, exact, targetCanon, overwrite = true)
            _currentVitals.value = map
            return
        }

        if (vitals.isEmpty()) {
            _hourlySteps.value = emptyList()
            _totalStepsToday.value = 0
            _totalActiveCalories.value = 0.0
            _stepsSourceDevice.value = null
            _restingBpm.value = 0.0
            _currentVitals.value = emptyMap()
            return
        }

        // All Devices mode:
        // - Class B (Steps & Active Kcal): Hourly Active-Wearer Envelope across wearables
        // - Class C (RHR, HRV, Resp, Skin Temp): Configured Priority Order (1-based ascending)
        // - Class A (SpO2, Weight): Recency-First with 30m simultaneous priority tie-break
        val activity = arbitrateHourlyActivity(vitals, cachedLeanSources)
        _hourlySteps.value = activity.hourlySteps
        _totalStepsToday.value = activity.totalSteps
        _totalActiveCalories.value = activity.activeCalories
        _stepsSourceDevice.value = activity.sourceDevice

        val prioritySorted = vitals.sortedWith(
            compareBy<HealthDailyVitalsRecord> { effectivePriorityRank(it.sourceDeviceKey) }
                .thenByDescending { it.steps }
        )

        val map = mutableMapOf<HealthMetricType, VitalMetricRecord>()
        for (row in prioritySorted) {
            val canon = DeviceSource.from(row.sourceDeviceKey).displayName
            populateVitalsRow(map, row, canon, overwrite = false)
        }

        arbitrateSpotVital(vitals, "spo2", cachedLeanSources, 1_800_000L) { it.spo2 }?.let { winner ->
            map[HealthMetricType.OXYGEN_SATURATION] = VitalMetricRecord(
                userId = "lean",
                type = HealthMetricType.OXYGEN_SATURATION.rawKey,
                value = winner.value,
                unit = "%",
                date = dateStr,
                sourceDevice = winner.sourceDevice,
                createdAt = winner.timestampMs ?: nowMs
            )
        }
        arbitrateSpotVital(vitals, "weight", cachedLeanSources, 1_800_000L) { it.weightKg }?.let { winner ->
            map[HealthMetricType.WEIGHT] = VitalMetricRecord(
                userId = "lean",
                type = HealthMetricType.WEIGHT.rawKey,
                value = winner.value,
                unit = "kg",
                date = dateStr,
                sourceDevice = winner.sourceDevice,
                createdAt = winner.timestampMs ?: nowMs
            )
        }
        if (activity.activeCalories > 0.0) {
            map[HealthMetricType.ACTIVE_ENERGY] = VitalMetricRecord(
                userId = "lean",
                type = HealthMetricType.ACTIVE_ENERGY.rawKey,
                value = activity.activeCalories,
                unit = "kcal",
                date = dateStr,
                sourceDevice = activity.sourceDevice,
                createdAt = nowMs
            )
        }

        _restingBpm.value = map[HealthMetricType.RESTING_HEART_RATE]?.value ?: 0.0
        _currentVitals.value = map
    }

    fun applyLeanIntradayHeartRate(buckets: List<HealthIntradayHeartRateRecord>, targetDateEpochMs: Long) {
        cachedLeanIntradayHeartRate = buckets
        val filter = _selectedDeviceFilter.value
        val dateStr = isoDateFormatter.format(Date(targetDateEpochMs))

        var finalLatest = arbitrateLatestHeartRate(
            vitals = cachedLeanDailyVitals,
            intradayBuckets = buckets,
            targetDateEpochMs = targetDateEpochMs,
            sources = cachedLeanSources,
            deviceFilter = filter
        )

        if (filter.isNullOrEmpty()) {
            val canonical = _canonicalSummary.value
            val cardio = canonical?.cardiovascular
            val summaryBpm = cardio?.latestBpm
            val summarySrc = cardio?.latestSourceDevice
            if (summaryBpm != null && summaryBpm >= 30.0 && !summarySrc.isNullOrEmpty()) {
                val summaryTs = parseIsoToEpochMs(cardio.latestBpmAt ?: canonical.computedAt) ?: 0L
                val existing = finalLatest
                if (existing == null || summaryTs > existing.timestampMs + 60_000L) {
                    finalLatest = ArbitratedLatestHeartRate(
                        bpm = summaryBpm,
                        timestampMs = summaryTs,
                        sourceDevice = DeviceSource.from(summarySrc).displayName
                    )
                }
            }
        }

        if (finalLatest != null) {
            _latestBpm.value = finalLatest.bpm
            _latestBpmAt.value = finalLatest.timestampMs.takeIf { it > 0L }
            _latestBpmSource.value = finalLatest.sourceDevice
            val updated = _currentVitals.value.toMutableMap()
            updated[HealthMetricType.HEART_RATE] = VitalMetricRecord(
                userId = "lean-hr",
                type = HealthMetricType.HEART_RATE.rawKey,
                value = finalLatest.bpm,
                unit = "bpm",
                date = dateStr,
                sourceDevice = finalLatest.sourceDevice,
                createdAt = finalLatest.timestampMs.takeIf { it > 0L }
            )
            _currentVitals.value = updated
        } else {
            _latestBpm.value = null
            _latestBpmAt.value = null
            _latestBpmSource.value = null
        }

        if (buckets.isEmpty()) {
            val archived = resolveArchivedCardiovascularFallback(
                cardio = _canonicalSummary.value?.cardiovascular,
                filter = filter
            )
            if (archived != null) {
                _intradayHeartRate.value = archived.points
                _averageBpm.value = archived.averageBpm
                _minBpm.value = archived.minBpm
                _maxBpm.value = archived.maxBpm
                _heartRateZones.value = archived.zones
                if (_restingBpm.value <= 0.0 && archived.restingBpm != null && archived.restingBpm > 0.0) {
                    _restingBpm.value = archived.restingBpm
                }
                if (_latestBpm.value == null && archived.latestBpm != null && archived.latestBpm > 30.0) {
                    _latestBpm.value = archived.latestBpm
                    _latestBpmAt.value = archived.latestTimestampMs
                    _latestBpmSource.value = archived.latestSourceDevice
                    val updated = _currentVitals.value.toMutableMap()
                    updated[HealthMetricType.HEART_RATE] = VitalMetricRecord(
                        userId = "lean-hr-archived",
                        type = HealthMetricType.HEART_RATE.rawKey,
                        value = archived.latestBpm,
                        unit = "bpm",
                        date = dateStr,
                        sourceDevice = archived.latestSourceDevice,
                        createdAt = archived.latestTimestampMs
                    )
                    _currentVitals.value = updated
                }
                return
            }
        }

        val maxBucketMinute = buckets.maxOfOrNull { it.bucketMinute } ?: 0
        val filtered = if (!filter.isNullOrEmpty()) {
            val targetCanon = DeviceSource.from(filter).displayName
            buckets.filter { DeviceSource.from(it.sourceDeviceKey).displayName == targetCanon }
        } else if (buckets.size > 1) {
            buckets.groupBy { it.bucketMinute }
                .toSortedMap()
                .map { (bm, group) ->
                    if (group.size == 1) {
                        group[0]
                    } else {
                        val activeSrc = finalLatest?.sourceDevice
                        val activeMatch = if (!activeSrc.isNullOrEmpty() && bm >= maxBucketMinute - 15) {
                            group.firstOrNull { DeviceSource.from(it.sourceDeviceKey).displayName == activeSrc }
                        } else null
                        if (activeMatch != null) {
                            activeMatch
                        } else {
                            val sortedGrp = group.sortedBy { effectivePriorityRank(it.sourceDeviceKey) }
                            val primary = sortedGrp[0]
                            val totalCnt = sortedGrp.sumOf { maxOf(1, it.sampleCount) }
                            val weightedSum = sortedGrp.sumOf { it.bpmAvg * maxOf(1, it.sampleCount) }
                            val minV = sortedGrp.minOf { if (it.bpmMin > 30) it.bpmMin else it.bpmAvg }
                            val maxV = sortedGrp.maxOf { if (it.bpmMax > 30) it.bpmMax else it.bpmAvg }
                            primary.copy(
                                bucketMinute = bm,
                                bpmAvg = Math.round(weightedSum.toDouble() / maxOf(1, totalCnt)).toInt(),
                                bpmMin = minV,
                                bpmMax = maxV,
                                sampleCount = totalCnt
                            )
                        }
                    }
                }
        } else {
            buckets
        }

        val points = filtered.map { it.toPoint(targetDateEpochMs) }.sortedBy { it.timestamp }
        _intradayHeartRate.value = points
        if (filtered.isNotEmpty()) {
            val totalSamples = filtered.sumOf { maxOf(1, it.sampleCount) }
            val weightedSum = filtered.sumOf { it.bpmAvg.toDouble() * maxOf(1, it.sampleCount) }
            _averageBpm.value = round(weightedSum / maxOf(1, totalSamples))
            var lo = (filtered.minOfOrNull { if (it.bpmMin > 30) it.bpmMin else it.bpmAvg } ?: 0).toDouble()
            var hi = (filtered.maxOfOrNull { if (it.bpmMax > 30) it.bpmMax else it.bpmAvg } ?: 0).toDouble()
            val live = _latestBpm.value
            if (live != null && live > 30.0) {
                if (lo <= 0.0 || live < lo) lo = live
                if (live > hi) hi = live
            }
            _minBpm.value = lo
            _maxBpm.value = hi
            if (_restingBpm.value <= 0.0) {
                val derived = StressAnalysisEngine.deriveNocturnalRhr(points, Date(targetDateEpochMs))
                if (derived != null) {
                    _restingBpm.value = derived
                } else if (_minBpm.value > 0.0) {
                    _restingBpm.value = minOf(85.0, maxOf(45.0, _minBpm.value + 6.0))
                }
            }

            val zones = mutableMapOf(
                HeartRateZone.RESTING to 0,
                HeartRateZone.FAT_BURN to 0,
                HeartRateZone.CARDIO to 0,
                HeartRateZone.PEAK to 0
            )
            for (pt in points) {
                zones[pt.zone] = (zones[pt.zone] ?: 0) + 1
            }
            _heartRateZones.value = zones
        } else {
            _averageBpm.value = _latestBpm.value ?: 0.0
            _minBpm.value = _latestBpm.value ?: 0.0
            _maxBpm.value = _latestBpm.value ?: 0.0
            _heartRateZones.value = emptyMap()
        }
    }

    fun applyLeanHealthSources(sources: List<HealthSourceRecord>) {
        // Store source metadata only; never inject global registry rows into date-scoped _availableSources!
        cachedLeanSources = sources
        rebuildConfigurableSources()
    }

    fun reapplyCurrentDeviceFilter() {
        val filter = _selectedDeviceFilter.value
        val dateKey = isoDateFormatter.format(Date(_selectedDate.value))
        if (cachedLeanSleepSessions.isEmpty() && cachedLeanDailyVitals.isEmpty() && cachedLeanIntradayHeartRate.isEmpty()) {
            if (filter.isNullOrEmpty()) {
                val canonical = _canonicalSummary.value
                if (canonical != null) {
                    applyCanonicalSummary(canonical, dateKey)
                    return
                }
            }
        }

        applyLeanDailyVitals(cachedLeanDailyVitals)
        applyLeanSleepSessions(cachedLeanSleepSessions)
        applyLeanIntradayHeartRate(cachedLeanIntradayHeartRate, _selectedDate.value)
        recalculateStressForCurrentDevice()
    }

    private fun recalculateStressForCurrentDevice() {
        val canonical = _canonicalSummary.value
        val filter = _selectedDeviceFilter.value
        val dateKey = isoDateFormatter.format(Date(_selectedDate.value))
        val vitalsMap = _currentVitals.value.toMutableMap()

        val stress = canonical?.stress
        val summaryComputedAtMs = parseIsoToEpochMs(canonical?.computedAt)
        val latestHrAtMs = _latestBpmAt.value
        if (filter.isNullOrEmpty() && stress != null && summaryComputedAtMs != null &&
            (latestHrAtMs == null || summaryComputedAtMs + 90_000L >= latestHrAtMs)
        ) {
            _stressAnalysis.value = stress.toDomainAnalysis()
            _currentStressScore.value = stress.currentScore
            _currentStressLevel.value = stress.toDomainLevel()
            _intradayStress.value = stress.intradayStress
            val resolvedSrc = stress.sourceDevice?.takeIf { it.isNotEmpty() && !DeviceSource.from(it).isVirtualEngine }
                ?.let { DeviceSource.from(it).displayName }
                ?: _latestBpmSource.value
                ?: _stepsSourceDevice.value
                ?: _primarySleepSession.value?.sourceDevice
            vitalsMap[HealthMetricType.STRESS] = VitalMetricRecord(
                userId = currentUserId,
                type = HealthMetricType.STRESS.rawKey,
                value = stress.currentScore.toDouble(),
                unit = "pts",
                date = dateKey,
                sourceDevice = resolvedSrc
            )
            _currentVitals.value = vitalsMap
            return
        }

        val hasSdnn = (vitalsMap[HealthMetricType.HRV_SDNN]?.value ?: 0.0) > 0.0
        val hasRmssd = !hasSdnn && (vitalsMap[HealthMetricType.HRV_RMSSD]?.value ?: 0.0) > 0.0
        val hrvVal = when {
            hasSdnn -> vitalsMap[HealthMetricType.HRV_SDNN]?.value
            hasRmssd -> vitalsMap[HealthMetricType.HRV_RMSSD]?.value
            else -> null
        }
        val canonFilter = filter?.takeIf { it.isNotEmpty() }?.let { DeviceSource.from(it).displayName }

        // Anchor RHR to the active HR sensor's own RHR in All Devices mode to avoid cross-sensor optical bias
        val activeHrSensorCanon = canonFilter ?: _latestBpmSource.value
        val sensorMatchedRhr: Double? = run {
            if (!activeHrSensorCanon.isNullOrEmpty()) {
                val rowRhr = cachedLeanDailyVitals
                    .firstOrNull { DeviceSource.from(it.sourceDeviceKey).displayName == activeHrSensorCanon }
                    ?.restingHeartRate
                if (rowRhr != null && rowRhr > 0) return@run rowRhr.toDouble()
                val srvDerived = canonical?.sourcesBreakdown?.get(activeHrSensorCanon)?.get("derived_rhr")
                if (srvDerived != null && srvDerived > 0.0) return@run srvDerived
            }
            vitalsMap[HealthMetricType.RESTING_HEART_RATE]?.value
        }

        val hrPoints = _intradayHeartRate.value

        val summaryUsedRmssd = (canonical?.vitals?.get("hrvsdnn") == null) && (canonical?.vitals?.get("hrvrmssd") != null)
        val matchedBaselineHrv = canonical?.stress?.biometricDrivers?.baselineHrvMs?.takeIf { base ->
            base > 0.0 && ((hasRmssd && summaryUsedRmssd && base >= 35.0) || (hasSdnn && !summaryUsedRmssd && base <= 120.0))
        }

        if (hrvVal != null || hrPoints.isNotEmpty() || (sensorMatchedRhr != null && sensorMatchedRhr > 0.0)) {
            val stressCalc = StressAnalysisEngine.calculateStress(
                targetDate = Date(_selectedDate.value),
                hrvMs = hrvVal,
                isRmssd = hasRmssd,
                hrTelemetry = hrPoints,
                hourlySteps = _hourlySteps.value,
                restingBpm = sensorMatchedRhr?.takeIf { it > 0.0 },
                priorSleepScore = _primarySleepSession.value?.sleepScore,
                personalBaselineHrv = matchedBaselineHrv
            )
            if (stressCalc != null) {
                var (stressResult, intradayPoints) = stressCalc
                val srvScoreDouble = canonFilter?.let { canonical?.sourcesBreakdown?.get(it)?.get("stress_score") }
                if (srvScoreDouble != null) {
                    val srvScore = round(srvScoreDouble).toInt()
                    val srvAvg = canonFilter.let { canonical?.sourcesBreakdown?.get(it)?.get("stress_daily_avg") }
                        ?.let { round(it).toInt() } ?: stressResult.dailyAverageScore
                    val srvLevel = StressLevel.from(srvScore)
                    val para = minOf(90, maxOf(10, 100 - srvScore))
                    val mood = MonkeyMood.fromLevel(srvLevel)
                    stressResult = stressResult.copy(
                        currentScore = srvScore,
                        currentLevel = srvLevel,
                        dailyAverageScore = srvAvg,
                        parasympatheticPercent = para,
                        sympatheticPercent = 100 - para,
                        monkeyMood = mood,
                        adviceQuote = mood.adviceQuote,
                        recommendedBreathing = BreathingProtocol.defaultForLevel(srvLevel)
                    )
                }
                _currentStressScore.value = stressResult.currentScore
                _currentStressLevel.value = stressResult.currentLevel
                _stressAnalysis.value = stressResult
                _intradayStress.value = intradayPoints
                val attrSource = canonFilter
                    ?: _latestBpmSource.value
                    ?: vitalsMap[HealthMetricType.HRV_SDNN]?.sourceDevice
                    ?: vitalsMap[HealthMetricType.HRV_RMSSD]?.sourceDevice
                    ?: hrPoints.lastOrNull()?.sourceDevice
                vitalsMap[HealthMetricType.STRESS] = VitalMetricRecord(
                    userId = currentUserId,
                    type = HealthMetricType.STRESS.rawKey,
                    value = stressResult.currentScore.toDouble(),
                    unit = "pts",
                    date = dateKey,
                    sourceDevice = attrSource
                )
                _currentVitals.value = vitalsMap
                return
            }
        }

        _stressAnalysis.value = null
        _intradayStress.value = emptyList()
        _currentStressScore.value = 0
        _currentStressLevel.value = StressLevel.CALM
        vitalsMap.remove(HealthMetricType.STRESS)
        _currentVitals.value = vitalsMap
    }

    private fun applyCanonicalSummary(payload: DailyHealthSummaryPayload, dateKey: String) {
        _canonicalSummary.value = payload

        // Sleep
        _primarySleepSession.value = payload.sleep?.primarySession
        _allSleepSessions.value = payload.sleep?.allSessions ?: listOfNotNull(payload.sleep?.primarySession)
        _daytimeNaps.value = payload.sleep?.naps ?: emptyList()
        _sleepRecoveryVerdict.value = payload.sleep?.guidance?.verdict?.toDomain()
        _sleepActionableTips.value = payload.sleep?.guidance?.tips?.map { it.toDomain() } ?: emptyList()
        _sleepAIContext.value = payload.sleep?.guidance?.aiContext?.toDomain()

        // Activity
        val isAllDevices = _selectedDeviceSource.value == null && _selectedDeviceFilter.value.isNullOrEmpty()
        if (isAllDevices && payload.allDevicesView.containsKey("steps")) {
            _totalStepsToday.value = (payload.allDevicesView["steps"]?.value ?: 0.0).toInt()
            _stepsSourceDevice.value = payload.allDevicesView["steps"]?.sourceKey?.takeIf { it.isNotEmpty() }?.let { DeviceSource.from(it).displayName }
                ?: payload.activity?.sourceDevice?.let { DeviceSource.from(it).displayName }
        } else {
            _totalStepsToday.value = payload.activity?.totalSteps ?: 0
            _stepsSourceDevice.value = payload.activity?.sourceDevice?.let { DeviceSource.from(it).displayName }
        }

        if (isAllDevices && payload.allDevicesView.containsKey("active_energy")) {
            _totalActiveCalories.value = payload.allDevicesView["active_energy"]?.value ?: 0.0
        } else {
            _totalActiveCalories.value = payload.activity?.activeCaloriesKcal ?: 0.0
        }
        _hourlySteps.value = payload.activity?.hourlySteps ?: emptyList()

        // Cardiovascular
        val cardio = payload.cardiovascular
        val hrPts = cardio?.intradayHeartRate ?: emptyList()
        _intradayHeartRate.value = hrPts
        _restingBpm.value = cardio?.restingHeartRateBpm ?: 0.0
        _averageBpm.value = cardio?.averageHeartRateBpm ?: 0.0
        _maxBpm.value = cardio?.maxHeartRateBpm ?: 0.0
        _minBpm.value = cardio?.minHeartRateBpm ?: 0.0
        _heartRateZones.value = cardio?.heartRateZones?.toMap() ?: emptyMap()

        val srvLatest = cardio?.latestBpm
        if (srvLatest != null && srvLatest >= 30.0) {
            _latestBpm.value = srvLatest
            _latestBpmAt.value = parseIsoToEpochMs(cardio.latestBpmAt ?: payload.computedAt)
            _latestBpmSource.value = cardio.latestSourceDevice?.let { DeviceSource.from(it).displayName }
        } else {
            val lastPt = hrPts.lastOrNull()
            _latestBpm.value = lastPt?.bpm
            _latestBpmAt.value = lastPt?.timestamp
            _latestBpmSource.value = lastPt?.sourceDevice?.let { DeviceSource.from(it).displayName }
        }

        // Stress
        val stress = payload.stress
        if (stress != null) {
            _currentStressScore.value = stress.currentScore
            _currentStressLevel.value = stress.toDomainLevel()
            _stressAnalysis.value = stress.toDomainAnalysis()
            _intradayStress.value = stress.intradayStress
        } else {
            _currentStressScore.value = 0
            _currentStressLevel.value = StressLevel.CALM
            _stressAnalysis.value = null
            _intradayStress.value = emptyList()
        }

        // Vitals Map
        val vitalsMap = mutableMapOf<HealthMetricType, VitalMetricRecord>()
        for ((metricKey, item) in payload.vitals) {
            val type = HealthMetricType.from(metricKey) ?: continue
            vitalsMap[type] = VitalMetricRecord(
                id = UUID.randomUUID().toString(),
                userId = currentUserId,
                type = metricKey,
                value = item.value,
                unit = item.unit,
                date = dateKey,
                sourceDevice = item.sourceDevice?.let { src ->
                    val ds = DeviceSource.from(src)
                    if (ds.isVirtualEngine) null else ds.displayName
                }
            )
        }
        if (isAllDevices) {
            for ((metricKey, item) in payload.allDevicesView) {
                val type = HealthMetricType.from(metricKey) ?: continue
                if (item.value <= 0.0) continue
                vitalsMap[type] = VitalMetricRecord(
                    id = UUID.randomUUID().toString(),
                    userId = currentUserId,
                    type = metricKey,
                    value = item.value,
                    unit = item.unit,
                    date = dateKey,
                    sourceDevice = item.sourceKey.takeIf { it.isNotEmpty() }?.let { src ->
                        val ds = DeviceSource.from(src)
                        if (ds.isVirtualEngine) null else ds.displayName
                    },
                    createdAt = parseIsoToEpochMs(item.timestamp)
                )
            }
        }
        val lBpm = _latestBpm.value
        if (lBpm != null && lBpm >= 30.0) {
            vitalsMap[HealthMetricType.HEART_RATE] = VitalMetricRecord(
                id = UUID.randomUUID().toString(),
                userId = currentUserId,
                type = HealthMetricType.HEART_RATE.rawKey,
                value = lBpm,
                unit = "bpm",
                date = dateKey,
                sourceDevice = _latestBpmSource.value,
                createdAt = _latestBpmAt.value
            )
        }
        if (stress != null) {
            val stressSrc = stress.sourceDevice?.takeIf { it.isNotEmpty() && !DeviceSource.from(it).isVirtualEngine }
                ?.let { DeviceSource.from(it).displayName }
                ?: _latestBpmSource.value
                ?: _stepsSourceDevice.value
            vitalsMap[HealthMetricType.STRESS] = VitalMetricRecord(
                id = UUID.randomUUID().toString(),
                userId = currentUserId,
                type = HealthMetricType.STRESS.rawKey,
                value = stress.currentScore.toDouble(),
                unit = "pts",
                date = dateKey,
                sourceDevice = stressSrc
            )
        }
        _currentVitals.value = vitalsMap

        // Only populate from payload.sources if lean caches are not yet loaded for this date
        if (cachedLeanSleepSessions.isEmpty() && cachedLeanDailyVitals.isEmpty() && cachedLeanIntradayHeartRate.isEmpty()) {
            val sourcesList = payload.sources
                .map { DeviceSource.from(it) }
                .filter { !it.isVirtualEngine }
                .distinctBy { it.displayName }
                .sortedWith(compareBy<DeviceSource> { effectivePriorityRank(it.displayName) }.thenBy { it.displayName })
            _availableSources.value = sourcesList
            _availableDevices.value = sourcesList.map { it.displayName }
            rebuildConfigurableSources()
        }
    }

    private fun ensureLocalDeviceSourcesPopulated() {
        val canonicalList = _availableSources.value
            .filter { !it.isVirtualEngine }
            .distinctBy { it.displayName }
            .sortedWith(compareBy<DeviceSource> { effectivePriorityRank(it.displayName) }.thenBy { it.displayName })
        _availableSources.value = canonicalList
        _availableDevices.value = canonicalList.map { it.displayName }
    }

    private fun updateDevicesAndSources() {
        val srcSet = mutableSetOf<DeviceSource>()
        for (t in cachedTelemetry) {
            val d = t.sourceDevice
            if (!d.isNullOrEmpty()) {
                val src = DeviceSource.from(d)
                if (!src.isVirtualEngine) srcSet.add(src)
            }
        }
        for (v in cachedVitals) {
            val d = v.sourceDevice
            if (!d.isNullOrEmpty()) {
                val src = DeviceSource.from(d)
                if (!src.isVirtualEngine) srcSet.add(src)
            }
        }
        val sorted = srcSet.toList().sortedWith(
            compareBy<DeviceSource> { effectivePriorityRank(it.displayName) }.thenBy { it.displayName }
        )
        _availableSources.value = sorted
        _availableDevices.value = sorted.map { it.displayName }
        rebuildConfigurableSources()
    }

    private suspend fun processDataForCurrentDate() {
        val targetEpochMs = _selectedDate.value
        val targetDate = Date(targetEpochMs)
        val dateKey = isoDateFormatter.format(targetDate)

        var telemetry = cachedTelemetry
        var vitals = cachedVitals

        // Filter by device source if active
        val filterSource = _selectedDeviceSource.value
        val filterDevice = _selectedDeviceFilter.value

        if (filterSource != null) {
            telemetry = telemetry.filter { DeviceSource.from(it.sourceDevice) == filterSource }
            vitals = vitals.filter { DeviceSource.from(it.sourceDevice) == filterSource }
        } else if (!filterDevice.isNullOrEmpty()) {
            telemetry = telemetry.filter { it.sourceDevice?.contains(filterDevice, ignoreCase = true) == true }
            vitals = vitals.filter { it.sourceDevice?.contains(filterDevice, ignoreCase = true) == true }
        }

        // Vitals map (filtering virtual computational engines)
        val vitalsMap = mutableMapOf<HealthMetricType, VitalMetricRecord>()
        val vitalsValues = mutableMapOf<HealthMetricType, Double>()
        for (v in vitals) {
            val type = v.metricType
            if (type != null) {
                if (v.sourceDevice != null && DeviceSource.from(v.sourceDevice).isVirtualEngine) {
                    continue
                }
                vitalsMap[type] = v
                vitalsValues[type] = v.value
            }
        }

        // Synthesize missing vitals from telemetry
        val sortedTelemetry = telemetry.sortedBy { it.startTime }
        for (t in sortedTelemetry) {
            val valNum = t.value ?: continue
            if (valNum <= 0) continue
            val metricType = HealthMetricType.from(t.type) ?: continue

            if (metricType == HealthMetricType.STEPS || t.isSleep || t.isSleepStage) continue

            val existing = vitalsMap[metricType]
            if (existing == null || t.startTime >= (existing.createdAt ?: 0L)) {
                val record = VitalMetricRecord(
                    userId = t.userId,
                    type = metricType.name,
                    value = valNum,
                    unit = t.unit ?: metricType.defaultUnit,
                    date = dateKey,
                    sourceDevice = t.sourceDevice,
                    createdAt = t.startTime
                )
                vitalsMap[metricType] = record
                vitalsValues[metricType] = valNum
            }
        }

        // 1. Process Sleep using SleepClusteringEngine
        val sleepResult = SleepClusteringEngine.clusterSleep(
            targetDate = targetDate,
            telemetry = telemetry,
            vitalsSummary = vitalsValues,
            preferredDevice = filterDevice
        )
        _primarySleepSession.value = sleepResult.primarySession
        _allSleepSessions.value = sleepResult.allSessions
        _daytimeNaps.value = sleepResult.naps

        // Run clinical sleep analysis engine
        if (sleepResult.primarySession != null) {
            val analysis = SleepAnalysisEngine.analyze(
                session = sleepResult.primarySession,
                nocturnalRestingBpm = vitalsValues[HealthMetricType.RESTING_HEART_RATE],
                nocturnalHrvMs = vitalsValues[HealthMetricType.HRV_SDNN] ?: vitalsValues[HealthMetricType.HRV_RMSSD]
            )
            _sleepRecoveryVerdict.value = analysis.verdict
            _sleepActionableTips.value = analysis.tips
            _sleepAIContext.value = analysis.aiContext
        } else {
            _sleepRecoveryVerdict.value = null
            _sleepActionableTips.value = emptyList()
            _sleepAIContext.value = null
        }

        // 2. Process Heart Rate
        val cal = Calendar.getInstance()
        val hrTelemetry = telemetry.filter {
            it.isHeartRate && isSameDay(it.startTime, targetEpochMs)
        }
        val hrPoints = mutableListOf<IntradayHeartRatePoint>()
        for (r in hrTelemetry) {
            val bpm = r.value ?: continue
            if (bpm in 31.0..239.0) {
                hrPoints.add(
                    IntradayHeartRatePoint(
                        id = r.id,
                        timestamp = r.startTime,
                        bpm = bpm,
                        sourceDevice = r.sourceDevice
                    )
                )
            }
        }
        val sortedHrPoints = hrPoints.sortedBy { it.timestamp }
        _intradayHeartRate.value = sortedHrPoints
        _latestBpm.value = sortedHrPoints.lastOrNull()?.bpm

        if (sortedHrPoints.isNotEmpty()) {
            val bpms = sortedHrPoints.map { it.bpm }
            _averageBpm.value = round(bpms.average())
            _minBpm.value = bpms.minOrNull() ?: 0.0
            _maxBpm.value = bpms.maxOrNull() ?: 0.0
            _restingBpm.value = vitalsValues[HealthMetricType.RESTING_HEART_RATE]
                ?: if (_minBpm.value > 0) _minBpm.value + 4.0 else 62.0

            val zones = mutableMapOf(
                HeartRateZone.RESTING to 0,
                HeartRateZone.FAT_BURN to 0,
                HeartRateZone.CARDIO to 0,
                HeartRateZone.PEAK to 0
            )
            for (pt in sortedHrPoints) {
                zones[pt.zone] = (zones[pt.zone] ?: 0) + 1
            }
            _heartRateZones.value = zones
        } else {
            _averageBpm.value = vitalsValues[HealthMetricType.HEART_RATE] ?: 0.0
            _restingBpm.value = vitalsValues[HealthMetricType.RESTING_HEART_RATE] ?: 0.0
            _minBpm.value = 0.0
            _maxBpm.value = 0.0
            _heartRateZones.value = emptyMap()
        }

        // 3. Process Steps & Hourly Cadence
        val stepsResult = calculateDailySteps(
            targetDate = targetDate,
            telemetry = telemetry,
            vitalsSummary = vitalsValues,
            preferredDevice = filterDevice,
            preferredSource = filterSource
        )
        _hourlySteps.value = stepsResult.hourlyBuckets
        _totalStepsToday.value = stepsResult.totalSteps
        _totalActiveCalories.value = stepsResult.activeCalories
        _stepsSourceDevice.value = stepsResult.sourceDeviceUsed

        // Fill computed resting HR in currentVitals
        if (vitalsMap[HealthMetricType.RESTING_HEART_RATE] == null && _restingBpm.value > 0) {
            val rhrRecord = VitalMetricRecord(
                userId = "computed",
                type = "resting_heart_rate",
                value = _restingBpm.value,
                unit = "bpm",
                date = dateKey,
                sourceDevice = filterDevice ?: filterSource?.displayName ?: "Biometric Engine"
            )
            vitalsMap[HealthMetricType.RESTING_HEART_RATE] = rhrRecord
            vitalsValues[HealthMetricType.RESTING_HEART_RATE] = _restingBpm.value
        }

        // 4. Process Stress using StressAnalysisEngine v2.0
        val hasSdnnRaw = (vitalsValues[HealthMetricType.HRV_SDNN] ?: 0.0) > 0.0
        val hasRmssdRaw = !hasSdnnRaw && (vitalsValues[HealthMetricType.HRV_RMSSD] ?: 0.0) > 0.0
        val hrvVal = when {
            hasSdnnRaw -> vitalsValues[HealthMetricType.HRV_SDNN]
            hasRmssdRaw -> vitalsValues[HealthMetricType.HRV_RMSSD]
            else -> null
        }
        val stressCalculation = StressAnalysisEngine.calculateStress(
            targetDate = targetDate,
            hrvMs = hrvVal,
            isRmssd = hasRmssdRaw,
            hrTelemetry = sortedHrPoints,
            hourlySteps = stepsResult.hourlyBuckets,
            restingBpm = vitalsValues[HealthMetricType.RESTING_HEART_RATE] ?: _restingBpm.value.takeIf { it > 0 },
            priorSleepScore = _primarySleepSession.value?.sleepScore
        )

        if (stressCalculation != null) {
            val (stressResult, intradayPoints) = stressCalculation
            _currentStressScore.value = stressResult.currentScore
            _currentStressLevel.value = stressResult.currentLevel
            _stressAnalysis.value = stressResult
            _intradayStress.value = intradayPoints

            // Resolve honest source device
            val resolvedSourceDevice = filterDevice
                ?: filterSource?.displayName
                ?: vitalsMap[HealthMetricType.HRV_SDNN]?.sourceDevice?.takeIf { !DeviceSource.from(it).isVirtualEngine }
                ?: vitalsMap[HealthMetricType.HRV_RMSSD]?.sourceDevice?.takeIf { !DeviceSource.from(it).isVirtualEngine }
                ?: sortedHrPoints.lastOrNull { it.sourceDevice != null && !DeviceSource.from(it.sourceDevice).isVirtualEngine }?.sourceDevice
                ?: "Daily Biometric Engine"

            val stressRecord = VitalMetricRecord(
                userId = currentUserId,
                type = "stress",
                value = stressResult.currentScore.toDouble(),
                unit = "pts",
                date = dateKey,
                sourceDevice = resolvedSourceDevice
            )
            vitalsMap[HealthMetricType.STRESS] = stressRecord
            vitalsValues[HealthMetricType.STRESS] = stressResult.currentScore.toDouble()
        } else {
            _currentStressScore.value = 0
            _currentStressLevel.value = StressLevel.CALM
            _stressAnalysis.value = null
            _intradayStress.value = emptyList()
            vitalsMap.remove(HealthMetricType.STRESS)
            vitalsValues.remove(HealthMetricType.STRESS)
        }

        _currentVitals.value = vitalsMap

        // Persist computed daily vitals to Room and sync to Supabase
        val vitalsToSave = vitalsMap.values.toList()
        if (vitalsToSave.isNotEmpty()) {
            withContext(Dispatchers.IO) {
                vitalsDao.insertVitals(vitalsToSave.map { VitalMetricEntity.fromRecord(it) })
            }
            if (currentUserId != "local_user") {
                scope.launch(Dispatchers.IO) {
                    syncVitalsToSupabase(vitalsToSave)
                }
            }
        }
    }

    // MARK: - 7-Day Trend Generator

    private suspend fun loadHistoricalTrends(selectedDate: Date) {
        val cal = Calendar.getInstance()
        val trends = mutableMapOf<HealthMetricType, List<DailyMetricTrendPoint>>()
        val metrics = listOf(
            HealthMetricType.STEPS,
            HealthMetricType.SLEEP_DURATION,
            HealthMetricType.HEART_RATE,
            HealthMetricType.STRESS,
            HealthMetricType.HRV_SDNN,
            HealthMetricType.ACTIVE_ENERGY,
            HealthMetricType.WEIGHT
        )

        val selectedMidnight = getStartOfDay(selectedDate.time)
        val selectedDateKey = isoDateFormatter.format(selectedDate)
        cal.timeInMillis = selectedMidnight
        cal.add(Calendar.DAY_OF_YEAR, -6)
        val minDateKey = isoDateFormatter.format(cal.time)

        val historicalVitalsByDate = mutableMapOf<String, MutableMap<HealthMetricType, Double>>()
        val filter = _selectedDeviceFilter.value
        val isAllDevices = filter.isNullOrEmpty()
        val targetCanon = filter?.let { DeviceSource.from(it).displayName }

        // 1. Read cached canonical summaries from Room ONLY in All Devices mode
        if (isAllDevices) {
            val cachedSummaries = withContext(Dispatchers.IO) {
                summaryDao.getSummariesInRange(currentUserId, minDateKey, selectedDateKey)
            }
            for (summaryEntity in cachedSummaries) {
                if (summaryEntity.summaryVersion < CURRENT_SUMMARY_CACHE_VERSION) continue
                val dKey = summaryEntity.dateKey
                try {
                    val payload = jsonSerializer.decodeFromString<DailyHealthSummaryPayload>(summaryEntity.payloadJson)
                    payload.activity?.totalSteps?.takeIf { it > 0 }?.let {
                        historicalVitalsByDate.getOrPut(dKey) { mutableMapOf() }[HealthMetricType.STEPS] = it.toDouble()
                    }
                    val sleepSec = payload.sleep?.primarySession?.asleepSeconds?.takeIf { it > 0 }
                        ?: payload.sleep?.naps?.sumOf { it.durationSeconds }?.takeIf { it > 0 }
                    sleepSec?.let {
                        historicalVitalsByDate.getOrPut(dKey) { mutableMapOf() }[HealthMetricType.SLEEP_DURATION] = it / 60.0
                    }
                    payload.cardiovascular?.restingHeartRateBpm?.takeIf { it > 0 }?.let {
                        historicalVitalsByDate.getOrPut(dKey) { mutableMapOf() }[HealthMetricType.HEART_RATE] = it
                    }
                    payload.stress?.currentScore?.takeIf { it > 0 }?.let {
                        historicalVitalsByDate.getOrPut(dKey) { mutableMapOf() }[HealthMetricType.STRESS] = it.toDouble()
                    }
                    payload.stress?.biometricDrivers?.currentHrvMs?.takeIf { it > 0 }?.let {
                        historicalVitalsByDate.getOrPut(dKey) { mutableMapOf() }[HealthMetricType.HRV_SDNN] = it
                    }
                    payload.activity?.activeCaloriesKcal?.takeIf { it > 0 }?.let {
                        historicalVitalsByDate.getOrPut(dKey) { mutableMapOf() }[HealthMetricType.ACTIVE_ENERGY] = it
                    }
                } catch (_: Exception) {}
            }
        }

        // 2. Query Room vitals matching canonical device filter (if any)
        for (dayOffset in 0..6) {
            cal.timeInMillis = selectedMidnight
            cal.add(Calendar.DAY_OF_YEAR, -dayOffset)
            val dKey = isoDateFormatter.format(cal.time)
            val historyVitals = withContext(Dispatchers.IO) {
                vitalsDao.getVitalsForDateSync(currentUserId, dKey)
            }
            for (v in historyVitals) {
                if (targetCanon != null) {
                    val vSrc = v.sourceDevice ?: continue
                    if (DeviceSource.from(vSrc).displayName != targetCanon) continue
                }
                val t = HealthMetricType.from(v.type)
                if (t != null && v.value > 0.0) {
                    val map = historicalVitalsByDate.getOrPut(dKey) { mutableMapOf() }
                    if (!map.containsKey(t)) {
                        map[t] = v.value
                    }
                }
            }
        }

        // 3. For authenticated users, fetch remote scalar summaries & lean tables (30-min Trends cache + live Today overlay)
        if (currentUserId != "local_user") {
            try {
                val trendsCacheKey = "$currentUserId|$minDateKey|$selectedDateKey"
                val nowMs = System.currentTimeMillis()
                val cachedEntry = trendsRemoteCache?.takeIf {
                    it.cacheKey == trendsCacheKey && (nowMs - it.fetchedAtMs) < 30 * 60 * 1000L
                }

                val (remoteSummaries, cachedRemoteSleep, cachedRemoteVitals) = if (cachedEntry != null) {
                    Triple(cachedEntry.summaries, cachedEntry.sleep, cachedEntry.vitals)
                } else {
                    coroutineScope {
                        val remoteSummariesDeferred = async(Dispatchers.IO) {
                            try {
                                remoteService.fetchDailySummariesBetween(currentUserId, minDateKey, selectedDateKey)
                            } catch (e: Exception) {
                                emptyList()
                            }
                        }
                        val remoteSleepDeferred = async(Dispatchers.IO) {
                            try {
                                remoteService.fetchSleepSessionsBetween(currentUserId, minDateKey, selectedDateKey)
                            } catch (e: Exception) {
                                emptyList()
                            }
                        }
                        val remoteVitalsDeferred = async(Dispatchers.IO) {
                            try {
                                remoteService.fetchDailyVitalsBetween(currentUserId, minDateKey, selectedDateKey)
                            } catch (e: Exception) {
                                emptyList()
                            }
                        }

                        val fetchedSummaries = remoteSummariesDeferred.await()
                        val fetchedSleep = remoteSleepDeferred.await()
                        val fetchedVitals = remoteVitalsDeferred.await()
                        trendsRemoteCache = TrendsRemoteCacheEntry(
                            cacheKey = trendsCacheKey,
                            fetchedAtMs = System.currentTimeMillis(),
                            summaries = fetchedSummaries,
                            sleep = fetchedSleep,
                            vitals = fetchedVitals
                        )
                        Triple(fetchedSummaries, fetchedSleep, fetchedVitals)
                    }
                }

                // Overlay live in-memory lean rows for selectedDateKey so Today's Trend bar stays fresh without invalidating 30m cache
                val liveSelectedVitals = cachedLeanDailyVitals.filter { it.localDate == selectedDateKey }
                val remoteVitals = if (liveSelectedVitals.isNotEmpty()) {
                    mergeLeanDailyVitals(
                        remote = cachedRemoteVitals.filter { it.localDate == selectedDateKey },
                        local = liveSelectedVitals
                    ) + cachedRemoteVitals.filter { it.localDate != selectedDateKey }
                } else {
                    cachedRemoteVitals
                }

                val liveSelectedSleep = cachedLeanSleepSessions.filter { it.localDate == selectedDateKey }
                val remoteSleep = if (liveSelectedSleep.isNotEmpty()) {
                    mergeLeanSleepSessions(
                        remote = cachedRemoteSleep.filter { it.localDate == selectedDateKey },
                        local = liveSelectedSleep
                    ) + cachedRemoteSleep.filter { it.localDate != selectedDateKey }
                } else {
                    cachedRemoteSleep
                }

                run {
                    // Group lean vitals by date and apply canonical device filter
                    val vitalsByDate = remoteVitals
                        .filter { v ->
                            if (targetCanon != null) {
                                DeviceSource.from(v.sourceDeviceKey).displayName == targetCanon
                            } else true
                        }
                        .groupBy { it.localDate }

                    // Group lean sleep by date and apply canonical device filter
                    val sleepByDate = remoteSleep
                        .filter { s ->
                            if (targetCanon != null) {
                                DeviceSource.from(s.sourceDeviceKey).displayName == targetCanon
                            } else true
                        }
                        .groupBy { it.localDate }

                    for ((dKey, rows) in vitalsByDate) {
                        val map = historicalVitalsByDate.getOrPut(dKey) { mutableMapOf() }
                        val act = arbitrateHourlyActivity(rows, cachedLeanSources)
                        if (act.totalSteps > 0) map[HealthMetricType.STEPS] = act.totalSteps.toDouble()
                        if (act.activeCalories > 0.0) map[HealthMetricType.ACTIVE_ENERGY] = act.activeCalories

                        val sortedByPrio = rows.sortedBy { effectivePriorityRank(it.sourceDeviceKey) }
                        sortedByPrio.mapNotNull { it.restingHeartRate }.firstOrNull { it > 0 }?.let {
                            map[HealthMetricType.HEART_RATE] = it.toDouble()
                        }
                        arbitrateSpotVital(rows, "spo2", cachedLeanSources, 1_800_000L) { it.spo2 }?.let {
                            map[HealthMetricType.OXYGEN_SATURATION] = it.value
                        }
                        arbitrateSpotVital(rows, "weight", cachedLeanSources, 1_800_000L) { it.weightKg }?.let {
                            map[HealthMetricType.WEIGHT] = it.value
                        }
                        val hrvVal = sortedByPrio.mapNotNull { it.hrvSdnnNightly }.firstOrNull { it > 0.0 }
                            ?: sortedByPrio.mapNotNull { it.hrvRmssdNightly }.firstOrNull { it > 0.0 }
                        if (hrvVal != null) {
                            map[HealthMetricType.HRV_SDNN] = hrvVal
                        }
                        sortedByPrio.mapNotNull { it.skinTempCelsius }.firstOrNull()?.let {
                            map[HealthMetricType.BODY_TEMPERATURE] = it
                        }
                        sortedByPrio.mapNotNull { it.respiratoryRate }.firstOrNull { it > 0.0 }?.let {
                            map[HealthMetricType.RESPIRATORY_RATE] = it
                        }

                        // Per-device historical stress calculation when filtered to a specific device
                        if (!isAllDevices) {
                            val rhrForStress = sortedByPrio.mapNotNull { it.restingHeartRate }.firstOrNull { it > 0 }?.toDouble()
                            val sleepScoreForDay = sleepByDate[dKey]?.firstOrNull { it.sessionType == "primary_sleep" }?.sleepScore
                            if (hrvVal != null || rhrForStress != null) {
                                val parsedDay = runCatching { isoDateFormatter.parse(dKey) }.getOrNull() ?: selectedDate
                                val calc = StressAnalysisEngine.calculateStress(
                                    targetDate = parsedDay,
                                    hrvMs = hrvVal,
                                    hrTelemetry = emptyList(),
                                    hourlySteps = emptyList(),
                                    restingBpm = rhrForStress,
                                    priorSleepScore = sleepScoreForDay
                                )
                                if (calc != null && calc.first.currentScore > 0) {
                                    map[HealthMetricType.STRESS] = calc.first.currentScore.toDouble()
                                }
                            }
                        }
                    }

                    for ((dKey, rows) in sleepByDate) {
                        val sortedRows = rows.sortedWith(
                            compareByDescending<HealthSleepSessionRecord> { it.isUserSelected }
                                .thenByDescending { it.hasGranularSleepStages }
                                .thenBy { effectivePriorityRank(it.sourceDeviceKey) }
                                .thenByDescending { it.durationSeconds }
                        )
                        val primary = sortedRows.firstOrNull { it.sessionType == "primary_sleep" } ?: sortedRows.firstOrNull()
                        if (primary != null && primary.durationSeconds > 0) {
                            val map = historicalVitalsByDate.getOrPut(dKey) { mutableMapOf() }
                            val asleepMinutes = primary.durationSeconds.toDouble() / 60.0
                            map[HealthMetricType.SLEEP_DURATION] = asleepMinutes
                        }
                    }

                    // Fallback to health_daily_summary ONLY in All Devices mode
                    if (isAllDevices) {
                        for (record in remoteSummaries) {
                            val dKey = record.localDate
                            val map = historicalVitalsByDate.getOrPut(dKey) { mutableMapOf() }
                            if (!map.containsKey(HealthMetricType.STEPS)) {
                                record.steps?.takeIf { it > 0 }?.let { map[HealthMetricType.STEPS] = it.toDouble() }
                            }
                            if (!map.containsKey(HealthMetricType.SLEEP_DURATION)) {
                                record.sleepAsleepS?.takeIf { it > 0 }?.let { map[HealthMetricType.SLEEP_DURATION] = it.toDouble() / 60.0 }
                            }
                            if (!map.containsKey(HealthMetricType.HEART_RATE)) {
                                record.rhr?.takeIf { it > 0 }?.let { map[HealthMetricType.HEART_RATE] = it }
                            }
                            if (!map.containsKey(HealthMetricType.STRESS)) {
                                record.stressAvg?.takeIf { it > 0 }?.let { map[HealthMetricType.STRESS] = it.toDouble() }
                            }
                            if (!map.containsKey(HealthMetricType.HRV_SDNN)) {
                                record.hrvSdnn?.takeIf { it > 0 }?.let { map[HealthMetricType.HRV_SDNN] = it }
                            }
                            if (!map.containsKey(HealthMetricType.ACTIVE_ENERGY)) {
                                record.activeKcal?.takeIf { it > 0 }?.let { map[HealthMetricType.ACTIVE_ENERGY] = it }
                            }
                            if (!map.containsKey(HealthMetricType.WEIGHT)) {
                                record.weight?.takeIf { it > 0 }?.let { map[HealthMetricType.WEIGHT] = it }
                            }
                            if (!map.containsKey(HealthMetricType.OXYGEN_SATURATION)) {
                                record.spo2?.takeIf { it > 0 }?.let { map[HealthMetricType.OXYGEN_SATURATION] = it }
                            }

                            // Also cache into Room ONLY if full payload exists (never overwrite full JSONB with scalar-only row)
                            val payload = record.summary
                            if (payload != null) {
                                val payloadJson = jsonSerializer.encodeToString(payload)
                                withContext(Dispatchers.IO) {
                                    summaryDao.upsertSummary(
                                        HealthDailySummaryEntity(
                                            id = record.id.ifEmpty { "summary_${currentUserId}_$dKey" },
                                            userId = currentUserId,
                                            dateKey = dKey,
                                            summaryVersion = CURRENT_SUMMARY_CACHE_VERSION,
                                            payloadJson = payloadJson,
                                            computedAt = System.currentTimeMillis()
                                        )
                                    )
                                }
                            }
                        }
                    }
                }
            } catch (_: Exception) {}
        }

        // 4. Assemble final trend points with honest data (zero synthetic fallback)
        for (m in metrics) {
            val points = mutableListOf<DailyMetricTrendPoint>()
            for (dayOffset in (0..6).reversed()) {
                cal.timeInMillis = selectedMidnight
                cal.add(Calendar.DAY_OF_YEAR, -dayOffset)
                val dayTime = cal.timeInMillis
                val dateStr = isoDateFormatter.format(Date(dayTime))
                val isComplete = dayOffset > 0
                val target = defaultTarget(m)

                val valNum = if (dayOffset == 0) {
                    historicalVitalsByDate[dateStr]?.get(m) ?: when (m) {
                        HealthMetricType.STEPS -> _totalStepsToday.value.toDouble()
                        HealthMetricType.SLEEP_DURATION -> (_primarySleepSession.value?.asleepSeconds ?: 0.0) / 60.0
                        HealthMetricType.HEART_RATE -> if (_averageBpm.value > 0) _averageBpm.value else _restingBpm.value
                        HealthMetricType.STRESS -> _currentStressScore.value.toDouble()
                        HealthMetricType.ACTIVE_ENERGY -> _totalActiveCalories.value
                        else -> _currentVitals.value[m]?.value ?: 0.0
                    }
                } else {
                    historicalVitalsByDate[dateStr]?.get(m) ?: 0.0
                }

                points.add(
                    DailyMetricTrendPoint(
                        date = dayTime,
                        value = valNum,
                        target = target,
                        isCompleteDay = isComplete && valNum > 0.0
                    )
                )
            }
            trends[m] = points
        }

        _historicalTrends.value = trends
    }

    private fun defaultTarget(metric: HealthMetricType): Double = when (metric) {
        HealthMetricType.STEPS -> 10_000.0
        HealthMetricType.SLEEP_DURATION -> 480.0 // 8 hours in minutes
        HealthMetricType.ACTIVE_ENERGY -> 550.0 // kcal
        HealthMetricType.HYDRATION -> 2_500.0 // ml
        HealthMetricType.STRESS -> 35.0 // Optimal recovery threshold matching iOS
        else -> 0.0
    }

    // MARK: - Daily Steps Calculation

    private fun calculateDailySteps(
        targetDate: Date,
        telemetry: List<HealthTelemetryRecord>,
        vitalsSummary: Map<HealthMetricType, Double>,
        preferredDevice: String?,
        preferredSource: DeviceSource?
    ): DailyStepsResult {
        val cal = Calendar.getInstance()
        val daySteps = telemetry.filter { it.isSteps && isSameDay(it.startTime, targetDate.time) }

        val grouped = daySteps.groupBy { DeviceSource.from(it.sourceDevice).displayName }
        data class DeviceResult(val device: String, val total: Int, val hourly: Map<Int, Int>, val isWearable: Boolean)
        val deviceResults = mutableListOf<DeviceResult>()

        for ((device, records) in grouped) {
            val source = DeviceSource.from(device)
            if (source.isVirtualEngine) continue
            val isWearable = source.isWearable

            val isCumulative = isCumulativeStepDevice(device, records)
            val hourlyMap = mutableMapOf<Int, Int>()
            var total = 0

            if (isCumulative) {
                val sorted = records.sortedBy { it.startTime }
                val maxVal = sorted.mapNotNull { it.value }.maxOrNull() ?: 0.0
                total = maxVal.toInt()

                var prevVal = 0.0
                for (r in sorted) {
                    val v = r.value ?: continue
                    if (v <= 0) continue
                    val delta = if (v >= prevVal) (v - prevVal) else v
                    cal.timeInMillis = r.startTime
                    val hour = cal.get(Calendar.HOUR_OF_DAY)
                    hourlyMap[hour] = (hourlyMap[hour] ?: 0) + delta.toInt()
                    prevVal = v
                }
            } else {
                val sorted = records.sortedBy { it.startTime }
                val uniqueSlices = mutableListOf<HealthTelemetryRecord>()
                for (r in sorted) {
                    if (uniqueSlices.isNotEmpty()) {
                        val last = uniqueSlices.last()
                        val isIdentical = abs(last.startTime - r.startTime) < 5000 &&
                                abs((last.endTime ?: last.startTime) - (r.endTime ?: r.startTime)) < 5000
                        if (isIdentical) continue
                    }
                    uniqueSlices.add(r)
                }

                for (r in uniqueSlices) {
                    val v = (r.value ?: 0.0).toInt()
                    cal.timeInMillis = r.startTime
                    val hour = cal.get(Calendar.HOUR_OF_DAY)
                    hourlyMap[hour] = (hourlyMap[hour] ?: 0) + v
                }
                total = hourlyMap.values.sum()
            }

            deviceResults.add(DeviceResult(device, total, hourlyMap, isWearable))
        }

        val isAllDevices = preferredSource == null && preferredDevice.isNullOrEmpty()
        var chosen: DeviceResult? = null
        if (preferredSource != null) {
            chosen = deviceResults.firstOrNull {
                val dSrc = DeviceSource.from(it.device)
                dSrc == preferredSource || dSrc.displayName.equals(preferredSource.displayName, ignoreCase = true)
            }
        }
        if (chosen == null && !preferredDevice.isNullOrEmpty()) {
            val pdCanon = DeviceSource.from(preferredDevice).displayName
            chosen = deviceResults.firstOrNull {
                it.device.contains(preferredDevice, ignoreCase = true) ||
                    DeviceSource.from(it.device).displayName.equals(pdCanon, ignoreCase = true)
            }
        }
        if (chosen == null && isAllDevices) {
            val wearables = deviceResults.filter { it.isWearable && it.total > 0 }
            chosen = wearables.maxByOrNull { it.total } ?: deviceResults.maxByOrNull { it.total }
        }

        var chosenTotal = chosen?.total ?: 0
        val chosenHourly = chosen?.hourly ?: emptyMap()
        var chosenDevice = chosen?.device
        val vitalsSteps = vitalsSummary[HealthMetricType.STEPS]
        if (vitalsSteps != null && vitalsSteps > 0) {
            val vitalsInt = vitalsSteps.toInt()
            if (isAllDevices) {
                if (vitalsInt > chosenTotal) {
                    chosenTotal = vitalsInt
                    if (chosenDevice == null) chosenDevice = "Smartwatch"
                }
            } else if (chosenTotal == 0) {
                chosenTotal = vitalsInt
            }
        }

        val buckets = (0..23).map { h ->
            HourlyStepBucket(
                id = h,
                hour = h,
                steps = chosenHourly[h] ?: 0
            )
        }

        var activeCal = vitalsSummary[HealthMetricType.ACTIVE_ENERGY] ?: 0.0
        if (activeCal <= 0.0) {
            val energyRecs = telemetry.filter {
                it.normalizedType == "activeenergy" || it.normalizedType == "calories"
            }
            if (chosenDevice != null) {
                val devEnergy = energyRecs.filter { it.sourceDevice == chosenDevice }
                if (isCumulativeStepDevice(chosenDevice, devEnergy)) {
                    activeCal = devEnergy.mapNotNull { it.value }.maxOrNull() ?: 0.0
                } else {
                    activeCal = devEnergy.mapNotNull { it.value }.sum()
                }
            }
            if (activeCal <= 0.0) {
                activeCal = (chosenTotal * 0.042).round(0)
            }
        }

        return DailyStepsResult(
            totalSteps = chosenTotal,
            hourlyBuckets = buckets,
            activeCalories = activeCal,
            sourceDeviceUsed = chosenDevice
        )
    }

    private fun isCumulativeStepDevice(device: String, records: List<HealthTelemetryRecord>): Boolean {
        val lower = device.lowercase()
        if (lower.contains("zepp") || lower.contains("amazfit") || lower.contains("balance") ||
            lower.contains("huawei") || lower.contains("harmony") || lower.contains("gt5")
        ) {
            return true
        }
        val nonZero = records.mapNotNull { it.value }.filter { it > 0 }
        if (nonZero.size >= 2) {
            val isIncreasing = nonZero.zipWithNext().all { (a, b) -> a <= b }
            val hasLargeValues = nonZero.any { it >= 500.0 }
            if (isIncreasing && hasLargeValues) return true
        }
        return false
    }

    private fun deduplicateTelemetry(records: List<HealthTelemetryRecord>): List<HealthTelemetryRecord> {
        val seen = mutableSetOf<String>()
        val unique = mutableListOf<HealthTelemetryRecord>()

        for (r in records) {
            val typeKey = r.normalizedType
            val devKey = r.sourceDevice?.lowercase()?.trim() ?: ""
            val stKey = r.startTime / 1000
            val etKey = (r.endTime ?: r.startTime) / 1000
            val valKey = ((r.value ?: 0.0) * 100).toInt()

            val compositeKey = "${typeKey}_${devKey}_${stKey}_${etKey}_${valKey}"
            if (seen.add(compositeKey)) {
                unique.add(r)
            }
        }
        return unique
    }

    // MARK: - Supabase Cloud Synchronization

    fun triggerCanonicalEngineIfNeeded(
        dateKey: String,
        fingerprint: String? = null,
        force: Boolean = false
    ) {
        if (currentUserId == "local_user") return
        val now = System.currentTimeMillis()
        val last = lastEngineInvocation[dateKey] ?: 0L
        val prevFp = lastEnginePayloadFingerprint[dateKey]
        val changedFp = !fingerprint.isNullOrEmpty() && fingerprint != prevFp
        val minIntervalMs = if (changedFp) 20_000L else 180_000L
        if (!force && now - last < minIntervalMs) {
            return
        }
        lastEngineInvocation[dateKey] = now
        if (!fingerprint.isNullOrEmpty()) {
            lastEnginePayloadFingerprint[dateKey] = fingerprint
        }
        scope.launch(Dispatchers.IO) {
            try {
                remoteService.triggerCanonicalEngine(currentUserId, date = dateKey)
            } catch (e: Exception) {
                android.util.Log.w("HealthDataRepository", "Failed to trigger canonical engine for $dateKey: ${e.message}")
            }
        }
    }

    // MARK: - Lean Health Ingestion (v2.1 Canonical Full-Day Aggregates)

    suspend fun syncTelemetryToSupabase(telemetry: List<HealthTelemetryRecord>): Boolean {
        if (currentUserId == "local_user" || telemetry.isEmpty()) return false

        val hostName = healthConnectManager.getHostPhoneName()

        // IMPORTANT: Always group and aggregate FULL-DAY records per localDate;
        // never slice by lastPushedTelemetryEpochMs, which would overwrite full-day step totals with partial deltas!
        val recordsByDate = telemetry.groupBy { r ->
            r.localDate ?: isoDateFormatter.format(Date(r.startTime))
        }

        var anySyncSucceeded = false
        val affectedDates = LinkedHashMap<String, String>()

        for ((dateKey, dateRecords) in recordsByDate) {
            val dateEpochMs = try {
                isoDateFormatter.parse(dateKey)?.time ?: System.currentTimeMillis()
            } catch (e: Exception) {
                System.currentTimeMillis()
            }

            val isWithinIntradayRetention = (getStartOfDay(System.currentTimeMillis()) - getStartOfDay(dateEpochMs)) <= 7L * 86_400_000L

            // Upload Order: 1. Sleep -> 2. Intraday HR (<= 7d) -> 3. Daily Vitals (so Realtime vitals notification never sees stale HR!)
            val sleepOk = syncLeanSleepSessions(dateRecords, dateKey, dateEpochMs, hostName)
            val hrOk = if (isWithinIntradayRetention) syncLeanIntradayHeartRate(dateRecords, dateKey) else false
            val vitalsOk = syncLeanDailyVitals(dateRecords, dateKey, hostName)

            if (sleepOk || vitalsOk || hrOk) {
                anySyncSucceeded = true
                lastLocalUploadCompletedAtMs = System.currentTimeMillis()
                val maxTs = dateRecords.maxOfOrNull { it.endTime ?: it.startTime } ?: 0L
                val totalSteps = dateRecords.filter { it.isSteps }.sumOf { (it.value ?: 0.0).toInt() }
                val latestHr = dateRecords.filter { it.isLatestHeartRate || it.isHeartRate }
                    .maxByOrNull { it.endTime ?: it.startTime }?.value?.toInt() ?: 0
                affectedDates[dateKey] = "${dateRecords.size}_${totalSteps}_${latestHr}_$maxTs"
            }
        }

        // 4. Register canonical local health sources (respecting user custom priorities & session dedup)
        registerLocalHealthSources(telemetry, hostName)

        if (anySyncSucceeded || telemetry.isNotEmpty()) {
            val ids = telemetry.map { it.id }
            withContext(Dispatchers.IO) {
                for (chunk in ids.chunked(400)) {
                    telemetryDao.markRecordsSynced(chunk, System.currentTimeMillis())
                }
            }
        }
        if (anySyncSucceeded) {
            for ((dKey, fp) in affectedDates) {
                triggerCanonicalEngineIfNeeded(dateKey = dKey, fingerprint = fp)
            }
        }
        return anySyncSucceeded
    }

    private suspend fun syncLeanSleepSessions(
        records: List<HealthTelemetryRecord>,
        dateKey: String,
        dateEpochMs: Long,
        hostName: String
    ): Boolean {
        val sleepRecords = records.filter { it.isSleep || it.isSleepStage }
        if (sleepRecords.isEmpty()) return false

        val clusterResult = SleepClusteringEngine.clusterSleep(
            targetDate = Date(dateEpochMs),
            telemetry = sleepRecords,
            vitalsSummary = emptyMap(),
            preferredDevice = null
        )

        val sessions = buildLeanSleepSessionRecords(
            primarySession = clusterResult.primarySession,
            naps = clusterResult.naps,
            dateKey = dateKey,
            userId = currentUserId,
            hostName = hostName,
            allSessions = clusterResult.allSessions
        )
        if (sessions.isEmpty()) return false

        val fp = sessions.sortedBy { it.id }.joinToString("|") {
            "${it.id}:${it.durationSeconds}:${it.deepSeconds}:${it.remSeconds}:${it.lightSeconds}:${it.awakeSeconds}:${it.stages.size}:${it.isUserSelected}"
        }
        if (lastUploadedSleepFpByDate[dateKey] == fp) return false

        var success = true
        for (s in sessions) {
            val ok = remoteService.pushSleepSession(s)
            if (!ok) success = false
        }
        if (success) {
            lastUploadedSleepFpByDate[dateKey] = fp
            lastLocalUploadCompletedAtMs = System.currentTimeMillis()
        }
        return success
    }

    private suspend fun syncLeanDailyVitals(
        records: List<HealthTelemetryRecord>,
        dateKey: String,
        hostName: String
    ): Boolean {
        val vitalsList = buildLeanDailyVitalsRecords(
            records = records,
            dateKey = dateKey,
            userId = currentUserId,
            hostName = hostName
        )
        if (vitalsList.isEmpty()) return false

        val fp = vitalsList.sortedBy { it.id }.joinToString("|") {
            "${it.id}:${it.steps}:${it.activeKcal.toInt()}:${it.restingHeartRate ?: 0}:${it.latestHeartRate ?: 0}:${it.latestHrAt ?: ""}:${it.spo2 ?: 0.0}:${it.weightKg ?: 0.0}:${it.hrvSdnnNightly ?: 0.0}:${it.hrvRmssdNightly ?: 0.0}"
        }
        if (lastUploadedVitalsFpByDate[dateKey] == fp) return false

        var success = true
        for (v in vitalsList) {
            val ok = remoteService.pushDailyVitals(v)
            if (!ok) success = false
        }
        if (success) {
            lastUploadedVitalsFpByDate[dateKey] = fp
            lastLocalUploadCompletedAtMs = System.currentTimeMillis()
        }
        return success
    }

    private suspend fun syncLeanIntradayHeartRate(
        records: List<HealthTelemetryRecord>,
        dateKey: String
    ): Boolean {
        val buckets = groupIntradayHeartRateIntoBuckets(
            records = records,
            userId = currentUserId,
            dateKey = dateKey
        )
        if (buckets.isEmpty()) return false

        val maxMin = buckets.maxOf { it.bucketMinute }
        val totalSamples = buckets.sumOf { it.sampleCount }
        val lastBpm = buckets.maxByOrNull { it.bucketMinute }?.bpmAvg ?: 0
        val fp = "${buckets.size}:$maxMin:$totalSamples:$lastBpm"
        if (lastUploadedHrFpByDate[dateKey] == fp) return false

        val ok = remoteService.pushIntradayHeartRate(buckets)
        if (ok) {
            lastUploadedHrFpByDate[dateKey] = fp
            lastLocalUploadCompletedAtMs = System.currentTimeMillis()
        }
        return ok
    }

    private suspend fun registerLocalHealthSources(
        records: List<HealthTelemetryRecord>,
        hostName: String
    ) {
        val canonicalSources = records
            .mapNotNull { it.sourceDevice }
            .map { DeviceSource.from(it) }
            .filter { !it.isVirtualEngine && it !is DeviceSource.Manual }
            .distinctBy { it.displayName }

        if (canonicalSources.isEmpty()) return

        for (src in canonicalSources) {
            val name = src.displayName
            val sourceId = canonicalSourceId(src, name)
            if (registeredSourceIdsInSession.contains(sourceId)) {
                continue
            }

            // Never overwrite user-configured custom priority ranks, and skip if already registered identically!
            val existing = cachedLeanSources.firstOrNull {
                it.id == sourceId || DeviceSource.from(it.displayName) == src
            }
            if (existing?.isCustomPriority == true) {
                registeredSourceIdsInSession.add(sourceId)
                continue
            }
            if (existing != null && existing.id == sourceId && existing.hostDeviceName == hostName) {
                registeredSourceIdsInSession.add(sourceId)
                continue
            }

            val kind = when (src) {
                is DeviceSource.Oura -> "ring"
                is DeviceSource.AppleWatch, is DeviceSource.PixelWatch, is DeviceSource.Fitbit,
                is DeviceSource.OnePlus, is DeviceSource.Amazfit, is DeviceSource.Huawei,
                is DeviceSource.Garmin, is DeviceSource.Polar -> "watch"
                is DeviceSource.HealthKit, is DeviceSource.HealthConnect, is DeviceSource.SamsungHealth -> "phone"
                else -> "wearable"
            }
            val vendor = when (src) {
                is DeviceSource.Oura -> "Oura"
                is DeviceSource.PixelWatch, is DeviceSource.Fitbit, is DeviceSource.HealthConnect -> "Google"
                is DeviceSource.SamsungHealth -> "Samsung"
                is DeviceSource.OnePlus -> "OnePlus"
                is DeviceSource.AppleWatch, is DeviceSource.HealthKit -> "Apple"
                else -> "Wearable"
            }
            // Unified 1-based ascending default rank (1 = Oura, 2 = AW, 3 = PW5, 4 = OnePlus, 5 = Wearable, 10 = Phone)
            val dbPrio = src.sortPriority
            val color = DeviceColorPalette.getColorForSource(name)

            val record = HealthSourceRecord(
                id = sourceId,
                userId = currentUserId,
                platform = if (src is DeviceSource.AppleWatch || src is DeviceSource.HealthKit) "iOS" else "Android",
                deviceKind = kind,
                vendor = vendor,
                model = name,
                displayName = name,
                hostDeviceName = hostName,
                prioritySleep = dbPrio,
                priorityActivity = dbPrio,
                isCustomPriority = false,
                color = color
            )
            if (remoteService.registerHealthSource(record)) {
                registeredSourceIdsInSession.add(sourceId)
            }
        }
    }

    suspend fun syncVitalsToSupabase(vitals: List<VitalMetricRecord>): Boolean {
        return true
    }

    suspend fun syncUnsyncedTelemetry(): Boolean {
        if (currentUserId == "local_user") return false
        val unsynced = withContext(Dispatchers.IO) {
            telemetryDao.getUnsyncedRecords()
        }
        if (unsynced.isEmpty()) return true

        val affectedDates = unsynced.map { entity ->
            entity.localDate ?: isoDateFormatter.format(Date(entity.startTime))
        }.toSet()

        var allOk = true
        for (dateKey in affectedDates) {
            val parsedDate = runCatching { isoDateFormatter.parse(dateKey) }.getOrNull() ?: continue
            val fullDayRecords = if (healthConnectManager.isAvailable && healthConnectManager.hasAnyPermissions()) {
                healthConnectManager.fetchTelemetryForDate(parsedDate, currentUserId)
            } else {
                val dayStart = getStartOfDay(parsedDate.time)
                val winStart = dayStart - 6 * 3600 * 1000L
                val winEnd = dayStart + 24 * 3600 * 1000L
                withContext(Dispatchers.IO) {
                    telemetryDao.getTelemetryBetweenSync(currentUserId, winStart, winEnd).map { it.toRecord() }
                }
            }
            if (fullDayRecords.isNotEmpty()) {
                val ok = syncTelemetryToSupabase(fullDayRecords)
                if (!ok) allOk = false
            }
        }

        if (allOk) {
            val unsyncedIds = unsynced.map { it.id }
            withContext(Dispatchers.IO) {
                for (chunk in unsyncedIds.chunked(400)) {
                    telemetryDao.markRecordsSynced(chunk, System.currentTimeMillis())
                }
            }
        }
        return allOk
    }

    suspend fun syncMissingHistoricalDataIfNeeded() {
        if (isSyncingHistory) return
        if (currentUserId == "local_user") return
        isSyncingHistory = true
        try {
            val sharedPrefs = context.getSharedPreferences("daily_health_prefs", Context.MODE_PRIVATE)
            val lastSyncEpoch = sharedPrefs.getLong("last_historical_health_sync_epoch", 0L)
            val nowEpoch = System.currentTimeMillis()
            // Throttle check to at most once every 12 hours
            if (lastSyncEpoch > 0 && (nowEpoch - lastSyncEpoch) < 12 * 3600 * 1000L) {
                return
            }

            if (!healthConnectManager.isAvailable || !healthConnectManager.hasAnyPermissions()) {
                return
            }

            val cal = Calendar.getInstance()
            cal.time = Date()
            cal.add(Calendar.DAY_OF_YEAR, -14)
            val minDateStr = isoDateFormatter.format(cal.time)

            cal.time = Date()
            cal.add(Calendar.DAY_OF_YEAR, -1)
            val maxDateStr = isoDateFormatter.format(cal.time)

            val existingSummaries = try {
                remoteService.fetchDailySummariesBetween(currentUserId, minDateStr, maxDateStr)
            } catch (e: Exception) {
                android.util.Log.w("HealthDataRepository", "Could not query existing historical summaries: ${e.message}")
                emptyList()
            }

            val existingDatesWithData = existingSummaries.filter {
                (it.steps ?: 0) > 0 || (it.sleepAsleepS ?: 0) > 0 || (it.rhr ?: 0.0) > 0.0
            }.map { it.localDate }.toSet()

            val missingDates = mutableListOf<Date>()
            for (dayOffset in 1..14) {
                val c = Calendar.getInstance()
                c.add(Calendar.DAY_OF_YEAR, -dayOffset)
                val dKey = isoDateFormatter.format(c.time)
                if (!existingDatesWithData.contains(dKey)) {
                    missingDates.add(c.time)
                }
            }

            if (missingDates.isEmpty()) {
                sharedPrefs.edit().putLong("last_historical_health_sync_epoch", nowEpoch).apply()
                return
            }

            var hasUploadedAnyHistory = false
            for (missingDate in missingDates) {
                val pastTelemetry = healthConnectManager.fetchTelemetryForDate(missingDate, currentUserId)
                if (pastTelemetry.isNotEmpty()) {
                    val pushed = syncTelemetryToSupabase(pastTelemetry)
                    if (pushed) {
                        hasUploadedAnyHistory = true
                    }
                }
            }

            if (hasUploadedAnyHistory) {
                try {
                    remoteService.triggerCanonicalEngine(currentUserId, processDirty = true)
                } catch (e: Exception) {
                    android.util.Log.w("HealthDataRepository", "Failed to trigger batch dirty engine: ${e.message}")
                }
            }

            sharedPrefs.edit().putLong("last_historical_health_sync_epoch", nowEpoch).apply()
        } finally {
            isSyncingHistory = false
        }
    }

    suspend fun syncUnsyncedVitals(): Boolean {
        if (currentUserId == "local_user") return false
        val unsynced = withContext(Dispatchers.IO) {
            vitalsDao.getUnsyncedVitals()
        }
        if (unsynced.isEmpty()) return true
        val records = unsynced.map { it.toRecord() }
        val realVitals = records.filter { v ->
            if (v.userId == "stress-engine" || v.userId == "computed" || v.userId == "canonical" || v.userId == "habits") {
                return@filter false
            }
            val dev = v.sourceDevice
            if (dev != null && DeviceSource.from(dev).isVirtualEngine) {
                return@filter false
            }
            true
        }
        if (realVitals.isEmpty()) {
            val ids = records.map { it.id }
            withContext(Dispatchers.IO) {
                vitalsDao.markVitalsSynced(ids, System.currentTimeMillis())
            }
            return true
        }
        val success = remoteService.pushVitals(realVitals)
        if (success) {
            val ids = records.map { it.id }
            withContext(Dispatchers.IO) {
                vitalsDao.markVitalsSynced(ids, System.currentTimeMillis())
            }
        }
        return success
    }

    private fun getStartOfDay(timeMillis: Long): Long {
        val cal = Calendar.getInstance().apply {
            this.timeInMillis = timeMillis
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        return cal.timeInMillis
    }

    private fun isSameDay(time1: Long, time2: Long): Boolean {
        val c1 = Calendar.getInstance().apply { timeInMillis = time1 }
        val c2 = Calendar.getInstance().apply { timeInMillis = time2 }
        return c1.get(Calendar.YEAR) == c2.get(Calendar.YEAR) &&
                c1.get(Calendar.DAY_OF_YEAR) == c2.get(Calendar.DAY_OF_YEAR)
    }

    private fun Double.round(decimals: Int): Double {
        var multiplier = 1.0
        repeat(decimals) { multiplier *= 10 }
        return round(this * multiplier) / multiplier
    }

    companion object {
        const val CURRENT_SUMMARY_CACHE_VERSION = 2

        data class ArbitratedActivityResult(
            val totalSteps: Int,
            val activeCalories: Double,
            val hourlySteps: List<HourlyStepBucket>,
            val sourceDevice: String?
        )

        data class ArbitratedLatestHeartRate(
            val bpm: Double,
            val timestampMs: Long,
            val sourceDevice: String
        )

        data class ArbitratedSpotVital(
            val value: Double,
            val sourceDevice: String,
            val timestampMs: Long?
        )

        private fun canonicalSlug(name: String): String =
            name.lowercase(Locale.US)
                .replace(Regex("[^a-z0-9]+"), "_")
                .trim('_')

        fun canonicalSourceId(src: DeviceSource, displayName: String = src.displayName): String = when (src) {
            is DeviceSource.Oura -> "oura_ring"
            is DeviceSource.AppleWatch -> "apple_watch_ultra_2"
            is DeviceSource.PixelWatch, is DeviceSource.Fitbit -> "pixel_watch_5"
            is DeviceSource.OnePlus -> "oneplus_watch_3"
            is DeviceSource.HealthKit -> "schmitz_iphone"
            is DeviceSource.HealthConnect -> "trapper_pixel9"
            is DeviceSource.SamsungHealth -> "radar_fold8"
            else -> canonicalSlug(displayName)
        }

        fun resolveEffectivePriorityRank(deviceName: String?, sources: List<HealthSourceRecord>): Int {
            val src = DeviceSource.from(deviceName)
            val sid = canonicalSourceId(src, src.displayName)
            val matched = sources.firstOrNull {
                it.id == sid ||
                    DeviceSource.from(it.displayName) == src ||
                    (!deviceName.isNullOrEmpty() && it.displayName.equals(deviceName, ignoreCase = true))
            }
            if (matched != null) {
                val dbRank = minOf(matched.prioritySleep, matched.priorityActivity)
                if (dbRank in 1..30) {
                    return dbRank
                }
            }
            return src.sortPriority
        }

        fun parseIsoToEpochMs(raw: String?): Long? {
            if (raw.isNullOrBlank()) return null
            val trimmed = raw.trim()
            trimmed.toLongOrNull()?.let { return it }
            return try {
                java.time.Instant.parse(trimmed).toEpochMilli()
            } catch (_: Exception) {
                try {
                    java.time.OffsetDateTime.parse(trimmed).toInstant().toEpochMilli()
                } catch (_: Exception) {
                    try {
                        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", Locale.US).parse(trimmed)?.time
                    } catch (_: Exception) {
                        try {
                            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US).parse(trimmed)?.time
                        } catch (_: Exception) {
                            null
                        }
                    }
                }
            }
        }

        /**
         * Class B — Hourly Active-Wearer Envelope (`0..23`):
         * Sums disjoint active wearable hours (e.g. morning Oura/Pixel Watch + afternoon OnePlus Watch 3)
         * while preventing double-counting during simultaneous wear using `resolveEffectivePriorityRank` as tie-breaker.
         */
        fun arbitrateHourlyActivity(
            vitals: List<HealthDailyVitalsRecord>,
            sources: List<HealthSourceRecord>
        ): ArbitratedActivityResult {
            val validRows = vitals.filter { !DeviceSource.from(it.sourceDeviceKey).isVirtualEngine }
            if (validRows.isEmpty()) {
                return ArbitratedActivityResult(0, 0.0, emptyList(), null)
            }

            val wearables = validRows.filter { r ->
                DeviceSource.from(r.sourceDeviceKey).isWearable &&
                    (r.steps > 0 || r.hourlySteps?.any { it.steps > 0 } == true)
            }
            val candidates = wearables.ifEmpty {
                validRows.filter { r -> r.steps > 0 || r.hourlySteps?.any { it.steps > 0 } == true }
            }

            if (candidates.isEmpty()) {
                val fallback = validRows.minBy { resolveEffectivePriorityRank(it.sourceDeviceKey, sources) }
                val canon = DeviceSource.from(fallback.sourceDeviceKey).displayName
                return ArbitratedActivityResult(0, fallback.activeKcal, emptyList(), canon)
            }

            val anyHasHourly = candidates.any { r -> r.hourlySteps?.any { it.steps > 0 } == true }
            if (anyHasHourly) {
                val mergedBuckets = mutableListOf<HourlyStepBucket>()
                val contributedStepsByCanon = mutableMapOf<String, Int>()
                val latestActiveHourByCanon = mutableMapOf<String, Int>()

                data class HourEntry(val canon: String, val steps: Int, val rank: Int)
                for (h in 0..23) {
                    val entries = mutableListOf<HourEntry>()
                    for (row in candidates) {
                        val canon = DeviceSource.from(row.sourceDeviceKey).displayName
                        val hSteps = row.hourlySteps?.firstOrNull { it.hour == h }?.steps ?: 0
                        if (hSteps > 0) {
                            entries.add(HourEntry(canon, hSteps, resolveEffectivePriorityRank(canon, sources)))
                        }
                    }
                    val winner = entries.sortedWith(
                        compareBy<HourEntry> { it.rank }.thenByDescending { it.steps }
                    ).firstOrNull()
                    if (winner != null) {
                        mergedBuckets.add(HourlyStepBucket(id = h, hour = h, steps = winner.steps))
                        contributedStepsByCanon[winner.canon] = (contributedStepsByCanon[winner.canon] ?: 0) + winner.steps
                        latestActiveHourByCanon[winner.canon] = h
                    } else {
                        mergedBuckets.add(HourlyStepBucket(id = h, hour = h, steps = 0))
                    }
                }

                val envelopeSum = mergedBuckets.sumOf { it.steps }
                val maxSingleRow = candidates.maxBy { it.steps }
                val totalSteps = maxOf(envelopeSum, maxSingleRow.steps)

                var mergedKcal = 0.0
                for (row in candidates) {
                    val canon = DeviceSource.from(row.sourceDeviceKey).displayName
                    val contributed = contributedStepsByCanon[canon] ?: 0
                    if (contributed > 0 && row.activeKcal > 0.0) {
                        val ratio = minOf(1.0, contributed.toDouble() / maxOf(1, row.steps).toDouble())
                        mergedKcal += row.activeKcal * ratio
                    }
                }
                val maxSingleKcal = candidates.maxOfOrNull { it.activeKcal } ?: 0.0
                var finalKcal = round(maxOf(mergedKcal, maxSingleKcal) * 10.0) / 10.0
                if (finalKcal <= 0.0 && totalSteps > 0) {
                    finalKcal = round(totalSteps * 0.042 * 10.0) / 10.0
                }

                val winnerCanon = contributedStepsByCanon.entries.maxWithOrNull(
                    compareBy<Map.Entry<String, Int>> { it.value }
                        .thenBy { latestActiveHourByCanon[it.key] ?: -1 }
                )?.key ?: DeviceSource.from(maxSingleRow.sourceDeviceKey).displayName

                return ArbitratedActivityResult(
                    totalSteps = totalSteps,
                    activeCalories = finalKcal,
                    hourlySteps = mergedBuckets,
                    sourceDevice = winnerCanon
                )
            }

            val best = candidates.sortedWith(
                compareByDescending<HealthDailyVitalsRecord> { it.steps }
                    .thenBy { resolveEffectivePriorityRank(it.sourceDeviceKey, sources) }
            ).first()
            val canon = DeviceSource.from(best.sourceDeviceKey).displayName
            var kcal = best.activeKcal
            if (kcal <= 0.0) kcal = candidates.maxOfOrNull { it.activeKcal } ?: 0.0
            if (kcal <= 0.0 && best.steps > 0) kcal = round(best.steps * 0.042 * 10.0) / 10.0
            return ArbitratedActivityResult(
                totalSteps = best.steps,
                activeCalories = kcal,
                hourlySteps = best.hourlySteps ?: emptyList(),
                sourceDevice = canon
            )
        }

        /**
         * Class A — Recency-First Latest Heart Rate:
         * Always selects the newest real reading from the currently worn sensor.
         * Configured device priority ONLY breaks ties when >=2 sensors reported within `simultaneousWindowMs` (default 15m).
         */
        fun arbitrateLatestHeartRate(
            vitals: List<HealthDailyVitalsRecord>,
            intradayBuckets: List<HealthIntradayHeartRateRecord>,
            targetDateEpochMs: Long,
            sources: List<HealthSourceRecord>,
            deviceFilter: String? = null,
            simultaneousWindowMs: Long = 900_000L
        ): ArbitratedLatestHeartRate? {
            val cal = Calendar.getInstance().apply {
                timeInMillis = targetDateEpochMs
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val startOfDayMs = cal.timeInMillis
            val byDevice = LinkedHashMap<String, ArbitratedLatestHeartRate>()

            for (b in intradayBuckets) {
                if (b.bpmAvg !in 30..240) continue
                val src = DeviceSource.from(b.sourceDeviceKey)
                if (src.isVirtualEngine) continue
                val canon = src.displayName
                val bucketTs = startOfDayMs + b.bucketMinute * 60_000L
                val existing = byDevice[canon]
                if (existing == null || bucketTs >= existing.timestampMs) {
                    byDevice[canon] = ArbitratedLatestHeartRate(b.bpmAvg.toDouble(), bucketTs, canon)
                }
            }

            for (v in vitals) {
                val lhr = v.latestHeartRate ?: continue
                if (lhr !in 30..240) continue
                val src = DeviceSource.from(v.sourceDeviceKey)
                if (src.isVirtualEngine) continue
                val canon = src.displayName
                val spotTs = parseIsoToEpochMs(v.latestHrAt) ?: parseIsoToEpochMs(v.updatedAt) ?: startOfDayMs
                val existing = byDevice[canon]
                if (existing == null || spotTs >= existing.timestampMs) {
                    byDevice[canon] = ArbitratedLatestHeartRate(lhr.toDouble(), spotTs, canon)
                }
            }

            if (!deviceFilter.isNullOrEmpty()) {
                val targetCanon = DeviceSource.from(deviceFilter).displayName
                return byDevice[targetCanon]
            }

            val allCandidates = byDevice.values.toList()
            val newestTs = allCandidates.maxOfOrNull { it.timestampMs } ?: return null
            val activeWindow = allCandidates.filter { newestTs - it.timestampMs <= simultaneousWindowMs }

            return activeWindow.sortedWith(
                compareBy<ArbitratedLatestHeartRate> { resolveEffectivePriorityRank(it.sourceDevice, sources) }
                    .thenByDescending { it.timestampMs }
            ).firstOrNull()
        }

        /**
         * Class A — Recency-First Spot Vital (`spo2`, `weight`) with 30-minute tie-break window.
         */
        fun arbitrateSpotVital(
            vitals: List<HealthDailyVitalsRecord>,
            timestampKey: String,
            sources: List<HealthSourceRecord>,
            windowMs: Long = 1_800_000L,
            extract: (HealthDailyVitalsRecord) -> Double?
        ): ArbitratedSpotVital? {
            data class SpotCandidate(val value: Double, val sourceDevice: String, val tsMs: Long?, val rank: Int)
            val candidates = mutableListOf<SpotCandidate>()
            for (row in vitals) {
                val src = DeviceSource.from(row.sourceDeviceKey)
                if (src.isVirtualEngine) continue
                val v = extract(row) ?: continue
                if (v <= 0.0) continue
                val canon = src.displayName
                val ts = parseIsoToEpochMs(row.vitalsTimestamps?.get(timestampKey)) ?: parseIsoToEpochMs(row.updatedAt)
                val rank = resolveEffectivePriorityRank(canon, sources)
                candidates.add(SpotCandidate(v, canon, ts, rank))
            }
            if (candidates.isEmpty()) return null

            val newestTs = candidates.mapNotNull { it.tsMs }.maxOrNull()
            if (newestTs != null) {
                val active = candidates.filter { it.tsMs != null && newestTs - it.tsMs <= windowMs }
                val winner = active.sortedWith(
                    compareBy<SpotCandidate> { it.rank }.thenByDescending { it.tsMs ?: 0L }
                ).firstOrNull()
                if (winner != null) {
                    return ArbitratedSpotVital(winner.value, winner.sourceDevice, winner.tsMs)
                }
            }

            val fallback = candidates.minBy { it.rank }
            return ArbitratedSpotVital(fallback.value, fallback.sourceDevice, fallback.tsMs)
        }

        fun groupIntradayHeartRateIntoBuckets(
            records: List<HealthTelemetryRecord>,
            userId: String,
            dateKey: String
        ): List<HealthIntradayHeartRateRecord> {
            val hrRecords = records.filter { it.isHeartRate && (it.value ?: 0.0) > 0.0 }
            if (hrRecords.isEmpty()) return emptyList()

            data class BucketKey(val sourceKey: String, val bucketMinute: Int)
            class BucketAgg {
                var weightedSum: Double = 0.0
                var totalCount: Int = 0
                var minBpm: Double = Double.MAX_VALUE
                var maxBpm: Double = 0.0
            }
            val buckets = LinkedHashMap<BucketKey, BucketAgg>()

            val cal = Calendar.getInstance()
            for (r in hrRecords) {
                val bpm = r.value ?: continue
                if (bpm < 30.0 || bpm > 240.0) continue
                val rawKey = if (r.effectiveSourceKey.isNotEmpty()) r.effectiveSourceKey else (r.sourceDevice ?: "Unknown")
                val src = DeviceSource.from(rawKey)
                if (src.isVirtualEngine) continue
                val canonKey = src.displayName

                cal.timeInMillis = r.startTime
                val rowDateStr = String.format(
                    Locale.US,
                    "%04d-%02d-%02d",
                    cal.get(Calendar.YEAR),
                    cal.get(Calendar.MONTH) + 1,
                    cal.get(Calendar.DAY_OF_MONTH)
                )
                if (rowDateStr != dateKey) continue

                val minute = cal.get(Calendar.MINUTE)
                val hour = cal.get(Calendar.HOUR_OF_DAY)
                val bucketMinute = hour * 60 + (minute / 5) * 5

                val bKey = BucketKey(sourceKey = canonKey, bucketMinute = bucketMinute)
                val cnt = maxOf(1, r.sampleCount ?: 1)
                val rMin = (r.minValue ?: bpm).takeIf { it >= 30.0 } ?: bpm
                val rMax = (r.maxValue ?: bpm).takeIf { it <= 240.0 } ?: bpm
                val agg = buckets.getOrPut(bKey) { BucketAgg() }
                agg.weightedSum += bpm * cnt
                agg.totalCount += cnt
                agg.minBpm = minOf(agg.minBpm, rMin)
                agg.maxBpm = maxOf(agg.maxBpm, rMax)
            }

            return buckets.filter { it.value.totalCount > 0 }.map { (bKey, agg) ->
                val avg = agg.weightedSum / agg.totalCount
                val minBpm = if (agg.minBpm < Double.MAX_VALUE) agg.minBpm else avg
                val maxBpm = if (agg.maxBpm > 0.0) agg.maxBpm else avg
                val sourceSlug = canonicalSlug(bKey.sourceKey)
                val recordId = "hr_${userId}_${dateKey}_${sourceSlug}_${bKey.bucketMinute}"

                HealthIntradayHeartRateRecord(
                    id = recordId,
                    userId = userId,
                    localDate = dateKey,
                    sourceDeviceKey = bKey.sourceKey,
                    bucketMinute = bKey.bucketMinute,
                    bpmAvg = Math.round(avg).toInt(),
                    bpmMin = Math.round(minBpm).toInt(),
                    bpmMax = Math.round(maxBpm).toInt(),
                    sampleCount = agg.totalCount
                )
            }.sortedBy { it.bucketMinute }
        }

        fun buildLeanSleepSessionRecords(
            primarySession: SleepSession?,
            naps: List<NapSession> = emptyList(),
            dateKey: String,
            userId: String,
            hostName: String = "Trapper (Pixel 9 Pro)",
            allSessions: List<SleepSession> = emptyList()
        ): List<HealthSleepSessionRecord> {
            val results = mutableListOf<HealthSleepSessionRecord>()

            val candidates = if (allSessions.isNotEmpty()) {
                allSessions.filter { !it.isNap }
            } else {
                listOfNotNull(primarySession)
            }

            // Keep best nocturnal session per canonical physical wearable
            val byCanonical = candidates.groupBy { DeviceSource.from(it.sourceDevice).displayName }
            for ((canonName, deviceSessions) in byCanonical) {
                val src = DeviceSource.from(canonName)
                if (src.isVirtualEngine) continue
                val best = deviceSessions.sortedWith(
                    compareByDescending<SleepSession> { it.stages.isNotEmpty() }
                        .thenByDescending { it.asleepSeconds }
                ).firstOrNull() ?: continue
                if (best.asleepSeconds <= 0) continue

                val sourceSlug = canonicalSlug(canonName)
                val id = "sleep_${userId}_${dateKey}_primary_sleep_$sourceSlug"
                val durationS = best.asleepSeconds.toInt()
                val inBedS = maxOf(durationS, best.durationSeconds.toInt())

                results.add(
                    HealthSleepSessionRecord(
                        id = id,
                        userId = userId,
                        localDate = dateKey,
                        sessionType = "primary_sleep",
                        sourceDeviceKey = canonName,
                        hostDeviceName = hostName,
                        startTime = best.startTime,
                        endTime = best.endTime,
                        durationSeconds = durationS,
                        timeInBedSeconds = inBedS,
                        efficiencyPercent = best.efficiencyPercent.toDouble(),
                        sleepScore = best.sleepScore,
                        deepSeconds = best.deepSeconds.toInt(),
                        remSeconds = best.remSeconds.toInt(),
                        lightSeconds = best.lightSeconds.toInt(),
                        awakeSeconds = best.awakeSeconds.toInt(),
                        latencySeconds = 0,
                        qualityRating = best.sleepQualityRating,
                        stages = best.stages.map { st ->
                            st.copy(sourceDevice = canonName)
                        },
                        sourcePriority = src.sortPriority,
                        isUserSelected = false
                    )
                )
            }

            for (nap in naps) {
                val src = DeviceSource.from(nap.sourceDevice)
                if (src.isVirtualEngine) continue
                val canonName = src.displayName
                val sourceSlug = canonicalSlug(canonName)
                val id = "sleep_${userId}_${dateKey}_nap_${nap.id.take(8)}_$sourceSlug"
                val durationS = nap.durationSeconds.toInt()
                if (durationS <= 0) continue

                results.add(
                    HealthSleepSessionRecord(
                        id = id,
                        userId = userId,
                        localDate = dateKey,
                        sessionType = "nap",
                        sourceDeviceKey = canonName,
                        hostDeviceName = hostName,
                        startTime = nap.startTime,
                        endTime = nap.endTime,
                        durationSeconds = durationS,
                        timeInBedSeconds = durationS,
                        efficiencyPercent = 100.0,
                        sleepScore = null,
                        deepSeconds = 0,
                        remSeconds = 0,
                        lightSeconds = durationS,
                        awakeSeconds = 0,
                        latencySeconds = 0,
                        qualityRating = "Nap",
                        stages = emptyList(),
                        sourcePriority = src.sortPriority,
                        isUserSelected = false
                    )
                )
            }

            return results
        }

        fun buildLeanDailyVitalsRecords(
            records: List<HealthTelemetryRecord>,
            dateKey: String,
            userId: String,
            hostName: String = "Trapper (Pixel 9 Pro)"
        ): List<HealthDailyVitalsRecord> {
            val bySource = records.groupBy { r ->
                val raw = if (r.effectiveSourceKey.isNotEmpty()) r.effectiveSourceKey else (r.sourceDevice ?: hostName)
                DeviceSource.from(raw).displayName
            }

            val results = mutableListOf<HealthDailyVitalsRecord>()
            for ((canonName, sourceRecords) in bySource) {
                val src = DeviceSource.from(canonName)
                if (src.isVirtualEngine) continue

                val stepRecords = sourceRecords.filter { it.isSteps }.sortedBy { it.startTime }
                var totalSteps = 0
                val hourlyMap = mutableMapOf<Int, Int>()
                val cal = Calendar.getInstance()

                // Deduplicate near-identical step intervals from Health Connect sync bursts
                val uniqueStepSlices = mutableListOf<HealthTelemetryRecord>()
                for (r in stepRecords) {
                    if (uniqueStepSlices.isNotEmpty()) {
                        val last = uniqueStepSlices.last()
                        val sameStart = abs(last.startTime - r.startTime) < 5000L
                        val sameEnd = abs((last.endTime ?: last.startTime) - (r.endTime ?: r.startTime)) < 5000L
                        if (sameStart && sameEnd) continue
                    }
                    uniqueStepSlices.add(r)
                }

                for (r in uniqueStepSlices) {
                    val v = (r.value ?: 0.0).toInt()
                    if (v <= 0) continue
                    cal.timeInMillis = r.startTime
                    val hour = cal.get(Calendar.HOUR_OF_DAY)
                    hourlyMap[hour] = (hourlyMap[hour] ?: 0) + v
                    totalSteps += v
                }

                val hourlyBuckets = if (totalSteps > 0) {
                    (0..23).map { h ->
                        HourlyStepBucket(id = h, hour = h, steps = hourlyMap[h] ?: 0)
                    }
                } else null

                val tsMap = LinkedHashMap<String, String>()
                fun newestRecord(predicate: (HealthTelemetryRecord) -> Boolean): HealthTelemetryRecord? =
                    sourceRecords.filter { predicate(it) && it.value != null }
                        .maxByOrNull { it.endTime ?: it.startTime }

                fun extractLatest(key: String, predicate: (HealthTelemetryRecord) -> Boolean): Double? {
                    val rec = newestRecord(predicate) ?: return null
                    val v = rec.value ?: return null
                    tsMap[key] = java.time.Instant.ofEpochMilli(rec.endTime ?: rec.startTime).toString()
                    return v
                }

                val activeKcal = sourceRecords.filter { it.type == "active_energy" || it.type == "active_calories" }
                    .mapNotNull { it.value }.sum()
                val rhr = extractLatest("rhr") { it.type == "resting_heart_rate" }?.let { Math.round(it).toInt() }
                val spo2 = extractLatest("spo2") { it.type == "oxygen_saturation" }
                val resp = extractLatest("resp") { it.type == "respiratory_rate" }
                val temp = extractLatest("temp") { it.type == "wrist_temperature" || it.type == "body_temperature" }
                val weight = extractLatest("weight") { it.type == "weight" }
                val hrvSdnn = extractLatest("hrv_sdnn") { it.type == "hrv_sdnn" }
                val hrvRmssd = extractLatest("hrv_rmssd") { it.type == "hrv_rmssd" }

                val spotHrRec = newestRecord { it.isLatestHeartRate && (it.value ?: 0.0) in 30.0..240.0 }
                val bucketHrRec = newestRecord { it.isHeartRate && (it.value ?: 0.0) in 30.0..240.0 }
                val chosenHrRec: HealthTelemetryRecord? = when {
                    spotHrRec != null && bucketHrRec != null -> {
                        val sTs = spotHrRec.endTime ?: spotHrRec.startTime
                        val bTs = bucketHrRec.endTime ?: bucketHrRec.startTime
                        if (sTs >= bTs) spotHrRec else bucketHrRec
                    }
                    else -> spotHrRec ?: bucketHrRec
                }
                val latestHr = chosenHrRec?.value?.let { Math.round(it).toInt() }
                val latestHrAt = chosenHrRec?.let {
                    java.time.Instant.ofEpochMilli(it.endTime ?: it.startTime).toString()
                }
                if (latestHrAt != null) {
                    tsMap["latest_hr"] = latestHrAt
                }

                if (totalSteps <= 0 && activeKcal <= 0.0 && rhr == null && latestHr == null && spo2 == null &&
                    resp == null && temp == null && weight == null && hrvSdnn == null && hrvRmssd == null
                ) {
                    continue
                }

                val sourceSlug = canonicalSlug(canonName)
                val recordId = "vitals_${userId}_${dateKey}_$sourceSlug"

                results.add(
                    HealthDailyVitalsRecord(
                        id = recordId,
                        userId = userId,
                        localDate = dateKey,
                        sourceDeviceKey = canonName,
                        hostDeviceName = hostName,
                        steps = totalSteps,
                        activeKcal = activeKcal,
                        restingHeartRate = rhr,
                        spo2 = spo2,
                        respiratoryRate = resp,
                        skinTempCelsius = temp,
                        weightKg = weight,
                        hrvSdnnNightly = hrvSdnn,
                        hrvRmssdNightly = hrvRmssd,
                        hourlySteps = hourlyBuckets,
                        latestHeartRate = latestHr,
                        latestHrAt = latestHrAt,
                        vitalsTimestamps = tsMap.takeIf { it.isNotEmpty() },
                        updatedAt = java.time.Instant.now().toString()
                    )
                )
            }
            return results
        }

        data class ArchivedCardiovascularSnapshot(
            val points: List<IntradayHeartRatePoint>,
            val averageBpm: Double,
            val minBpm: Double,
            val maxBpm: Double,
            val zones: Map<HeartRateZone, Int>,
            val restingBpm: Double?,
            val latestBpm: Double?,
            val latestTimestampMs: Long?,
            val latestSourceDevice: String?
        )

        fun resolveArchivedCardiovascularFallback(
            cardio: CanonicalCardiovascularSummary?,
            filter: String?
        ): ArchivedCardiovascularSnapshot? {
            if (cardio == null || cardio.intradayHeartRate.isEmpty()) return null

            fun computeZones(pts: List<IntradayHeartRatePoint>): Map<HeartRateZone, Int> {
                val z = mutableMapOf(
                    HeartRateZone.RESTING to 0,
                    HeartRateZone.FAT_BURN to 0,
                    HeartRateZone.CARDIO to 0,
                    HeartRateZone.PEAK to 0
                )
                for (pt in pts) {
                    z[pt.zone] = (z[pt.zone] ?: 0) + 1
                }
                return z
            }

            if (!filter.isNullOrEmpty()) {
                val targetCanon = DeviceSource.from(filter).displayName
                val matching = cardio.intradayHeartRate
                    .filter { !it.sourceDevice.isNullOrEmpty() && DeviceSource.from(it.sourceDevice!!).displayName == targetCanon }
                    .sortedBy { it.timestamp }
                if (matching.isEmpty()) return null
                val avg = round(matching.sumOf { it.bpm } / matching.size.toDouble())
                val lo = matching.minOf { it.bpm }
                val hi = matching.maxOf { it.bpm }
                val latestPt = matching.last()
                return ArchivedCardiovascularSnapshot(
                    points = matching,
                    averageBpm = avg,
                    minBpm = lo,
                    maxBpm = hi,
                    zones = computeZones(matching),
                    restingBpm = null,
                    latestBpm = latestPt.bpm,
                    latestTimestampMs = latestPt.timestamp.takeIf { it > 0L },
                    latestSourceDevice = targetCanon
                )
            }

            val pts = cardio.intradayHeartRate.sortedBy { it.timestamp }
            val avg = cardio.averageHeartRateBpm?.takeIf { it > 0.0 }
                ?: round(pts.sumOf { it.bpm } / pts.size.toDouble())
            val lo = cardio.minHeartRateBpm?.takeIf { it > 0.0 }
                ?: pts.minOf { it.bpm }
            val hi = cardio.maxHeartRateBpm?.takeIf { it > 0.0 }
                ?: pts.maxOf { it.bpm }
            val zones = cardio.heartRateZones?.toMap() ?: computeZones(pts)
            val lastPt = pts.lastOrNull()
            return ArchivedCardiovascularSnapshot(
                points = pts,
                averageBpm = avg,
                minBpm = lo,
                maxBpm = hi,
                zones = zones,
                restingBpm = cardio.restingHeartRateBpm,
                latestBpm = cardio.latestBpm ?: lastPt?.bpm,
                latestTimestampMs = lastPt?.timestamp?.takeIf { it > 0L },
                latestSourceDevice = cardio.latestSourceDevice?.let { DeviceSource.from(it).displayName }
                    ?: lastPt?.sourceDevice?.let { DeviceSource.from(it).displayName }
            )
        }
    }
}
