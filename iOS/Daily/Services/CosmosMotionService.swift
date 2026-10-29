import Foundation
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

/// High-frequency (60Hz–120Hz) device attitude & True North sky tracker for AR "Point to Sky" mode.
/// Projects the back-camera optical axis `[0, 0, -1]` through an adaptive SLERP-filtered quaternion
/// directly into the NWZ (`+X=North, +Y=West, +Z=Up`) horizontal frame — eliminating Euler gimbal lock
/// at the Zenith (`Alt = 90°`) and correcting for WMM magnetic declination via `.xTrueNorthZVertical`.
@MainActor
public final class CosmosMotionService: ObservableObject {
    public static let shared = CosmosMotionService()

    #if canImport(CoreMotion) && !os(macOS)
    private let motionManager = CMMotionManager()
    private let headingLocationManager = CLLocationManager()
    #endif

    @Published public private(set) var isTracking: Bool = false
    @Published public private(set) var isAvailable: Bool = false
    @Published public private(set) var isUsingTrueNorth: Bool = false
    @Published public private(set) var isRelativeGyroOnly: Bool = false
    @Published public private(set) var needsCompassCalibration: Bool = false

    @Published public private(set) var currentAzimuth: Double = 180.0
    @Published public private(set) var currentAltitude: Double = 45.0
    @Published public private(set) var currentRoll: Double = 0.0

    private var smoothedQuat: simd_quatd? = nil
    private var lastValidAzimuthRadians: Double = .pi

    private init() {
        #if canImport(CoreMotion) && !os(macOS)
        self.isAvailable = motionManager.isDeviceMotionAvailable
        #else
        self.isAvailable = false
        #endif
    }

