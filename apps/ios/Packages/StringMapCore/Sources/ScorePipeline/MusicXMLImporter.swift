import Foundation

/// Photo recognition reads visible staff pitches. Ordinary guitar notation
/// sounds one octave lower; structured XML keeps its explicitly encoded intent.
public enum MusicXMLPitchConvention: String, Codable, Sendable, CaseIterable {
    case asEncoded
    case guitarWritten
}

public struct MusicXMLImporter: ScoreImporter {
    public init() {}

    public func importScore(from data: Data) throws -> NormalizedScore {
        try importScore(from: data, forReview: false)
    }

    /// In review, orphan ties and bounded unsupported note annotations remain
    /// editable. They must be resolved before serialization, playback or fingering.
    public func importScore(from data: Data, forReview: Bool,
                            pitchConvention: MusicXMLPitchConvention = .asEncoded) throws -> NormalizedScore {
        let data = try MusicXMLContainer.scoreData(from: data)
        let delegate = ParserDelegate(pitchConvention: pitchConvention, forReview: forReview)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never

        let succeeded = parser.parse()
        if let error = delegate.failure { throw error }
        guard succeeded else {
            throw MusicXMLImportError.malformed(parser.parserError?.localizedDescription ?? "Unknown parser error")
        }
        return try delegate.finish(forReview: forReview)
    }
}

private final class ParserDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {
    struct NoteBuilder {
        var sourceID: String?
        var voice = "1"
        var hasExplicitVoice = false
        var staff = 1
        var isChord = false
        var actualNotes: Int?
        var normalNotes: Int?
        var step: String?
        var alter = 0.0
        var octave: Int?
        var duration: Double?
        var isRest = false
        var hasPitch = false
        var tieStart = false
        var tieStop = false
        var unsupportedMarks: [String] = []
    }

    struct MeasureBuilder {
        let id: String
        let index: Int
        let number: String
        var timeSignature: TimeSignature
        var keyFifths: Int
        var cursorQuarters = 0.0
        var forwardEndQuarters = 0.0
        var lastOnset: Double?
        var lastVoice: String?
        var repeatStart = false
        var repeatCount = 0
        var events: [NormalizedEvent] = []
    }

    var failure: MusicXMLImportError?
    private var elementStack: [String] = []
    private var textStack: [String] = []
    private var rootName: String?
    private var title = ""
    private var movementTitle = ""
    private var composer: String?
    private var currentCreatorType: String?
    private var partNames: [String: String] = [:]
    private var currentScorePartID: String?
    private var selectedPartID: String?
    private var actualPartCount = 0
    private var parsingFirstPart = false
    private var divisions = 1.0
    private var currentTime = TimeSignature(beats: 4, beatType: 4)
    private var currentKeyFifths = 0
    private var tempo: Double?
    private var measures: [NormalizedMeasure] = []
    private var measure: MeasureBuilder?
    private var note: NoteBuilder?
    private var forwardDuration: Double?
    private var backupDuration: Double?
    private var chromaticTranspose = 0
    private var octaveTranspose = 0
    private var transposeSeen = false
    private var eventCounter = 0
    private var reviewWarnings = Set<String>()
    private var recognitionWarning = false

    private let forReview: Bool
    private var reviewIssues: [ScoreReviewIssue] = []

