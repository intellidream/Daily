import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Isolated Heading Readout (Reads @Observable Camera Without Rebuilding HUD)

private struct CosmosHeadingReadoutView: View {
    let camera: CosmosCameraController
    let locationName: String
    let isLiveTime: Bool
    let simulationDate: Date
    let playbackSpeed: Double
    let isUsingTrueNorth: Bool
    let isMotionTracking: Bool
    let needsCalibration: Bool
    let palette: CosmosPalette

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 5) {
                Text(locationName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(palette.fgPrimary)
                    .lineLimit(1)

                Text(
                    String(
                        format: "· %03d° %@ · Alt %+d° · %@",
                        Int(camera.effectiveAzimuth.rounded()) % 360,
                        CelestialCoordinates.compassPoint(for: camera.effectiveAzimuth),
                        Int(camera.effectiveAltitude.rounded()),
                        camera.fov < 10.0 ? String(format: "%.1f° FOV", camera.fov) : "\(Int(camera.fov.rounded()))° FOV"
                    )
                )
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(palette.accent)
                .lineLimit(1)
            }

            HStack(spacing: 5) {
                Circle()
                    .fill(isLiveTime ? palette.positive : palette.warning)
                    .frame(width: 5, height: 5)

                Text(statusLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(palette.fgMuted)

                if isMotionTracking {
                    Text(needsCalibration ? "· Calibrate Compass (Figure-8)" : (isUsingTrueNorth ? "· True North AR" : "· Magnetic AR"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(needsCalibration ? palette.warning : palette.accent)
                } else if camera.isZenithPlanisphereLocked {
                    Text("· Zenith Lock")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(palette.accent)
                }
            }
        }
    }

    private var statusLabel: String {
        if isLiveTime {
            return "LIVE EPHEMERIS"
        }
        let formatted = simulationDate.formatted(date: .abbreviated, time: .shortened)
        if playbackSpeed > 0 {
            return "\(formatted) (\(Int(playbackSpeed))×)"
        }
        return formatted
    }
}

#if os(macOS)
// MARK: - Native macOS Scroll-Wheel, Trackpad Magnify & Keyboard Bridge

private struct MacOSSkyInputBridge: NSViewRepresentable {
    var onScrollZoom: (Double, CGPoint, CGSize) -> Void
    var onPanScroll: (Double, Double, CGSize) -> Void
    var onKeyCommand: (String) -> Bool

    func makeNSView(context: Context) -> SkyInputNSView {
        let v = SkyInputNSView()
        v.onScrollZoom = onScrollZoom
        v.onPanScroll = onPanScroll
        v.onKeyCommand = onKeyCommand
        return v
    }

    func updateNSView(_ nsView: SkyInputNSView, context: Context) {
        nsView.onScrollZoom = onScrollZoom
        nsView.onPanScroll = onPanScroll
        nsView.onKeyCommand = onKeyCommand
    }

    final class SkyInputNSView: NSView {
        var onScrollZoom: ((Double, CGPoint, CGSize) -> Void)?
        var onPanScroll: ((Double, Double, CGSize) -> Void)?
        var onKeyCommand: ((String) -> Bool)?
        private var eventMonitor: Any?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil && eventMonitor == nil {
                eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify, .keyDown]) { [weak self] event in
                    guard let self = self, let win = self.window, event.window === win else { return event }
                    switch event.type {
                    case .scrollWheel:
                        let localPt = self.convert(event.locationInWindow, from: nil)
                        guard self.bounds.contains(localPt) else { return event }
                        let flippedPt = CGPoint(x: localPt.x, y: self.bounds.height - localPt.y)
                        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) || !event.hasPreciseScrollingDeltas {
                            let dy = Double(event.scrollingDeltaY)
                            if abs(dy) > 0.01 {
                                let factor = exp(dy * (event.hasPreciseScrollingDeltas ? 0.008 : 0.06))
                                self.onScrollZoom?(factor, flippedPt, self.bounds.size)
                                return nil
                            }
                        } else {
                            let dy = Double(event.scrollingDeltaY)
                            let dx = Double(event.scrollingDeltaX)
                            if abs(dy) > abs(dx) * 1.35 && abs(dy) > 0.2 {
                                let factor = exp(dy * 0.0065)
                                self.onScrollZoom?(factor, flippedPt, self.bounds.size)
                                return nil
                            }
                        }
                        return event

                    case .magnify:
                        let localPt = self.convert(event.locationInWindow, from: nil)
                        guard self.bounds.contains(localPt) else { return event }
                        let flippedPt = CGPoint(x: localPt.x, y: self.bounds.height - localPt.y)
                        let factor = max(0.2, 1.0 + Double(event.magnification))
                        self.onScrollZoom?(factor, flippedPt, self.bounds.size)
                        return nil

                    case .keyDown:
                        if let resp = win.firstResponder, resp is NSTextView || resp is NSTextField {
                            return event
                        }
                        if event.modifierFlags.contains(.command) {
                            return event
                        }
                        if let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty {
                            if event.keyCode == 53 {
                                if self.onKeyCommand?("esc") == true { return nil }
                            } else if self.onKeyCommand?(chars) == true {
                                return nil
                            }
                        }
                        return event

                    default:
                        return event
                    }
                }
            } else if window == nil, let mon = eventMonitor {
                NSEvent.removeMonitor(mon)
                eventMonitor = nil
            }
        }

        deinit {
            if let mon = eventMonitor {
                NSEvent.removeMonitor(mon)
            }
        }
    }
}
#endif

// MARK: - 120Hz Interactive Planetarium & Night Sky Observatory

public struct CosmosDetailView: View {
    @StateObject private var vm = CosmosViewModel()
    @ObservedObject private var liveService = CosmosLiveService.shared
    @ObservedObject private var motionService = CosmosMotionService.shared
    @ObservedObject private var syncService = CosmosSyncService.shared

    public var onNavigateBack: (() -> Void)? = nil
    public var onNavigateToWeather: (() -> Void)? = nil
    public var allowSplitDeckByDefault: Bool = true

    @State private var showingDrawer: Bool = false
    @State private var showingSearchSheet: Bool = false
    @State private var showingLayersSheet: Bool = false
    @State private var showingDateJumpPopover: Bool = false
    @State private var showSplitObservatoryDeck: Bool = true
    @State private var showTimeScrubberBar: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var currentZoomScale: CGFloat = 1.0

    public init(
        onNavigateBack: (() -> Void)? = nil,
        onNavigateToWeather: (() -> Void)? = nil,
        allowSplitDeckByDefault: Bool = true
    ) {
        self.onNavigateBack = onNavigateBack
        self.onNavigateToWeather = onNavigateToWeather
        self.allowSplitDeckByDefault = allowSplitDeckByDefault
    }

    private func triggerHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #elseif canImport(AppKit)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }

