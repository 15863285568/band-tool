import Foundation
import Network
import CryptoKit
import UIKit

/// A tiny loopback HTTP server.  The Xiaomi editor is a web application; this
/// server hosts its bundled assets and emulates the small Electron file-system
/// bridge it expects.  It listens on 127.0.0.1 only and requires a per-launch
/// bearer token.
final class LocalWebServer {
    private(set) var port: UInt16 = 0
    private let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private let queue = DispatchQueue(label: "com.miface.webserver", qos: .userInitiated)
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let resources: URL

    var onReady: ((UInt16) -> Void)?
    var onOpenURL: ((URL) -> Void)?
    /// Called on the main queue.  Completion receives virtual paths.
    var onPickFiles: ((_ multiple: Bool, _ extensions: [String], _ completion: @escaping ([String]) -> Void) -> Void)?

    init() {
        resources = Bundle.main.resourceURL?.appendingPathComponent("WebEditor", isDirectory: true)
            ?? Bundle.main.bundleURL.appendingPathComponent("WebEditor", isDirectory: true)
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener: NWListener
        do {
            listener = try NWListener(using: params, on: .any)
        } catch {
            // Some iOS builds reject a loopback required endpoint with an
            // ephemeral port.  The bearer token still protects the API.
            let fallback = NWParameters.tcp
            fallback.allowLocalEndpointReuse = true
            listener = try NWListener(using: fallback, on: .any)
        }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state, let raw = listener.port?.rawValue {
                DispatchQueue.main.async {
                    self.port = raw
                    self.onReady?(raw)
                }
            }
            if case .failed(let error) = state {
                NSLog("[MiFace] web server failed: \(error)")
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        queue.async {
            self.connections.values.forEach { $0.cancel() }
            self.connections.removeAll()
        }
    }

    func editorURL() -> URL? {
        guard port != 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/index.html#/home")
    }

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        queue.async { self.connections[key] = connection }
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.queue.async {
                    self?.connections.removeValue(forKey: key)
                }
            default: break
            }
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let request = self.parseRequest(buffer) {
                self.handle(request, on: connection)
                return
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.receive(on: connection, buffer: buffer)
        }
    }

    private struct Request {
        var method: String
        var target: String
        var path: String
        var query: [String: String]
        var headers: [String: String]
        var body: Data
    }

    private func parseRequest(_ data: Data) -> Request? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.count >= bodyStart + length else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + length))

        let target = parts[1]
        let components = URLComponents(string: "http://127.0.0.1" + target)
        var query: [String: String] = [:]
        components?.queryItems?.forEach { query[$0.name] = $0.value ?? "" }
        return Request(
            method: parts[0].uppercased(),
            target: target,
            path: components?.path ?? target,
            query: query,
            headers: headers,
            body: body
        )
    }

    private func handle(_ request: Request, on connection: NWConnection) {
        if request.path.hasPrefix("/_api/") {
            handleAPI(request, on: connection)
            return
        }
        if request.path == "/shim.js" {
            let url = resources.appendingPathComponent("EditorShim.js")
            guard var text = try? String(contentsOf: url, encoding: .utf8) else {
                respond(connection, status: 404, type: "text/plain", body: Data("missing shim".utf8))
                return
            }
            text = text.replacingOccurrences(of: "__MIFACE_PORT__", with: String(port))
            text = text.replacingOccurrences(of: "__MIFACE_TOKEN__", with: token)
            respond(connection, status: 200, type: "text/javascript; charset=utf-8", body: Data(text.utf8))
            return
        }

        var path = request.path
        if path == "/" { path = "/index.html" }
        guard let decoded = path.removingPercentEncoding else {
            respond(connection, status: 400, type: "text/plain", body: Data("bad path".utf8))
            return
        }
        let file = resources.appendingPathComponent(decoded.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        let standardized = file.standardizedFileURL
        guard standardized.path.hasPrefix(resources.standardizedFileURL.path),
              FileManager.default.fileExists(atPath: standardized.path),
              (try? standardized.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true,
              let data = try? Data(contentsOf: standardized) else {
            respond(connection, status: 404, type: "text/plain", body: Data("not found".utf8))
            return
        }
        respond(connection, status: 200, type: mimeType(for: standardized.pathExtension), body: data)
    }

    // MARK: - Editor API

    private func handleAPI(_ request: Request, on connection: NWConnection) {
        guard request.headers["x-miface-token"] == token else {
            respondJSON(connection, status: 403, object: ["error": "forbidden"])
            return
        }
        let q = request.query
        func native(_ key: String = "path") -> URL? {
            AppPaths.nativeURL(for: q[key] ?? "")
        }

        switch request.path {
        case "/_api/read":
            guard let url = native(), let data = try? Data(contentsOf: url) else {
                respondJSON(connection, status: 404, object: ["error": "ENOENT"])
                return
            }
            respond(connection, status: 200, type: "application/octet-stream", body: data)
        case "/_api/exists":
            let exists = native().map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            respond(connection, status: 200, type: "text/plain", body: Data((exists ? "1" : "0").utf8))
        case "/_api/readdir":
            guard let url = native(), let items = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
                respondJSON(connection, status: 404, object: ["error": "ENOENT"])
                return
            }
            respondJSON(connection, status: 200, object: items)
        case "/_api/stat":
            guard let url = native(),
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]) else {
                respondJSON(connection, status: 404, object: ["error": "ENOENT"])
                return
            }
            let type = values.isDirectory == true ? "dir" : "file"
            respondJSON(connection, status: 200, object: [
                "type": type,
                "size": values.fileSize ?? 0,
                "mtimeMs": Int((values.contentModificationDate ?? .distantPast).timeIntervalSince1970 * 1000),
            ])
        case "/_api/path":
            let key = q["key"] ?? "userData"
            let mapping: [String: String] = [
                "desktop": "/workspace/Desktop",
                "documents": "/workspace/Documents",
                "userData": "/userData",
                "temp": "/temp",
                "appData": "/userData",
            ]
            let value = mapping[key] ?? ("/" + key)
            if key == "desktop" || key == "documents" {
                if let url = AppPaths.nativeURL(for: value) {
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                }
            }
            respond(connection, status: 200, type: "text/plain", body: Data(value.utf8))
        case "/_api/md5":
            guard let url = native(), let data = try? Data(contentsOf: url) else {
                respondJSON(connection, status: 404, object: ["error": "ENOENT"])
                return
            }
            let digest = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
            respond(connection, status: 200, type: "text/plain", body: Data(digest.utf8))
        case "/_api/write":
            guard let url = native() else {
                respondJSON(connection, status: 400, object: ["error": "bad path"])
                return
            }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try request.body.write(to: url, options: .atomic)
                notifyIfFace(url)
                respond(connection, status: 200, type: "text/plain", body: Data("1".utf8))
            } catch {
                respondJSON(connection, status: 500, object: ["error": error.localizedDescription])
            }
        case "/_api/mkdir", "/_api/rm", "/_api/copy", "/_api/cp", "/_api/rename", "/_api/download":
            handleJSONMutation(request, on: connection)
        case "/_api/exec":
            guard let object = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any],
                  let filename = object["filename"] as? String else {
                respondJSON(connection, status: 400, object: ["error": "bad exec request"])
                return
            }
            let args = object["args"] as? [String] ?? []
            do {
                let result = try ToolShim.run(executable: filename, arguments: args)
                respondJSON(connection, status: 200, object: ["stdout": result.stdout, "stderr": result.stderr])
            } catch {
                respondJSON(connection, status: 200, object: ["error": error.localizedDescription])
            }
        case "/_api/pick":
            guard let onPickFiles else {
                respondJSON(connection, status: 200, object: [String]())
                return
            }
            let multiple = (q["multiple"] ?? "0") == "1"
            let extensions = (q["extensions"] ?? "").split(separator: ",").map(String.init)
            DispatchQueue.main.async {
                onPickFiles(multiple, extensions) { paths in
                    self.respondJSON(connection, status: 200, object: paths)
                }
            }
        default:
            respondJSON(connection, status: 404, object: ["error": "unknown api"])
        }
    }

    private func handleJSONMutation(_ request: Request, on connection: NWConnection) {
        guard let object = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] else {
            respondJSON(connection, status: 400, object: ["error": "bad json"])
            return
        }
        let fm = FileManager.default
        do {
            switch request.path {
            case "/_api/mkdir":
                if let url = AppPaths.nativeURL(for: object["path"] as? String ?? "") {
                    try fm.createDirectory(at: url, withIntermediateDirectories: true)
                }
            case "/_api/rm":
                if let url = AppPaths.nativeURL(for: object["path"] as? String ?? "") {
                    try? fm.removeItem(at: url)
                }
            case "/_api/copy":
                guard let from = AppPaths.nativeURL(for: object["from"] as? String ?? ""),
                      let to = AppPaths.nativeURL(for: object["to"] as? String ?? "") else { break }
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
                try fm.copyItem(at: from, to: to)
            case "/_api/cp":
                guard let from = AppPaths.nativeURL(for: object["from"] as? String ?? ""),
                      let to = AppPaths.nativeURL(for: object["to"] as? String ?? "") else { break }
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
                try fm.copyItem(at: from, to: to)
            case "/_api/rename":
                guard let from = AppPaths.nativeURL(for: object["from"] as? String ?? ""),
                      let to = AppPaths.nativeURL(for: object["to"] as? String ?? "") else { break }
                try fm.moveItem(at: from, to: to)
            case "/_api/download":
                let name = (object["name"] as? String ?? "watchface.bin").components(separatedBy: "/").last ?? "watchface.bin"
                let data = Data(base64Encoded: object["data"] as? String ?? "") ?? Data()
                let url = AppPaths.exports.appendingPathComponent(name)
                try fm.createDirectory(at: AppPaths.exports, withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                notifyIfFace(url)
            default: break
            }
            respond(connection, status: 200, type: "text/plain", body: Data("1".utf8))
        } catch {
            respondJSON(connection, status: 500, object: ["error": error.localizedDescription])
        }
    }

    private func notifyIfFace(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ["face", "bin", "mwz"].contains(ext) else { return }
        let path = url.path
        guard path.contains("/WatchFace/") || path.contains("/Exports/") else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .miFaceDidWriteFile, object: url)
        }
    }

    private func respondJSON(_ connection: NWConnection, status: Int, object: Any) {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        respond(connection, status: status, type: "application/json", body: data)
    }

    private func respond(_ connection: NWConnection, status: Int, type: String, body: Data) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        default: reason = "Internal Server Error"
        }
        var header = "HTTP/1.1 \(status) \(reason)\r\n"
        header += "Content-Type: \(type)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Cache-Control: no-store\r\n"
        header += "Connection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json"
        case "wasm": return "application/wasm"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "woff2": return "font/woff2"
        case "ico": return "image/x-icon"
        default: return "application/octet-stream"
        }
    }
}
