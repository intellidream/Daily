package com.intellidream.daily.cosmos

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.intellidream.daily.DailyApp
import com.intellidream.daily.model.AstronomyService
import com.intellidream.daily.model.CelestialBody
import com.intellidream.daily.model.CelestialCoordinates
import com.intellidream.daily.model.CosmosConstellation
import com.intellidream.daily.model.CosmosDeepSkyObject
import com.intellidream.daily.model.CosmosStar
import com.intellidream.daily.model.MoonPhaseInfo
import com.intellidream.daily.model.StargazingConditions
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class CosmosViewState(
    val observerLatitude: Double = 44.4323,
    val observerLongitude: Double = 26.1063,
    val effectiveTimestamp: Long = System.currentTimeMillis(),
    val isLiveTime: Boolean = true,
    val timeOffsetMinutes: Long = 0L,
    val cameraAzimuth: Double = 180.0,
    val cameraAltitude: Double = 45.0,
    val cameraRoll: Double = 0.0,
    val fovDegrees: Double = 60.0,
    val isArGyroActive: Boolean = false,
    val isNightVisionMode: Boolean = false,
    val conditions: StargazingConditions? = null,
    val moon: MoonPhaseInfo? = null,
    val visiblePlanets: List<Pair<CelestialBody, CelestialCoordinates>> = emptyList(),
    val allPlanets: List<Pair<CelestialBody, CelestialCoordinates>> = emptyList(),
    val selectedTarget: CosmosSearchResult? = null,
    val searchQuery: String = "",
    val searchResults: List<CosmosSearchResult> = emptyList(),
    val isCatalogLoaded: Boolean = false,
    val stars: List<CosmosStar> = emptyList(),
    val constellations: List<CosmosConstellation> = emptyList(),
    val dsos: List<CosmosDeepSkyObject> = emptyList()
)

class CosmosViewModel(application: Application) : AndroidViewModel(application) {
    val catalogRepository = CosmosCatalogRepository(application)
    val motionManager = CosmosMotionManager(application)

