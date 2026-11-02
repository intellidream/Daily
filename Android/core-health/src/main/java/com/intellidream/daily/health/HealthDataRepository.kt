package com.intellidream.daily.health

import android.content.Context
import com.intellidream.daily.database.DailyDatabase
import com.intellidream.daily.database.dao.HealthDailySummaryDao
import com.intellidream.daily.database.dao.HealthTelemetryDao
import com.intellidream.daily.database.dao.VitalMetricDao
import com.intellidream.daily.database.entity.HealthDailySummaryEntity
import com.intellidream.daily.database.entity.HealthTelemetryEntity
import com.intellidream.daily.database.entity.VitalMetricEntity
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
import io.github.jan.supabase.realtime.channel
import io.github.jan.supabase.realtime.postgresChangeFlow
import io.github.jan.supabase.realtime.PostgresAction
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
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

    var currentUserId: String = "local_user"
        set(value) {
            val changed = field != value
            field = value
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

    fun startActiveSyncLoop() {
        periodicActiveSyncJob?.cancel()
        periodicActiveSyncJob = scope.launch(Dispatchers.IO) {
            while (isActive) {
                kotlinx.coroutines.delay(5 * 60 * 1000L) // 5 minutes periodic cadence
                if (currentUserId != "local_user") {
                    val isToday = isSameDay(_selectedDate.value, System.currentTimeMillis())
                    if (isToday) {
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
        realtimeJob = scope.launch(Dispatchers.IO) {
            try {
                SupabaseClientManager.ensureSessionReady()
                val channel = SupabaseClientManager.client.channel("health_realtime_sub_${currentUserId}")
                val summaryFlow = channel.postgresChangeFlow<PostgresAction>(schema = "public") {
                    table = "health_daily_summary"
                }
                val vitalsFlow = channel.postgresChangeFlow<PostgresAction>(schema = "public") {
                    table = "health_daily_vitals"
                }
                val sleepFlow = channel.postgresChangeFlow<PostgresAction>(schema = "public") {
                    table = "health_sleep_sessions"
                }

                merge(summaryFlow, vitalsFlow, sleepFlow).collect {
                    val now = System.currentTimeMillis()
                    // Throttle realtime bursts to at most once every 3 seconds (1:1 parity with iOS)
                    if (now - lastRealtimeSummaryFetchMs < 3000L) {
                        return@collect
                    }
                    lastRealtimeSummaryFetchMs = now
                    android.util.Log.d("HealthDataRepository", "Realtime update received for health data: silently refreshing")
                    // Silently refresh remote canonical summary without re-querying Health Connect,
                    // uploading telemetry, toggling isLoading, or triggering health-engine!
                    fetchRemoteSummarySilentlyForSelectedDate()
                }
            } catch (e: Exception) {
                android.util.Log.w("HealthDataRepository", "Realtime subscription exception", e)
            }
        }
    }

    /**
     * Silently fetches the latest canonical summary and lean health records for the selected date from Supabase
     * without triggering local telemetry collection, uploading telemetry, toggling isLoading,
     * or re-invoking health-engine (1:1 parity with iOS fetchRemoteSummarySilentlyForSelectedDate).
     */
    fun fetchRemoteSummarySilentlyForSelectedDate() {
        if (currentUserId == "local_user") return
        scope.launch(Dispatchers.IO) {
            val targetEpochMs = _selectedDate.value
            val targetDate = Date(targetEpochMs)
            val dateKey = isoDateFormatter.format(targetDate)
            val isToday = isSameDay(targetEpochMs, System.currentTimeMillis())

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
                        try { remoteService.fetchIntradayHeartRate(currentUserId, dateKey) } catch (e: Exception) { emptyList() }
                    }
                    val sourcesDeferred = async {
                        try { remoteService.fetchHealthSources(currentUserId) } catch (e: Exception) { emptyList() }
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
        val now = System.currentTimeMillis()
        val isToday = isSameDay(_selectedDate.value, now)
        val staleThreshold = if (isToday) 5 * 60 * 1000L else 60 * 60 * 1000L
        if (now - lastRefreshTimestamp > staleThreshold) {
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

                val remoteHrDeferred = async(Dispatchers.IO) {
                    if (currentUserId != "local_user") {
                        remoteService.fetchIntradayHeartRate(currentUserId, dateKey)
                    } else {
                        emptyList()
                    }
                }

                val remoteSourcesDeferred = async(Dispatchers.IO) {
                    if (currentUserId != "local_user") {
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
        if (local.isEmpty()) return remote
        if (remote.isEmpty()) return local
        val map = LinkedHashMap<String, HealthDailyVitalsRecord>()
        for (r in remote) {
            val canon = DeviceSource.from(r.sourceDeviceKey).displayName
            val existing = map[canon]
            if (existing == null || r.steps >= existing.steps) {
                map[canon] = r.copy(sourceDeviceKey = canon)
            }
        }
        for (l in local) {
            val canon = DeviceSource.from(l.sourceDeviceKey).displayName
            val existing = map[canon]
            if (existing != null) {
                val mergedSteps = maxOf(existing.steps, l.steps)
                val mergedKcal = maxOf(existing.activeKcal, l.activeKcal)
                val mergedHourly = if (l.steps >= existing.steps && !l.hourlySteps.isNullOrEmpty()) {
                    l.hourlySteps
                } else {
                    existing.hourlySteps ?: l.hourlySteps
                }
                map[canon] = HealthDailyVitalsRecord(
                    id = existing.id,
                    userId = l.userId,
                    localDate = l.localDate,
                    sourceDeviceKey = canon,
                    hostDeviceName = l.hostDeviceName ?: existing.hostDeviceName,
                    steps = mergedSteps,
                    activeKcal = mergedKcal,
                    restingHeartRate = l.restingHeartRate ?: existing.restingHeartRate,
                    spo2 = l.spo2 ?: existing.spo2,
                    respiratoryRate = l.respiratoryRate ?: existing.respiratoryRate,
                    skinTempCelsius = l.skinTempCelsius ?: existing.skinTempCelsius,
                    weightKg = l.weightKg ?: existing.weightKg,
                    hrvSdnnNightly = l.hrvSdnnNightly ?: existing.hrvSdnnNightly,
                    hrvRmssdNightly = l.hrvRmssdNightly ?: existing.hrvRmssdNightly,
                    hourlySteps = mergedHourly
                )
            } else {
                map[canon] = l.copy(sourceDeviceKey = canon)
            }
        }
        return map.values.toList()
    }

    private fun mergeLeanIntradayHr(
        remote: List<HealthIntradayHeartRateRecord>,
        local: List<HealthIntradayHeartRateRecord>
    ): List<HealthIntradayHeartRateRecord> {
        if (local.isEmpty()) return remote
        if (remote.isEmpty()) return local
        val map = LinkedHashMap<String, HealthIntradayHeartRateRecord>()
        for (r in remote) {
            val canon = DeviceSource.from(r.sourceDeviceKey).displayName
            val key = "${canon}_${r.bucketMinute}"
            map[key] = r.copy(sourceDeviceKey = canon)
        }
        for (l in local) {
            val canon = DeviceSource.from(l.sourceDeviceKey).displayName
            val key = "${canon}_${l.bucketMinute}"
            val existing = map[key]
            if (existing == null || l.sampleCount >= existing.sampleCount) {
                map[key] = l.copy(sourceDeviceKey = canon)
            }
        }
        return map.values.sortedBy { it.bucketMinute }
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
            if (h.bpmAvg <= 0 || h.sourceDeviceKey.isEmpty()) continue
            val src = DeviceSource.from(h.sourceDeviceKey)
            if (!src.isVirtualEngine) srcSet.add(src)
        }
        if (srcSet.isEmpty()) {
            val summarySources = _canonicalSummary.value?.sources.orEmpty()
            for (raw in summarySources) {
                val src = DeviceSource.from(raw)
                if (!src.isVirtualEngine) srcSet.add(src)
            }
        }
        val sortedSources = srcSet.toList().sortedWith(
            compareByDescending<DeviceSource> { it.sortPriority }.thenBy { it.displayName }
        )
        _availableSources.value = sortedSources
        _availableDevices.value = sortedSources.map { it.displayName }

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
            .filter { it.sessionType == "primary_sleep" }
            .sortedWith(
                compareByDescending<HealthSleepSessionRecord> { it.isUserSelected }
                    .thenByDescending { it.stages.isNotEmpty() }
                    .thenByDescending { DeviceSource.from(it.sourceDeviceKey).sortPriority }
                    .thenByDescending { it.durationSeconds }
            )

        val mapped = candidateRows.map { it.toSleepSession() }
        val primary = sortedPrimaryCandidates.firstOrNull()?.toSleepSession()
            ?: mapped.firstOrNull { !it.isNap }

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
            _totalActiveCalories.value = exact.activeKcal
            _stepsSourceDevice.value = targetCanon

            val map = mutableMapOf<HealthMetricType, VitalMetricRecord>()
            val rhr = exact.restingHeartRate
            if (rhr != null && rhr > 0) {
                _restingBpm.value = rhr.toDouble()
                map[HealthMetricType.RESTING_HEART_RATE] = VitalMetricRecord(
                    userId = exact.userId,
                    type = HealthMetricType.RESTING_HEART_RATE.rawKey,
                    value = rhr.toDouble(),
                    unit = "bpm",
                    date = exact.localDate,
                    sourceDevice = targetCanon,
                    createdAt = nowMs
                )
            } else {
                _restingBpm.value = 0.0
            }

            exact.spo2?.takeIf { it > 0 }?.let {
                map[HealthMetricType.OXYGEN_SATURATION] = VitalMetricRecord(
                    userId = exact.userId,
                    type = HealthMetricType.OXYGEN_SATURATION.rawKey,
                    value = it,
                    unit = "%",
                    date = exact.localDate,
                    sourceDevice = targetCanon,
                    createdAt = nowMs
                )
            }
            exact.respiratoryRate?.takeIf { it > 0 }?.let {
                map[HealthMetricType.RESPIRATORY_RATE] = VitalMetricRecord(
                    userId = exact.userId,
                    type = HealthMetricType.RESPIRATORY_RATE.rawKey,
                    value = it,
                    unit = "br/min",
                    date = exact.localDate,
                    sourceDevice = targetCanon,
                    createdAt = nowMs
                )
            }
            exact.skinTempCelsius?.let {
                map[HealthMetricType.BODY_TEMPERATURE] = VitalMetricRecord(
                    userId = exact.userId,
                    type = HealthMetricType.BODY_TEMPERATURE.rawKey,
                    value = it,
                    unit = "°C",
                    date = exact.localDate,
                    sourceDevice = targetCanon,
                    createdAt = nowMs
                )
            }
            exact.weightKg?.takeIf { it > 0 }?.let {
                map[HealthMetricType.WEIGHT] = VitalMetricRecord(
                    userId = exact.userId,
                    type = HealthMetricType.WEIGHT.rawKey,
                    value = it,
                    unit = "kg",
                    date = exact.localDate,
                    sourceDevice = targetCanon,
                    createdAt = nowMs
                )
            }
            val hrv = exact.hrvSdnnNightly
            val rmssd = exact.hrvRmssdNightly
            if (hrv != null && hrv > 0) {
                map[HealthMetricType.HRV_SDNN] = VitalMetricRecord(
                    userId = exact.userId,
                    type = HealthMetricType.HRV_SDNN.rawKey,
                    value = hrv,
                    unit = "ms",
                    date = exact.localDate,
                    sourceDevice = targetCanon,
                    createdAt = nowMs
                )
            } else if (rmssd != null && rmssd > 0) {
                map[HealthMetricType.HRV_RMSSD] = VitalMetricRecord(
                    userId = exact.userId,
                    type = HealthMetricType.HRV_RMSSD.rawKey,
                    value = rmssd,
                    unit = "ms",
                    date = exact.localDate,
                    sourceDevice = targetCanon,
                    createdAt = nowMs
                )
            }
            _currentVitals.value = map
            return
        }

        // All Devices mode: highest-step wearable first, else highest-step device
        val wearableWithSteps = vitals.filter { DeviceSource.from(it.sourceDeviceKey).isWearable && it.steps > 0 }
        val stepLeader = wearableWithSteps.maxByOrNull { it.steps }
            ?: vitals.maxByOrNull { it.steps }
            ?: vitals.firstOrNull()

        if (stepLeader != null) {
            _hourlySteps.value = stepLeader.hourlySteps ?: emptyList()
            _totalStepsToday.value = stepLeader.steps
            _stepsSourceDevice.value = DeviceSource.from(stepLeader.sourceDeviceKey).displayName
            val bestKcal = vitals.maxOfOrNull { it.activeKcal } ?: stepLeader.activeKcal
            _totalActiveCalories.value = if (bestKcal > 0) bestKcal else (stepLeader.steps * 0.042).round(0)
        }

        // Merge clinical vitals across all devices sorted by canonical priority
        val map = _currentVitals.value.toMutableMap()
        val sortedByPriority = vitals.sortedByDescending { DeviceSource.from(it.sourceDeviceKey).sortPriority }

        sortedByPriority.firstOrNull { (it.restingHeartRate ?: 0) > 0 }?.let { r ->
            val v = (r.restingHeartRate ?: 0).toDouble()
            _restingBpm.value = v
            map[HealthMetricType.RESTING_HEART_RATE] = VitalMetricRecord(
                userId = r.userId,
                type = HealthMetricType.RESTING_HEART_RATE.rawKey,
                value = v,
                unit = "bpm",
                date = dateStr,
                sourceDevice = DeviceSource.from(r.sourceDeviceKey).displayName,
                createdAt = nowMs
            )
        }
        sortedByPriority.firstOrNull { (it.spo2 ?: 0.0) > 0.0 }?.let { r ->
            map[HealthMetricType.OXYGEN_SATURATION] = VitalMetricRecord(
                userId = r.userId,
                type = HealthMetricType.OXYGEN_SATURATION.rawKey,
                value = r.spo2 ?: 0.0,
                unit = "%",
                date = dateStr,
                sourceDevice = DeviceSource.from(r.sourceDeviceKey).displayName,
                createdAt = nowMs
            )
        }
        sortedByPriority.firstOrNull { (it.respiratoryRate ?: 0.0) > 0.0 }?.let { r ->
            map[HealthMetricType.RESPIRATORY_RATE] = VitalMetricRecord(
                userId = r.userId,
                type = HealthMetricType.RESPIRATORY_RATE.rawKey,
                value = r.respiratoryRate ?: 0.0,
                unit = "br/min",
                date = dateStr,
                sourceDevice = DeviceSource.from(r.sourceDeviceKey).displayName,
                createdAt = nowMs
            )
        }
        sortedByPriority.firstOrNull { it.skinTempCelsius != null }?.let { r ->
            map[HealthMetricType.BODY_TEMPERATURE] = VitalMetricRecord(
                userId = r.userId,
                type = HealthMetricType.BODY_TEMPERATURE.rawKey,
                value = r.skinTempCelsius ?: 0.0,
                unit = "°C",
                date = dateStr,
                sourceDevice = DeviceSource.from(r.sourceDeviceKey).displayName,
                createdAt = nowMs
            )
        }
        sortedByPriority.firstOrNull { (it.weightKg ?: 0.0) > 0.0 }?.let { r ->
            map[HealthMetricType.WEIGHT] = VitalMetricRecord(
                userId = r.userId,
                type = HealthMetricType.WEIGHT.rawKey,
                value = r.weightKg ?: 0.0,
                unit = "kg",
                date = dateStr,
                sourceDevice = DeviceSource.from(r.sourceDeviceKey).displayName,
                createdAt = nowMs
            )
        }
        val hrvRow = sortedByPriority.firstOrNull { (it.hrvSdnnNightly ?: 0.0) > 0.0 }
        val rmssdRow = sortedByPriority.firstOrNull { (it.hrvRmssdNightly ?: 0.0) > 0.0 }
        if (hrvRow != null) {
            map[HealthMetricType.HRV_SDNN] = VitalMetricRecord(
                userId = hrvRow.userId,
                type = HealthMetricType.HRV_SDNN.rawKey,
                value = hrvRow.hrvSdnnNightly ?: 0.0,
                unit = "ms",
                date = dateStr,
                sourceDevice = DeviceSource.from(hrvRow.sourceDeviceKey).displayName,
                createdAt = nowMs
            )
        } else if (rmssdRow != null) {
            map[HealthMetricType.HRV_RMSSD] = VitalMetricRecord(
                userId = rmssdRow.userId,
                type = HealthMetricType.HRV_RMSSD.rawKey,
                value = rmssdRow.hrvRmssdNightly ?: 0.0,
                unit = "ms",
                date = dateStr,
                sourceDevice = DeviceSource.from(rmssdRow.sourceDeviceKey).displayName,
                createdAt = nowMs
            )
        }
        _currentVitals.value = map
    }

    fun applyLeanIntradayHeartRate(buckets: List<HealthIntradayHeartRateRecord>, targetDateEpochMs: Long) {
        cachedLeanIntradayHeartRate = buckets
        val filter = _selectedDeviceFilter.value
        val filtered = if (!filter.isNullOrEmpty()) {
            val targetCanon = DeviceSource.from(filter).displayName
            buckets.filter { DeviceSource.from(it.sourceDeviceKey).displayName == targetCanon }
        } else {
            buckets
        }

        val points = filtered.map { it.toPoint(targetDateEpochMs) }.sortedBy { it.timestamp }
        _intradayHeartRate.value = points
        if (filtered.isNotEmpty()) {
            val totalSamples = filtered.sumOf { maxOf(1, it.sampleCount) }
            val weightedSum = filtered.sumOf { it.bpmAvg.toDouble() * maxOf(1, it.sampleCount) }
            _averageBpm.value = round(weightedSum / totalSamples)
            _minBpm.value = (filtered.minOfOrNull { it.bpmMin } ?: 0).toDouble()
            _maxBpm.value = (filtered.maxOfOrNull { it.bpmMax } ?: 0).toDouble()
            _latestBpm.value = points.lastOrNull()?.bpm

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
            _averageBpm.value = 0.0
            _minBpm.value = 0.0
            _maxBpm.value = 0.0
            _latestBpm.value = null
            _heartRateZones.value = emptyMap()
        }
    }

    fun applyLeanHealthSources(sources: List<HealthSourceRecord>) {
        // Store source metadata only; never inject global registry rows into date-scoped _availableSources!
        cachedLeanSources = sources
    }

    fun reapplyCurrentDeviceFilter() {
        val filter = _selectedDeviceFilter.value
        val dateKey = isoDateFormatter.format(Date(_selectedDate.value))
        if (filter.isNullOrEmpty()) {
            val canonical = _canonicalSummary.value
            if (canonical != null) {
                applyCanonicalSummary(canonical, dateKey)
            }
        } else {
            // Clear cross-device state before populating strictly for the selected canonical device
            _hourlySteps.value = emptyList()
            _totalStepsToday.value = 0
            _totalActiveCalories.value = 0.0
            _stepsSourceDevice.value = filter
            _restingBpm.value = 0.0
            _currentVitals.value = emptyMap()
        }

        if (cachedLeanDailyVitals.isNotEmpty()) {
            applyLeanDailyVitals(cachedLeanDailyVitals)
        }

        if (cachedLeanSleepSessions.isNotEmpty()) {
            applyLeanSleepSessions(cachedLeanSleepSessions)
        } else if (!filter.isNullOrEmpty()) {
            _primarySleepSession.value = null
            _allSleepSessions.value = emptyList()
            _daytimeNaps.value = emptyList()
            _sleepRecoveryVerdict.value = null
            _sleepActionableTips.value = emptyList()
            _sleepAIContext.value = null
        }

        if (cachedLeanIntradayHeartRate.isNotEmpty()) {
            applyLeanIntradayHeartRate(cachedLeanIntradayHeartRate, _selectedDate.value)
        } else if (!filter.isNullOrEmpty()) {
            _intradayHeartRate.value = emptyList()
            _averageBpm.value = 0.0
            _minBpm.value = 0.0
            _maxBpm.value = 0.0
            _latestBpm.value = null
            _heartRateZones.value = emptyMap()
        }

        recalculateStressForCurrentDevice()
    }

    private fun recalculateStressForCurrentDevice() {
        val canonical = _canonicalSummary.value
        val filter = _selectedDeviceFilter.value
        val dateKey = isoDateFormatter.format(Date(_selectedDate.value))

        val stress = canonical?.stress
        if (filter.isNullOrEmpty() && stress != null) {
            _stressAnalysis.value = stress.toDomainAnalysis()
            _currentStressScore.value = stress.currentScore
            _currentStressLevel.value = stress.toDomainLevel()
            _intradayStress.value = stress.intradayStress
            return
        }

        val vitalsMap = _currentVitals.value.toMutableMap()
        val hrvVal = vitalsMap[HealthMetricType.HRV_SDNN]?.value ?: vitalsMap[HealthMetricType.HRV_RMSSD]?.value
        val rhrVal = if (_restingBpm.value > 0) _restingBpm.value else vitalsMap[HealthMetricType.RESTING_HEART_RATE]?.value
        val hrPoints = _intradayHeartRate.value

        if (hrvVal != null || hrPoints.isNotEmpty() || (rhrVal != null && rhrVal > 0)) {
            val stressCalc = StressAnalysisEngine.calculateStress(
                targetDate = Date(_selectedDate.value),
                hrvMs = hrvVal,
                hrTelemetry = hrPoints,
                hourlySteps = _hourlySteps.value,
                restingBpm = rhrVal?.takeIf { it > 0 },
                priorSleepScore = _primarySleepSession.value?.sleepScore
            )
            if (stressCalc != null) {
                val (stressResult, intradayPoints) = stressCalc
                _currentStressScore.value = stressResult.currentScore
                _currentStressLevel.value = stressResult.currentLevel
                _stressAnalysis.value = stressResult
                _intradayStress.value = intradayPoints
                val attrSource = filter
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
        _daytimeNaps.value = payload.sleep?.naps ?: emptyList()
        _sleepRecoveryVerdict.value = payload.sleep?.guidance?.verdict?.toDomain()
        _sleepActionableTips.value = payload.sleep?.guidance?.tips?.map { it.toDomain() } ?: emptyList()
        _sleepAIContext.value = payload.sleep?.guidance?.aiContext?.toDomain()

        // Activity
        val isAllDevices = _selectedDeviceSource.value == null && _selectedDeviceFilter.value.isNullOrEmpty()
        if (isAllDevices && payload.allDevicesView?.containsKey("steps") == true) {
            _totalStepsToday.value = (payload.allDevicesView["steps"]?.value ?: 0.0).toInt()
            _stepsSourceDevice.value = payload.allDevicesView["steps"]?.sourceKey?.let { DeviceSource.from(it).displayName }
                ?: payload.activity?.sourceDevice?.let { DeviceSource.from(it).displayName }
        } else {
            _totalStepsToday.value = payload.activity?.totalSteps ?: 0
            _stepsSourceDevice.value = payload.activity?.sourceDevice?.let { DeviceSource.from(it).displayName }
        }

        if (isAllDevices && payload.allDevicesView?.containsKey("active_energy") == true) {
            _totalActiveCalories.value = payload.allDevicesView["active_energy"]?.value ?: 0.0
        } else {
            _totalActiveCalories.value = payload.activity?.activeCaloriesKcal ?: 0.0
        }
        _hourlySteps.value = payload.activity?.hourlySteps ?: emptyList()

        // Cardiovascular
        _intradayHeartRate.value = payload.cardiovascular?.intradayHeartRate ?: emptyList()
        _restingBpm.value = payload.cardiovascular?.restingHeartRateBpm ?: 0.0
        _averageBpm.value = payload.cardiovascular?.averageHeartRateBpm ?: 0.0
        _maxBpm.value = payload.cardiovascular?.maxHeartRateBpm ?: 0.0
        _minBpm.value = payload.cardiovascular?.minHeartRateBpm ?: 0.0
        _heartRateZones.value = payload.cardiovascular?.heartRateZones?.toMap() ?: emptyMap()
        _latestBpm.value = payload.cardiovascular?.intradayHeartRate?.lastOrNull()?.bpm

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
        if (isAllDevices && payload.allDevicesView != null) {
            for ((metricKey, item) in payload.allDevicesView) {
                val type = HealthMetricType.from(metricKey) ?: continue
                val valNum = item.value ?: continue
                vitalsMap[type] = VitalMetricRecord(
                    id = UUID.randomUUID().toString(),
                    userId = currentUserId,
                    type = metricKey,
                    value = valNum,
                    unit = item.unit,
                    date = dateKey,
                    sourceDevice = item.sourceKey?.let { src ->
                        val ds = DeviceSource.from(src)
                        if (ds.isVirtualEngine) null else ds.displayName
                    }
                )
            }
        }
        _currentVitals.value = vitalsMap

        // Only populate from payload.sources if lean caches are not yet loaded for this date
        if (cachedLeanSleepSessions.isEmpty() && cachedLeanDailyVitals.isEmpty() && cachedLeanIntradayHeartRate.isEmpty()) {
            val sourcesList = payload.sources
                .map { DeviceSource.from(it) }
                .filter { !it.isVirtualEngine }
                .distinctBy { it.displayName }
                .sortedWith(compareByDescending<DeviceSource> { it.sortPriority }.thenBy { it.displayName })
            _availableSources.value = sourcesList
            _availableDevices.value = sourcesList.map { it.displayName }
        }
    }

    private fun ensureLocalDeviceSourcesPopulated() {
        val canonicalList = _availableSources.value
            .filter { !it.isVirtualEngine }
            .distinctBy { it.displayName }
            .sortedWith(compareByDescending<DeviceSource> { it.sortPriority }.thenBy { it.displayName })
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
            compareByDescending<DeviceSource> { it.sortPriority }.thenBy { it.displayName }
        )
        _availableSources.value = sorted
        _availableDevices.value = sorted.map { it.displayName }
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

        // 4. Process Stress using StressAnalysisEngine
        val hrvVal = vitalsValues[HealthMetricType.HRV_SDNN] ?: vitalsValues[HealthMetricType.HRV_RMSSD]
        val stressCalculation = StressAnalysisEngine.calculateStress(
            targetDate = targetDate,
            hrvMs = hrvVal,
            hrTelemetry = sortedHrPoints,
            hourlySteps = stepsResult.hourlyBuckets,
            restingBpm = _restingBpm.value.takeIf { it > 0 },
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

        // 3. For authenticated users, fetch remote canonical summaries and lean tables from Supabase
        if (currentUserId != "local_user") {
            try {
                coroutineScope {
                    val remoteSummariesDeferred = async(Dispatchers.IO) {
                        if (isAllDevices) {
                            try {
                                remoteService.fetchDailySummariesBetween(currentUserId, minDateKey, selectedDateKey)
                            } catch (e: Exception) {
                                emptyList()
                            }
                        } else emptyList()
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

                    val remoteSummaries = remoteSummariesDeferred.await()
                    val remoteSleep = remoteSleepDeferred.await()
                    val remoteVitals = remoteVitalsDeferred.await()

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
                        val wearableSteps = rows.filter { DeviceSource.from(it.sourceDeviceKey).isWearable && it.steps > 0 }
                            .maxOfOrNull { it.steps }
                        val bestSteps = wearableSteps ?: rows.maxOfOrNull { it.steps } ?: 0
                        val bestKcal = rows.maxOfOrNull { it.activeKcal } ?: 0.0
                        if (bestSteps > 0) map[HealthMetricType.STEPS] = bestSteps.toDouble()
                        if (bestKcal > 0.0) map[HealthMetricType.ACTIVE_ENERGY] = bestKcal

                        val sortedByPrio = rows.sortedByDescending { DeviceSource.from(it.sourceDeviceKey).sortPriority }
                        sortedByPrio.mapNotNull { it.restingHeartRate }.firstOrNull { it > 0 }?.let {
                            map[HealthMetricType.HEART_RATE] = it.toDouble()
                        }
                        sortedByPrio.mapNotNull { it.spo2 }.firstOrNull { it > 0.0 }?.let {
                            map[HealthMetricType.OXYGEN_SATURATION] = it
                        }
                        sortedByPrio.mapNotNull { it.weightKg }.firstOrNull { it > 0.0 }?.let {
                            map[HealthMetricType.WEIGHT] = it
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
                                .thenByDescending { it.stages.isNotEmpty() }
                                .thenByDescending { DeviceSource.from(it.sourceDeviceKey).sortPriority }
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

                            // Also cache into Room if payload exists
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

        var chosen: DeviceResult? = null
        if (preferredSource != null) {
            chosen = deviceResults.firstOrNull { DeviceSource.from(it.device) == preferredSource }
        }
        if (chosen == null && !preferredDevice.isNullOrEmpty()) {
            chosen = deviceResults.firstOrNull { it.device.contains(preferredDevice, ignoreCase = true) }
        }
        if (chosen == null) {
            val wearables = deviceResults.filter { it.isWearable && it.total > 0 }
            chosen = wearables.maxByOrNull { it.total } ?: deviceResults.maxByOrNull { it.total }
        }

        var chosenTotal = chosen?.total ?: 0
        val chosenHourly = chosen?.hourly ?: emptyMap()
        var chosenDevice = chosen?.device

        val isAllDevices = preferredSource == null && preferredDevice.isNullOrEmpty()
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

    fun triggerCanonicalEngineIfNeeded(dateKey: String) {
        if (currentUserId == "local_user") return
        val now = System.currentTimeMillis()
        val last = lastEngineInvocation[dateKey] ?: 0L
        if (now - last < 180_000L) {
            // Throttled: invoked within last 3 minutes for this date
            return
        }
        lastEngineInvocation[dateKey] = now
        scope.launch(Dispatchers.IO) {
            try {
                remoteService.triggerCanonicalEngine(currentUserId, date = dateKey)
            } catch (e: Exception) {
                android.util.Log.w("HealthDataRepository", "Failed to trigger canonical engine for $dateKey: ${e.message}")
            }
        }
    }

    // MARK: - Lean Health Ingestion (v2 Canonical Full-Day Aggregates)

    suspend fun syncTelemetryToSupabase(telemetry: List<HealthTelemetryRecord>): Boolean {
        if (currentUserId == "local_user" || telemetry.isEmpty()) return false

        val hostName = healthConnectManager.getHostPhoneName()

        // IMPORTANT: Always group and aggregate FULL-DAY records per localDate;
        // never slice by lastPushedTelemetryEpochMs, which would overwrite full-day step totals with partial deltas!
        val recordsByDate = telemetry.groupBy { r ->
            r.localDate ?: isoDateFormatter.format(Date(r.startTime))
        }

        var anySyncSucceeded = false
        val affectedDates = mutableSetOf<String>()

        for ((dateKey, dateRecords) in recordsByDate) {
            val dateEpochMs = try {
                isoDateFormatter.parse(dateKey)?.time ?: System.currentTimeMillis()
            } catch (e: Exception) {
                System.currentTimeMillis()
            }

            // 1. Sync Clustered Sleep Sessions (all wearables) to `health_sleep_sessions`
            val sleepOk = syncLeanSleepSessions(dateRecords, dateKey, dateEpochMs, hostName)

            // 2. Sync Consolidated Daily Vitals to `health_daily_vitals`
            val vitalsOk = syncLeanDailyVitals(dateRecords, dateKey, hostName)

            // 3. Sync 5-minute Intraday Heart Rate Buckets to `health_intraday_heart_rate`
            val hrOk = syncLeanIntradayHeartRate(dateRecords, dateKey)

            if (sleepOk || vitalsOk || hrOk) {
                anySyncSucceeded = true
                affectedDates.add(dateKey)
            }
        }

        // 4. Register canonical local health sources
        registerLocalHealthSources(telemetry, hostName)

        if (anySyncSucceeded) {
            val ids = telemetry.map { it.id }
            withContext(Dispatchers.IO) {
                for (chunk in ids.chunked(400)) {
                    telemetryDao.markRecordsSynced(chunk, System.currentTimeMillis())
                }
            }
            for (dKey in affectedDates) {
                triggerCanonicalEngineIfNeeded(dKey)
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

        var success = true
        for (s in sessions) {
            val ok = remoteService.pushSleepSession(s)
            if (!ok) success = false
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

        var success = true
        for (v in vitalsList) {
            val ok = remoteService.pushDailyVitals(v)
            if (!ok) success = false
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
        return remoteService.pushIntradayHeartRate(buckets)
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
            val sourceId = when (src) {
                is DeviceSource.Oura -> "oura_ring"
                is DeviceSource.AppleWatch -> "apple_watch_ultra_2"
                is DeviceSource.PixelWatch, is DeviceSource.Fitbit -> "pixel_watch_5"
                is DeviceSource.OnePlus -> "oneplus_watch_3"
                is DeviceSource.HealthKit -> "schmitz_iphone"
                is DeviceSource.HealthConnect -> "trapper_pixel9"
                is DeviceSource.SamsungHealth -> "radar_fold8"
                else -> canonicalSlug(name)
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
            val dbPrio = when (src) {
                is DeviceSource.Oura -> 100
                is DeviceSource.AppleWatch, is DeviceSource.PixelWatch, is DeviceSource.Fitbit -> 90
                is DeviceSource.OnePlus -> 85
                is DeviceSource.Amazfit, is DeviceSource.Huawei, is DeviceSource.Garmin, is DeviceSource.Whoop -> 75
                else -> 40
            }
            val color = DeviceColorPalette.getColorForSource(name)

            val record = HealthSourceRecord(
                id = sourceId,
                userId = currentUserId,
                platform = "Android",
                deviceKind = kind,
                vendor = vendor,
                model = name,
                displayName = name,
                hostDeviceName = hostName,
                prioritySleep = dbPrio,
                priorityActivity = dbPrio,
                color = color
            )
            remoteService.registerHealthSource(record)
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

        private fun canonicalSlug(name: String): String =
            name.lowercase(Locale.US)
                .replace(Regex("[^a-z0-9]+"), "_")
                .trim('_')

        fun groupIntradayHeartRateIntoBuckets(
            records: List<HealthTelemetryRecord>,
            userId: String,
            dateKey: String
        ): List<HealthIntradayHeartRateRecord> {
            val hrRecords = records.filter { it.isHeartRate && (it.value ?: 0.0) > 0.0 }
            if (hrRecords.isEmpty()) return emptyList()

            data class BucketKey(val sourceKey: String, val bucketMinute: Int)
            val buckets = mutableMapOf<BucketKey, MutableList<Double>>()

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
                buckets.getOrPut(bKey) { mutableListOf() }.add(bpm)
            }

            return buckets.map { (bKey, bpms) ->
                val avg = bpms.sum() / bpms.size
                val minBpm = bpms.minOrNull() ?: avg
                val maxBpm = bpms.maxOrNull() ?: avg
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
                    sampleCount = bpms.size
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

                val activeKcal = sourceRecords.filter { it.type == "active_energy" || it.type == "active_calories" }
                    .mapNotNull { it.value }.sum()
                val rhr = sourceRecords.filter { it.type == "resting_heart_rate" }
                    .sortedBy { it.startTime }
                    .mapNotNull { it.value }.lastOrNull()?.let { Math.round(it).toInt() }
                val spo2 = sourceRecords.filter { it.type == "oxygen_saturation" }
                    .sortedBy { it.startTime }
                    .mapNotNull { it.value }.lastOrNull()
                val resp = sourceRecords.filter { it.type == "respiratory_rate" }
                    .sortedBy { it.startTime }
                    .mapNotNull { it.value }.lastOrNull()
                val temp = sourceRecords.filter { it.type == "wrist_temperature" || it.type == "body_temperature" }
                    .sortedBy { it.startTime }
                    .mapNotNull { it.value }.lastOrNull()
                val weight = sourceRecords.filter { it.type == "weight" }
                    .sortedBy { it.startTime }
                    .mapNotNull { it.value }.lastOrNull()
                val hrvSdnn = sourceRecords.filter { it.type == "hrv_sdnn" }
                    .sortedBy { it.startTime }
                    .mapNotNull { it.value }.lastOrNull()
                val hrvRmssd = sourceRecords.filter { it.type == "hrv_rmssd" }
                    .sortedBy { it.startTime }
                    .mapNotNull { it.value }.lastOrNull()

                if (totalSteps <= 0 && activeKcal <= 0.0 && rhr == null && spo2 == null &&
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
                        hourlySteps = hourlyBuckets
                    )
                )
            }
            return results
        }
    }
}
