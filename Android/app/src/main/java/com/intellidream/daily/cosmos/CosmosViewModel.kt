package com.intellidream.daily.cosmos

import android.Manifest
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.SensorManager
import android.location.LocationManager
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.intellidream.daily.DailyApp
import com.intellidream.daily.model.ApodResponse
import com.intellidream.daily.model.AstronomyService
import com.intellidream.daily.model.BodyRiseTransitSet
import com.intellidream.daily.model.CelestialBody
import com.intellidream.daily.model.CelestialCoordinates
import com.intellidream.daily.model.CelesTrakOmmRecord
import com.intellidream.daily.model.CircadianSkyContext
import com.intellidream.daily.model.CosmosAsterism
import com.intellidream.daily.model.CosmosBookmark
import com.intellidream.daily.model.CosmosConstellation
import com.intellidream.daily.model.CosmosConstellationBorderArc
import com.intellidream.daily.model.CosmosDeepSkyObject
import com.intellidream.daily.model.CosmosObservation
import com.intellidream.daily.model.CosmosStar
import com.intellidream.daily.model.JupiterMoonsState
import com.intellidream.daily.model.LiveSatellitePosition
import com.intellidream.daily.model.MeteorShower
import com.intellidream.daily.model.MilkyWayContourLayer
import com.intellidream.daily.model.MoonPhaseInfo
import com.intellidream.daily.model.PackedStarCatalog
import com.intellidream.daily.model.SatellitePass
import com.intellidream.daily.model.SkyProjectionMatrix
import com.intellidream.daily.model.SpaceWeatherReport
import com.intellidream.daily.model.StargazingConditions
import com.intellidream.daily.model.SunTimes
import com.intellidream.daily.model.TelemetryProvenance
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId

enum class CosmosZoomPreset(val label: String, val fovDegrees: Double) {
    NAKED_EYE("120° Wide", 115.0),
    STANDARD("60° Eye", 60.0),
    BINOCULARS("8° 7x50", 8.0),
    TELESCOPE("2° Scope", 2.0)
}

/**
 * High-frequency 120Hz camera state isolated from slow 1Hz ephemeris recompositions.
 */
data class CosmosCameraState(
    val azimuthDegrees: Double = 180.0,
    val altitudeDegrees: Double = 42.0,
    val rollDegrees: Double = 0.0,
    val fovDegrees: Double = 65.0,
    val isArGyroActive: Boolean = false,
    val sensorAccuracy: Int = SensorManager.SENSOR_STATUS_ACCURACY_HIGH,
    val isRelativeGyroFallback: Boolean = false,
    val needsCompassCalibration: Boolean = false,
    val hingeAngleDegrees: Float? = null
)

data class TargetLiveMetrics(
    val azimuthDegrees: Double,
    val altitudeDegrees: Double,
    val raHours: Double,
    val decDegrees: Double,
    val magnitude: Double?,
    val distanceLabel: String?,
    val phasePercent: Int?,
    val angularSizeLabel: String?,
    val riseTransitSet: BodyRiseTransitSet?
)