    public func startTracking() {
        #if canImport(CoreMotion) && !os(macOS)
        guard motionManager.isDeviceMotionAvailable, !isTracking else { return }

        smoothedQuat = nil
        motionManager.deviceMotionUpdateInterval = 1.0 / 90.0
        motionManager.showsDeviceMovementDisplay = true

        let available = CMMotionManager.availableAttitudeReferenceFrames()
        let authStatus = headingLocationManager.authorizationStatus
        let canUseTrueNorth = available.contains(.xTrueNorthZVertical) &&
            (authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways)

        let selectedFrame: CMAttitudeReferenceFrame
        if canUseTrueNorth {
            selectedFrame = .xTrueNorthZVertical
            isUsingTrueNorth = true
            isRelativeGyroOnly = false
            headingLocationManager.startUpdatingHeading()
        } else if available.contains(.xMagneticNorthZVertical) {
            selectedFrame = .xMagneticNorthZVertical
            isUsingTrueNorth = false
            isRelativeGyroOnly = false
            if authStatus == .notDetermined {
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

        motionManager.startDeviceMotionUpdates(using: selectedFrame, to: .main) { [weak self] motion, _ in
            guard let self = self, let motion = motion else { return }
            self.processMotion(motion)
        }
        isTracking = true
        #endif
    }

    public func stopTracking() {
        #if canImport(CoreMotion) && !os(macOS)
        guard isTracking else { return }
        motionManager.stopDeviceMotionUpdates()
        headingLocationManager.stopUpdatingHeading()
        isTracking = false
        needsCompassCalibration = false
        smoothedQuat = nil
        #endif
    }

    #if canImport(CoreMotion) && !os(macOS)
    private func processMotion(_ motion: CMDeviceMotion) {
        if !isRelativeGyroOnly {
            let acc = motion.magneticField.accuracy
            needsCompassCalibration = (acc == .uncalibrated || acc == .low)
        } else {
            needsCompassCalibration = false
        }

        let cq = motion.attitude.quaternion
        var rawQ = simd_normalize(simd_quatd(ix: cq.x, iy: cq.y, iz: cq.z, r: cq.w))

        let filteredQ: simd_quatd
        if let prev = smoothedQuat {
            if simd_dot(prev.vector, rawQ.vector) < 0 {
                rawQ = simd_quatd(vector: -rawQ.vector)
            }
            let cosHalfTheta = min(1.0, max(-1.0, Double(simd_dot(prev.vector, rawQ.vector))))
            let angularDelta = 2.0 * acos(cosHalfTheta) // radians
            // Adaptive SLERP: damp micro-tremor when steady (alpha=0.12), track fast sweeps smoothly (up to 0.58)
            let alpha = min(0.58, max(0.12, 0.12 + angularDelta * 1.65))
            filteredQ = simd_normalize(simd_slerp(prev, rawQ, alpha))
        } else {
            filteredQ = rawQ
        }
        smoothedQuat = filteredQ

        // Optical axis of rear camera looking through screen into the sky: -Z in device coordinates.
        let opticalAxisDev = SIMD3<Double>(0.0, 0.0, -1.0)
        let screenUpDev = currentScreenUpDeviceVector()

        // CoreMotion reference frame (.xTrueNorthZVertical / .xMagneticNorthZVertical):
        // +X = North, +Y = West, +Z = Up (Zenith) — identical to CAstronomy's NWZ horizon basis!
        let forwardNWZ = simd_normalize(filteredQ.act(opticalAxisDev))
        let screenUpNWZ = simd_normalize(filteredQ.act(screenUpDev))

        let altRad = asin(min(1.0, max(-1.0, forwardNWZ.z)))
        let horizMag = hypot(forwardNWZ.x, forwardNWZ.y)

        let azRad: Double
        if horizMag > 1.0e-3 {
            var a = atan2(-forwardNWZ.y, forwardNWZ.x)
            if a < 0.0 { a += 2.0 * .pi }
            azRad = a
            lastValidAzimuthRadians = a
        } else {
            // Exactly at Zenith / Nadir: top of screen defines continuous compass bearing without gimbal lock!
            let upHoriz = hypot(screenUpNWZ.x, screenUpNWZ.y)
            if upHoriz > 1.0e-3 {
                // When looking straight up at Zenith, top of phone points opposite to viewer's facing azimuth
                let sign = forwardNWZ.z >= 0 ? -1.0 : 1.0
                var a = atan2(-sign * screenUpNWZ.y, sign * screenUpNWZ.x)
                if a < 0.0 { a += 2.0 * .pi }
                azRad = a
                lastValidAzimuthRadians = a
            } else {
                azRad = lastValidAzimuthRadians
            }
        }

        // Compute horizon-relative roll around forwardNWZ so sky rotates naturally when tilting the phone
        let cosAz = cos(azRad)
        let sinAz = sin(azRad)
        let cosAlt = cos(altRad)
        let sinAlt = sin(altRad)
        // Canonical zero-roll camera basis in NWZ (East = -Y, North = +X, Up = +Z)
        let right0 = SIMD3<Double>(-sinAz, -cosAz, 0.0)
        let up0 = SIMD3<Double>(-sinAlt * cosAz, sinAlt * sinAz, cosAlt)

        let projUpOnRight = simd_dot(screenUpNWZ, right0)
        let projUpOnUp = simd_dot(screenUpNWZ, up0)
        let rollDeg = atan2(projUpOnRight, projUpOnUp) * (180.0 / .pi)

        currentAzimuth = azRad * (180.0 / .pi)
        currentAltitude = max(-85.0, min(90.0, altRad * (180.0 / .pi)))
        currentRoll = rollDeg
    }

    private func currentScreenUpDeviceVector() -> SIMD3<Double> {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation ?? .portrait
        switch orientation {
        case .landscapeLeft:
            return SIMD3<Double>(-1.0, 0.0, 0.0)
        case .landscapeRight:
            return SIMD3<Double>(1.0, 0.0, 0.0)
        case .portraitUpsideDown:
            return SIMD3<Double>(0.0, -1.0, 0.0)
        default:
            return SIMD3<Double>(0.0, 1.0, 0.0)
        }
    }
    #endif
}