    private val _state = MutableStateFlow(CosmosViewState())
    val state: StateFlow<CosmosViewState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            catalogRepository.ensureLoaded()
            _state.value = _state.value.copy(
                isCatalogLoaded = true,
                stars = catalogRepository.stars,
                constellations = catalogRepository.constellations,
                dsos = catalogRepository.deepSkyObjects
            )
            refreshCosmosCalculations()
        }

        // Listen for sensor attitude updates if AR gyro is active
        viewModelScope.launch {
            motionManager.attitude.collect { att ->
                if (_state.value.isArGyroActive) {
                    _state.value = _state.value.copy(
                        cameraAzimuth = att.azimuthDegrees,
                        cameraAltitude = att.altitudeDegrees,
                        cameraRoll = att.rollDegrees
                    )
                }
            }
        }
    }

    fun setObserverLocation(lat: Double, lon: Double) {
        _state.value = _state.value.copy(observerLatitude = lat, observerLongitude = lon)
        refreshCosmosCalculations()
    }

    fun toggleArGyro() {
        val next = !_state.value.isArGyroActive
        _state.value = _state.value.copy(isArGyroActive = next)
        if (next) {
            motionManager.startTracking()
        } else {
            motionManager.stopTracking()
        }
    }

    fun toggleNightVision() {
        _state.value = _state.value.copy(isNightVisionMode = !_state.value.isNightVisionMode)
    }

    fun setCameraAttitude(azimuth: Double, altitude: Double) {
        if (_state.value.isArGyroActive) {
            // Disengage gyro on manual drag
            motionManager.stopTracking()
            _state.value = _state.value.copy(isArGyroActive = false)
        }
        val clampedAlt = altitude.coerceIn(0.0, 90.0)
        val normalizedAz = (azimuth % 360.0 + 360.0) % 360.0
        _state.value = _state.value.copy(cameraAzimuth = normalizedAz, cameraAltitude = clampedAlt)
    }

    fun setFov(fov: Double) {
        _state.value = _state.value.copy(fovDegrees = fov.coerceIn(25.0, 110.0))
    }

    fun shiftTime(deltaHours: Double) {
        val offsetDelta = (deltaHours * 60).toLong()
        val newOffset = _state.value.timeOffsetMinutes + offsetDelta
        val newTime = System.currentTimeMillis() + (newOffset * 60 * 1000)
        _state.value = _state.value.copy(
            isLiveTime = false,
            timeOffsetMinutes = newOffset,
            effectiveTimestamp = newTime
        )
        refreshCosmosCalculations()
    }

    fun resetToLiveTime() {
        _state.value = _state.value.copy(
            isLiveTime = true,
            timeOffsetMinutes = 0L,
            effectiveTimestamp = System.currentTimeMillis()
        )
        refreshCosmosCalculations()
    }

    fun selectTarget(target: CosmosSearchResult?) {
        _state.value = _state.value.copy(selectedTarget = target)
        // Point camera towards target if selected
        if (target != null) {
            pointCameraAtTarget(target)
        }
    }

    private fun pointCameraAtTarget(target: CosmosSearchResult) {
        val s = _state.value
        val time = AstronomyService.makeTime(s.effectiveTimestamp)
        when (target) {
            is CosmosSearchResult.Planet -> {
                val coords = AstronomyService.coordinates(target.body, s.observerLatitude, s.observerLongitude, 0.0, time)
                setCameraAttitude(coords.azimuthDegrees, coords.altitudeDegrees)
            }
            is CosmosSearchResult.Star -> {
                val hor = io.github.cosinekitty.astronomy.horizon(
                    time,
                    io.github.cosinekitty.astronomy.Observer(s.observerLatitude, s.observerLongitude, 0.0),
                    target.star.raHours,
                    target.star.decDeg,
                    io.github.cosinekitty.astronomy.Refraction.None
                )
                setCameraAttitude(hor.azimuth, hor.altitude)
            }
            is CosmosSearchResult.Constellation -> {
                val hor = io.github.cosinekitty.astronomy.horizon(
                    time,
                    io.github.cosinekitty.astronomy.Observer(s.observerLatitude, s.observerLongitude, 0.0),
                    target.constellation.raCenterHours,
                    target.constellation.decCenterDeg,
                    io.github.cosinekitty.astronomy.Refraction.None
                )
                setCameraAttitude(hor.azimuth, hor.altitude)
            }
            is CosmosSearchResult.DSO -> {
                val hor = io.github.cosinekitty.astronomy.horizon(
                    time,
                    io.github.cosinekitty.astronomy.Observer(s.observerLatitude, s.observerLongitude, 0.0),
                    target.dso.raHours,
                    target.dso.decDeg,
                    io.github.cosinekitty.astronomy.Refraction.None
                )
                setCameraAttitude(hor.azimuth, hor.altitude)
            }
        }
    }

    fun onSearchQueryChanged(q: String) {
        val results = catalogRepository.search(q)
        _state.value = _state.value.copy(searchQuery = q, searchResults = results)
    }

    fun refreshCosmosCalculations() {
        val s = _state.value
        val time = AstronomyService.makeTime(s.effectiveTimestamp)

        val moon = AstronomyService.moonPhase(time)

        // Evaluate conditions based on weather clouds if available
        val weather = DailyApp.instance.weatherRepository.currentWeather.value
        val clouds = weather?.clouds?.all ?: 15

        val conditions = AstronomyService.evaluateStargazingConditions(
            latitude = s.observerLatitude,
            longitude = s.observerLongitude,
            millis = s.effectiveTimestamp,
            cloudCoverTotal = clouds,
            cloudCoverLow = (clouds * 0.3).toInt(),
            cloudCoverMid = (clouds * 0.4).toInt(),
            cloudCoverHigh = (clouds * 0.3).toInt(),
            bortleClass = 4
        )

        // Calculate all planetary positions
        val planetCoords = CelestialBody.majorPlanets.map { body ->
            Pair(body, AstronomyService.coordinates(body, s.observerLatitude, s.observerLongitude, 0.0, time))
        }

        val visible = planetCoords.filter { it.second.isVisible }

        _state.value = _state.value.copy(
            conditions = conditions,
            moon = moon,
            allPlanets = planetCoords,
            visiblePlanets = visible
        )
    }

    override fun onCleared() {
        super.onCleared()
        motionManager.stopTracking()
    }
}
