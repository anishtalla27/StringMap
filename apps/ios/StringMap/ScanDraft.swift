import Foundation
import ScorePipeline

/// One private, atomically saved draft. It survives process death and is removed
/// after save/cancellation; abandoned drafts expire locally after seven days.
struct ScanDraft: Codable {
    var requestID: String
    var serviceURL: String
    var sourceName: String
    var imageData: Data
    var musicXML: Data?
    var createdAt = Date.now
    // Missing in earlier drafts: retain their original as-encoded interpretation.
    var pitchConvention: MusicXMLPitchConvention?
    var reviewState: ScoreReviewState?
    var modifiedAt: Date?

    private static func location() throws -> URL {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "ScanDraft.plist")
    }
    static func load(from savedURL: URL? = nil) throws -> ScanDraft? {
        let url = try savedURL ?? location()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let value = try PropertyListDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard (value.modifiedAt ?? value.createdAt) > .now.addingTimeInterval(-7 * 86400) else { try clear(at: url); return nil }
        return value
    }
    func save(to savedURL: URL? = nil) throws {
        var snapshot = self; snapshot.modifiedAt = .now
        let data = try PropertyListEncoder().encode(snapshot)
        try data.write(to: savedURL ?? Self.location(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func clear(at savedURL: URL? = nil) throws {
        let url = try savedURL ?? location()
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

/// Commit an edit only after its recoverable copy has been saved. Incomplete
/// ties are allowed during correction, but final MusicXML export stays strict.
struct ScoreReviewState: Codable, Equatable {
    var score: NormalizedScore
    var history: [NormalizedScore] = []

    mutating func change(_ action: (inout NormalizedScore) throws -> Void,
                         persist: (Self) throws -> Void) throws {
        var next = self
        try action(&next.score)
        next.score = try ScoreValidator.validate(next.score, allowUnresolvedTies: true, allowUnresolvedReviewIssues: true)
        next.history.append(score)
        if next.history.count > 30 { next.history.removeFirst(next.history.count - 30) }
        try persist(next)
        self = next
    }

    mutating func undo(persist: (Self) throws -> Void) throws {
        guard let previous = history.last else { return }
        var next = self
        next.score = previous
        next.history.removeLast()
        try persist(next)
        self = next
    }
}