data class CosmosViewState(
    val observerLatitude: Double = 44.4323,
    val observerLongitude: Double = 26.1063,
    val observerElevationMeters: Double = 85.0,
    val locationName: String = "Local Observatory",
    val effectiveTimestamp: Long = System.currentTimeMillis(),
    val isLiveTime: Boolean = true,
    val timeOffsetMinutes: Double = 0.0,
    val playbackSpeedMultiplier: Int = 0, // 0 = paused/live, 1, 60, 600
    val isNightVisionMode: Boolean = false,
    val isFullBleedFoldable: Boolean = false,
    val showAtmosphere: Boolean = true,
    val showConstellationLines: Boolean = true,
    val showConstellationBorders: Boolean = false,
    val showAsterisms: Boolean = false,
    val showAltAzGrid: Boolean = false,
    val showRaDecGrid: Boolean = false,
    val showEcliptic: Boolean = true,
    val showMilkyWay: Boolean = true,
    val showDeepSkyObjects: Boolean = true,
    val showMeteorRadiants: Boolean = true,
    val showSatellites: Boolean = true,
    val conditions: StargazingConditions? = null,
    val sunTimes: SunTimes? = null,
    val sunAltitudeDegrees: Double = -25.0,
    val circadianContext: CircadianSkyContext? = null,
    val moon: MoonPhaseInfo? = null,
    val jupiterMoons: JupiterMoonsState? = null,
    val saturnRingTiltDegrees: Double = 4.0,
    val visiblePlanets: List<Pair<CelestialBody, CelestialCoordinates>> = emptyList(),
    val allBodies: List<Pair<CelestialBody, CelestialCoordinates>> = emptyList(),
    val allPlanets: List<Pair<CelestialBody, CelestialCoordinates>> = emptyList(),
    val weatherOverlay: CosmosWeatherOverlay? = null,
    val spaceWeather: SpaceWeatherReport = SpaceWeatherReport(),
    val apod: ApodResponse? = null,
    val apodProvenance: TelemetryProvenance = TelemetryProvenance.unavailable(),
    val issLivePosition: LiveSatellitePosition? = null,
    val issPasses: List<SatellitePass> = emptyList(),
    val issProvenance: TelemetryProvenance = TelemetryProvenance.unavailable(),
    val selectedTarget: CosmosSearchResult? = null,
    val selectedTargetMetrics: TargetLiveMetrics? = null,
    val bookmarks: List<CosmosBookmark> = emptyList(),
    val observations: List<CosmosObservation> = emptyList(),
    val statusBannerMessage: String? = null,
    val searchQuery: String = "",
    val searchResults: List<CosmosSearchResult> = emptyList(),
    val isCatalogLoaded: Boolean = false,
    val packedStars: PackedStarCatalog = PackedStarCatalog.EMPTY,
    val stars: List<CosmosStar> = emptyList(),
    val constellations: List<CosmosConstellation> = emptyList(),
    val constellationBorders: List<CosmosConstellationBorderArc> = emptyList(),
    val asterisms: List<CosmosAsterism> = emptyList(),
    val dsos: List<CosmosDeepSkyObject> = emptyList(),
    val activeMeteorShowers: List<MeteorShower> = emptyList(),
    val allMeteorShowers: List<MeteorShower> = emptyList(),
    val milkyWayLayers: List<MilkyWayContourLayer> = emptyList()
)

class CosmosViewModel(application: Application) : AndroidViewModel(application) {
    val catalogRepository = CosmosCatalogRepository(application)
    val liveRepository = CosmosLiveRepository(application)
    val motionManager = CosmosMotionManager(application)

    private val _cameraState = MutableStateFlow(CosmosCameraState())
    val cameraState: StateFlow<CosmosCameraState> = _cameraState.asStateFlow()

    private val _state = MutableStateFlow(CosmosViewState())
    val state: StateFlow<CosmosViewState> = _state.asStateFlow()

    private var cachedIssOmm: CelesTrakOmmRecord? = null
    private var tickerJob: Job? = null
    private var isViewActive: Boolean = false

    init {
        viewModelScope.launch {
            resolveObserverCoordinates()
            catalogRepository.ensureLoaded()
            val loadedBookmarks = liveRepository.loadBookmarks()
            val loadedObservations = liveRepository.loadObservations()
            _state.value = _state.value.copy(
                isCatalogLoaded = true,
                packedStars = catalogRepository.packedStars,
                stars = catalogRepository.stars,
                constellations = catalogRepository.constellations,
                constellationBorders = catalogRepository.constellationBorders,
                asterisms = catalogRepository.asterisms,
                dsos = catalogRepository.deepSkyObjects,
                allMeteorShowers = catalogRepository.meteorShowers,
                milkyWayLayers = catalogRepository.milkyWayLayers,
                bookmarks = loadedBookmarks,
                observations = loadedObservations
            )
            refreshCosmosCalculations()
            refreshLiveTelemetry()
        }

        // Observe WeatherRepository location updates automatically
        viewModelScope.launch {
            DailyApp.instance.weatherRepository.currentWeather.collect { w ->
                val coord = w?.coord
                if (coord != null) {
                    val city = DailyApp.instance.weatherRepository.currentLocationName.value
                        .takeIf { it.isNotBlank() && it != "Detecting..." }
                        ?: w.name.ifBlank { "Local Observatory" }
                    updateLocationInternal(coord.lat, coord.lon, city)
                }
            }
        }

        // Collect 120Hz validated optical-axis gyro/hinge stream into isolated cameraState
        viewModelScope.launch {
            motionManager.attitude.collect { att ->
                val cur = _cameraState.value
                if (cur.isArGyroActive) {
                    _cameraState.value = cur.copy(
                        azimuthDegrees = att.azimuthDegrees,
                        altitudeDegrees = att.altitudeDegrees,
                        rollDegrees = att.rollDegrees,
                        sensorAccuracy = att.accuracy,
                        isRelativeGyroFallback = att.isRelativeGyroFallback,
                        needsCompassCalibration = att.needsCompassCalibration,
                        hingeAngleDegrees = att.hingeAngleDegrees
                    )
                } else if (att.hingeAngleDegrees != cur.hingeAngleDegrees) {
                    _cameraState.value = cur.copy(hingeAngleDegrees = att.hingeAngleDegrees)
                }
            }
        }
    }

