import Foundation

/// Original, deterministic guitar fingering search used by StringMap.
///
/// Each note becomes a layer of playable string/fret candidates. Dynamic programming
/// finds the exact cheapest path through those layers. Unary costs describe a shape;
/// transition costs describe movement between shapes. This separation is inspired by
/// MoChord (MIT), while this implementation and cost model are original to StringMap.
public enum FingeringEngine {
    public static func positions(
        for midi: Int,
        tuning: GuitarTuning = .standard,
        capo: Int = 0,
        maxFret: Int = 20
    ) throws -> [GuitarPosition] {
        try validateInstrument(capo: capo, maxFret: maxFret)
        guard (0...127).contains(midi) else { throw FingeringError.invalidMIDI(midi) }

        return tuning.openMIDIPitches.enumerated()
            .map { index, openMIDI in
                let physicalFret = midi - openMIDI
                return GuitarPosition(
                    string: index + 1,
                    fret: physicalFret - capo,
                    midi: midi,
                    physicalFret: physicalFret
                )
            }
            .filter { $0.fret >= 0 && $0.physicalFret <= maxFret }
            .sorted { left, right in
                left.fret == right.fret ? left.string < right.string : left.fret < right.fret
            }
    }

    /// Finds the exact cheapest path through the layered candidate graph.
    /// Complexity is O(notes × candidates²); six strings keep each layer small.
    public static func optimize(
        _ notes: [FingeringNote],
        options: OptimizationOptions = .init()
    ) throws -> FingeringResult {
        try validateInstrument(capo: options.capo, maxFret: options.maxFret)
        let weights = options.customWeights ?? options.profile.weights
        let appliedProfile: AppliedFingeringProfile = options.customWeights == nil
            ? .preset(options.profile)
            : .custom

        guard !notes.isEmpty else {
            return makeResult(
                profile: appliedProfile,
                weights: weights,
                options: options,
                totalCost: 0,
                steps: []
            )
        }

        var noteIDs = Set<String>()
        for note in notes where !noteIDs.insert(note.id).inserted {
            throw FingeringError.duplicateNoteID(note.id)
        }

        let allLayers = try notes.map { note in
            let allCandidates = try positions(
                for: note.midi,
                tuning: options.tuning,
                capo: options.capo,
                maxFret: options.maxFret
            )
            guard !allCandidates.isEmpty else {
                throw FingeringError.unplayableNote(id: note.id, midi: note.midi)
            }
            return allCandidates
        }
        let layers = try zip(notes, allLayers).map { note, allCandidates in
            guard let locked = options.lockedPositions[note.id] else { return allCandidates }
            let matches = allCandidates.filter { $0 == locked }
            guard !matches.isEmpty else { throw FingeringError.invalidLockedPosition(id: note.id) }
            return matches
        }

        var table: [[PathCell]] = []
        for noteIndex in notes.indices {
            let note = notes[noteIndex]
            let candidates = layers[noteIndex]
            var row: [PathCell] = []

            for candidate in candidates {
                let unary = unaryCost(
                    candidate,
                    weights: weights,
                    preferredHandPosition: noteIndex == 0 ? options.preferredHandPosition : nil
                )
                if noteIndex == 0 {
                    row.append(PathCell(cost: unary.total, previousIndex: nil, unary: unary, transition: nil))
                    continue
                }

                var best = PathCell.unreachable(unary: unary)
                for previousIndex in layers[noteIndex - 1].indices {
                    let previous = layers[noteIndex - 1][previousIndex]
                    let previousCell = table[noteIndex - 1][previousIndex]
                    guard previousCell.cost.isFinite else { continue }
                    if note.tieStop && previous != candidate { continue }

                    let transition = transitionCost(
                        previous,
                        candidate,
                        previousNote: notes[noteIndex - 1],
                        currentNote: note,
                        weights: weights
                    )
                    let cost = previousCell.cost + transition.total + unary.total
                    // Strict comparison preserves deterministic candidate ordering on equal costs.
                    if cost < best.cost {
                        best = PathCell(
                            cost: cost,
                            previousIndex: previousIndex,
                            unary: unary,
                            transition: transition
                        )
                    }
                }
                row.append(best)
            }
            table.append(row)
        }

        guard let finalIndex = minimumFiniteIndex(in: table[table.count - 1]) else {
            throw FingeringError.noValidPath
        }

        let suffixCosts = remainingCosts(
            notes: notes,
            layers: layers,
            table: table,
            weights: weights
        )

        var selectedIndex = finalIndex
        var selectedIndices = Array(repeating: 0, count: notes.count)
        var reversedSteps: [FingeringStep] = []
        for noteIndex in notes.indices.reversed() {
            let cell = table[noteIndex][selectedIndex]
            selectedIndices[noteIndex] = selectedIndex
            reversedSteps.append(FingeringStep(
                note: notes[noteIndex],
                position: layers[noteIndex][selectedIndex],
                candidateCount: allLayers[noteIndex].count,
                unary: cell.unary,
                transition: cell.transition,
                incrementalCost: cell.unary.total + (cell.transition?.total ?? 0),
                cumulativeCost: cell.cost,
                isLocked: options.lockedPositions[notes[noteIndex].id] != nil
            ))
            selectedIndex = cell.previousIndex ?? 0
        }

        let debugLayers = makeDebugLayers(
            notes: notes,
            allLayers: allLayers,
            constrainedLayers: layers,
            table: table,
            suffixCosts: suffixCosts,
            selectedIndices: selectedIndices,
            totalCost: table[table.count - 1][finalIndex].cost,
            lockedPositions: options.lockedPositions,
            weights: weights,
            preferredHandPosition: options.preferredHandPosition
        )

        return makeResult(
            profile: appliedProfile,
            weights: weights,
            options: options,
            totalCost: table[table.count - 1][finalIndex].cost,
            steps: Array(reversedSteps.reversed()),
            debugLayers: debugLayers
        )
    }

