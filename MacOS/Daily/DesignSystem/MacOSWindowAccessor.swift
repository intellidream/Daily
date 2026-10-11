import SwiftUI
import AppKit

public struct MacOSWindowAccessor: NSViewRepresentable {
    public var configure: (NSWindow) -> Void
    
    public init(configure: @escaping (NSWindow) -> Void) {
        self.configure = configure
    }
    
    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }
    
    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                configure(window)
            }
        }
    }
}

public extension View {
    func configureMacOSWindow(minWidth: CGFloat = 440, minHeight: CGFloat = 650) -> some View {
        self.background(
            MacOSWindowAccessor { window in
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = true
                window.minSize = NSSize(width: minWidth, height: minHeight)
            }
        )
    }
}