    // MARK: - Strict Lifecycle Management (Zero Background Drain)

    fun onObservatoryVisible() {
        isViewActive = true
        motionManager.startHingeMonitoringOnly()
        if (_cameraState.value.isArGyroActive) {
            motionManager.startTracking()
        }
        startLiveTicker()
    }

    fun onObservatoryHidden() {
        isViewActive = false
        tickerJob?.cancel()
        tickerJob = null
        motionManager.stopTracking()
    }

    private fun startLiveTicker() {
        tickerJob?.cancel()
        tickerJob = viewModelScope.launch {
            while (isActive && isViewActive) {
                val s = _state.value
                when {
                    s.playbackSpeedMultiplier != 0 -> {
                        val nextMs = s.effectiveTimestamp + (s.playbackSpeedMultiplier * 100L)
                        val offsetMin = (nextMs - System.currentTimeMillis()) / 60_000.0
                        _state.value = s.copy(
                            isLiveTime = false,
                            effectiveTimestamp = nextMs,
                            timeOffsetMinutes = offsetMin
                        )
                        refreshCosmosCalculations()
                        delay(100L)
                    }
                    s.isLiveTime -> {
                        _state.value = s.copy(
                            effectiveTimestamp = System.currentTimeMillis(),
                            timeOffsetMinutes = 0.0
                        )
                        refreshCosmosCalculations()
                        delay(1000L)
                    }
                    else -> {
                        delay(500L)
                    }
                }
            }
        }
    }

    // MARK: - Location Resolution (Android GPS -> WeatherRepository -> Cached Weather)

    private suspend fun resolveObserverCoordinates() {
        val ctx = getApplication<Application>()
        val hasFine = ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val hasCoarse = ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (hasFine || hasCoarse) {
            val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            val loc = runCatching {
                lm?.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                    ?: lm?.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            }.getOrNull()
            if (loc != null) {
                val city = DailyApp.instance.weatherRepository.currentLocationName.value
                    .takeIf { it.isNotBlank() && it != "Detecting..." }
                    ?: "GPS Observatory"
                updateLocationInternal(loc.latitude, loc.longitude, city, loc.altitude.takeIf { it != 0.0 } ?: 50.0)
                return
            }
        }

        val currentWeather = DailyApp.instance.weatherRepository.currentWeather.value
        if (currentWeather?.coord != null) {
            val city = DailyApp.instance.weatherRepository.currentLocationName.value
                .takeIf { it.isNotBlank() && it != "Detecting..." }
                ?: currentWeather.name.ifBlank { "Local Observatory" }
            updateLocationInternal(currentWeather.coord!!.lat, currentWeather.coord!!.lon, city)
            return
        }

        val cached = DailyApp.instance.weatherCacheRepository.cachedWeather.firstOrNull()
        if (cached?.lat != null && cached.lon != null) {
            updateLocationInternal(cached.lat!!, cached.lon!!, cached.cityName ?: "Cached Observatory")
        }
    }

    private fun updateLocationInternal(lat: Double, lon: Double, name: String, elev: Double = 85.0) {
        motionManager.updateObserverLocation(lat, lon, elev)
        val cur = _state.value
        if (kotlin.math.abs(cur.observerLatitude - lat) > 0.001 ||
            kotlin.math.abs(cur.observerLongitude - lon) > 0.001 ||
            cur.locationName != name
        ) {
            _state.value = cur.copy(
                observerLatitude = lat,
                observerLongitude = lon,
                observerElevationMeters = elev,
                locationName = name
            )
            if (cur.isCatalogLoaded) {
                refreshCosmosCalculations()
            }
        }
    }

