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
import com.intellidream.daily.model.DeviceSource
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
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
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
                val cacheCutoff = System.currentTimeMillis() - 14 * 24 * 3600 * 1000L
                summaryDao.deleteOldCache(cacheCutoff)
                db.execSQL("VACUUM")
                android.util.Log.d("HealthDataRepository", "Database maintenance completed (48h retention + VACUUM)")
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
                val channel = SupabaseClientManager.client.channel("health_daily_summary_sub_${currentUserId}")
                channel.postgresChangeFlow<PostgresAction>(schema = "public") {
                    table = "health_daily_summary"
                }.collect {
                    val now = System.currentTimeMillis()
                    // Throttle realtime bursts to at most once every 3 seconds (1:1 parity with iOS)
                    if (now - lastRealtimeSummaryFetchMs < 3000L) {
                        return@collect
                    }
                    lastRealtimeSummaryFetchMs = now
                    android.util.Log.d("HealthDataRepository", "Realtime update received for health_daily_summary: silently refreshing")
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
     * Silently fetches the latest canonical summary for the selected date from Supabase
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
                val remoteSummary = remoteService.fetchDailySummary(currentUserId, dateKey)
                if (remoteSummary != null && !remoteSummary.isEmpty()) {
                    // Avoid redundant UI re-renders if payload is identical
                    if (_canonicalSummary.value != remoteSummary) {
                        val entity = HealthDailySummaryEntity(
                            id = "summary_${currentUserId}_$dateKey",
                            userId = currentUserId,
                            dateKey = dateKey,
                            summaryVersion = 1,
                            payloadJson = jsonSerializer.encodeToString(remoteSummary),
                            computedAt = System.currentTimeMillis(),
                            sourceDevicePrimary = remoteSummary.sources.firstOrNull()
                        )
                        summaryDao.upsertSummary(entity)
                        withContext(Dispatchers.Main) {
                            applyCanonicalSummary(remoteSummary, dateKey)
                        }
                    }
                    if (isToday && cachedTelemetry.isNotEmpty()) {
                        withContext(Dispatchers.Main) {
                            mergeLocalTelemetryWithSummary(cachedTelemetry, isToday = true)
                        }
                    }
                    ensureLocalDeviceSourcesPopulated()
                    loadHistoricalTrends(targetDate)
                }
            } catch (e: Exception) {
                android.util.Log.w("HealthDataRepository", "Could not silently fetch health_daily_summary: ${e.message}")
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
        loadDataForSelectedDate(forceRefresh = false)
    }

    fun setDeviceFilter(source: DeviceSource?) {
        if (_selectedDeviceSource.value == source) return
        _selectedDeviceSource.value = source
        _selectedDeviceFilter.value = source?.displayName
        scope.launch {
            processDataForCurrentDate()
        }
    }

    fun setDeviceFilter(device: String?) {
        if (_selectedDeviceFilter.value == device) return
        _selectedDeviceFilter.value = device
        _selectedDeviceSource.value = if (device != null) DeviceSource.from(device) else null
        scope.launch {
            processDataForCurrentDate()
        }
    }

    // MARK: - Smart Refresh
    private var lastRefreshTimestamp: Long = 0L

    fun refreshIfStale() {
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

            // 0. Check in-memory summary
            if (!forceRefresh && _canonicalSummary.value?.date == dateKey && _canonicalSummary.value?.isEmpty() == false) {
                if (!isToday) {
                    ensureLocalDeviceSourcesPopulated()
                    loadHistoricalTrends(targetDate)
                    return@launch
                }
            }

            // 1. Check Room local database cache for canonical summary (<10ms)
            var hasValidCachedSummary = false
            val cachedSummaryEntity = withContext(Dispatchers.IO) {
                summaryDao.getSummary(currentUserId, dateKey)
            }
            if (!forceRefresh && cachedSummaryEntity != null && cachedSummaryEntity.summaryVersion == 1) {
                try {
                    val payload = jsonSerializer.decodeFromString<DailyHealthSummaryPayload>(cachedSummaryEntity.payloadJson)
                    if (!payload.isEmpty()) {
                        hasValidCachedSummary = true
                        if (_canonicalSummary.value != payload) {
                            applyCanonicalSummary(payload, dateKey)
                        }
                        if (!isToday) {
                            ensureLocalDeviceSourcesPopulated()
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
                // 2. Concurrently fetch Supabase canonical summary and local Health Connect
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

                val localTelemetry = localTelemetryDeferred.await()
                val remoteSummary = remoteSummaryDeferred.await()

                if (localTelemetry.isNotEmpty()) {
                    withContext(Dispatchers.IO) {
                        telemetryDao.insertRecords(localTelemetry.map { HealthTelemetryEntity.fromRecord(it) })
                    }
                    if (currentUserId != "local_user") {
                        scope.launch(Dispatchers.IO) {
                            syncTelemetryToSupabase(localTelemetry)
                        }
                    }
                }

                // 3. If canonical summary was found, apply and merge local sensor data
                if (remoteSummary != null && !remoteSummary.isEmpty()) {
                    if (_canonicalSummary.value != remoteSummary) {
                        withContext(Dispatchers.IO) {
                            val entity = HealthDailySummaryEntity(
                                id = "summary_${currentUserId}_$dateKey",
                                userId = currentUserId,
                                dateKey = dateKey,
                                summaryVersion = 1,
                                payloadJson = jsonSerializer.encodeToString(remoteSummary),
                                computedAt = System.currentTimeMillis(),
                                sourceDevicePrimary = remoteSummary.sources.firstOrNull()
                            )
                            summaryDao.upsertSummary(entity)
                        }
                        applyCanonicalSummary(remoteSummary, dateKey)
                    }

                    if (localTelemetry.isNotEmpty()) {
                        mergeLocalTelemetryWithSummary(localTelemetry, isToday = isToday)
                    }
                    ensureLocalDeviceSourcesPopulated()
                    loadHistoricalTrends(targetDate)
                    return@launch
                } else if (remoteSummary != null && remoteSummary.isEmpty()) {
                    if (currentUserId != "local_user") {
                        triggerCanonicalEngineIfNeeded(dateKey)
                    }
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

    private fun applyCanonicalSummary(payload: DailyHealthSummaryPayload, dateKey: String) {
        _canonicalSummary.value = payload

        // Sleep
        _primarySleepSession.value = payload.sleep?.primarySession
        _daytimeNaps.value = payload.sleep?.naps ?: emptyList()
        _sleepRecoveryVerdict.value = payload.sleep?.guidance?.verdict?.toDomain()
        _sleepActionableTips.value = payload.sleep?.guidance?.tips?.map { it.toDomain() } ?: emptyList()
        _sleepAIContext.value = payload.sleep?.guidance?.aiContext?.toDomain()

        // Activity
        val isToday = isSameDay(_selectedDate.value, System.currentTimeMillis())
        val isAllDevices = _selectedDeviceSource.value == null && _selectedDeviceFilter.value.isNullOrEmpty()
        if (isAllDevices && payload.allDevicesView?.containsKey("steps") == true) {
            _totalStepsToday.value = (payload.allDevicesView["steps"]?.value ?: 0.0).toInt()
        } else if (isToday) {
            _totalStepsToday.value = maxOf(_totalStepsToday.value, payload.activity?.totalSteps ?: 0)
        } else {
            _totalStepsToday.value = payload.activity?.totalSteps ?: 0
        }

        if (isAllDevices && payload.allDevicesView?.containsKey("active_energy") == true) {
            _totalActiveCalories.value = payload.allDevicesView["active_energy"]?.value ?: 0.0
        } else if (isToday) {
            _totalActiveCalories.value = maxOf(_totalActiveCalories.value, payload.activity?.activeCaloriesKcal ?: 0.0)
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
                sourceDevice = item.sourceDevice
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
                    sourceDevice = item.sourceKey
                )
            }
        }
        _currentVitals.value = vitalsMap

        // Update available devices & sources
        val sourcesList = payload.sources.map { DeviceSource.from(it) }.distinctBy { it.displayName }
        _availableSources.value = sourcesList.sortedBy { it.displayName }
        _availableDevices.value = payload.sources.sorted()
        ensureLocalDeviceSourcesPopulated()
    }

    private fun ensureLocalDeviceSourcesPopulated() {
        val devSet = _availableDevices.value.toMutableSet()
        val srcSet = _availableSources.value.toMutableSet()

        if (healthConnectManager.isAvailable) {
            if (devSet.none { it.contains("Health Connect", ignoreCase = true) || it.contains("Google", ignoreCase = true) }) {
                devSet.add("Health Connect")
                srcSet.add(DeviceSource.HealthConnect)
            }
        }

        _availableDevices.value = devSet.toList().sorted()
        _availableSources.value = srcSet.toList().sortedBy { it.displayName }
    }

    private fun mergeLocalTelemetryWithSummary(telemetry: List<HealthTelemetryRecord>, isToday: Boolean) {
        if (telemetry.isEmpty()) return
        val targetEpochMs = _selectedDate.value
        val targetDate = Date(targetEpochMs)
        val dateKey = isoDateFormatter.format(targetDate)

        // 1. Devices & Sources
        val devSet = _availableDevices.value.toMutableSet()
        val srcSet = _availableSources.value.toMutableSet()
        for (t in telemetry) {
            val d = t.sourceDevice
            if (!d.isNullOrEmpty()) {
                val src = DeviceSource.from(d)
                if (!src.isVirtualEngine) {
                    devSet.add(d)
                    srcSet.add(src)
                }
            }
        }
        _availableDevices.value = devSet.toList().sorted()
        _availableSources.value = srcSet.toList().sortedBy { it.displayName }
        ensureLocalDeviceSourcesPopulated()

        // 2. Activity (Steps & Active Calories)
        val stepsResult = calculateDailySteps(
            targetDate = targetDate,
            telemetry = telemetry,
            vitalsSummary = emptyMap(),
            preferredDevice = _selectedDeviceFilter.value,
            preferredSource = _selectedDeviceSource.value
        )
        val isAllDevices = _selectedDeviceSource.value == null && _selectedDeviceFilter.value.isNullOrEmpty()
        if (isAllDevices) {
            if (stepsResult.totalSteps > _totalStepsToday.value) {
                _totalStepsToday.value = stepsResult.totalSteps
                _hourlySteps.value = stepsResult.hourlyBuckets
            } else if (_hourlySteps.value.isEmpty() && stepsResult.totalSteps > 0) {
                _hourlySteps.value = stepsResult.hourlyBuckets
            }
        } else {
            if (isToday || stepsResult.totalSteps > _totalStepsToday.value) {
                if (stepsResult.totalSteps > 0) {
                    _totalStepsToday.value = stepsResult.totalSteps
                    _hourlySteps.value = stepsResult.hourlyBuckets
                }
            }
        }

        val activeCals = telemetry.filter { it.type == "active_energy" || it.type == "active_calories" }
            .mapNotNull { it.value }.sum()
        if (isAllDevices) {
            if (activeCals > _totalActiveCalories.value) {
                _totalActiveCalories.value = activeCals
            } else if (_totalActiveCalories.value == 0.0 && stepsResult.activeCalories > 0.0) {
                _totalActiveCalories.value = stepsResult.activeCalories
            }
        } else {
            if ((isToday || activeCals > _totalActiveCalories.value) && activeCals > 0) {
                _totalActiveCalories.value = activeCals
            } else if (_totalActiveCalories.value == 0.0 && stepsResult.activeCalories > 0.0) {
                _totalActiveCalories.value = stepsResult.activeCalories
            }
        }

        // 3. Intraday Heart Rate
        val hrTelemetry = telemetry.filter { it.isHeartRate && isSameDay(it.startTime, targetEpochMs) }
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
        if (hrPoints.isNotEmpty()) {
            val sortedHrPoints = hrPoints.sortedBy { it.timestamp }
            if (_intradayHeartRate.value.isEmpty() || (isToday && sortedHrPoints.size >= _intradayHeartRate.value.size)) {
                _intradayHeartRate.value = sortedHrPoints
                _latestBpm.value = sortedHrPoints.lastOrNull()?.bpm
                val bpms = sortedHrPoints.map { it.bpm }
                _averageBpm.value = round(bpms.average())
                _minBpm.value = bpms.minOrNull() ?: 0.0
                _maxBpm.value = bpms.maxOrNull() ?: 0.0

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
            }
        }

        // 4. Vitals Map Enrichment
        val updatedVitals = _currentVitals.value.toMutableMap()
        for (t in telemetry.sortedBy { it.startTime }) {
            val valNum = t.value ?: continue
            if (valNum <= 0) continue
            val metricType = HealthMetricType.from(t.type) ?: continue
            if (metricType == HealthMetricType.STEPS || t.isSleep || t.isSleepStage) continue

            val existing = updatedVitals[metricType]
            if (existing == null || t.startTime >= (existing.createdAt ?: 0L)) {
                updatedVitals[metricType] = VitalMetricRecord(
                    id = t.id,
                    userId = t.userId,
                    type = metricType.name.lowercase(),
                    value = valNum,
                    unit = t.unit ?: metricType.defaultUnit,
                    date = dateKey,
                    sourceDevice = t.sourceDevice,
                    createdAt = t.startTime
                )
            }
        }
        _currentVitals.value = updatedVitals

        // 5. Resting Heart Rate from vitals if missing
        if (_restingBpm.value == 0.0) {
            val rhr = updatedVitals[HealthMetricType.RESTING_HEART_RATE]?.value
            if (rhr != null && rhr > 0) {
                _restingBpm.value = rhr
            }
        }

        // 6. Sleep fallback if summary sleep was nil
        if (_primarySleepSession.value == null) {
            val vitalsSummary = updatedVitals.mapValues { it.value.value }
            val sleepResult = SleepClusteringEngine.clusterSleep(
                targetDate = targetDate,
                telemetry = telemetry,
                vitalsSummary = vitalsSummary,
                preferredDevice = _selectedDeviceFilter.value
            )
            if (sleepResult.primarySession != null) {
                _primarySleepSession.value = sleepResult.primarySession
                _daytimeNaps.value = sleepResult.naps
            }
        }
    }

    private fun updateDevicesAndSources() {
        val devSet = mutableSetOf<String>()
        val srcSet = mutableSetOf<DeviceSource>()
        for (t in cachedTelemetry) {
            val d = t.sourceDevice
            if (!d.isNullOrEmpty()) {
                val src = DeviceSource.from(d)
                if (!src.isVirtualEngine) {
                    devSet.add(d)
                    srcSet.add(src)
                }
            }
        }
        for (v in cachedVitals) {
            val d = v.sourceDevice
            if (!d.isNullOrEmpty()) {
                val src = DeviceSource.from(d)
                if (!src.isVirtualEngine) {
                    devSet.add(d)
                    srcSet.add(src)
                }
            }
        }
        _availableDevices.value = devSet.toList().sorted()
        _availableSources.value = srcSet.toList().sortedBy { it.displayName }
        ensureLocalDeviceSourcesPopulated()
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

        // 1. Read cached canonical summaries from Room
        val cachedSummaries = withContext(Dispatchers.IO) {
            summaryDao.getSummariesInRange(currentUserId, minDateKey, selectedDateKey)
        }
        for (summaryEntity in cachedSummaries) {
            val dKey = summaryEntity.dateKey
            try {
                val payload = jsonSerializer.decodeFromString<DailyHealthSummaryPayload>(summaryEntity.payloadJson)
                payload.activity?.totalSteps?.takeIf { it > 0 }?.let {
                    historicalVitalsByDate.getOrPut(dKey) { mutableMapOf() }[HealthMetricType.STEPS] = it.toDouble()
                }
                val sleepSec = payload.sleep?.primarySession?.asleepSeconds?.takeIf { it > 0 }
                    ?: payload.sleep?.naps?.map { it.durationSeconds }?.sum()?.toDouble()?.takeIf { it > 0 }
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

        // 2. Query Room vitals for any missing historical metrics
        for (dayOffset in 0..6) {
            cal.timeInMillis = selectedMidnight
            cal.add(Calendar.DAY_OF_YEAR, -dayOffset)
            val dKey = isoDateFormatter.format(cal.time)
            val historyVitals = withContext(Dispatchers.IO) {
                vitalsDao.getVitalsForDateSync(currentUserId, dKey)
            }
            for (v in historyVitals) {
                val t = HealthMetricType.from(v.type)
                if (t != null && v.value > 0.0) {
                    val map = historicalVitalsByDate.getOrPut(dKey) { mutableMapOf() }
                    if (!map.containsKey(t)) {
                        map[t] = v.value
                    }
                }
            }
        }

        // 3. For authenticated users, fetch remote canonical summaries from Supabase
        if (currentUserId != "local_user") {
            try {
                val remoteSummaries = remoteService.fetchDailySummariesBetween(currentUserId, minDateKey, selectedDateKey)
                for (record in remoteSummaries) {
                    val dKey = record.localDate
                    val map = historicalVitalsByDate.getOrPut(dKey) { mutableMapOf() }
                    record.steps?.takeIf { it > 0 }?.let { map[HealthMetricType.STEPS] = it.toDouble() }
                    record.sleepAsleepS?.takeIf { it > 0 }?.let { map[HealthMetricType.SLEEP_DURATION] = it.toDouble() / 60.0 }
                    record.rhr?.takeIf { it > 0 }?.let { map[HealthMetricType.HEART_RATE] = it }
                    record.stressAvg?.takeIf { it > 0 }?.let { map[HealthMetricType.STRESS] = it.toDouble() }
                    record.hrvSdnn?.takeIf { it > 0 }?.let { map[HealthMetricType.HRV_SDNN] = it }
                    record.activeKcal?.takeIf { it > 0 }?.let { map[HealthMetricType.ACTIVE_ENERGY] = it }
                    record.weight?.takeIf { it > 0 }?.let { map[HealthMetricType.WEIGHT] = it }
                    record.spo2?.takeIf { it > 0 }?.let { map[HealthMetricType.OXYGEN_SATURATION] = it }

                    // Also cache into Room if payload exists
                    val payload = record.summary
                    if (payload != null) {
                        val payloadJson = jsonSerializer.encodeToString(payload)
                        withContext(Dispatchers.IO) {
                            summaryDao.upsertSummary(
                                HealthDailySummaryEntity(
                                    id = record.id.ifEmpty { "${currentUserId}_$dKey" },
                                    userId = currentUserId,
                                    dateKey = dKey,
                                    summaryVersion = 1,
                                    payloadJson = payloadJson,
                                    computedAt = System.currentTimeMillis()
                                )
                            )
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

        val grouped = daySteps.groupBy { it.sourceDevice ?: "Unknown" }
        data class DeviceResult(val device: String, val total: Int, val hourly: Map<Int, Int>, val isWearable: Boolean)
        val deviceResults = mutableListOf<DeviceResult>()

        for ((device, records) in grouped) {
            val lower = device.lowercase()
            val source = DeviceSource.from(device)
            val isWearable = (source is DeviceSource.AppleWatch || source is DeviceSource.Amazfit ||
                    source is DeviceSource.OnePlus || source is DeviceSource.Huawei ||
                    source is DeviceSource.HealthKit || source is DeviceSource.HealthConnect) ||
                    lower.contains("watch") || lower.contains("balance") || lower.contains("gt5")

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

    private var lastPushedTelemetryEpochMs: Long = 0L

    suspend fun syncTelemetryToSupabase(telemetry: List<HealthTelemetryRecord>): Boolean {
        if (currentUserId == "local_user" || telemetry.isEmpty()) return false
        val deltaTelemetry = if (lastPushedTelemetryEpochMs > 0) {
            telemetry.filter { it.startTime >= lastPushedTelemetryEpochMs || (it.endTime ?: it.startTime) >= lastPushedTelemetryEpochMs }
        } else {
            telemetry
        }
        if (deltaTelemetry.isEmpty()) return true

        val success = remoteService.pushTelemetry(deltaTelemetry)
        if (success) {
            val maxEpoch = deltaTelemetry.maxOfOrNull { it.startTime } ?: 0L
            if (maxEpoch > lastPushedTelemetryEpochMs) {
                lastPushedTelemetryEpochMs = maxEpoch
            }
            val ids = deltaTelemetry.map { it.id }
            withContext(Dispatchers.IO) {
                telemetryDao.markRecordsSynced(ids, System.currentTimeMillis())
            }
            val affectedDates = deltaTelemetry.map { isoDateFormatter.format(Date(it.startTime)) }.toSet()
            for (dKey in affectedDates) {
                triggerCanonicalEngineIfNeeded(dKey)
            }
        }
        return success
    }

    suspend fun syncVitalsToSupabase(vitals: List<VitalMetricRecord>): Boolean {
        if (currentUserId == "local_user" || vitals.isEmpty()) return false
        val realVitals = vitals.filter { v ->
            if (v.userId == "stress-engine" || v.userId == "computed" || v.userId == "canonical" || v.userId == "habits") {
                return@filter false
            }
            val dev = v.sourceDevice
            if (dev != null && DeviceSource.from(dev).isVirtualEngine) {
                return@filter false
            }
            true
        }
        if (realVitals.isEmpty()) return true
        val success = remoteService.pushVitals(realVitals)
        if (success) {
            val ids = vitals.map { it.id }
            withContext(Dispatchers.IO) {
                vitalsDao.markVitalsSynced(ids, System.currentTimeMillis())
            }
        }
        return success
    }

    suspend fun syncUnsyncedTelemetry(): Boolean {
        if (currentUserId == "local_user") return false
        val unsynced = withContext(Dispatchers.IO) {
            telemetryDao.getUnsyncedRecords()
        }
        if (unsynced.isEmpty()) return true
        val records = unsynced.map { it.toRecord() }
        val success = remoteService.pushTelemetry(records)
        if (success) {
            val ids = records.map { it.id }
            withContext(Dispatchers.IO) {
                telemetryDao.markRecordsSynced(ids, System.currentTimeMillis())
            }
            val affectedDates = records.map { isoDateFormatter.format(Date(it.startTime)) }.toSet()
            for (dKey in affectedDates) {
                triggerCanonicalEngineIfNeeded(dKey)
            }
        }
        return success
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

            // 1. Query existing summaries from Supabase
            val existingSummaries = try {
                remoteService.fetchDailySummariesBetween(currentUserId, minDateStr, maxDateStr)
            } catch (e: Exception) {
                android.util.Log.w("HealthDataRepository", "Could not query existing historical summaries: ${e.message}")
                emptyList()
            }

            val existingDatesWithData = existingSummaries.filter {
                (it.steps ?: 0) > 0 || (it.sleepAsleepS ?: 0) > 0 || (it.rhr ?: 0.0) > 0.0
            }.map { it.localDate }.toSet()

            // 2. Identify missing dates
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

            // 3. For missing dates only, fetch local Health Connect data and upload
            var hasUploadedAnyHistory = false
            for (missingDate in missingDates) {
                val pastTelemetry = healthConnectManager.fetchTelemetryForDate(missingDate, currentUserId)
                if (pastTelemetry.isNotEmpty()) {
                    val pushed = remoteService.pushTelemetry(pastTelemetry)
                    if (pushed) {
                        withContext(Dispatchers.IO) {
                            telemetryDao.insertRecords(pastTelemetry.map { HealthTelemetryEntity.fromRecord(it) })
                            telemetryDao.markRecordsSynced(pastTelemetry.map { it.id }, nowEpoch)
                        }

                        // Calculate and sync daily vitals for this day
                        val pastDateKey = isoDateFormatter.format(missingDate)
                        val vitalsList = mutableListOf<VitalMetricRecord>()
                        for (t in pastTelemetry) {
                            val valNum = t.value ?: continue
                            if (valNum <= 0) continue
                            val metricType = HealthMetricType.from(t.type) ?: continue
                            if (metricType == HealthMetricType.STEPS || t.isSleep || t.isSleepStage) continue

                            vitalsList.add(
                                VitalMetricRecord(
                                    userId = currentUserId,
                                    type = metricType.name.lowercase(),
                                    value = valNum,
                                    unit = t.unit ?: metricType.defaultUnit,
                                    date = pastDateKey,
                                    sourceDevice = t.sourceDevice,
                                    createdAt = t.startTime
                                )
                            )
                        }
                        if (vitalsList.isNotEmpty()) {
                            val vitalsPushed = remoteService.pushVitals(vitalsList)
                            if (vitalsPushed) {
                                withContext(Dispatchers.IO) {
                                    vitalsDao.insertVitals(vitalsList.map { VitalMetricEntity.fromRecord(it) })
                                    vitalsDao.markVitalsSynced(vitalsList.map { it.id }, nowEpoch)
                                }
                            }
                        }
                        hasUploadedAnyHistory = true
                    }
                }
            }

            // 4. If new historical telemetry was uploaded, trigger a single batch dirty computation in health-engine
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
}
