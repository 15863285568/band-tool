import Foundation
import UIKit

@MainActor
final class FaceLibrary: ObservableObject {
    @Published private(set) var projects: [FaceProject] = []
    @Published private(set) var artifacts: [FaceArtifact] = []
    @Published var lastError: String?

    private let fm = FileManager.default

    init() {
        NotificationCenter.default.addObserver(
            forName: .miFaceDidWriteFile,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        AppPaths.bootstrap()
        projects = scanProjects()
        artifacts = scanArtifacts()
    }

    private func scanProjects() -> [FaceProject] {
        guard let children = try? fm.contentsOfDirectory(
            at: AppPaths.watchfaces,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return children.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let config = url.appendingPathComponent("editor.config.json")
            let description = url.appendingPathComponent("description.xml")
            guard fm.fileExists(atPath: config.path) || fm.fileExists(atPath: description.path) else { return nil }

            let meta = readDescription(at: description)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let preview = ["preview/preview.png", "preview/market-preview.png", "preview/style_1_static.png"]
                .map { url.appendingPathComponent($0) }
                .first { fm.fileExists(atPath: $0.path) }
            return FaceProject(
                id: url.path,
                url: url,
                name: meta.name.isEmpty ? url.lastPathComponent : meta.name,
                device: meta.device,
                size: meta.size,
                modified: modified,
                preview: preview
            )
        }
        .sorted { $0.modified > $1.modified }
    }

    private func scanArtifacts() -> [FaceArtifact] {
        var result: [FaceArtifact] = []
        for directory in [AppPaths.watchFaceDir, AppPaths.exports, AppPaths.desktop] {
            guard let children = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in children {
                let ext = url.pathExtension.lowercased()
                guard ["face", "bin", "mwz"].contains(ext) else { continue }
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let full = try? Data(contentsOf: url, options: .mappedIfSafe)
                let head = full.map { Data($0.prefix(512 * 1024)) } ?? Data()
                let meta = FacePackage.metadata(for: head)
                result.append(FaceArtifact(
                    id: url.path,
                    url: url,
                    name: meta.name.isEmpty ? url.deletingPathExtension().lastPathComponent : meta.name,
                    device: meta.deviceType,
                    bytes: values?.fileSize ?? 0,
                    modified: values?.contentModificationDate ?? .distantPast,
                    watchfaceID: meta.identifier
                ))
            }
        }
        return result.sorted { $0.modified > $1.modified }
    }

    private func readDescription(at url: URL) -> (name: String, device: String, size: String) {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return ("", "", "")
        }
        func value(_ tag: String) -> String {
            guard let start = text.range(of: "<\(tag)>"),
                  let end = text.range(of: "</\(tag)>", range: start.upperBound..<text.endIndex) else { return "" }
            return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (value("name"), value("deviceType"), value("size"))
    }

    func delete(project: FaceProject) throws {
        try fm.removeItem(at: project.url)
        refresh()
    }

    func delete(artifact: FaceArtifact) throws {
        try fm.removeItem(at: artifact.url)
        refresh()
    }

    func importFiles(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let target = AppPaths.watchFaceDir.appendingPathComponent(url.lastPathComponent)
            do {
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.copyItem(at: url, to: target)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                lastError = "导入失败：\(error.localizedDescription)"
            }
        }
        refresh()
    }
}

extension Notification.Name {
    static let miFaceDidWriteFile = Notification.Name("MiFaceDidWriteFile")
}
