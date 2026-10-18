import Foundation

enum L1Type: UInt8 {
    case nak = 0
    case ack = 1
    case cmd = 2
    case data = 3
}

struct L1Packet {
    static let magic: UInt16 = 0xA5A5

    var type: L1Type
    var frx: Bool
    var seq: UInt8
    var payload: Data

    init(type: L1Type, frx: Bool = false, seq: UInt8, payload: Data) {
        self.type = type
        self.frx = frx
        self.seq = seq
        self.payload = payload
    }

    var bytes: Data {
        var data = Data()
        data.append(UInt8(Self.magic & 0xFF))
        data.append(UInt8(Self.magic >> 8))
        data.append(type.rawValue | (frx ? 0x10 : 0))
        data.append(seq)
        let length = UInt16(payload.count)
        data.append(UInt8(length & 0xFF))
        data.append(UInt8(length >> 8))
        let crc = Self.crc16(payload)
        data.append(UInt8(crc & 0xFF))
        data.append(UInt8(crc >> 8))
        data.append(payload)
        return data
    }

    init?(data: Data) {
        guard data.count >= 8 else { return nil }
        let bytes = [UInt8](data)
        guard UInt16(bytes[0]) | (UInt16(bytes[1]) << 8) == Self.magic else { return nil }
        guard let type = L1Type(rawValue: bytes[2] & 0x0F) else { return nil }
        self.type = type
        self.frx = (bytes[2] & 0x10) != 0
        self.seq = bytes[3]
        let length = Int(UInt16(bytes[4]) | (UInt16(bytes[5]) << 8))
        guard bytes.count >= 8 + length else { return nil }
        let declared = UInt16(bytes[6]) | (UInt16(bytes[7]) << 8)
        let payload = Data(bytes[8..<(8 + length)])
        guard Self.crc16(payload) == declared else { return nil }
        self.payload = payload
    }

    static func crc16(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0
        for byte in data {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xA001
                } else {
                    crc >>= 1
                }
            }
        }
        return crc
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    static func le32(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ])
    }

    static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }
}

enum L2Channel: UInt8 {
    case pb = 1
    case mass = 2
    case ota = 6
    case canopus = 0x43
}

enum L2OpCode: UInt8 {
    case write = 1
    case writeEnc = 2
    case read = 3
}

enum L1Command: UInt8 {
    case startReq = 1
    case startRsp = 2
    case stopReq = 3
    case stopRsp = 4
}

struct L1CommandPacket {
    var command: L1Command
    var config: [UInt8: Data]

    var payload: Data {
        var data = Data([command.rawValue])
        for key in config.keys.sorted() {
            guard let value = config[key] else { continue }
            data.append(key)
            let length = UInt16(value.count)
            data.append(UInt8(length & 0xFF))
            data.append(UInt8(length >> 8))
            data.append(value)
        }
        return data
    }

    init(command: L1Command, config: [UInt8: Data] = [:]) {
        self.command = command
        self.config = config
    }

    init?(payload: Data) {
        guard let first = payload.first, let command = L1Command(rawValue: first) else { return nil }
        self.command = command
        var config: [UInt8: Data] = [:]
        var index = 1
        let bytes = [UInt8](payload)
        while index + 3 <= bytes.count {
            let key = bytes[index]
            let length = Int(UInt16(bytes[index + 1]) | (UInt16(bytes[index + 2]) << 8))
            index += 3
            guard index + length <= bytes.count else { break }
            config[key] = Data(bytes[index..<(index + length)])
            index += length
        }
        self.config = config
    }

    var txWindow: UInt8? {
        guard let value = config[3], value.count == 2 else { return nil }
        return UInt8(clamping: Int(UInt16(value[0]) | (UInt16(value[1]) << 8)))
    }

    var sendTimeout: UInt16? {
        guard let value = config[4], value.count == 2 else { return nil }
        return UInt16(value[0]) | (UInt16(value[1]) << 8)
    }
}

