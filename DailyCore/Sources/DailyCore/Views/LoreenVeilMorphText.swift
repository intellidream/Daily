#if canImport(SwiftUI)
import SwiftUI

/// GPU-composited `TextRenderer` that sweeps a left-to-right "movie password decrypt"
/// sparkle (`✦`) and micro-dot (`•`) burst across glyphs during Loreen ↔ Latin transitions.
/// At rest (`progress <= 0.001`), it draws lines directly with zero filter or particle overhead.
@available(iOS 18.0, macOS 15.0, *)
public struct LoreenWaveTextRenderer: TextRenderer, Sendable {
    public var progress: Double
    public let isIncoming: Bool

    public var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    public init(progress: Double, isIncoming: Bool) {
        self.progress = progress
        self.isIncoming = isIncoming
    }

    public func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize {
        text.sizeThatFits(proposal)
    }

    public func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        if progress <= 0.001 {
            for line in layout {
                context.draw(line)
            }
            return
        }

        let runs = layout.flatMap { Array($0) }
        let glyphCount = runs.reduce(0) { $0 + $1.count }

        if glyphCount <= 64 && glyphCount > 0 {
            var idx = 0
            for run in runs {
                for slice in run {
                    let localT = normalizedLocalT(index: idx, total: glyphCount)
                    let copy = configuredContext(base: context, localT: localT)
                    copy.draw(slice)
                    if isIncoming {
                        drawSparkles(in: &context, rect: slice.typographicBounds.rect, localT: localT, seedBase: idx * 31 + 7, count: 5)
                    }
                    idx += 1
                }
            }
        } else {
            let total = max(1, runs.count)
            for (idx, run) in runs.enumerated() {
                let localT = normalizedLocalT(index: idx, total: total)
                let copy = configuredContext(base: context, localT: localT)
                copy.draw(run)
                if isIncoming {
                    drawSparkles(in: &context, rect: run.typographicBounds.rect, localT: localT, seedBase: idx * 53 + 11, count: 8)
                }
            }
        }
    }

    private func normalizedLocalT(index: Int, total: Int) -> Double {
        let staggerSpan = 0.48
        let activeWindow = 1.0 - staggerSpan
        let delay = total > 1 ? (Double(index) / Double(total - 1)) * staggerSpan : 0.0

        if isIncoming {
            let p = 1.0 - progress
            let appeared = min(1.0, max(0.0, (p - delay) / activeWindow))
            return 1.0 - appeared
        } else {
            return min(1.0, max(0.0, (progress - delay) / activeWindow))
        }
    }

    private func configuredContext(base: GraphicsContext, localT: Double) -> GraphicsContext {
        var copy = base
        let glyphAlpha = max(0.0, 1.0 - localT * 1.38)
        copy.opacity = glyphAlpha
        if localT > 0.01 && glyphAlpha > 0.01 {
            copy.addFilter(.blur(radius: localT * 1.6))
            let glow = sin(localT * .pi)
            if glow > 0.05 {
                copy.addFilter(.brightness(glow * 0.25))
            }
            copy.translateBy(x: 0, y: (isIncoming ? 1.8 : -1.8) * localT)
        }
        return copy
    }

    private func drawSparkles(
        in context: inout GraphicsContext,
        rect: CGRect,
        localT: Double,
        seedBase: Int,
        count: Int
    ) {
        let sparkleIntensity = sin(localT * .pi)
        guard sparkleIntensity > 0.06, rect.width > 0.5, rect.height > 0.5 else { return }

        let padded = rect.insetBy(dx: -1.5, dy: -1.5)
        for k in 0..<count {
            let h1 = hash01(seedBase &+ k &* 17)
            let h2 = hash01(seedBase &+ k &* 37 &+ 3)
            let h3 = hash01(seedBase &+ k &* 71 &+ 9)
            let h4 = hash01(seedBase &+ k &* 101 &+ 13)

            let driftX = (h3 - 0.5) * 6.4 * sparkleIntensity
            let driftY = (h4 - 0.5) * 6.4 * sparkleIntensity
            let px = padded.minX + padded.width * (0.1 + 0.8 * h1) + driftX
            let py = padded.minY + padded.height * (0.1 + 0.8 * h2) + driftY

            let twinkle = 0.55 + 0.45 * sin((localT * 3.5 + h3 * 2.0) * .pi)
            let alpha = min(1.0, sparkleIntensity * 1.25 * twinkle)
            let color = sparkleColor(index: k)

            var pContext = context
            pContext.opacity = alpha

            if k == 0 || (k == 3 && rect.height >= 13.0) {
                let r = (2.0 + 1.4 * h4) * twinkle
                let star = fourPointSparklePath(center: CGPoint(x: px, y: py), radius: r)
                pContext.fill(star, with: .color(color))
            } else {
                let r = (0.9 + 1.0 * h4) * twinkle
                let dotRect = CGRect(x: px - r, y: py - r, width: r * 2.0, height: r * 2.0)
                pContext.fill(Path(ellipseIn: dotRect), with: .color(color))
            }
        }
    }

    private func fourPointSparklePath(center: CGPoint, radius: CGFloat) -> Path {
        let inner = radius * 0.24
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + inner, y: center.y - inner))
        path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x + inner, y: center.y + inner))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        path.addLine(to: CGPoint(x: center.x - inner, y: center.y + inner))
        path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x - inner, y: center.y - inner))
        path.closeSubpath()
        return path
    }

    private func sparkleColor(index: Int) -> Color {
        switch index % 3 {
        case 0:
            return Color(red: 0.22, green: 0.91, blue: 1.0) // Electric Cyan
        case 1:
            return Color.white // Starlight White
        default:
            return Color(red: 0.72, green: 0.52, blue: 1.0) // Soft Violet
        }
    }

    private func hash01(_ seed: Int) -> Double {
        var x = UInt64(bitPattern: Int64(seed))
        x = (x ^ (x >> 30)) &* 0xbf58476d1ce4e5b9
        x = (x ^ (x >> 27)) &* 0x94d049bb133111eb
        x = x ^ (x >> 31)
        return Double(x & 0xFFFF) / 65535.0
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct LoreenCipherAnimatableModifier: ViewModifier, Animatable {
    var progress: Double
    let isIncoming: Bool

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        if progress <= 0.001 {
            content
        } else {
            content.textRenderer(LoreenWaveTextRenderer(progress: progress, isIncoming: isIncoming))
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
@MainActor
public enum LoreenVeilTransitions {
    public static let cipherWave: AnyTransition = .asymmetric(
        insertion: .modifier(
            active: LoreenCipherAnimatableModifier(progress: 1, isIncoming: true),
            identity: LoreenCipherAnimatableModifier(progress: 0, isIncoming: true)
        ),
        removal: .modifier(
            active: LoreenCipherAnimatableModifier(progress: 1, isIncoming: false),
            identity: LoreenCipherAnimatableModifier(progress: 0, isIncoming: false)
        )
    )
}

/// Renders plain text in either Loreen Script or the system font with a 120Hz GPU sparkle & micro-dot decrypt sweep.
/// At rest, only one `Text` view is active with zero `TextRenderer`, particle, or blur overhead.
@available(iOS 18.0, macOS 15.0, *)
public struct LoreenVeilText: View {
    public let text: String
    public let isVeiled: Bool
    public let size: CGFloat
    public let weight: Font.Weight
    public let design: Font.Design
    public let strikethrough: Bool
    public let strikethroughColor: Color?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ text: String,
        isVeiled: Bool,
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        strikethrough: Bool = false,
        strikethroughColor: Color? = nil
    ) {
        self.text = text
        self.isVeiled = isVeiled
        self.size = size
        self.weight = weight
        self.design = design
        self.strikethrough = strikethrough
        self.strikethroughColor = strikethroughColor
    }

    public var body: some View {
        let transition: AnyTransition = reduceMotion ? .opacity : LoreenVeilTransitions.cipherWave
        let anim: Animation = reduceMotion ? .easeInOut(duration: 0.16) : .easeInOut(duration: 0.46)

        ZStack(alignment: .leading) {
            if isVeiled {
                Text(text)
                    .font(.loreen(size: size))
                    .strikethrough(strikethrough, color: strikethroughColor)
                    .transition(transition)
            } else {
                Text(text)
                    .font(.system(size: size, weight: weight, design: design))
                    .strikethrough(strikethrough, color: strikethroughColor)
                    .transition(transition)
            }
        }
        .animation(anim, value: isVeiled)
    }
}

/// Renders Markdown text (`LocalizedStringKey`) in either Loreen Script or the system font
/// with the same zero-idle-overhead sparkle & micro-dot decrypt sweep.
@available(iOS 18.0, macOS 15.0, *)
public struct LoreenVeilMarkdownText: View {
    public let text: String
    public let isVeiled: Bool
    public let size: CGFloat
    public let weight: Font.Weight

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ text: String,
        isVeiled: Bool,
        size: CGFloat,
        weight: Font.Weight = .regular
    ) {
        self.text = text
        self.isVeiled = isVeiled
        self.size = size
        self.weight = weight
    }

    public var body: some View {
        let transition: AnyTransition = reduceMotion ? .opacity : LoreenVeilTransitions.cipherWave
        let anim: Animation = reduceMotion ? .easeInOut(duration: 0.16) : .easeInOut(duration: 0.46)

        ZStack(alignment: .leading) {
            if isVeiled {
                Text(LocalizedStringKey(text))
                    .font(.loreen(size: size))
                    .transition(transition)
            } else {
                Text(LocalizedStringKey(text))
                    .font(.system(size: size, weight: weight))
                    .transition(transition)
            }
        }
        .animation(anim, value: isVeiled)
    }
}
#endif
