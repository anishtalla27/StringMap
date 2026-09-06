import FingeringEngine

public enum AlphaTexGenerator {
    public static func generate(score: NormalizedScore, fingering: FingeringResult) throws -> String {
        let score = try ScoreValidator.validate(score)
        if score.measures.flatMap(\.events).contains(where: { (try? alphaTexDuration($0.durationQuarters)) == nil }) || score.needsPolyphonicFingering || Set(score.measures.flatMap(\.events).map(\.voice)).count > 1 || score.measures.contains(where: { measure in
            var cursor = 0.0
            for event in measure.events {
                if abs(event.onsetQuarters - cursor) > 1e-8 { return true }
                cursor += event.durationQuarters
            }
            return measure.events.isEmpty || abs(cursor - measure.durationQuarters) > 1e-8
        }) { return try generateVoices(score: score, fingering: fingering) }
        let stepsByID = Dictionary(uniqueKeysWithValues: fingering.steps.map { ($0.note.id, $0) })
        var lines = [
            "\\title \"\(escape(score.title))\"",
            "\\track \"\(escape(score.partName))\"",
            "\\staff{score tabs}",
            "\\tuning \(fingering.tuning.pitchNames.joined(separator: " "))",
            "\\instrument acousticguitarnylon",
            "\\tempo \(formatNumber(score.tempo))",
            ".",
        ]
        if fingering.capo > 0 {
            lines.insert("\\capo \(fingering.capo)", at: 4)
        }

        var previousKey = 0
        var previousTime: TimeSignature?
        for measure in score.measures {
            var tokens: [String] = []
            if abs(measure.durationQuarters - Double(measure.timeSignature.beats) * 4 / Double(measure.timeSignature.beatType)) > 1e-8 { tokens.append("\\ac") }
            if previousKey != measure.keyFifths { tokens.append("\\ks \(keyName(measure.keyFifths))"); previousKey = measure.keyFifths }
            if previousTime != measure.timeSignature {
                tokens.append("\\ts \(measure.timeSignature.beats) \(measure.timeSignature.beatType)")
                previousTime = measure.timeSignature
            }
            for event in measure.events {
                tokens.append(try token(for: event, stepsByID: stepsByID))
            }
            tokens.append("|")
            lines.append(tokens.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }

    /// Notation/playback remains available even when a guitar arrangement fails.
    public static func notation(score: NormalizedScore) throws -> String {
        try generateVoices(score: ScoreValidator.validate(score).expandingRepeats(), fingering: nil)
    }

    private static func generateVoices(score: NormalizedScore, fingering: FingeringResult?) throws -> String {
        var lines = ["\\title \"\(escape(score.title))\"", "\\track \"\(escape(score.partName))\"",
                     fingering == nil ? "\\staff{score}" : "\\staff{score tabs}",
                     fingering.map { "\\tuning \($0.tuning.pitchNames.joined(separator: " "))" } ?? "\\tuning piano",
                     "\\instrument acousticguitarnylon", "\\tempo \(formatNumber(score.tempo))", "."]
        if let fingering, fingering.capo > 0 { lines.insert("\\capo \(fingering.capo)", at: 4) }
        let positions = Dictionary(uniqueKeysWithValues: (fingering?.steps ?? []).map { ($0.note.id, $0.position) })
        let renderedVoices = score.renderedVoices
        let voices = Array(Set(renderedVoices.values)).sorted()
        for (voiceIndex, voice) in voices.enumerated() {
            if voices.count > 1 { lines.append("\\voice") }
            var previousKey = 0
            for measure in score.measures {
                var tokens: [String] = []
                if voiceIndex == 0 {
                    if previousKey != measure.keyFifths { tokens.append("\\ks \(keyName(measure.keyFifths))"); previousKey = measure.keyFifths }
                    if abs(measure.durationQuarters - Double(measure.timeSignature.beats) * 4 / Double(measure.timeSignature.beatType)) > 1e-8 { tokens.append("\\ac") }
                    tokens.append("\\ts \(measure.timeSignature.beats) \(measure.timeSignature.beatType)")
                }
                let events = measure.events.filter { renderedVoices[$0.id] == voice }
                let bounds = Array(Set([0.0, measure.durationQuarters] + events.flatMap { [$0.onsetQuarters, $0.onsetQuarters + $0.durationQuarters] })).sorted()
                for (start, end) in zip(bounds, bounds.dropFirst()) where end - start > 1e-8 {
                    var segmentStart = start
                    for segment in try durationSegments(end - start) {
                    let start = segmentStart
                    let duration = try alphaTexDuration(segment)
                    defer { segmentStart += segment }
                    let notes = events.compactMap { event -> NormalizedNote? in
                        guard case let .note(n) = event, n.onsetQuarters <= start + 1e-8,
                              n.onsetQuarters + n.durationQuarters > start + 1e-8 else { return nil }
                        return n
                    }
                    let values = try notes.map { n -> String in
                        let value: String
                        if fingering != nil {
                            guard let p = positions[n.id] else { throw MusicXMLImportError.missingElement("fingering") }
                            value = "\(p.fret).\(p.string)"
                        } else { value = ScoreValidator.pitchName(n.midi).lowercased() }
                        return value + ((n.tieStop || start > n.onsetQuarters + 1e-8) ? "{t}" : "")
                    }
                    let content = values.isEmpty ? "r" : (values.count == 1 ? values[0] : "(" + values.joined(separator: " ") + ")")
                    tokens.append("\(content).\(duration.value)\(duration.effect)")
                    }
                }
                tokens.append("|"); lines.append(tokens.joined(separator: " "))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func token(
        for event: NormalizedEvent,
        stepsByID: [String: FingeringStep]
    ) throws -> String {
        let duration = try alphaTexDuration(event.durationQuarters)
        switch event {
        case .rest:
            return "r.\(duration.value)\(duration.effect)"
        case let .note(note):
            guard let step = stepsByID[note.id] else { throw MusicXMLImportError.missingElement("fingering") }
            let tie = note.tieStop ? "{t}" : ""
            return "\(step.position.fret).\(step.position.string)\(tie).\(duration.value)\(duration.effect)"
        }
    }

    // Split durations introduced by overlapping voices into exact tied beats.
    // Never round an unsupported rhythm or alter source note identities.
    static func durationSegments(_ quarters: Double) throws -> [Double] {
        if (try? alphaTexDuration(quarters)) != nil { return [quarters] }
        let grid: Double
        if abs(quarters * 16 - (quarters * 16).rounded()) < 1e-7 { grid = 16 }
        else if abs(quarters * 12 - (quarters * 12).rounded()) < 1e-7 { grid = 12 }
        else if abs(quarters * 24 - (quarters * 24).rounded()) < 1e-7 { grid = 24 }
        else { throw MusicXMLImportError.unsupportedDuration(quarters) }
        guard quarters > 0, quarters <= 128 else { throw MusicXMLImportError.unsupportedDuration(quarters) }
        let options: [Double] = grid == 16 ? [4.0, 3, 2, 1.5, 1, 0.75, 0.5, 0.375, 0.25, 0.125, 0.0625] :
            [4.0, 2, 1, 0.5, 0.25, 1.0 / 6, 1.0 / 12] + (grid == 24 ? [1.0 / 24] : [])
        var remaining = Int((quarters * grid).rounded())
        var result: [Double] = []
        for value in options {
            let ticks = Int((value * grid).rounded())
            while remaining >= ticks { result.append(value); remaining -= ticks }
        }
        guard remaining == 0 else { throw MusicXMLImportError.unsupportedDuration(quarters) }
        return result
    }

    static func alphaTexDuration(_ quarters: Double) throws -> (value: Int, effect: String) {
        let candidates: [(Double, Int, String)] = [
            (4, 1, ""), (3, 2, "{d}"), (2, 2, ""), (1.5, 4, "{d}"),
            (1, 4, ""), (0.75, 8, "{d}"), (0.5, 8, ""),
            (0.375, 16, "{d}"), (0.25, 16, ""), (0.125, 32, ""), (0.0625, 64, ""),
            (4.0 / 3, 2, "{tu 3}"), (2.0 / 3, 4, "{tu 3}"),
            (1.0 / 3, 8, "{tu 3}"), (1.0 / 6, 16, "{tu 3}"), (1.0 / 12, 32, "{tu 3}"),
            (1.0 / 24, 64, "{tu 3}"),
        ]
        guard let match = candidates.first(where: { abs($0.0 - quarters) < 0.0000001 }) else {
            throw MusicXMLImportError.unsupportedDuration(quarters)
        }
        return (match.1, match.2)
    }

    private static func keyName(_ fifths: Int) -> String {
        ["cb", "gb", "db", "ab", "eb", "bb", "f", "c", "g", "d", "a", "e", "b", "f#", "c#"][fifths + 7]
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func formatNumber(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}
