package com.intellidream.daily.cosmos

import android.content.Context
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.SystemClock
import android.view.Surface
import android.view.WindowManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

enum class AndroidCosmosSensorMode {
    UNAVAILABLE,
    STANDBY_AUTO_LIFT,
    ACTIVE_LIVE_SKY,
    PAUSED_AFTER_DRAG,
    MANUAL_OFF
}

data class DeviceAttitude(
    val azimuthDegrees: Double = 180.0,
    val altitudeDegrees: Double = 45.0,
    val rollDegrees: Double = 0.0,
    val rightNWZ0: Double = 0.0,
    val rightNWZ1: Double = 1.0,
    val rightNWZ2: Double = 0.0,
    val upNWZ0: Double = 0.0,
    val upNWZ1: Double = 0.0,
    val upNWZ2: Double = 1.0,
    val forwardNWZ0: Double = -1.0,
    val forwardNWZ1: Double = 0.0,
    val forwardNWZ2: Double = 0.0,
    val hasValidBasis: Boolean = false,
    val magneticDeclinationDegrees: Double = 0.0,
    val magneticFieldMicroTesla: Double = 0.0,
    val expectedFieldMicroTesla: Double = 49.0,
    val azimuthOffsetDegrees: Double = 0.0,
    val accuracy: Int = SensorManager.SENSOR_STATUS_ACCURACY_HIGH,
    val isRelativeGyroFallback: Boolean = false,
    val isGyroLockIgnoreMagnet: Boolean = false,
    val isGyroscopeLessHardware: Boolean = false,
    val hasMagneticInterference: Boolean = false,
    val sensorMode: AndroidCosmosSensorMode = AndroidCosmosSensorMode.UNAVAILABLE,
    val hingeAngleDegrees: Float? = null
) {
    val needsCompassCalibration: Boolean
        get() = !isRelativeGyroFallback && !isGyroLockIgnoreMagnet &&
            (accuracy == SensorManager.SENSOR_STATUS_UNRELIABLE ||
                accuracy == SensorManager.SENSOR_STATUS_ACCURACY_LOW ||
                hasMagneticInterference)
}

/**
 * Stellarium-grade 90Hz–120Hz 9-DOF optical-axis sensor fusion manager for Android phones & foldables:
 * - Tier 1: `TYPE_ROTATION_VECTOR` (Gyroscope + Accelerometer + Magnetometer) + NOAA WMM True North declination.
 * - Tier 2: `TYPE_GAME_ROTATION_VECTOR` (Gyroscope + Accelerometer) for Balcony / MagSafe Gyro-Lock mode.
 * - Tier 3: `TYPE_GEOMAGNETIC_ROTATION_VECTOR` or `ACCELEROMETER + MAGNETIC_FIELD` fallback for gyroscope-less hardware.
 * - FOV-adaptive quaternion SLERP stabilization (acts like optical image stabilization in Binocular/Telescope zoom).
 * - Automatic Lift-to-Sky activation (> +15° sustained for >= 250ms) with instant disengage on manual 1-finger drag.
 * - Real-time ambient magnetic flux norm (µT) anomaly detection + 1-tap celestial "Align on Target" calibration.
 */
class CosmosMotionManager(context: Context) : SensorEventListener {
    private val appContext = context.applicationContext
    private val sensorManager = appContext.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
    private val windowManager = appContext.getSystemService(Context.WINDOW_SERVICE) as? WindowManager

