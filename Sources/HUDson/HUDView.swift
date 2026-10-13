import SwiftUI

struct HUDSymbol: Equatable {
    var name: String
    /// Lights up the symbol's layers by level (speaker waves).
    var variableValue: Double?
    var rotation: Double = 0
}

final class HUDModel: ObservableObject {
    @Published var value: Double = 0
    @Published var symbol = HUDSymbol(name: "speaker.wave.3.fill")
    @Published var vertical = false
    @Published var isVisible = false
    /// Entrance in two beats: a thin line stretches out, then puffs up to full thickness.
    @Published var revealLength: CGFloat = 0
    @Published var revealThickness: CGFloat = 0
    @Published var entryEdge: Edge = .top
    /// Signed squash & stretch: positive pushes toward max, negative toward min.
    @Published var stretch: CGFloat = 0
    /// 0…1 wobble of the fill's edge, kicked on every change and left to settle.
    @Published var slosh: CGFloat = 0
    @Published var bounce = 0
    @Published var wiggle = 0
}

struct HUDView: View {
    @ObservedObject var model: HUDModel

    static func pillSize(vertical: Bool) -> CGSize {
        vertical ? CGSize(width: 54, height: 210) : CGSize(width: 240, height: 44)
    }

    static func cornerRadius(vertical: Bool) -> CGFloat { vertical ? 15 : 12 }

    var body: some View {
        let size = Self.pillSize(vertical: model.vertical)
        let radius = Self.cornerRadius(vertical: model.vertical)
        // Squash along one axis, bulge a little across the other, so it reads as elastic.
        let along = 1 + 0.045 * model.stretch
        let across = 1 - 0.025 * model.stretch

        LevelPill(model: model, cornerRadius: radius)
            .frame(width: size.width, height: size.height)
            .background {
                PillReveal(length: model.revealLength, thickness: model.revealThickness,
                           vertical: model.vertical, cornerRadius: radius)
                    .fill(.black.opacity(0.22))
                    .blur(radius: 12)
                    .offset(y: 6)
            }
            .scaleEffect(x: model.vertical ? across : along,
                         y: model.vertical ? along : across,
                         anchor: model.vertical ? .bottom : .leading)
            .scaleEffect(model.isVisible ? 1 : 0.86, anchor: entryAnchor)
            .offset(model.isVisible ? .zero : entryOffset)
            .blur(radius: model.isVisible ? 0 : 4)
            .opacity(model.isVisible ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.colorScheme, .dark)
    }

    private var entryOffset: CGSize {
        switch model.entryEdge {
        case .top: CGSize(width: 0, height: -8)
        case .bottom: CGSize(width: 0, height: 8)
        case .leading: CGSize(width: -12, height: 0)
        case .trailing: CGSize(width: 12, height: 0)
        }
    }

    private var entryAnchor: UnitPoint {
        switch model.entryEdge {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }
}

/// Light fill over a dark frosted track, with the icon punched out of both so the blurred
/// desktop shows through it.
private struct LevelPill: View {
    @ObservedObject var model: HUDModel
    let cornerRadius: CGFloat

    var body: some View {
        let vertical = model.vertical
        TimelineView(.animation(paused: !model.isVisible)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 7
            GeometryReader { geo in
                let length = vertical ? geo.size.height : geo.size.width
                let thickness = vertical ? geo.size.width : geo.size.height
                // The icon's square is always on the fill, even at zero.
                let filled = thickness + (length - thickness) * min(max(model.value, 0), 1)

                ZStack(alignment: vertical ? .bottom : .leading) {
                    Color.black.opacity(0.42)
                    SloshFill(length: filled, wobble: model.slosh * 2.6, phase: phase, vertical: vertical)
                        .fill(Color(white: 0.92))
                    icon(size: thickness)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(PillReveal(length: model.revealLength, thickness: model.revealThickness,
                              vertical: model.vertical, cornerRadius: cornerRadius))
    }

    private func icon(size: CGFloat) -> some View {
        Image(systemName: model.symbol.name, variableValue: model.symbol.variableValue)
            .font(.system(size: size * 0.38, weight: .medium))
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: model.bounce)
            .symbolEffect(.wiggle, value: model.wiggle)
            .rotationEffect(.degrees(model.symbol.rotation))
            .scaleEffect(0.3 + 0.7 * model.revealThickness)
            .frame(width: size, height: size)
    }
}

/// The visible part of the pill during the entrance: a centered capsule that grows from a thin,
/// shorter line to the full pill. Content stays laid out at full size underneath.
private struct PillReveal: Shape {
    var length: CGFloat
    var thickness: CGFloat
    let vertical: Bool
    let cornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(length, thickness) }
        set { length = newValue.first; thickness = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let line: CGFloat = 5
        let fullLength = vertical ? rect.height : rect.width
        let fullThickness = vertical ? rect.width : rect.height
        let l = fullLength * (0.55 + 0.45 * length)
        let t = line + (fullThickness - line) * thickness
        let size = vertical ? CGSize(width: t, height: l) : CGSize(width: l, height: t)
        let shape = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                           width: size.width, height: size.height)
        let radius = min(cornerRadius, min(size.width, size.height) / 2)
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: shape)
    }
}

/// The fill, with a sine-wave edge whose amplitude (`wobble`) is animated down to a flat line.
private struct SloshFill: Shape {
    var length: CGFloat
    var wobble: CGFloat
    var phase: Double
    let vertical: Bool

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(length, wobble) }
        set { length = newValue.first; wobble = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let total = vertical ? rect.height : rect.width
        let edgeSpan = vertical ? rect.width : rect.height
        // Calm down near the far end so a full bar doesn't flicker the track at its tip.
        let amplitude = wobble * min(1, max(0, total - length) / 8)
        let wavelength: CGFloat = 26
        func offset(_ s: CGFloat) -> CGFloat {
            amplitude * CGFloat(sin(Double(s / wavelength) * 2 * .pi + phase))
        }

        var path = Path()
        if vertical {
            let surface = rect.maxY - length
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            for s in stride(from: 0, through: edgeSpan, by: 2) {
                path.addLine(to: CGPoint(x: rect.minX + s, y: surface + offset(s)))
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            let edge = rect.minX + length
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            for s in stride(from: 0, through: edgeSpan, by: 2) {
                path.addLine(to: CGPoint(x: edge + offset(s), y: rect.minY + s))
            }
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

enum Symbols {
    static func volume(level: Float, muted: Bool, kind: AudioOutput.Kind) -> HUDSymbol {
        if muted || level == 0 { return HUDSymbol(name: "speaker.slash.fill") }
        switch kind {
        case .airPods: return HUDSymbol(name: "airpods")
        case .airPodsPro: return HUDSymbol(name: "airpodspro")
        case .airPodsMax: return HUDSymbol(name: "airpodsmax")
        case .headphones: return HUDSymbol(name: "headphones")
        case .display: return HUDSymbol(name: "tv")
        case .speakers: return HUDSymbol(name: "speaker.wave.3.fill", variableValue: Double(level))
        }
    }

    static func brightness(_ level: Float, builtIn: Bool) -> HUDSymbol {
        if !builtIn { return HUDSymbol(name: "display") }
        return HUDSymbol(name: "sun.max.fill", rotation: Double(level) * 120)
    }
}
