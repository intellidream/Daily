import Foundation
import DailyCore
#if canImport(CoreMotion)
import CoreMotion
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(UIKit)
import UIKit
#endif
import simd
import Combine

public enum CosmosSensorMode: String, Equatable, Sendable {
    case unavailable
    case standbyAutoLift
    case activeLiveSky
    case pausedAfterDrag
    case manualOff
}

/// High-frequency (90Hz–120Hz) 9-DOF sensor fusion & True North sky tracker for iOS & Foldable devices.
/// Combines CoreMotion gyroscope + accelerometer + magnetometer with CoreLocation / NOAA WMM-2025 True North
/// declination, FOV-adaptive quaternion SLERP optical stabilization, magnetic anomaly (µT) detection,
/// Gyro-Only balcony mode, and 1-tap celestial "Align on Target" azimuth calibration.
@MainActor
public final class CosmosMotionService: NSObject, ObservableObject {
    public static let shared = CosmosMotionService()

    #if canImport(CoreMotion) && !os(macOS)
    private let motionManager = CMMotionManager()
    private let headingLocationManager = CLLocationManager()
    private var activeReferenceFrame: CMAttitudeReferenceFrame = .xArbitraryZVertical
    #endif

    @Published public private(set) var sensorMode: CosmosSensorMode = .unavailable
    @Published public private(set) var isTracking: Bool = false
    @Published public private(set) var isAvailable: Bool = false
    @Published public private(set) var isUsingTrueNorth: Bool = false
    @Published public private(set) var isRelativeGyroOnly: Bool = false
    @Published public private(set) var isGyroLockIgnoreMagnet: Bool = false
    @Published public private(set) var needsCompassCalibration: Bool = false
    @Published public private(set) var hasMagneticInterference: Bool = false

    @Published public private(set) var magneticFieldMicroTesla: Double = 0.0
    @Published public private(set) var expectedFieldMicroTesla: Double = 49.0
    @Published public private(set) var wmmDeclinationDegrees: Double = 0.0
    @Published public private(set) var headingAccuracyDegrees: Double = -1.0
    @Published public private(set) var azimuthOffsetDegrees: Double = 0.0

    @Published public private(set) var currentAzimuth: Double = 180.0
    @Published public private(set) var currentAltitude: Double = 45.0
    @Published public private(set) var currentRoll: Double = 0.0

    /// Direct orthonormal camera basis `(right, up, forward)` in NWZ (`+X=North, +Y=West, +Z=Zenith`),
    /// eliminating Euler gimbal singularities at exact Zenith (+90°) and Nadir (-90°).
    public private(set) var currentBasisNWZ: (
        right: (Double, Double, Double),
        up: (Double, Double, Double),
        forward: (Double, Double, Double)
    )? = nil

    public var onAutoLiftEngaged: (() -> Void)? = nil

    private var smoothedQuat: simd_quatd? = nil
    private var lastRawTrueAzimuthDegrees: Double = 180.0
    private var lastValidAzimuthRadians: Double = .pi
    private var gyroAnchorOffsetDegrees: Double = 0.0
    private var currentFovDegrees: Double = 60.0

    // Auto-lift hysteresis state (> +15° sustained for >= 0.25s; re-arms after lowering < -5° when pausedAfterDrag)
    private var liftAboveThresholdSince: TimeInterval? = nil
    private var hasLoweredSinceDragPause: Bool = true
    private var dragPausedTimestamp: TimeInterval = 0.0

    private override init() {
        super.init()
        #if canImport(CoreMotion) && !os(macOS)
        self.isAvailable = motionManager.isDeviceMotionAvailable
        self.sensorMode = self.isAvailable ? .standbyAutoLift : .unavailable
        self.headingLocationManager.delegate = self
        self.headingLocationManager.headingFilter = 1.0
        #else
        self.isAvailable = false
        self.sensorMode = .unavailable
        #endif
    }