@MainActor
protocol SarTransport: AnyObject {
    func sendFrames(_ frames: [Data])
}

@MainActor
final class SarController {
    weak var transport: SarTransport?
    var onHandshake: (() -> Void)?
    var onPayload: ((_ channel: UInt8, _ opcode: UInt8, _ payload: Data) -> Void)?
    var onFailure: ((String) -> Void)?

    private(set) var handshakeDone = false
    private let window: UInt8 = 4
    private let sendTimeout: TimeInterval = 6.0
    private var nextSeq: UInt8 = 0
    private var pending: [(seq: UInt8, payload: Data)] = []
    private var inFlight: [OutItem] = []
    private var acked: Set<UInt8> = []
    private var rxExpected: UInt8 = 0
    private var rxSeen = false
    private var startDeadline: Date?
    private var startResends = 0
    private var timer: Timer?
    private var epoch = 0
    private var lastProgress = Date()
    private var failureReported = false

    private struct OutItem {
        var seq: UInt8
        var frame: Data
        var deadline: Date
        var retries: Int
        var acked: Bool
        var part: Int
    }

    var onProgress: ((Int, Int) -> Void)?
    private var totalParts = 0
    private var ackedParts = 0

    var pendingCount: Int { pending.count }
    var inFlightCount: Int { inFlight.count }

    func start() {
        resetSession()
        sendStartRequest()
        startTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pending.removeAll()
        inFlight.removeAll()
    }

    func enqueue(_ payload: Data) -> UInt8 {
        let seq = nextSeq
        nextSeq = nextSeq &+ 1
        pending.append((seq: seq, payload: payload))
        pump()
        return seq
    }

    func enqueueBatch(_ payloads: [Data]) -> [UInt8] {
        var seqs: [UInt8] = []
        for payload in payloads {
            let seq = nextSeq
            nextSeq = nextSeq &+ 1
            seqs.append(seq)
            pending.append((seq: seq, payload: payload))
        }
        pump()
        return seqs
    }

