import Foundation
import ZIPFoundation

/// Opens plain MusicXML or its standard .mxl container entirely in memory.
/// Only the declared score and container metadata are decompressed; embedded
/// images, audio and alternative renditions are never extracted or followed.
public enum MusicXMLContainer {
    public static let maximumInputBytes = 20 * 1024 * 1024
    public static let maximumScoreBytes = 10 * 1024 * 1024

    public static func read(from url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var data = Data()
        while let chunk = try file.read(upToCount: min(64 * 1024, maximumInputBytes + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= maximumInputBytes else { throw invalid("File exceeds 20 MB.") }
        }
        return data
    }

    public static func scoreData(from data: Data) throws -> Data {
        guard !data.isEmpty else { throw MusicXMLImportError.emptyInput }
        guard data.count <= maximumInputBytes else { throw invalid("File exceeds 20 MB.") }
        guard data.starts(with: [0x50, 0x4b]) else {
            guard data.count <= maximumScoreBytes else { throw invalid("Score exceeds 10 MB.") }
            return data
        }
        do {
            let archive = try Archive(data: data, accessMode: .read, pathEncoding: .utf8)
            var entries: [String: Entry] = [:]
            for entry in archive {
                guard entries.count < 256 else { throw invalid("Compressed score contains too many files.") }
                guard entries.updateValue(entry, forKey: entry.path) == nil else {
                    throw invalid("Compressed score contains duplicate file names.")
                }
            }
            guard let container = entries["META-INF/container.xml"] else {
                throw invalid("This archive is missing its MusicXML container. Export it as compressed MusicXML (.mxl).")
            }
            let metadata = try extract(container, from: archive, limit: 64 * 1024)
            let delegate = ContainerDelegate()
            let parser = XMLParser(data: metadata)
            parser.shouldProcessNamespaces = true
            parser.shouldResolveExternalEntities = false
            parser.externalEntityResolvingPolicy = .never
            parser.delegate = delegate
            guard parser.parse(), !delegate.invalid, let path = delegate.rootPath,
                  delegate.mediaType == nil || delegate.mediaType == "application/vnd.recordare.musicxml+xml" else {
                throw invalid("The compressed MusicXML container is invalid or does not declare a MusicXML score.")
            }
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  !path.contains("\\"), !path.contains(":"), !path.contains("\0"),
                  let score = entries[path] else {
                throw invalid("The score declared by this MusicXML container is missing or has an invalid path.")
            }
            return try extract(score, from: archive, limit: maximumScoreBytes)
        } catch let error as MusicXMLImportError { throw error }
        catch { throw invalid("The compressed score is damaged or uses unsupported ZIP compression. Export a new MusicXML file.") }
    }

    private static func extract(_ entry: Entry, from archive: Archive, limit: Int) throws -> Data {
        guard entry.type == .file, entry.uncompressedSize > 0, entry.uncompressedSize <= UInt64(limit) else {
            throw invalid("The compressed score contains an invalid or oversized document.")
        }
        var output = Data()
        let checksum = try archive.extract(entry, bufferSize: 16 * 1024) { chunk in
            guard chunk.count <= limit - output.count else { throw invalid("The expanded MusicXML document exceeds its size limit.") }
            output.append(chunk)
        }
        guard output.count == entry.uncompressedSize, checksum == entry.checksum else {
            throw invalid("The compressed score failed its integrity check. Export a new MusicXML file.")
        }
        return output
    }

    private static func invalid(_ message: String) -> MusicXMLImportError { .malformed(message) }
}

private final class ContainerDelegate: NSObject, XMLParserDelegate {
    var rootPath: String?
    var mediaType: String?
    var invalid = false
    private var elements: [String] = []
    private var foundRoot = false

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        elements.append(name)
        if elements.count == 1 && name != "container" { invalid = true; parser.abortParsing() }
        if elements == ["container", "rootfiles", "rootfile"] && !foundRoot {
            foundRoot = true; rootPath = attributes["full-path"]; mediaType = attributes["media-type"]
        }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) { elements.removeLast() }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { invalid = true; parser.abortParsing() }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { invalid = true; parser.abortParsing() }
}
