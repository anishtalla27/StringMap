import FingeringEngine

public enum AlphaTexGenerator {
    public static func generate(score: NormalizedScore, fingering: FingeringResult) throws -> String {
        let stepsByID = Dictionary(uniqueKeysWithValues: fingering.steps.map { ($0.note.id, $0) })
        var lines = [
            "\\title \"\(escape(score.title))\"",
            "\\track \"\(escape(score.partName))\"",
            "\\staff{score tabs}",
            "\\tuning \(fingering.tuning.pitchNames.joined(separator: " "))",
            "\\instrument acousticguitarsteel",
            "\\tempo \(formatNumber(score.tempo))",
            ".",
        ]
        if fingering.capo > 0 {
            lines.insert("\\capo \(fingering.capo)", at: 4)
        }

        var previousTime: TimeSignature?
        for measure in score.measures {
            var tokens: [String] = []
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
            return "\(step.position.fret).\(step.position.string).\(duration.value)\(duration.effect)\(tie)"
        }
    }

    private static func alphaTexDuration(_ quarters: Double) throws -> (value: Int, effect: String) {
        let candidates: [(Double, Int, String)] = [
            (4, 1, ""), (3, 2, "{d}"), (2, 2, ""), (1.5, 4, "{d}"),
            (1, 4, ""), (0.75, 8, "{d}"), (0.5, 8, ""),
            (0.375, 16, "{d}"), (0.25, 16, ""), (0.125, 32, ""),
        ]
        guard let match = candidates.first(where: { abs($0.0 - quarters) < 0.0000001 }) else {
            throw MusicXMLImportError.unsupportedDuration(quarters)
        }
        return (match.1, match.2)
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func formatNumber(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}