    fun setObserverLocation(lat: Double, lon: Double, name: String = "Manual Site") {
        updateLocationInternal(lat, lon, name)
        refreshLiveTelemetry()
    }

    // MARK: - Live Network Telemetry

    fun refreshLiveTelemetry() {
        viewModelScope.launch {
            val s = _state.value
            val settings = DailyApp.instance.settingsRepository.getLatest()
            val bundle = liveRepository.fetchLiveBundle(
                latitude = s.observerLatitude,
                longitude = s.observerLongitude,
                elevationMeters = s.observerElevationMeters,
                settings = settings
            )
            cachedIssOmm = bundle.issOmm
            _state.value = _state.value.copy(
                weatherOverlay = bundle.weatherOverlay,
                spaceWeather = bundle.spaceWeather,
                apod = bundle.apod,
                apodProvenance = bundle.apodProvenance,
                issLivePosition = bundle.issLivePosition,
                issPasses = bundle.issPasses,
                issProvenance = bundle.issProvenance
            )
            refreshCosmosCalculations()
            liveRepository.evaluateOptInNotifications(
                settings = settings,
                conditions = _state.value.conditions,
                spaceWeather = bundle.spaceWeather,
                nextIssPass = bundle.issPasses.firstOrNull()
            )
        }
    }

    // MARK: - Camera, Zoom, Layers & Time Machine Controls

    fun toggleArGyro() {
        if (!motionManager.hasSensorHardware) {
            postStatusBanner("Orientation sensor unavailable on this device.")
            return
        }
        val next = !_cameraState.value.isArGyroActive
        if (next) {
            motionManager.updateObserverLocation(
                _state.value.observerLatitude,
                _state.value.observerLongitude,
                _state.value.observerElevationMeters
            )
            motionManager.startTracking()
            _cameraState.value = _cameraState.value.copy(
                isArGyroActive = true,
                isRelativeGyroFallback = motionManager.isUsingRelativeFallback
            )
        } else {
            motionManager.stopTracking()
            if (isViewActive) motionManager.startHingeMonitoringOnly()
            _cameraState.value = _cameraState.value.copy(
                isArGyroActive = false,
                rollDegrees = 0.0
            )
        }
    }

    fun toggleNightVision() {
        _state.value = _state.value.copy(isNightVisionMode = !_state.value.isNightVisionMode)
    }

    fun toggleFullBleedFoldable() {
        _state.value = _state.value.copy(isFullBleedFoldable = !_state.value.isFullBleedFoldable)
    }

    fun toggleAtmosphere() {
        _state.value = _state.value.copy(showAtmosphere = !_state.value.showAtmosphere)
    }

    fun toggleConstellationLines() {
        _state.value = _state.value.copy(showConstellationLines = !_state.value.showConstellationLines)
    }

    fun toggleConstellationBorders() {
        _state.value = _state.value.copy(showConstellationBorders = !_state.value.showConstellationBorders)
    }

    fun toggleAsterisms() {
        _state.value = _state.value.copy(showAsterisms = !_state.value.showAsterisms)
    }

    fun toggleAltAzGrid() {
        _state.value = _state.value.copy(showAltAzGrid = !_state.value.showAltAzGrid)
    }

    fun toggleRaDecGrid() {
        _state.value = _state.value.copy(showRaDecGrid = !_state.value.showRaDecGrid)
    }

    fun toggleDeepSkyObjects() {
        _state.value = _state.value.copy(showDeepSkyObjects = !_state.value.showDeepSkyObjects)
    }

    fun toggleMilkyWay() {
        _state.value = _state.value.copy(showMilkyWay = !_state.value.showMilkyWay)
    }

    fun setCameraAttitude(azimuth: Double, altitude: Double) {
        val cur = _cameraState.value
        if (cur.isArGyroActive) {
            motionManager.stopTracking()
            if (isViewActive) motionManager.startHingeMonitoringOnly()
        }
        val clampedAlt = altitude.coerceIn(-45.0, 90.0)
        val normalizedAz = (azimuth % 360.0 + 360.0) % 360.0
        _cameraState.value = cur.copy(
            isArGyroActive = false,
            azimuthDegrees = normalizedAz,
            altitudeDegrees = clampedAlt,
            rollDegrees = 0.0
        )
    }