    public func updateObserverLocation(latitude: Double, longitude: Double, elevationMeters: Double = 50.0) {
        let est = AstronomyService.shared.geomagneticFieldEstimate(
            latitudeDegrees: latitude,
            longitudeDegrees: longitude,
            elevationMeters: elevationMeters
        )
        wmmDeclinationDegrees = est.declinationDegrees
        expectedFieldMicroTesla = est.expectedIntensityMicroTesla
    }

    public func updateCurrentFov(_ fovDegrees: Double) {
        currentFovDegrees = max(0.5, min(130.0, fovDegrees))
    }

    // MARK: - Observatory Session Lifecycle

    /// Begins passive Lift-to-Sky standby monitoring when entering Cosmos on a physical iPhone / iPad / Foldable.
    /// Does NOT hijack the camera until the user lifts the phone above +15° toward the sky (or taps Live Sky).
    public func beginObservatorySession(autoLiftEnabled: Bool = true) {
        #if canImport(CoreMotion) && !os(macOS)
        guard motionManager.isDeviceMotionAvailable else {
            sensorMode = .unavailable
            return
        }
        liftAboveThresholdSince = nil
        hasLoweredSinceDragPause = true
        if sensorMode == .unavailable || sensorMode == .manualOff {
            sensorMode = autoLiftEnabled ? .standbyAutoLift : .manualOff
        }
        if sensorMode == .standbyAutoLift {
            startHardwarePipeline(highFrequency: false)
        } else if sensorMode == .activeLiveSky {
            startHardwarePipeline(highFrequency: true)
            isTracking = true
        }
        #endif
    }

    public func endObservatorySession() {
        stopHardwarePipeline()
        isTracking = false
        currentBasisNWZ = nil
        liftAboveThresholdSince = nil
        if isAvailable {
            sensorMode = .standbyAutoLift
        }
    }

    /// Explicit user tap on the Live Sky / Compass button.
    public func startTracking() {
        #if canImport(CoreMotion) && !os(macOS)
        guard motionManager.isDeviceMotionAvailable else { return }
        smoothedQuat = nil
        liftAboveThresholdSince = nil
        sensorMode = .activeLiveSky
        isTracking = true
        startHardwarePipeline(highFrequency: true)
        #endif
    }

    /// Explicit user tap to turn Live Sky OFF completely (disables auto-lift for current session until re-enabled).
    public func stopTracking(explicitUserOff: Bool = true) {
        #if canImport(CoreMotion) && !os(macOS)
        isTracking = false
        currentBasisNWZ = nil
        needsCompassCalibration = false
        smoothedQuat = nil
        liftAboveThresholdSince = nil
        if explicitUserOff {
            sensorMode = isAvailable ? .manualOff : .unavailable
            stopHardwarePipeline()
        } else {
            // Disengaged by 1-finger touch pan: keep lightweight attitude monitor so lowering & re-lifting works,
            // while surfacing a 1-tap "Resume Live Sky" pill.
            sensorMode = isAvailable ? .pausedAfterDrag : .unavailable
            hasLoweredSinceDragPause = false
            dragPausedTimestamp = ProcessInfo.processInfo.systemUptime
            motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        }
        #endif
    }

    /// Switches between Magnetometer-fused True North and pure drift-free Gyroscope + Gravity lock (ideal for steel balconies / MagSafe cases).
    public func setGyroLockIgnoreMagnet(_ enabled: Bool) {
        #if canImport(CoreMotion) && !os(macOS)
        guard isGyroLockIgnoreMagnet != enabled else { return }
        let targetAzBeforeSwitch = currentAzimuth
        isGyroLockIgnoreMagnet = enabled
        smoothedQuat = nil
        if sensorMode == .activeLiveSky || sensorMode == .standbyAutoLift || sensorMode == .pausedAfterDrag {
            stopHardwarePipeline()
            startHardwarePipeline(highFrequency: sensorMode == .activeLiveSky)
            if enabled {
                // Anchor arbitrary gyro yaw to the last known true azimuth
                gyroAnchorOffsetDegrees = normalizeDegreesSigned(targetAzBeforeSwitch - lastRawTrueAzimuthDegrees)
            } else {
                gyroAnchorOffsetDegrees = 0.0
            }
        }
        #endif
    }

