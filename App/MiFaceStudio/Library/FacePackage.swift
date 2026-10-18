import Foundation
import ZIPFoundation

/// Reads and rewrites Xiaomi watch-face containers without needing any of the
/// vendor desktop binaries.
///
/// Supported:
/// - `.face` / `.bin` raw containers beginning with `5A A5 34 12`
/// - `.mwz` / zipped `.face` packages built around a raw `.bin`
enum FacePackage {
    static let rawMagic: [UInt8] = [0x5A, 0xA5, 0x34, 0x12]
    static let zipMagic: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
    static let idOffset = 34
    static let idFieldLength = 24

    struct Metadata {
        var name: String = ""
        var deviceType: String = ""
        var size: String = ""
        var identifier: String?
        var isZip: Bool = false
    }

    enum PackageError: LocalizedError {
        case unsupported
        case badZip
        case idNotFound
        case idTooLong

        var errorDescription: String? {
            switch self {
            case .unsupported: return "不是可识别的表盘文件（.face / .bin / .mwz）"
            case .badZip: return "表盘压缩包损坏"
            case .idNotFound: return "无法在表盘中找到表盘 ID"
            case .idTooLong: return "新的表盘 ID 超出预留字段"
            }
        }
    }

    static func isWatchFace(_ data: Data) -> Bool {
        hasRawMagic(data) || hasZipMagic(data)
    }

    private static func hasRawMagic(_ data: Data) -> Bool {
        data.count >= 4 && data.prefix(4).elementsEqual(rawMagic)
    }

    private static func hasZipMagic(_ data: Data) -> Bool {
        data.count >= 4 && data.prefix(4).elementsEqual(zipMagic)
    }

    static func metadata(for data: Data) -> Metadata {
        if hasRawMagic(data) {
            var meta = Metadata()
            meta.identifier = readRawID(data)
            meta.name = readRawName(data)
            meta.isZip = false
            return meta
        }
        guard hasZipMagic(data),
              let archive = try? Archive(data: data, accessMode: .read) else {
            return Metadata()
        }
        var meta = Metadata()
        meta.isZip = true
        for entry in archive {
            let name = entry.path.lowercased()
            guard name.hasSuffix("description.xml") else { continue }
            var xml = Data()
            _ = try? archive.extract(entry) { xml.append($0) }
            let text = String(decoding: xml, as: UTF8.self)
            meta.name = xmlValue(text, tag: "name") ?? meta.name
            meta.deviceType = xmlValue(text, tag: "deviceType") ?? meta.deviceType
            meta.size = xmlValue(text, tag: "size") ?? meta.size
            meta.identifier = xmlValue(text, tag: "_id") ?? xmlValue(text, tag: "id")
            break
        }
        if meta.identifier == nil {
            meta.identifier = readIDFromZipBin(data)
        }
        return meta
    }

