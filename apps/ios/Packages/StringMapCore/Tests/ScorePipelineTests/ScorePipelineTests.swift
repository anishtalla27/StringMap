import XCTest
import FingeringEngine
@testable import ScorePipeline

final class ScorePipelineTests: XCTestCase {
    private let importer = MusicXMLImporter()

    func testNormalizesMetadataPitchRhythmAndRest() throws {
        let score = try importer.importScore(from: xmlData())
        XCTAssertEqual(score.title, "Known melody")
        XCTAssertEqual(score.partName, "Lead")
        XCTAssertEqual(score.tempo, 88)
        XCTAssertEqual(score.measures.count, 2)
        XCTAssertEqual(score.measures[0].timeSignature, TimeSignature(beats: 3, beatType: 4))
        XCTAssertEqual(score.notes.map { ($0.pitch, $0.midi) }.map(PitchPair.init), [
            PitchPair("C4", 60), PitchPair("D4", 62), PitchPair("E4", 64),
            PitchPair("F#4", 66), PitchPair("G4", 67),
        ])
        guard case let .rest(rest) = score.measures[1].events[0] else {
            return XCTFail("Expected a normalized rest")
        }
        XCTAssertEqual(rest.durationQuarters, 0.5)
    }

    func testAcceptsFlatAccidentals() throws {
        let flat = simpleMusicXML.replacingOccurrences(
            of: "<step>C</step><octave>4</octave>",
            with: "<step>B</step><alter>-1</alter><octave>3</octave>"
        )
        XCTAssertEqual(try importer.importScore(from: xmlData(flat)).notes.first?.midi, 58)
        XCTAssertEqual(try importer.importScore(from: xmlData(flat)).notes.first?.pitch, "A#3")
    }

    func testWarnsForMultiplePartsAndUsesFirst() throws {
        let multiple = simpleMusicXML.replacingOccurrences(
            of: "</score-partwise>",
            with: "<part id=\"P2\"><measure number=\"1\"/></part></score-partwise>"
        )
        let score = try importer.importScore(from: xmlData(multiple))
        XCTAssertEqual(score.notes.count, 5)
        XCTAssertEqual(score.warnings, ["Only the first MusicXML part was imported."])
    }

    func testRejectsUnsupportedAndMalformedInput() {
        assertError(simpleMusicXML.replacingOccurrences(
            of: "<note><pitch><step>D</step>",
            with: "<note><chord/><pitch><step>D</step>"
        ), is: .unsupportedChord(measure: 1))
        assertError(simpleMusicXML.replacingOccurrences(
            of: "<note><pitch><step>D</step>",
            with: "<backup><duration>1</duration></backup><note><pitch><step>D</step>"
        ), is: .unsupportedMultipleVoices(measure: 1))
        assertError(simpleMusicXML.replacingOccurrences(
            of: "<note><pitch><step>D</step>",
            with: "<note><grace/><pitch><step>D</step>"
        ), is: .unsupportedGraceNote(measure: 1))
        assertError(simpleMusicXML.replacingOccurrences(
            of: "<note><pitch><step>D</step>",
            with: "<note><time-modification/><pitch><step>D</step>"
        ), is: .unsupportedTuplet(measure: 1))
        assertError(simpleMusicXML.replacingOccurrences(
            of: "<note><pitch><step>D</step><octave>4</octave></pitch>",
            with: "<note><unpitched/>"
        ), is: .unpitchedNote(measure: 1))
        XCTAssertThrowsError(try importer.importScore(from: xmlData("<score-partwise>")))
        XCTAssertThrowsError(try importer.importScore(from: Data())) { error in
            XCTAssertEqual(error as? MusicXMLImportError, .emptyInput)
        }
        XCTAssertThrowsError(try importer.importScore(from: xmlData("<score-timewise/>"))) { error in
            XCTAssertEqual(error as? MusicXMLImportError, .unsupportedRoot("score-timewise"))
        }
    }