    /// Calibrates compass bearing against a real visible celestial body (e.g. Moon, Venus, Jupiter, Sirius) when local metal/magnets skew North.
    public func alignAzimuth(toTrueTargetAzimuth targetAzimuthDegrees: Double) {
        let delta = normalizeDegreesSigned(targetAzimuthDegrees - lastRawTrueAzimuthDegrees - gyroAnchorOffsetDegrees)
        azimuthOffsetDegrees = delta
        if hasMagneticInterference && !isGyroLockIgnoreMagnet {
            // Automatically engage Gyro-Stabilized Lock so wandering balcony magnetic fields cannot undo the star alignment!
            setGyroLockIgnoreMagnet(true)
            azimuthOffsetDegrees = normalizeDegreesSigned(targetAzimuthDegrees - lastRawTrueAzimuthDegrees - gyroAnchorOffsetDegrees)
        }
    }

    public func clearAzimuthAlignmentOffset() {
        azimuthOffsetDegrees = 0.0
    }

    // MARK: - Hardware Sensor Pipeline

    private func stopHardwarePipeline() {
        #if canImport(CoreMotion) && !os(macOS)
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        headingLocationManager.stopUpdatingHeading()
        #endif
    }

    #if canImport(CoreMotion) && !os(macOS)
    private func startHardwarePipeline(highFrequency: Bool) {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = highFrequency ? (1.0 / 90.0) : (1.0 / 30.0)
        motionManager.showsDeviceMovementDisplay = highFrequency && !isGyroLockIgnoreMagnet

        let available = CMMotionManager.availableAttitudeReferenceFrames()
        let authStatus = headingLocationManager.authorizationStatus
        let isLocAuthorized = (authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways)

        let selectedFrame: CMAttitudeReferenceFrame
        if isGyroLockIgnoreMagnet {
            selectedFrame = .xArbitraryZVertical
            isUsingTrueNorth = false
            isRelativeGyroOnly = true
        } else if available.contains(.xTrueNorthZVertical) && isLocAuthorized {
            selectedFrame = .xTrueNorthZVertical
            isUsingTrueNorth = true
            isRelativeGyroOnly = false
            if CLLocationManager.headingAvailable() {
                headingLocationManager.startUpdatingHeading()
            }
            if headingLocationManager.location == nil {
                headingLocationManager.requestLocation()
            }
        } else if available.contains(.xMagneticNorthZVertical) {
            selectedFrame = .xMagneticNorthZVertical
            // Offline WMM-2025 declination upgrades Magnetic North -> True Geographic North!
            isUsingTrueNorth = true
            isRelativeGyroOnly = false
            if CLLocationManager.headingAvailable() {
                headingLocationManager.startUpdatingHeading()
            }
            if authStatus == .notDetermined && highFrequency {
                headingLocationManager.requestWhenInUseAuthorization()
            }
        } else if available.contains(.xArbitraryCorrectedZVertical) {
            selectedFrame = .xArbitraryCorrectedZVertical
            isUsingTrueNorth = false
            isRelativeGyroOnly = true
        } else {
            selectedFrame = .xArbitraryZVertical
            isUsingTrueNorth = false
            isRelativeGyroOnly = true
        }

        if motionManager.isDeviceMotionActive && activeReferenceFrame == selectedFrame {
            return
        }
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        activeReferenceFrame = selectedFrame
        motionManager.startDeviceMotionUpdates(using: selectedFrame, to: .main) { [weak self] motion, _ in
            guard let self = self, let motion = motion else { return }
            self.processMotion(motion)
        }
    }