    init(pitchConvention: MusicXMLPitchConvention, forReview: Bool) {
        self.forReview = forReview
        // An explicit <transpose> resets these values before any of its notes
        // are read. Never infer an octave from playable range or fingering cost.
        octaveTranspose = pitchConvention == .guitarWritten ? -1 : 0
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        if rootName == nil { rootName = name }
        elementStack.append(name)
        textStack.append("")
        guard elementStack.count <= 64 else { abort(parser, with: .malformed("XML nesting is too deep.")); return }

        if name == "score-part" {
            currentScorePartID = attributeDict["id"]
        } else if name == "creator" {
            currentCreatorType = attributeDict["type"]
        } else if name == "miscellaneous-field" {
            recognitionWarning = attributeDict["name"] == "stringmap:recognition-warning"
        } else if name == "part" {
            actualPartCount += 1
            parsingFirstPart = actualPartCount == 1
            if parsingFirstPart { selectedPartID = attributeDict["id"] }
        }

        guard parsingFirstPart else { return }

        switch name {
        case "measure":
            measure = MeasureBuilder(
                id: attributeDict["id"] ?? "measure-\(measures.count)",
                index: measures.count,
                number: attributeDict["number"] ?? String(measures.count + 1),
                timeSignature: currentTime,
                keyFifths: currentKeyFifths
            )
        case "note":
            note = NoteBuilder(sourceID: attributeDict["id"])
        case "forward":
            forwardDuration = nil
        case "backup":
            backupDuration = nil
        case "chord":
            note?.isChord = true
        case "transpose":
            chromaticTranspose = 0; octaveTranspose = 0; transposeSeen = true
        case "repeat":
            if attributeDict["direction"] == "forward" { measure?.repeatStart = true }
            if attributeDict["direction"] == "backward" {
                let count = Int(attributeDict["times"] ?? "2") ?? 0
                if !(2...8).contains(count) { abort(parser, with: .malformed("Repeat count must be between 2 and 8.")) }
                measure?.repeatCount = count
            }
        case "trill-mark", "turn", "mordent", "fermata", "staccato", "staccatissimo", "arpeggiate":
            if forReview, note != nil, elementStack.contains("notations") {
                note?.unsupportedMarks.append(name)
            } else {
                abort(parser, with: .malformed("Measure \(currentMeasureNumber): <\(name)> is not supported yet."))
            }
        case "ending", "segno", "coda", "octave-shift", "tremolo", "glissando", "slide", "bend", "harmonic", "hammer-on", "pull-off", "breath-mark", "caesura", "beat-unit-dot":
            abort(parser, with: .malformed("Measure \(currentMeasureNumber): <\(name)> is not supported yet."))
        case "harmony":
            abort(parser, with: .malformed("Chord names are not interpreted. Import the written notes of the guitar part."))
        case "dynamics", "wedge", "pedal", "slur", "accent", "strong-accent", "tenuto", "detached-legato":
            reviewWarnings.insert("Expression marks such as dynamics, slurs, accents and pedal are not preserved in playback. Check the notes and rhythms before saving.")
        case "words":
            reviewWarnings.insert("Written text instructions are not interpreted. Check tempo, repeats and other directions against the page.")
        case "fingering", "string", "fret":
            reviewWarnings.insert("Source fingering marks are not used as locks. StringMap assigns guitar positions; you can lock positions in the player.")
        case "grace":
            if note != nil { abort(parser, with: .unsupportedGraceNote(measure: currentMeasureNumber)) }
        case "rest":
            note?.isRest = true
        case "pitch":
            note?.hasPitch = true
        case "tie":
            if attributeDict["type"] == "start" { note?.tieStart = true }
            if attributeDict["type"] == "stop" { note?.tieStop = true }
        case "sound":
            if ["dacapo", "dalsegno", "tocoda", "fine"].contains(where: { attributeDict[$0] != nil }) { abort(parser, with: .malformed("Playback jumps are not supported.")); return }
            if let value = attributeDict["tempo"] {
                do { try setTempo(value) }
                catch let error as MusicXMLImportError { abort(parser, with: error) }
                catch { abort(parser, with: .malformed(error.localizedDescription)) }
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !textStack.isEmpty else { return }
        textStack[textStack.count - 1].append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(elementName)
        guard !textStack.isEmpty else { return }
        let text = textStack.removeLast().trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = elementStack.dropLast().last

        do {
            if name == "work-title" { title = text }
            if name == "miscellaneous-field", recognitionWarning {
                if !text.isEmpty { reviewWarnings.insert(String(text.prefix(500))) }
                recognitionWarning = false
            }
            if name == "movement-title" { movementTitle = text }
            if name == "creator", (parent == "identification" || elementStack.contains("identification")) {
                if !text.isEmpty, currentCreatorType == nil || currentCreatorType == "composer" { composer = text }
            }
            if name == "part-name", let id = currentScorePartID { partNames[id] = text }

            if parsingFirstPart {
                try handleEnd(name: name, parent: parent, text: text)
            }
        } catch let error as MusicXMLImportError {
            abort(parser, with: error)
        } catch {
            abort(parser, with: .malformed(error.localizedDescription))
        }

        if name == "score-part" { currentScorePartID = nil }
        if name == "creator" { currentCreatorType = nil }
        if name == "part" { parsingFirstPart = false }
        elementStack.removeLast()
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if failure == nil { failure = .malformed(parseError.localizedDescription) }
    }

    func finish(forReview: Bool) throws -> NormalizedScore {
        let root = rootName ?? "missing root"
        guard root == "score-partwise" else { throw MusicXMLImportError.unsupportedRoot(root) }
        guard actualPartCount > 0 else { throw MusicXMLImportError.missingPart }
        let resolvedTitle = !title.isEmpty ? title : (!movementTitle.isEmpty ? movementTitle : "Untitled score")
        let resolvedPartName = selectedPartID.flatMap { partNames[$0] }.flatMap { $0.isEmpty ? nil : $0 } ?? "Guitar"
        guard actualPartCount == 1 else { throw MusicXMLImportError.malformed("Import the guitar part alone. Multiple parts are not supported; no parts were discarded.") }
        let warnings = reviewWarnings.sorted()
        let score = NormalizedScore(
            source: .musicXML,
            title: resolvedTitle,
            composer: composer,
            partName: resolvedPartName,
            tempo: tempo ?? 120,
            measures: measures,
            warnings: warnings, reviewIssues: reviewIssues.isEmpty ? nil : reviewIssues
        )
        return try ScoreValidator.validate(score, allowUnresolvedTies: forReview, allowUnresolvedReviewIssues: forReview)
    }

    private func setTempo(_ value: String) throws {
        let bpm = try positiveDouble(value, element: "tempo")
        if let tempo, abs(tempo - bpm) > 1e-8 { throw MusicXMLImportError.malformed("Tempo changes inside a score are not supported yet.") }
        tempo = bpm
    }

    private func handleEnd(name: String, parent: String?, text: String) throws {
        switch name {
        case "divisions" where parent == "attributes":
            divisions = try positiveDouble(text, element: "divisions")
        case "beats" where parent == "time":
            let beats = try positiveInt(text, element: "beats")
            currentTime = TimeSignature(beats: beats, beatType: currentTime.beatType)
            measure?.timeSignature = currentTime
        case "beat-type" where parent == "time":
            let beatType = try positiveInt(text, element: "beat-type")
            currentTime = TimeSignature(beats: currentTime.beats, beatType: beatType)
            measure?.timeSignature = currentTime
        case "fifths" where parent == "key":
            currentKeyFifths = try finiteInt(text, element: "fifths")
            measure?.keyFifths = currentKeyFifths
        case "per-minute":
            try setTempo(text)
        case "beat-unit" where parent == "metronome":
            if text != "quarter" { throw MusicXMLImportError.malformed("Only quarter-note tempo marks are supported.") }
        case "step" where note != nil:
            note?.step = text
        case "alter" where note != nil:
            note?.alter = try finiteDouble(text, element: "alter")
        case "octave" where note != nil:
            note?.octave = try finiteInt(text, element: "octave")
        case "duration" where note != nil:
            note?.duration = try positiveDouble(text, element: "duration")
        case "voice" where note != nil:
            note?.voice = text.isEmpty ? "1" : text
            note?.hasExplicitVoice = !text.isEmpty
        case "staff" where note != nil:
            let staff = try positiveInt(text, element: "staff")
            guard staff == 1 else { throw MusicXMLImportError.malformed("Import one guitar staff. Piano and multiple-staff scores are not supported.") }
            note?.staff = staff
        case "staves":
            guard try positiveInt(text, element: "staves") == 1 else { throw MusicXMLImportError.malformed("Import one guitar staff, not a piano score.") }
        case "chromatic" where parent == "transpose":
            chromaticTranspose = try finiteInt(text, element: name)
            guard (-24...24).contains(chromaticTranspose) else { throw MusicXMLImportError.invalidValue(element: name, value: text) }
        case "octave-change" where parent == "transpose":
            octaveTranspose = try finiteInt(text, element: name)
            guard (-2...2).contains(octaveTranspose) else { throw MusicXMLImportError.invalidValue(element: name, value: text) }
        case "actual-notes": note?.actualNotes = try positiveInt(text, element: name)
        case "normal-notes": note?.normalNotes = try positiveInt(text, element: name)
        case "time-modification":
            guard let a = note?.actualNotes, let n = note?.normalNotes, a == 3, n == 2 else {
                throw MusicXMLImportError.unsupportedTuplet(measure: currentMeasureNumber)
            }
        case "duration" where parent == "backup":
            backupDuration = try positiveDouble(text, element: "duration")
        case "backup":
            guard let d = backupDuration, var m = measure else { throw MusicXMLImportError.missingElement("backup duration") }
            m.cursorQuarters -= d / divisions
            guard m.cursorQuarters >= -1e-8 else { throw MusicXMLImportError.malformed("A voice moves before the start of the measure.") }
            m.cursorQuarters = max(0, m.cursorQuarters); m.lastOnset = nil; m.lastVoice = nil
            measure = m
        case "duration" where parent == "forward":
            forwardDuration = try positiveDouble(text, element: "duration")
        case "note":
            try finishNote()
        case "forward":
            try finishForward()
        case "measure":
            finishMeasure()
        default:
            break
        }
    }

    private func finishNote() throws {
        guard var builder = note else { return }
        defer { note = nil }
        guard let duration = builder.duration else { throw MusicXMLImportError.missingElement("duration") }
        guard var currentMeasure = measure else { return }
        if builder.isChord && !builder.hasExplicitVoice, let voice = currentMeasure.lastVoice {
            builder.voice = voice
        }
        let id = builder.sourceID ?? "event-\(eventCounter)"
        eventCounter += 1
        guard eventCounter <= 100_000 else { throw MusicXMLImportError.malformed("Score exceeds 100,000 events.") }
        let onset: Double
        if builder.isChord {
            guard let previous = currentMeasure.lastOnset, currentMeasure.lastVoice == builder.voice, !builder.isRest else {
                throw MusicXMLImportError.malformed("A chord note must follow a pitched note in the same voice.")
            }
            onset = previous
        } else { onset = currentMeasure.cursorQuarters }
        let normalizedDuration = duration / divisions

        if builder.isRest {
            currentMeasure.events.append(.rest(NormalizedRest(
                id: id,
                measureIndex: currentMeasure.index,
                onsetQuarters: onset,
                durationQuarters: normalizedDuration, voice: builder.voice, staff: builder.staff
            )))
        } else {
            guard builder.hasPitch else { throw MusicXMLImportError.unpitchedNote(measure: currentMeasure.index + 1) }
            guard let step = builder.step else { throw MusicXMLImportError.missingElement("step") }
            guard let octave = builder.octave else { throw MusicXMLImportError.missingElement("octave") }
            let written = try musicXMLPitchToMIDI(step: step, alter: builder.alter, octave: octave)
            let midi = written + chromaticTranspose + octaveTranspose * 12
            guard (0...127).contains(midi) else { throw MusicXMLImportError.pitchOutsideMIDIRange("MIDI \(midi)") }
            currentMeasure.events.append(.note(NormalizedNote(
                id: id,
                measureIndex: currentMeasure.index,
                onsetQuarters: onset,
                durationQuarters: normalizedDuration,
                midi: midi,
                pitch: midiToPitch(midi),
                tieStart: builder.tieStart,
                tieStop: builder.tieStop, voice: builder.voice, staff: builder.staff
            )))
        }

        for (index, mark) in builder.unsupportedMarks.enumerated() {
            reviewIssues.append(ScoreReviewIssue(id: "\(id)-mark-\(index)",
                measureIndex: currentMeasure.index, measureNumber: currentMeasure.number,
                eventID: id, mark: mark))
        }
        if !builder.isChord {
            currentMeasure.cursorQuarters += normalizedDuration
            currentMeasure.lastOnset = builder.isRest ? nil : onset
            currentMeasure.lastVoice = builder.voice
        }
        measure = currentMeasure
    }

    private func finishForward() throws {
        defer { forwardDuration = nil }
        guard let duration = forwardDuration else { throw MusicXMLImportError.missingElement("duration") }
        guard var currentMeasure = measure else { return }
        currentMeasure.cursorQuarters += duration / divisions
        currentMeasure.forwardEndQuarters = max(currentMeasure.forwardEndQuarters, currentMeasure.cursorQuarters)
        measure = currentMeasure
    }

    private func finishMeasure() {
        guard let currentMeasure = measure else { return }
        let eventEnd = currentMeasure.events.map { $0.onsetQuarters + $0.durationQuarters }.max() ?? 0
        measures.append(NormalizedMeasure(
            id: currentMeasure.id,
            index: currentMeasure.index,
            number: currentMeasure.number,
            timeSignature: currentMeasure.timeSignature,
            keyFifths: currentMeasure.keyFifths,
            events: currentMeasure.events, repeatStart: currentMeasure.repeatStart, repeatCount: currentMeasure.repeatCount,
            minimumDurationQuarters: currentMeasure.forwardEndQuarters > eventEnd + 1e-8 ? currentMeasure.forwardEndQuarters : nil
        ))
        measure = nil
    }

    private var currentMeasureNumber: Int { (measure?.index ?? measures.count) + 1 }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        abort(parser, with: .malformed("Entity declarations are not supported in MusicXML."))
    }

    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
        abort(parser, with: .malformed("Entity declarations are not supported in MusicXML."))
    }

