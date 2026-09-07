import SwiftUI
import FingeringEngine

/// The fretboard is StringMap's hero, not a diagram in a corner. It is drawn as
/// a rosewood faceplate mounted into the app's cream chassis — nickel fret
/// wire, a bone nut, bronze strings — because a pale diagram on a pale page
/// gives light nowhere to go. On a dark board the route actually glows.
struct TeachingBarre: Decodable {
    let fret: Int
    let firstString: Int
    let lastString: Int
    let finger: Int
}

struct FretboardTeaching {
    var fingers: [GuitarPosition: Int] = [:]
    var mutedStrings: Set<Int> = []
    var maxFret = 5
    var rootPitchClass: Int? = nil
    var barre: TeachingBarre?
    var select: ((GuitarPosition) -> Void)? = nil
}

struct FretboardView: View {
    let tuning: GuitarTuning
    let capo: Int
    let maxFret: Int
    let active: GuitarPosition?
    var sounding: [GuitarPosition] = []
    let upcoming: GuitarPosition?
    var leftHanded = false
    var isExpanded = false
    var teaching: FretboardTeaching? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visibleFrets: Int {
        if let teaching { return teaching.maxFret }
        let reach = max(active?.fret ?? 0, upcoming?.fret ?? 0)
        return max(5, min(maxFret - capo, max(12, max(reach, sounding.map(\.fret).max() ?? 0) + 1)))
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = Metrics(
                size: geometry.size,
                frets: visibleFrets,
                leftHanded: leftHanded,
                expanded: isExpanded,
                compactTeaching: teaching != nil && geometry.size.width < 500
            )

            ZStack(alignment: .topLeading) {
                faceplate(metrics)
                board(metrics)
                inlays(metrics)
                fretWires(metrics)
                strings(metrics)
                if capo > 0 { capoBar(metrics) } else { nut(metrics) }
                route(metrics)
                if let teaching { teachingBarre(teaching, metrics) }
                markers(metrics)
                stringLabels(metrics)
                fretNumbers(metrics)
                if let teaching { teachingOverlay(teaching, metrics) }
            }
            // The glow is light on the wood, so it stops at the edge of the
            // plate rather than bleeding onto the page behind it.
            .clipShape(RoundedRectangle(cornerRadius: metrics.plateRadius, style: .continuous))
        }
        .accessibilityElement(children: teaching == nil ? .ignore : .contain)
        .accessibilityLabel("Guitar fretboard")
        .accessibilityIdentifier("guitarFretboard")
        .accessibilityValue(accessibilityDescription)
    }

    private var soundingPositions: [GuitarPosition] {
        Array(Set(sounding + (active.map { [$0] } ?? []))).sorted { $0.string < $1.string }
    }

    private var accessibilityDescription: String {
        var text = active.map { "Now: string \($0.string), fret \($0.fret)" } ?? "No note sounding"
        if let upcoming { text += ". Next: string \(upcoming.string), fret \(upcoming.fret)" }
        if capo > 0 { text += ". Capo at fret \(capo)" }
        if soundingPositions.count > 1 { text += ". Sounding chord: " + soundingPositions.map { "string \($0.string), fret \($0.fret)" }.joined(separator: "; ") }
        return text
    }

    // MARK: - Layers

    /// The mounted plate. It runs to the edge of the component so the string
    /// names and fret numbers sit on the instrument rather than beside it.
    private func faceplate(_ m: Metrics) -> some View {
        RoundedRectangle(cornerRadius: m.plateRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Palette.plateHighlight, Palette.boardEdge],
                    startPoint: .topLeading,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: m.plateRadius, style: .continuous)
                    .strokeBorder(Palette.plateEdge, lineWidth: 1)
            }
            .frame(width: m.size.width, height: m.size.height)
            .position(x: m.size.width / 2, y: m.size.height / 2)
    }

    private func board(_ m: Metrics) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Palette.plateHighlight, Palette.board, Palette.plateHighlight],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: m.boardWidth, height: m.boardHeight + m.boardPad * 2)
            .position(x: m.left + m.boardWidth / 2, y: m.top + m.boardHeight / 2)
    }

    private func inlays(_ m: Metrics) -> some View {
        ForEach(Self.inlayFrets.filter { $0 <= m.frets }, id: \.self) { fret in
            let centre = m.markerX(fret: fret)
            Group {
                if fret % 12 == 0 {
                    VStack(spacing: m.boardHeight * 0.28) {
                        inlayDot(m)
                        inlayDot(m)
                    }
                } else {
                    inlayDot(m)
                }
            }
            .position(x: centre, y: m.top + m.boardHeight / 2)
        }
    }

    private func inlayDot(_ m: Metrics) -> some View {
        Circle()
            .fill(Palette.inlay.opacity(0.55))
            .frame(width: m.inlaySize, height: m.inlaySize)
    }

    private func fretWires(_ m: Metrics) -> some View {
        ForEach(1...max(1, m.frets), id: \.self) { fret in
            let x = m.fretX(fret)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Palette.fretWire.opacity(0.55), Palette.fretWire, Palette.fretWire.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: m.expanded ? 1.6 : 1.1, height: m.boardHeight + m.boardPad * 2)
                .position(x: x, y: m.top + m.boardHeight / 2)
        }
    }

    private func strings(_ m: Metrics) -> some View {
        // String 1 (high E) is the thinnest and sits at the top, matching how a
        // player looks down at the instrument.
        ForEach(0..<6, id: \.self) { index in
            Rectangle()
                .fill(Palette.stringLine.opacity(0.9))
                .frame(width: m.boardWidth, height: m.stringGauge(index))
                .position(x: m.left + m.boardWidth / 2, y: m.stringY(index))
        }
    }

    private func nut(_ m: Metrics) -> some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Palette.bone)
            .frame(width: m.expanded ? 5 : 4, height: m.boardHeight + m.boardPad * 2 + 2)
            .position(x: m.fretX(0), y: m.top + m.boardHeight / 2)
    }

    private func capoBar(_ m: Metrics) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Palette.positionLocked)
            .frame(width: m.expanded ? 7 : 5, height: m.boardHeight + m.boardPad * 2 + 4)
            .position(x: m.fretX(0), y: m.top + m.boardHeight / 2)
            .shadow(color: Palette.positionLocked.opacity(0.5), radius: 4)
    }

    /// The route: the icon's connecting line, drawn between the note sounding
    /// now and the one after it.
    @ViewBuilder
    private func route(_ m: Metrics) -> some View {
        if soundingPositions.count == 1, let active, let upcoming, active.fret <= m.frets, upcoming.fret <= m.frets {
            let from = m.point(active)
            let to = m.point(upcoming)
            let path = Path { p in
                p.move(to: from)
                p.addLine(to: to)
            }
            ZStack {
                path.stroke(
                    LinearGradient(
                        colors: [Palette.positionActive, Palette.positionUpcoming],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: m.expanded ? 3.5 : 2.5, lineCap: .round)
                )
                .blur(radius: m.expanded ? 7 : 5)
                .opacity(0.85)

                path.stroke(
                    LinearGradient(
                        colors: [Palette.positionActive, Palette.positionUpcoming],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: m.expanded ? 2 : 1.5, lineCap: .round)
                )
            }
            .motion(Motion.travel, value: RoutePair(from: active, to: upcoming))
        }
    }

    @ViewBuilder
    private func markers(_ m: Metrics) -> some View {
        if let upcoming, upcoming.fret <= m.frets, !soundingPositions.contains(upcoming) {
            marker(upcoming, m: m, tint: Palette.positionUpcoming, isActive: false)
        }
        ForEach(soundingPositions.filter { $0.fret <= m.frets }, id: \.self) { position in
            marker(position, m: m, tint: Palette.positionActive, isActive: true)
        }
    }

    private func marker(
        _ position: GuitarPosition,
        m: Metrics,
        tint: Color,
        isActive: Bool
    ) -> some View {
        let point = m.point(position)
        let size = isActive ? m.markerSize : m.markerSize * 0.82
        return ZStack {
            // The glow reproduces the icon's lit nodes.
            Circle()
                .fill(tint)
                .frame(width: size * 1.5, height: size * 1.5)
                .blur(radius: size * 0.42)
                .opacity(glowOpacity(isActive: isActive))
            Circle()
                .fill(tint)
                .overlay { Circle().strokeBorder(.white.opacity(0.55), lineWidth: isActive ? 1.5 : 1) }
                .frame(width: size, height: size)
            Text(teaching.map { _ in position.fret == 0 ? "○" : String(teaching?.fingers[position] ?? position.fret) } ?? String(position.fret))
                .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .position(point)
        // A note change must land on its exact fret immediately, even at 200% tempo.
        .transaction { $0.animation = nil }
    }

    /// The board is dark in both appearances, so the glow no longer has to be
    /// dialled back for a pale background the way it once did.
    private func glowOpacity(isActive: Bool) -> Double {
        isActive ? 0.60 : 0.34
    }

    private func stringLabels(_ m: Metrics) -> some View {
        ForEach(0..<6, id: \.self) { index in
            Text(teaching == nil ? tuning.pitchNames[index].replacingOccurrences(of: "#", with: "♯") : (m.compactTeaching ? "\(index + 1)" : "\(index + 1) · \(tuning.pitchNames[index])"))
                .font(.system(size: m.expanded ? 11 : 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.onPlate)
                .position(
                    x: leftHanded ? m.size.width - m.gutter / 2 : m.gutter / 2,
                    y: m.stringY(index)
                )
        }
    }

    private func fretNumbers(_ m: Metrics) -> some View {
        ForEach(teaching == nil ? Self.inlayFrets.filter { $0 <= m.frets } : Array(0...m.frets), id: \.self) { fret in
            Text(String(fret + capo))
                .font(.system(size: m.expanded ? 10 : 8, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.onPlateDim)
                .position(x: m.markerX(fret: fret), y: m.top + m.boardHeight + m.bottom / 2)
        }
    }

    private static let inlayFrets = [3, 5, 7, 9, 12, 15, 17, 19, 21, 24]

    @ViewBuilder
    private func teachingBarre(_ teaching: FretboardTeaching, _ m: Metrics) -> some View {
        if let barre = teaching.barre, soundingPositions.contains(where: { $0.fret == barre.fret && (barre.firstString...barre.lastString).contains($0.string) }) {
            Capsule().fill(Palette.brand.opacity(0.6))
                .frame(width: 9, height: m.stringY(barre.lastString-1) - m.stringY(barre.firstString-1) + 12)
                .position(x: m.markerX(fret: barre.fret), y: (m.stringY(barre.firstString-1) + m.stringY(barre.lastString-1))/2)
                .accessibilityLabel("Finger \(barre.finger) barre: strings \(barre.firstString) through \(barre.lastString), fret \(barre.fret)")
        }
    }

    @ViewBuilder
    private func teachingOverlay(_ teaching: FretboardTeaching, _ m: Metrics) -> some View {
        if let root = teaching.rootPitchClass {
            ForEach(1...6, id: \.self) { string in
                ForEach((0...teaching.maxFret).filter { (tuning.openMIDIPitches[string-1] + $0) % 12 == root }, id: \.self) { fret in
                    Circle().stroke(.yellow.opacity(0.8), lineWidth: 2)
                        .frame(width: m.markerSize + 5, height: m.markerSize + 5)
                        .position(m.point(.init(string: string, fret: fret, midi: tuning.openMIDIPitches[string-1]+fret)))
                        .accessibilityLabel("Root note, string \(string), fret \(fret)")
                }
            }
        }
        ForEach(Array(teaching.mutedStrings).sorted(), id: \.self) { string in
            Text("×").font(.title3.bold()).foregroundStyle(Palette.onPlate)
                .position(m.point(GuitarPosition(string: string, fret: 0, midi: tuning.openMIDIPitches[string - 1])))
                .accessibilityLabel("Do not play string \(string)")
        }
        if let select = teaching.select {
            ForEach(1...6, id: \.self) { string in
                ForEach(0...teaching.maxFret, id: \.self) { fret in
                    let position = GuitarPosition(string: string, fret: fret, midi: tuning.openMIDIPitches[string - 1] + fret)
                    Button { select(position) } label: {
                        Color.white.opacity(0.001)
                            .frame(width: m.teachingHitWidth(fret: fret), height: m.boardHeight / 5)
                    }
                    .buttonStyle(.plain)
                    .position(m.point(position))
                    .accessibilityLabel("String \(string), \(fret == 0 ? "open" : "fret \(fret)"), \(tutorialPitchName(position.midi))")
                    .accessibilityIdentifier("tutorial-fret-\(string)-\(fret)")
                }
            }
        }
    }

    // MARK: - Geometry

    private struct RoutePair: Hashable {
        let from: GuitarPosition
        let to: GuitarPosition
    }

    /// Fret positions blend true logarithmic spacing with linear spacing: pure
    /// logarithmic looks like a real neck but squeezes the high frets past the
    /// point of being tappable, so the neck keeps its taper without losing them.
    private struct Metrics {
        let size: CGSize
        let frets: Int
        let leftHanded: Bool
        let expanded: Bool
        let compactTeaching: Bool

        var gutter: CGFloat { expanded ? 42 : 32 }
        var top: CGFloat { expanded ? 24 : 18 }
        var bottom: CGFloat { expanded ? 26 : 20 }
        /// Board margin above the high E and below the low E, so the outer
        /// strings do not sit on the edge of the wood.
        var boardPad: CGFloat { expanded ? 11 : 8 }
        var plateRadius: CGFloat { expanded ? 16 : 12 }
        var left: CGFloat { gutter }
        var boardWidth: CGFloat { max(1, size.width - gutter * 2) }
        var boardHeight: CGFloat { max(1, size.height - top - bottom) }
        var markerSize: CGFloat { min(expanded ? 34 : 24, boardHeight / 4.4) }
        var inlaySize: CGFloat { expanded ? 9 : 6 }

        func stringY(_ index: Int) -> CGFloat {
            top + CGFloat(index) * boardHeight / 5
        }

        func stringGauge(_ index: Int) -> CGFloat {
            let base = expanded ? 1.0 : 0.7
            return base + CGFloat(index) * (expanded ? 0.42 : 0.26)
        }

        private func fraction(_ fret: Int) -> CGFloat {
            guard frets > 0 else { return 0 }
            let n = CGFloat(fret)
            let total = CGFloat(frets)
            let linear = n / total
            let logarithmic = (1 - pow(2, -n / 12)) / (1 - pow(2, -total / 12))
            return linear * 0.4 + logarithmic * 0.6
        }

        func fretX(_ fret: Int) -> CGFloat {
            mirrored(left + fraction(fret) * boardWidth)
        }

        /// A fretted note sounds between two wires, so its marker sits in the
        /// middle of the space rather than on the wire itself. An open string
        /// has no space to sit in, so its marker steps just onto the board
        /// instead of straddling the nut.
        func markerX(fret: Int) -> CGFloat {
            guard fret > 0 else { return mirrored(left + (compactTeaching ? 0 : markerSize * 0.42)) }
            let lower = fraction(fret - 1)
            let upper = fraction(fret)
            return mirrored(left + (lower + upper) / 2 * boardWidth)
        }

        func teachingHitWidth(fret: Int) -> CGFloat {
            let next = abs(markerX(fret: fret + 1) - markerX(fret: fret))
            let previous = fret == 0 ? next : abs(markerX(fret: fret) - markerX(fret: fret - 1))
            return min(previous, next)
        }

        func point(_ position: GuitarPosition) -> CGPoint {
            CGPoint(x: markerX(fret: position.fret), y: stringY(position.string - 1))
        }

        private func mirrored(_ x: CGFloat) -> CGFloat {
            leftHanded ? left + boardWidth - (x - left) : x
        }
    }
}