    private func processMotion(_ motion: CMDeviceMotion) {
        // 1. Magnetic Calibration & Anomaly Assessment (µT)
        if !isRelativeGyroOnly {
            let acc = motion.magneticField.accuracy
            let mf = motion.magneticField.field
            let normCalibrated = sqrt(mf.x * mf.x + mf.y * mf.y + mf.z * mf.z)
            if normCalibrated > 0.5 {
                magneticFieldMicroTesla = normCalibrated
            }
            let highThresh = max(72.0, expectedFieldMicroTesla * 1.48)
            let lowThresh = min(18.0, expectedFieldMicroTesla * 0.42)
            let fieldAnomaly = (magneticFieldMicroTesla > highThresh) ||
                (magneticFieldMicroTesla > 1.0 && magneticFieldMicroTesla < lowThresh)
            hasMagneticInterference = fieldAnomaly || (headingAccuracyDegrees > 30.0)
            needsCompassCalibration = (acc == .uncalibrated || acc == .low) ||
                (headingAccuracyDegrees < 0 && normCalibrated < 0.5) ||
                hasMagneticInterference
        } else {
            hasMagneticInterference = false
            needsCompassCalibration = false
        }

        // 2. FOV-Adaptive Quaternion SLERP (OIS stabilization at binocular/telescope magnification)
        let cq = motion.attitude.quaternion
        var rawQ = simd_normalize(simd_quatd(ix: cq.x, iy: cq.y, iz: cq.z, r: cq.w))

        // Self-verifying physical check against `motion.gravity` (device-frame gravity must map to world -Z):
        let gDev = SIMD3<Double>(motion.gravity.x, motion.gravity.y, motion.gravity.z)
        if abs(gDev.z) < 0.92 {
            let zDirect = rawQ.act(gDev).z
            let zInv = rawQ.inverse.act(gDev).z
            if abs(zInv + 1.0) + 0.08 < abs(zDirect + 1.0) {
                rawQ = rawQ.inverse
            }
        }

        let fovGain = sqrt(max(0.04, min(1.5, currentFovDegrees / 60.0)))
        let minAlpha = max(0.025, 0.10 * fovGain)
        let maxAlpha = max(0.22, min(0.62, 0.56 * fovGain + 0.08))

        let filteredQ: simd_quatd
        if let prev = smoothedQuat {
            if simd_dot(prev.vector, rawQ.vector) < 0 {
                rawQ = simd_quatd(vector: -rawQ.vector)
            }
            let cosHalfTheta = min(1.0, max(-1.0, Double(simd_dot(prev.vector, rawQ.vector))))
            let angularDelta = 2.0 * acos(cosHalfTheta)
            let alpha = min(maxAlpha, max(minAlpha, minAlpha + angularDelta * (1.75 * fovGain)))
            filteredQ = simd_normalize(simd_slerp(prev, rawQ, alpha))
        } else {
            filteredQ = rawQ
        }
        smoothedQuat = filteredQ

        // 3. Transform full right-handed screen basis (Right, Up, Rear-Camera Optical -Z) into NWZ
        let (screenRightDev, screenUpDev) = currentScreenBasisDeviceVectors()
        let opticalAxisDev = SIMD3<Double>(0.0, 0.0, -1.0)

        var rightNWZ = simd_normalize(filteredQ.act(screenRightDev))
        var upNWZ = simd_normalize(filteredQ.act(screenUpDev))
        var forwardNWZ = simd_normalize(filteredQ.act(opticalAxisDev))

        // 4. Apply True North WMM declination (when frame is Magnetic North) + Gyro/Target-Align Azimuth Offset
        var totalEastClockwiseDeg: Double = 0.0
        if activeReferenceFrame == .xMagneticNorthZVertical {
            totalEastClockwiseDeg += wmmDeclinationDegrees
        }
        totalEastClockwiseDeg += gyroAnchorOffsetDegrees + azimuthOffsetDegrees

        if abs(totalEastClockwiseDeg) > 1e-4 {
            // Increasing compass azimuth by +Δ° East corresponds to rotating around -Z (since +X=N, +Y=W => -Y=E)
            let rotZ = simd_quatd(angle: -totalEastClockwiseDeg * (.pi / 180.0), axis: SIMD3<Double>(0.0, 0.0, 1.0))
            rightNWZ = rotZ.act(rightNWZ)
            upNWZ = rotZ.act(upNWZ)
            forwardNWZ = rotZ.act(forwardNWZ)
        }

        // Also compute raw unaligned azimuth (with WMM declination only) for 1-tap Target-Align calibration
        let rawForward = (activeReferenceFrame == .xMagneticNorthZVertical)
            ? simd_quatd(angle: -wmmDeclinationDegrees * (.pi / 180.0), axis: SIMD3<Double>(0.0, 0.0, 1.0)).act(simd_normalize(filteredQ.act(opticalAxisDev)))
            : simd_normalize(filteredQ.act(opticalAxisDev))
        if hypot(rawForward.x, rawForward.y) > 1.0e-3 {
            var rawAz = atan2(-rawForward.y, rawForward.x) * (180.0 / .pi)
            if rawAz < 0.0 { rawAz += 360.0 }
            lastRawTrueAzimuthDegrees = rawAz
        }

        let altRad = asin(min(1.0, max(-1.0, forwardNWZ.z)))
        let altDeg = altRad * (180.0 / .pi)

        // 5. Standby Auto-Lift State Machine (> +15° sustained for >= 250ms)
        let nowUptime = ProcessInfo.processInfo.systemUptime
        if sensorMode == .standbyAutoLift {
            if altDeg >= 15.0 {
                if let since = liftAboveThresholdSince {
                    if (nowUptime - since) >= 0.25 {
                        liftAboveThresholdSince = nil
                        engageFromAutoLift()
                    }
                } else {
                    liftAboveThresholdSince = nowUptime
                }
            } else {
                liftAboveThresholdSince = nil
            }
        } else if sensorMode == .pausedAfterDrag {
            if altDeg < -5.0 && (nowUptime - dragPausedTimestamp) > 1.2 {
                hasLoweredSinceDragPause = true
            } else if hasLoweredSinceDragPause && altDeg >= 20.0 && (nowUptime - dragPausedTimestamp) > 2.0 {
                if let since = liftAboveThresholdSince {
                    if (nowUptime - since) >= 0.30 {
                        liftAboveThresholdSince = nil
                        engageFromAutoLift()
                    }
                } else {
                    liftAboveThresholdSince = nowUptime
                }
            } else {
                liftAboveThresholdSince = nil
            }
        }

        guard sensorMode == .activeLiveSky else { return }

        // 6. Extract Azimuth & Horizon-Relative Roll (while preserving exact 3x3 basis for gimbal-free rendering)
        let horizMag = hypot(forwardNWZ.x, forwardNWZ.y)
        let azRad: Double
        if horizMag > 1.0e-3 {
            var a = atan2(-forwardNWZ.y, forwardNWZ.x)
            if a < 0.0 { a += 2.0 * .pi }
            azRad = a
            lastValidAzimuthRadians = a
        } else {
            let upHoriz = hypot(upNWZ.x, upNWZ.y)
            if upHoriz > 1.0e-3 {
                let sign = forwardNWZ.z >= 0 ? -1.0 : 1.0
                var a = atan2(-sign * upNWZ.y, sign * upNWZ.x)
                if a < 0.0 { a += 2.0 * .pi }
                azRad = a
                lastValidAzimuthRadians = a
            } else {
                azRad = lastValidAzimuthRadians
            }
        }

        let cosAz = cos(azRad), sinAz = sin(azRad)
        let cosAlt = cos(altRad), sinAlt = sin(altRad)
        let right0 = SIMD3<Double>(-sinAz, -cosAz, 0.0)
        let up0 = SIMD3<Double>(-sinAlt * cosAz, sinAlt * sinAz, cosAlt)

        let projUpOnRight = simd_dot(upNWZ, right0)
        let projUpOnUp = simd_dot(upNWZ, up0)
        let rollDeg = atan2(projUpOnRight, projUpOnUp) * (180.0 / .pi)

        currentBasisNWZ = (
            right: (rightNWZ.x, rightNWZ.y, rightNWZ.z),
            up: (upNWZ.x, upNWZ.y, upNWZ.z),
            forward: (forwardNWZ.x, forwardNWZ.y, forwardNWZ.z)
        )
        currentAzimuth = azRad * (180.0 / .pi)
        currentAltitude = max(-89.9, min(90.0, altDeg))
        currentRoll = rollDeg
    }