    private val primaryRotationSensor: Sensor? = sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
    private val gameRotationSensor: Sensor? = sensorManager?.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
    private val geomagneticRotationSensor: Sensor? = sensorManager?.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR)
    private val accelerometerSensor: Sensor? = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private val magneticFieldSensor: Sensor? = sensorManager?.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
    private val hingeSensor: Sensor? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        sensorManager?.getDefaultSensor(Sensor.TYPE_HINGE_ANGLE)
    } else {
        null
    }

    val hasSensorHardware: Boolean
        get() = primaryRotationSensor != null ||
            gameRotationSensor != null ||
            geomagneticRotationSensor != null ||
            (accelerometerSensor != null && magneticFieldSensor != null)

    val hasHardwareGyroscope: Boolean
        get() = primaryRotationSensor != null || gameRotationSensor != null

    val isUsingRelativeFallbackDefault: Boolean
        get() = primaryRotationSensor == null && gameRotationSensor != null && geomagneticRotationSensor == null

    var onAutoLiftEngaged: (() -> Unit)? = null

    private var currentSensorMode: AndroidCosmosSensorMode =
        if (hasSensorHardware) AndroidCosmosSensorMode.STANDBY_AUTO_LIFT else AndroidCosmosSensorMode.UNAVAILABLE

    private val _attitude = MutableStateFlow(
        DeviceAttitude(
            isRelativeGyroFallback = isUsingRelativeFallbackDefault,
            isGyroscopeLessHardware = hasSensorHardware && !hasHardwareGyroscope,
            sensorMode = currentSensorMode
        )
    )
    val attitude: StateFlow<DeviceAttitude> = _attitude.asStateFlow()

    private val _isTracking = MutableStateFlow(false)
    val isTracking: StateFlow<Boolean> = _isTracking.asStateFlow()

    private var declinationDegrees: Double = 0.0
    private var expectedFieldMicroTesla: Double = 49.0
    private var measuredFieldMicroTesla: Double = 0.0
    private var currentAccuracy: Int = SensorManager.SENSOR_STATUS_ACCURACY_HIGH
    private var magSensorAccuracy: Int = SensorManager.SENSOR_STATUS_ACCURACY_HIGH
    private var currentHingeAngle: Float? = null
    private var activeDisplayRotation: Int? = null
    private var currentFovDegrees: Double = 65.0
    private var isTabletopPosture: Boolean = false

    private var isGyroLockIgnoreMagnet: Boolean = false
    private var gyroAnchorOffsetDegrees: Double = 0.0
    private var azimuthOffsetDegrees: Double = 0.0
    private var lastRawTrueAzimuthDegrees: Double = 180.0
    private var lastValidAzimuthRadians: Double = Math.PI

    // Lift-to-Sky hysteresis (>= +6° unsmoothed optical altitude sustained >= 180ms)
    private var liftAboveThresholdSinceMs: Long = 0L
    private var hasLoweredSinceDragPause: Boolean = true
    private var dragPausedAtMs: Long = 0L

    // Reusable pre-allocated buffers (zero GC pressure at 120Hz)
    private val rawQuat = FloatArray(4) // [w, x, y, z]
    private val smoothedQuat = FloatArray(4)
    private val rawQuatForMatrix = FloatArray(4) // [x, y, z, w]
    private val rawRotationMatrix = FloatArray(9)
    private val rawRemappedMatrix = FloatArray(9)
    private val quatForMatrix = FloatArray(4) // [x, y, z, w]
    private val rotationMatrix = FloatArray(9)
    private val remappedMatrix = FloatArray(9)
    private val gravityBuf = FloatArray(3)
    private val magBuf = FloatArray(3)
    private var hasGravitySample = false
    private var hasMagSample = false
    private var hasInitialQuat = false
    private var activeCompositeSensor: Sensor? = null
    private var usingRawAccelMagFallback = false
    private var sensorsRegistered = false
    private var registeredCompositeType: Int = -1
    private var registeredWithMagMonitor = false

    fun updateObserverLocation(latitude: Double, longitude: Double, elevationMeters: Double = 50.0) {
        val field = GeomagneticField(
            latitude.toFloat(),
            longitude.toFloat(),
            elevationMeters.toFloat(),
            System.currentTimeMillis()
        )
        declinationDegrees = field.declination.toDouble()
        expectedFieldMicroTesla = (field.fieldStrength / 1000.0).coerceIn(22.0, 68.0)
    }

    fun updateDisplayRotation(rotation: Int?) {
        activeDisplayRotation = rotation
    }

    fun updateCurrentFov(fovDegrees: Double) {
        currentFovDegrees = fovDegrees.coerceIn(0.5, 130.0)
    }

    fun updateTabletopPosture(isTabletop: Boolean) {
        isTabletopPosture = isTabletop
    }

    fun beginObservatorySession(autoLiftEnabled: Boolean = true) {
        if (!hasSensorHardware) {
            currentSensorMode = AndroidCosmosSensorMode.UNAVAILABLE
            publishModeOnly()
            return
        }
        liftAboveThresholdSinceMs = 0L
        hasLoweredSinceDragPause = true
        // Every fresh visit to Cosmos starts ready for Auto-Lift unless already actively tracking
        if (currentSensorMode != AndroidCosmosSensorMode.ACTIVE_LIVE_SKY) {
            currentSensorMode = if (autoLiftEnabled) {
                AndroidCosmosSensorMode.STANDBY_AUTO_LIFT
            } else {
                AndroidCosmosSensorMode.MANUAL_OFF
            }
        }
        when (currentSensorMode) {
            AndroidCosmosSensorMode.ACTIVE_LIVE_SKY -> {
                ensureHardwareSensorsRegistered()
                _isTracking.value = true
            }
            AndroidCosmosSensorMode.STANDBY_AUTO_LIFT,
            AndroidCosmosSensorMode.PAUSED_AFTER_DRAG -> {
                ensureHardwareSensorsRegistered()
                _isTracking.value = false
            }
            else -> {
                unregisterAllSensors()
                startHingeMonitoringOnly()
                _isTracking.value = false
            }
        }
        publishModeOnly()
    }

    fun endObservatorySession() {
        unregisterAllSensors()
        _isTracking.value = false
        hasInitialQuat = false
        liftAboveThresholdSinceMs = 0L
        if (hasSensorHardware) {
            currentSensorMode = AndroidCosmosSensorMode.STANDBY_AUTO_LIFT
        }
        publishModeOnly()
    }

    fun startTracking() {
        if (!hasSensorHardware) return
        hasInitialQuat = false
        liftAboveThresholdSinceMs = 0L
        currentSensorMode = AndroidCosmosSensorMode.ACTIVE_LIVE_SKY
        ensureHardwareSensorsRegistered()
        _isTracking.value = true
        publishModeOnly()
    }

    fun stopTracking(explicitUserOff: Boolean = true) {
        _isTracking.value = false
        hasInitialQuat = false
        liftAboveThresholdSinceMs = 0L
        if (explicitUserOff) {
            currentSensorMode = if (hasSensorHardware) AndroidCosmosSensorMode.MANUAL_OFF else AndroidCosmosSensorMode.UNAVAILABLE
            unregisterAllSensors()
            startHingeMonitoringOnly()
        } else {
            currentSensorMode = if (hasSensorHardware) AndroidCosmosSensorMode.PAUSED_AFTER_DRAG else AndroidCosmosSensorMode.UNAVAILABLE
            hasLoweredSinceDragPause = false
            dragPausedAtMs = SystemClock.elapsedRealtime()
            ensureHardwareSensorsRegistered()
        }
        publishModeOnly()
    }

    fun startHingeMonitoringOnly() {
        if (hingeSensor != null && !_isTracking.value && currentSensorMode == AndroidCosmosSensorMode.MANUAL_OFF) {
            sensorManager?.registerListener(this, hingeSensor, SensorManager.SENSOR_DELAY_UI)
        }
    }

    fun setGyroLockIgnoreMagnet(enabled: Boolean) {
        if (!hasHardwareGyroscope || isGyroLockIgnoreMagnet == enabled) return
        val curAz = _attitude.value.azimuthDegrees
        isGyroLockIgnoreMagnet = enabled
        hasInitialQuat = false
        if (currentSensorMode == AndroidCosmosSensorMode.ACTIVE_LIVE_SKY ||
            currentSensorMode == AndroidCosmosSensorMode.STANDBY_AUTO_LIFT ||
            currentSensorMode == AndroidCosmosSensorMode.PAUSED_AFTER_DRAG
        ) {
            ensureHardwareSensorsRegistered(forceRebind = true)
            gyroAnchorOffsetDegrees = if (enabled) {
                normalizeSignedDegrees(curAz - lastRawTrueAzimuthDegrees)
            } else {
                0.0
            }
        }
        publishModeOnly()
    }

    fun alignAzimuthToTarget(trueTargetAzimuthDegrees: Double) {
        azimuthOffsetDegrees = normalizeSignedDegrees(
            trueTargetAzimuthDegrees - lastRawTrueAzimuthDegrees - gyroAnchorOffsetDegrees
        )
        if (_attitude.value.hasMagneticInterference && hasHardwareGyroscope && !isGyroLockIgnoreMagnet) {
            setGyroLockIgnoreMagnet(true)
            azimuthOffsetDegrees = normalizeSignedDegrees(
                trueTargetAzimuthDegrees - lastRawTrueAzimuthDegrees - gyroAnchorOffsetDegrees
            )
        } else {
            publishModeOnly()
        }
    }

    fun clearAzimuthAlignmentOffset() {
        azimuthOffsetDegrees = 0.0
        publishModeOnly()
    }

    private fun unregisterAllSensors() {
        sensorManager?.unregisterListener(this)
        sensorsRegistered = false
        registeredCompositeType = -1
        registeredWithMagMonitor = false
    }

    private fun ensureHardwareSensorsRegistered(forceRebind: Boolean = false) {
        val chosenComposite: Sensor? = when {
            isGyroLockIgnoreMagnet && gameRotationSensor != null -> gameRotationSensor
            primaryRotationSensor != null -> primaryRotationSensor
            gameRotationSensor != null -> gameRotationSensor
            geomagneticRotationSensor != null -> geomagneticRotationSensor
            else -> null
        }

        val fallbackAccelMag = (chosenComposite == null && accelerometerSensor != null && magneticFieldSensor != null)
        val wantMagMonitor = (magneticFieldSensor != null && !fallbackAccelMag && !isGyroLockIgnoreMagnet)
        val desiredType = chosenComposite?.type ?: (if (fallbackAccelMag) -2 else -1)

        if (!forceRebind &&
            sensorsRegistered &&
            registeredCompositeType == desiredType &&
            registeredWithMagMonitor == wantMagMonitor
        ) {
            return
        }

        sensorManager?.unregisterListener(this)
        activeCompositeSensor = chosenComposite
        usingRawAccelMagFallback = fallbackAccelMag
        registeredCompositeType = desiredType
        registeredWithMagMonitor = wantMagMonitor
        sensorsRegistered = true

        // Always register SENSOR_DELAY_GAME once while Cosmos is visible so STANDBY -> ACTIVE_LIVE_SKY
        // transitions instantaneously without re-entrant unregisterListener/registerListener inside onSensorChanged!
        val delay = SensorManager.SENSOR_DELAY_GAME
        if (chosenComposite != null) {
            sensorManager?.registerListener(this, chosenComposite, delay)
        } else if (usingRawAccelMagFallback) {
            sensorManager?.registerListener(this, accelerometerSensor, delay)
            sensorManager?.registerListener(this, magneticFieldSensor, delay)
        }

        if (wantMagMonitor) {
            sensorManager?.registerListener(this, magneticFieldSensor, SensorManager.SENSOR_DELAY_UI)
        }

        if (hingeSensor != null) {
            sensorManager?.registerListener(this, hingeSensor, SensorManager.SENSOR_DELAY_UI)
        }
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && event.sensor.type == Sensor.TYPE_HINGE_ANGLE) {
            val angle = event.values.firstOrNull()
            if (angle != null) {
                currentHingeAngle = angle
                _attitude.value = _attitude.value.copy(hingeAngleDegrees = angle)
            }
            return
        }

        if (event.sensor.type == Sensor.TYPE_MAGNETIC_FIELD) {
            if (event.values.size >= 3) {
                val bx = event.values[0]
                val by = event.values[1]
                val bz = event.values[2]
                measuredFieldMicroTesla = sqrt((bx * bx + by * by + bz * bz).toDouble())
                if (usingRawAccelMagFallback) {
                    magBuf[0] = bx; magBuf[1] = by; magBuf[2] = bz
                    hasMagSample = true
                }
            }
            if (event.accuracy >= 0) {
                magSensorAccuracy = event.accuracy
            }
            if (!usingRawAccelMagFallback) return
        }

        if (usingRawAccelMagFallback) {
            if (event.sensor.type == Sensor.TYPE_ACCELEROMETER && event.values.size >= 3) {
                gravityBuf[0] = event.values[0]
                gravityBuf[1] = event.values[1]
                gravityBuf[2] = event.values[2]
                hasGravitySample = true
            }
            if (!hasGravitySample || !hasMagSample) return
            if (!SensorManager.getRotationMatrix(rotationMatrix, null, gravityBuf, magBuf)) return
            matrixToQuaternion(rotationMatrix, rawQuat)
        } else {
            if (event.sensor.type != activeCompositeSensor?.type) return
            SensorManager.getQuaternionFromVector(rawQuat, event.values)
            if (event.accuracy >= 0) {
                currentAccuracy = event.accuracy
            }
        }

        @Suppress("DEPRECATION")
        val displayRotation = activeDisplayRotation ?: windowManager?.defaultDisplay?.rotation ?: Surface.ROTATION_0
        val (axisX, axisY) = when (displayRotation) {
            Surface.ROTATION_90 -> Pair(SensorManager.AXIS_Y, SensorManager.AXIS_MINUS_X)
            Surface.ROTATION_180 -> Pair(SensorManager.AXIS_MINUS_X, SensorManager.AXIS_MINUS_Y)
            Surface.ROTATION_270 -> Pair(SensorManager.AXIS_MINUS_Y, SensorManager.AXIS_X)
            else -> Pair(SensorManager.AXIS_X, SensorManager.AXIS_Y)
        }

        // Zero-Lag Auto-Lift Check on unsmoothed `rawQuat` BEFORE SLERP (>= +6.0° sustained >= 180ms)
        if (currentSensorMode != AndroidCosmosSensorMode.ACTIVE_LIVE_SKY) {
            rawQuatForMatrix[0] = rawQuat[1]
            rawQuatForMatrix[1] = rawQuat[2]
            rawQuatForMatrix[2] = rawQuat[3]
            rawQuatForMatrix[3] = rawQuat[0]
            SensorManager.getRotationMatrixFromVector(rawRotationMatrix, rawQuatForMatrix)
            SensorManager.remapCoordinateSystem(rawRotationMatrix, axisX, axisY, rawRemappedMatrix)
            val rawFUp = -rawRemappedMatrix[8].toDouble()
            val rawAltDeg = Math.toDegrees(asin(rawFUp.coerceIn(-1.0, 1.0)))

            // Only suppress auto-lift when genuinely resting flat on a table in tabletop flex posture (< 138° hinge & pointing below horizon)
            val hinge = currentHingeAngle
            val isRestingInTabletop = isTabletopPosture &&
                (hinge == null || hinge in 65f..138f) &&
                rawAltDeg < 4.0

            val nowMs = SystemClock.elapsedRealtime()
            if (!isRestingInTabletop) {
                if (currentSensorMode == AndroidCosmosSensorMode.STANDBY_AUTO_LIFT) {
                    if (rawAltDeg >= 6.0) {
                        if (liftAboveThresholdSinceMs == 0L) {
                            liftAboveThresholdSinceMs = nowMs
                        } else if ((nowMs - liftAboveThresholdSinceMs) >= 180L) {
                            liftAboveThresholdSinceMs = 0L
                            engageFromAutoLift()
                        }
                    } else {
                        liftAboveThresholdSinceMs = 0L
                    }
                } else if (currentSensorMode == AndroidCosmosSensorMode.PAUSED_AFTER_DRAG) {
                    if (rawAltDeg < -5.0 && (nowMs - dragPausedAtMs) > 900L) {
                        hasLoweredSinceDragPause = true
                    } else if (hasLoweredSinceDragPause && rawAltDeg >= 14.0 && (nowMs - dragPausedAtMs) > 1500L) {
                        if (liftAboveThresholdSinceMs == 0L) {
                            liftAboveThresholdSinceMs = nowMs
                        } else if ((nowMs - liftAboveThresholdSinceMs) >= 200L) {
                            liftAboveThresholdSinceMs = 0L
                            engageFromAutoLift()
                        }
                    } else {
                        liftAboveThresholdSinceMs = 0L
                    }
                }
            }
        }

        if (!hasInitialQuat) {
            System.arraycopy(rawQuat, 0, smoothedQuat, 0, 4)
            hasInitialQuat = true
        } else {
            slerpAdaptive(smoothedQuat, rawQuat)
        }

        quatForMatrix[0] = smoothedQuat[1]
        quatForMatrix[1] = smoothedQuat[2]
        quatForMatrix[2] = smoothedQuat[3]
        quatForMatrix[3] = smoothedQuat[0]
        SensorManager.getRotationMatrixFromVector(rotationMatrix, quatForMatrix)
        SensorManager.remapCoordinateSystem(rotationMatrix, axisX, axisY, remappedMatrix)

        // Screen basis in Magnetic ENU:
        // Screen-Right = (1, 0, 0), Screen-Up = (0, 1, 0), Optical-Forward = (0, 0, -1).
        val rMagE = remappedMatrix[0].toDouble()
        val rMagN = remappedMatrix[3].toDouble()
        val rUp = remappedMatrix[6].toDouble()

        val uMagE = remappedMatrix[1].toDouble()
        val uMagN = remappedMatrix[4].toDouble()
        val uUp = remappedMatrix[7].toDouble()

        val fMagE = -remappedMatrix[2].toDouble()
        val fMagN = -remappedMatrix[5].toDouble()
        val fUp = -remappedMatrix[8].toDouble()

        val altRad = asin(fUp.coerceIn(-1.0, 1.0))
        val altDeg = Math.toDegrees(altRad)

        val isRelativeOnly = isGyroLockIgnoreMagnet ||
            (activeCompositeSensor?.type == Sensor.TYPE_GAME_ROTATION_VECTOR)

        // Raw True North azimuth (with WMM declination only) for 1-tap Target-Align reference
        val declOnlyRad = Math.toRadians(if (isRelativeOnly) 0.0 else declinationDegrees)
        val cd0 = cos(declOnlyRad)
        val sd0 = sin(declOnlyRad)
        val rawTrueE = fMagE * cd0 + fMagN * sd0
        val rawTrueN = -fMagE * sd0 + fMagN * cd0
        if (hypot(rawTrueE, rawTrueN) > 1e-3) {
            lastRawTrueAzimuthDegrees = (Math.toDegrees(atan2(rawTrueE, rawTrueN)) + 360.0) % 360.0
        }

        if (currentSensorMode != AndroidCosmosSensorMode.ACTIVE_LIVE_SKY) return

        // Full Eastward rotation: WMM declination + Gyro-Lock anchor + Celestial Target-Align offset
        val totalEastDeg = (if (isRelativeOnly) 0.0 else declinationDegrees) +
            gyroAnchorOffsetDegrees +
            azimuthOffsetDegrees
        val rotRad = Math.toRadians(totalEastDeg)
        val cd = cos(rotRad)
        val sd = sin(rotRad)

        // Convert Magnetic ENU -> True Geographic NWZ (`+X = North, +Y = West = -East, +Z = Up`)
        val rTrueE = rMagE * cd + rMagN * sd
        val rTrueN = -rMagE * sd + rMagN * cd
        val rxNWZ = rTrueN; val ryNWZ = -rTrueE; val rzNWZ = rUp

        val uTrueE = uMagE * cd + uMagN * sd
        val uTrueN = -uMagE * sd + uMagN * cd
        val uxNWZ = uTrueN; val uyNWZ = -uTrueE; val uzNWZ = uUp

        val fTrueE = fMagE * cd + fMagN * sd
        val fTrueN = -fMagE * sd + fMagN * cd
        val fxNWZ = fTrueN; val fyNWZ = -fTrueE; val fzNWZ = fUp

        // Singularity-free azimuth & positive-clockwise horizon roll
        val horizLen = hypot(fxNWZ, fyNWZ)
        val azRad = if (horizLen > 1e-3) {
            var a = atan2(-fyNWZ, fxNWZ)
            if (a < 0.0) a += 2.0 * Math.PI
            lastValidAzimuthRadians = a
            a
        } else {
            val upHoriz = hypot(uxNWZ, uyNWZ)
            if (upHoriz > 1e-3) {
                val sign = if (fzNWZ >= 0.0) -1.0 else 1.0
                var a = atan2(-sign * uyNWZ, sign * uxNWZ)
                if (a < 0.0) a += 2.0 * Math.PI
                lastValidAzimuthRadians = a
                a
            } else {
                lastValidAzimuthRadians
            }
        }

        val cosAz = cos(azRad); val sinAz = sin(azRad)
        val cosAlt = cos(altRad); val sinAlt = sin(altRad)
        val r0x = -sinAz; val r0y = -cosAz
        val u0x = -sinAlt * cosAz; val u0y = sinAlt * sinAz; val u0z = cosAlt

        val projUpOnRight = uxNWZ * r0x + uyNWZ * r0y
        val projUpOnUp = uxNWZ * u0x + uyNWZ * u0y + uzNWZ * u0z
        val rollDeg = Math.toDegrees(atan2(projUpOnRight, projUpOnUp))

        val highThresh = max(72.0, expectedFieldMicroTesla * 1.48)
        val lowThresh = min(18.0, expectedFieldMicroTesla * 0.42)
        val magAnomaly = !isRelativeOnly && measuredFieldMicroTesla > 0.5 &&
            (measuredFieldMicroTesla > highThresh || measuredFieldMicroTesla < lowThresh)

        val effectiveAcc = if (isRelativeOnly) {
            SensorManager.SENSOR_STATUS_ACCURACY_HIGH
        } else {
            min(currentAccuracy, magSensorAccuracy)
        }

        _attitude.value = DeviceAttitude(
            azimuthDegrees = Math.toDegrees(azRad),
            altitudeDegrees = altDeg.coerceIn(-89.9, 90.0),
            rollDegrees = rollDeg,
            rightNWZ0 = rxNWZ, rightNWZ1 = ryNWZ, rightNWZ2 = rzNWZ,
            upNWZ0 = uxNWZ, upNWZ1 = uyNWZ, upNWZ2 = uzNWZ,
            forwardNWZ0 = fxNWZ, forwardNWZ1 = fyNWZ, forwardNWZ2 = fzNWZ,
            hasValidBasis = true,
            magneticDeclinationDegrees = declinationDegrees,
            magneticFieldMicroTesla = measuredFieldMicroTesla,
            expectedFieldMicroTesla = expectedFieldMicroTesla,
            azimuthOffsetDegrees = azimuthOffsetDegrees,
            accuracy = effectiveAcc,
            isRelativeGyroFallback = isRelativeOnly && !isGyroLockIgnoreMagnet,
            isGyroLockIgnoreMagnet = isGyroLockIgnoreMagnet,
            isGyroscopeLessHardware = !hasHardwareGyroscope,
            hasMagneticInterference = magAnomaly,
            sensorMode = currentSensorMode,
            hingeAngleDegrees = currentHingeAngle
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        if (sensor?.type == activeCompositeSensor?.type) {
            currentAccuracy = accuracy
        } else if (sensor?.type == Sensor.TYPE_MAGNETIC_FIELD) {
            magSensorAccuracy = accuracy
        }
    }

    private fun engageFromAutoLift() {
        currentSensorMode = AndroidCosmosSensorMode.ACTIVE_LIVE_SKY
        System.arraycopy(rawQuat, 0, smoothedQuat, 0, 4)
        hasInitialQuat = true
        _isTracking.value = true
        onAutoLiftEngaged?.invoke()
    }

    private fun publishModeOnly() {
        val highThresh = max(72.0, expectedFieldMicroTesla * 1.48)
        val lowThresh = min(18.0, expectedFieldMicroTesla * 0.42)
        val isRel = isGyroLockIgnoreMagnet || (activeCompositeSensor?.type == Sensor.TYPE_GAME_ROTATION_VECTOR)
        val magAnomaly = !isRel && measuredFieldMicroTesla > 0.5 &&
            (measuredFieldMicroTesla > highThresh || measuredFieldMicroTesla < lowThresh)
        _attitude.value = _attitude.value.copy(
            sensorMode = currentSensorMode,
            hasValidBasis = currentSensorMode == AndroidCosmosSensorMode.ACTIVE_LIVE_SKY && _attitude.value.hasValidBasis,
            isGyroLockIgnoreMagnet = isGyroLockIgnoreMagnet,
            azimuthOffsetDegrees = azimuthOffsetDegrees,
            magneticDeclinationDegrees = declinationDegrees,
            expectedFieldMicroTesla = expectedFieldMicroTesla,
            hasMagneticInterference = magAnomaly
        )
    }

    private fun slerpAdaptive(current: FloatArray, target: FloatArray) {
        var tw = target[0]
        var tx = target[1]
        var ty = target[2]
        var tz = target[3]

        var dot = current[0] * tw + current[1] * tx + current[2] * ty + current[3] * tz
        if (dot < 0f) {
            dot = -dot
            tw = -tw; tx = -tx; ty = -ty; tz = -tz
        }
        val clampedDot = dot.coerceIn(-1f, 1f)
        val omega = acos(clampedDot.toDouble())
        val angleDeg = Math.toDegrees(omega)

        // Stronger tremor suppression for gyroscope-less compass hardware and high-magnification binocular/scope FOV
        val fovGain = sqrt((currentFovDegrees / 60.0).coerceIn(0.04, 1.5))
        val minT = if (hasHardwareGyroscope) (0.085 * fovGain).coerceAtLeast(0.022) else (0.040 * fovGain).coerceAtLeast(0.018)
        val maxT = if (hasHardwareGyroscope) (0.46 * fovGain + 0.06).coerceIn(0.20, 0.54) else 0.24
        val t = (((angleDeg - 0.20) / 6.0) * fovGain).coerceIn(minT, maxT).toFloat()

        if (clampedDot > 0.9995f) {
            current[0] += t * (tw - current[0])
            current[1] += t * (tx - current[1])
            current[2] += t * (ty - current[2])
            current[3] += t * (tz - current[3])
        } else {
            val sinOmega = sin(omega).toFloat()
            val s0 = (sin((1.0 - t) * omega) / sinOmega).toFloat()
            val s1 = (sin(t * omega) / sinOmega).toFloat()
            current[0] = s0 * current[0] + s1 * tw
            current[1] = s0 * current[1] + s1 * tx
            current[2] = s0 * current[2] + s1 * ty
            current[3] = s0 * current[3] + s1 * tz
        }
        val norm = sqrt(
            current[0] * current[0] +
                current[1] * current[1] +
                current[2] * current[2] +
                current[3] * current[3]
        )
        if (norm > 1e-6f) {
            current[0] /= norm
            current[1] /= norm
            current[2] /= norm
            current[3] /= norm
        }
    }

    private fun matrixToQuaternion(m: FloatArray, outWxyz: FloatArray) {
        val trace = m[0] + m[4] + m[8]
        if (trace > 0f) {
            val s = 0.5f / sqrt(trace + 1.0f)
            outWxyz[0] = 0.25f / s
            outWxyz[1] = (m[7] - m[5]) * s
            outWxyz[2] = (m[2] - m[6]) * s
            outWxyz[3] = (m[3] - m[1]) * s
        } else if (m[0] > m[4] && m[0] > m[8]) {
            val s = 2.0f * sqrt(1.0f + m[0] - m[4] - m[8])
            outWxyz[0] = (m[7] - m[5]) / s
            outWxyz[1] = 0.25f * s
            outWxyz[2] = (m[1] + m[3]) / s
            outWxyz[3] = (m[2] + m[6]) / s
        } else if (m[4] > m[8]) {
            val s = 2.0f * sqrt(1.0f + m[4] - m[0] - m[8])
            outWxyz[0] = (m[2] - m[6]) / s
            outWxyz[1] = (m[1] + m[3]) / s
            outWxyz[2] = 0.25f * s
            outWxyz[3] = (m[5] + m[7]) / s
        } else {
            val s = 2.0f * sqrt(1.0f + m[8] - m[0] - m[4])
            outWxyz[0] = (m[3] - m[1]) / s
            outWxyz[1] = (m[2] + m[6]) / s
            outWxyz[2] = (m[5] + m[7]) / s
            outWxyz[3] = 0.25f * s
        }
    }

    private fun normalizeSignedDegrees(deg: Double): Double {
        var d = (deg + 180.0) % 360.0
        if (d < 0.0) d += 360.0
        return d - 180.0
    }
}
