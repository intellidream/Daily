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

/// Ultra-low-latency (100Hz–120Hz) 9-DOF sensor fusion & True North sky tracker for iOS & Foldable devices.
/// Streams attitude samples directly into `@Observable CosmosCameraController` via `onAttitudeSample`
/// (zero `@Published` / `ObservableObject` view-tree invalidations per frame!).
@MainActor
public final class CosmosMotionService: NSObject, ObservableObject {
    public static let shared = CosmosMotionService()

    public typealias BasisNWZ = (
        right: (Double, Double, Double),
        up: (Double, Double, Double),
        forward: (Double, Double, Double)
    )

    #if canImport(CoreMotion) && !os(macOS)
    private let motionManager = CMMotionManager()
    private let headingLocationManager = CLLocationManager()
    private var activeReferenceFrame: CMAttitudeReferenceFrame = .xArbitraryZVertical
    private var orientationObserver: NSObjectProtocol?
    #endif

    // Low-frequency UI diagnostic state (strictly change-guarded — 0 emissions/sec during steady tracking!)
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

    // High-frequency attitude values (NOT @Published — pushed directly to @Observable CosmosCameraController!)
    public private(set) var currentAzimuth: Double = 180.0
    public private(set) var currentAltitude: Double = 45.0
    public private(set) var currentRoll: Double = 0.0
    public private(set) var currentBasisNWZ: BasisNWZ? = nil

    public var onAutoLiftEngaged: (() -> Void)? = nil
    public var onAttitudeSample: ((Double, Double, Double, BasisNWZ) -> Void)? = nil

    private var smoothedQuat: simd_quatd? = nil
    private var lastRawTrueAzimuthDegrees: Double = 180.0
    private var lastValidAzimuthRadians: Double = .pi
    private var gyroAnchorOffsetDegrees: Double = 0.0
    private var currentFovDegrees: Double = 60.0

    private var cachedScreenRightDev = SIMD3<Double>(1.0, 0.0, 0.0)
    private var cachedScreenUpDev = SIMD3<Double>(0.0, 1.0, 0.0)
    private var lastMagUiPublishUptime: TimeInterval = 0.0
    private var latestRawMagMicroTesla: Double = 0.0

    // Auto-lift hysteresis (> +8° sustained for >= 180ms; re-arms after lowering < -5° when pausedAfterDrag)
    private var liftAboveThresholdSince: TimeInterval? = nil
    private var hasLoweredSinceDragPause: Bool = true
    private var dragPausedTimestamp: TimeInterval = 0.0

