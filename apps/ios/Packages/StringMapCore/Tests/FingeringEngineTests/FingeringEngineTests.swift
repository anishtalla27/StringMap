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

    private func melody(_ pitches: [Int]) -> [FingeringNote] {
        pitches.enumerated().map { FingeringNote(id: "n\($0.offset)", midi: $0.element) }
    }
}
