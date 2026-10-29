package com.intellidream.daily.cosmos

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.intellidream.daily.DailyApp
import com.intellidream.daily.model.ApodResponse
import com.intellidream.daily.model.AppSettings
import com.intellidream.daily.model.AuthSessionState
import com.intellidream.daily.model.CelesTrakOmmRecord
import com.intellidream.daily.model.CosmosBookmark
import com.intellidream.daily.model.CosmosObservation
import com.intellidream.daily.model.LiveSatellitePosition
import com.intellidream.daily.model.SGP4Propagator
import com.intellidream.daily.model.SatellitePass
import com.intellidream.daily.model.SpaceWeatherReport
import com.intellidream.daily.model.StargazingConditions
import com.intellidream.daily.model.TelemetryProvenance
import com.intellidream.daily.network.SupabaseClientManager
import io.github.jan.supabase.postgrest.from
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.UUID
import kotlin.math.abs
import kotlin.math.roundToInt

data class CosmosWeatherOverlay(
    val cloudTotalPercent: Int,
    val cloudLowPercent: Int,
    val cloudMidPercent: Int,
    val cloudHighPercent: Int,
    val visibilityKm: Double?,
    val temperatureCelsius: Double?,
    val dewPointCelsius: Double?,
    val seeingArcseconds: Double?,
    val transparencyLabel: String?,
    val provenance: TelemetryProvenance
)

data class CosmosLiveBundle(
    val weatherOverlay: CosmosWeatherOverlay?,
    val spaceWeather: SpaceWeatherReport,
    val apod: ApodResponse?,
    val apodProvenance: TelemetryProvenance,
    val issOmm: CelesTrakOmmRecord?,
    val issLivePosition: LiveSatellitePosition?,
    val issPasses: List<SatellitePass>,
    val issProvenance: TelemetryProvenance
)