    private func abort(_ parser: XMLParser, with error: MusicXMLImportError) {
        if failure == nil { failure = error }
        parser.abortParsing()
    }
}

private func localName(_ value: String) -> String {
    value.split(separator: ":").last.map(String.init) ?? value
}

private func positiveDouble(_ value: String, element: String) throws -> Double {
    let number = try finiteDouble(value, element: element)
    guard number > 0 else { throw MusicXMLImportError.invalidValue(element: element, value: value) }
    return number
}

private func finiteDouble(_ value: String, element: String) throws -> Double {
    guard let number = Double(value), number.isFinite else {
        throw MusicXMLImportError.invalidValue(element: element, value: value)
    }
    return number
}

private func positiveInt(_ value: String, element: String) throws -> Int {
    let number = try finiteInt(value, element: element)
    guard number > 0 else { throw MusicXMLImportError.invalidValue(element: element, value: value) }
    return number
}

private func finiteInt(_ value: String, element: String) throws -> Int {
    guard let number = Int(value) else {
        throw MusicXMLImportError.invalidValue(element: element, value: value)
    }
    return number
}

private func musicXMLPitchToMIDI(step: String, alter: Double, octave: Int) throws -> Int {
    let semitones = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
    guard let semitone = semitones[step.uppercased()] else {
        throw MusicXMLImportError.invalidValue(element: "step", value: step)
    }
    guard (-1...9).contains(octave), alter.isFinite, (-2...2).contains(alter) else {
        throw MusicXMLImportError.pitchOutsideMIDIRange("Invalid octave or accidental")
    }
    let value = Double((octave + 1) * 12 + semitone) + alter
    guard value.rounded() == value, (0...127).contains(value) else {
        throw MusicXMLImportError.pitchOutsideMIDIRange("\(step)\(alter == 0 ? "" : String(alter))/\(octave)")
    }
    return Int(value)
}

private func midiToPitch(_ midi: Int) -> String {
    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return "\(names[midi % 12])\(midi / 12 - 1)"
}
