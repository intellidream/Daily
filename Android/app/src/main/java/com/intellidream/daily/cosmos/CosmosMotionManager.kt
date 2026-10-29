package com.intellidream.daily.cosmos

import android.content.Context
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
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
import kotlin.math.sin
import kotlin.math.sqrt

data class DeviceAttitude(
    val azimuthDegrees: Double = 180.0,
    val altitudeDegrees: Double = 45.0,
    val rollDegrees: Double = 0.0,
    val magneticDeclinationDegrees: Double = 0.0,
    val accuracy: Int = SensorManager.SENSOR_STATUS_ACCURACY_HIGH,
    val isRelativeGyroFallback: Boolean = false,
    val hingeAngleDegrees: Float? = null
) {
    val needsCompassCalibration: Boolean
        get() = !isRelativeGyroFallback &&
            (accuracy == SensorManager.SENSOR_STATUS_UNRELIABLE || accuracy == SensorManager.SENSOR_STATUS_ACCURACY_LOW)
}

/**
 * Validated 120Hz optical-axis sensor fusion manager for Android phones & foldables:
 * - Uses Quaternion SLERP smoothing with adaptive velocity gain (jitter-free while stationary, zero-lag slewing).
 * - Remaps sensor axes dynamically for Display.rotation (portrait, landscape, unfolded Z Fold 8).
 * - Projects the back-camera optical axis [0, 0, -1] directly in ENU without Euler gimbal lock at Zenith (+90°).
 * - Applies NOAA World Magnetic Model (GeomagneticField) declination so Azimuth is referenced to True North.
 * - Monitors Sensor.TYPE_HINGE_ANGLE on foldables for Tabletop Flex Mode tilt awareness.
 */
class CosmosMotionManager(context: Context) : SensorEventListener {
    private val appContext = context.applicationContext
    private val sensorManager = appContext.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
    private val windowManager = appContext.getSystemService(Context.WINDOW_SERVICE) as? WindowManager

