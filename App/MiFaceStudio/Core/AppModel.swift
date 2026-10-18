import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var route: String = "/home"
    @Published var editorURL: URL?
    @Published var serverReady = false
    @Published var toast: String?
    @Published var showingImporter = false

    let server = LocalWebServer()
    let library = FaceLibrary()
    let devices = DeviceStore()
    lazy var bluetooth = XiaomiBluetoothManager(store: devices)

    private var picker: DocumentPickerCoordinator?
    private var toastWorkItem: DispatchWorkItem?
    private var starting = false

    init() {
        AppPaths.bootstrap()
    }

    func start() {
        guard editorURL == nil, !starting else { return }
        starting = true
        server.onReady = { [weak self] port in
            DispatchQueue.main.async {
                guard let self else { return }
                self.serverReady = true
                self.starting = false
                self.editorURL = URL(string: "http://127.0.0.1:\(port)/index.html#/home")
                self.library.refresh()
            }
        }
        server.onOpenURL = { url in
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }
        server.onPickFiles = { [weak self] multiple, extensions, completion in
            DispatchQueue.main.async {
                self?.presentPicker(multiple: multiple, extensions: extensions, completion: completion)
            }
        }
        do {
            try server.start()
        } catch {
            starting = false
            toast = "编辑器启动失败：\(error.localizedDescription)"
        }
    }

    func stop() {
        server.stop()
    }

    func restartServer() {
        server.stop()
        editorURL = nil
        serverReady = false
        starting = false
        start()
    }

    func openProject(_ project: FaceProject) {
        let encoded = project.virtualPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? project.virtualPath
        route = "/editor?path=\(encoded)"
    }

    func editArtifact(_ artifact: FaceArtifact) {
        route = "/editor?path=\(artifact.url.deletingLastPathComponent().path)"
    }

    func goHome() {
        route = "/home"
    }

    func showToast(_ text: String) {
        toast = text
        toastWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: item)
    }

    func handleEditorEvent(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "export":
            library.refresh()
            showToast("表盘已导出到「表盘库」")
        case "toast":
            if let text = event["text"] as? String { showToast(text) }
        case "openURL":
            if let raw = event["url"] as? String, let url = URL(string: raw) {
                UIApplication.shared.open(url)
            }
        default:
            break
        }
    }

    private func presentPicker(multiple: Bool, extensions: [String], completion: @escaping ([String]) -> Void) {
        let types: [UTType] = extensions.compactMap { UTType(filenameExtension: $0) }
        let controller = UIDocumentPickerViewController(
            forOpeningContentTypes: types.isEmpty ? [.data] : types,
            asCopy: true
        )
        controller.allowsMultipleSelection = multiple
        let coordinator = DocumentPickerCoordinator { [weak self] urls in
            guard let self else { completion([]); return }
            var paths: [String] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let target = AppPaths.imports.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.createDirectory(at: AppPaths.imports, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: target)
                do {
                    try FileManager.default.copyItem(at: url, to: target)
                    paths.append(AppPaths.virtualPath(for: target))
                } catch {
                    self.showToast("导入失败：\(error.localizedDescription)")
                }
            }
            completion(paths)
            self.picker = nil
        }
        picker = coordinator
        controller.delegate = coordinator
        topViewController()?.present(controller, animated: true)
    }

    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}

final class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
    private let completion: ([URL]) -> Void

    init(completion: @escaping ([URL]) -> Void) {
        self.completion = completion
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion([])
    }
}
