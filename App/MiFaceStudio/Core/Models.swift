import Foundation

struct FaceProject: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let device: String
    let size: String
    let modified: Date
    let preview: URL?

    var virtualPath: String { AppPaths.virtualPath(for: url) }

    var subtitle: String {
        [device, size].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct FaceArtifact: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let device: String
    let bytes: Int
    let modified: Date
    let watchfaceID: String?

    var subtitle: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        return [device.isEmpty ? nil : device, size].compactMap { $0 }.joined(separator: " · ")
    }
}

struct DeviceIdentity: Identifiable, Hashable, Codable {
    var id: String { peripheralID }
    let peripheralID: String
    var name: String
    var authKey: String
    var lastConnected: Date?
    var model: String
    var firmware: String

    var hasKey: Bool { authKey.count == 32 && authKey.allSatisfy(\.isHexDigit) }
}

enum InstallPhase: Equatable {
    case idle
    case connecting
    case handshake
    case authenticating
    case preparing
    case uploading(Double)
    case waitingForDevice
    case done
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "未连接"
        case .connecting: return "正在连接"
        case .handshake: return "正在建立链路"
        case .authenticating: return "正在认证"
        case .preparing: return "正在校验表盘"
        case .uploading(let p): return "正在传输 \(Int(p * 100))%"
        case .waitingForDevice: return "设备正在安装"
        case .done: return "安装完成"
        case .failed(let message): return message
        }
    }

    var isBusy: Bool {
        switch self {
        case .connecting, .handshake, .authenticating, .preparing, .uploading(_), .waitingForDevice:
            return true
        default:
            return false
        }
    }
}