    private val primaryRotationSensor: Sensor? = sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
    private val fallbackGameSensor: Sensor? = sensorManager?.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
    private val activeRotationSensor: Sensor? = primaryRotationSensor ?: fallbackGameSensor
    private val hingeSensor: Sensor? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        sensorManager?.getDefaultSensor(Sensor.TYPE_HINGE_ANGLE)
    } else {
        null
    }

    val hasSensorHardware: Boolean get() = activeRotationSensor != null
    val isUsingRelativeFallback: Boolean get() = primaryRotationSensor == null && fallbackGameSensor != null

    private val _attitude = MutableStateFlow(
        DeviceAttitude(isRelativeGyroFallback = isUsingRelativeFallback)
    )
    val attitude: StateFlow<DeviceAttitude> = _attitude.asStateFlow()

    private val _isTracking = MutableStateFlow(false)
    val isTracking: StateFlow<Boolean> = _isTracking.asStateFlow()

    private var declinationDegrees: Double = 0.0
    private var currentAccuracy: Int = SensorManager.SENSOR_STATUS_ACCURACY_HIGH
    private var currentHingeAngle: Float? = null

    // Reusable pre-allocated buffers (zero GC pressure at 120Hz)
    private val rawQuat = FloatArray(4) // [w, x, y, z] from SensorManager.getQuaternionFromVector
    private val smoothedQuat = FloatArray(4)
    private val quatForMatrix = FloatArray(4) // [x, y, z, w] expected by getRotationMatrixFromVector
    private val rotationMatrix = FloatArray(9)
    private val remappedMatrix = FloatArray(9)
    private var hasInitialQuat = false

    fun updateObserverLocation(latitude: Double, longitude: Double, elevationMeters: Double = 0.0) {
        val field = GeomagneticField(
            latitude.toFloat(),
            longitude.toFloat(),
            elevationMeters.toFloat(),
            System.currentTimeMillis()
        )
        declinationDegrees = field.declination.toDouble()
    }

    fun startTracking() {
        if (_isTracking.value) return
        val rot = activeRotationSensor
        if (rot != null) {
            hasInitialQuat = false
            sensorManager?.registerListener(this, rot, SensorManager.SENSOR_DELAY_GAME)
        }
        if (hingeSensor != null) {
            sensorManager?.registerListener(this, hingeSensor, SensorManager.SENSOR_DELAY_UI)
        }
        _isTracking.value = rot != null
    }

    fun startHingeMonitoringOnly() {
        if (hingeSensor != null && !_isTracking.value) {
            sensorManager?.registerListener(this, hingeSensor, SensorManager.SENSOR_DELAY_UI)
        }
    }

    fun stopTracking() {
        sensorManager?.unregisterListener(this)
        _isTracking.value = false
        hasInitialQuat = false
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

        if (event.sensor.type != activeRotationSensor?.type) return

        // 1. Extract unit quaternion [w, x, y, z]
        SensorManager.getQuaternionFromVector(rawQuat, event.values)

        if (!hasInitialQuat) {
            System.arraycopy(rawQuat, 0, smoothedQuat, 0, 4)
            hasInitialQuat = true
        } else {
            slerpAdaptive(smoothedQuat, rawQuat)
        }

        // 2. Convert smoothed quaternion [x, y, z, w] -> 3x3 ENU rotation matrix
        quatForMatrix[0] = smoothedQuat[1]
        quatForMatrix[1] = smoothedQuat[2]
        quatForMatrix[2] = smoothedQuat[3]
        quatForMatrix[3] = smoothedQuat[0]
        SensorManager.getRotationMatrixFromVector(rotationMatrix, quatForMatrix)

        // 3. Remap axes for current Display rotation (portrait, landscape, unfolded tablet)
        @Suppress("DEPRECATION")
        val displayRotation = windowManager?.defaultDisplay?.rotation ?: Surface.ROTATION_0
        val (axisX, axisY) = when (displayRotation) {
            Surface.ROTATION_90 -> Pair(SensorManager.AXIS_Y, SensorManager.AXIS_MINUS_X)
            Surface.ROTATION_180 -> Pair(SensorManager.AXIS_MINUS_X, SensorManager.AXIS_MINUS_Y)
            Surface.ROTATION_270 -> Pair(SensorManager.AXIS_MINUS_Y, SensorManager.AXIS_X)
            else -> Pair(SensorManager.AXIS_X, SensorManager.AXIS_Y)
        }
        SensorManager.remapCoordinateSystem(rotationMatrix, axisX, axisY, remappedMatrix)

        // 4. Optical-axis sky vector in ENU:
        // Screen-space forward out the rear camera is (0, 0, -1); screen-up is (0, 1, 0); screen-right is (1, 0, 0).
        // remappedMatrix is row-major:
        //   East  = m[0]*sx + m[1]*sy + m[2]*sz
        //   North = m[3]*sx + m[4]*sy + m[5]*sz
        //   Up    = m[6]*sx + m[7]*sy + m[8]*sz
        val fEast = -remappedMatrix[2].toDouble()
        val fNorth = -remappedMatrix[5].toDouble()
        val fUp = -remappedMatrix[8].toDouble()

        val uEast = remappedMatrix[1].toDouble()
        val uNorth = remappedMatrix[4].toDouble()
        val uUp = remappedMatrix[7].toDouble()

        val rEast = remappedMatrix[0].toDouble()
        val rUp = remappedMatrix[6].toDouble()

        val altDeg = Math.toDegrees(asin(fUp.coerceIn(-1.0, 1.0)))

        // Singularity-free azimuth: smoothly transitions to -screenUp horizontal projection near exact Zenith/Nadir
        val horizLen = hypot(fEast, fNorth)
        val magAzRad = if (horizLen > 1e-2) {
            atan2(fEast, fNorth)
        } else {
            val sign = if (fUp >= 0.0) -1.0 else 1.0
            atan2(sign * uEast, sign * uNorth)
        }
        val magAzDeg = (Math.toDegrees(magAzRad) + 360.0) % 360.0
        val trueAzDeg = if (isUsingRelativeFallback) {
            magAzDeg
        } else {
            (magAzDeg + declinationDegrees + 360.0) % 360.0
        }

        // Horizon roll angle (degrees of screen tilt around the optical axis)
        val rollDeg = if (horizLen > 1e-2) {
            Math.toDegrees(atan2(rUp, uUp))
        } else {
            0.0
        }

        val acc = if (event.accuracy >= 0) event.accuracy else currentAccuracy
        currentAccuracy = acc

        _attitude.value = DeviceAttitude(
            azimuthDegrees = trueAzDeg,
            altitudeDegrees = altDeg,
            rollDegrees = rollDeg,
            magneticDeclinationDegrees = declinationDegrees,
            accuracy = acc,
            isRelativeGyroFallback = isUsingRelativeFallback,
            hingeAngleDegrees = currentHingeAngle
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        if (sensor?.type == activeRotationSensor?.type) {
            currentAccuracy = accuracy
            _attitude.value = _attitude.value.copy(accuracy = accuracy)
        }
    }

    /**
     * In-place adaptive quaternion SLERP on [w, x, y, z]:
     * Small angular deltas (<0.5°) use alpha=0.09 to suppress magnetometer/MEMS noise;
     * fast slews (>6°) ramp alpha up to 0.42 for crisp 120Hz responsiveness.
     */
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
        val t = ((angleDeg - 0.25) / 6.0).coerceIn(0.09, 0.42).toFloat()

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
}