    private override init() {
        super.init()
        #if canImport(CoreMotion) && !os(macOS)
        let avail = motionManager.isDeviceMotionAvailable
        self.isAvailable = avail
        self.sensorMode = avail ? .standbyAutoLift : .unavailable
        self.headingLocationManager.delegate = self
        self.headingLocationManager.headingFilter = 2.0
        refreshCachedScreenBasisVectors()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCachedScreenBasisVectors()
            }
        }
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
        if abs(wmmDeclinationDegrees - est.declinationDegrees) > 0.05 {
            wmmDeclinationDegrees = est.declinationDegrees
        }
        if abs(expectedFieldMicroTesla - est.expectedIntensityMicroTesla) > 0.2 {
            expectedFieldMicroTesla = est.expectedIntensityMicroTesla
        }
    }

    public func updateCurrentFov(_ fovDegrees: Double) {
        currentFovDegrees = max(0.5, min(130.0, fovDegrees))
    }

    // MARK: - Observatory Session Lifecycle

    public func beginObservatorySession(autoLiftEnabled: Bool = true) {
        #if canImport(CoreMotion) && !os(macOS)
        guard motionManager.isDeviceMotionAvailable else {
            setModeIfChanged(.unavailable)
            return
        }
        refreshCachedScreenBasisVectors()
        liftAboveThresholdSince = nil
        hasLoweredSinceDragPause = true
        if sensorMode != .activeLiveSky {
            setModeIfChanged(autoLiftEnabled ? .standbyAutoLift : .manualOff)
        }
        if sensorMode == .standbyAutoLift || sensorMode == .activeLiveSky {
            startHardwarePipeline()
            setIsTrackingIfChanged(sensorMode == .activeLiveSky)
        }
        #endif
    }

    public func endObservatorySession() {
        stopHardwarePipeline()
        setIsTrackingIfChanged(false)
        currentBasisNWZ = nil
        smoothedQuat = nil
        liftAboveThresholdSince = nil
        if isAvailable {
            setModeIfChanged(.standbyAutoLift)
        }
    }

    public func startTracking() {
        #if canImport(CoreMotion) && !os(macOS)
        guard motionManager.isDeviceMotionAvailable else { return }
        refreshCachedScreenBasisVectors()
        smoothedQuat = nil
        liftAboveThresholdSince = nil
        setModeIfChanged(.activeLiveSky)
        setIsTrackingIfChanged(true)
        startHardwarePipeline()
        #endif
    }

    public func stopTracking(explicitUserOff: Bool = true) {
        #if canImport(CoreMotion) && !os(macOS)
        setIsTrackingIfChanged(false)
        currentBasisNWZ = nil
        if needsCompassCalibration { needsCompassCalibration = false }
        smoothedQuat = nil
        liftAboveThresholdSince = nil
        if explicitUserOff {
            setModeIfChanged(isAvailable ? .manualOff : .unavailable)
            stopHardwarePipeline()
        } else {
            setModeIfChanged(isAvailable ? .pausedAfterDrag : .unavailable)
            hasLoweredSinceDragPause = false
            dragPausedTimestamp = ProcessInfo.processInfo.systemUptime
        }
        #endif
    }

    public func setGyroLockIgnoreMagnet(_ enabled: Bool) {
        #if canImport(CoreMotion) && !os(macOS)
        guard isGyroLockIgnoreMagnet != enabled else { return }
        let targetAzBeforeSwitch = currentAzimuth
        isGyroLockIgnoreMagnet = enabled
        smoothedQuat = nil
        if sensorMode == .activeLiveSky || sensorMode == .standbyAutoLift || sensorMode == .pausedAfterDrag {
            stopHardwarePipeline()
            startHardwarePipeline()
            gyroAnchorOffsetDegrees = enabled
                ? normalizeDegreesSigned(targetAzBeforeSwitch - lastRawTrueAzimuthDegrees)
                : 0.0
        }
        #endif
    }

    public func alignAzimuth(toTrueTargetAzimuth targetAzimuthDegrees: Double) {
        let delta = normalizeDegreesSigned(targetAzimuthDegrees - lastRawTrueAzimuthDegrees - gyroAnchorOffsetDegrees)
        if abs(azimuthOffsetDegrees - delta) > 0.01 {
            azimuthOffsetDegrees = delta
        }
        if hasMagneticInterference && !isGyroLockIgnoreMagnet {
            setGyroLockIgnoreMagnet(true)
            let updatedDelta = normalizeDegreesSigned(targetAzimuthDegrees - lastRawTrueAzimuthDegrees - gyroAnchorOffsetDegrees)
            if abs(azimuthOffsetDegrees - updatedDelta) > 0.01 {
                azimuthOffsetDegrees = updatedDelta
            }
        }
    }

    public func clearAzimuthAlignmentOffset() {
        if azimuthOffsetDegrees != 0.0 {
            azimuthOffsetDegrees = 0.0
        }
    }

    // MARK: - Hardware Sensor Pipeline

    private func setModeIfChanged(_ next: CosmosSensorMode) {
        if sensorMode != next { sensorMode = next }
    }

    private func setIsTrackingIfChanged(_ next: Bool) {
        if isTracking != next { isTracking = next }
    }

    private func stopHardwarePipeline() {
        #if canImport(CoreMotion) && !os(macOS)
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        headingLocationManager.stopUpdatingHeading()
        #endif
    }

    #if canImport(CoreMotion) && !os(macOS)
    private func startHardwarePipeline() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 100.0
        motionManager.showsDeviceMovementDisplay = false

        let available = CMMotionManager.availableAttitudeReferenceFrames()
        let authStatus = headingLocationManager.authorizationStatus
        let isLocAuthorized = (authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways)

        let selectedFrame: CMAttitudeReferenceFrame
        let nextTrueNorth: Bool
        let nextRelGyro: Bool

        if isGyroLockIgnoreMagnet {
            selectedFrame = .xArbitraryZVertical
            nextTrueNorth = false
            nextRelGyro = true
        } else if available.contains(.xTrueNorthZVertical) && isLocAuthorized {
            selectedFrame = .xTrueNorthZVertical
            nextTrueNorth = true
            nextRelGyro = false
            if CLLocationManager.headingAvailable() {
                headingLocationManager.startUpdatingHeading()
            }
            if headingLocationManager.location == nil {
                headingLocationManager.requestLocation()
            }
        } else if available.contains(.xMagneticNorthZVertical) {
            selectedFrame = .xMagneticNorthZVertical
            nextTrueNorth = true
            nextRelGyro = false
            if CLLocationManager.headingAvailable() {
                headingLocationManager.startUpdatingHeading()
            }
            if authStatus == .notDetermined && sensorMode == .activeLiveSky {
                headingLocationManager.requestWhenInUseAuthorization()
            }
        } else if available.contains(.xArbitraryCorrectedZVertical) {
            selectedFrame = .xArbitraryCorrectedZVertical
            nextTrueNorth = false
            nextRelGyro = true
        } else {
            selectedFrame = .xArbitraryZVertical
            nextTrueNorth = false
            nextRelGyro = true
        }

        if isUsingTrueNorth != nextTrueNorth { isUsingTrueNorth = nextTrueNorth }
        if isRelativeGyroOnly != nextRelGyro { isRelativeGyroOnly = nextRelGyro }

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
        let nowUptime = ProcessInfo.processInfo.systemUptime

        // 1. Throttled, Zero-Thrash Magnetic Health Check (only publishes on actual state transition!)
        if !isRelativeGyroOnly {
            let acc = motion.magneticField.accuracy
            let mf = motion.magneticField.field
            let normCalibrated = sqrt(mf.x * mf.x + mf.y * mf.y + mf.z * mf.z)
            if normCalibrated > 0.5 {
                latestRawMagMicroTesla = normCalibrated
            }
            if (nowUptime - lastMagUiPublishUptime) >= 0.5 && abs(latestRawMagMicroTesla - magneticFieldMicroTesla) >= 1.0 {
                lastMagUiPublishUptime = nowUptime
                magneticFieldMicroTesla = latestRawMagMicroTesla
            }
            let highThresh = max(72.0, expectedFieldMicroTesla * 1.48)
            let lowThresh = min(18.0, expectedFieldMicroTesla * 0.42)
            let fieldAnomaly = (latestRawMagMicroTesla > highThresh) ||
                (latestRawMagMicroTesla > 1.0 && latestRawMagMicroTesla < lowThresh)
            let nextInterf = fieldAnomaly || (headingAccuracyDegrees > 30.0)
            let nextCal = (acc == .uncalibrated || acc == .low) ||
                (headingAccuracyDegrees < 0 && normCalibrated < 0.5) ||
                nextInterf
            if hasMagneticInterference != nextInterf { hasMagneticInterference = nextInterf }
            if needsCompassCalibration != nextCal { needsCompassCalibration = nextCal }
        } else {
            if hasMagneticInterference { hasMagneticInterference = false }
            if needsCompassCalibration { needsCompassCalibration = false }
        }

        // 2. Extract hardware-fused quaternion & verify physical gravity orientation
        let cq = motion.attitude.quaternion
        var rawQ = simd_normalize(simd_quatd(ix: cq.x, iy: cq.y, iz: cq.z, r: cq.w))

        let gDev = SIMD3<Double>(motion.gravity.x, motion.gravity.y, motion.gravity.z)
        if abs(gDev.z) < 0.92 {
            let zDirect = rawQ.act(gDev).z
            let zInv = rawQ.inverse.act(gDev).z
            if abs(zInv + 1.0) + 0.08 < abs(zDirect + 1.0) {
                rawQ = rawQ.inverse
            }
        }

        let opticalAxisDev = SIMD3<Double>(0.0, 0.0, -1.0)

        // 3. Zero-Lag Auto-Lift Check directly on unsmoothed `rawQ` (>= +6° sustained for 180ms)
        if sensorMode != .activeLiveSky {
            let rawFwdZ = simd_normalize(rawQ.act(opticalAxisDev)).z
            let rawAltDeg = asin(min(1.0, max(-1.0, rawFwdZ))) * (180.0 / .pi)
            if sensorMode == .standbyAutoLift {
                if rawAltDeg >= 6.0 {
                    if let since = liftAboveThresholdSince {
                        if (nowUptime - since) >= 0.18 {
                            liftAboveThresholdSince = nil
                            smoothedQuat = rawQ
                            engageFromAutoLift()
                        }
                    } else {
                        liftAboveThresholdSince = nowUptime
                    }
                } else {
                    liftAboveThresholdSince = nil
                }
            } else if sensorMode == .pausedAfterDrag {
                if rawAltDeg < -5.0 && (nowUptime - dragPausedTimestamp) > 1.0 {
                    hasLoweredSinceDragPause = true
                } else if hasLoweredSinceDragPause && rawAltDeg >= 14.0 && (nowUptime - dragPausedTimestamp) > 1.5 {
                    if let since = liftAboveThresholdSince {
                        if (nowUptime - since) >= 0.20 {
                            liftAboveThresholdSince = nil
                            smoothedQuat = rawQ
                            engageFromAutoLift()
                        }
                    } else {
                        liftAboveThresholdSince = nowUptime
                    }
                } else {
                    liftAboveThresholdSince = nil
                }
            }
            if sensorMode != .activeLiveSky { return }
        }

        // 4. Responsive Low-Latency 100Hz Quaternion SLERP (1:1 tracking when panning, OIS damping when steady / zoomed)
        // CoreMotion's M-series hardware EKF is already gyro-fused; avoid heavy double-filtering!
        let fovGain = sqrt(max(0.05, min(1.4, currentFovDegrees / 60.0)))
        let minAlpha = max(0.06, 0.30 * fovGain)
        let maxAlpha = max(0.38, min(0.94, 0.88 * fovGain + 0.06))

        let filteredQ: simd_quatd
        if let prev = smoothedQuat {
            if simd_dot(prev.vector, rawQ.vector) < 0 {
                rawQ = simd_quatd(vector: -rawQ.vector)
            }
            let cosHalfTheta = min(1.0, max(-1.0, Double(simd_dot(prev.vector, rawQ.vector))))
            let angularDelta = 2.0 * acos(cosHalfTheta) // radians per 10ms sample
            let alpha = min(maxAlpha, max(minAlpha, minAlpha + angularDelta * (28.0 * fovGain)))
            filteredQ = simd_normalize(simd_slerp(prev, rawQ, alpha))
        } else {
            filteredQ = rawQ
        }
        smoothedQuat = filteredQ

        // 5. Transform cached screen basis (Right, Up, Optical -Z) into NWZ
        var rightNWZ = simd_normalize(filteredQ.act(cachedScreenRightDev))
        var upNWZ = simd_normalize(filteredQ.act(cachedScreenUpDev))
        var forwardNWZ = simd_normalize(filteredQ.act(opticalAxisDev))

        // 6. Apply WMM-2025 declination (if Magnetic frame) + Gyro/Target-Align Azimuth Offset
        var totalEastClockwiseDeg: Double = 0.0
        if activeReferenceFrame == .xMagneticNorthZVertical {
            totalEastClockwiseDeg += wmmDeclinationDegrees
        }
        totalEastClockwiseDeg += gyroAnchorOffsetDegrees + azimuthOffsetDegrees

        if abs(totalEastClockwiseDeg) > 1e-4 {
            let rotZ = simd_quatd(angle: -totalEastClockwiseDeg * (.pi / 180.0), axis: SIMD3<Double>(0.0, 0.0, 1.0))
            rightNWZ = rotZ.act(rightNWZ)
            upNWZ = rotZ.act(upNWZ)
            forwardNWZ = rotZ.act(forwardNWZ)
        }

        let rawForward = (activeReferenceFrame == .xMagneticNorthZVertical)
            ? simd_quatd(angle: -wmmDeclinationDegrees * (.pi / 180.0), axis: SIMD3<Double>(0.0, 0.0, 1.0)).act(simd_normalize(filteredQ.act(opticalAxisDev)))
            : simd_normalize(filteredQ.act(opticalAxisDev))
        if hypot(rawForward.x, rawForward.y) > 1.0e-3 {
            var rawAz = atan2(-rawForward.y, rawForward.x) * (180.0 / .pi)
            if rawAz < 0.0 { rawAz += 360.0 }
            lastRawTrueAzimuthDegrees = rawAz
        }

        let altRad = asin(min(1.0, max(-1.0, forwardNWZ.z)))
        let altDeg = max(-89.9, min(90.0, altRad * (180.0 / .pi)))

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
        let azDeg = azRad * (180.0 / .pi)

        let basis: BasisNWZ = (
            right: (rightNWZ.x, rightNWZ.y, rightNWZ.z),
            up: (upNWZ.x, upNWZ.y, upNWZ.z),
            forward: (forwardNWZ.x, forwardNWZ.y, forwardNWZ.z)
        )
        currentBasisNWZ = basis
        currentAzimuth = azDeg
        currentAltitude = altDeg
        currentRoll = rollDeg

        // Direct zero-allocation callback into @Observable CosmosCameraController!
        onAttitudeSample?(azDeg, altDeg, rollDeg, basis)
    }

    private func engageFromAutoLift() {
        setModeIfChanged(.activeLiveSky)
        setIsTrackingIfChanged(true)
        if headingLocationManager.authorizationStatus == .notDetermined {
            headingLocationManager.requestWhenInUseAuthorization()
        }
        onAutoLiftEngaged?()
    }

    private func refreshCachedScreenBasisVectors() {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation ?? .portrait
        switch orientation {
        case .landscapeLeft:
            cachedScreenRightDev = SIMD3<Double>(0.0, 1.0, 0.0)
            cachedScreenUpDev = SIMD3<Double>(-1.0, 0.0, 0.0)
        case .landscapeRight:
            cachedScreenRightDev = SIMD3<Double>(0.0, -1.0, 0.0)
            cachedScreenUpDev = SIMD3<Double>(1.0, 0.0, 0.0)
        case .portraitUpsideDown:
            cachedScreenRightDev = SIMD3<Double>(-1.0, 0.0, 0.0)
            cachedScreenUpDev = SIMD3<Double>(0.0, -1.0, 0.0)
        default:
            cachedScreenRightDev = SIMD3<Double>(1.0, 0.0, 0.0)
            cachedScreenUpDev = SIMD3<Double>(0.0, 1.0, 0.0)
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
                self.startHardwarePipeline()
            }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let hAcc = newHeading.headingAccuracy
        let magNorm = sqrt(newHeading.x * newHeading.x + newHeading.y * newHeading.y + newHeading.z * newHeading.z)
        Task { @MainActor in
            if abs(self.headingAccuracyDegrees - hAcc) >= 1.0 {
                self.headingAccuracyDegrees = hAcc
            }
            if magNorm > 0.5 && self.latestRawMagMicroTesla < 0.5 {
                self.latestRawMagMicroTesla = magNorm
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

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated public func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        return false
    }
}
#endif