    /// Evaluates capo positions against the same deterministic model and reports
    /// the best material improvement. A nil result means capo 0 is already best.
    public static func suggestCapo(
        for notes: [FingeringNote],
        options: OptimizationOptions = .init(),
        range: ClosedRange<Int> = 0...7
    ) throws -> CapoSuggestion? {
        var baselineOptions = options
        baselineOptions.capo = 0
        let baseline = try optimize(notes, options: baselineOptions)
        var best: FingeringResult?

        for capo in range where capo > 0 && capo <= options.maxFret {
            var candidateOptions = options
            candidateOptions.capo = capo
            if let result = try? optimize(notes, options: candidateOptions),
               result.totalCost < (best?.totalCost ?? baseline.totalCost) {
                best = result
            }
        }

        guard let best else { return nil }
        return CapoSuggestion(capo: best.capo, result: best, improvement: baseline.totalCost - best.totalCost)
    }
}

private struct PathCell {
    let cost: Double
    let previousIndex: Int?
    let unary: UnaryCostBreakdown
    let transition: TransitionCostBreakdown?

    static func unreachable(unary: UnaryCostBreakdown) -> PathCell {
        PathCell(cost: .infinity, previousIndex: nil, unary: unary, transition: nil)
    }
}

private func validateInstrument(capo: Int, maxFret: Int) throws {
    guard maxFret >= 0 else { throw FingeringError.invalidMaxFret(maxFret) }
    guard capo >= 0, capo <= maxFret else { throw FingeringError.invalidCapo(capo) }
}

private func minimumFiniteIndex(in cells: [PathCell]) -> Int? {
    cells.indices.filter { cells[$0].cost.isFinite }.min { cells[$0].cost < cells[$1].cost }
}

