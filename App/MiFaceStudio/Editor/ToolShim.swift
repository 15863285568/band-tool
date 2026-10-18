import Foundation

/// Replacement for the desktop helper executables the editor downloads.
/// Only the tools needed by the normal (non-professional) editor are
/// implemented; everything else fails with a readable message.
enum ToolShim {
    struct Result {
        var stdout: String = ""
        var stderr: String = ""
    }

    static func run(executable: String, arguments: [String]) throws -> Result {
        let tool = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        if tool.contains("lvglimage") {
            return Result(stdout: try LVGLImageEncoder.run(arguments: arguments))
        }
        if tool.contains("imgutils") {
            // imgutils compress <input> <output> -f true-color-alpha
            // Our ARGB encoder already keeps the alpha channel, so a copy is
            // sufficient for the editor's format-decision pass.
            if arguments.count >= 3, arguments[0] == "compress" {
                try copy(from: arguments[1], to: arguments[2])
            }
            return Result()
        }
        if tool.contains("pngquant") {
            guard let input = arguments.last else { return Result() }
            var output = input
            if let index = arguments.firstIndex(of: "--output"), index + 1 < arguments.count {
                output = arguments[index + 1]
            }
            try copy(from: input, to: output)
            return Result()
        }
        if tool.contains("dssim") {
            // A large distance makes the editor prefer true-color formats,
            // which are exactly the formats our encoder implements losslessly.
            return Result(stdout: "1.000000\t0\n")
        }
        if tool.contains("ffmpeg") {
            throw ShimError.unsupported("视频表盘需要 ffmpeg，当前版本暂不支持。请使用静态图制作表盘。")
        }
        if tool.contains("ezip") {
            throw ShimError.unsupported("该表盘使用了 EZIP 压缩，当前设备不支持。请在导出时选择普通压缩。")
        }
        if tool.contains("clip-font") || tool.contains("fontclip") {
            throw ShimError.unsupported("字体裁剪工具仅专业版需要，当前版本不支持该字体图层。")
        }
        throw ShimError.unsupported("不支持的辅助工具：\(tool)")
    }

    private static func copy(from virtualInput: String, to virtualOutput: String) throws {
        let fm = FileManager.default
        let input = AppPaths.nativeURL(for: virtualInput) ?? URL(fileURLWithPath: virtualInput)
        let output = AppPaths.nativeURL(for: virtualOutput) ?? URL(fileURLWithPath: virtualOutput)
        try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: output.path) { try fm.removeItem(at: output) }
        try fm.copyItem(at: input, to: output)
    }

    enum ShimError: LocalizedError {
        case unsupported(String)
        var errorDescription: String? {
            switch self { case .unsupported(let text): return text }
        }
    }
}