    func waitUntilDrained() async {
        while !pending.isEmpty || !inFlight.isEmpty {
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
    }

    func beginPartTracking(_ total: Int) {
        totalParts = total
        ackedParts = 0
    }

    private func resetSession() {
        pending.removeAll()
        inFlight.removeAll()
        acked.removeAll()
        nextSeq = 0
        rxExpected = 0
        rxSeen = false
        handshakeDone = false
        startDeadline = nil
        startResends = 0
        failureReported = false
        lastProgress = Date()
        epoch &+= 1
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func sendStartRequest() {
        var config: [UInt8: Data] = [:]
        config[1] = Data([1, 0, 0])
        config[2] = L1Packet.le16(64512)
        config[3] = L1Packet.le16(UInt16(window))
        config[4] = L1Packet.le16(UInt16(sendTimeout * 1000))
        let command = L1CommandPacket(command: .startReq, config: config)
        transport?.sendFrames([L1Packet(type: .cmd, seq: 0, payload: command.payload).bytes])
        startDeadline = Date().addingTimeInterval(sendTimeout)
    }

    private func tick() {
        guard !failureReported else { return }
        let now = Date()
        if !handshakeDone, let deadline = startDeadline, now >= deadline {
            if startResends < 3 {
                startResends += 1
                sendStartRequest()
            }
        }
        guard handshakeDone else { return }

        if let first = inFlight.first, now >= first.deadline {
            if first.retries >= 3 {
                fail("设备长时间没有确认数据，请重新连接")
                return
            }
            for index in inFlight.indices {
                inFlight[index].deadline = now.addingTimeInterval(sendTimeout)
                inFlight[index].retries += 1
            }
            let frames = inFlight.map(\.frame)
            transport?.sendFrames(frames)
        }
    }

    func receive(_ packet: L1Packet) {
        switch packet.type {
        case .ack:
            handleAck(packet.seq)
        case .nak:
            handleNak(packet.seq)
        case .cmd:
            guard let command = L1CommandPacket(payload: packet.payload) else { return }
            handleCommand(command)
        case .data:
            handleData(packet)
        }
    }

    private func handleCommand(_ command: L1CommandPacket) {
        switch command.command {
        case .startRsp:
            guard !handshakeDone else { return }
            handshakeDone = true
            startDeadline = nil
            if let win = command.txWindow { _ = win }
            onHandshake?()
            pump()
        case .startReq:
            var config: [UInt8: Data] = [:]
            config[1] = Data([1, 0, 0])
            config[2] = L1Packet.le16(64512)
            config[3] = L1Packet.le16(UInt16(window))
            config[4] = L1Packet.le16(UInt16(sendTimeout * 1000))
            let rsp = L1CommandPacket(command: .startRsp, config: config)
            transport?.sendFrames([L1Packet(type: .cmd, seq: 0, payload: rsp.payload).bytes])
            handshakeDone = true
            onHandshake?()
        default:
            break
        }
    }

    private func handleData(_ packet: L1Packet) {
        guard handshakeDone else { return }
        if packet.frx {
            deliver(packet.payload)
            return
        }
        if packet.seq != rxExpected {
            let ahead = packet.seq &- rxExpected < 128
            if ahead {
                sendNak(rxExpected)
            } else if rxSeen {
                sendAck(rxExpected &- 1)
            }
            return
        }
        sendAck(packet.seq)
        rxExpected = rxExpected &+ 1
        rxSeen = true
        deliver(packet.payload)
    }

    private func deliver(_ payload: Data) {
        guard payload.count >= 2 else { return }
        let channel = payload[0]
        let opcode = payload[1]
        let body = payload.dropFirst(2)
        onPayload?(channel, opcode, Data(body))
    }

    private func sendAck(_ seq: UInt8) {
        transport?.sendFrames([L1Packet(type: .ack, seq: seq, payload: Data()).bytes])
    }

    private func sendNak(_ seq: UInt8) {
        transport?.sendFrames([L1Packet(type: .nak, seq: seq, payload: Data()).bytes])
    }

    private func handleAck(_ seq: UInt8) {
        var removed = 0
        while let first = inFlight.first, seqLE(first.seq, seq) {
            acked.insert(first.seq)
            inFlight.removeFirst()
            removed += 1
            ackedParts += 1
        }
        if removed > 0 {
            lastProgress = Date()
            onProgress?(ackedParts, max(totalParts, ackedParts))
            pump()
        }
    }

    private func handleNak(_ seq: UInt8) {
        while let first = inFlight.first, seqLE(first.seq, seq &- 1) {
            acked.insert(first.seq)
            inFlight.removeFirst()
            ackedParts += 1
        }
        let now = Date()
        for index in inFlight.indices where seqLE(seq, inFlight[index].seq) {
            inFlight[index].deadline = now.addingTimeInterval(sendTimeout)
        }
        let frames = inFlight.filter { seqLE(seq, $0.seq) }.map(\.frame)
        if !frames.isEmpty { transport?.sendFrames(frames) }
    }

    private func pump() {
        guard handshakeDone else { return }
        while inFlight.count < Int(window), !pending.isEmpty {
            let item = pending.removeFirst()
            let frame = L1Packet(type: .data, seq: item.seq, payload: item.payload).bytes
            let out = OutItem(
                seq: item.seq,
                frame: frame,
                deadline: Date().addingTimeInterval(sendTimeout),
                retries: 0,
                acked: false,
                part: ackedParts
            )
            inFlight.append(out)
            transport?.sendFrames([frame])
        }
    }

    private func seqLE(_ a: UInt8, _ b: UInt8) -> Bool {
        b &- a < 128
    }

    private func fail(_ message: String) {
        guard !failureReported else { return }
        failureReported = true
        timer?.invalidate()
        timer = nil
        pending.removeAll()
        inFlight.removeAll()
        onFailure?(message)
    }
}