    private func engageFromAutoLift() {
        sensorMode = .activeLiveSky
        isTracking = true
        startHardwarePipeline(highFrequency: true)
        onAutoLiftEngaged?()
    }

    private func currentScreenBasisDeviceVectors() -> (right: SIMD3<Double>, up: SIMD3<Double>) {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation ?? .portrait
        switch orientation {
        case .landscapeLeft:
            // Device rotated clockwise (home indicator on left): screen-up = -X_dev, screen-right = +Y_dev
            return (SIMD3<Double>(0.0, 1.0, 0.0), SIMD3<Double>(-1.0, 0.0, 0.0))
        case .landscapeRight:
            // Device rotated counter-clockwise (home indicator on right): screen-up = +X_dev, screen-right = -Y_dev
            return (SIMD3<Double>(0.0, -1.0, 0.0), SIMD3<Double>(1.0, 0.0, 0.0))
        case .portraitUpsideDown:
            return (SIMD3<Double>(-1.0, 0.0, 0.0), SIMD3<Double>(0.0, -1.0, 0.0))
        default:
            return (SIMD3<Double>(1.0, 0.0, 0.0), SIMD3<Double>(0.0, 1.0, 0.0))
        }
    }
    #endif

    private func normalizeDegreesSigned(_ deg: Double) -> Double {
        var d = (deg + 180.0).truncatingRemainder(dividingBy: 360.0)
        if d < 0 { d += 360.0 }
        return d - 180.0
    }
}