    fun setFov(fov: Double) {
        _cameraState.value = _cameraState.value.copy(fovDegrees = fov.coerceIn(0.5, 130.0))
    }

    fun applyZoomPreset(preset: CosmosZoomPreset) {
        setFov(preset.fovDegrees)
    }

    fun setTimeOffsetMinutes(offsetMinutes: Double) {
        val targetMs = System.currentTimeMillis() + (offsetMinutes * 60_000.0).toLong()
        _state.value = _state.value.copy(
            isLiveTime = false,
            playbackSpeedMultiplier = 0,
            timeOffsetMinutes = offsetMinutes,
            effectiveTimestamp = targetMs
        )
        refreshCosmosCalculations()
    }

    fun shiftTime(deltaHours: Double) {
        val nextOffset = _state.value.timeOffsetMinutes + (deltaHours * 60.0)
        setTimeOffsetMinutes(nextOffset)
    }

    fun jumpToTimestamp(epochMillis: Long) {
        val minEpoch = -2_208_988_800_000L // 1900-01-01T00:00:00Z
        val maxEpoch = 4_102_444_800_000L  // 2100-01-01T00:00:00Z
        val clamped = epochMillis.coerceIn(minEpoch, maxEpoch)
        val offsetMin = (clamped - System.currentTimeMillis()) / 60_000.0
        _state.value = _state.value.copy(
            isLiveTime = false,
            playbackSpeedMultiplier = 0,
            timeOffsetMinutes = offsetMin,
            effectiveTimestamp = clamped
        )
        refreshCosmosCalculations()
    }

    fun setPlaybackSpeed(multiplier: Int) {
        val current = _state.value.playbackSpeedMultiplier
        val next = if (current == multiplier) 0 else multiplier
        _state.value = _state.value.copy(
            isLiveTime = false,
            playbackSpeedMultiplier = next
        )
    }

    fun resetToLiveTime() {
        _state.value = _state.value.copy(
            isLiveTime = true,
            playbackSpeedMultiplier = 0,
            timeOffsetMinutes = 0.0,
            effectiveTimestamp = System.currentTimeMillis()
        )
        refreshCosmosCalculations()
    }

    // MARK: - Target Selection, Centering, Bookmarks & #sky Observation Logging

    fun selectTarget(target: CosmosSearchResult?, centerCamera: Boolean = true) {
        val metrics = target?.let { computeTargetMetrics(it, _state.value) }
        _state.value = _state.value.copy(
            selectedTarget = target,
            selectedTargetMetrics = metrics
        )
        if (target != null && centerCamera && !_cameraState.value.isArGyroActive && metrics != null) {
            setCameraAttitude(metrics.azimuthDegrees, metrics.altitudeDegrees.coerceAtLeast(-15.0))
        }
    }

    fun centerOnSelectedTarget() {
        val metrics = _state.value.selectedTargetMetrics ?: return
        setCameraAttitude(metrics.azimuthDegrees, metrics.altitudeDegrees.coerceAtLeast(-15.0))
    }

    fun isBookmarked(target: CosmosSearchResult): Boolean {
        return _state.value.bookmarks.any { it.objectId == target.objectId }
    }

    fun toggleBookmark(target: CosmosSearchResult) {
        viewModelScope.launch {
            val metrics = computeTargetMetrics(target, _state.value)
            val updated = liveRepository.toggleBookmark(
                objectId = target.objectId,
                objectName = target.title,
                category = target.categoryKey,
                raHours = metrics.raHours,
                decDeg = metrics.decDegrees,
                magnitude = metrics.magnitude
            )
            val added = updated.any { it.objectId == target.objectId }
            _state.value = _state.value.copy(bookmarks = updated)
            postStatusBanner(if (added) "Saved ${target.title} to Sky Bookmarks." else "Removed ${target.title} from Sky Bookmarks.")
        }
    }

