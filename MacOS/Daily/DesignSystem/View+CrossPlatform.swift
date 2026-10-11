import SwiftUI
import AppKit

#if os(macOS)
public enum NavigationBarItem {
    public enum TitleDisplayMode {
        case inline
        case automatic
        case large
    }
}

public enum UIKeyboardType {
    case numberPad
    case numbersAndPunctuation
    case decimalPad
    case `default`
    case emailAddress
}

public extension View {
    @ViewBuilder
    func navigationBarTitleDisplayMode(_ mode: NavigationBarItem.TitleDisplayMode) -> some View {
        self
    }
    
    @ViewBuilder
    func keyboardType(_ type: UIKeyboardType) -> some View {
        self
    }
}

public struct UIPasteboard {
    public static let general = UIPasteboard()
    
    public var string: String? {
        get {
            NSPasteboard.general.string(forType: .string)
        }
        set {
            if let newValue = newValue {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(newValue, forType: .string)
            }
        }
    }
}

public struct UIImpactFeedbackGenerator {
    public enum FeedbackStyle {
        case heavy, medium, light, soft, rigid
    }
    public init(style: FeedbackStyle = .medium) {}
    public func impactOccurred() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}

public extension ToolbarItemPlacement {
    static var navigationBarTrailing: ToolbarItemPlacement { .primaryAction }
    static var navigationBarLeading: ToolbarItemPlacement { .cancellationAction }
    static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
    static var topBarLeading: ToolbarItemPlacement { .cancellationAction }
    static var bottomBar: ToolbarItemPlacement { .automatic }
}

public enum TextInputAutocapitalization {
    case never, words, sentences, characters
}

public extension View {
    @ViewBuilder
    func textInputAutocapitalization(_ autocapitalization: TextInputAutocapitalization?) -> some View {
        self
    }
}

public typealias UIImage = NSImage

public extension Image {
    init(uiImage: NSImage) {
        self.init(nsImage: uiImage)
    }
}

public extension DatePickerStyle where Self == StepperFieldDatePickerStyle {
    static var wheel: StepperFieldDatePickerStyle { .stepperField }
}
#endif
