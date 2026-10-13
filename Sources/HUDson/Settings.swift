import SwiftUI

enum HUDPosition: String, CaseIterable {
    case topRight, rightEdge, bottomCenter

    var title: String {
        switch self {
        case .topRight: "Top Right"
        case .rightEdge: "Right Edge"
        case .bottomCenter: "Bottom Center"
        }
    }

    var isVertical: Bool { self == .rightEdge }

    /// The HUD slides in from (and back out to) the nearest screen edge.
    var entryEdge: Edge {
        switch self {
        case .topRight: .top
        case .rightEdge: .trailing
        case .bottomCenter: .bottom
        }
    }
}

enum Settings {
    private static let defaults = UserDefaults.standard

    static var position: HUDPosition {
        get { defaults.string(forKey: "position").flatMap(HUDPosition.init) ?? .topRight }
        set { defaults.set(newValue.rawValue, forKey: "position") }
    }

    static var hideMenuBarIcon: Bool {
        get { defaults.bool(forKey: "hideMenuBarIcon") }
        set { defaults.set(newValue, forKey: "hideMenuBarIcon") }
    }

    /// The system's "Play feedback when volume is changed" switch.
    static var volumeFeedback: Bool {
        defaults.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.sound.beep.feedback"] as? Int == 1
    }
}
