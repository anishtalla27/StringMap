import XCTest
@testable import FingeringEngine

final class FingeringEngineTests: XCTestCase {
    func testEnumeratesEveryStandardTuningPositionForE4() throws {
        XCTAssertEqual(try FingeringEngine.positions(for: 64, maxFret: 24), [
            GuitarPosition(string: 1, fret: 0, midi: 64),
            GuitarPosition(string: 2, fret: 5, midi: 64),
            GuitarPosition(string: 3, fret: 9, midi: 64),
            GuitarPosition(string: 4, fret: 14, midi: 64),
            GuitarPosition(string: 5, fret: 19, midi: 64),
            GuitarPosition(string: 6, fret: 24, midi: 64),
        ])
        XCTAssertEqual(try FingeringEngine.positions(for: 64, maxFret: 20).count, 5)
    }

    func testFiltersNegativeAndAboveLimitFrets() throws {
        XCTAssertEqual(try FingeringEngine.positions(for: 60), [
            GuitarPosition(string: 2, fret: 1, midi: 60),
            GuitarPosition(string: 3, fret: 5, midi: 60),
            GuitarPosition(string: 4, fret: 10, midi: 60),
            GuitarPosition(string: 5, fret: 15, midi: 60),
            GuitarPosition(string: 6, fret: 20, midi: 60),
        ])
        XCTAssertEqual(try FingeringEngine.positions(for: 39), [])
    }

    func testRejectsInvalidInputsAndTuning() {
        XCTAssertThrowsError(try FingeringEngine.positions(for: -1)) { error in
            XCTAssertEqual(error as? FingeringError, .invalidMIDI(-1))
        }
        XCTAssertThrowsError(try FingeringEngine.positions(for: 128)) { error in
            XCTAssertEqual(error as? FingeringError, .invalidMIDI(128))
        }
        XCTAssertThrowsError(try FingeringEngine.positions(for: 60, maxFret: -1)) { error in
            XCTAssertEqual(error as? FingeringError, .invalidMaxFret(-1))
        }
        XCTAssertThrowsError(try GuitarTuning(openMIDIPitches: [64, 59])) { error in
            XCTAssertEqual(error as? FingeringError, .invalidTuning)
        }
    }

    func testChoosesSmoothScalePath() throws {
        let result = try FingeringEngine.optimize(melody([64, 66, 67, 69]))
        XCTAssertEqual(result.steps.map(\.position), [
            GuitarPosition(string: 1, fret: 0, midi: 64),
            GuitarPosition(string: 1, fret: 2, midi: 66),
            GuitarPosition(string: 1, fret: 3, midi: 67),
            GuitarPosition(string: 1, fret: 5, midi: 69),
        ])
    }

    func testProfilesChangeTheChosenPath() throws {
        let notes = melody([40, 43, 59])
        let beginner = try FingeringEngine.optimize(notes, options: .init(profile: .beginner))
        let balanced = try FingeringEngine.optimize(notes, options: .init(profile: .balanced))
        XCTAssertEqual(beginner.steps.last?.position, GuitarPosition(string: 2, fret: 0, midi: 59))
        XCTAssertEqual(balanced.steps.last?.position, GuitarPosition(string: 3, fret: 4, midi: 59))
    }

    func testTiePreservesPositionAndRejectsIncompatiblePitch() throws {
        let result = try FingeringEngine.optimize([
            FingeringNote(id: "start", midi: 64),
            FingeringNote(id: "stop", midi: 64, tieStop: true),
        ])
        XCTAssertEqual(result.steps[0].position, result.steps[1].position)

        XCTAssertThrowsError(try FingeringEngine.optimize([
            FingeringNote(id: "start", midi: 64),
            FingeringNote(id: "bad-stop", midi: 65, tieStop: true),
        ])) { error in
            XCTAssertEqual(error as? FingeringError, .noValidPath)
        }
    }

    func testAuditComponentsReconcileWithTotal() throws {
        let result = try FingeringEngine.optimize(melody([60, 62, 64]))
        XCTAssertEqual(result.steps.reduce(0) { $0 + $1.incrementalCost }, result.totalCost, accuracy: 0.000001)
        XCTAssertNotNil(result.steps.last?.transition)
        XCTAssertTrue(result.steps.allSatisfy { $0.candidateCount > 0 })
        for (index, step) in result.steps.enumerated() {
            XCTAssertEqual(
                step.unary.total + (step.transition?.total ?? 0),
                step.incrementalCost,
                accuracy: 0.000001
            )
            let previous = index == 0 ? 0 : result.steps[index - 1].cumulativeCost
            XCTAssertEqual(previous + step.incrementalCost, step.cumulativeCost, accuracy: 0.000001)
        }
    }

