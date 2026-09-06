import Foundation

extension NormalizedScore {
    /// Correct signature metadata without transposing or retiming note events.
    /// Each inherited signature stops at its own next pre-existing change.
    public func updatingSignatures(at index: Int, timeSignature: TimeSignature,
                                   keyFifths: Int, includeFollowing: Bool) throws -> Self {
        guard measures.indices.contains(index), (1...32).contains(timeSignature.beats),
              [1, 2, 4, 8, 16, 32].contains(timeSignature.beatType), (-7...7).contains(keyFifths) else {
            throw MusicXMLImportError.malformed("Choose a valid measure, time signature and key signature.")
        }
        var result = self
        let original = measures[index]
        var updateTime = true
        var updateKey = true
        for i in index..<(includeFollowing ? measures.count : index + 1) {
            if measures[i].timeSignature != original.timeSignature { updateTime = false }
            if measures[i].keyFifths != original.keyFifths { updateKey = false }
            if updateTime { result.measures[i].timeSignature = timeSignature }
            if updateKey { result.measures[i].keyFifths = keyFifths }
        }
        return result
    }
}

/// Shared checks for imported and edited scores. Validation is independent of
/// guitar range so an unplayable recognition result can still be corrected.
public enum ScoreValidator {
    public static func validate(_ input: NormalizedScore, allowUnresolvedTies: Bool = false, allowUnresolvedReviewIssues: Bool = false) throws -> NormalizedScore {
        if !allowUnresolvedReviewIssues, let issue = input.reviewIssues?.first {
            throw MusicXMLImportError.malformed("Measure \(issue.measureNumber): resolve the unsupported \(issue.mark) mark in note review before playback or saving.")
        }
        var score = input
        // Recompute these validation findings after edits. Recognition warnings
        // about the source image and unsupported symbols must remain available.
        score.warnings.removeAll {
            $0.hasPrefix("Correct the unmatched or ambiguous tie into ")
                || $0 == "A tied note needs a continuation or removal of its tie mark."
        }
        guard score.tempo.isFinite, (10...600).contains(score.tempo), !score.measures.isEmpty,
              score.measures.count <= 10_000 else { throw MusicXMLImportError.malformed("Score needs measures and a tempo from 10 to 600 BPM.") }
        var ids = Set<String>(); var ties: [String: [(String, Double)]] = [:]; var offset = 0.0
        for m in score.measures.indices {
            let measure = score.measures[m]
            if let extent = measure.minimumDurationQuarters {
                guard extent.isFinite, extent > 0, extent <= 160 else {
                    throw MusicXMLImportError.malformed("Invalid measure length in measure \(m + 1).")
                }
            }
            guard (1...32).contains(measure.timeSignature.beats), [1, 2, 4, 8, 16, 32].contains(measure.timeSignature.beatType),
                  (-7...7).contains(measure.keyFifths) else { throw MusicXMLImportError.malformed("Invalid time or key signature in measure \(m + 1).") }
            score.measures[m].index = m
            score.measures[m].events.sort { $0.onsetQuarters == $1.onsetQuarters ? $0.id < $1.id : $0.onsetQuarters < $1.onsetQuarters }
            for e in score.measures[m].events.indices {
                let event = score.measures[m].events[e]
                guard !event.id.isEmpty, ids.insert(event.id).inserted else { throw MusicXMLImportError.malformed("Every note and rest needs a unique identifier: \(event.id).") }
                guard event.onsetQuarters.isFinite, (0...128).contains(event.onsetQuarters),
                      event.durationQuarters.isFinite, event.durationQuarters > 0, event.durationQuarters <= 32,
                      event.staff == 1, !event.voice.isEmpty else { throw MusicXMLImportError.malformed("Invalid note timing or staff in measure \(m + 1).") }
                switch event {
                case var .note(note):
                    guard (0...127).contains(note.midi) else { throw MusicXMLImportError.pitchOutsideMIDIRange("MIDI \(note.midi)") }
                    note.measureIndex = m; note.pitch = pitchName(note.midi); note.tieFromID = nil
                    let key = "\(note.voice):\(note.staff):\(note.midi)"
                    if note.tieStop {
                        let onset = offset + note.onsetQuarters
                        let sameVoice = (ties[key] ?? []).enumerated().filter { abs($0.element.1 - onset) < 1e-7 }.map { (key, $0.offset) }
                        let matches = sameVoice.isEmpty ? ties.keys.sorted().filter { $0.hasSuffix(":\(note.staff):\(note.midi)") }.flatMap { candidateKey in
                            (ties[candidateKey] ?? []).enumerated().filter { abs($0.element.1 - onset) < 1e-7 }.map { (candidateKey, $0.offset) }
                        } : sameVoice
                        if matches.count == 1, let match = matches.first,
                           let previous = ties[match.0]?.remove(at: match.1) { note.tieFromID = previous.0 }
                        else if allowUnresolvedTies { score.warnings.append("Correct the unmatched or ambiguous tie into \(note.id).") }
                        else { throw MusicXMLImportError.malformed("Tie into \(note.id) has no unique matching sustained note.") }
                    }
                    if note.tieStart { ties[key, default: []].append((note.id, offset + note.onsetQuarters + note.durationQuarters)) }
                    score.measures[m].events[e] = .note(note)
                case var .rest(rest):
                    rest.measureIndex = m; score.measures[m].events[e] = .rest(rest)
                }
            }
            offset += measure.durationQuarters
        }
        if !ties.values.allSatisfy(\.isEmpty) {
            if allowUnresolvedTies { score.warnings.append("A tied note needs a continuation or removal of its tie mark.") }
            else { throw MusicXMLImportError.malformed("A tied note has no continuation. Correct the tie before saving.") }
        }
        return score
    }

