import SwiftUI
import DailyCore

/// Represents the active view target displayed in the secondary / detail pane
/// of the adaptive dual-pane foldable layout on expanded displays (e.g. iPhone Duo).
public enum FoldableDetailTarget: Equatable, Sendable {
    /// Default persistent companion view showing diurnal wish header, concentric rings, live mascot, and executive multi-hub digest
    case companion
    
    /// Full functional Hub embedded in the right pane
    case hub(NavigationTab)
    
    /// User settings view embedded in the right pane
    case settings
    
    /// Dashboard widget customization embedded in the right pane
    case customize
}
