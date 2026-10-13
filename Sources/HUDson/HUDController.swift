import AppKit
import SwiftUI

/// Owns the floating panel and the show / auto-hide timing.
final class HUDController {
    var position: HUDPosition
    /// Never auto-hide; used by `--preview`.
    var persistent = false

    private let model = HUDModel()
    private let panel: NSPanel
    private var hideWork: DispatchWorkItem?
    /// Room around the pill for its shadow, the entry slide and the blur-in.
    private static let margin: CGFloat = 40

    init(position: HUDPosition) {
        self.position = position
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
    }

    func show(value: Double, symbol: HUDSymbol, on screen: NSScreen?, hitLimit: Bool = false) {
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = frame(on: screen)
        let appearing = !model.isVisible || panel.frame != frame
        let previous = (value: model.value, muted: model.symbol.name.contains("slash"))

        if appearing {
            // Appear already at the new level instead of sweeping from the last one.
            model.vertical = position.isVertical
            model.entryEdge = position.entryEdge
            model.value = value
            model.symbol = symbol
            model.stretch = 0
            model.slosh = 0
            model.revealLength = 0
            model.revealThickness = 0
            panel.setFrame(frame, display: false)
            panel.orderFrontRegardless()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.75)) {
                model.isVisible = true
                model.revealLength = 1
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.62).delay(0.1)) {
                model.revealThickness = 1
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                model.value = value
                model.symbol = symbol
            }
        }

        if symbol.name.contains("slash") != previous.muted && !appearing {
            model.wiggle += 1
        } else if hitLimit {
            kick(value >= 0.5 ? 1 : -1)
            model.bounce += 1
        } else if !appearing && value != previous.value {
            kick(value > previous.value ? 0.3 : -0.3)
            model.bounce += 1
        }
        scheduleHide()
    }

    /// Squash toward the change and make the fill's edge slosh, then let both settle.
    private func kick(_ amount: CGFloat) {
        withAnimation(.easeOut(duration: 0.07)) {
            model.stretch = amount
            model.slosh = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { [model] in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.45)) { model.stretch = 0 }
            withAnimation(.easeOut(duration: 1.1)) { model.slosh = 0 }
        }
    }

    private func scheduleHide() {
        hideWork?.cancel()
        guard !persistent else { return }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func hide() {
        // The entrance in reverse: deflate to a line, then shrink and fade.
        withAnimation(.easeIn(duration: 0.16)) { model.revealThickness = 0 }
        withAnimation(.easeIn(duration: 0.22).delay(0.1)) {
            model.revealLength = 0
            model.isVisible = false
        } completion: { [weak self] in
            guard let self, !self.model.isVisible else { return }
            self.panel.orderOut(nil)
        }
    }

    private func frame(on screen: NSScreen) -> NSRect {
        let size = HUDView.pillSize(vertical: position.isVertical)
        let full = screen.frame
        let visible = screen.visibleFrame // below the menu bar, above the Dock
        let inset: CGFloat = 12
        let origin: NSPoint
        switch position {
        case .topRight:
            origin = NSPoint(x: full.maxX - inset - size.width, y: visible.maxY - inset - size.height)
        case .rightEdge:
            origin = NSPoint(x: full.maxX - inset - size.width, y: full.midY - size.height / 2)
        case .bottomCenter:
            origin = NSPoint(x: full.midX - size.width / 2, y: visible.minY + 48)
        }
        return NSRect(origin: origin, size: size).insetBy(dx: -Self.margin, dy: -Self.margin)
    }
}
