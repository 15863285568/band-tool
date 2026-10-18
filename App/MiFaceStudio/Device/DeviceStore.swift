import Foundation
import Security

@MainActor
final class DeviceStore: ObservableObject {
    @Published private(set) var devices: [String: DeviceIdentity] = [:]

    private let defaultsKey = "miface.devices.v1"
    private let service = "com.miface.studio.authkey"

    init() {
        load()
    }

    func identity(for peripheralID: String, name: String = "") -> DeviceIdentity {
        if var existing = devices[peripheralID] {
            if !name.isEmpty { existing.name = name }
            existing.authKey = readKey(peripheralID) ?? existing.authKey
            return existing
        }
        return DeviceIdentity(
            peripheralID: peripheralID,
            name: name,
            authKey: readKey(peripheralID) ?? "",
            lastConnected: nil,
            model: "",
            firmware: ""
        )
    }

    func upsert(_ identity: DeviceIdentity) {
        var value = identity
        if !identity.authKey.isEmpty {
            writeKey(identity.authKey, for: identity.peripheralID)
        }
        value.authKey = ""
        devices[identity.peripheralID] = value
        save()
    }

    func setAuthKey(_ key: String, for peripheralID: String) throws {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        guard normalized.count == 32, normalized.allSatisfy(\.isHexDigit) else {
            throw KeyError.invalid
        }
        writeKey(normalized, for: peripheralID)
        if var identity = devices[peripheralID] {
            identity.authKey = ""
            devices[peripheralID] = identity
            save()
        }
        objectWillChange.send()
    }

    func authKey(for peripheralID: String) -> String {
        readKey(peripheralID) ?? ""
    }

    func remove(_ peripheralID: String) {
        devices.removeValue(forKey: peripheralID)
        deleteKey(peripheralID)
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: DeviceIdentity].self, from: data) else {
            return
        }
        devices = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func writeKey(_ key: String, for account: String) {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private func readKey(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKey(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeyError: LocalizedError {
        case invalid
        var errorDescription: String? { "AuthKey 必须是 32 位十六进制字符" }
    }
}
