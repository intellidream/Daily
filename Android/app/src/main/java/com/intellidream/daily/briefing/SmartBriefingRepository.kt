package com.intellidream.daily.briefing

import android.content.Context
import android.content.SharedPreferences
import android.speech.tts.TextToSpeech
import com.intellidream.daily.database.FinanceDataRepository
import com.intellidream.daily.database.HabitsRepository
import com.intellidream.daily.database.NewsRepository
import com.intellidream.daily.database.SmartLedgerRepository
import com.intellidream.daily.database.TagdosRepository
import com.intellidream.daily.health.HealthDataRepository
import com.intellidream.daily.model.AppSettings
import com.intellidream.daily.model.BriefingCardItem
import com.intellidream.daily.model.BriefingTimeSlot
import com.intellidream.daily.model.TagDoPillType
import com.intellidream.daily.model.SmartBriefingMetrics
import com.intellidream.daily.model.SmartBriefingNarrative
import com.intellidream.daily.model.SmartBriefingRecord
import com.intellidream.daily.model.WeatherResponse
import com.intellidream.daily.network.GeminiApiService
import com.intellidream.daily.network.SupabaseClientManager
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.security.MessageDigest
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.UUID
import kotlin.math.roundToInt

/**
 * Android repository managing Smart Periodic Briefings across 4 daily diurnal slots.
 * Features 0ms caching, local deterministic rule synthesis (Tier 1),
 * Gemini Flash AI enhancement (Tier 2), and Supabase cloud sync.
 * Forensic match with iOS DailyCore SmartBriefingService.
 */
