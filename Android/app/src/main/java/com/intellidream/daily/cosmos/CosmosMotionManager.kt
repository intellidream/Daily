package com.intellidream.daily.cosmos

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.math.atan2
import kotlin.math.roundToInt

data class DeviceAttitude(
    val azimuthDegrees: Double = 0.0,
    val altitudeDegrees: Double = 45.0,
    val rollDegrees: Double = 0.0
)

class CosmosMotionManager(context: Context) : SensorEventListener {
    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
    private val rotationSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        ?: sensorManager?.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)

    private val _attitude = MutableStateFlow(DeviceAttitude())
    val attitude: StateFlow<DeviceAttitude> = _attitude.asStateFlow()

    private val _isTracking = MutableStateFlow(false)
    val isTracking: StateFlow<Boolean> = _isTracking.asStateFlow()

    private val rotationMatrix = FloatArray(9)
    private val remappedMatrix = FloatArray(9)
    private val orientationAngles = FloatArray(3)

    // Low-pass filter smoothing coefficient (0.15 = buttery smooth on 120Hz displays)
    private val alpha = 0.18f
    private var smoothedAzimuth = 0.0
    private var smoothedAltitude = 45.0
    private var smoothedRoll = 0.0
    private var isInitialized = false

    fun startTracking() {
        if (_isTracking.value || rotationSensor == null) return
        sensorManager?.registerListener(this, rotationSensor, SensorManager.SENSOR_DELAY_GAME)
        _isTracking.value = true
    }

    fun stopTracking() {
        if (!_isTracking.value) return
        sensorManager?.unregisterListener(this)
        _isTracking.value = false
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null || event.sensor.type != rotationSensor?.type) return

        SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)

        // Remap coordinates for standard camera pointing (holding phone up towards sky)
        // X -> X (Right), Y -> Z (Top of device pointing outward towards sky)
        SensorManager.remapCoordinateSystem(
            rotationMatrix,
            SensorManager.AXIS_X,
            SensorManager.AXIS_Z,
            remappedMatrix
        )

        SensorManager.getOrientation(remappedMatrix, orientationAngles)

        // Azimuth (yaw): orientationAngles[0] in [-PI, PI] -> convert to [0, 360) degrees
        var rawAz = Math.toDegrees(orientationAngles[0].toDouble())
        if (rawAz < 0) rawAz += 360.0

        // Pitch / Altitude: orientationAngles[1] in [-PI/2, PI/2] -> degrees [-90, +90]
        val rawAlt = Math.toDegrees(orientationAngles[1].toDouble()).coerceIn(-90.0, 90.0)

        // Roll: orientationAngles[2] in [-PI, PI] -> degrees
        val rawRoll = Math.toDegrees(orientationAngles[2].toDouble())

        if (!isInitialized) {
            smoothedAzimuth = rawAz
            smoothedAltitude = rawAlt
            smoothedRoll = rawRoll
            isInitialized = true
        } else {
            // Handle angular wrap-around for azimuth
            var diffAz = rawAz - smoothedAzimuth
            while (diffAz > 180.0) diffAz -= 360.0
            while (diffAz < -180.0) diffAz += 360.0
            smoothedAzimuth = (smoothedAzimuth + (alpha * diffAz) + 360.0) % 360.0

            smoothedAltitude += alpha * (rawAlt - smoothedAltitude)
            smoothedRoll += alpha * (rawRoll - smoothedRoll)
        }

        _attitude.value = DeviceAttitude(
            azimuthDegrees = smoothedAzimuth,
            altitudeDegrees = smoothedAltitude,
            rollDegrees = smoothedRoll
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // No-op
    }
}