    func testEmptyInputAndUnplayableNotes() throws {
        let empty = try FingeringEngine.optimize([])
        XCTAssertEqual(empty.totalCost, 0)
        XCTAssertEqual(empty.steps, [])
        XCTAssertThrowsError(try FingeringEngine.optimize(melody([30]))) { error in
            XCTAssertEqual(error as? FingeringError, .unplayableNote(id: "n0", midi: 30))
        }
        XCTAssertThrowsError(try FingeringEngine.optimize([
            FingeringNote(id: "duplicate", midi: 60),
            FingeringNote(id: "duplicate", midi: 62),
        ])) { error in
            XCTAssertEqual(error as? FingeringError, .duplicateNoteID("duplicate"))
        }
    }

    func testCandidateOrderingMakesTiesDeterministic() throws {
        let zero = CostWeights(
            fretMovement: 0,
            positionShift: 0,
            stringChange: 0,
            largeStretch: 0,
            fretHeight: 0,
            openStringPreference: 0,
            comfortableStretch: 4
        )
        let result = try FingeringEngine.optimize(
            melody([64, 64]),
            options: .init(maxFret: 24, customWeights: zero)
        )
        XCTAssertEqual(result.steps.map(\.position.string), [1, 1])
    }

    func testCapoUsesRelativeTabFretsAndPhysicalFretLimit() throws {
        let positions = try FingeringEngine.positions(for: 64, capo: 2, maxFret: 20)
        XCTAssertEqual(positions.first, GuitarPosition(string: 2, fret: 3, midi: 64, physicalFret: 5))
        XCTAssertFalse(positions.contains { $0.string == 1 })
        XCTAssertTrue(positions.allSatisfy { $0.physicalFret == $0.fret + 2 && $0.physicalFret <= 20 })
    }

    func testAlternateTuningsChangeCandidates() throws {
        XCTAssertEqual(try FingeringEngine.positions(for: 38, tuning: .standard), [])
        XCTAssertEqual(try FingeringEngine.positions(for: 38, tuning: .dropD), [
            GuitarPosition(string: 6, fret: 0, midi: 38),
        ])
        XCTAssertEqual(try FingeringEngine.positions(for: 62, tuning: .dadgad).first,
                       GuitarPosition(string: 1, fret: 0, midi: 62))
    }

    func testLockedFingeringSurvivesOptimization() throws {
        let lock = GuitarPosition(string: 2, fret: 5, midi: 64)
        let result = try FingeringEngine.optimize(
            melody([62, 64, 66]),
            options: .init(lockedPositions: ["n1": lock])
        )
        XCTAssertEqual(result.steps[1].position, lock)
        XCTAssertTrue(result.steps[1].isLocked)
        XCTAssertGreaterThan(result.steps[1].candidateCount, 1)

        XCTAssertThrowsError(try FingeringEngine.optimize(
            melody([64]),
            options: .init(lockedPositions: ["n0": GuitarPosition(string: 6, fret: 0, midi: 64)])
        )) { error in
            XCTAssertEqual(error as? FingeringError, .invalidLockedPosition(id: "n0"))
        }
    }

    func testRepeatedNotesRemainConsistentAndMetricsAreMeasured() throws {
        let result = try FingeringEngine.optimize(melody([64, 64, 64, 67, 69]))
        XCTAssertEqual(Set(result.steps.prefix(3).map(\.position)).count, 1)
        XCTAssertEqual(result.metrics.stringChanges,
                       zip(result.steps, result.steps.dropFirst()).filter { $0.position.string != $1.position.string }.count)
        XCTAssertEqual(result.metrics.openStrings, result.steps.filter { $0.position.fret == 0 }.count)
        XCTAssertGreaterThanOrEqual(result.metrics.estimatedDifficulty, 0)
    }

    func testAllProfilesHaveIndependentCostModels() {
        XCTAssertEqual(FingeringProfile.allCases.count, 5)
        XCTAssertEqual(Set(FingeringProfile.allCases.map(\.weights.positionShift)).count, 5)
    }

    func testCapoSuggestionReturnsOnlyARealImprovement() throws {
        let notes = melody([66, 68, 70, 71, 73])
        if let suggestion = try FingeringEngine.suggestCapo(for: notes, options: .init(profile: .beginner)) {
            XCTAssertGreaterThan(suggestion.capo, 0)
            XCTAssertGreaterThan(suggestion.improvement, 0)
        }
    }

    func testRejectsCapoBeyondInstrument() {
        XCTAssertThrowsError(try FingeringEngine.positions(for: 64, capo: 21, maxFret: 20)) { error in
            XCTAssertEqual(error as? FingeringError, .invalidCapo(21))
        }
    }