private func remainingCosts(
    notes: [FingeringNote],
    layers: [[GuitarPosition]],
    table: [[PathCell]],
    weights: CostWeights
) -> [[Double]] {
    var suffix = layers.map { Array(repeating: Double.infinity, count: $0.count) }
    guard let last = layers.indices.last else { return suffix }
    suffix[last] = Array(repeating: 0, count: layers[last].count)
    guard last > 0 else { return suffix }

    for noteIndex in stride(from: last - 1, through: 0, by: -1) {
        for candidateIndex in layers[noteIndex].indices where table[noteIndex][candidateIndex].cost.isFinite {
            let current = layers[noteIndex][candidateIndex]
            for nextIndex in layers[noteIndex + 1].indices {
                let next = layers[noteIndex + 1][nextIndex]
                if notes[noteIndex + 1].tieStop && current != next { continue }
                guard suffix[noteIndex + 1][nextIndex].isFinite else { continue }
                let unary = table[noteIndex + 1][nextIndex].unary
                let transition = transitionCost(
                    current,
                    next,
                    previousNote: notes[noteIndex],
                    currentNote: notes[noteIndex + 1],
                    weights: weights
                )
                suffix[noteIndex][candidateIndex] = min(
                    suffix[noteIndex][candidateIndex],
                    transition.total + unary.total + suffix[noteIndex + 1][nextIndex]
                )
            }
        }
    }
    return suffix
}

private func makeDebugLayers(
    notes: [FingeringNote],
    allLayers: [[GuitarPosition]],
    constrainedLayers: [[GuitarPosition]],
    table: [[PathCell]],
    suffixCosts: [[Double]],
    selectedIndices: [Int],
    totalCost: Double,
    lockedPositions: [String: GuitarPosition],
    weights: CostWeights,
    preferredHandPosition: Int?
) -> [FingeringDebugLayer] {
    notes.indices.map { noteIndex in
        let selectedPosition = constrainedLayers[noteIndex][selectedIndices[noteIndex]]
        let evaluations = allLayers[noteIndex].map { position -> CandidateEvaluation in
            let unary = unaryCost(
                position,
                weights: weights,
                preferredHandPosition: noteIndex == 0 ? preferredHandPosition : nil
            )
            guard let constrainedIndex = constrainedLayers[noteIndex].firstIndex(of: position) else {
                return CandidateEvaluation(
                    position: position,
                    unary: unary,
                    incomingTransition: nil,
                    bestPreviousPosition: nil,
                    partialCost: nil,
                    bestPathCost: nil,
                    selected: false,
                    rejectionReason: "Excluded by the locked fingering for this note."
                )
            }
            let cell = table[noteIndex][constrainedIndex]
            let pathCost = cell.cost.isFinite && suffixCosts[noteIndex][constrainedIndex].isFinite
                ? cell.cost + suffixCosts[noteIndex][constrainedIndex]
                : nil
            let selected = position == selectedPosition
            let previous = cell.previousIndex.map { constrainedLayers[noteIndex - 1][$0] }
            let reason: String?
            if selected {
                reason = nil
            } else if let pathCost {
                reason = String(
                    format: "Best complete path costs %.2f more than the selected path.",
                    max(0, pathCost - totalCost)
                )
            } else {
                reason = notes[noteIndex].tieStop
                    ? "No compatible predecessor satisfies the tie constraint."
                    : "No complete path can pass through this position."
            }
            return CandidateEvaluation(
                position: position,
                unary: cell.unary,
                incomingTransition: cell.transition,
                bestPreviousPosition: previous,
                partialCost: cell.cost.isFinite ? cell.cost : nil,
                bestPathCost: pathCost,
                selected: selected,
                rejectionReason: reason
            )
        }
        return FingeringDebugLayer(note: notes[noteIndex], candidates: evaluations)
    }
}

