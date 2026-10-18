import Foundation

/// All filesystem locations used by the embedded editor.
///
/// The JavaScript editor expects a small POSIX-like tree.  We map virtual
/// paths (`/userData`, `/temp`, `/workspace`, `/app`) onto sandbox folders so
/// the unmodified editor code can keep using Node-style paths.
enum AppPaths {
    static let fileManager = FileManager.default

    static var supportRoot: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MiFaceStudio", isDirectory: true)
    }

    static var workspace: URL { supportRoot.appendingPathComponent("Workspace", isDirectory: true) }
    static var userData: URL { supportRoot.appendingPathComponent("UserData", isDirectory: true) }
    static var temp: URL { supportRoot.appendingPathComponent("Temp", isDirectory: true) }
    static var desktop: URL { workspace.appendingPathComponent("Desktop", isDirectory: true) }
    static var watchFaceDir: URL { desktop.appendingPathComponent("WatchFace", isDirectory: true) }
    static var watchfaces: URL { userData.appendingPathComponent("Watchfaces", isDirectory: true) }
    static var samples: URL { userData.appendingPathComponent("Samples", isDirectory: true) }
    static var widgets: URL { userData.appendingPathComponent("Widgets", isDirectory: true) }
    static var imports: URL { workspace.appendingPathComponent("Imports", isDirectory: true) }
    static var exports: URL { workspace.appendingPathComponent("Exports", isDirectory: true) }

    static func bootstrap() {
        for url in [
            supportRoot, workspace, userData, temp, desktop, watchFaceDir,
            watchfaces, samples, widgets, imports, exports
        ] {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var t = temp
        try? t.setResourceValues(values)
    }

    /// Map a virtual editor path to a real URL, refusing escapes.
    static func nativeURL(for virtualPath: String) -> URL? {
        let path = virtualPath.replacingOccurrences(of: "\\", with: "/")
        let mappings: [(String, URL)] = [
            ("/workspace", workspace),
            ("/userData", userData),
            ("/temp", temp),
            ("/app", Bundle.main.resourceURL ?? workspace),
            ("/desktop", desktop),
        ]
        for (prefix, root) in mappings {
            if path == prefix || path.hasPrefix(prefix + "/") {
                let relative = String(path.dropFirst(prefix.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let url = relative.isEmpty
                    ? root
                    : root.appendingPathComponent(relative)
                return url.standardizedFileURL
            }
        }
        if path.hasPrefix("/") {
            return workspace.appendingPathComponent(path.dropFirst())
        }
        return workspace.appendingPathComponent(path)
    }

    /// Inverse mapping, used when handing paths back to JavaScript.
    static func virtualPath(for url: URL) -> String {
        let target = url.standardizedFileURL.path
        let mappings: [(String, URL)] = [
            ("/userData", userData),
            ("/workspace", workspace),
            ("/temp", temp),
            ("/app", Bundle.main.resourceURL ?? workspace),
        ]
        for (prefix, root) in mappings {
            let base = root.standardizedFileURL.path
            if target == base { return prefix }
            if target.hasPrefix(base + "/") {
                return prefix + String(target.dropFirst(base.count))
            }
        }
        return target
    }
}