    public static func pitchName(_ midi: Int) -> String {
        guard (0...127).contains(midi) else { return "Invalid pitch" }
        return ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"][midi % 12] + String(midi / 12 - 1)
    }
}

/// Writes sounding pitches; the source's MusicXML transpose has already been
/// applied exactly once on import. A clef's octave label is display information.
public enum MusicXMLWriter {
    public static func data(for input: NormalizedScore) throws -> Data {
        let score = try ScoreValidator.validate(input)
        let divisions = 24_000
        func ticks(_ value: Double) throws -> Int {
            let scaled = value * Double(divisions)
            guard abs(scaled - scaled.rounded()) < 1e-6 else { throw MusicXMLImportError.unsupportedDuration(value) }
            return Int(scaled.rounded())
        }
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><score-partwise version=\"4.0\"><work><work-title>\(escape(score.title))</work-title></work>"
        if let composer = score.composer { xml += "<identification><creator type=\"composer\">\(escape(composer))</creator></identification>" }
        xml += "<part-list><score-part id=\"P1\"><part-name>\(escape(score.partName))</part-name></score-part></part-list><part id=\"P1\">"
        for measure in score.measures {
            xml += "<measure id=\"\(escape(measure.id))\" number=\"\(escape(measure.number))\"><attributes><divisions>\(divisions)</divisions><key><fifths>\(measure.keyFifths)</fifths></key><time><beats>\(measure.timeSignature.beats)</beats><beat-type>\(measure.timeSignature.beatType)</beat-type></time><clef><sign>G</sign><line>2</line><clef-octave-change>-1</clef-octave-change></clef></attributes>"
            if measure.index == 0 { xml += "<direction><sound tempo=\"\(score.tempo)\"/></direction>" }
            if measure.repeatStart { xml += "<barline location=\"left\"><repeat direction=\"forward\"/></barline>" }
            var cursor = 0
            // Use backup/forward instead of inferring chord duration. This also
            // preserves overlapping voices with different note lengths.
            for event in measure.events {
                let onset = try ticks(event.onsetQuarters); let duration = try ticks(event.durationQuarters)
                if onset < cursor { xml += "<backup><duration>\(cursor - onset)</duration></backup>" }
                if onset > cursor { xml += "<forward><duration>\(onset - cursor)</duration></forward>" }
                xml += "<note id=\"\(escape(event.id))\">"
                switch event {
                case .rest: xml += "<rest/>"
                case let .note(n):
                    let steps = ["C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B"]
                    let sharp = [1, 3, 6, 8, 10].contains(n.midi % 12)
                    xml += "<pitch><step>\(steps[n.midi % 12])</step>\(sharp ? "<alter>1</alter>" : "")<octave>\(n.midi / 12 - 1)</octave></pitch>"
                }
                xml += "<duration>\(duration)</duration>"
                if case let .note(n) = event {
                    if n.tieStop { xml += "<tie type=\"stop\"/>" }
                    if n.tieStart { xml += "<tie type=\"start\"/>" }
                }
                xml += "<voice>\(escape(event.voice))</voice></note>"; cursor = onset + duration
            }
            if let minimum = measure.minimumDurationQuarters {
                let end = try ticks(minimum)
                if end > cursor { xml += "<forward><duration>\(end - cursor)</duration></forward>" }
            }
            if measure.repeatCount > 0 { xml += "<barline location=\"right\"><repeat direction=\"backward\" times=\"\(measure.repeatCount)\"/></barline>" }
            xml += "</measure>"
        }
        xml += "</part></score-partwise>"
        return Data(xml.utf8)
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

extension NormalizedScore {
    /// Simple repeat sections are expanded for a single consistent practice,
    /// fingering and playback timeline. IDs retain the source ID as a prefix.
    public func expandingRepeats() throws -> NormalizedScore {
        guard measures.contains(where: { $0.repeatStart || $0.repeatCount > 0 }) else { return self }
        var result = self; result.measures = []; var start = 0; var open = false
        for (index, measure) in measures.enumerated() {
            if measure.repeatStart {
                guard !open else { throw MusicXMLImportError.malformed("Nested repeats are not supported.") }
                start = index; open = true
            }
            result.measures.append(measure)
            if measure.repeatCount > 0 {
                for pass in 2...measure.repeatCount {
                    for original in measures[start...index] {
                        var copy = original; copy.id += "-repeat\(pass)"; copy.number += " (\(pass))"
                        copy.events = original.events.map { event in
                            switch event {
                            case var .note(n): n.id += "-repeat\(pass)"; return .note(n)
                            case var .rest(r): r.id += "-repeat\(pass)"; return .rest(r)
                            }
                        }
                        result.measures.append(copy)
                    }
                }
                start = index + 1; open = false
            }
        }
        guard !open else { throw MusicXMLImportError.malformed("A repeat start has no matching repeat end.") }
        for i in result.measures.indices { result.measures[i].repeatStart = false; result.measures[i].repeatCount = 0 }
        result.warnings.append("Repeat sections are written out in full for synchronized practice.")
        return try ScoreValidator.validate(result)
    }
}
