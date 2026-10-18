import Foundation
import UIKit

/// Minimal, byte-compatible implementation of the LVGLImage tool used by the
/// Xiaomi editor.  The editor shells out to that binary for every image in a
/// watch face; on iOS we reproduce the output format in-process.
enum LVGLImageEncoder {
    enum Format: String {
        case argb8888 = "ARGB8888"
        case rgb565 = "RGB565"
        case a8 = "A8"
        case i8 = "I8"

        var code: UInt8 {
            switch self {
            case .a8: return 0x0E
            case .argb8888: return 0x10
            case .rgb565: return 0x12
            case .i8: return 0x09
            }
        }

        var bytesPerPixel: Int {
            switch self {
            case .a8, .i8: return 1
            case .rgb565: return 2
            case .argb8888: return 4
            }
        }
    }

    enum EncoderError: LocalizedError {
        case cannotDecode(String)
        case unsupportedFormat(String)
        case cannotWrite(String)

        var errorDescription: String? {
            switch self {
            case .cannotDecode(let path): return "无法解码图片：\(path)"
            case .unsupportedFormat(let f): return "暂不支持的图片格式：\(f)"
            case .cannotWrite(let path): return "无法写入：\(path)"
            }
        }
    }

    static func run(arguments: [String]) throws -> String {
        guard arguments.count >= 2 else { throw EncoderError.cannotDecode("参数不足") }
        let input = arguments[0]
        var outputDir: String?
        var format = Format.argb8888
        var rle = false
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "-o":
                index += 1
                if index < arguments.count { outputDir = arguments[index] }
            case "--cf":
                index += 1
                if index < arguments.count, let parsed = Format(rawValue: arguments[index].uppercased()) {
                    format = parsed
                }
            case "--compress":
                index += 1
                if index < arguments.count {
                    rle = arguments[index].uppercased() != "NONE"
                }
            default:
                break
            }
            index += 1
        }
        guard let outputDir else { throw EncoderError.cannotWrite("缺少 -o 输出目录") }
        let outRoot = AppPaths.nativeURL(for: outputDir) ?? URL(fileURLWithPath: outputDir)
        try FileManager.default.createDirectory(at: outRoot, withIntermediateDirectories: true)

        let inputURL = AppPaths.nativeURL(for: input) ?? URL(fileURLWithPath: input)
        let fm = FileManager.default
        var count = 0
        if (try? inputURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let files = try fm.contentsOfDirectory(at: inputURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "png" }
            for file in files {
                let data = try encode(imageAt: file, format: format, rle: rle)
                let out = outRoot.appendingPathComponent(file.deletingPathExtension().lastPathComponent + ".bin")
                try data.write(to: out)
                count += 1
            }
        } else {
            let data = try encode(imageAt: inputURL, format: format, rle: rle)
            let out = outRoot.appendingPathComponent(inputURL.deletingPathExtension().lastPathComponent + ".bin")
            try data.write(to: out)
            count = 1
        }
        return "done \(count) files\n"
    }

    static func encode(imageAt url: URL, format: Format, rle: Bool) throws -> Data {
        guard let image = UIImage(contentsOfFile: url.path), let cg = image.cgImage else {
            throw EncoderError.cannotDecode(url.lastPathComponent)
        }
        let width = cg.width
        let height = cg.height
        let rgba = try rgbaBytes(cg)
        let effective: Format = format == .i8 ? .argb8888 : format
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * effective.bytesPerPixel)
        let hasAlpha = (0..<(width * height)).contains { rgba[$0 * 4 + 3] != 255 }
        var useFormat = effective
        if effective == .rgb565 && hasAlpha {
            useFormat = .argb8888
        }

        switch useFormat {
        case .rgb565:
            for i in 0..<(width * height) {
                let r = UInt16(rgba[i * 4]) >> 3
                let g = UInt16(rgba[i * 4 + 1]) >> 2
                let b = UInt16(rgba[i * 4 + 2]) >> 3
                let value = (r << 11) | (g << 5) | b
                pixels.append(UInt8(value & 0xFF))
                pixels.append(UInt8(value >> 8))
            }
        case .a8:
            for i in 0..<(width * height) { pixels.append(rgba[i * 4 + 3]) }
        case .argb8888, .i8:
            for i in 0..<(width * height) {
                pixels.append(rgba[i * 4 + 2])
                pixels.append(rgba[i * 4 + 1])
                pixels.append(rgba[i * 4])
                pixels.append(rgba[i * 4 + 3])
            }
        }

        var out = Data()
        out.append(0x19)
        out.append(useFormat.code)
        out.append(contentsOf: le16(rle ? 0x08 : 0))
        out.append(contentsOf: le16(UInt16(width)))
        out.append(contentsOf: le16(UInt16(height)))
        let stride = UInt16(width * useFormat.bytesPerPixel)
        out.append(contentsOf: le16(stride))
        out.append(contentsOf: [0, 0])

        if rle {
            let compressed = rleCompress(pixels, block: useFormat.bytesPerPixel)
            out.append(contentsOf: le32(1))
            out.append(contentsOf: le32(UInt32(compressed.count)))
            out.append(contentsOf: le32(UInt32(pixels.count)))
            out.append(contentsOf: compressed)
        } else {
            out.append(contentsOf: pixels)
        }
        return out
    }

    private static func le16(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
    }

    private static func le32(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ]
    }

    /// Matches LVGLImage.py's `rle_compress`: runs shorter than 16 are folded
    /// into literal runs.
    static func rleCompress(_ data: [UInt8], block: Int) -> [UInt8] {
        guard block > 0, !data.isEmpty else { return [] }
        let count = data.count / block
        var out: [UInt8] = []
        var index = 0
        func equal(_ a: Int, _ b: Int) -> Bool {
            data[(a * block)..<((a + 1) * block)].elementsEqual(data[(b * block)..<((b + 1) * block)])
        }
        while index < count {
            var repeatCount = 1
            while index + repeatCount < count, repeatCount < 127, equal(index, index + repeatCount) {
                repeatCount += 1
            }
            if repeatCount >= 16 {
                out.append(UInt8(repeatCount))
                out.append(contentsOf: data[(index * block)..<((index + 1) * block)])
                index += repeatCount
            } else {
                let start = index
                var literal = 0
                var cursor = index
                while cursor < count, literal < 127 {
                    var nextRepeat = 1
                    while cursor + nextRepeat < count, nextRepeat < 16, equal(cursor, cursor + nextRepeat) {
                        nextRepeat += 1
                    }
                    if nextRepeat >= 16 && cursor != start { break }
                    if nextRepeat >= 16 && cursor == start {
                        // A long run at the start is handled by the repeat branch
                        // next iteration; emit one literal block to make progress.
                        cursor += 1
                        literal += 1
                        break
                    }
                    cursor += 1
                    literal += 1
                }
                if literal == 0 { literal = 1 }
                out.append(0x80 | UInt8(literal))
                out.append(contentsOf: data[(start * block)..<((start + literal) * block)])
                index = start + literal
            }
        }
        return out
    }

    static func rgbaBytes(_ cg: CGImage) throws -> [UInt8] {
        let width = cg.width
        let height = cg.height
        let byteCount = width * height * 4
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
        buffer.initialize(repeating: 0, count: byteCount)
        defer { buffer.deallocate() }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(
            data: buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw EncoderError.cannotDecode("CGContext")
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var bytes = [UInt8](repeating: 0, count: byteCount)
        bytes.withUnsafeMutableBytes { destination in
            destination.copyMemory(from: UnsafeRawBufferPointer(start: buffer, count: byteCount))
        }
        // Un-premultiply to match LVGLImage's straight-alpha output.
        for i in 0..<(width * height) {
            let a = Int(bytes[i * 4 + 3])
            if a > 0 && a < 255 {
                bytes[i * 4] = UInt8(min(255, Int(bytes[i * 4]) * 255 / a))
                bytes[i * 4 + 1] = UInt8(min(255, Int(bytes[i * 4 + 1]) * 255 / a))
                bytes[i * 4 + 2] = UInt8(min(255, Int(bytes[i * 4 + 2]) * 255 / a))
            }
        }
        return bytes
    }
}