    public var body: some View {
        GeometryReader { outerGeo in
            let isExpandedSurface = allowSplitDeckByDefault && outerGeo.size.width >= 840
            HStack(spacing: 0) {
                skyDomeViewport(
                    isSplitActive: isExpandedSurface && showSplitObservatoryDeck,
                    canToggleSplit: isExpandedSurface
                )
                .frame(
                    width: (isExpandedSurface && showSplitObservatoryDeck)
                        ? round(outerGeo.size.width * 0.58)
                        : outerGeo.size.width,
                    height: outerGeo.size.height
                )

                if isExpandedSurface && showSplitObservatoryDeck {
                    Rectangle()
                        .fill(vm.palette.border)
                        .frame(width: 1)
                        .ignoresSafeArea()

                    observatorySideDeck
                        .frame(
                            width: max(320, outerGeo.size.width - round(outerGeo.size.width * 0.58) - 1),
                            height: outerGeo.size.height
                        )
                        .background(
                            LinearGradient(
                                colors: [vm.palette.sheetBackgroundTop, vm.palette.sheetBackgroundBottom],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
        }
        .preferredColorScheme(.dark)
        #if os(iOS)
        .statusBarHidden(vm.isNightVisionMode)
        #endif
        .sheet(isPresented: $showingSearchSheet) {
            cosmosSearchSheet
        }
        .sheet(isPresented: $showingDrawer) {
            tonightsBestSheet
        }
        .sheet(isPresented: $showingLayersSheet) {
            layersAndDateSheet
        }
        .onAppear {
            vm.onObservatoryAppear()
        }
        .onDisappear {
            vm.onObservatoryDisappear()
        }
        .task {
            await liveService.refreshCosmosData(latitude: vm.observerLatitude, longitude: vm.observerLongitude)
        }
    }

    // MARK: - Interactive Sky Dome Viewport

    @ViewBuilder
    private func skyDomeViewport(isSplitActive: Bool, canToggleSplit: Bool) -> some View {
        GeometryReader { geometry in
            let frameInterval: Double = (vm.isMotionTrackingEnabled || vm.playbackSpeedMultiplier > 0) ? (1.0 / 90.0) : (1.0 / 30.0)
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                #if os(macOS)
                MacOSSkyInputBridge(
                    onScrollZoom: { factor, cursorPt, viewSize in
                        vm.handleZoom(deltaMagnification: factor, anchorPoint: cursorPt, viewportSize: viewSize)
                    },
                    onPanScroll: { dx, dy, viewSize in
                        vm.handlePan(deltaX: dx, deltaY: dy, viewportWidth: Double(viewSize.width), viewportHeight: Double(viewSize.height))
                    },
                    onKeyCommand: { key in
                        handleDesktopShortcut(key)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif

                TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
                    let scene = vm.projectSkyScene(
                        in: geometry.size,
                        renderTimestamp: timeline.date.timeIntervalSinceReferenceDate
                    )
                    ZStack(alignment: .topLeading) {
                        Canvas { context, size in
                            drawSkyScene(context: context, size: size, scene: scene)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        #if os(macOS)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let pt):
                                vm.camera.hoverLocation = pt
                            case .ended:
                                vm.camera.hoverLocation = nil
                            }
                        }
                        #endif
                        .gesture(
                            DragGesture(minimumDistance: 3)
                                .onChanged { value in
                                    let dx = Double(value.translation.width - dragOffset.width)
                                    let dy = Double(value.translation.height - dragOffset.height)
                                    dragOffset = value.translation
                                    vm.handlePan(
                                        deltaX: dx,
                                        deltaY: dy,
                                        viewportWidth: Double(geometry.size.width),
                                        viewportHeight: Double(geometry.size.height)
                                    )
                                }
                                .onEnded { _ in
                                    dragOffset = .zero
                                }
                        )
                        .simultaneousGesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    let delta = value.magnification / currentZoomScale
                                    currentZoomScale = value.magnification
                                    vm.handleZoom(
                                        deltaMagnification: Double(delta),
                                        anchorPoint: value.startLocation,
                                        viewportSize: geometry.size
                                    )
                                }
                                .onEnded { _ in
                                    currentZoomScale = 1.0
                                }
                        )
                        .onTapGesture { location in
                            let tapScene = vm.projectSkyScene(in: geometry.size)
                            if let hit = vm.hitTestTarget(at: location, in: tapScene) {
                                triggerHaptic()
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                    vm.selectedTarget = hit
                                }
                            } else if vm.selectedTarget != nil {
                                withAnimation(.spring(response: 0.28)) {
                                    vm.selectedTarget = nil
                                }
                            }
                        }

                        ForEach(scene.accessibilityLandmarks) { lm in
                            Color.clear
                                .frame(width: lm.frame.width, height: lm.frame.height)
                                .position(x: lm.frame.midX, y: lm.frame.midY)
                                .accessibilityElement()
                                .accessibilityLabel(lm.label)
                                .accessibilityValue(lm.valueSummary)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction {
                                    vm.centerOn(target: lm.target)
                                }
                        }
                    }
                }

                VStack(spacing: 8) {
                    topHUDBar(isSplitActive: isSplitActive, canToggleSplit: canToggleSplit)
                    zoomPresetsStrip

                    if let banner = vm.statusBannerMessage {
                        Text(banner)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(vm.palette.fgPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(vm.palette.cardBackground)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(vm.palette.border, lineWidth: 1))
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                VStack(spacing: 10) {
                    Spacer()

                    if let target = vm.selectedTarget {
                        targetInspectorCard(target: target)
                            .padding(.horizontal, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    bottomControlBar(isSplitActive: isSplitActive)
                }
            }
        }
    }

    #if os(macOS)
    private func handleDesktopShortcut(_ key: String) -> Bool {
        switch key {
        case " ":
            vm.cyclePlaybackSpeed()
            return true
        case "[":
            vm.adjustSimulationTime(byHours: -1.0)
            return true
        case "]":
            vm.adjustSimulationTime(byHours: 1.0)
            return true
        case "l":
            vm.resetToLive()
            return true
        case "n":
            withAnimation(.easeInOut(duration: 0.2)) { vm.isNightVisionMode.toggle() }
            return true
        case "g":
            vm.showAltAzGrid.toggle()
            return true
        case "c":
            vm.showConstellationLines.toggle()
            return true
        case "a":
            vm.showAtmosphere.toggle()
            return true
        case "z":
            vm.camera.isZenithPlanisphereLocked.toggle()
            return true
        case "=", "+":
            vm.handleZoom(deltaMagnification: 1.30)
            return true
        case "-", "_":
            vm.handleZoom(deltaMagnification: 0.77)
            return true
        case "esc":
            if vm.selectedTarget != nil {
                vm.selectedTarget = nil
                return true
            }
            return false
        default:
            return false
        }
    }
    #endif

    // MARK: - Top HUD Bar & Zoom Strip

    @ViewBuilder
    private func topHUDBar(isSplitActive: Bool, canToggleSplit: Bool) -> some View {
        let p = vm.palette
        HStack(alignment: .center, spacing: 8) {
            if let onNavigateBack = onNavigateBack {
                Button {
                    triggerHaptic()
                    onNavigateBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(p.fgPrimary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(p.pillBackground))
                        .overlay(Circle().strokeBorder(p.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Back to Dashboard")
            }

            if let onNavigateToWeather = onNavigateToWeather {
                Button {
                    triggerHaptic()
                    onNavigateToWeather()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cloud.sun.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Weather")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(p.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(p.pillBackground))
                    .overlay(Capsule().strokeBorder(p.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 4)

            CosmosHeadingReadoutView(
                camera: vm.camera,
                locationName: vm.observerLocationName,
                isLiveTime: vm.isLiveTime,
                simulationDate: vm.simulationDate,
                playbackSpeed: vm.playbackSpeedMultiplier,
                isUsingTrueNorth: motionService.isUsingTrueNorth,
                isMotionTracking: vm.isMotionTrackingEnabled,
                needsCalibration: motionService.needsCompassCalibration,
                palette: p
            )

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                Button {
                    triggerHaptic()
                    withAnimation(.easeInOut(duration: 0.22)) {
                        vm.isNightVisionMode.toggle()
                    }
                } label: {
                    Image(systemName: vm.isNightVisionMode ? "eye.fill" : "eye")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(vm.isNightVisionMode ? .black : p.primaryRed)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(vm.isNightVisionMode ? p.primaryRed : p.pillBackground))
                        .overlay(Circle().strokeBorder(p.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Red Night-Vision Mode (N)")

                if motionService.isAvailable {
                    Button {
                        triggerHaptic()
                        withAnimation(.spring(response: 0.3)) {
                            vm.toggleMotionTracking()
                        }
                    } label: {
                        Image(systemName: vm.isMotionTrackingEnabled ? "dot.scope" : "gyroscope")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(vm.isMotionTrackingEnabled ? .black : p.accent)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(vm.isMotionTrackingEnabled ? p.accent : p.pillBackground))
                            .overlay(Circle().strokeBorder(p.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Point-to-Sky AR Gyroscope")
                }

                Button {
                    triggerHaptic()
                    showingLayersSheet = true
                } label: {
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(p.fgPrimary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(p.pillBackground))
                        .overlay(Circle().strokeBorder(p.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Sky Layers, Grids & Date Jump")

                if canToggleSplit {
                    Button {
                        triggerHaptic()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            showSplitObservatoryDeck.toggle()
                        }
                    } label: {
                        Image(systemName: isSplitActive ? "arrow.up.left.and.arrow.down.right" : "sidebar.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(p.accent)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(p.pillBackground))
                            .overlay(Circle().strokeBorder(p.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(isSplitActive ? "Full-Bleed Sky Dome" : "Show Observatory Deck (58% / 42%)")
                }

                Button {
                    triggerHaptic()
                    showingSearchSheet = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(p.fgPrimary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(p.pillBackground))
                        .overlay(Circle().strokeBorder(p.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Search Stars, Planets & Deep-Sky Catalog")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var zoomPresetsStrip: some View {
        let p = vm.palette
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(CosmosZoomPreset.allCases) { preset in
                    let isSelected = abs(vm.camera.fov - preset.fovDegrees) < max(1.5, preset.fovDegrees * 0.15)
                    Button {
                        triggerHaptic()
                        vm.applyZoomPreset(preset)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: preset.iconName)
                                .font(.system(size: 10, weight: .semibold))
                            Text(preset.rawValue)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(isSelected ? .black : p.fgSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(isSelected ? p.accent : p.cardBackground))
                        .overlay(Capsule().strokeBorder(p.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    triggerHaptic()
                    vm.showAtmosphere.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: vm.showAtmosphere ? "sun.haze.fill" : "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                        Text(vm.showAtmosphere ? "Atmosphere" : "No Atmos")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(vm.showAtmosphere ? p.accent : p.fgMuted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(p.cardBackground))
                    .overlay(Capsule().strokeBorder(p.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    triggerHaptic()
                    vm.camera.isZenithPlanisphereLocked.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.dashed")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Planisphere")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(vm.camera.isZenithPlanisphereLocked ? .black : p.fgSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(vm.camera.isZenithPlanisphereLocked ? p.accent : p.cardBackground))
                    .overlay(Capsule().strokeBorder(p.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Bottom Observatory & Continuous Time Machine Console

    @ViewBuilder
    private func bottomControlBar(isSplitActive: Bool) -> some View {
        let p = vm.palette
        VStack(spacing: 8) {
            if showTimeScrubberBar {
                VStack(spacing: 6) {
                    HStack {
                        Text("TIME MACHINE (±12H SCRUBBER)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(p.fgMuted)
                        Spacer()
                        Text(vm.simulationDate.formatted(date: .abbreviated, time: .standard))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(p.accent)
                        Button {
                            showingLayersSheet = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 10))
                                Text("1900–2100")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(p.fgPrimary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(p.pillBackground))
                        }
                        .buttonStyle(.plain)
                    }

                    Slider(
                        value: Binding(
                            get: { vm.scrubberMinutesOffset },
                            set: { newVal in
                                if Int(newVal / 60.0) != Int(vm.scrubberMinutesOffset / 60.0) {
                                    triggerHaptic()
                                }
                                vm.scrubTimeOffset(minutes: newVal)
                            }
                        ),
                        in: -720...720
                    )
                    .tint(p.accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 16).fill(p.cardBackground))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(p.border, lineWidth: 1))
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 8) {
                Button {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        showTimeScrubberBar.toggle()
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(showTimeScrubberBar ? .black : p.accent)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(showTimeScrubberBar ? p.accent : p.pillBackground))
                }
                .buttonStyle(.plain)
                .help("Toggle Continuous Time Machine Slider")

                Button {
                    triggerHaptic()
                    vm.adjustSimulationTime(byHours: -1.0)
                } label: {
                    Text("−1h")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(p.fgPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(p.pillBackground))
                }
                .buttonStyle(.plain)

                Button {
                    triggerHaptic()
                    vm.cyclePlaybackSpeed()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: vm.playbackSpeedMultiplier > 0 ? "forward.end.alt.fill" : "play.fill")
                            .font(.system(size: 9, weight: .bold))
                        if vm.playbackSpeedMultiplier > 0 {
                            Text("\(Int(vm.playbackSpeedMultiplier))×")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                        }
                    }
                    .foregroundColor(vm.playbackSpeedMultiplier > 0 ? .black : p.fgPrimary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(vm.playbackSpeedMultiplier > 0 ? p.accent : p.pillBackground))
                }
                .buttonStyle(.plain)
                .help("Play / Speed Up Sky Rotation (Space)")

                Button {
                    triggerHaptic()
                    vm.resetToLive()
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(vm.isLiveTime ? p.positive : p.warning)
                            .frame(width: 6, height: 6)
                        Text(vm.isLiveTime ? "LIVE" : "NOW")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(vm.isLiveTime ? p.positive : p.fgPrimary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(p.pillBackground))
                }
                .buttonStyle(.plain)

                Button {
                    triggerHaptic()
                    vm.adjustSimulationTime(byHours: 1.0)
                } label: {
                    Text("+1h")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(p.fgPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(p.pillBackground))
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    Button {
                        triggerHaptic()
                        vm.handleZoom(deltaMagnification: 1.32)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(p.fgPrimary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(p.pillBackground))
                    }
                    .buttonStyle(.plain)

                    Button {
                        triggerHaptic()
                        vm.handleZoom(deltaMagnification: 0.76)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(p.fgPrimary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(p.pillBackground))
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 4)

                if !isSplitActive {
                    Button {
                        triggerHaptic()
                        showingDrawer = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                            Text("Tonight (\(vm.stargazingScore))")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(p.accent)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(p.pillBackground))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(p.cardBackground))
            .overlay(Capsule().strokeBorder(p.border, lineWidth: 1))
            .padding(.leading, 16)
            .padding(.trailing, isSplitActive ? 16 : 84)
            .padding(.bottom, 22)
        }
    }

    // MARK: - 120Hz Hardware-Accelerated Sky Dome Renderer

    private func drawSkyScene(context: GraphicsContext, size: CGSize, scene: ProjectedSkyScene) {
        let p = vm.palette

        drawSkyAtmosphere(context: context, size: size, scene: scene, palette: p)

        for mw in scene.milkyWayRings {
            guard mw.points.count >= 3 else { continue }
            var path = Path()
            path.move(to: mw.points[0])
            for pt in mw.points.dropFirst() {
                path.addLine(to: pt)
            }
            path.closeSubpath()
            let baseOpacity = 0.020 + Double(mw.level) * 0.011
            let mwColor = vm.isNightVisionMode
                ? p.primaryRed.opacity(baseOpacity * 1.1)
                : Color(red: 0.62, green: 0.70, blue: 0.96).opacity(baseOpacity)
            context.fill(path, with: .color(mwColor))
        }

        let gridStroke = StrokeStyle(lineWidth: 0.7, dash: [3, 4])
        if !scene.altAzGridPolylines.isEmpty {
            let col = vm.isNightVisionMode ? p.mutedRed.opacity(0.32) : ThemeColors.accentCyan.opacity(0.16)
            for poly in scene.altAzGridPolylines {
                strokePolyline(poly, in: context, color: col, style: gridStroke)
            }
        }
        if !scene.raDecGridPolylines.isEmpty {
            let col = vm.isNightVisionMode ? p.mutedRed.opacity(0.28) : Color(red: 0.55, green: 0.65, blue: 1.0).opacity(0.16)
            for poly in scene.raDecGridPolylines {
                strokePolyline(poly, in: context, color: col, style: gridStroke)
            }
        }
        if !scene.borderPolylines.isEmpty {
            let col = vm.isNightVisionMode ? p.mutedRed.opacity(0.35) : Color.white.opacity(0.12)
            for poly in scene.borderPolylines {
                strokePolyline(poly, in: context, color: col, style: StrokeStyle(lineWidth: 0.8, dash: [2, 3]))
            }
        }
        if scene.eclipticPolyline.count >= 2 {
            let col = vm.isNightVisionMode ? p.softRed.opacity(0.45) : Color(hex: "#FFB300").opacity(0.38)
            strokePolyline(scene.eclipticPolyline, in: context, color: col, style: StrokeStyle(lineWidth: 1.1, dash: [6, 4]))
        }

        if !scene.constellationSegments.isEmpty {
            var cPath = Path()
            for seg in scene.constellationSegments {
                cPath.move(to: CGPoint(x: seg.x1, y: seg.y1))
                cPath.addLine(to: CGPoint(x: seg.x2, y: seg.y2))
            }
            let cCol = vm.isNightVisionMode ? p.primaryRed.opacity(0.36) : Color(red: 0.45, green: 0.76, blue: 1.0).opacity(0.28)
            context.stroke(cPath, with: .color(cCol), style: StrokeStyle(lineWidth: 1.05, lineCap: .round))
        }
        if !scene.asterismSegments.isEmpty {
            var aPath = Path()
            for seg in scene.asterismSegments {
                aPath.move(to: CGPoint(x: seg.x1, y: seg.y1))
                aPath.addLine(to: CGPoint(x: seg.x2, y: seg.y2))
            }
            let aCol = vm.isNightVisionMode ? p.softRed.opacity(0.28) : Color(hex: "#FFD54F").opacity(0.22)
            context.stroke(aPath, with: .color(aCol), style: StrokeStyle(lineWidth: 0.95, lineCap: .round, dash: [4, 3]))
        }

        for lbl in scene.constellationLabels {
            let text = Text(lbl.record.nameEn.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(vm.isNightVisionMode ? p.primaryRed.opacity(0.62) : ThemeColors.accentCyan.opacity(0.55))
            context.draw(text, at: CGPoint(x: lbl.screenX, y: lbl.screenY))
        }

        for star in scene.stars {
            let starCol = vm.isNightVisionMode
                ? p.primaryRed.opacity(star.alpha)
                : Color(red: star.r, green: star.g, blue: star.b).opacity(star.alpha)
            let rect = CGRect(
                x: star.x - star.diameter * 0.5,
                y: star.y - star.diameter * 0.5,
                width: star.diameter,
                height: star.diameter
            )
            if star.magnitude < 1.8 {
                let halo = rect.insetBy(dx: -star.diameter * 0.95, dy: -star.diameter * 0.95)
                context.fill(Path(ellipseIn: halo), with: .color(starCol.opacity(0.20)))
            }
            context.fill(Path(ellipseIn: rect), with: .color(starCol))

            if let name = star.label {
                let txt = Text(name)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(vm.isNightVisionMode ? p.softRed.opacity(0.82) : Color.white.opacity(0.76))
                context.draw(txt, at: CGPoint(x: star.x, y: star.y - star.diameter * 0.5 - 7))
            }
        }

        for item in scene.dsos {
            drawDSOSymbol(context: context, item: item, palette: p)
        }

        for rad in scene.meteorRadiants {
            let pt = CGPoint(x: rad.screenX, y: rad.screenY)
            let col = vm.isNightVisionMode
                ? p.primaryRed.opacity(rad.isActiveTonight ? 0.85 : 0.45)
                : (rad.isActiveTonight ? Color(hex: "#80DEEA") : Color.white.opacity(0.42))
            var burst = Path()
            for a in stride(from: 0, to: 360, by: 45) {
                let radA = Double(a) * (.pi / 180.0)
                burst.move(to: CGPoint(x: pt.x + cos(radA) * 4, y: pt.y + sin(radA) * 4))
                burst.addLine(to: CGPoint(x: pt.x + cos(radA) * 9, y: pt.y + sin(radA) * 9))
            }
            context.stroke(burst, with: .color(col), style: StrokeStyle(lineWidth: 1.0))
            if rad.isActiveTonight || vm.camera.fov < 45.0 {
                let label = Text("\(rad.shower.name) (ZHR \(rad.shower.zhr))")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(col)
                context.draw(label, at: CGPoint(x: pt.x, y: pt.y + 14))
            }
        }

        for planet in scene.planets {
            drawSolarSystemBody(context: context, planet: planet, palette: p)
        }

        if let iss = scene.issState {
            if iss.trajectoryPoints.count >= 2 {
                for i in 0..<(iss.trajectoryPoints.count - 1) {
                    let a = iss.trajectoryPoints[i]
                    let b = iss.trajectoryPoints[i + 1]
                    let dx = a.point.x - b.point.x, dy = a.point.y - b.point.y
                    guard (dx * dx + dy * dy) < pow(max(size.width, size.height) * 0.5, 2.0) else { continue }
                    var seg = Path()
                    seg.move(to: a.point)
                    seg.addLine(to: b.point)
                    let col = vm.isNightVisionMode
                        ? p.primaryRed.opacity(a.isSunlit ? 0.75 : 0.32)
                        : (a.isSunlit ? Color(hex: "#FFD54F").opacity(0.80) : Color.white.opacity(0.28))
                    let style = a.isSunlit
                        ? StrokeStyle(lineWidth: 1.5, lineCap: .round)
                        : StrokeStyle(lineWidth: 1.1, dash: [3, 4])
                    context.stroke(seg, with: .color(col), style: style)
                }
            }
            let pt = CGPoint(x: iss.screenX, y: iss.screenY)
            let issCol = vm.isNightVisionMode ? p.primaryRed : (iss.position.isSunlit ? Color(hex: "#FF5E7E") : Color.white.opacity(0.65))
            let ring = CGRect(x: pt.x - 9, y: pt.y - 9, width: 18, height: 18)
            context.stroke(Path(ellipseIn: ring), with: .color(issCol), style: StrokeStyle(lineWidth: 1.5))
            context.fill(Path(ellipseIn: CGRect(x: pt.x - 3.5, y: pt.y - 3.5, width: 7, height: 7)), with: .color(issCol))
            let issLbl = Text(iss.position.isSunlit ? "ISS (Sunlit)" : "ISS (Umbra)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(issCol)
            context.draw(issLbl, at: CGPoint(x: pt.x, y: pt.y - 15))
        }

        if let sel = vm.selectedTarget {
            let live = vm.liveMetrics(for: sel)
            if let sp = scene.matrix.projectHorizontal(azimuthDegrees: live.azimuthDegrees, altitudeDegrees: live.altitudeDegrees, margin: 20.0), sp.isVisible {
                let rRect = CGRect(x: sp.x - 16, y: sp.y - 16, width: 32, height: 32)
                context.stroke(
                    Path(ellipseIn: rRect),
                    with: .color(p.accent),
                    style: StrokeStyle(lineWidth: 1.6, dash: [5, 3])
                )
            }
        }

        if vm.showHorizonCompass {
            drawHorizonAndCompass(context: context, size: size, scene: scene, palette: p)
        }

        if let guide = scene.targetGuide {
            drawTargetGuideArrow(context: context, size: size, guide: guide, palette: p)
        }

        if let hover = scene.hoverSummary {
            let pt = hover.point
            let ret = CGRect(x: pt.x - 8, y: pt.y - 8, width: 16, height: 16)
            context.stroke(Path(ellipseIn: ret), with: .color(p.accent.opacity(0.65)), style: StrokeStyle(lineWidth: 1.0))
            let labelPos = CGPoint(x: min(size.width - 110, max(110, pt.x)), y: max(68, pt.y - 22))
            let txt = Text(hover.title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(p.fgPrimary)
            context.draw(txt, at: labelPos)
        }
    }

    private func drawSkyAtmosphere(context: GraphicsContext, size: CGSize, scene: ProjectedSkyScene, palette: CosmosPalette) {
        let fullRect = CGRect(origin: .zero, size: size)
        if vm.isNightVisionMode {
            let grad = Gradient(colors: [Color(hex: "#1C0204"), Color(hex: "#0A0001"), .black])
            context.fill(
                Path(fullRect),
                with: .radialGradient(grad, center: CGPoint(x: size.width * 0.5, y: size.height * 0.45), startRadius: 20, endRadius: max(size.width, size.height) * 0.8)
            )
            return
        }

        guard vm.showAtmosphere else {
            let grad = Gradient(colors: [Color(hex: "#060B19"), Color(hex: "#02040A"), .black])
            context.fill(Path(fullRect), with: .linearGradient(grad, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            return
        }

        let sunAlt = scene.sunAltitudeDegrees
        let topCol: Color
        let botCol: Color
        if sunAlt > 4.0 {
            topCol = Color(red: 0.04, green: 0.12, blue: 0.30)
            botCol = Color(red: 0.10, green: 0.25, blue: 0.48)
        } else if sunAlt > -6.0 {
            let t = (sunAlt + 6.0) / 10.0
            topCol = Color(red: 0.03 + 0.02 * t, green: 0.06 + 0.08 * t, blue: 0.16 + 0.16 * t)
            botCol = Color(red: 0.12 + 0.12 * t, green: 0.11 + 0.15 * t, blue: 0.22 + 0.24 * t)
        } else if sunAlt > -18.0 {
            let t = (sunAlt + 18.0) / 12.0
            topCol = Color(red: 0.02 + 0.03 * t, green: 0.04 + 0.06 * t, blue: 0.10 + 0.18 * t)
            botCol = Color(red: 0.05 + 0.16 * t, green: 0.07 + 0.10 * t, blue: 0.15 + 0.16 * t)
        } else {
            topCol = Color(hex: "#050A1B")
            botCol = Color(hex: "#02040B")
        }

        context.fill(
            Path(fullRect),
            with: .linearGradient(Gradient(colors: [topCol, botCol]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
        )

        if sunAlt > -14.0, let sunPt = scene.sunScreenPoint {
            let glowCol = sunAlt > 0 ? Color(hex: "#FFF3C4").opacity(0.32) : Color(hex: "#FF8A50").opacity(0.24)
            context.fill(
                Path(fullRect),
                with: .radialGradient(
                    Gradient(colors: [glowCol, .clear]),
                    center: sunPt,
                    startRadius: 8,
                    endRadius: min(size.width, size.height) * 0.55
                )
            )
        }
    }

    private func drawDSOSymbol(context: GraphicsContext, item: ProjectedDSO, palette: CosmosPalette) {
        let pt = CGPoint(x: item.screenX, y: item.screenY)
        let r = item.radiusPx
        let col: Color = vm.isNightVisionMode
            ? palette.primaryRed.opacity(0.78)
            : {
                switch item.dso.type {
                case .galaxy: return Color(hex: "#FF80AB").opacity(0.82)
                case .emissionNebula, .reflectionNebula, .supernovaRemnant: return Color(hex: "#EA80FC").opacity(0.82)
                case .planetaryNebula: return Color(hex: "#64FFDA").opacity(0.85)
                case .globularCluster, .openCluster: return Color(hex: "#FFD54F").opacity(0.82)
                default: return ThemeColors.accentPink.opacity(0.75)
                }
            }()

        context.drawLayer { layer in
            layer.translateBy(x: pt.x, y: pt.y)
            if item.dso.type == .galaxy {
                layer.rotate(by: .degrees(-item.positionAngleDeg))
                let w = r * 2.1
                let h = max(5.0, w * item.aspectRatio)
                let rect = CGRect(x: -w * 0.5, y: -h * 0.5, width: w, height: h)
                layer.fill(Path(ellipseIn: rect), with: .color(col.opacity(0.14)))
                layer.stroke(Path(ellipseIn: rect), with: .color(col), style: StrokeStyle(lineWidth: 1.15))
            } else if item.dso.type == .globularCluster {
                let rect = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
                layer.stroke(Path(ellipseIn: rect), with: .color(col), style: StrokeStyle(lineWidth: 1.15))
                var cross = Path()
                cross.move(to: CGPoint(x: -r, y: 0))
                cross.addLine(to: CGPoint(x: r, y: 0))
                cross.move(to: CGPoint(x: 0, y: -r))
                cross.addLine(to: CGPoint(x: 0, y: r))
                layer.stroke(cross, with: .color(col.opacity(0.75)), style: StrokeStyle(lineWidth: 0.9))
            } else if item.dso.type == .openCluster {
                let rect = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
                layer.stroke(Path(ellipseIn: rect), with: .color(col), style: StrokeStyle(lineWidth: 1.2, dash: [2, 2.5]))
            } else {
                let rect = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
                layer.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(col.opacity(0.12)))
                layer.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(col), style: StrokeStyle(lineWidth: 1.1))
            }
        }

        if vm.camera.fov <= 45.0 || item.dso.visualMagnitude <= 6.2 {
            let lbl = Text(item.dso.id)
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundColor(col)
            context.draw(lbl, at: CGPoint(x: pt.x, y: pt.y + r + 8))
        }
    }

    private func drawSolarSystemBody(context: GraphicsContext, planet: ProjectedPlanet, palette: CosmosPalette) {
        let pt = CGPoint(x: planet.screenX, y: planet.screenY)
        let rad = planet.diameter * 0.5
        let rect = CGRect(x: pt.x - rad, y: pt.y - rad, width: planet.diameter, height: planet.diameter)

        for gm in planet.galileanMoons where !gm.isFrontOfPlanet {
            drawGalileanMoonDot(context: context, moon: gm, palette: palette)
        }

        if planet.body == .moon {
            let darkEarthshine = vm.isNightVisionMode ? Color(hex: "#2B0307") : Color(hex: "#1B2234")
            let litLunar = vm.isNightVisionMode ? palette.primaryRed : Color(hex: "#F6F1DF")
            context.fill(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(litLunar.opacity(0.18)))
            context.fill(Path(ellipseIn: rect), with: .color(darkEarthshine))

            let k = max(0.0, min(1.0, vm.currentMoonPhase.illuminatedFraction))
            if k > 0.01 {
                context.drawLayer { layer in
                    layer.translateBy(x: pt.x, y: pt.y)
                    layer.rotate(by: .degrees(planet.brightLimbAngleDeg - 90.0))
                    let terminatorPath = sphericalPhasePath(radius: rad, illuminatedFraction: k)
                    layer.fill(terminatorPath, with: .color(litLunar))
                }
            }
            context.stroke(Path(ellipseIn: rect), with: .color(litLunar.opacity(0.45)), style: StrokeStyle(lineWidth: 0.8))
        } else if planet.body == .sun {
            let sunCol = vm.isNightVisionMode ? palette.primaryRed : Color(hex: "#FFD600")
            context.fill(Path(ellipseIn: rect.insetBy(dx: -8, dy: -8)), with: .color(sunCol.opacity(0.28)))
            context.fill(Path(ellipseIn: rect), with: .color(sunCol))
        } else {
            let col = vm.isNightVisionMode ? palette.primaryRed : Color(hex: planet.body.baseColorHex)

            if planet.body == .saturn {
                context.drawLayer { layer in
                    layer.translateBy(x: pt.x, y: pt.y)
                    let tiltSin = max(0.14, min(0.85, abs(sin(planet.saturnRingTiltDeg * (.pi / 180.0)))))
                    let outerW = planet.diameter * 2.25
                    let outerH = outerW * tiltSin
                    let ringRect = CGRect(x: -outerW * 0.5, y: -outerH * 0.5, width: outerW, height: outerH)
                    layer.stroke(Path(ellipseIn: ringRect), with: .color(col.opacity(0.85)), style: StrokeStyle(lineWidth: max(1.6, rad * 0.24)))
                }
            }

            context.fill(Path(ellipseIn: rect.insetBy(dx: -2.5, dy: -2.5)), with: .color(col.opacity(0.26)))
            if (planet.body == .venus || planet.body == .mercury) && planet.diameter >= 14.0 {
                let darkSide = vm.isNightVisionMode ? Color(hex: "#2B0307") : Color(hex: "#202430")
                context.fill(Path(ellipseIn: rect), with: .color(darkSide))
                context.drawLayer { layer in
                    layer.translateBy(x: pt.x, y: pt.y)
                    layer.rotate(by: .degrees(planet.brightLimbAngleDeg - 90.0))
                    layer.fill(sphericalPhasePath(radius: rad, illuminatedFraction: planet.coordinates.illuminatedFraction), with: .color(col))
                }
            } else {
                context.fill(Path(ellipseIn: rect), with: .color(col))
            }
        }

        for gm in planet.galileanMoons where gm.isFrontOfPlanet {
            drawGalileanMoonDot(context: context, moon: gm, palette: palette)
        }

        let label = Text(planet.body.displayName)
            .font(.system(size: 9.5, weight: .bold, design: .rounded))
            .foregroundColor(palette.fgPrimary)
        context.draw(label, at: CGPoint(x: pt.x, y: pt.y + rad + 9))
    }

    private func sphericalPhasePath(radius r: Double, illuminatedFraction k: Double) -> Path {
        var path = Path()
        let steps = 28
        for i in 0...steps {
            let theta = -(.pi * 0.5) + (.pi * Double(i) / Double(steps))
            let x = r * cos(theta)
            let y = r * sin(theta)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        let termScale = -(2.0 * k - 1.0)
        for i in stride(from: steps, through: 0, by: -1) {
            let theta = -(.pi * 0.5) + (.pi * Double(i) / Double(steps))
            let x = termScale * r * cos(theta)
            let y = r * sin(theta)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.closeSubpath()
        return path
    }

    private func drawGalileanMoonDot(context: GraphicsContext, moon: ProjectedGalileanMoon, palette: CosmosPalette) {
        let col = vm.isNightVisionMode ? palette.softRed : Color(hex: "#FFF8E1")
        let r = CGRect(x: moon.x - 2.2, y: moon.y - 2.2, width: 4.4, height: 4.4)
        context.fill(Path(ellipseIn: r), with: .color(col))
        if vm.camera.fov <= 4.5 {
            let t = Text(moon.name)
                .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                .foregroundColor(col.opacity(0.9))
            context.draw(t, at: CGPoint(x: moon.x, y: moon.y - 8))
        }
    }

    private func drawHorizonAndCompass(context: GraphicsContext, size: CGSize, scene: ProjectedSkyScene, palette: CosmosPalette) {
        let strokeCol = vm.isNightVisionMode ? palette.primaryRed.opacity(0.50) : ThemeColors.accentCyan.opacity(0.42)

        if scene.horizonPoints.count >= 2 {
            let gCol = vm.isNightVisionMode
                ? Color(hex: "#0A0001").opacity(0.90)
                : Color(hex: "#03060E").opacity(0.88)
            if vm.camera.isZenithPlanisphereLocked {
                let r = CGFloat(scene.matrix.scale)
                let cx = CGFloat(scene.matrix.halfWidth)
                let cy = CGFloat(scene.matrix.halfHeight)
                var maskPath = Path(CGRect(origin: .zero, size: size))
                maskPath.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                context.fill(maskPath, with: .color(gCol), style: FillStyle(eoFill: true))
            } else if vm.camera.effectiveAltitude < 65.0,
                      let first = scene.horizonPoints.first,
                      let last = scene.horizonPoints.last,
                      first.x < last.x {
                let bottomY = max(size.height + 60, max(first.y, last.y) + 420)
                var ground = Path()
                ground.move(to: CGPoint(x: first.x, y: bottomY))
                for pt in scene.horizonPoints {
                    ground.addLine(to: pt)
                }
                ground.addLine(to: CGPoint(x: last.x, y: bottomY))
                ground.closeSubpath()
                context.fill(ground, with: .color(gCol))
            }

            strokePolyline(
                scene.horizonPoints,
                in: context,
                color: strokeCol,
                style: StrokeStyle(lineWidth: vm.camera.isZenithPlanisphereLocked ? 1.8 : 1.4, dash: vm.camera.isZenithPlanisphereLocked ? [] : [5, 4])
            )
        }

        for card in scene.cardinals {
            let pt = CGPoint(x: card.x, y: card.y)
            let discSize: CGFloat = card.isPrimary ? 24 : 17
            let badgeRect = CGRect(x: pt.x - discSize * 0.5, y: pt.y - discSize * 0.5, width: discSize, height: discSize)
            context.fill(Path(ellipseIn: badgeRect), with: .color(palette.cardBackground))
            context.stroke(
                Path(ellipseIn: badgeRect),
                with: .color(card.isPrimary ? palette.accent : strokeCol),
                style: StrokeStyle(lineWidth: card.isPrimary ? 1.5 : 1.0)
            )
            let txt = Text(card.label)
                .font(.system(size: card.isPrimary ? 11 : 8.5, weight: .bold, design: .rounded))
                .foregroundColor(card.isPrimary ? palette.fgPrimary : palette.fgMuted)
            context.draw(txt, at: pt)
        }

        if let zPt = scene.zenithPoint {
            var cross = Path()
            cross.move(to: CGPoint(x: zPt.x - 7, y: zPt.y))
            cross.addLine(to: CGPoint(x: zPt.x + 7, y: zPt.y))
            cross.move(to: CGPoint(x: zPt.x, y: zPt.y - 7))
            cross.addLine(to: CGPoint(x: zPt.x, y: zPt.y + 7))
            context.stroke(cross, with: .color(strokeCol), style: StrokeStyle(lineWidth: 1.1))
            let zTxt = Text("ZENITH")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(palette.accent.opacity(0.75))
            context.draw(zTxt, at: CGPoint(x: zPt.x, y: zPt.y - 13))
        }
    }

    private func drawTargetGuideArrow(context: GraphicsContext, size: CGSize, guide: SkyTargetGuideState, palette: CosmosPalette) {
        let cx = size.width * 0.5
        let cy = size.height * 0.5
        let ringRadius = min(size.width, size.height) * 0.30
        let ax = cx + cos(guide.angleRadians) * ringRadius
        let ay = cy + sin(guide.angleRadians) * ringRadius

        context.stroke(
            Path(ellipseIn: CGRect(x: cx - ringRadius, y: cy - ringRadius, width: ringRadius * 2, height: ringRadius * 2)),
            with: .color(palette.accent.opacity(0.18)),
            style: StrokeStyle(lineWidth: 1.0, dash: [4, 6])
        )

        context.drawLayer { layer in
            layer.translateBy(x: ax, y: ay)
            layer.rotate(by: .radians(guide.angleRadians))
            var arrow = Path()
            arrow.move(to: CGPoint(x: 9, y: 0))
            arrow.addLine(to: CGPoint(x: -6, y: -6))
            arrow.addLine(to: CGPoint(x: -3, y: 0))
            arrow.addLine(to: CGPoint(x: -6, y: 6))
            arrow.closeSubpath()
            layer.fill(arrow, with: .color(palette.accent))
        }

        let lbl = Text("\(guide.targetName) · \(Int(guide.angularSeparationDeg.rounded()))°")
            .font(.system(size: 9.5, weight: .bold, design: .rounded))
            .foregroundColor(palette.accent)
        context.draw(lbl, at: CGPoint(x: ax, y: ay + 16))
    }

    private func strokePolyline(_ points: [CGPoint], in context: GraphicsContext, color: Color, style: StrokeStyle) {
        guard points.count >= 2 else { return }
        let maxJump2 = pow(max(context.clipBoundingRect.width, context.clipBoundingRect.height) * 0.65, 2.0)
        var path = Path()
        path.move(to: points[0])
        for i in 1..<points.count {
            let prev = points[i - 1]
            let cur = points[i]
            let dx = cur.x - prev.x, dy = cur.y - prev.y
            if (dx * dx + dy * dy) <= maxJump2 {
                path.addLine(to: cur)
            } else {
                path.move(to: cur)
            }
        }
        context.stroke(path, with: .color(color), style: style)
    }

    // MARK: - Target Inspector Card

    @ViewBuilder
    private func targetInspectorCard(target: CosmosTarget) -> some View {
        let p = vm.palette
        let live = vm.liveMetrics(for: target)
        let bookmarked = vm.isBookmarked(target)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                if let thumbPath = target.thumbnailRelativePath,
                   let thumbURL = vm.catalogService.thumbnailURL(for: thumbPath),
                   let img = loadLocalPlatformImage(from: thumbURL) {
                    img
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(p.border, lineWidth: 1))
                        .colorMultiply(vm.isNightVisionMode ? p.primaryRed : .white)
                } else {
                    Image(systemName: target.iconName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(vm.isNightVisionMode ? p.primaryRed : Color(hex: target.accentColorHex))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(p.pillBackground))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(p.fgPrimary)
                        .lineLimit(1)
                    Text("\(target.category) · \(live.isAboveHorizon ? "Above Horizon" : "Below Horizon")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(live.isAboveHorizon ? p.positive : p.fgMuted)
                }

                Spacer()

                Button {
                    triggerHaptic()
                    vm.toggleBookmark(for: target)
                } label: {
                    Image(systemName: bookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(bookmarked ? p.accent : p.fgPrimary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(p.pillBackground))
                }
                .buttonStyle(.plain)
                .help("Bookmark Target")

                Button {
                    triggerHaptic()
                    vm.centerOn(target: target)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "scope")
                            .font(.system(size: 10, weight: .bold))
                        Text("Center")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(p.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(p.pillBackground))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation { vm.selectedTarget = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(p.fgMuted)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    metricPill(
                        title: "AZ / ALT",
                        value: String(format: "%.1f° %@ · %+.1f°", live.azimuthDegrees, live.compassDirection, live.altitudeDegrees)
                    )
                    if target.kind != .iss {
                        metricPill(
                            title: "RA / DEC (J2000)",
                            value: String(format: "%.2fh · %+.1f°", live.rightAscensionHours, live.declinationDegrees)
                        )
                    }
                    if let mag = target.visualMagnitude {
                        metricPill(title: "MAG", value: String(format: "%.1f", mag))
                    }
                    if let dist = live.distanceLabel {
                        metricPill(title: "DISTANCE", value: dist)
                    }
                    if let rise = live.riseTime {
                        metricPill(title: "RISE", value: rise.formatted(date: .omitted, time: .shortened))
                    }
                    if let transit = live.transitTime {
                        metricPill(title: "TRANSIT", value: transit.formatted(date: .omitted, time: .shortened))
                    }
                    if let set = live.setTime {
                        metricPill(title: "SET", value: set.formatted(date: .omitted, time: .shortened))
                    }
                    if let detail = live.phaseOrDetailLabel {
                        metricPill(title: "STATE", value: detail)
                    }
                }
            }

            Text(target.lore)
                .font(.system(size: 12))
                .foregroundColor(p.fgSecondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Button {
                    triggerHaptic()
                    vm.logSightingToTagdos(for: target)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checklist")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Log Sighting (#sky)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(p.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(p.pillBackground))
                    .overlay(Capsule().strokeBorder(p.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    triggerHaptic()
                    let schedDate = live.transitTime ?? live.riseTime ?? Date().addingTimeInterval(3600)
                    Task {
                        await vm.scheduleObservationInCalendar(
                            title: "Observe \(target.name)",
                            startDate: schedDate,
                            notes: "\(target.subtitle)\nRecommended optics: \(target.recommendedOptics ?? "Naked Eye")\n\(target.lore)"
                        )
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Schedule")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(p.fgPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(p.pillBackground))
                    .overlay(Capsule().strokeBorder(p.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()

                if let optics = target.recommendedOptics {
                    Text(optics)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(p.fgMuted)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(p.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(p.border, lineWidth: 1))
    }

    @ViewBuilder
    private func metricPill(title: String, value: String) -> some View {
        let p = vm.palette
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(p.fgMuted)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(p.fgPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(p.pillBackground))
    }

    private func loadLocalPlatformImage(from url: URL) -> Image? {
        #if canImport(UIKit)
        if let uiImg = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: uiImg)
        }
        #elseif canImport(AppKit)
        if let nsImg = NSImage(contentsOf: url) {
            return Image(nsImage: nsImg)
        }
        #endif
        return nil
    }

    // MARK: - 42% Side-by-Side Observatory Deck

    @ViewBuilder
    private var observatorySideDeck: some View {
        let p = vm.palette
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Observatory Deck", systemImage: "moon.stars.fill")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(p.accent)
                    Spacer()
                    provenancePill(vm.stargazingConditions.provenance)
                }

                observatoryTelemetryContent
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var observatoryTelemetryContent: some View {
        let p = vm.palette
        let cond = vm.stargazingConditions

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TONIGHT'S SKY SCORE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(p.fgMuted)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(vm.stargazingScore)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(p.fgPrimary)
                        Text("/ 100 · \(vm.stargazingVerdict)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(
                                vm.isNightVisionMode
                                    ? p.primaryRed
                                    : (vm.stargazingScore >= 75 ? p.positive : (vm.stargazingScore >= 50 ? p.accent : (vm.stargazingScore >= 30 ? Color(hex: "#FFB300") : p.accentSecondary)))
                            )
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Bortle \(cond.bortleClass) · NELM \(String(format: "%.1f", cond.limitingMagnitude))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(p.fgPrimary)
                    if let darkWindow = cond.bestWindowDescription, !darkWindow.isEmpty {
                        Text("Dark Window: \(darkWindow)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(p.accent)
                    }
                }
            }

            HStack(spacing: 8) {
                metricPill(
                    title: "CLOUDS (L/M/H)",
                    value: cond.cloudCoverTotalPercent != nil
                        ? "\(cond.cloudCoverLowPercent ?? 0)% / \(cond.cloudCoverMidPercent ?? 0)% / \(cond.cloudCoverHighPercent ?? 0)%"
                        : "Offline"
                )
                metricPill(
                    title: "SEEING",
                    value: cond.seeingArcseconds.map { String(format: "%.1f\" FWHM", $0) } ?? "Offline"
                )
                metricPill(
                    title: "MOON",
                    value: "\(vm.currentMoonPhase.illuminationPercent)% · \(Int((vm.currentMoonPhase.topocentricDistanceKm ?? vm.currentMoonPhase.distanceKm).rounded()).formatted()) km"
                )
            }

            Text(cond.narrativeAdvice)
                .font(.system(size: 11.5))
                .foregroundColor(p.fgSecondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(p.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(p.border, lineWidth: 1))

        VStack(alignment: .leading, spacing: 8) {
            Text("VISIBLE ABOVE HORIZON NOW")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(p.fgMuted)

            ForEach(vm.tonightFeaturedTargets.prefix(6)) { t in
                let live = vm.liveMetrics(for: t)
                Button {
                    triggerHaptic()
                    showingDrawer = false
                    vm.centerOn(target: t)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: t.iconName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(vm.isNightVisionMode ? p.primaryRed : Color(hex: t.accentColorHex))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(p.fgPrimary)
                            Text(String(format: "Az %.0f° (%@) · Alt %+.0f°", live.azimuthDegrees, live.compassDirection, live.altitudeDegrees))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(p.fgMuted)
                        }
                        Spacer()
                        Image(systemName: "scope")
                            .font(.system(size: 12))
                            .foregroundColor(p.accent)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(p.pillBackground))
                }
                .buttonStyle(.plain)
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ISS SGP4 VISIBLE PASSES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(p.fgMuted)
                Spacer()
                provenancePill(liveService.satelliteProvenance)
            }

            if liveService.upcomingIssPasses.isEmpty {
                Text("No sunlit passes above 10° altitude in the next 36 hours (or CelesTrak OMM not yet cached).")
                    .font(.system(size: 11.5))
                    .foregroundColor(p.fgMuted)
            } else {
                ForEach(liveService.upcomingIssPasses.prefix(4)) { pass in
                    HStack {
                        Image(systemName: "satellite.fill")
                            .foregroundColor(p.accentSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pass.startTime.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(p.fgPrimary)
                            Text("Max Alt \(Int(pass.maxAltitudeDegrees))° · Mag \(String(format: "%.1f", pass.peakMagnitude)) · \(pass.durationMinutes) min")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(p.fgMuted)
                        }
                        Spacer()
                        Button {
                            triggerHaptic()
                            Task {
                                await vm.scheduleObservationInCalendar(
                                    title: "ISS Bright Pass (\(Int(pass.maxAltitudeDegrees))° max alt)",
                                    startDate: pass.startTime,
                                    durationMinutes: max(10, pass.durationMinutes),
                                    notes: "Analytical SGP4 pass prediction for \(vm.observerLocationName). Peak magnitude \(String(format: "%.1f", pass.peakMagnitude))."
                                )
                            }
                        } label: {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 13))
                                .foregroundColor(p.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(p.pillBackground))
                }
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NOAA SPACE WEATHER & AURORA")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(p.fgMuted)
                Spacer()
                if let sw = liveService.spaceWeather {
                    provenancePill(sw.provenance)
                }
            }

            if let sw = liveService.spaceWeather {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        metricPill(title: "KP INDEX", value: sw.kpIndex.map { String(format: "%.1f", $0) } ?? "--")
                        metricPill(title: "IMF Bz", value: sw.bzMagneticFieldNt.map { String(format: "%+.1f nT", $0) } ?? "--")
                        metricPill(title: "SOLAR WIND", value: sw.solarWindSpeedKmS.map { "\(Int($0)) km/s" } ?? "--")
                    }
                    Text(sw.statusMessage)
                        .font(.system(size: 11.5))
                        .foregroundColor(sw.isAuroraAlertActive ? p.positive : p.fgSecondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(p.pillBackground))
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("CIRCADIAN & NATURAL SKYGLOW")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(p.fgMuted)
            Text(vm.circadianContext.summary)
                .font(.system(size: 11.5))
                .foregroundColor(p.fgSecondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(p.pillBackground))
        }

        if let apod = liveService.apodPicture {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("NASA ASTRONOMY PICTURE OF THE DAY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(p.fgMuted)
                    Spacer()
                    provenancePill(liveService.apodProvenance)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if apod.media_type == "image", let url = URL(string: apod.url) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(height: 150)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .colorMultiply(vm.isNightVisionMode ? p.primaryRed : .white)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(p.pillBackground)
                                .frame(height: 110)
                        }
                    }
                    Text(apod.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(p.fgPrimary)
                    Text(apod.explanation)
                        .font(.system(size: 11))
                        .foregroundColor(p.fgSecondary)
                        .lineLimit(4)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(p.pillBackground))
            }
        }

        if !syncService.bookmarks.isEmpty || !syncService.observations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("BOOKMARKS & LOGGED SIGHTINGS (#SKY)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(p.fgMuted)

                ForEach(syncService.bookmarks.prefix(5)) { bm in
                    HStack {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 11))
                            .foregroundColor(p.accent)
                        Text(bm.objectName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(p.fgPrimary)
                        Spacer()
                        Text(bm.category)
                            .font(.system(size: 10))
                            .foregroundColor(p.fgMuted)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(p.pillBackground))
                }

                ForEach(syncService.observations.prefix(4)) { obs in
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundColor(p.positive)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(obs.objectName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(p.fgPrimary)
                            Text("\(obs.observedAt.formatted(date: .abbreviated, time: .shortened)) · \(obs.optics)")
                                .font(.system(size: 10))
                                .foregroundColor(p.fgMuted)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(p.pillBackground))
                }
            }
        }
    }

    @ViewBuilder
    private func provenancePill(_ prov: TelemetryProvenance) -> some View {
        let p = vm.palette
        Text(prov.badgeLabel)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(prov.isAvailable ? p.accent : p.fgMuted)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(p.pillBackground))
            .overlay(Capsule().strokeBorder(p.border, lineWidth: 1))
    }

    // MARK: - Search Catalog Sheet

    @ViewBuilder
    private var cosmosSearchSheet: some View {
        let p = vm.palette
        NavigationStack {
            ZStack {
                LinearGradient(colors: [p.sheetBackgroundTop, p.sheetBackgroundBottom], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(p.fgMuted)
                        TextField("Search 15,544 stars, 219 Messier/Caldwell DSOs, planets, ISS...", text: $vm.searchQuery)
                            .foregroundColor(p.fgPrimary)
                        if !vm.searchQuery.isEmpty {
                            Button { vm.searchQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(p.fgMuted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(p.pillBackground))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(p.border, lineWidth: 1))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(vm.searchResults) { target in
                                let live = vm.liveMetrics(for: target)
                                Button {
                                    triggerHaptic()
                                    showingSearchSheet = false
                                    vm.centerOn(target: target)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: target.iconName)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(vm.isNightVisionMode ? p.primaryRed : Color(hex: target.accentColorHex))
                                            .frame(width: 26)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(target.name)
                                                .font(.system(size: 13.5, weight: .semibold))
                                                .foregroundColor(p.fgPrimary)
                                            Text("\(target.subtitle) · Alt \(Int(live.altitudeDegrees.rounded()))°")
                                                .font(.system(size: 11.5))
                                                .foregroundColor(p.fgMuted)
                                        }
                                        Spacer()
                                        Text(live.isAboveHorizon ? "Visible" : "Set")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(live.isAboveHorizon ? p.positive : p.fgMuted)
                                    }
                                    .padding(11)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(p.pillBackground))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Cosmos Sky Catalog")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { showingSearchSheet = false }
                        .foregroundColor(p.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Tonight's Best Drawer Sheet

    @ViewBuilder
    private var tonightsBestSheet: some View {
        let p = vm.palette
        NavigationStack {
            ZStack {
                LinearGradient(colors: [p.sheetBackgroundTop, p.sheetBackgroundBottom], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        observatoryTelemetryContent
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Tonight's Sky Observatory")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingDrawer = false }
                        .foregroundColor(p.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sky Layers, Grids & 1900–2100 Date Jump Sheet

    @ViewBuilder
    private var layersAndDateSheet: some View {
        let p = vm.palette
        NavigationStack {
            ZStack {
                LinearGradient(colors: [p.sheetBackgroundTop, p.sheetBackgroundBottom], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("EPOCH & DATE JUMP (1900–2100)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(p.fgMuted)

                        DatePicker(
                            "Observation Date & Time",
                            selection: Binding(
                                get: { vm.simulationDate },
                                set: { vm.setSimulationDate($0) }
                            ),
                            in: Date(timeIntervalSince1970: -2_208_988_800)...Date(timeIntervalSince1970: 4_102_444_800),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .foregroundColor(p.fgPrimary)
                        .tint(p.accent)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(p.pillBackground))

                        Text("PLANETARIUM LAYERS & GRIDS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(p.fgMuted)

                        VStack(spacing: 8) {
                            layerToggleRow("Rayleigh Atmosphere & Twilight", isOn: $vm.showAtmosphere, palette: p)
                            layerToggleRow("Milky Way Galactic Isophotes", isOn: $vm.showMilkyWay, palette: p)
                            layerToggleRow("IAU 88 Constellation Figures", isOn: $vm.showConstellationLines, palette: p)
                            layerToggleRow("Constellation Names", isOn: $vm.showConstellationLabels, palette: p)
                            layerToggleRow("IAU Constellation Boundaries", isOn: $vm.showConstellationBorders, palette: p)
                            layerToggleRow("Famous Asterisms (Big Dipper, Summer Triangle)", isOn: $vm.showAsterisms, palette: p)
                            layerToggleRow("Messier & Caldwell Deep-Sky Objects (219)", isOn: $vm.showDeepSkyObjects, palette: p)
                            layerToggleRow("Solar System Planets, Moon & Galilean Moons", isOn: $vm.showPlanets, palette: p)
                            layerToggleRow("IAU Meteor Shower Radiants", isOn: $vm.showMeteorRadiants, palette: p)
                            layerToggleRow("Live ISS (SGP4) & Orbital Pass Arc", isOn: $vm.showSatellites, palette: p)
                            layerToggleRow("Alt-Azimuth Coordinate Grid", isOn: $vm.showAltAzGrid, palette: p)
                            layerToggleRow("Equatorial RA/Dec (J2000) Grid", isOn: $vm.showEquatorialGrid, palette: p)
                            layerToggleRow("Ecliptic Plane", isOn: $vm.showEcliptic, palette: p)
                            layerToggleRow("Horizon Silhouette & Cardinal Compass", isOn: $vm.showHorizonCompass, palette: p)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Sky Layers & Time")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingLayersSheet = false }
                        .foregroundColor(p.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func layerToggleRow(_ title: String, isOn: Binding<Bool>, palette: CosmosPalette) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(palette.fgPrimary)
        }
        .tint(palette.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.pillBackground))
    }
}
