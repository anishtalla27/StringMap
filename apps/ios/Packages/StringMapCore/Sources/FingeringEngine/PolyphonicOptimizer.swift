import Foundation

/// Absolute score time, before speed changes. Ties reference source identities,
/// not adjacent array positions (another voice may occur between tied notes).
public struct TimedFingeringNote: Sendable {
    public let note: FingeringNote
    public let onset: Double
    public let voice: String
    public let tieFromID: String?

    public init(note: FingeringNote, onset: Double, voice: String = "1", tieFromID: String? = nil) {
        self.note = note; self.onset = onset; self.voice = voice; self.tieFromID = tieFromID
    }
}

extension FingeringEngine {
    /// Exact dynamic programming over complete, physically compatible hand shapes.
    /// A layer includes every sounding note, including notes held from earlier beats.
    public static func optimizePolyphonic(_ input: [TimedFingeringNote], options: OptimizationOptions = .init()) throws -> FingeringResult {
        try validateInstrument(capo: options.capo, maxFret: options.maxFret)
        let notes = input.sorted { $0.onset == $1.onset ? $0.note.id < $1.note.id : $0.onset < $1.onset }
        guard !notes.isEmpty else { return try optimize([], options: options) }
        guard notes.count <= 4096 else { throw FingeringError.scoreTooComplex }
        var ids = Set<String>()
        for n in notes {
            guard ids.insert(n.note.id).inserted else { throw FingeringError.duplicateNoteID(n.note.id) }
            guard n.onset.isFinite, n.onset >= 0, n.note.durationQuarters.isFinite, n.note.durationQuarters > 0 else {
                throw FingeringError.noValidPath
            }
        }
        let byID = Dictionary(uniqueKeysWithValues: notes.enumerated().map { ($0.element.note.id, $0.offset) })
        let candidates = try notes.map { n in
            let all = try positions(for: n.note.midi, tuning: options.tuning, capo: options.capo, maxFret: options.maxFret)
            guard !all.isEmpty else { throw FingeringError.unplayableNote(id: n.note.id, midi: n.note.midi) }
            return all
        }
        let constrained = try notes.indices.map { i in
            guard let locked = options.lockedPositions[notes[i].note.id] else { return candidates[i] }
            guard candidates[i].contains(locked) else { throw FingeringError.invalidLockedPosition(id: notes[i].note.id) }
            return [locked]
        }
        let weights = options.customWeights ?? options.profile.weights
        // Different voice cursors can reach the same triplet boundary by
        // addition or division, differing by a few floating-point bits.
        let times = notes.map(\.onset).reduce(into: [Double]()) { result, onset in
            if result.last.map({ abs($0 - onset) > 1e-8 }) ?? true { result.append(onset) }
        }
        var layers: [[ChordShape]] = []
        var starts: [[Int]] = []
        var shapeCount = 0
        for time in times {
            try Task.checkCancellation()
            let active = notes.indices.filter { notes[$0].onset <= time + 1e-8 && notes[$0].onset + notes[$0].note.durationQuarters > time + 1e-8 }
            let new = active.filter { abs(notes[$0].onset - time) < 1e-8 }
            guard active.count <= 6 else { throw FingeringError.unplayableChord(onset: time) }
            var shapes: [ChordShape] = []
            func visit(_ offset: Int, _ assignment: [Int: GuitarPosition], _ strings: Set<Int>) {
                if offset == active.count {
                    if playableHand(Array(assignment.values)) { shapes.append(ChordShape(positions: assignment)) }
                    return
                }
                let i = active[offset]
                for p in constrained[i] where !strings.contains(p.string) {
                    var next = assignment; next[i] = p
                    visit(offset + 1, next, strings.union([p.string]))
                }
            }
            visit(0, [:], [])
            guard !shapes.isEmpty else { throw FingeringError.unplayableChord(onset: time) }
            shapeCount += shapes.count
            guard shapeCount <= 200_000 else { throw FingeringError.scoreTooComplex }
            layers.append(shapes); starts.append(new)
        }
        func unary(_ layer: Int, _ shape: ChordShape) -> Double {
            starts[layer].reduce(0) { $0 + unaryCost(shape.positions[$1]!, weights: weights,
                preferredHandPosition: layer == 0 ? options.preferredHandPosition : nil).total }
        }
        func edge(_ layer: Int, _ previous: ChordShape, _ current: ChordShape) -> Double? {
            for (i, p) in current.positions {
                if let held = previous.positions[i], held != p { return nil }
                if let id = notes[i].tieFromID, let predecessor = byID[id], starts[layer].contains(i) {
                    guard previous.positions[predecessor] == p else { return nil }
                }
            }
            return starts[layer].reduce(0) { sum, i in
                guard let prior = previous.positions.keys.sorted().filter({ notes[$0].voice == notes[i].voice })
                    .min(by: { abs(notes[$0].note.midi - notes[i].note.midi) < abs(notes[$1].note.midi - notes[i].note.midi) }) else { return sum }
                return sum + transitionCost(previous.positions[prior]!, current.positions[i]!,
                    previousNote: notes[prior].note, currentNote: notes[i].note, weights: weights).total
            }
        }
        var costs = layers.map { Array(repeating: Double.infinity, count: $0.count) }
        var parents = layers.map { Array(repeating: -1, count: $0.count) }
        var operations = 0
        for l in layers.indices {
            try Task.checkCancellation()
            for c in layers[l].indices {
                let own = unary(l, layers[l][c])
                if l == 0 { costs[l][c] = own; continue }
                for p in layers[l - 1].indices where costs[l - 1][p].isFinite {
                    operations += 1
                    if operations % 1024 == 0 { try Task.checkCancellation() }
                    guard operations <= 20_000_000 else { throw FingeringError.scoreTooComplex }
                    if let transition = edge(l, layers[l - 1][p], layers[l][c]) {
                        let cost = costs[l - 1][p] + transition + own
                        if cost < costs[l][c] { costs[l][c] = cost; parents[l][c] = p }
                    }
                }
            }
        }
        let last = layers.count - 1
        guard let final = costs[last].indices.filter({ costs[last][$0].isFinite }).min(by: { costs[last][$0] < costs[last][$1] }) else {
            throw FingeringError.noValidPath
        }
        var selected = Array(repeating: 0, count: layers.count); selected[last] = final
        if last > 0 { for l in stride(from: last, through: 1, by: -1) { selected[l - 1] = parents[l][selected[l]] } }
        var suffix = layers.map { Array(repeating: Double.infinity, count: $0.count) }
        suffix[last] = Array(repeating: 0, count: layers[last].count)
        if last > 0 {
            for l in stride(from: last - 1, through: 0, by: -1) {
                try Task.checkCancellation()
                for p in layers[l].indices where costs[l][p].isFinite {
                    for c in layers[l + 1].indices where suffix[l + 1][c].isFinite {
                        operations += 1
                        if operations % 1024 == 0 { try Task.checkCancellation() }
                        guard operations <= 40_000_000 else { throw FingeringError.scoreTooComplex }
                        if let transition = edge(l + 1, layers[l][p], layers[l + 1][c]) {
                            suffix[l][p] = min(suffix[l][p], transition + unary(l + 1, layers[l + 1][c]) + suffix[l + 1][c])
                        }
                    }
                }
            }
        }
        var steps: [FingeringStep] = []; var debug: [FingeringDebugLayer] = []; var running = 0.0
        var movements: [(GuitarPosition, GuitarPosition)] = []
        var simultaneousSpan = 0
        for l in layers.indices {
            let shape = layers[l][selected[l]]
            let frets = shape.positions.values.filter { $0.fret > 0 }.map(\.physicalFret)
            simultaneousSpan = max(simultaneousSpan, (frets.max() ?? 0) - (frets.min() ?? 0))
            for i in starts[l] {
                let p = shape.positions[i]!
                let own = unaryCost(p, weights: weights, preferredHandPosition: l == 0 ? options.preferredHandPosition : nil)
                var transition: TransitionCostBreakdown?
                if l > 0 {
                    let previous = layers[l - 1][selected[l - 1]]
                    if let prior = previous.positions.keys.sorted().filter({ notes[$0].voice == notes[i].voice })
                        .min(by: { abs(notes[$0].note.midi - notes[i].note.midi) < abs(notes[$1].note.midi - notes[i].note.midi) }) {
                        transition = transitionCost(previous.positions[prior]!, p, previousNote: notes[prior].note, currentNote: notes[i].note, weights: weights)
                        movements.append((previous.positions[prior]!, p))
                    }
                }
                running += own.total + (transition?.total ?? 0)
                steps.append(FingeringStep(note: notes[i].note, position: p, candidateCount: candidates[i].count,
                    unary: own, transition: transition, incrementalCost: own.total + (transition?.total ?? 0),
                    cumulativeCost: running, isLocked: options.lockedPositions[notes[i].note.id] != nil))
                debug.append(FingeringDebugLayer(note: notes[i].note, candidates: candidates[i].map { position in
                    let routes = layers[l].indices.filter { layers[l][$0].positions[i] == position }
                        .map { costs[l][$0] + suffix[l][$0] }.filter(\.isFinite)
                    let best = routes.min()
                    return CandidateEvaluation(position: position, unary: unaryCost(position, weights: weights, preferredHandPosition: nil),
                        incomingTransition: nil, bestPreviousPosition: nil, partialCost: nil, bestPathCost: best,
                        selected: position == p, rejectionReason: position == p ? nil : (best.map {
                            String(format: "Best complete chord route costs %.2f more.", max(0, $0 - costs[last][final]))
                        } ?? "Incompatible with another sounding note, a tie, a lock, or the hand span."))
                }))
            }
        }
        return makeResult(profile: options.customWeights == nil ? .preset(options.profile) : .custom,
            weights: weights, options: options, totalCost: costs[last][final], steps: steps, debugLayers: debug,
            motionTransitions: movements, simultaneousSpan: simultaneousSpan)
    }
}

private struct ChordShape { let positions: [Int: GuitarPosition] }

/// Conservative four-finger feasibility with contiguous partial/full barres.
private func playableHand(_ positions: [GuitarPosition]) -> Bool {
    let fretted = positions.filter { $0.fret > 0 }
    guard let low = fretted.map(\.physicalFret).min(), let high = fretted.map(\.physicalFret).max() else { return true }
    guard high - low <= 5 else { return false }
    var fingers = fretted.count
    for fret in Set(fretted.map(\.fret)) {
        let same = fretted.filter { $0.fret == fret }.sorted { $0.string < $1.string }
        var group: [GuitarPosition] = []
        for p in same {
            if let previous = group.last,
               positions.contains(where: { $0.string > previous.string && $0.string < p.string && $0.fret < fret }) {
                fingers -= max(0, group.count - 1); group = []
            }
            group.append(p)
        }
        fingers -= max(0, group.count - 1)
    }
    return fingers <= 4
}
