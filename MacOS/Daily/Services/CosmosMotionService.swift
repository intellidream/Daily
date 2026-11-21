import Foundation
import Combine

public enum CosmosSensorMode: String, Equatable, Sendable {
    case unavailable
    case standbyAutoLift
    case activeLiveSky
    case pausedAfterDrag
    case manualOff
}

@MainActor
public final class CosmosMotionService: ObservableObject {
    public static let shared = CosmosMotionService()

    public typealias BasisNWZ = (
        right: (Double, Double, Double),
        up: (Double, Double, Double),
        forward: (Double, Double, Double)
    )

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

    public private(set) var currentAzimuth: Double = 180.0
    public private(set) var currentAltitude: Double = 45.0
    public private(set) var currentRoll: Double = 0.0
    public private(set) var currentBasisNWZ: BasisNWZ? = nil

    public var onAutoLiftEngaged: (() -> Void)? = nil
    public var onAttitudeSample: ((Double, Double, Double, BasisNWZ) -> Void)? = nil

    private init() {
        self.isAvailable = false
    }

    public func updateObserverLocation(latitude: Double, longitude: Double, elevationMeters: Double = 50.0) {}
    public func updateCurrentFov(_ fovDegrees: Double) {}
    public func beginObservatorySession(autoLiftEnabled: Bool = true) {}
    public func endObservatorySession() { isTracking = false }
    public func startTracking() {}
    public func stopTracking(explicitUserOff: Bool = true) { isTracking = false }
    public func setGyroLockIgnoreMagnet(_ enabled: Bool) {}
    public func alignAzimuth(toTrueTargetAzimuth targetAzimuthDegrees: Double) {}
    public func clearAzimuthAlignmentOffset() {}
}
