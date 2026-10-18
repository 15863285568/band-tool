import Foundation

/// A deliberately tiny protobuf reader/writer.  The Xiaomi protocol uses only
/// varints, length-delimited fields and a handful of enums, so pulling in a
/// full protobuf runtime would add size and build complexity for no benefit.
struct ProtoWriter {
    private(set) var data = Data()

    mutating func varint(_ field: Int, _ value: UInt64) {
        appendTag(field, wire: 0)
        appendVarint(value)
    }

    mutating func bool(_ field: Int, _ value: Bool) {
        varint(field, value ? 1 : 0)
    }

    mutating func bytes(_ field: Int, _ value: Data) {
        appendTag(field, wire: 2)
        appendVarint(UInt64(value.count))
        data.append(value)
    }

    mutating func string(_ field: Int, _ value: String) {
        bytes(field, Data(value.utf8))
    }

    private mutating func appendTag(_ field: Int, wire: UInt64) {
        appendVarint((UInt64(field) << 3) | wire)
    }

    private mutating func appendVarint(_ value: UInt64) {
        var value = value
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            data.append(byte)
        } while value != 0
    }
}

struct ProtoFields {
    var varints: [Int: UInt64] = [:]
    var bytes: [Int: Data] = [:]

    init(_ data: Data) {
        var index = data.startIndex
        while index < data.endIndex {
            guard let tag = Self.readVarint(data, &index) else { break }
            let field = Int(tag >> 3)
            let wire = Int(tag & 0x07)
            switch wire {
            case 0:
                guard let value = Self.readVarint(data, &index) else { return }
                varints[field] = value
            case 2:
                guard let length = Self.readVarint(data, &index) else { return }
                let end = index + Int(length)
                guard end <= data.endIndex else { return }
                bytes[field] = data.subdata(in: index..<end)
                index = end
            case 1:
                guard index + 8 <= data.endIndex else { return }
                index += 8
            case 5:
                guard index + 4 <= data.endIndex else { return }
                index += 4
            default:
                return
            }
        }
    }

    private static func readVarint(_ data: Data, _ index: inout Data.Index) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < data.endIndex {
            let byte = data[index]
            index = data.index(after: index)
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }
}

enum XiaomiPacket {
    enum PacketType: Int {
        case account = 1
        case system = 2
        case watchFace = 4
        case mass = 22
    }

    struct Incoming {
        var type: Int
        var id: Int
        var payload: Data?
        var payloadField: Int?
    }

    static func parse(_ data: Data) -> Incoming? {
        let fields = ProtoFields(data)
        guard let type = fields.varints[1], let id = fields.varints[2] else { return nil }
        let known: [Int] = [3, 4, 6, 24]
        for field in known {
            if let payload = fields.bytes[field] {
                return Incoming(type: Int(type), id: Int(id), payload: payload, payloadField: field)
            }
        }
        return Incoming(type: Int(type), id: Int(id), payload: nil, payloadField: nil)
    }

    static func wrapAccount(_ payload: Data, id: Int) -> Data {
        var packet = ProtoWriter()
        packet.varint(1, UInt64(PacketType.account.rawValue))
        packet.varint(2, UInt64(id))
        packet.bytes(3, payload)
        return packet.data
    }

    static func wrapWatchFace(_ payload: Data, id: Int) -> Data {
        var packet = ProtoWriter()
        packet.varint(1, UInt64(PacketType.watchFace.rawValue))
        packet.varint(2, UInt64(id))
        packet.bytes(6, payload)
        return packet.data
    }

    static func wrapMass(_ payload: Data, id: Int = 0) -> Data {
        var packet = ProtoWriter()
        packet.varint(1, UInt64(PacketType.mass.rawValue))
        packet.varint(2, UInt64(id))
        packet.bytes(24, payload)
        return packet.data
    }

    static func authAppVerify(random: Data) -> Data {
        var verify = ProtoWriter()
        verify.bytes(1, random)
        var account = ProtoWriter()
        account.bytes(30, verify.data)
        return wrapAccount(account.data, id: 26) // AUTH_VERIFY
    }

    static func authAppConfirm(sign: Data, encryptedDevice: Data) -> Data {
        var confirm = ProtoWriter()
        confirm.bytes(1, sign)
        confirm.bytes(2, encryptedDevice)
        var account = ProtoWriter()
        account.bytes(32, confirm.data)
        return wrapAccount(account.data, id: 27) // AUTH_CONFIRM
    }

    static func watchFacePrepare(id: String, size: Int) -> Data {
        var info = ProtoWriter()
        info.string(1, id)
        info.varint(2, UInt64(size))
        info.varint(3, 65536)
        var face = ProtoWriter()
        face.bytes(6, info.data)
        return wrapWatchFace(face.data, id: 4) // PREPARE_INSTALL_WATCH_FACE
    }

    static func watchFaceSetCurrent(id: String) -> Data {
        var face = ProtoWriter()
        face.string(2, id)
        return wrapWatchFace(face.data, id: 1) // SET_WATCH_FACE
    }

    static func massPrepare(dataType: UInt8, md5: Data, length: Int) -> Data {
        var request = ProtoWriter()
        request.varint(1, UInt64(dataType))
        request.bytes(2, md5)
        request.varint(3, UInt64(length))
        var mass = ProtoWriter()
        mass.bytes(1, request.data)
        return wrapMass(mass.data)
    }

    // MARK: - Auth parsing

    static func authDeviceVerify(from account: Data) -> (random: Data, sign: Data)? {
        let fields = ProtoFields(account)
        guard let verify = fields.bytes[31] else { return nil }
        let inner = ProtoFields(verify)
        guard let random = inner.bytes[1], let sign = inner.bytes[2] else { return nil }
        return (random, sign)
    }

    static func authDeviceConfirm(from account: Data) -> Bool? {
        let fields = ProtoFields(account)
        guard let confirm = fields.bytes[33] else { return nil }
        return ProtoFields(confirm).varints[1].map { $0 != 0 }
    }

    // MARK: - Watch face parsing

    static func watchFaceStatus(from data: Data) -> Int? {
        let fields = ProtoFields(data)
        if let value = fields.varints[5] { return Int(value) }
        if let reply = fields.bytes[9] {
            let inner = ProtoFields(reply)
            if let value = inner.varints[2] { return Int(value) }
        }
        return nil
    }

    static func watchFaceInstallResult(from data: Data) -> (id: String, code: Int)? {
        let fields = ProtoFields(data)
        guard let result = fields.bytes[7] else { return nil }
        let inner = ProtoFields(result)
        let id = inner.bytes[1].map { String(decoding: $0, as: UTF8.self) } ?? ""
        return (id, Int(inner.varints[2] ?? 0))
    }

    static func massPrepareResponse(from data: Data) -> (status: Int, sliceLength: Int, remained: Int)? {
        let fields = ProtoFields(data)
        guard let response = fields.bytes[2] else { return nil }
        let inner = ProtoFields(response)
        return (
            Int(inner.varints[2] ?? 0),
            Int(inner.varints[5] ?? 0),
            Int(inner.varints[4] ?? 0)
        )
    }
}