    static func prepareForInstall(_ data: Data, preferredID: String? = nil) throws -> (data: Data, id: String) {
        if hasRawMagic(data) {
            var out = Data(data)
            let existing = readRawID(out)
            let id = preferredID ?? existing ?? makeID()
            if let existing, existing == id {
                return (out, id)
            }
            try writeRawID(&out, id: id)
            return (out, id)
        }

        guard hasZipMagic(data) else { throw PackageError.unsupported }
        guard let archive = try? Archive(data: data, accessMode: .read) else {
            throw PackageError.badZip
        }
        let requested = preferredID ?? metadata(for: data).identifier ?? makeID()
        let id = sanitizeID(requested) ?? makeID()
        let tempDir = AppPaths.temp.appendingPathComponent("repack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outURL = tempDir.appendingPathComponent("out.mwz")
        do {
            let outArchive = try Archive(url: outURL, accessMode: .create)
            var replacedAnyBin = false

            for entry in archive {
                if entry.type == .directory { continue }
                var content = Data()
                _ = try archive.extract(entry) { content.append($0) }
                var path = entry.path
                let lower = path.lowercased()

                if lower.hasSuffix(".bin"), hasRawMagic(content) {
                    let old = readRawID(content)
                    try? writeRawID(&content, id: id)
                    if let old, !old.isEmpty { path = path.replacingOccurrences(of: old, with: id) }
                    replacedAnyBin = true
                } else if lower.hasSuffix("description.xml") {
                    var text = String(decoding: content, as: UTF8.self)
                    text = replaceXMLValue(text, tag: "_id", value: id)
                    text = replaceXMLValue(text, tag: "id", value: id)
                    content = Data(text.utf8)
                } else if lower.hasSuffix("manifest.xml") {
                    var text = String(decoding: content, as: UTF8.self)
                    text = replaceManifestID(text, id: id)
                    content = Data(text.utf8)
                }

                try outArchive.addEntry(
                    with: path,
                    type: .file,
                    uncompressedSize: Int64(content.count),
                    compressionMethod: .deflate
                ) { position, size in
                    let start = Int(position)
                    return content.subdata(in: start..<min(start + size, content.count))
                }
            }

            guard replacedAnyBin else { throw PackageError.idNotFound }
        }
        let packed = try Data(contentsOf: outURL)
        return (packed, id)
    }

    /// Generate an ID that the firmware accepts (9 or 12 alphanumerics).
    static func makeID(length: Int = 9) -> String {
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    static func sanitizeID(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard [9, 12].contains(trimmed.utf8.count),
              trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            return nil
        }
        return trimmed
    }

    // MARK: - Raw container

    static func readRawID(_ data: Data) -> String? {
        guard data.count >= idOffset + idFieldLength else { return nil }
        let field = [UInt8](data[idOffset..<(idOffset + idFieldLength)])
        var run: [UInt8] = []
        for byte in field {
            if isAlphanumeric(byte) {
                run.append(byte)
            } else {
                if [9, 12].contains(run.count), let text = String(bytes: run, encoding: .utf8) {
                    return text
                }
                run.removeAll(keepingCapacity: true)
            }
        }
        if [9, 12].contains(run.count), let text = String(bytes: run, encoding: .utf8) {
            return text
        }
        return nil
    }

    static func writeRawID(_ data: inout Data, id: String) throws {
        guard data.count >= idOffset + idFieldLength else { throw PackageError.idNotFound }
        let bytes = Array(id.utf8)
        guard bytes.count <= idFieldLength else { throw PackageError.idTooLong }
        let oldField = [UInt8](data[idOffset..<(idOffset + idFieldLength)])
        var start = 0
        if let range = findIDRange(in: oldField) {
            start = range.lowerBound
        } else if let digit = oldField.firstIndex(where: { $0 >= 48 && $0 <= 57 }) {
            start = digit
            while start > 0 && isAlphanumeric(oldField[start - 1]) { start -= 1 }
        }
        guard start + bytes.count <= idFieldLength else { throw PackageError.idTooLong }
        data.replaceSubrange((idOffset + start)..<(idOffset + start + bytes.count), with: bytes)
        let tailStart = idOffset + start + bytes.count
        let tailEnd = idOffset + idFieldLength
        if tailStart < tailEnd {
            data.replaceSubrange(tailStart..<tailEnd, with: [UInt8](repeating: 0, count: tailEnd - tailStart))
        }
    }

    private static func findIDRange(in field: [UInt8]) -> Range<Int>? {
        var index = 0
        while index < field.count {
            guard isAlphanumeric(field[index]) else { index += 1; continue }
            let start = index
            while index < field.count, isAlphanumeric(field[index]) { index += 1 }
            if [9, 12].contains(index - start) { return start..<index }
        }
        return nil
    }

    private static func readRawName(_ data: Data) -> String {
        // The N67 container stores a NUL-terminated display name after the
        // fixed header.  Scan a conservative window and pick the longest run.
        guard data.count > 90 else { return "" }
        let window = [UInt8](data[80..<min(data.count, 240)])
        var best = ""
        var current: [UInt8] = []
        for byte in window {
            if byte == 0 {
                if current.count >= 3, let text = String(bytes: current, encoding: .utf8) {
                    if text.count > best.count { best = text }
                }
                current.removeAll(keepingCapacity: true)
            } else if byte >= 32 && byte < 127 {
                current.append(byte)
            } else {
                current.removeAll(keepingCapacity: true)
            }
        }
        return best.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Zip helpers

    private static func readIDFromZipBin(_ data: Data) -> String? {
        guard let archive = try? Archive(data: data, accessMode: .read) else { return nil }
        for entry in archive where entry.path.lowercased().hasSuffix(".bin") {
            var bin = Data()
            _ = try? archive.extract(entry) { bin.append($0) }
            if let id = readRawID(bin) { return id }
        }
        return nil
    }

    private static func isAlphanumeric(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
    }

    private static func xmlValue(_ xml: String, tag: String) -> String? {
        guard let start = xml.range(of: "<\(tag)>"),
              let end = xml.range(of: "</\(tag)>", range: start.upperBound..<xml.endIndex) else {
            return nil
        }
        return String(xml[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replaceXMLValue(_ xml: String, tag: String, value: String) -> String {
        guard let start = xml.range(of: "<\(tag)>"),
              let end = xml.range(of: "</\(tag)>", range: start.upperBound..<xml.endIndex) else {
            return xml
        }
        return xml.replacingCharacters(in: start.upperBound..<end.lowerBound, with: value)
    }

    private static func replaceManifestID(_ xml: String, id: String) -> String {
        guard let range = xml.range(of: "id=\"") else { return xml }
        guard let end = xml.range(of: "\"", range: range.upperBound..<xml.endIndex) else { return xml }
        return xml.replacingCharacters(in: range.upperBound..<end.lowerBound, with: id)
    }
}