private func unaryCost(
    _ position: GuitarPosition,
    weights: CostWeights,
    preferredHandPosition: Int?
) -> UnaryCostBreakdown {
    let handPenalty = preferredHandPosition.map {
        Double(abs(handPosition(position.physicalFret) - $0)) * weights.initialHandPosition
    } ?? 0
    return UnaryCostBreakdown(
        fretHeight: Double(position.physicalFret) * weights.fretHeight,
        openStringPreference: position.fret == 0 ? -weights.openStringPreference : 0,
        initialHandPosition: handPenalty
    )
}

private func transitionCost(
    _ previous: GuitarPosition,
    _ current: GuitarPosition,
    previousNote: FingeringNote,
    currentNote: FingeringNote,
    weights: CostWeights
) -> TransitionCostBreakdown {
    let fretDistance = abs(current.physicalFret - previous.physicalFret)
    let positionDistance = abs(handPosition(current.physicalFret) - handPosition(previous.physicalFret))
    let stringDistance = abs(current.string - previous.string)
    let excessStretch: Double
    if previous.fret > 0 && current.fret > 0 {
        excessStretch = max(0, Double(fretDistance) - weights.comfortableStretch)
    } else {
        excessStretch = 0
    }
    let awkwardExcess = max(0, Double(fretDistance - 7))

    return TransitionCostBreakdown(
        fretMovement: Double(fretDistance) * weights.fretMovement,
        positionShift: Double(positionDistance) * weights.positionShift,
        stringChange: stringDistance == 0 ? 0 : weights.stringChange,
        stringSkipping: Double(max(0, stringDistance - 1)) * weights.stringSkipping,
        largeStretch: excessStretch * excessStretch * weights.largeStretch,
        repeatedNoteConsistency: previousNote.midi == currentNote.midi && previous != current
            ? weights.repeatedNoteConsistency
            : 0,
        awkwardTransition: awkwardExcess * awkwardExcess * weights.awkwardTransition
    )
}

private func handPosition(_ physicalFret: Int) -> Int {
    physicalFret == 0 ? 1 : max(1, physicalFret - 1)
}

private func makeResult(
    profile: AppliedFingeringProfile,
    weights: CostWeights,
    options: OptimizationOptions,
    totalCost: Double,
    steps: [FingeringStep],
    debugLayers: [FingeringDebugLayer] = []
) -> FingeringResult {
    let transitions = zip(steps, steps.dropFirst())
    let totalFretMovement = transitions.reduce(0) {
        $0 + abs($1.0.position.physicalFret - $1.1.position.physicalFret)
    }
    let positionShifts = transitions.filter {
        handPosition($0.0.position.physicalFret) != handPosition($0.1.position.physicalFret)
    }.count
    let stringChanges = transitions.filter { $0.0.position.string != $0.1.position.string }.count
    let stringSkips = transitions.reduce(0) {
        $0 + max(0, abs($1.0.position.string - $1.1.position.string) - 1)
    }
    let largestStretch = transitions.map {
        abs($0.0.position.physicalFret - $0.1.position.physicalFret)
    }.max() ?? 0
    let averageFret = steps.isEmpty ? 0 : steps.reduce(0) {
        $0 + Double($1.position.physicalFret)
    } / Double(steps.count)
    let normalizedCost = steps.isEmpty ? 0 : max(0, totalCost) / Double(steps.count)
    let metrics = FingeringMetrics(
        totalFretMovement: totalFretMovement,
        positionShifts: positionShifts,
        stringChanges: stringChanges,
        stringSkips: stringSkips,
        openStrings: steps.filter { $0.position.fret == 0 }.count,
        averagePhysicalFret: averageFret,
        maximumPhysicalFret: steps.map(\.position.physicalFret).max() ?? 0,
        largestStretch: largestStretch,
        estimatedDifficulty: min(100, normalizedCost * 4)
    )
    return FingeringResult(
        profile: profile,
        weights: weights,
        tuning: options.tuning,
        capo: options.capo,
        maxFret: options.maxFret,
        totalCost: totalCost,
        steps: steps,
        metrics: metrics,
        debugLayers: debugLayers
    )
}
