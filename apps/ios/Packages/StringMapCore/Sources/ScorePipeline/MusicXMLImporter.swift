import Foundation

public struct MusicXMLImporter: ScoreImporter {
    public init() {}

    public func importScore(from data: Data) throws -> NormalizedScore {
        guard !data.isEmpty else { throw MusicXMLImportError.emptyInput }
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true

        let succeeded = parser.parse()
        if let error = delegate.failure { throw error }
        guard succeeded else {
            throw MusicXMLImportError.malformed(parser.parserError?.localizedDescription ?? "Unknown parser error")
        }
        return try delegate.finish()
    }
}

private final class ParserDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {
    struct NoteBuilder {
        var sourceID: String?
        var step: String?
        var alter = 0.0
        var octave: Int?
        var duration: Double?
        var isRest = false
        var hasPitch = false
        var tieStart = false
        var tieStop = false
    }

    struct MeasureBuilder {
        let id: String
        let index: Int
        let number: String
        var timeSignature: TimeSignature
        var keyFifths: Int
        var cursorDivisions = 0.0
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
    private var eventCounter = 0

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

        if name == "score-part" {
            currentScorePartID = attributeDict["id"]
        } else if name == "creator" {
            currentCreatorType = attributeDict["type"]
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
            abort(parser, with: .unsupportedMultipleVoices(measure: currentMeasureNumber))
        case "chord":
            if note != nil { abort(parser, with: .unsupportedChord(measure: currentMeasureNumber)) }
        case "grace":
            if note != nil { abort(parser, with: .unsupportedGraceNote(measure: currentMeasureNumber)) }
        case "time-modification":
            if note != nil { abort(parser, with: .unsupportedTuplet(measure: currentMeasureNumber)) }
        case "rest":
            note?.isRest = true
        case "pitch":
            note?.hasPitch = true
        case "tie":
            if attributeDict["type"] == "start" { note?.tieStart = true }
            if attributeDict["type"] == "stop" { note?.tieStop = true }
        case "sound":
            if tempo == nil, let value = attributeDict["tempo"] {
                do { tempo = try positiveDouble(value, element: "tempo") }
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
        let text = textStack.removeLast().trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = elementStack.dropLast().last

        do {
            if name == "work-title" { title = text }
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

    func finish() throws -> NormalizedScore {
        let root = rootName ?? "missing root"
        guard root == "score-partwise" else { throw MusicXMLImportError.unsupportedRoot(root) }
        guard actualPartCount > 0 else { throw MusicXMLImportError.missingPart }
        let resolvedTitle = !title.isEmpty ? title : (!movementTitle.isEmpty ? movementTitle : "Untitled score")
        let resolvedPartName = selectedPartID.flatMap { partNames[$0] }.flatMap { $0.isEmpty ? nil : $0 } ?? "Guitar"
        let warnings = actualPartCount > 1 ? ["Only the first MusicXML part was imported."] : []
        return NormalizedScore(
            source: .musicXML,
            title: resolvedTitle,
            composer: composer,
            partName: resolvedPartName,
            tempo: tempo ?? 120,
            measures: measures,
            warnings: warnings
        )
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
            if tempo == nil { tempo = try positiveDouble(text, element: "tempo") }
        case "step" where note != nil:
            note?.step = text
        case "alter" where note != nil:
            note?.alter = try finiteDouble(text, element: "alter")
        case "octave" where note != nil:
            note?.octave = try finiteInt(text, element: "octave")
        case "duration" where note != nil:
            note?.duration = try positiveDouble(text, element: "duration")
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
        guard let builder = note else { return }
        defer { note = nil }
        guard let duration = builder.duration else { throw MusicXMLImportError.missingElement("duration") }
        guard var currentMeasure = measure else { return }
        let id = builder.sourceID ?? "event-\(eventCounter)"
        eventCounter += 1
        let onset = currentMeasure.cursorDivisions / divisions
        let normalizedDuration = duration / divisions

        if builder.isRest {
            currentMeasure.events.append(.rest(NormalizedRest(
                id: id,
                measureIndex: currentMeasure.index,
                onsetQuarters: onset,
                durationQuarters: normalizedDuration
            )))
        } else {
            guard builder.hasPitch else { throw MusicXMLImportError.unpitchedNote(measure: currentMeasure.index + 1) }
            guard let step = builder.step else { throw MusicXMLImportError.missingElement("step") }
            guard let octave = builder.octave else { throw MusicXMLImportError.missingElement("octave") }
            let midi = try musicXMLPitchToMIDI(step: step, alter: builder.alter, octave: octave)
            currentMeasure.events.append(.note(NormalizedNote(
                id: id,
                measureIndex: currentMeasure.index,
                onsetQuarters: onset,
                durationQuarters: normalizedDuration,
                midi: midi,
                pitch: midiToPitch(midi),
                tieStart: builder.tieStart,
                tieStop: builder.tieStop
            )))
        }

        currentMeasure.cursorDivisions += duration
        measure = currentMeasure
    }

    private func finishForward() throws {
        defer { forwardDuration = nil }
        guard let duration = forwardDuration else { throw MusicXMLImportError.missingElement("duration") }
        guard var currentMeasure = measure else { return }
        currentMeasure.events.append(.rest(NormalizedRest(
            id: "rest-\(eventCounter)",
            measureIndex: currentMeasure.index,
            onsetQuarters: currentMeasure.cursorDivisions / divisions,
            durationQuarters: duration / divisions
        )))
        eventCounter += 1
        currentMeasure.cursorDivisions += duration
        measure = currentMeasure
    }

    private func finishMeasure() {
        guard let currentMeasure = measure else { return }
        measures.append(NormalizedMeasure(
            id: currentMeasure.id,
            index: currentMeasure.index,
            number: currentMeasure.number,
            timeSignature: currentMeasure.timeSignature,
            keyFifths: currentMeasure.keyFifths,
            events: currentMeasure.events
        ))
        measure = nil
    }

    private var currentMeasureNumber: Int { (measure?.index ?? measures.count) + 1 }

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
    let value = Double((octave + 1) * 12 + semitone) + alter
    guard value.rounded() == value, (0...127).contains(Int(value)) else {
        throw MusicXMLImportError.pitchOutsideMIDIRange("\(step)\(alter == 0 ? "" : String(alter))/\(octave)")
    }
    return Int(value)
}

private func midiToPitch(_ midi: Int) -> String {
    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return "\(names[midi % 12])\(midi / 12 - 1)"
}