#if canImport(CoreLocation) && !os(macOS)
extension CosmosMotionService: CLLocationManagerDelegate {
    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if (status == .authorizedWhenInUse || status == .authorizedAlways),
               !self.isGyroLockIgnoreMagnet,
               self.activeReferenceFrame == .xMagneticNorthZVertical,
               (self.sensorMode == .activeLiveSky || self.sensorMode == .standbyAutoLift) {
                self.stopHardwarePipeline()
                self.startHardwarePipeline(highFrequency: self.sensorMode == .activeLiveSky)
            }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let hAcc = newHeading.headingAccuracy
        let magNorm = sqrt(newHeading.x * newHeading.x + newHeading.y * newHeading.y + newHeading.z * newHeading.z)
        Task { @MainActor in
            self.headingAccuracyDegrees = hAcc
            if magNorm > 0.5 && self.magneticFieldMicroTesla < 0.5 {
                self.magneticFieldMicroTesla = magNorm
            }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let lat = loc.coordinate.latitude
        let lon = loc.coordinate.longitude
        let alt = loc.verticalAccuracy >= 0 ? loc.altitude : 50.0
        Task { @MainActor in
            self.updateObserverLocation(latitude: lat, longitude: lon, elevationMeters: alt)
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Gracefully ignore transient CoreLocation heading/fix timeouts; offline WMM-2025 declination remains active.
    }

    nonisolated public func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        // Never interrupt passive browsing; allow native figure-8 prompt only if severely uncalibrated during active AR sky pointing.
        return false
    }
}
#endif
