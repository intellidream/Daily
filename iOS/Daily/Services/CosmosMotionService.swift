import Foundation
#if canImport(CoreMotion)
import CoreMotion
#endif
import Combine

/// High-frequency (60Hz/120Hz) device motion & gyroscope tracker for AR "Point to Sky" mode.
/// Smoothly maps device attitude quaternions to horizontal azimuth, altitude, and roll.
@MainActor
public final class CosmosMotionService: ObservableObject {
    public static let shared = CosmosMotionService()

    #if canImport(CoreMotion) && !os(macOS)
    private let motionManager = CMMotionManager()
    #endif

    @Published public private(set) var isTracking: Bool = false
    @Published public private(set) var isAvailable: Bool = false
    @Published public private(set) var currentAzimuth: Double = 180.0
    @Published public private(set) var currentAltitude: Double = 45.0
    @Published public private(set) var currentRoll: Double = 0.0

    // Low-pass filter damping factor
    private let alpha: Double = 0.18

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

        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        let referenceFrame: CMAttitudeReferenceFrame = motionManager.isDeviceMotionAvailable ? .xMagneticNorthZVertical : .xArbitraryCorrectedZVertical

        motionManager.startDeviceMotionUpdates(using: referenceFrame, to: .main) { [weak self] motion, _ in
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
        isTracking = false
        #endif
    }

    #if canImport(CoreMotion) && !os(macOS)
    private func processMotion(_ motion: CMDeviceMotion) {
        let attitude = motion.attitude

        // Device in portrait orientation pointing back camera toward the sky:
        // pitch is angle from horizontal (-90 to +90 degrees)
        // yaw is rotation around vertical (-180 to +180 or 0 to 360 degrees)
        // roll is side-to-side tilt
        let pitchDegrees = attitude.pitch * (180.0 / .pi)
        let rollDegrees = attitude.roll * (180.0 / .pi)
        var yawDegrees = attitude.yaw * (180.0 / .pi)

        // Normalize yaw to 0..<360 (compass azimuth: 0 = North, 90 = East, 180 = South, 270 = West)
        if yawDegrees < 0 {
            yawDegrees += 360.0
        }

        // When holding the phone upright and pointing forward at the sky:
        // Device pitch is 90 when vertical (horizon), 0 when flat face-up (zenith)
        // Altitude = 90 - pitch
        let targetAltitude = max(-10.0, min(90.0, 90.0 - abs(pitchDegrees)))
        let targetAzimuth = yawDegrees
        let targetRoll = rollDegrees

        // Low-pass exponential smoothing filter for jitter-free 120Hz rendering
        currentAltitude = currentAltitude + alpha * (targetAltitude - currentAltitude)
        
        // Handle azimuth angle wraparound (0 <-> 360)
        var deltaAz = targetAzimuth - currentAzimuth
        if deltaAz > 180.0 { deltaAz -= 360.0 }
        if deltaAz < -180.0 { deltaAz += 360.0 }
        currentAzimuth = (currentAzimuth + alpha * deltaAz).truncatingRemainder(dividingBy: 360.0)
        if currentAzimuth < 0 { currentAzimuth += 360.0 }

        currentRoll = currentRoll + alpha * (targetRoll - currentRoll)
    }
    #endif
}