class SmartBriefingRepository(
    private val context: Context,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
) {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private val prefs: SharedPreferences = context.getSharedPreferences("daily_smart_briefing_prefs", Context.MODE_PRIVATE)

    private val cacheStorageKey = "daily_smart_summary_cache_v4"
    private val lastAutoShownDateKey = "daily_briefing_last_auto_shown_date_v2"
    private val lastReadDataHashKey = "daily_briefing_last_read_hash_v2"

    private val _activeBriefing = MutableStateFlow<SmartBriefingRecord?>(null)
    val activeBriefing: StateFlow<SmartBriefingRecord?> = _activeBriefing.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _isAiGenerated = MutableStateFlow(false)
    val isAiGenerated: StateFlow<Boolean> = _isAiGenerated.asStateFlow()

    private val _hasUnreadBrief = MutableStateFlow(false)
    val hasUnreadBrief: StateFlow<Boolean> = _hasUnreadBrief.asStateFlow()

    private val _shouldPresentMorningAutomatically = MutableStateFlow(false)
    val shouldPresentMorningAutomatically: StateFlow<Boolean> = _shouldPresentMorningAutomatically.asStateFlow()

    private var inMemoryCache = mutableMapOf<BriefingTimeSlot, SmartBriefingRecord>()

    // TextToSpeech Audio Engine
    private var tts: TextToSpeech? = null
    private var isTtsReady = false
    private val _isSpeaking = MutableStateFlow(false)
    val isSpeaking: StateFlow<Boolean> = _isSpeaking.asStateFlow()

    init {
        initTts()
        loadCachedBriefing()
    }

    private fun initTts() {
        tts = TextToSpeech(context.applicationContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.language = Locale.US
                isTtsReady = true
            }
        }
    }

    fun toggleSpeechReadout(text: String) {
        val engine = tts ?: return
        if (_isSpeaking.value) {
            engine.stop()
            _isSpeaking.value = false
        } else {
            if (isTtsReady) {
                engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "smart_briefing_utterance")
                _isSpeaking.value = true
            }
        }
    }

    fun stopSpeech() {
        tts?.stop()
        _isSpeaking.value = false
    }

    fun markBriefingAsRead() {
        val current = _activeBriefing.value
        if (current != null) {
            prefs.edit().putString(lastReadDataHashKey, current.dataHash).apply()
        }
        _hasUnreadBrief.value = false
    }

    private fun loadCachedBriefing() {
        val rawJson = prefs.getString(cacheStorageKey, null) ?: return
        try {
            val record = json.decodeFromString<SmartBriefingRecord>(rawJson)
            val currentSlot = BriefingTimeSlot.current()
            if (record.slot == currentSlot && isToday(record.createdAt)) {
                inMemoryCache[record.slot] = record
                _activeBriefing.value = record
                _isAiGenerated.value = record.isAiGenerated
                val lastRead = prefs.getString(lastReadDataHashKey, null)
                _hasUnreadBrief.value = (lastRead != record.dataHash)
            }
        } catch (_: Exception) {}
    }

    private fun saveCachedBriefing(record: SmartBriefingRecord) {
        inMemoryCache[record.slot] = record
        _activeBriefing.value = record
        _isAiGenerated.value = record.isAiGenerated
        val lastRead = prefs.getString(lastReadDataHashKey, null)
        _hasUnreadBrief.value = (lastRead != record.dataHash)

        try {
            val rawJson = json.encodeToString(record)
            prefs.edit().putString(cacheStorageKey, rawJson).apply()
        } catch (_: Exception) {}
    }

    private fun isToday(timestampMs: Long): Boolean {
        val cal1 = Calendar.getInstance().apply { timeInMillis = timestampMs }
        val cal2 = Calendar.getInstance()
        return cal1.get(Calendar.YEAR) == cal2.get(Calendar.YEAR) &&
               cal1.get(Calendar.DAY_OF_YEAR) == cal2.get(Calendar.DAY_OF_YEAR)
    }

    suspend fun getOrGenerateBriefing(
        forceRefresh: Boolean = false,
        userName: String,
        userId: String,
        settings: AppSettings,
        weather: WeatherResponse?,
        locationName: String,
        healthRepository: HealthDataRepository,
        habitsRepository: HabitsRepository,
        smartLedgerRepository: SmartLedgerRepository,
        tagdosRepository: TagdosRepository,
        newsRepository: NewsRepository
    ): SmartBriefingRecord = withContext(Dispatchers.IO) {
        val currentSlot = BriefingTimeSlot.current()
        val metrics = collectCurrentMetrics(
            weather = weather,
            locationName = locationName,
            healthRepository = healthRepository,
            habitsRepository = habitsRepository,
            smartLedgerRepository = smartLedgerRepository,
            tagdosRepository = tagdosRepository,
            newsRepository = newsRepository
        )
        val activeStreams = tagdosRepository.streams.value.map { it.displayTitle }
        val hash = computeDataHash(currentSlot, metrics, activeStreams.size)

        // 1. Check local cache (0ms return) if not force refreshing
        if (!forceRefresh) {
            val cached = inMemoryCache[currentSlot]
            if (cached != null && cached.dataHash == hash && cached.slot == currentSlot && isToday(cached.createdAt)) {
                _activeBriefing.value = cached
                return@withContext cached
            }
        }

        _isLoading.value = true
        try {
            val topPills = extractTopPills(tagdosRepository)

            // Tier 1: Instant Local Deterministic Synthesis (<5ms)
            val localNarrative = synthesizeLocalNarrative(
                slot = currentSlot,
                userName = userName,
                metrics = metrics,
                activeStreams = activeStreams,
                topPills = topPills
            )

            var finalRecord = SmartBriefingRecord(
                id = UUID.randomUUID().toString(),
                userId = userId,
                timeSlot = currentSlot.value,
                dataHash = hash,
                narrative = localNarrative,
                metrics = metrics,
                isAiGenerated = false,
                createdAt = System.currentTimeMillis(),
                updatedAt = System.currentTimeMillis()
            )

            // Tier 2: AI Enhancement via Gemini Flash API (if key is present)
            val apiKey = settings.geminiApiKey?.trim() ?: ""
            if (apiKey.isNotEmpty()) {
                try {
                    val aiNarrative = GeminiApiService.shared.generateBriefing(
                        apiKey = apiKey,
                        slot = currentSlot,
                        userName = userName,
                        metrics = metrics,
                        streamTitles = activeStreams,
                        topPills = topPills,
                        closingWish = localNarrative.closingWish,
                        closingIcon = localNarrative.closingIcon
                    )
                    finalRecord = finalRecord.copy(
                        narrative = aiNarrative,
                        isAiGenerated = true
                    )
                } catch (_: Exception) {
                    // Retain Tier 1 deterministic narrative on timeout or error
                }
            }

            saveCachedBriefing(finalRecord)

            // Asynchronously sync to Supabase
            scope.launch(Dispatchers.IO) {
                syncToSupabase(finalRecord)
            }

            finalRecord
        } finally {
            _isLoading.value = false
        }
    }

    suspend fun checkAutomaticMorningPresentation(
        settings: AppSettings,
        userName: String,
        userId: String,
        weather: WeatherResponse?,
        locationName: String,
        healthRepository: HealthDataRepository,
        habitsRepository: HabitsRepository,
        smartLedgerRepository: SmartLedgerRepository,
        tagdosRepository: TagdosRepository,
        newsRepository: NewsRepository
    ): Boolean = withContext(Dispatchers.IO) {
        if (!settings.smartBriefingEnabled || !settings.smartBriefingAutoMorning) {
            return@withContext false
        }

        val slot = BriefingTimeSlot.current()
        if (slot != BriefingTimeSlot.MORNING) {
            return@withContext false
        }

        val todayKey = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val lastShownDay = prefs.getString(lastAutoShownDateKey, null)

        val metrics = collectCurrentMetrics(
            weather = weather,
            locationName = locationName,
            healthRepository = healthRepository,
            habitsRepository = habitsRepository,
            smartLedgerRepository = smartLedgerRepository,
            tagdosRepository = tagdosRepository,
            newsRepository = newsRepository
        )
        val activeStreams = tagdosRepository.streams.value.map { it.displayTitle }
        val hash = computeDataHash(slot, metrics, activeStreams.size)

        if (lastShownDay != todayKey || _activeBriefing.value?.dataHash != hash) {
            prefs.edit().putString(lastAutoShownDateKey, todayKey).apply()
            getOrGenerateBriefing(
                forceRefresh = true,
                userName = userName,
                userId = userId,
                settings = settings,
                weather = weather,
                locationName = locationName,
                healthRepository = healthRepository,
                habitsRepository = habitsRepository,
                smartLedgerRepository = smartLedgerRepository,
                tagdosRepository = tagdosRepository,
                newsRepository = newsRepository
            )
            _shouldPresentMorningAutomatically.value = true
            true
        } else {
            false
        }
    }

    private fun collectCurrentMetrics(
        weather: WeatherResponse?,
        locationName: String,
        healthRepository: HealthDataRepository,
        habitsRepository: HabitsRepository,
        smartLedgerRepository: SmartLedgerRepository,
        tagdosRepository: TagdosRepository,
        newsRepository: NewsRepository
    ): SmartBriefingMetrics {
        val primarySession = healthRepository.primarySleepSession.value
        val sleepDurationHours = primarySession?.let { it.asleepSeconds.toDouble() / 3600.0 }
        val sleepDurationFormatted = primarySession?.totalAsleepFormatted

        val resolvedCity = when {
            locationName.isNotBlank() && locationName != "Detecting..." -> locationName
            !weather?.name.isNullOrBlank() -> weather?.name
            else -> "Bucharest"
        }

        val ledger = smartLedgerRepository.parsedLedger.value
        val streams = tagdosRepository.streams.value
        val activeMemoCount = streams.count { it.activeMemos.isNotBlank() }

        val restingBpm = healthRepository.restingBpm.value.toDouble()

        return SmartBriefingMetrics(
            weatherTemp = weather?.main?.temp,
            weatherCondition = weather?.weather?.firstOrNull()?.description?.replaceFirstChar { it.uppercase() },
            weatherIcon = weather?.weather?.firstOrNull()?.icon,
            weatherCity = resolvedCity,
            sleepScore = primarySession?.sleepScore,
            sleepDurationHours = sleepDurationHours,
            sleepDurationFormatted = sleepDurationFormatted,
            restingBpm = if (restingBpm > 0) restingBpm else null,
            totalStepsToday = healthRepository.totalStepsToday.value,
            waterMlToday = habitsRepository.waterTotalToday.value,
            waterGoalMl = habitsRepository.waterGoal.value,
            smokesToday = habitsRepository.smokesTotalToday.value,
            smokesBaseline = habitsRepository.smokesSettings.value.baselineDailyCount,
            netWorth = ledger.netWorth,
            daySpend = ledger.outgoingTotal,
            activeStreamCount = streams.size,
            activeMemoCount = activeMemoCount,
            topNewsTitle = newsRepository.articles.value.firstOrNull()?.title
        )
    }

    private fun computeDataHash(slot: BriefingTimeSlot, metrics: SmartBriefingMetrics, streamCount: Int): String {
        val tempRounded = (metrics.weatherTemp ?: 20.0).roundToInt()
        val sleepRounded = metrics.sleepScore ?: 0
        val stepsBucket = metrics.totalStepsToday / 500
        val waterBucket = (metrics.waterMlToday / 100.0).toInt()
        val smokes = metrics.smokesToday
        val netWorthBucket = (metrics.netWorth / 50.0).toInt()

        val composite = "${slot.value}|$tempRounded|$sleepRounded|$stepsBucket|$waterBucket|$smokes|$netWorthBucket|$streamCount|${metrics.topNewsTitle ?: ""}"
        val digest = MessageDigest.getInstance("SHA-256").digest(composite.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }

    private fun extractTopPills(tagdosRepository: TagdosRepository): List<String> {
        val streams = tagdosRepository.streams.value
        val pills = mutableListOf<String>()

        // 1. Urgent uncompleted pills
        for (stream in streams) {
            for (cluster in stream.clusters) {
                for (pill in cluster.pills) {
                    if (!pill.isCompleted && pill.type == TagDoPillType.Urgent) {
                        val trimmed = pill.rawText.trim()
                        if (trimmed.isNotEmpty() && !pills.contains(trimmed)) {
                            pills.add(trimmed)
                        }
                    }
                }
            }
        }

        // 2. Driving pills from each stream
        for (stream in streams) {
            val driving = stream.clusters.firstOrNull()?.pills?.firstOrNull { !it.isCompleted }?.rawText?.trim()
            if (!driving.isNullOrEmpty() && !pills.contains(driving)) {
                pills.add(driving)
            }
            if (pills.size >= 4) break
        }

        // 3. Fallback active pills
        if (pills.isEmpty()) {
            for (stream in streams) {
                for (cluster in stream.clusters) {
                    for (pill in cluster.pills) {
                        if (!pill.isCompleted) {
                            val trimmed = pill.rawText.trim()
                            if (trimmed.isNotEmpty() && !pills.contains(trimmed)) {
                                pills.add(trimmed)
                            }
                            if (pills.size >= 4) break
                        }
                    }
                    if (pills.size >= 4) break
                }
                if (pills.size >= 4) break
            }
        }

        return pills
    }

    fun synthesizeLocalNarrative(
        slot: BriefingTimeSlot,
        userName: String,
        metrics: SmartBriefingMetrics,
        activeStreams: List<String>,
        topPills: List<String> = emptyList()
    ): SmartBriefingNarrative {
        val greeting = "${slot.diurnalGreeting(userName)} Here is your integrated daily briefing."

        // Weather & Rain Detection
        val tempString = metrics.weatherTemp?.let { "${it.roundToInt()}°C" } ?: "pleasant temperatures"
        val condition = metrics.weatherCondition ?: "clear skies"
        val condLower = condition.lowercase()
        val isRaining = condLower.contains("rain") || condLower.contains("ploaie") || condLower.contains("drizzle") ||
                condLower.contains("thunderstorm") || condLower.contains("averse")

        val weatherAdvice = if (isRaining) {
            "It's $tempString outside with $condition. Don't forget an umbrella if you head out today."
        } else {
            when (slot) {
                BriefingTimeSlot.MORNING -> "Conditions show $condition at $tempString. Great weather to plan your day."
                BriefingTimeSlot.INTRADAY -> "Weather holds steady with $condition around $tempString."
                BriefingTimeSlot.EVENING -> "The evening winds down peacefully with $condition at $tempString."
                BriefingTimeSlot.NIGHTLY -> "Night air is calm around $tempString."
            }
        }

        val closingWish: String
        val closingIcon: String
        if (isRaining) {
            closingWish = "Grab an umbrella today! :))"
            closingIcon = "umbrella.fill"
        } else {
            closingWish = slot.defaultClosingWish
            closingIcon = slot.defaultClosingIcon
        }

        // Health & Vitals
        val steps = metrics.totalStepsToday
        val formattedAsleep = metrics.sleepDurationFormatted?.takeIf { it.isNotBlank() && it != "--" }
            ?: metrics.sleepDurationHours?.takeIf { it > 0 }?.let { h ->
                val totalMin = (h * 60.0).roundToInt()
                val hrs = totalMin / 60
                val mins = totalMin % 60
                if (mins > 0) "${hrs}h ${mins}m" else "${hrs}h"
            }

        val score = metrics.sleepScore
        val healthAdvice = if (score != null && formattedAsleep != null) {
            if (score >= 80) {
                if (steps > 500) {
                    "Great recovery with $formattedAsleep asleep (Score $score/100). You've already logged $steps steps."
                } else {
                    "Great recovery with $formattedAsleep asleep (Score $score/100). Ready for a focused, high-energy day."
                }
            } else {
                "Logged $formattedAsleep asleep (Score $score/100). Maintain a steady pace and stay well hydrated."
            }
        } else if (steps > 500) {
            val bpmInfo = if ((metrics.restingBpm ?: 0.0) > 0) ", with resting heart rate at ${metrics.restingBpm!!.toInt()} bpm" else ""
            "Activity in full stride with $steps steps logged today$bpmInfo."
        } else {
            if ((metrics.restingBpm ?: 0.0) > 0) "Resting heart rate is at ${metrics.restingBpm!!.toInt()} bpm." else "Recovery vitals are syncing as your day gets underway."
        }

        // Habits & Cravings
        val waterLiters = "%.1fL".format(Locale.US, metrics.waterMlToday / 1000.0)
        val waterGoalLiters = "%.1fL".format(Locale.US, metrics.waterGoalMl / 1000.0)
        val smokes = metrics.smokesToday
        val baseline = metrics.smokesBaseline
        val smokesAdvice = when {
            smokes == 0 -> {
                if (slot == BriefingTimeSlot.MORNING) "Start the day with a glass of water and keep cravings at zero."
                else "Zero cigarettes logged—excellent discipline for your health."
            }
            smokes <= baseline -> "$smokes cigarettes logged, staying below your daily limit ($baseline). Stay hydrated whenever a craving hits."
            else -> "$smokes cigarettes logged today. Take a deep breath, pause, and focus on clean hydration for the rest of the day."
        }

        val habitAdvice = if (metrics.waterMlToday > 0) {
            "Hydration is at $waterLiters / $waterGoalLiters. $smokesAdvice"
        } else {
            smokesAdvice
        }

        // Finance (Romanian Lei with dot separator)
        val symbols = DecimalFormatSymbols(Locale("ro", "RO")).apply {
            groupingSeparator = '.'
            decimalSeparator = ','
        }
        val numFormatter = DecimalFormat("#,###", symbols)
        val formattedNetWorth = "${numFormatter.format(metrics.netWorth)} Lei"

        val financeAdvice = if (metrics.daySpend > 0) {
            val outK = "%.1fk".format(Locale.US, metrics.daySpend / 1000.0)
            "Net worth stands at $formattedNetWorth, with today's outflow at $outK Lei."
        } else {
            "Liquid reserves and portfolio hold steady at $formattedNetWorth."
        }

        // Tagdos
        val resolvedPills = topPills
        val tagdosAdvice = when {
            resolvedPills.isNotEmpty() -> "Here's what needs your focus today: ${resolvedPills.take(3).joinToString(", ")}."
            activeStreams.isNotEmpty() -> "All Tagdos streams are up to date with no active blockers."
            else -> "Tagdos streams are clear with no pending tasks."
        }

        // News
        val newsAdvice = if (!metrics.topNewsTitle.isNullOrBlank()) {
            "Top headline on your radar: \"${metrics.topNewsTitle}\"."
        } else {
            ""
        }

        // Outro
        val outro = when (slot) {
            BriefingTimeSlot.MORNING -> "Set your intentions, stay focused, and make today count."
            BriefingTimeSlot.INTRADAY -> "Keep up this steady momentum through the afternoon."
            BriefingTimeSlot.EVENING -> "Reflect on today's milestones and enjoy a restful evening."
            BriefingTimeSlot.NIGHTLY -> "Power down screens, recharge your energy, and sleep peacefully."
        }

        return SmartBriefingNarrative(
            greeting = greeting,
            weatherText = weatherAdvice,
            healthText = healthAdvice,
            habitsText = habitAdvice,
            financeText = financeAdvice,
            tagdosText = tagdosAdvice,
            newsText = newsAdvice,
            outroText = outro,
            closingWish = closingWish,
            closingIcon = closingIcon
        )
    }

    fun buildCardItems(record: SmartBriefingRecord): List<BriefingCardItem> {
        val list = mutableListOf<BriefingCardItem>()
        val narrative = record.narrative
        val metrics = record.metrics

        // 1. Atmosphere
        if (narrative.weatherText.isNotBlank()) {
            val temp = metrics.weatherTemp?.roundToInt()
            val badge = if (temp != null) "$temp°C · ${metrics.weatherCondition ?: "Clear"}" else null
            list.add(
                BriefingCardItem(
                    id = "weather",
                    iconName = "cloud",
                    title = "Atmosphere & Weather",
                    badgeText = badge,
                    badgeColorHex = "#00BBF9",
                    text = narrative.weatherText,
                    accentColorHex = "#00BBF9"
                )
            )
        }

        // 2. Health & Recovery
        if (narrative.healthText.isNotBlank()) {
            val badge = if (metrics.sleepScore != null) "Score ${metrics.sleepScore}/100" else "${metrics.totalStepsToday} steps"
            list.add(
                BriefingCardItem(
                    id = "health",
                    iconName = "heart",
                    title = "Health & Recovery",
                    badgeText = badge,
                    badgeColorHex = "#FF5252",
                    text = narrative.healthText,
                    accentColorHex = "#FF5252"
                )
            )
        }

        // 3. Habits & Cravings
        if (narrative.habitsText.isNotBlank()) {
            val badge = if (metrics.smokesToday == 0) "Zero Smokes" else "${metrics.smokesToday} Cigs"
            list.add(
                BriefingCardItem(
                    id = "habits",
                    iconName = "water_drop",
                    title = "Habits & Cravings",
                    badgeText = badge,
                    badgeColorHex = "#00F5D4",
                    text = narrative.habitsText,
                    accentColorHex = "#00F5D4"
                )
            )
        }

        // 4. Financial Clarity
        if (narrative.financeText.isNotBlank()) {
            val symbols = DecimalFormatSymbols(Locale("ro", "RO")).apply {
                groupingSeparator = '.'
            }
            val numFormatter = DecimalFormat("#,###", symbols)
            val badge = "${numFormatter.format(metrics.netWorth)} Lei"
            list.add(
                BriefingCardItem(
                    id = "finances",
                    iconName = "credit_card",
                    title = "Financial Overview",
                    badgeText = badge,
                    badgeColorHex = "#34C759",
                    text = narrative.financeText,
                    accentColorHex = "#34C759"
                )
            )
        }

        // 5. Tagdos Focus
        if (narrative.tagdosText.isNotBlank()) {
            list.add(
                BriefingCardItem(
                    id = "tagdos",
                    iconName = "checklist",
                    title = "Tagdos Daily Focus",
                    badgeText = "${metrics.activeStreamCount} Streams",
                    badgeColorHex = "#7B2CBF",
                    text = narrative.tagdosText,
                    accentColorHex = "#7B2CBF"
                )
            )
        }

        // 6. News Radar
        if (narrative.newsText.isNotBlank()) {
            list.add(
                BriefingCardItem(
                    id = "news",
                    iconName = "newspaper",
                    title = "Headlines Radar",
                    badgeText = "Breaking",
                    badgeColorHex = "#FF9A3D",
                    text = narrative.newsText,
                    accentColorHex = "#FF9A3D"
                )
            )
        }

        // 7. Outro
        if (narrative.outroText.isNotBlank()) {
            list.add(
                BriefingCardItem(
                    id = "outro",
                    iconName = "sparkles",
                    title = "Diurnal Focus",
                    badgeText = record.slot.displayName,
                    badgeColorHex = "#F72585",
                    text = narrative.outroText,
                    accentColorHex = "#F72585"
                )
            )
        }

        return list
    }

    private suspend fun syncToSupabase(record: SmartBriefingRecord) {
        if (record.userId.isEmpty() || record.userId == "guest") return
        try {
            SupabaseClientManager.client.postgrest["daily_smart_summaries"].upsert(record)
        } catch (_: Exception) {}
    }
}