class CosmosLiveRepository(private val context: Context) {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        isLenient = true
    }
    private val prefs = context.getSharedPreferences("cosmos_live_cache_v2", Context.MODE_PRIVATE)

    companion object {
        private const val KEY_ISS_OMM = "iss_omm_json"
        private const val KEY_ISS_OMM_TS = "iss_omm_ts"
        private const val KEY_APOD_JSON = "apod_json"
        private const val KEY_APOD_TS = "apod_ts"
        private const val KEY_SPACE_JSON = "space_weather_json"
        private const val KEY_SPACE_TS = "space_weather_ts"
        private const val KEY_WEATHER_JSON = "sky_weather_json"
        private const val KEY_WEATHER_TS = "sky_weather_ts"
        private const val KEY_BOOKMARKS = "cosmos_bookmarks_json"
        private const val KEY_OBSERVATIONS = "cosmos_observations_json"
        private const val CHANNEL_ID = "daily_cosmos_alerts"
    }

    // MARK: - Full Live Telemetry Refresh (Parallel & Resilient)

    suspend fun fetchLiveBundle(
        latitude: Double,
        longitude: Double,
        elevationMeters: Double = 0.0,
        settings: AppSettings
    ): CosmosLiveBundle = coroutineScope {
        val weatherDeferred = async { fetchWeatherAndSeeing(latitude, longitude, settings) }
        val spaceDeferred = async { fetchSpaceWeather() }
        val apodDeferred = async { fetchApod(settings.nasaApiKey.orEmpty()) }
        val ommDeferred = async { fetchOrLoadIssOmm() }

        val weather = weatherDeferred.await()
        val space = spaceDeferred.await()
        val (apod, apodProv) = apodDeferred.await()
        val (omm, issProv) = ommDeferred.await()

        val nowMs = System.currentTimeMillis()
        val livePos = omm?.let {
            SGP4Propagator.livePosition(it, nowMs, latitude, longitude, elevationMeters)
        }
        val passes = omm?.let {
            SGP4Propagator.predictVisiblePasses(
                omm = it,
                latitudeDegrees = latitude,
                longitudeDegrees = longitude,
                elevationMeters = elevationMeters,
                startMillis = nowMs,
                hoursAhead = 48.0,
                minPeakAltitudeDegrees = 10.0
            )
        } ?: emptyList()

        CosmosLiveBundle(
            weatherOverlay = weather,
            spaceWeather = space,
            apod = apod,
            apodProvenance = apodProv,
            issOmm = omm,
            issLivePosition = livePos,
            issPasses = passes,
            issProvenance = issProv
        )
    }

    fun computeLiveIssPosition(
        omm: CelesTrakOmmRecord?,
        timestampMillis: Long,
        latitude: Double,
        longitude: Double,
        elevationMeters: Double = 0.0
    ): LiveSatellitePosition? {
        if (omm == null) return null
        return SGP4Propagator.livePosition(omm, timestampMillis, latitude, longitude, elevationMeters)
    }

    // MARK: - 1. Open-Meteo UTC Multi-Layer Clouds + 7Timer ASTRO Seeing

    @Serializable
    private data class CachedWeatherOverlay(
        val cloudTotalPercent: Int,
        val cloudLowPercent: Int,
        val cloudMidPercent: Int,
        val cloudHighPercent: Int,
        val visibilityKm: Double? = null,
        val temperatureCelsius: Double? = null,
        val dewPointCelsius: Double? = null,
        val seeingArcseconds: Double? = null,
        val transparencyLabel: String? = null
    )

    private suspend fun fetchWeatherAndSeeing(
        lat: Double,
        lon: Double,
        settings: AppSettings
    ): CosmosWeatherOverlay? = withContext(Dispatchers.IO) {
        val seeingPair = fetch7TimerSeeing(lat, lon)

        val baseEndpoint = settings.cosmosWeatherEndpoint.orEmpty().trim().ifEmpty {
            "https://api.open-meteo.com/v1/forecast"
        }
        val apiKeyQuery = settings.cosmosWeatherApiKey.orEmpty().trim().takeIf { it.isNotEmpty() }?.let { "&apikey=$it" } ?: ""
        val url = "$baseEndpoint?latitude=${"%.4f".format(java.util.Locale.US, lat)}" +
            "&longitude=${"%.4f".format(java.util.Locale.US, lon)}" +
            "&hourly=cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high,visibility,temperature_2m,dew_point_2m" +
            "&forecast_days=2&timezone=UTC$apiKeyQuery"

        val body = httpGet(url, timeoutMs = 8_000)
        if (body != null) {
            val parsed = parseOpenMeteoUtc(body, seeingPair)
            if (parsed != null) {
                val cacheObj = CachedWeatherOverlay(
                    parsed.cloudTotalPercent,
                    parsed.cloudLowPercent,
                    parsed.cloudMidPercent,
                    parsed.cloudHighPercent,
                    parsed.visibilityKm,
                    parsed.temperatureCelsius,
                    parsed.dewPointCelsius,
                    parsed.seeingArcseconds,
                    parsed.transparencyLabel
                )
                prefs.edit()
                    .putString(KEY_WEATHER_JSON, json.encodeToString(cacheObj))
                    .putLong(KEY_WEATHER_TS, System.currentTimeMillis())
                    .apply()
                return@withContext parsed
            }
        }

        // Fallback to cached weather with explicit age provenance
        val cachedRaw = prefs.getString(KEY_WEATHER_JSON, null)
        val cachedTs = prefs.getLong(KEY_WEATHER_TS, 0L)
        if (!cachedRaw.isNullOrBlank() && cachedTs > 0L) {
            val c = runCatching { json.decodeFromString<CachedWeatherOverlay>(cachedRaw) }.getOrNull()
            if (c != null) {
                val ageSec = ((System.currentTimeMillis() - cachedTs) / 1000L).coerceAtLeast(1L)
                return@withContext CosmosWeatherOverlay(
                    cloudTotalPercent = c.cloudTotalPercent,
                    cloudLowPercent = c.cloudLowPercent,
                    cloudMidPercent = c.cloudMidPercent,
                    cloudHighPercent = c.cloudHighPercent,
                    visibilityKm = c.visibilityKm,
                    temperatureCelsius = c.temperatureCelsius,
                    dewPointCelsius = c.dewPointCelsius,
                    seeingArcseconds = c.seeingArcseconds,
                    transparencyLabel = c.transparencyLabel,
                    provenance = TelemetryProvenance.cached(ageSec, "Open-Meteo + 7Timer")
                )
            }
        }
        null
    }

    private fun parseOpenMeteoUtc(
        rawJson: String,
        seeingPair: Pair<Double?, String?>
    ): CosmosWeatherOverlay? = runCatching {
        val root = json.parseToJsonElement(rawJson).jsonObject
        val hourly = root["hourly"]?.jsonObject ?: return null
        val times = hourly["time"]?.jsonArray ?: return null
        if (times.isEmpty()) return null

        val nowEpochSec = System.currentTimeMillis() / 1000L
        var bestIdx = 0
        var bestDiff = Long.MAX_VALUE
        for (i in 0 until times.size) {
            val iso = times[i].jsonPrimitive.content
            val normalizedIso = if (iso.endsWith("Z")) iso else "${iso}:00Z".replace(":00:00Z", ":00Z")
            val epoch = runCatching { Instant.parse(normalizedIso).epochSecond }.getOrNull() ?: continue
            val diff = abs(epoch - nowEpochSec)
            if (diff < bestDiff) {
                bestDiff = diff
                bestIdx = i
            }
        }

        fun intAt(key: String, fallback: Int = 0): Int =
            hourly[key]?.jsonArray?.getOrNull(bestIdx)?.jsonPrimitive?.doubleOrNull?.roundToInt() ?: fallback

        fun doubleAt(key: String): Double? =
            hourly[key]?.jsonArray?.getOrNull(bestIdx)?.jsonPrimitive?.doubleOrNull

        val total = intAt("cloud_cover", 0).coerceIn(0, 100)
        val low = intAt("cloud_cover_low", total / 3).coerceIn(0, 100)
        val mid = intAt("cloud_cover_mid", total / 3).coerceIn(0, 100)
        val high = intAt("cloud_cover_high", total / 3).coerceIn(0, 100)
        val visMeters = doubleAt("visibility")
        val tempC = doubleAt("temperature_2m")
        val dewC = doubleAt("dew_point_2m")

        CosmosWeatherOverlay(
            cloudTotalPercent = total,
            cloudLowPercent = low,
            cloudMidPercent = mid,
            cloudHighPercent = high,
            visibilityKm = visMeters?.let { it / 1000.0 },
            temperatureCelsius = tempC,
            dewPointCelsius = dewC,
            seeingArcseconds = seeingPair.first,
            transparencyLabel = seeingPair.second,
            provenance = TelemetryProvenance.live(
                if (seeingPair.first != null) "Open-Meteo UTC + 7Timer ASTRO" else "Open-Meteo UTC"
            )
        )
    }.getOrNull()

    private fun fetch7TimerSeeing(lat: Double, lon: Double): Pair<Double?, String?> {
        val url = "https://www.7timer.info/bin/astro.php?lon=${"%.3f".format(java.util.Locale.US, lon)}" +
            "&lat=${"%.3f".format(java.util.Locale.US, lat)}&ac=0&unit=metric&output=json&tzshift=0"
        val raw = httpGet(url, timeoutMs = 6_000) ?: return Pair(null, null)
        return runCatching {
            val root = json.parseToJsonElement(raw).jsonObject
            val series = root["dataseries"]?.jsonArray ?: return Pair(null, null)
            val first = series.firstOrNull()?.jsonObject ?: return Pair(null, null)
            val seeingIdx = first["seeing"]?.jsonPrimitive?.intOrNull
            val transIdx = first["transparency"]?.jsonPrimitive?.intOrNull
            val seeingArcsec = when (seeingIdx) {
                1 -> 0.7; 2 -> 0.9; 3 -> 1.1; 4 -> 1.4
                5 -> 1.8; 6 -> 2.3; 7 -> 3.0; 8 -> 4.0
                else -> null
            }
            val transLabel = when (transIdx) {
                1, 2 -> "Crystal (<0.4 mag)"
                3 -> "Clear (0.5 mag)"
                4 -> "Moderate (0.7 mag)"
                5, 6 -> "Hazy (1.0 mag)"
                7, 8 -> "Poor (>1.2 mag)"
                else -> null
            }
            Pair(seeingArcsec, transLabel)
        }.getOrDefault(Pair(null, null))
    }

    // MARK: - 2. Real NOAA SWPC Space Weather (Kp + RTSW Bz/Bt + Solar Wind + OVATION)

    private suspend fun fetchSpaceWeather(): SpaceWeatherReport = withContext(Dispatchers.IO) {
        val kpRaw = httpGet("https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json", 7_000)
        val magRaw = httpGet("https://services.swpc.noaa.gov/json/rtsw/rtsw_mag_1m.json", 7_000)
        val windRaw = httpGet("https://services.swpc.noaa.gov/json/rtsw/rtsw_wind_1m.json", 7_000)

        val kpVal = kpRaw?.let { parseNoaaKp(it) }
        val (btVal, bzVal) = magRaw?.let { parseNoaaMag(it) } ?: Pair(null, null)
        val (speedVal, densityVal) = windRaw?.let { parseNoaaWind(it) } ?: Pair(null, null)

        if (kpVal != null || bzVal != null || speedVal != null) {
            val kp = kpVal ?: 2.0
            val bz = bzVal
            val stormAlert = kp >= 5.0 || (bz != null && bz <= -8.0 && kp >= 4.0)
            val status = when {
                kp >= 7.0 -> "Severe Geomagnetic Storm (G3+) — Mid-latitude aurora active!"
                kp >= 5.0 -> "Geomagnetic Storm (G1–G2) — High-latitude aurora active."
                bz != null && bz <= -5.0 -> "Southward IMF Bz (${"%.1f".format(bz)} nT) — Substorm coupling favorable."
                else -> "Quiet magnetosphere (Kp ${"%.1f".format(kp)}) — Stable dark-sky conditions."
            }
            val report = SpaceWeatherReport(
                kpIndex = kpVal,
                btTotalFieldNt = btVal,
                bzMagneticFieldNt = bzVal,
                solarWindSpeedKmS = speedVal,
                solarWindDensityCm3 = densityVal,
                ovationProbabilityPercent = null,
                isAuroraAlertActive = stormAlert,
                statusMessage = status,
                provenance = TelemetryProvenance.live("NOAA SWPC DSCOVR/Planetary-K")
            )
            prefs.edit()
                .putString(KEY_SPACE_JSON, json.encodeToString(report))
                .putLong(KEY_SPACE_TS, System.currentTimeMillis())
                .apply()
            return@withContext report
        }

        val cached = prefs.getString(KEY_SPACE_JSON, null)
        val cachedTs = prefs.getLong(KEY_SPACE_TS, 0L)
        if (!cached.isNullOrBlank() && cachedTs > 0L) {
            val decoded = runCatching { json.decodeFromString<SpaceWeatherReport>(cached) }.getOrNull()
            if (decoded != null) {
                val ageSec = ((System.currentTimeMillis() - cachedTs) / 1000L).coerceAtLeast(1L)
                return@withContext decoded.copy(
                    provenance = TelemetryProvenance.cached(ageSec, "NOAA SWPC")
                )
            }
        }

        SpaceWeatherReport(
            statusMessage = "NOAA SWPC live telemetry unavailable offline.",
            provenance = TelemetryProvenance.unavailable("Offline")
        )
    }

    private fun parseNoaaKp(raw: String): Double? = runCatching {
        val arr = json.parseToJsonElement(raw).jsonArray
        for (i in arr.size - 1 downTo 1) {
            val row = arr[i]
            if (row is JsonArray && row.size >= 2) {
                val kp = row[1].jsonPrimitive.content.toDoubleOrNull()
                if (kp != null) return kp
            } else if (row is JsonObject) {
                val kp = row["Kp"]?.jsonPrimitive?.content?.toDoubleOrNull()
                    ?: row["kp_index"]?.jsonPrimitive?.content?.toDoubleOrNull()
                if (kp != null) return kp
            }
        }
        null
    }.getOrNull()

    private fun parseNoaaMag(raw: String): Pair<Double?, Double?> = runCatching {
        val arr = json.parseToJsonElement(raw).jsonArray
        for (i in arr.size - 1 downTo 0) {
            val obj = arr[i].jsonObject
            val bz = obj["bz_gsm"]?.jsonPrimitive?.doubleOrNull
            val bt = obj["bt"]?.jsonPrimitive?.doubleOrNull
            if (bz != null || bt != null) return Pair(bt, bz)
        }
        Pair(null, null)
    }.getOrDefault(Pair(null, null))

    private fun parseNoaaWind(raw: String): Pair<Double?, Double?> = runCatching {
        val arr = json.parseToJsonElement(raw).jsonArray
        for (i in arr.size - 1 downTo 0) {
            val obj = arr[i].jsonObject
            val speed = obj["proton_speed"]?.jsonPrimitive?.doubleOrNull
                ?: obj["speed"]?.jsonPrimitive?.doubleOrNull
            val density = obj["proton_density"]?.jsonPrimitive?.doubleOrNull
                ?: obj["density"]?.jsonPrimitive?.doubleOrNull
            if (speed != null && speed > 0.0) return Pair(speed, density)
        }
        Pair(null, null)
    }.getOrDefault(Pair(null, null))

    // MARK: - 3. CelesTrak ISS OMM + SGP4 Orbital Elements Cache (Zero Synthetic Passes)

    private suspend fun fetchOrLoadIssOmm(): Pair<CelesTrakOmmRecord?, TelemetryProvenance> = withContext(Dispatchers.IO) {
        val raw = httpGet("https://celestrak.org/NORAD/elements/gp.php?CATNR=25544&FORMAT=JSON", 8_000)
        if (raw != null) {
            val parsed = runCatching {
                json.decodeFromString<List<CelesTrakOmmRecord>>(raw).firstOrNull()
            }.getOrNull()
            if (parsed != null) {
                prefs.edit()
                    .putString(KEY_ISS_OMM, json.encodeToString(parsed))
                    .putLong(KEY_ISS_OMM_TS, System.currentTimeMillis())
                    .apply()
                return@withContext Pair(parsed, TelemetryProvenance.live("CelesTrak GP + SGP4"))
            }
        }

        val cached = prefs.getString(KEY_ISS_OMM, null)
        val cachedTs = prefs.getLong(KEY_ISS_OMM_TS, 0L)
        if (!cached.isNullOrBlank() && cachedTs > 0L) {
            val ageMs = System.currentTimeMillis() - cachedTs
            // Valid up to 7 days for SGP4 propagation
            if (ageMs <= 7L * 24L * 3600_000L) {
                val omm = runCatching { json.decodeFromString<CelesTrakOmmRecord>(cached) }.getOrNull()
                if (omm != null) {
                    return@withContext Pair(
                        omm,
                        TelemetryProvenance.cached((ageMs / 1000L).coerceAtLeast(1L), "Cached CelesTrak OMM + SGP4")
                    )
                }
            }
        }
        Pair(null, TelemetryProvenance.unavailable("Download ISS orbital elements once while online"))
    }

    // MARK: - 4. NASA APOD (Configurable API Key + Cached Fallback)

    private suspend fun fetchApod(configuredApiKey: String): Pair<ApodResponse?, TelemetryProvenance> =
        withContext(Dispatchers.IO) {
            val key = configuredApiKey.trim().ifEmpty { "DEMO_KEY" }
            val raw = httpGet("https://api.nasa.gov/planetary/apod?api_key=$key", 8_000)
            if (raw != null) {
                val parsed = runCatching { json.decodeFromString<ApodResponse>(raw) }.getOrNull()
                if (parsed != null && parsed.title.isNotBlank()) {
                    prefs.edit()
                        .putString(KEY_APOD_JSON, json.encodeToString(parsed))
                        .putLong(KEY_APOD_TS, System.currentTimeMillis())
                        .apply()
                    return@withContext Pair(parsed, TelemetryProvenance.live("NASA APOD"))
                }
            }

            val cached = prefs.getString(KEY_APOD_JSON, null)
            val cachedTs = prefs.getLong(KEY_APOD_TS, 0L)
            if (!cached.isNullOrBlank() && cachedTs > 0L) {
                val parsed = runCatching { json.decodeFromString<ApodResponse>(cached) }.getOrNull()
                if (parsed != null) {
                    val ageSec = ((System.currentTimeMillis() - cachedTs) / 1000L).coerceAtLeast(1L)
                    return@withContext Pair(parsed, TelemetryProvenance.cached(ageSec, "NASA APOD"))
                }
            }
            Pair(null, TelemetryProvenance.unavailable("Set a free NASA API key in Settings if rate-limited"))
        }

    // MARK: - 5. Supabase Bookmarks & Observations + #sky TagDoS Quick Note Mirror

    suspend fun loadBookmarks(): List<CosmosBookmark> = withContext(Dispatchers.IO) {
        val local = prefs.getString(KEY_BOOKMARKS, null)?.let {
            runCatching { json.decodeFromString<List<CosmosBookmark>>(it) }.getOrNull()
        } ?: emptyList()

        val uid = currentAuthenticatedUserId() ?: return@withContext local
        val remote = runCatching {
            SupabaseClientManager.client.from("cosmos_bookmarks")
                .select {
                    filter { eq("user_id", uid) }
                }
                .decodeList<CosmosBookmark>()
        }.getOrNull()

        if (remote != null) {
            val merged = (remote + local).distinctBy { it.objectId }
            prefs.edit().putString(KEY_BOOKMARKS, json.encodeToString(merged)).apply()
            merged
        } else {
            local
        }
    }

    suspend fun toggleBookmark(
        objectId: String,
        objectName: String,
        category: String,
        raHours: Double? = null,
        decDeg: Double? = null,
        magnitude: Double? = null,
        constellation: String? = null
    ): List<CosmosBookmark> = withContext(Dispatchers.IO) {
        val existing = loadBookmarks().toMutableList()
        val found = existing.firstOrNull { it.objectId == objectId }
        val uid = currentAuthenticatedUserId()
        val nowIso = DateTimeFormatter.ISO_INSTANT.format(Instant.now())

        if (found != null) {
            existing.removeAll { it.objectId == objectId }
            prefs.edit().putString(KEY_BOOKMARKS, json.encodeToString(existing)).apply()
            if (uid != null) {
                runCatching {
                    SupabaseClientManager.client.from("cosmos_bookmarks").delete {
                        filter {
                            eq("user_id", uid)
                            eq("object_id", objectId)
                        }
                    }
                }
            }
        } else {
            val created = CosmosBookmark(
                id = UUID.randomUUID().toString(),
                userId = uid,
                objectId = objectId,
                objectName = objectName,
                category = category,
                raHours = raHours,
                decDeg = decDeg,
                magnitude = magnitude,
                constellation = constellation,
                notes = "",
                createdAt = nowIso,
                updatedAt = nowIso
            )
            existing.add(0, created)
            prefs.edit().putString(KEY_BOOKMARKS, json.encodeToString(existing)).apply()
            if (uid != null) {
                runCatching {
                    SupabaseClientManager.client.from("cosmos_bookmarks").upsert(created)
                }
            }
        }
        existing
    }

    suspend fun loadObservations(): List<CosmosObservation> = withContext(Dispatchers.IO) {
        val local = prefs.getString(KEY_OBSERVATIONS, null)?.let {
            runCatching { json.decodeFromString<List<CosmosObservation>>(it) }.getOrNull()
        } ?: emptyList()

        val uid = currentAuthenticatedUserId() ?: return@withContext local
        val remote = runCatching {
            SupabaseClientManager.client.from("cosmos_observations")
                .select {
                    filter { eq("user_id", uid) }
                }
                .decodeList<CosmosObservation>()
        }.getOrNull()

        if (remote != null) {
            val merged = (remote + local).distinctBy { it.id }.sortedByDescending { it.observedAt }
            prefs.edit().putString(KEY_OBSERVATIONS, json.encodeToString(merged)).apply()
            merged
        } else {
            local
        }
    }

    suspend fun logObservationAndMirrorToTagdos(
        objectId: String,
        objectName: String,
        category: String,
        latitude: Double,
        longitude: Double,
        locationName: String,
        azimuthDeg: Double?,
        altitudeDeg: Double?,
        bortleClass: Int,
        stargazingScore: Int,
        optics: String = "Naked Eye",
        notes: String = ""
    ): CosmosObservation = withContext(Dispatchers.IO) {
        val nowIso = DateTimeFormatter.ISO_INSTANT.format(Instant.now())
        val uid = currentAuthenticatedUserId()

        val coordsSummary = if (azimuthDeg != null && altitudeDeg != null) {
            "Az ${"%.1f".format(azimuthDeg)}° · Alt ${"%+.1f".format(altitudeDeg)}°"
        } else {
            "Equatorial Sky Target"
        }
        val tagdosTitle = "🌌 Sky Sighting: $objectName"
        val tagdosBody = buildString {
            appendLine("$objectName ($objectId) observed from ${locationName.ifBlank { "Local Observatory" }}.")
            appendLine("$coordsSummary · Bortle $bortleClass · Sky Score $stargazingScore/100 · Optics: $optics")
            if (notes.isNotBlank()) appendLine(notes)
            append("#sky #cosmos")
        }

        val mirroredNoteId = runCatching {
            DailyApp.instance.tagdosRepository.createQuickNoteReturningId(
                title = tagdosTitle,
                content = tagdosBody
            )
        }.getOrNull()

        val obs = CosmosObservation(
            id = UUID.randomUUID().toString(),
            userId = uid,
            objectId = objectId,
            objectName = objectName,
            category = category,
            observedAt = nowIso,
            latitude = latitude,
            longitude = longitude,
            locationName = locationName,
            azimuthDeg = azimuthDeg,
            altitudeDeg = altitudeDeg,
            bortleClass = bortleClass,
            stargazingScore = stargazingScore,
            optics = optics,
            notes = notes,
            tagdosNoteId = mirroredNoteId,
            createdAt = nowIso,
            updatedAt = nowIso
        )

        val updated = (listOf(obs) + loadObservations()).distinctBy { it.id }
        prefs.edit().putString(KEY_OBSERVATIONS, json.encodeToString(updated)).apply()

        if (uid != null) {
            runCatching {
                SupabaseClientManager.client.from("cosmos_observations").insert(obs)
            }
        }
        obs
    }

    // MARK: - 6. Opt-In Local Observatory Notifications (ISS, Aurora Kp, Pristine Sky)

    fun evaluateOptInNotifications(
        settings: AppSettings,
        conditions: StargazingConditions?,
        spaceWeather: SpaceWeatherReport?,
        nextIssPass: SatellitePass?
    ) {
        if (!settings.cosmosNotifyIssPasses && !settings.cosmosNotifyAurora && !settings.cosmosNotifyPristineSky) {
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        ensureChannel()

        val now = System.currentTimeMillis()
        if (settings.cosmosNotifyIssPasses && nextIssPass != null) {
            val minUntil = (nextIssPass.startTimeMillis - now) / 60_000L
            if (minUntil in 5..30 && nextIssPass.maxAltitudeDegrees >= 25.0) {
                val key = "notif_iss_${nextIssPass.id}"
                if (!prefs.getBoolean(key, false)) {
                    prefs.edit().putBoolean(key, true).apply()
                    postNotification(
                        7101,
                        "Bright ISS Pass in $minUntil min",
                        "Rises ${nextIssPass.startCompass}, peaks at ${nextIssPass.maxAltitudeDegrees.roundToInt()}° (mag ${"%.1f".format(nextIssPass.peakMagnitude)})."
                    )
                }
            }
        }

        if (settings.cosmosNotifyAurora && spaceWeather?.isAuroraAlertActive == true) {
            val dayKey = "notif_aurora_${Instant.now().atZone(ZoneOffset.UTC).toLocalDate()}"
            if (!prefs.getBoolean(dayKey, false)) {
                prefs.edit().putBoolean(dayKey, true).apply()
                postNotification(
                    7102,
                    "Geomagnetic Aurora Alert",
                    spaceWeather.statusMessage
                )
            }
        }

        if (settings.cosmosNotifyPristineSky && conditions != null && conditions.score >= 85) {
            val dayKey = "notif_pristine_${Instant.now().atZone(ZoneOffset.UTC).toLocalDate()}"
            if (!prefs.getBoolean(dayKey, false)) {
                prefs.edit().putBoolean(dayKey, true).apply()
                postNotification(
                    7103,
                    "Pristine Night Sky (${conditions.score}/100)",
                    conditions.narrativeAdvice
                )
            }
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Cosmos & Night Sky Alerts",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Opt-in alerts for bright ISS passes, geomagnetic aurora storms, and pristine clear skies."
            }
            mgr.createNotificationChannel(channel)
        }
    }

    private fun postNotification(id: Int, title: String, body: String) {
        runCatching {
            val notif = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true)
                .build()
            NotificationManagerCompat.from(context).notify(id, notif)
        }
    }

    private fun currentAuthenticatedUserId(): String? {
        val state = runCatching { DailyApp.instance.authRepository.sessionState.value }.getOrNull()
        val uid = (state as? AuthSessionState.Authenticated)?.profile?.id
        return uid?.takeIf { it.isNotBlank() && it != "guest" }
    }

    private fun httpGet(urlString: String, timeoutMs: Int): String? {
        return runCatching {
            val conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = timeoutMs
                readTimeout = timeoutMs
                setRequestProperty("Accept", "application/json")
                setRequestProperty("User-Agent", "DailyObservatory/2.0 (Android)")
            }
            try {
                if (conn.responseCode in 200..299) {
                    conn.inputStream.bufferedReader().use { it.readText() }
                } else {
                    null
                }
            } finally {
                conn.disconnect()
            }
        }.getOrNull()
    }
}