    func testEveryCandidateProducesTheRequestedSoundingPitchAcrossTuningsAndCapos() throws {
        let tunings: [GuitarTuning] = [.standard, .dropD, .dStandard, .halfStepDown, .dadgad,
            try GuitarTuning(name: "Open G variant", openMIDIPitches: [62, 59, 55, 50, 43, 38])]
        for tuning in tunings {
            for capo in [0, 2, 5, 7] {
                for midi in 38...88 {
                    for position in try FingeringEngine.positions(
                        for: midi,
                        tuning: tuning,
                        capo: capo,
                        maxFret: 24
                    ) {
                        XCTAssertEqual(
                            tuning.openMIDIPitches[position.string - 1] + capo + position.fret,
                            midi,
                            "\(tuning.name), capo \(capo), \(position)"
                        )
                        XCTAssertEqual(position.physicalFret, capo + position.fret)
                    }
                }
            }
        }
    }

    func testRepresentativePassagesRemainPlayableAndAuditable() throws {
        let passages = [
            [60, 62, 64, 65, 67, 69, 71, 72],             // major scale
            [57, 59, 60, 62, 64, 65, 67, 69],             // minor scale
            [40, 47, 52, 55, 59, 64, 59, 55],             // arpeggio
            [60, 61, 62, 63, 64, 65, 66, 67],             // chromatic run
            [40, 64, 43, 67, 45, 69],                     // large intervals
            [64, 64, 64, 67, 64, 64],                     // repeated notes
            [40, 41, 82, 83, 84],                         // low/high range
        ]
        for pitches in passages {
            let result = try FingeringEngine.optimize(melody(pitches), options: .init(maxFret: 24))
            XCTAssertEqual(result.steps.count, pitches.count)
            XCTAssertEqual(result.debugLayers.count, pitches.count)
            XCTAssertEqual(result.metrics.totalFretMovement,
                zip(result.steps, result.steps.dropFirst()).reduce(0) {
                    $0 + abs($1.0.position.physicalFret - $1.1.position.physicalFret)
                })
            XCTAssertEqual(result.metrics.maximumPhysicalFret,
                result.steps.map(\.position.physicalFret).max())
        }
    }

    func testCandidateDiagnosticsCompareCompleteRoutesAndExplainLocks() throws {
        let notes = melody([60, 64, 67])
        let unlocked = try FingeringEngine.optimize(notes)
        for (index, layer) in unlocked.debugLayers.enumerated() {
            XCTAssertEqual(layer.candidates.count, unlocked.steps[index].candidateCount)
            XCTAssertEqual(layer.candidates.filter(\.selected).count, 1)
            let cheapestRoute = try XCTUnwrap(layer.candidates.compactMap(\.bestPathCost).min())
            XCTAssertEqual(cheapestRoute, unlocked.totalCost, accuracy: 0.000001)
            XCTAssertTrue(layer.candidates.filter { !$0.selected }.allSatisfy { $0.rejectionReason != nil })
        }

        let lock = try XCTUnwrap(try FingeringEngine.positions(for: 64).last)
        let locked = try FingeringEngine.optimize(notes, options: .init(lockedPositions: ["n1": lock]))
        let lockedLayer = locked.debugLayers[1]
        XCTAssertEqual(lockedLayer.candidates.filter(\.selected).map(\.position), [lock])
        XCTAssertTrue(lockedLayer.candidates.filter { $0.position != lock }.allSatisfy {
            $0.rejectionReason?.contains("locked") == true
        })
    }

    func testDifficultyProfilesMakeDifferentMeasurableTradeoffs() throws {
        let notes = melody([40, 43, 59, 57, 59, 61, 62, 59, 55])
        let results = try Dictionary(uniqueKeysWithValues: FingeringProfile.allCases.map {
            ($0, try FingeringEngine.optimize(notes, options: .init(profile: $0)))
        })
        let uniquePaths = Set(results.values.map { $0.steps.map(\.position) })
        // Some weight sets legitimately agree on a globally dominant route;
        // this passage must still expose at least two distinct tradeoffs.
        XCTAssertGreaterThanOrEqual(uniquePaths.count, 2)
        let beginner = try XCTUnwrap(results[.beginner])
        let performance = try XCTUnwrap(results[.performance])
        XCTAssertLessThanOrEqual(beginner.metrics.averagePhysicalFret, performance.metrics.averagePhysicalFret)
        XCTAssertGreaterThanOrEqual(beginner.metrics.openStrings, performance.metrics.openStrings)
    }

    func testLongMonophonicPassageOptimizesWithinInteractiveBudget() throws {
        let pitches = (0..<2_000).map { 55 + ($0 % 18) }
        let started = ContinuousClock.now
        let result = try FingeringEngine.optimize(melody(pitches))
        let elapsed = started.duration(to: .now)
        XCTAssertEqual(result.steps.count, 2_000)
        XCTAssertLessThan(elapsed, .seconds(2))
    }

    private func melody(_ pitches: [Int]) -> [FingeringNote] {
        pitches.enumerated().map { FingeringNote(id: "n\($0.offset)", midi: $0.element) }
    }
}
