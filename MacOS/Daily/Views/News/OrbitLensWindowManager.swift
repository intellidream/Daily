import AppKit
import Combine
import SwiftUI
import DailyCore

@MainActor
private final class OrbitLensWindowState: ObservableObject {
    @Published var cluster: StoryCluster
    @Published var activeArticleLink: String?
    var onSelectArticle: (NewsArticle) -> Void
    var onOpenInPrism: (NewsArticle) -> Void

    init(
        cluster: StoryCluster,
        activeArticleLink: String? = nil,
        onSelectArticle: @escaping (NewsArticle) -> Void,
        onOpenInPrism: @escaping (NewsArticle) -> Void
    ) {
        self.cluster = cluster
        self.activeArticleLink = activeArticleLink
        self.onSelectArticle = onSelectArticle
        self.onOpenInPrism = onOpenInPrism
    }
}

/// Hosts `Orbit Lens` (`PerspectivesComparisonPane`) inside a spacious, resizable native macOS window
/// so dual-pane and compact main windows are never cramped or clipped to half-width.
@MainActor
public final class OrbitLensWindowManager: NSObject, NSWindowDelegate {
    public static let shared = OrbitLensWindowManager()

    private var lensController: NSWindowController?
    private var lensState: OrbitLensWindowState?

    private override init() {
        super.init()
    }

    public func open(
        cluster: StoryCluster,
        activeArticleLink: String? = nil,
        onSelectArticle: @escaping (NewsArticle) -> Void,
        onOpenInPrism: @escaping (NewsArticle) -> Void
    ) {
        if let existing = lensController?.window, let state = lensState {
            state.cluster = cluster
            state.activeArticleLink = activeArticleLink
            state.onSelectArticle = onSelectArticle
            state.onOpenInPrism = onOpenInPrism
            existing.title = "Orbit Lens — \(cluster.leadArticle.title)"
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let state = OrbitLensWindowState(
            cluster: cluster,
            activeArticleLink: activeArticleLink,
            onSelectArticle: onSelectArticle,
            onOpenInPrism: onOpenInPrism
        )
        self.lensState = state

        let contentWidth: CGFloat = 660
        let contentHeight: CGFloat = 760
        var origin = NSPoint(x: 200, y: 120)

        if let anchorWindow = NSApp.keyWindow ?? NSApp.mainWindow,
           let screen = anchorWindow.screen ?? NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            let anchorFrame = anchorWindow.frame
            let rightRoom = visible.maxX - anchorFrame.maxX
            if rightRoom >= contentWidth + 24 {
                origin.x = anchorFrame.maxX + 16
            } else if anchorFrame.minX - visible.minX >= contentWidth + 24 {
                origin.x = anchorFrame.minX - contentWidth - 16
            } else {
                origin.x = visible.midX - (contentWidth / 2)
            }
            origin.y = max(visible.minY + 16, min(anchorFrame.maxY - contentHeight, visible.maxY - contentHeight - 16))
        } else if let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            origin.x = visible.midX - (contentWidth / 2)
            origin.y = visible.midY - (contentHeight / 2)
        }

        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: NSSize(width: contentWidth, height: contentHeight)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 520, height: 540)
        window.title = "Orbit Lens — \(cluster.leadArticle.title)"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self

        let rootView = OrbitLensHostedRootView(state: state) { [weak window] in
            window?.close()
        }
        window.contentView = NSHostingView(rootView: rootView)

        let controller = NSWindowController(window: window)
        lensController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func updateActiveArticleLink(_ link: String) {
        lensState?.activeArticleLink = link
    }

    public func close() {
        lensController?.window?.close()
    }

    public func windowWillClose(_ notification: Notification) {
        if let closing = notification.object as? NSWindow, closing === lensController?.window {
            lensController = nil
            lensState = nil
        }
    }
}

private struct OrbitLensHostedRootView: View {
    @ObservedObject var state: OrbitLensWindowState
    let onClose: () -> Void

    var body: some View {
        PerspectivesComparisonPane(
            cluster: state.cluster,
            activeArticleLink: state.activeArticleLink,
            isSplitPane: false,
            isInSeparateWindow: true,
            onSelectArticle: { article in
                state.activeArticleLink = article.link
                state.onSelectArticle(article)
            },
            onOpenInPrism: { article in
                onClose()
                state.onOpenInPrism(article)
            },
            onClose: onClose
        )
        .id(state.cluster.id)
    }
}