    fun logSightingToTagdos(target: CosmosSearchResult, optics: String = "Naked Eye", notes: String = "") {
        viewModelScope.launch {
            val s = _state.value
            val metrics = computeTargetMetrics(target, s)
            val obs = liveRepository.logObservationAndMirrorToTagdos(
                objectId = target.objectId,
                objectName = target.title,
                category = target.categoryKey,
                latitude = s.observerLatitude,
                longitude = s.observerLongitude,
                locationName = s.locationName,
                azimuthDeg = metrics.azimuthDegrees,
                altitudeDeg = metrics.altitudeDegrees,
                bortleClass = s.conditions?.bortleClass ?: 5,
                stargazingScore = s.conditions?.score ?: 60,
                optics = optics,
                notes = notes
            )
            _state.value = _state.value.copy(observations = listOf(obs) + _state.value.observations)
            postStatusBanner("Logged sighting & saved #sky Quick Note in TagDoS!")
        }
    }

    private fun postStatusBanner(msg: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(statusBannerMessage = msg)
            delay(3200L)
            if (_state.value.statusBannerMessage == msg) {
                _state.value = _state.value.copy(statusBannerMessage = null)
            }
        }
    }

    fun onSearchQueryChanged(q: String) {
        val results = catalogRepository.search(q)
        _state.value = _state.value.copy(searchQuery = q, searchResults = results)
    }

    fun makeProjectionMatrix(viewportWidth: Double, viewportHeight: Double): SkyProjectionMatrix {
        val s = _state.value
        val c = _cameraState.value
        return AstronomyService.makeProjectionMatrix(
            observerLatitudeDegrees = s.observerLatitude,
            observerLongitudeDegrees = s.observerLongitude,
            millis = s.effectiveTimestamp,
            cameraAzimuthDegrees = c.azimuthDegrees,
            cameraAltitudeDegrees = c.altitudeDegrees,
            cameraRollDegrees = c.rollDegrees,
            fovDegrees = c.fovDegrees,
            viewportWidth = viewportWidth,
            viewportHeight = viewportHeight
        )
    }

    // MARK: - Ephemeris & Stargazing Intelligence Refresh

    fun refreshCosmosCalculations() {
        val s = _state.value
        val time = AstronomyService.makeTime(s.effectiveTimestamp)
        val lat = s.observerLatitude
        val lon = s.observerLongitude
        val elev = s.observerElevationMeters

        val moon = AstronomyService.moonPhase(time, lat, lon)
        val sunTimes = AstronomyService.sunTimes(lat, lon, s.effectiveTimestamp)
        val circadian = AstronomyService.circadianLunarContext(lat, lon, s.effectiveTimestamp)
        val jupMoons = AstronomyService.jupiterMoons(time, lat, lon)
        val satTilt = AstronomyService.saturnRingTilt(time)

        val bortle = if (s.isCatalogLoaded) catalogRepository.bortleClass(lat, lon) else 5
        val wx = s.weatherOverlay
        val fallbackWeather = DailyApp.instance.weatherRepository.currentWeather.value
        val fallbackClouds = fallbackWeather?.clouds?.all
        val tempC = wx?.temperatureCelsius ?: fallbackWeather?.main?.temp
        val dewDepression = if (tempC != null && wx?.dewPointCelsius != null) {
            tempC - wx.dewPointCelsius
        } else null

        val conditions = AstronomyService.evaluateStargazingConditions(
            latitude = lat,
            longitude = lon,
            millis = s.effectiveTimestamp,
            cloudCoverTotal = wx?.cloudTotalPercent ?: fallbackClouds,
            cloudCoverLow = wx?.cloudLowPercent,
            cloudCoverMid = wx?.cloudMidPercent,
            cloudCoverHigh = wx?.cloudHighPercent,
            bortleClass = bortle,
            seeingArcseconds = wx?.seeingArcseconds,
            transparencyLabel = wx?.transparencyLabel,
            dewPointDepression = dewDepression,
            provenance = wx?.provenance ?: if (fallbackClouds != null) {
                TelemetryProvenance.live("OpenWeather Total Cloud")
            } else {
                TelemetryProvenance.offlineCalculated("Offline Ephemeris + Bortle Grid")
            }
        )

        // Compute Sun + Moon + all 7 Major Planets
        val allBodies = CelestialBody.entries.map { body ->
            Pair(body, AstronomyService.coordinates(body, lat, lon, elev, time))
        }
        val sunAlt = allBodies.firstOrNull { it.first == CelestialBody.SUN }?.second?.altitudeDegrees ?: -25.0
        val planetCoords = allBodies.filter { it.first != CelestialBody.SUN && it.first != CelestialBody.MOON }
        val visible = planetCoords.filter { it.second.isVisible }

        // Active meteor showers for effective date
        val zdt = Instant.ofEpochMilli(s.effectiveTimestamp).atZone(ZoneId.systemDefault())
        val activeShowers = s.allMeteorShowers.filter {
            it.isActiveOn(zdt.monthValue, zdt.dayOfMonth)
        }

        // Update live ISS SGP4 position at effectiveTimestamp
        val issPos = liveRepository.computeLiveIssPosition(
            omm = cachedIssOmm,
            timestampMillis = s.effectiveTimestamp,
            latitude = lat,
            longitude = lon,
            elevationMeters = elev
        ) ?: s.issLivePosition

        val refreshedState = s.copy(
            conditions = conditions,
            sunTimes = sunTimes,
            sunAltitudeDegrees = sunAlt,
            circadianContext = circadian,
            moon = moon,
            jupiterMoons = jupMoons,
            saturnRingTiltDegrees = satTilt,
            allBodies = allBodies,
            allPlanets = planetCoords,
            visiblePlanets = visible,
            activeMeteorShowers = activeShowers,
            issLivePosition = issPos
        )
        val refreshedTargetMetrics = refreshedState.selectedTarget?.let { computeTargetMetrics(it, refreshedState) }
        _state.value = refreshedState.copy(selectedTargetMetrics = refreshedTargetMetrics)
    }

    private fun computeTargetMetrics(target: CosmosSearchResult, s: CosmosViewState): TargetLiveMetrics {
        val lat = s.observerLatitude
        val lon = s.observerLongitude
        val elev = s.observerElevationMeters
        val time = AstronomyService.makeTime(s.effectiveTimestamp)

        return when (target) {
            is CosmosSearchResult.Planet -> {
                val c = s.allBodies.firstOrNull { it.first == target.body }?.second
                    ?: AstronomyService.coordinates(target.body, lat, lon, elev, time)
                val rts = AstronomyService.riseTransitSet(target.body, lat, lon, s.effectiveTimestamp)
                val distLabel = if (target.body == CelestialBody.MOON) {
                    val km = s.moon?.topocentricDistanceKm ?: s.moon?.distanceKm ?: (c.distanceAU * 149_597_870.7)
                    "${"%,.0f".format(km)} km"
                } else {
                    "${"%.3f".format(c.distanceAU)} AU"
                }
                val phasePct = (c.illuminatedFraction * 100.0).toInt()
                val angSize = "${"%.1f".format(c.angularDiameterArcsec)}\""
                TargetLiveMetrics(
                    azimuthDegrees = c.azimuthDegrees,
                    altitudeDegrees = c.altitudeDegrees,
                    raHours = c.rightAscensionHours,
                    decDegrees = c.declinationDegrees,
                    magnitude = c.visualMagnitude,
                    distanceLabel = distLabel,
                    phasePercent = phasePct,
                    angularSizeLabel = angSize,
                    riseTransitSet = rts
                )
            }
            is CosmosSearchResult.Star -> {
                val hor = AstronomyService.starHorizontalCoordinates(
                    raHours = target.star.raHours,
                    decDegrees = target.star.decDegrees,
                    latitude = lat,
                    longitude = lon,
                    elevationMeters = elev,
                    time = time
                )
                val rts = AstronomyService.riseTransitSetStar(
                    raHours = target.star.raHours,
                    decDegrees = target.star.decDegrees,
                    latitude = lat,
                    longitude = lon,
                    millis = s.effectiveTimestamp
                )
                TargetLiveMetrics(
                    azimuthDegrees = hor.azimuthDegrees,
                    altitudeDegrees = hor.altitudeDegrees,
                    raHours = target.star.raHours,
                    decDegrees = target.star.decDegrees,
                    magnitude = target.star.mag,
                    distanceLabel = "HIP ${target.star.hip}",
                    phasePercent = null,
                    angularSizeLabel = "B-V ${"%+.2f".format(target.star.colorIndexBV)}",
                    riseTransitSet = rts
                )
            }
            is CosmosSearchResult.DSO -> {
                val hor = AstronomyService.starHorizontalCoordinates(
                    raHours = target.dso.raHours,
                    decDegrees = target.dso.decDeg,
                    latitude = lat,
                    longitude = lon,
                    elevationMeters = elev,
                    time = time
                )
                val rts = AstronomyService.riseTransitSetStar(
                    raHours = target.dso.raHours,
                    decDegrees = target.dso.decDeg,
                    latitude = lat,
                    longitude = lon,
                    millis = s.effectiveTimestamp
                )
                val distText = target.dso.distanceLy?.let {
                    if (it >= 1_000_000.0) "${"%.2f".format(it / 1_000_000.0)} Mly"
                    else "${"%,.0f".format(it)} ly"
                } ?: (target.dso.ngc ?: target.dso.catalog)
                TargetLiveMetrics(
                    azimuthDegrees = hor.azimuthDegrees,
                    altitudeDegrees = hor.altitudeDegrees,
                    raHours = target.dso.raHours,
                    decDegrees = target.dso.decDeg,
                    magnitude = target.dso.visualMag,
                    distanceLabel = distText,
                    phasePercent = null,
                    angularSizeLabel = "${"%.0f".format(target.dso.majorAxisArcmin)}'×${"%.0f".format(target.dso.minorAxisArcmin)}'",
                    riseTransitSet = rts
                )
            }
            is CosmosSearchResult.Constellation -> {
                val hor = AstronomyService.starHorizontalCoordinates(
                    raHours = target.constellation.centerRaHours,
                    decDegrees = target.constellation.centerDecDeg,
                    latitude = lat,
                    longitude = lon,
                    elevationMeters = elev,
                    time = time
                )
                TargetLiveMetrics(
                    azimuthDegrees = hor.azimuthDegrees,
                    altitudeDegrees = hor.altitudeDegrees,
                    raHours = target.constellation.centerRaHours,
                    decDegrees = target.constellation.centerDecDeg,
                    magnitude = null,
                    distanceLabel = "${target.constellation.segments.size} segments",
                    phasePercent = null,
                    angularSizeLabel = target.constellation.genitive,
                    riseTransitSet = null
                )
            }
            is CosmosSearchResult.Asterism -> {
                val hor = AstronomyService.starHorizontalCoordinates(
                    raHours = target.asterism.centerRaHours,
                    decDegrees = target.asterism.centerDecDeg,
                    latitude = lat,
                    longitude = lon,
                    elevationMeters = elev,
                    time = time
                )
                TargetLiveMetrics(
                    azimuthDegrees = hor.azimuthDegrees,
                    altitudeDegrees = hor.altitudeDegrees,
                    raHours = target.asterism.centerRaHours,
                    decDegrees = target.asterism.centerDecDeg,
                    magnitude = null,
                    distanceLabel = target.asterism.season,
                    phasePercent = null,
                    angularSizeLabel = "${target.asterism.segments.size} star links",
                    riseTransitSet = null
                )
            }
            is CosmosSearchResult.Shower -> {
                val hor = AstronomyService.starHorizontalCoordinates(
                    raHours = target.shower.radiantRaHours,
                    decDegrees = target.shower.radiantDecDeg,
                    latitude = lat,
                    longitude = lon,
                    elevationMeters = elev,
                    time = time
                )
                TargetLiveMetrics(
                    azimuthDegrees = hor.azimuthDegrees,
                    altitudeDegrees = hor.altitudeDegrees,
                    raHours = target.shower.radiantRaHours,
                    decDegrees = target.shower.radiantDecDeg,
                    magnitude = null,
                    distanceLabel = "ZHR ${target.shower.zhr}/hr",
                    phasePercent = null,
                    angularSizeLabel = "${target.shower.velocityKmS.toInt()} km/s",
                    riseTransitSet = null
                )
            }
            CosmosSearchResult.IssStation -> {
                val pos = s.issLivePosition
                TargetLiveMetrics(
                    azimuthDegrees = pos?.azimuthDegrees ?: 0.0,
                    altitudeDegrees = pos?.altitudeDegrees ?: -10.0,
                    raHours = 0.0,
                    decDegrees = 0.0,
                    magnitude = pos?.estimatedMagnitude,
                    distanceLabel = pos?.let { "${"%,.0f".format(it.rangeKm)} km (${it.orbitalAltitudeKm.toInt()} km LEO)" } ?: "SGP4 LEO",
                    phasePercent = null,
                    angularSizeLabel = if (pos?.isSunlit == true) "Sunlit" else "Earth Shadow",
                    riseTransitSet = null
                )
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        tickerJob?.cancel()
        motionManager.stopTracking()
    }
}
