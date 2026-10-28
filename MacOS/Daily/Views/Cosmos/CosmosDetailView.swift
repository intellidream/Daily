import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 120Hz ProMotion interactive Sky Dome hub with conformal stereographic canvas,
/// IAU constellation stick figures, planetary discs, Messier DSOs, AR gyro tracking,
/// Time Machine scrubber, and Red Night-Vision mode (#FF1824).
public struct CosmosDetailView: View {
    @StateObject private var vm = CosmosViewModel.shared
    @ObservedObject private var liveService = CosmosLiveService.shared

    public var onNavigateBack: (() -> Void)? = nil
    public var onNavigateToWeather: (() -> Void)? = nil

    @State private var showingDrawer: Bool = false
    @State private var showingSearchSheet: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var currentZoomScale: CGFloat = 1.0

    public init(
        onNavigateBack: (() -> Void)? = nil,
        onNavigateToWeather: (() -> Void)? = nil
    ) {
        self.onNavigateBack = onNavigateBack
        self.onNavigateToWeather = onNavigateToWeather
    }

    private func triggerHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #elseif canImport(AppKit)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // 1. Deep Space Sky Background
                skyBackground
                    .ignoresSafeArea()

                // 2. Interactive Sky Dome Canvas
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    Canvas { context, size in
                        drawSkyDome(context: context, size: size)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .gesture(
                        DragGesture(minimumDistance: 4)
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
                    .gesture(
                        MagnificationGesture()
                            .onChanged { scale in
                                let delta = scale / currentZoomScale
                                currentZoomScale = scale
                                vm.handleZoom(deltaMagnification: delta)
                            }
                            .onEnded { _ in
                                currentZoomScale = 1.0
                            }
                    )
                    .onTapGesture { location in
                        handleCanvasTap(at: location, size: geometry.size)
                    }
                }

                // 3. Top HUD Controls
                topHUDBar

                // 4. Target Inspector Floating Card (when target selected)
                if let target = vm.selectedTarget {
                    VStack {
                        Spacer()
                        targetInspectorCard(target: target)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 120)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                // 5. Bottom HUD Controls (Time Machine & Drawer Toggle)
                VStack {
                    Spacer()
                    bottomControlBar
                }
            }
        }
        .sheet(isPresented: $showingSearchSheet) {
            cosmosSearchSheet
        }
        .sheet(isPresented: $showingDrawer) {
            tonightsBestSheet
        }
        .task {
            await liveService.refreshCosmosData(latitude: vm.observerLatitude, longitude: vm.observerLongitude)
        }
    }

    // MARK: - Sky Background
    @ViewBuilder
    private var skyBackground: some View {
        if vm.isNightVisionMode {
            RadialGradient(
                colors: [Color(hex: "#260204"), Color(hex: "#100002"), Color.black],
                center: .center,
                startRadius: 40,
                endRadius: 600
            )
        } else {
            RadialGradient(
                colors: [Color(hex: "#0A122A"), Color(hex: "#040714"), Color(hex: "#010206")],
                center: .center,
                startRadius: 40,
                endRadius: 700
            )
        }
    }

    // MARK: - Top HUD Bar
    @ViewBuilder
    private var topHUDBar: some View {
        HStack(alignment: .center, spacing: 10) {
            // Back Button
            Button {
                triggerHaptic()
                onNavigateBack?()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(vm.isNightVisionMode ? Color(hex: "#FF1824") : .white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(Color.white.opacity(0.08))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)

            // Switch to Weather Hub Pill
            if let onNavigateToWeather = onNavigateToWeather {
                Button {
                    triggerHaptic()
                    onNavigateToWeather()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "cloud.sun.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Vreme")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(vm.isNightVisionMode ? Color(hex: "#FF1824") : ThemeColors.accentCyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Observer Location & Compass Heading Pill
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text(vm.observerLocationName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(vm.isNightVisionMode ? Color(hex: "#FF1824") : .white)
                        .lineLimit(1)
                    Text("· \(Int(vm.cameraAzimuth))° \(cardinalDirection(for: vm.cameraAzimuth))")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(vm.isNightVisionMode ? Color(hex: "#FF6666") : ThemeColors.accentCyan)
                }

                HStack(spacing: 4) {
                    Circle()
                        .fill(vm.isLiveTime ? ThemeColors.accentGreen : ThemeColors.accentOrange)
                        .frame(width: 5, height: 5)
                    Text(vm.isLiveTime ? "LIVE" : vm.simulationDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(vm.isNightVisionMode ? Color(hex: "#FF6666") : ThemeColors.fgMutedDark)
                }
            }

            Spacer()

            // Action Buttons (Night Vision, AR Gyro, Search)
            HStack(spacing: 8) {
                // Night Vision Toggle Button
                Button {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.3)) {
                        vm.isNightVisionMode.toggle()
                    }
                } label: {
                    Image(systemName: vm.isNightVisionMode ? "eye.fill" : "eye")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(vm.isNightVisionMode ? .white : Color(hex: "#FF1824"))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(vm.isNightVisionMode ? Color(hex: "#FF1824") : Color.white.opacity(0.08))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                // AR Gyroscope Tracker
                Button {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.3)) {
                        vm.toggleMotionTracking()
                    }
                } label: {
                    Image(systemName: vm.isMotionTrackingEnabled ? "dot.scope" : "gyroscope")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(vm.isMotionTrackingEnabled ? .black : (vm.isNightVisionMode ? Color(hex: "#FF1824") : ThemeColors.accentCyan))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(vm.isMotionTrackingEnabled ? ThemeColors.accentCyan : Color.white.opacity(0.08))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                // Search Catalog Button
                Button {
                    triggerHaptic()
                    showingSearchSheet = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(vm.isNightVisionMode ? Color(hex: "#FF1824") : .white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(Color.white.opacity(0.08))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // MARK: - Bottom Control Bar
    @ViewBuilder
    private var bottomControlBar: some View {
        VStack(spacing: 8) {
            // Time Machine Scrubber Capsule
            HStack(spacing: 12) {
                // -1 Hour
                Button {
                    triggerHaptic()
                    vm.adjustSimulationTime(byHours: -1.0)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 9))
                        Text("-1h")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(vm.isNightVisionMode ? Color(hex: "#FF1824") : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // LIVE button
                Button {
                    triggerHaptic()
                    vm.resetToLive()
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(vm.isLiveTime ? ThemeColors.accentGreen : ThemeColors.accentOrange)
                            .frame(width: 6, height: 6)
                        Text(vm.isLiveTime ? "LIVE" : "RESETEAZĂ")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(vm.isNightVisionMode ? Color(hex: "#FF1824") : (vm.isLiveTime ? ThemeColors.accentGreen : .white))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(vm.isLiveTime ? ThemeColors.accentGreen.opacity(0.16) : Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // +1 Hour
                Button {
                    triggerHaptic()
                    vm.adjustSimulationTime(byHours: 1.0)
                } label: {
                    HStack(spacing: 4) {
                        Text("+1h")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "forward.fill")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(vm.isNightVisionMode ? Color(hex: "#FF1824") : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                // "Tonight's Best" Drawer Toggle
                Button {
                    triggerHaptic()
                    showingDrawer = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                        Text("Recomandări")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(vm.isNightVisionMode ? Color(hex: "#FF1824") : ThemeColors.accentCyan)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Canvas Rendering (120Hz Hardware Accelerated)
    private func drawSkyDome(context: GraphicsContext, size: CGSize) {
        let elements = vm.projectElements(in: size)

        let primaryRed = Color(hex: "#FF1824")
        let dimRed = Color(hex: "#880005")

        // 1. Draw Horizon Grid & Compass Cardinal Markers
        if vm.showHorizonCompass {
            drawCompassAndHorizon(context: context, size: size)
        }

        // 2. Draw Constellation Lines
        let lineStroke = StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round)
        let lineColor = vm.isNightVisionMode ? dimRed.opacity(0.5) : Color.white.opacity(0.24)
        for line in elements.lines {
            var path = Path()
            path.move(to: CGPoint(x: line.startX, y: line.startY))
            path.addLine(to: CGPoint(x: line.endX, y: line.endY))
            context.stroke(path, with: .color(lineColor), style: lineStroke)
        }

        // 3. Draw Constellation Labels
        if vm.showConstellationLabels {
            for lbl in elements.labels {
                let text = Text(lbl.record.nameRo)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(vm.isNightVisionMode ? primaryRed.opacity(0.7) : ThemeColors.accentCyan.opacity(0.65))
                context.draw(text, at: CGPoint(x: lbl.screenX, y: lbl.screenY))
            }
        }

        // 4. Draw Stars
        for star in elements.stars {
            let rect = CGRect(
                x: star.screenX - star.diameter * 0.5,
                y: star.screenY - star.diameter * 0.5,
                width: star.diameter,
                height: star.diameter
            )
            // Soft halo glow
            context.fill(
                Path(ellipseIn: rect.insetBy(dx: -1.5, dy: -1.5)),
                with: .color(star.color.opacity(0.25))
            )
            // Star core
            context.fill(Path(ellipseIn: rect), with: .color(star.color))
        }

        // 5. Draw Messier Deep Sky Objects
        for dso in elements.dsos {
            let pt = CGPoint(x: dso.screenX, y: dso.screenY)
            let circleRect = CGRect(x: pt.x - 7, y: pt.y - 7, width: 14, height: 14)
            let strokeColor = vm.isNightVisionMode ? primaryRed : ThemeColors.accentPink.opacity(0.8)
            context.stroke(Path(ellipseIn: circleRect), with: .color(strokeColor), style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
            let text = Text(dso.dso.id)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(strokeColor)
            context.draw(text, at: CGPoint(x: pt.x, y: pt.y + 12))
        }

        // 6. Draw Planets & Moon
        for p in elements.planets {
            let pt = CGPoint(x: p.screenX, y: p.screenY)
            let rect = CGRect(x: pt.x - p.diameter * 0.5, y: pt.y - p.diameter * 0.5, width: p.diameter, height: p.diameter)

            if p.body == .moon {
                // Moon disk with illumination phase
                context.fill(Path(ellipseIn: rect), with: .color(vm.isNightVisionMode ? dimRed : Color(hex: "#333A4D")))
                // Illuminated crescent
                let illumRect = CGRect(x: pt.x - p.diameter * 0.5, y: pt.y - p.diameter * 0.5, width: p.diameter * vm.currentMoonPhase.illuminatedFraction, height: p.diameter)
                context.fill(Path(ellipseIn: illumRect), with: .color(vm.isNightVisionMode ? primaryRed : Color(hex: "#FFF8E7")))
            } else if p.body == .sun {
                // Sun disk
                context.fill(Path(ellipseIn: rect), with: .color(vm.isNightVisionMode ? primaryRed : Color(hex: "#FFD700")))
            } else {
                // Planet disc with glow
                let planetColor: Color
                switch p.body {
                case .jupiter: planetColor = vm.isNightVisionMode ? primaryRed : Color(hex: "#E0A96D")
                case .saturn:  planetColor = vm.isNightVisionMode ? primaryRed : Color(hex: "#ECCB8C")
                case .mars:    planetColor = vm.isNightVisionMode ? primaryRed : Color(hex: "#E5533D")
                case .venus:   planetColor = vm.isNightVisionMode ? primaryRed : Color(hex: "#F4E3B2")
                default:       planetColor = vm.isNightVisionMode ? primaryRed : Color(hex: "#A8B4C0")
                }

                // If Saturn, draw ring ellipse
                if p.body == .saturn {
                    let ringRect = CGRect(x: pt.x - p.diameter * 0.9, y: pt.y - p.diameter * 0.35, width: p.diameter * 1.8, height: p.diameter * 0.7)
                    context.stroke(Path(ellipseIn: ringRect), with: .color(planetColor.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5))
                }

                context.fill(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)), with: .color(planetColor.opacity(0.3)))
                context.fill(Path(ellipseIn: rect), with: .color(planetColor))
            }

            // Name label below planet
            let label = Text(p.body.rawValue.capitalized)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(vm.isNightVisionMode ? primaryRed : .white)
            context.draw(label, at: CGPoint(x: pt.x, y: pt.y + p.diameter * 0.5 + 8))
        }
    }

    private func drawCompassAndHorizon(context: GraphicsContext, size: CGSize) {
        // Horizon curve line and cardinal markers
        let cardinals: [(String, Double)] = [
            ("N", 0.0), ("NE", 45.0), ("E", 90.0), ("SE", 135.0),
            ("S", 180.0), ("SW", 225.0), ("W", 270.0), ("NW", 315.0)
        ]

        let strokeColor = vm.isNightVisionMode ? Color(hex: "#880005").opacity(0.6) : ThemeColors.accentCyan.opacity(0.3)

        for (label, az) in cardinals {
            // Compute relative screen position for cardinal label
            var diff = az - vm.cameraAzimuth
            if diff > 180 { diff -= 360 }
            if diff < -180 { diff += 360 }

            if abs(diff) < (vm.fov * 0.7) {
                let screenX = (Double(size.width) * 0.5) + (diff / vm.fov) * Double(size.width)
                // Horizon altitude line calculation
                let altFraction = (0.0 - vm.cameraAltitude) / vm.fov
                let screenY = (Double(size.height) * 0.5) - (altFraction * Double(size.height))

                if screenY >= 40 && screenY <= Double(size.height) - 40 {
                    let text = Text(label)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(vm.isNightVisionMode ? Color(hex: "#FF1824") : ThemeColors.accentCyan)
                    context.draw(text, at: CGPoint(x: screenX, y: screenY))

                    // Small vertical notch
                    var notch = Path()
                    notch.move(to: CGPoint(x: screenX, y: screenY - 8))
                    notch.addLine(to: CGPoint(x: screenX, y: screenY + 8))
                    context.stroke(notch, with: .color(strokeColor), style: StrokeStyle(lineWidth: 1.5))
                }
            }
        }
    }

    private func handleCanvasTap(at point: CGPoint, size: CGSize) {
        let elements = vm.projectElements(in: size)

        // Check if user tapped a planet
        for p in elements.planets {
            let dist = hypot(point.x - p.screenX, point.y - p.screenY)
            if dist < max(24.0, p.diameter * 1.5) {
                triggerHaptic()
                withAnimation(.spring(response: 0.35)) {
                    vm.selectedTarget = vm.target(for: p.body)
                }
                return
            }
        }

        // Check if user tapped a DSO
        for dso in elements.dsos {
            let dist = hypot(point.x - dso.screenX, point.y - dso.screenY)
            if dist < 24.0 {
                triggerHaptic()
                withAnimation(.spring(response: 0.35)) {
                    vm.selectedTarget = vm.target(for: dso.dso)
                }
                return
            }
        }

        // Check if user tapped a bright star
        for star in elements.stars {
            let dist = hypot(point.x - star.screenX, point.y - star.screenY)
            if dist < max(20.0, star.diameter * 2.0) {
                triggerHaptic()
                withAnimation(.spring(response: 0.35)) {
                    vm.selectedTarget = vm.target(for: star.star)
                }
                return
            }
        }

        // Tap empty sky to dismiss inspector
        if vm.selectedTarget != nil {
            withAnimation(.spring(response: 0.3)) {
                vm.selectedTarget = nil
            }
        }
    }

    // MARK: - Target Inspector Card
    @ViewBuilder
    private func targetInspectorCard(target: CosmosTarget) -> some View {
        GlassCard(cornerRadius: 18, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: target.iconName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(vm.isNightVisionMode ? Color(hex: "#FF1824") : Color(hex: target.accentColorHex))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.name)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(vm.isNightVisionMode ? Color(hex: "#FF1824") : .white)
                        Text(target.category)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }

                    Spacer()

                    // Center camera on target button
                    Button {
                        triggerHaptic()
                        vm.centerOn(target: target)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "scope")
                                .font(.system(size: 11, weight: .bold))
                            Text("Centrează")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(vm.isNightVisionMode ? Color(hex: "#FF1824") : ThemeColors.accentCyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    // Close Button
                    Button {
                        withAnimation { vm.selectedTarget = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .background(Color.white.opacity(0.10))

                // Coordinates & Metrics Row
                HStack(spacing: 12) {
                    if let mag = target.visualMagnitude {
                        metricPill(title: "MAGNITUDINE", value: String(format: "%.1f", mag))
                    }
                    if let dist = target.distanceDescription {
                        metricPill(title: "DISTANȚĂ", value: dist)
                    }
                    if let const = target.constellationName {
                        metricPill(title: "CONSTELAȚIE", value: const)
                    }
                    if let optics = target.recommendedOptics {
                        metricPill(title: "OPTICĂ", value: optics)
                    }
                }

                // Lore & Lore Details
                Text(target.lore)
                    .font(.system(size: 12))
                    .foregroundColor(vm.isNightVisionMode ? Color(hex: "#FF8888") : .white.opacity(0.85))
                    .lineLimit(3)
            }
        }
    }

    @ViewBuilder
    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(ThemeColors.fgMutedDark)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(vm.isNightVisionMode ? Color(hex: "#FF1824") : .white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Search Catalog Sheet
    @ViewBuilder
    private var cosmosSearchSheet: some View {
        NavigationStack {
            LiquidGlassBackground {
                VStack(spacing: 14) {
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(ThemeColors.fgMutedDark)
                        TextField("Caută stele, planete, obiecte Messier...", text: $vm.searchQuery)
                            .foregroundColor(.white)
                        if !vm.searchQuery.isEmpty {
                            Button { vm.searchQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    // Results List
                    List {
                        ForEach(vm.searchResults) { target in
                            Button {
                                triggerHaptic()
                                showingSearchSheet = false
                                vm.centerOn(target: target)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: target.iconName)
                                        .font(.system(size: 16))
                                        .foregroundColor(Color(hex: target.accentColorHex))
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(target.name)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.white)
                                        Text(target.subtitle)
                                            .font(.system(size: 12))
                                            .foregroundColor(ThemeColors.fgMutedDark)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Catalog Cosmos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Închide") { showingSearchSheet = false }
                        .foregroundColor(ThemeColors.accentCyan)
                }
            }
        }
    }

    // MARK: - Tonight's Best Drawer
    @ViewBuilder
    private var tonightsBestSheet: some View {
        NavigationStack {
            LiquidGlassBackground {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Stargazing Conditions Summary Card
                        GlassCard(cornerRadius: 16, padding: 14) {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("SCOR DE OBSERVARE")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Text("\(vm.stargazingScore)")
                                            .font(.system(size: 36, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                        Text("/ 100")
                                            .font(.system(size: 13))
                                            .foregroundColor(ThemeColors.fgMutedDark)
                                    }
                                    Text(vm.stargazingVerdict)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(ThemeColors.accentGreen)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Luna: \(vm.currentMoonPhase.quarter.displayNameRo)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text("\(vm.currentMoonPhase.illuminationPercent)% iluminată")
                                        .font(.system(size: 11))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                }
                            }
                        }

                        // ISS Satellite Passes
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TRECERI STAȚIA SPAȚIALĂ (ISS)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(ThemeColors.fgMutedDark)

                            if liveService.upcomingIssPasses.isEmpty {
                                Text("Nicio trecere strălucitoare calculată pentru următoarele 24h.")
                                    .font(.system(size: 12))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            } else {
                                ForEach(liveService.upcomingIssPasses) { pass in
                                    HStack {
                                        Image(systemName: "satellite.fill")
                                            .foregroundColor(ThemeColors.accentPink)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(pass.startTime.formatted(date: .abbreviated, time: .shortened))
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(.white)
                                            Text("Magnitudine max: \(String(format: "%.1f", pass.peakMagnitude)) · Alt: \(Int(pass.maxAltitudeDegrees))°")
                                                .font(.system(size: 11))
                                                .foregroundColor(ThemeColors.fgMutedDark)
                                        }
                                        Spacer()
                                    }
                                    .padding(10)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }

                        // Space Weather & Aurora
                        VStack(alignment: .leading, spacing: 8) {
                            Text("VREMEA SPAȚIALĂ & AURORĂ")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(ThemeColors.fgMutedDark)

                            if let sw = liveService.spaceWeather {
                                HStack {
                                    Image(systemName: "waveform.path.ecg")
                                        .foregroundColor(ThemeColors.accentCyan)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Index Geomagnetic Kp: \(String(format: "%.1f", sw.kpIndex))")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white)
                                        Text(sw.isAuroraAlertActive ? "ALERTA AURORĂ ACTIVĂ" : "Câmp geomagnetic liniștit.")
                                            .font(.system(size: 11))
                                            .foregroundColor(sw.isAuroraAlertActive ? ThemeColors.accentGreen : ThemeColors.fgMutedDark)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Recomandările Nopții")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Gata") { showingDrawer = false }
                        .foregroundColor(ThemeColors.accentCyan)
                }
            }
        }
    }

    private func cardinalDirection(for az: Double) -> String {
        switch az {
        case 337.5...360, 0..<22.5: return "N"
        case 22.5..<67.5: return "NE"
        case 67.5..<112.5: return "E"
        case 112.5..<157.5: return "SE"
        case 157.5..<202.5: return "S"
        case 202.5..<247.5: return "SW"
        case 247.5..<292.5: return "W"
        case 292.5..<337.5: return "NW"
        default: return "N"
        }
    }
}
