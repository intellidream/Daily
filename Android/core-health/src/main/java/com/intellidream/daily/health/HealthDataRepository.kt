package com.intellidream.daily.health

import android.content.Context
import com.intellidream.daily.database.DailyDatabase
import com.intellidream.daily.database.dao.HealthTelemetryDao
import com.intellidream.daily.database.dao.VitalMetricDao
import com.intellidream.daily.database.entity.HealthTelemetryEntity
import com.intellidream.daily.database.entity.VitalMetricEntity
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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
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
    private val remoteService: HealthRemoteService = HealthRemoteService(),
    val healthConnectManager: HealthConnectManager = HealthConnectManager(context),
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
) {
    var currentUserId: String = "local_user"

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

    // In-memory cache
    private var cachedTelemetry: List<HealthTelemetryRecord> = emptyList()
    private var cachedVitals: List<VitalMetricRecord> = emptyList()

    private val isoDateFormatter = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())

    init {
        loadDataForSelectedDate(forceRefresh = true)
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

    // MARK: - Data Fetching & Processing

    fun loadDataForSelectedDate(forceRefresh: Boolean = false) {
        scope.launch {
            _isLoading.value = true
            try {
                val targetEpochMs = _selectedDate.value
                val targetDate = Date(targetEpochMs)
                val dateKey = isoDateFormatter.format(targetDate)

                // Window: D-1 18:00 to D 24:00
                val cal = Calendar.getInstance().apply {
                    timeInMillis = targetEpochMs
                    add(Calendar.HOUR_OF_DAY, -6)
                }
                val windowStart = cal.timeInMillis
                val windowEnd = targetEpochMs + (24 * 3600 * 1000L)

                val telemetry = mutableListOf<HealthTelemetryRecord>()
                val vitals = mutableListOf<VitalMetricRecord>()

                // 1. Check Room local database cache first
                val localEntities = withContext(Dispatchers.IO) {
                    telemetryDao.getTelemetryBetweenSync(currentUserId, windowStart, windowEnd)
                }
                val localVitalsEntities = withContext(Dispatchers.IO) {
                    vitalsDao.getVitalsForDateSync(currentUserId, dateKey)
                }

                telemetry.addAll(localEntities.map { it.toRecord() })
                vitals.addAll(localVitalsEntities.map { it.toRecord() })

                // Pure real-data telemetry and vitals (honest empty state when unpopulated)
                cachedTelemetry = deduplicateTelemetry(telemetry)
                cachedVitals = vitals

                updateDevicesAndSources()
                processDataForCurrentDate()
                loadHistoricalTrends(targetDate)

                // 2. Fetch on-device Health Connect (if available and permissions granted)
                if (healthConnectManager.isAvailable && healthConnectManager.hasAnyPermissions()) {
                    val hcTelemetry = healthConnectManager.fetchTelemetryForDate(targetDate)
                    if (hcTelemetry.isNotEmpty()) {
                        telemetry.addAll(hcTelemetry)
                        withContext(Dispatchers.IO) {
                            telemetryDao.insertRecords(hcTelemetry.map { HealthTelemetryEntity.fromRecord(it) })
                        }
                        cachedTelemetry = deduplicateTelemetry(telemetry)
                        updateDevicesAndSources()
                        processDataForCurrentDate()
                        loadHistoricalTrends(targetDate)
                    }
                }

                // 3. Fetch from Supabase Remote (guarded with timeout)
                val remoteTelemetry = kotlinx.coroutines.withTimeoutOrNull(1500L) {
                    remoteService.fetchTelemetryBetween(currentUserId, windowStart, windowEnd)
                } ?: emptyList()
                val remoteVitals = kotlinx.coroutines.withTimeoutOrNull(1500L) {
                    remoteService.fetchVitalsForDate(currentUserId, dateKey)
                } ?: emptyList()

                if (remoteTelemetry.isNotEmpty()) {
                    telemetry.addAll(remoteTelemetry)
                }
                if (remoteVitals.isNotEmpty()) {
                    vitals.addAll(remoteVitals)
                }

                if (telemetry.isNotEmpty() || vitals.isNotEmpty()) {
                    cachedTelemetry = deduplicateTelemetry(telemetry)
                    cachedVitals = vitals
                    updateDevicesAndSources()
                    processDataForCurrentDate()
                    loadHistoricalTrends(targetDate)
                }
            } catch (e: Exception) {
                android.util.Log.e("HealthDataRepository", "Error loading health data", e)
            } finally {
                _isLoading.value = false
            }
        }
    }

    private fun updateDevicesAndSources() {
        val devSet = mutableSetOf<String>()
        val srcSet = mutableSetOf<DeviceSource>()
        for (t in cachedTelemetry) {
            val d = t.sourceDevice
            if (!d.isNullOrEmpty()) {
                devSet.add(d)
                srcSet.add(DeviceSource.from(d))
            }
        }
        for (v in cachedVitals) {
            val d = v.sourceDevice
            if (!d.isNullOrEmpty()) {
                devSet.add(d)
                srcSet.add(DeviceSource.from(d))
            }
        }
        _availableDevices.value = devSet.toList().sorted()
        _availableSources.value = srcSet.toList().sortedBy { it.displayName }
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

        // Vitals map
        val vitalsMap = mutableMapOf<HealthMetricType, VitalMetricRecord>()
        val vitalsValues = mutableMapOf<HealthMetricType, Double>()
        for (v in vitals) {
            val type = v.metricType
            if (type != null) {
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
        val (stressResult, intradayPoints) = StressAnalysisEngine.calculateStress(
            targetDate = targetDate,
            hrvMs = hrvVal,
            hrTelemetry = sortedHrPoints,
            hourlySteps = stepsResult.hourlyBuckets,
            restingBpm = _restingBpm.value.takeIf { it > 0 },
            priorSleepScore = _primarySleepSession.value?.sleepScore
        )
        _currentStressScore.value = stressResult.currentScore
        _currentStressLevel.value = stressResult.currentLevel
        _stressAnalysis.value = stressResult
        _intradayStress.value = intradayPoints

        // Store computed stress in vitalsMap
        val stressRecord = VitalMetricRecord(
            userId = "computed",
            type = "stress",
            value = stressResult.currentScore.toDouble(),
            unit = "pts",
            date = dateKey,
            sourceDevice = "Stress Engine"
        )
        vitalsMap[HealthMetricType.STRESS] = stressRecord
        vitalsValues[HealthMetricType.STRESS] = stressResult.currentScore.toDouble()

        _currentVitals.value = vitalsMap
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

        for (m in metrics) {
            val points = mutableListOf<DailyMetricTrendPoint>()
            for (dayOffset in (0..6).reversed()) {
                cal.timeInMillis = selectedMidnight
                cal.add(Calendar.DAY_OF_YEAR, -dayOffset)
                val dayTime = cal.timeInMillis
                val isComplete = dayOffset > 0
                val target = defaultTarget(m)

                val valNum = if (dayOffset == 0) {
                    when (m) {
                        HealthMetricType.STEPS -> _totalStepsToday.value.toDouble()
                        HealthMetricType.SLEEP_DURATION -> (_primarySleepSession.value?.asleepSeconds ?: 0.0) / 60.0
                        HealthMetricType.HEART_RATE -> if (_averageBpm.value > 0) _averageBpm.value else _restingBpm.value
                        HealthMetricType.STRESS -> _currentStressScore.value.toDouble()
                        HealthMetricType.ACTIVE_ENERGY -> _totalActiveCalories.value
                        else -> _currentVitals.value[m]?.value ?: 0.0
                    }
                } else {
                    val historyDateKey = isoDateFormatter.format(Date(dayTime))
                    val historyVitals = withContext(Dispatchers.IO) {
                        vitalsDao.getVitalsForDateSync(currentUserId, historyDateKey)
                    }
                    val found = historyVitals.firstOrNull { it.type.equals(m.name, ignoreCase = true) }
                    found?.value ?: 0.0
                }

                points.add(
                    DailyMetricTrendPoint(
                        date = dayTime,
                        value = valNum,
                        target = target,
                        isCompleteDay = isComplete && valNum > 0
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
        HealthMetricType.STRESS -> 50.0
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