    func testPipelineProducesCandidatesFingeringAndAlphaTex() throws {
        let result = try StructuredScorePipeline().run(musicXML: xmlData())
        XCTAssertTrue(result.candidates.values.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(result.fingering.steps.count, 5)
        XCTAssertEqual(result.alphaTex, """
        \\title "Known melody"
        \\track "Lead"
        \\staff{score tabs}
        \\tuning E4 B3 G3 D3 A2 E2
        \\instrument acousticguitarsteel
        \\tempo 88
        .
        \\ts 3 4 1.2.4 3.2.4 0.1.4 |
        r.8 2.1.8 3.1.2 |
        """)
    }

    func testTieMarkerAndUnsupportedDuration() throws {
        let tied = simpleMusicXML
            .replacingOccurrences(
                of: "<note><pitch><step>D</step><octave>4</octave></pitch><duration>2</duration></note>",
                with: "<note><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration><tie type=\"stop\"/></note>"
            )
            .replacingOccurrences(
                of: "<note><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration></note>",
                with: "<note><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration><tie type=\"start\"/></note>"
            )
        XCTAssertTrue(try StructuredScorePipeline().run(musicXML: xmlData(tied)).alphaTex.contains("{t}"))

        let unsupported = simpleMusicXML.replacingOccurrences(
            of: "<duration>2</duration>",
            with: "<duration>1.2</duration>"
        )
        XCTAssertThrowsError(try StructuredScorePipeline().run(musicXML: xmlData(unsupported))) { error in
            guard case .unsupportedDuration = error as? MusicXMLImportError else {
                return XCTFail("Expected unsupportedDuration, got \(error)")
            }
        }
    }

    func testTranspositionRegeneratesNotationAndFingering() throws {
        let original = try StructuredScorePipeline().run(musicXML: xmlData())
        let shifted = try StructuredScorePipeline().run(
            musicXML: xmlData(),
            options: .init(transposeSemitones: 2)
        )
        XCTAssertEqual(shifted.score.notes.map(\.midi), original.score.notes.map { $0.midi + 2 })
        XCTAssertEqual(shifted.score.notes.first?.pitch, "D4")
        XCTAssertNotEqual(shifted.alphaTex, original.alphaTex)
    }

    func testAlternateTuningAndCapoAreWrittenToAlphaTex() throws {
        let result = try StructuredScorePipeline().run(
            musicXML: xmlData(),
            options: .init(tuning: .dropD, capo: 2)
        )
        XCTAssertTrue(result.alphaTex.contains("\\tuning E4 B3 G3 D3 A2 D2"))
        XCTAssertTrue(result.alphaTex.contains("\\capo 2"))
        XCTAssertTrue(result.fingering.steps.allSatisfy { $0.position.fret + 2 == $0.position.physicalFret })
    }

    func testPreservesSourceIDsComposerAndKeyMetadata() throws {
        let enriched = simpleMusicXML
            .replacingOccurrences(
                of: "<part-list>",
                with: "<identification><creator type=\"composer\">Ada Strings</creator></identification><part-list>"
            )
            .replacingOccurrences(
                of: "<measure number=\"1\">",
                with: "<measure id=\"m-source-1\" number=\"1\">"
            )
            .replacingOccurrences(
                of: "<time><beats>3</beats><beat-type>4</beat-type></time>",
                with: "<key><fifths>2</fifths></key><time><beats>3</beats><beat-type>4</beat-type></time>"
            )
            .replacingOccurrences(
                of: "<note><pitch><step>C</step>",
                with: "<note id=\"n-source-1\"><pitch><step>C</step>"
            )
        let score = try importer.importScore(from: xmlData(enriched))
        XCTAssertEqual(score.composer, "Ada Strings")
        XCTAssertEqual(score.measures.first?.id, "m-source-1")
        XCTAssertEqual(score.measures.first?.keyFifths, 2)
        XCTAssertEqual(score.notes.first?.id, "n-source-1")
    }

    private func assertError(_ xml: String, is expected: MusicXMLImportError) {
        XCTAssertThrowsError(try importer.importScore(from: xmlData(xml))) { error in
            XCTAssertEqual(error as? MusicXMLImportError, expected)
        }
    }
}

private struct PitchPair: Equatable {
    let pitch: String
    let midi: Int

    init(_ tuple: (String, Int)) {
        pitch = tuple.0
        midi = tuple.1
    }

    init(_ pitch: String, _ midi: Int) {
        self.pitch = pitch
        self.midi = midi
    }
}
