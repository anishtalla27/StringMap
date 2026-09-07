import XCTest
import FingeringEngine
@testable import ScorePipeline

final class PolyphonicScoreTests: XCTestCase {
    func testRecognitionWarningsSurviveImportAreBoundedAndDeduplicated() throws {
        let message = String(repeating: "Check source. ", count: 80)
        let fields = "<miscellaneous-field name='stringmap:recognition-warning'>\(message)</miscellaneous-field>"
        let identification = "<identification><miscellaneous>\(fields)\(fields)<miscellaneous-field name='unrelated'>Ignore this</miscellaneous-field></miscellaneous></identification>"
        let data = xml(note("n", "C", 4, 12))
        let source = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "<part-list>", with: identification + "<part-list>")
        let score = try MusicXMLImporter().importScore(from: Data(source.utf8))
        XCTAssertEqual(score.notes.count, 1)
        XCTAssertEqual(score.warnings.filter { $0.hasPrefix("Check source") }.count, 1)
        XCTAssertEqual(score.warnings.first { $0.hasPrefix("Check source") }?.count, 500)
        XCTAssertFalse(score.warnings.contains("Ignore this"))
    }

    func testUnsupportedExpressionAndTextInstructionsAreDisclosed() throws {
        let data = xml("<direction><direction-type><dynamics><mf/></dynamics><words>ritardando</words></direction-type></direction>" + note("n", "C", 4, 12))
        let score = try MusicXMLImporter().importScore(from: data)
        XCTAssertEqual(score.notes.count, 1)
        XCTAssertTrue(score.warnings.contains { $0.contains("Expression marks") })
        XCTAssertTrue(score.warnings.contains { $0.contains("Written text instructions") })
    }

    func testFloatingPointEquivalentTripletOnsetsDoNotDuplicateChordNotes() throws {
        let data = xml(note("a", "C", 4, 12) + note("b", "E", 4, 12, extra: "<chord/>"))
        var score = try MusicXMLImporter().importScore(from: data)
        score.measures[0].events = score.measures[0].events.enumerated().map { i, event in
            guard case var .note(n) = event else { return event }
            n.onsetQuarters = i == 0 ? (1.0 / 3 + 1.0 / 3 + 1.0 / 3 + 1.0 / 3 + 1.0 / 3 + 1.0 / 3) : 2
            return .note(n)
        }
        let result = try StructuredScorePipeline().run(score: score)
        XCTAssertEqual(result.fingering.steps.count, 2)
        XCTAssertEqual(Set(result.fingering.steps.map(\.note.id)).count, 2)
        XCTAssertEqual(Set(result.fingering.steps.map(\.position.string)).count, 2)
    }

    private func xml(_ content: String, attributes: String = "") -> Data {
        Data("<score-partwise><part-list><score-part id='P1'><part-name>Guitar</part-name></score-part></part-list><part id='P1'><measure number='1'><attributes><divisions>12</divisions><time><beats>4</beats><beat-type>4</beat-type></time>\(attributes)</attributes>\(content)</measure></part></score-partwise>".utf8)
    }
    private func note(_ id: String, _ pitch: String, _ octave: Int, _ duration: Int, extra: String = "", voice: String = "1") -> String {
        "<note id='\(id)'>\(extra)<pitch><step>\(pitch)</step><octave>\(octave)</octave></pitch><duration>\(duration)</duration><voice>\(voice)</voice></note>"
    }

    func testStackedChordPreservesAllPitchesAndDistinctStrings() throws {
        let data = xml(note("c", "C", 4, 12) + note("e", "E", 4, 12, extra: "<chord/>") + note("g", "G", 4, 12, extra: "<chord/>"))
        let result = try StructuredScorePipeline().run(musicXML: data)
        XCTAssertEqual(result.score.notes.map(\.onsetQuarters), [0, 0, 0])
        XCTAssertEqual(Set(result.fingering.steps.map(\.position.string)).count, 3)
        XCTAssertEqual(result.fingering.steps.map(\.note.midi).sorted(), [60, 64, 67])
        // A single held chord has a span, but no sequential movement between
        // its simultaneously sounding notes.
        XCTAssertEqual(result.fingering.metrics.totalFretMovement, 0)
        XCTAssertEqual(result.fingering.metrics.stringChanges, 0)
        XCTAssertEqual(result.fingering.metrics.positionShifts, 0)
        for step in result.fingering.steps {
            XCTAssertEqual(step.note.midi, result.fingering.tuning.openMIDIPitches[step.position.string - 1] + step.position.physicalFret)
        }
        XCTAssertEqual(result.fingering.totalCost, result.fingering.steps.reduce(0) { $0 + $1.incrementalCost }, accuracy: 1e-8)
        XCTAssertTrue(result.alphaTex.contains("("))
        XCTAssertEqual(result, try StructuredScorePipeline().run(musicXML: data))
    }

    func testIndependentVoiceCannotReuseSustainedBassString() throws {
        let data = xml(note("bass", "E", 2, 48, voice: "2") + "<backup><duration>48</duration></backup>" +
            note("a", "G", 3, 12) + note("b", "A", 3, 12) + note("c", "B", 3, 24))
        let result = try StructuredScorePipeline().run(musicXML: data)
        let bass = try XCTUnwrap(result.fingering.steps.first { $0.note.id == "bass" })
        XCTAssertTrue(result.fingering.steps.filter { $0.note.id != "bass" }.allSatisfy { $0.position.string != bass.position.string })
        XCTAssertTrue(result.alphaTex.contains("\\voice"))
    }

    func testTiesMatchByVoiceAndIdentityAcrossOtherNotes() throws {
        let data = xml(note("a", "E", 3, 12, extra: "<tie type='start'/>", voice: "2") +
            note("b", "E", 3, 12, extra: "<tie type='stop'/>", voice: "2") +
            "<backup><duration>24</duration></backup>" + note("melody", "G", 4, 24))
        let result = try StructuredScorePipeline().run(musicXML: data)
        XCTAssertEqual(result.score.notes.first { $0.id == "b" }?.tieFromID, "a")
        XCTAssertEqual(result.fingering.steps.first { $0.note.id == "a" }?.position,
                       result.fingering.steps.first { $0.note.id == "b" }?.position)
    }

    func testUnplayableChordDoesNotPreventNotationReview() throws {
        let data = xml((0..<7).map { note("n\($0)", "E", 4, 12, extra: $0 == 0 ? "" : "<chord/>") }.joined())
        let score = try MusicXMLImporter().importScore(from: data)
        XCTAssertEqual(score.notes.count, 7)
        XCTAssertThrowsError(try StructuredScorePipeline().run(score: score))
        XCTAssertNoThrow(try AlphaTexGenerator.notation(score: score))
    }

    func testWrittenTransposeAppliedOnceAndClefDoesNotDoubleTranspose() throws {
        let data = xml(note("a", "E", 4, 12), attributes: "<clef><sign>G</sign><line>2</line><clef-octave-change>-1</clef-octave-change></clef><transpose><chromatic>0</chromatic><octave-change>-1</octave-change></transpose>")
        let score = try MusicXMLImporter().importScore(from: data)
        XCTAssertEqual(score.notes.first?.midi, 52)
        let roundTrip = try MusicXMLImporter().importScore(from: MusicXMLWriter.data(for: score))
        XCTAssertEqual(roundTrip.notes.map(\.midi), [52])
        XCTAssertEqual(roundTrip.notes.map(\.id), ["a"])
    }

    func testEditorRoundTripPreservesOverlapsRestsAndDurations() throws {
        let data = xml(note("bass", "E", 2, 48, voice: "2") + "<backup><duration>48</duration></backup>" +
            note("high", "E", 4, 12) + "<note id='rest'><rest/><duration>36</duration><voice>1</voice></note>")
        let score = try MusicXMLImporter().importScore(from: data)
        let copy = try MusicXMLImporter().importScore(from: MusicXMLWriter.data(for: score))
        XCTAssertEqual(copy.measures.flatMap(\.events), score.measures.flatMap(\.events))
    }

    func testTripletsAndRepeatsHaveExactTiming() throws {
        let content = "<barline location='left'><repeat direction='forward'/></barline>" +
            ["C", "D", "E"].enumerated().map { note("n\($0.offset)", $0.element, 4, 4, extra: "<time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>") }.joined() +
            "<barline location='right'><repeat direction='backward' times='2'/></barline>"
        let result = try StructuredScorePipeline().run(musicXML: xml(content))
        XCTAssertEqual(result.score.measures.count, 2)
        XCTAssertEqual(result.score.notes.count, 6)
        XCTAssertEqual(result.score.measures[0].durationQuarters, 1, accuracy: 1e-8)
        XCTAssertTrue(result.alphaTex.contains("{tu 3}"))
    }

    func testUnsafeAndUnsupportedScoresFailWithoutCrashing() {
        for content in [note("same", "E", 3, 12) + note("same", "F", 3, 12),
                        note("a", "E", Int.max, 12),
                        "<backup><duration>12</duration></backup>" + note("a", "E", 3, 12),
                        note("a", "E", 3, 12, extra: "<chord/>"),
                        note("a", "E", 3, 12, extra: "<tie type='stop'/>") + "<harmony/>"] {
            XCTAssertThrowsError(try MusicXMLImporter().importScore(from: xml(content)))
        }
        XCTAssertThrowsError(try MusicXMLImporter().importScore(from: xml(note("a", "E", 3, 12), attributes: "<staves>2</staves>")))
    }
    func testIncompleteRecognitionTiesCanBeReviewedButCannotBeSaved() throws {
        let data = xml(note("orphan", "E", 4, 12, extra: "<tie type='stop'/>"))
        XCTAssertThrowsError(try MusicXMLImporter().importScore(from: data))
        let draft = try MusicXMLImporter().importScore(from: data, forReview: true)
        XCTAssertTrue(draft.notes[0].tieStop)
        XCTAssertFalse(draft.warnings.isEmpty)
        XCTAssertThrowsError(try MusicXMLWriter.data(for: draft))
    }

    func testTempoChangesAndPlaybackEffectsAreNotSilentlyIgnored() {
        let content = "<direction><sound tempo='90'/></direction>" + note("a", "E", 4, 12) + "<direction><sound tempo='120'/></direction>"
        XCTAssertThrowsError(try MusicXMLImporter().importScore(from: xml(content)))
        XCTAssertThrowsError(try MusicXMLImporter().importScore(from: xml(note("a", "E", 4, 12, extra: "<notations><fermata/></notations>"))))
    }

    func testUnclosedRepeatFailsBeforeConversion() throws {
        let data = xml("<barline><repeat direction='forward'/></barline>" + note("a", "E", 4, 12))
        XCTAssertThrowsError(try StructuredScorePipeline().run(musicXML: data))
    }

    func testChordPitchReconstructionAcrossTuningsCaposAndExplicitTranspose() throws {
        let data = xml(note("e", "E", 4, 12) + note("g", "G", 4, 12, extra: "<chord/>") + note("b", "B", 4, 12, extra: "<chord/>"))
        for tuning in [GuitarTuning.standard, .dropD, .halfStepDown, .dStandard, .dadgad] {
            for capo in [0, 2, 7] {
                let result = try StructuredScorePipeline().run(musicXML: data, options: .init(tuning: tuning, maxFret: 24, capo: capo, transposeSemitones: 1))
                XCTAssertEqual(result.fingering.steps.map(\.note.midi).sorted(), [65, 68, 72])
                XCTAssertEqual(Set(result.fingering.steps.map(\.position.string)).count, 3)
                for step in result.fingering.steps {
                    XCTAssertEqual(step.note.midi, tuning.openMIDIPitches[step.position.string - 1] + step.position.fret + capo)
                }
            }
        }
    }

    func testConflictingChordLocksFailInsteadOfSharingAString() throws {
        let data = xml(note("a", "E", 4, 12) + note("b", "E", 4, 12, extra: "<chord/>"))
        let locked = GuitarPosition(string: 1, fret: 0, midi: 64)
        XCTAssertThrowsError(try StructuredScorePipeline().run(musicXML: data, options: .init(lockedPositions: ["a": locked, "b": locked])))
        let valid = try StructuredScorePipeline().run(musicXML: data, options: .init(lockedPositions: ["a": locked]))
        XCTAssertEqual(valid.fingering.steps.first { $0.note.id == "a" }?.position, locked)
        XCTAssertEqual(Set(valid.fingering.steps.map(\.position.string)).count, 2)
    }

}
