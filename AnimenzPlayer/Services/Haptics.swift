import Foundation

#if os(iOS)
import UIKit
#endif

/// Tiny cross-platform haptics wrapper. No-ops on macOS.
enum Haptics {
    enum Event {
        case selection     // light tick for selection changes (track tap)
        case impactSoft    // skip, shuffle toggle
        case success       // favorite added
        case warning       // sleep timer expired
    }

    static func play(_ event: Event) {
        #if os(iOS)
        switch event {
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .impactSoft:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        #endif
    }
}
