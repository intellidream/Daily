import SwiftUI
import AppKit

/// A smooth, interactive marquee view that renders text at full width on macOS.
/// If the text exceeds the container width, it automatically scrolls from start to end (and back)
/// so the entire title can be read.
public struct AutoScrollingText: View {
    public let text: String
    public let fontSize: CGFloat
    public let weight: Font.Weight
    public let design: Font.Design
    public let color: Color
    public let alignment: Alignment
    public let fixedContainerWidth: CGFloat?
    
    @State private var offset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var measuredContainerWidth: CGFloat = 0
    @State private var scrollTask: Task<Void, Never>? = nil
    
    public init(
        text: String,
        fontSize: CGFloat = 15,
        weight: Font.Weight = .bold,
        design: Font.Design = .default,
        color: Color = .white,
        alignment: Alignment = .leading,
        fixedContainerWidth: CGFloat? = nil
    ) {
        self.text = text
        self.fontSize = fontSize
        self.weight = weight
        self.design = design
        self.color = color
        self.alignment = alignment
        self.fixedContainerWidth = fixedContainerWidth
    }
    
    private var intrinsicWidth: CGFloat {
        let nsWeight: NSFont.Weight
        switch weight {
        case .bold: nsWeight = .bold
        case .semibold: nsWeight = .semibold
        case .medium: nsWeight = .medium
        case .regular: nsWeight = .regular
        case .heavy: nsWeight = .heavy
        case .black: nsWeight = .black
        default: nsWeight = .bold
        }
        
        var nsFont = NSFont.systemFont(ofSize: fontSize, weight: nsWeight)
        if design == .rounded, let descriptor = nsFont.fontDescriptor.withDesign(.rounded) {
            nsFont = NSFont(descriptor: descriptor, size: fontSize) ?? nsFont
        }
        
        let size = (text as NSString).size(withAttributes: [.font: nsFont])
        return ceil(size.width)
    }
    
    public var body: some View {
        let effectiveContainerWidth = fixedContainerWidth ?? measuredContainerWidth
        let isTooLong = effectiveContainerWidth > 0 && intrinsicWidth > effectiveContainerWidth
        let maxScroll = max(0, intrinsicWidth - effectiveContainerWidth + 8)
        
        Group {
            if let fixedWidth = fixedContainerWidth {
                contentView(isTooLong: isTooLong, maxScroll: maxScroll, containerWidth: fixedWidth)
                    .frame(width: fixedWidth)
            } else {
                GeometryReader { geo in
                    let w = geo.size.width
                    contentView(isTooLong: isTooLong, maxScroll: maxScroll, containerWidth: w)
                        .frame(width: w)
                        .onAppear {
                            measuredContainerWidth = w
                        }
                        .onChange(of: w) { _, newVal in
                            measuredContainerWidth = newVal
                        }
                }
            }
        }
        .frame(height: fontSize + 10)
        .clipped()
    }
    
    @ViewBuilder
    private func contentView(isTooLong: Bool, maxScroll: CGFloat, containerWidth: CGFloat) -> some View {
        if !isTooLong {
            Text(text)
                .font(.system(size: fontSize, weight: weight, design: design))
                .foregroundColor(color)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: alignment)
        } else {
            HStack(spacing: 0) {
                Text(text)
                    .font(.system(size: fontSize, weight: weight, design: design))
                    .foregroundColor(color)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: offset + dragOffset)
                
                Spacer(minLength: 0)
            }
            .frame(width: containerWidth, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        isDragging = true
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        let combined = offset + value.translation.width
                        offset = min(0, max(-maxScroll, combined))
                        dragOffset = 0
                        isDragging = false
                        startAutoScroll(maxScroll: maxScroll)
                    }
            )
            .onAppear {
                startAutoScroll(maxScroll: maxScroll)
            }
            .onDisappear {
                scrollTask?.cancel()
                scrollTask = nil
            }
            .onChange(of: text) { _, _ in
                offset = 0
                dragOffset = 0
                startAutoScroll(maxScroll: maxScroll)
            }
        }
    }
    
    private func startAutoScroll(maxScroll: CGFloat) {
        scrollTask?.cancel()
        guard maxScroll > 0 else { return }
        
        scrollTask = Task { @MainActor in
            // Initial delay to let the user read the start
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            
            while !Task.isCancelled {
                guard !isDragging else {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                
                let forwardSpeed: Double = 30.0
                let forwardDuration = max(2.0, Double(maxScroll) / forwardSpeed)
                let returnDuration = max(1.5, Double(maxScroll) / (forwardSpeed * 1.5))
                
                withAnimation(.easeInOut(duration: forwardDuration)) {
                    self.offset = -maxScroll
                }
                try? await Task.sleep(nanoseconds: UInt64((forwardDuration + 1.2) * 1_000_000_000))
                if Task.isCancelled || isDragging { continue }
                
                withAnimation(.easeInOut(duration: returnDuration)) {
                    self.offset = 0
                }
                try? await Task.sleep(nanoseconds: UInt64((returnDuration + 1.8) * 1_000_000_000))
            }
        }
    }
}
