import Foundation

enum XiaomiSessionError: LocalizedError {
    case authKeyMissing
    case authRejected
    case authTimeout
    case protocolError(String)
    case deviceRejected(String)
    case timeout(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .authKeyMissing: return "没有可用的 AuthKey。请先在设备页填写 32 位 AuthKey。"
        case .authRejected: return "设备拒绝了认证，AuthKey 可能不正确。"
        case .authTimeout: return "认证超时，请重新连接设备。"
        case .protocolError(let text): return text
        case .deviceRejected(let text): return text
        case .timeout(let text): return text
        case .cancelled: return "操作已取消"
        }
    }
}

@MainActor
final class XiaomiSession: SarTransport {
    weak var bluetooth: XiaomiBluetoothManager?
    let sar = SarController()

    var onPhase: ((InstallPhase) -> Void)?
    var onAuthReady: (() -> Void)?
    var onLog: ((String) -> Void)?

    private(set) var authKey: String = ""
    private var cipher: XiaomiL2Cipher?
    private var pendingKeys: XiaomiL2Cipher?
    private var authActive = false
    private var phoneRandom = Data()
    private var authContinuation: CheckedContinuation<Void, Error>?
    private var prepareContinuation: CheckedContinuation<Int, Error>?
    private var massContinuation: CheckedContinuation<(Int, Int), Error>?
    private var installContinuation: CheckedContinuation<Int, Error>?
    private var prepareToken = UUID()
    private var massToken = UUID()
    private var installToken = UUID()
    private var authToken = UUID()
    private var uploadingTotal = 0
    private var bufferedInstallCode: Int?

    init(bluetooth: XiaomiBluetoothManager) {
        self.bluetooth = bluetooth
        sar.transport = self
        sar.onHandshake = { [weak self] in self?.beginAuthentication() }
        sar.onPayload = { [weak self] channel, opcode, payload in
            self?.handlePayload(channel: channel, opcode: opcode, payload: payload)
        }
        sar.onFailure = { [weak self] message in
            self?.failAll(XiaomiSessionError.protocolError(message))
        }
        sar.onProgress = { [weak self] acked, total in
            guard let self, total > 0 else { return }
            let fraction = min(1.0, Double(acked) / Double(total))
            self.onPhase?(.uploading(fraction))
        }
    }

    func start(authKey: String) {
        self.authKey = authKey
        sar.start()
        onPhase?(.handshake)
    }

    func stop() {
        sar.stop()
        cipher = nil
        pendingKeys = nil
        authActive = false
        failAll(XiaomiSessionError.cancelled)
    }

    func sendFrames(_ frames: [Data]) {
        bluetooth?.send(frames: frames)
    }

    // MARK: - Sending

    private func sendPacket(_ packet: Data, encrypted: Bool = true) {
        var l2 = Data()
        if encrypted, let cipher {
            l2.append(L2Channel.pb.rawValue)
            l2.append(L2OpCode.writeEnc.rawValue)
            l2.append(cipher.encrypt(packet))
        } else {
            l2.append(L2Channel.pb.rawValue)
            l2.append(L2OpCode.write.rawValue)
            l2.append(packet)
        }
        _ = sar.enqueue(l2)
    }

    // MARK: - Receiving

    private func handlePayload(channel: UInt8, opcode: UInt8, payload: Data) {
        guard channel == L2Channel.pb.rawValue else { return }
        var plain = payload
        if opcode == L2OpCode.writeEnc.rawValue {
            let active = cipher ?? pendingKeys
            guard let active else { return }
            plain = active.decrypt(payload)
        }
        guard let packet = XiaomiPacket.parse(plain) else { return }
        switch packet.type {
        case XiaomiPacket.PacketType.account.rawValue:
            handleAccount(packet)
        case XiaomiPacket.PacketType.watchFace.rawValue:
            handleWatchFace(packet)
        case XiaomiPacket.PacketType.mass.rawValue:
            handleMass(packet)
        default:
            break
        }
    }

    private func handleAccount(_ packet: XiaomiPacket.Incoming) {
        guard let payload = packet.payload else { return }
        if let verify = XiaomiPacket.authDeviceVerify(from: payload) {
            handleDeviceVerify(verify)
            return
        }
        if let accepted = XiaomiPacket.authDeviceConfirm(from: payload) {
            if accepted {
                cipher = pendingKeys
                authActive = true
                resolveAuth()
                onPhase?(.authenticating)
                onAuthReady?()
            } else {
                failAuth(.authRejected)
            }
            return
        }
        let fields = ProtoFields(payload)
        if let error = fields.varints[3], error != 0 {
            failAuth(.authRejected)
        }
    }

    private func handleWatchFace(_ packet: XiaomiPacket.Incoming) {
        guard let payload = packet.payload else { return }
        if packet.id == 4, let status = XiaomiPacket.watchFaceStatus(from: payload) {
            guard let continuation = prepareContinuation else { return }
            prepareContinuation = nil
            prepareToken = UUID()
            continuation.resume(returning: status)
            return
        }
        if let result = XiaomiPacket.watchFaceInstallResult(from: payload) {
            guard let continuation = installContinuation else {
                bufferedInstallCode = result.code
                return
            }
            installContinuation = nil
            installToken = UUID()
            continuation.resume(returning: result.code)
        }
    }

    private func handleMass(_ packet: XiaomiPacket.Incoming) {
        guard let payload = packet.payload,
              let response = XiaomiPacket.massPrepareResponse(from: payload),
              let continuation = massContinuation else { return }
        massContinuation = nil
        massToken = UUID()
        continuation.resume(returning: (response.sliceLength, response.remained))
    }

    // MARK: - Auth

    private func beginAuthentication() {
        onPhase?(.authenticating)
        guard let secret = XiaomiCrypto.hexToBytes(authKey) else {
            failAuth(.authKeyMissing)
            return
        }
        _ = secret
        phoneRandom = XiaomiCrypto.randomBytes(16)
        authActive = false
        cipher = nil
        pendingKeys = nil
        sendPacket(XiaomiPacket.authAppVerify(random: phoneRandom), encrypted: false)
        scheduleAuthTimeout()
    }

    private func handleDeviceVerify(_ verify: (random: Data, sign: Data)) {
        guard verify.random.count == 16, verify.sign.count == 32,
              phoneRandom.count == 16,
              let secret = XiaomiCrypto.hexToBytes(authKey) else {
            failAuth(.protocolError("设备认证数据格式不正确"))
            return
        }
        let block = XiaomiCrypto.kdfMiwear(secret: secret, phoneNonce: phoneRandom, watchNonce: verify.random)
        guard block.count == 64 else { failAuth(.protocolError("认证密钥派生失败")); return }
        let decKey = block.subdata(in: 0..<16)
        let encKey = block.subdata(in: 16..<32)
        let decNonce = block.subdata(in: 32..<36)
        let encNonce = block.subdata(in: 36..<40)

        let expected = XiaomiCrypto.hmacSHA256(key: decKey, data: verify.random + phoneRandom)
        guard constantTimeEqual(expected, verify.sign) else {
            failAuth(.authRejected)
            return
        }

        let signs = XiaomiCrypto.hmacSHA256(key: encKey, data: phoneRandom + verify.random)

        var companion = ProtoWriter()
        companion.varint(1, 1) // iOS
        companion.string(3, "MiFace Studio")
        companion.varint(4, 0xFFFF_FFFF)
        var nonce = Data(encNonce)
        nonce.append(Data(repeating: 0, count: 8))
        let encrypted = XiaomiCrypto.aesCCMEncrypt(
            key: encKey, nonce: nonce, aad: Data(), plaintext: companion.data
        )

        pendingKeys = XiaomiL2Cipher(encryptionKey: encKey, decryptionKey: decKey)
        sendPacket(XiaomiPacket.authAppConfirm(sign: signs, encryptedDevice: encrypted), encrypted: false)
    }

    private func resolveAuth() {
        authToken = UUID()
        authContinuation?.resume()
        authContinuation = nil
    }

    private func failAuth(_ error: XiaomiSessionError) {
        authToken = UUID()
        authContinuation?.resume(throwing: error)
        authContinuation = nil
        onPhase?(.failed(error.localizedDescription))
    }

    private func scheduleAuthTimeout() {
        let token = UUID()
        authToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self, self.authToken == token else { return }
            self.failAuth(.authTimeout)
        }
    }

    // MARK: - Install

    func install(fileURL: URL, progress: @escaping (Double) -> Void) async throws {
        guard authActive else { throw XiaomiSessionError.authKeyMissing }
        bufferedInstallCode = nil
        let raw = try Data(contentsOf: fileURL)
        let prepared = try FacePackage.prepareForInstall(raw)
        onPhase?(.preparing)
        let status = try await prepareWatchface(id: prepared.id, size: prepared.data.count)
        guard status == 0 else {
            throw XiaomiSessionError.deviceRejected("设备拒绝安装表盘（状态 \(status)）")
        }
        try await upload(prepared.data, progress: progress)
        onPhase?(.waitingForDevice)
        let code = try await waitInstallResult()
        guard code == 2 || code == 3 else {
            throw XiaomiSessionError.deviceRejected("设备安装失败（代码 \(code)）")
        }
        _ = try? await setCurrent(id: prepared.id)
        onPhase?(.done)
    }

    private func prepareWatchface(id: String, size: Int) async throws -> Int {
        let packet = XiaomiPacket.watchFacePrepare(id: id, size: size)
        return try await withCheckedThrowingContinuation { continuation in
            prepareContinuation = continuation
            let token = UUID()
            prepareToken = token
            sendPacket(packet)
            DispatchQueue.main.asyncAfter(deadline: .now() + 35) { [weak self] in
                guard let self, self.prepareToken == token else { return }
                self.prepareContinuation?.resume(throwing: XiaomiSessionError.timeout("等待设备准备超时"))
                self.prepareContinuation = nil
                self.prepareToken = UUID()
            }
        }
    }

    private func upload(_ data: Data, progress: @escaping (Double) -> Void) async throws {
        let digest = XiaomiCrypto.md5(data)
        let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Int, Int), Error>) in
            massContinuation = continuation
            let token = UUID()
            massToken = token
            sendPacket(XiaomiPacket.massPrepare(dataType: 16, md5: digest, length: data.count))
            DispatchQueue.main.asyncAfter(deadline: .now() + 35) { [weak self] in
                guard let self, self.massToken == token else { return }
                self.massContinuation?.resume(throwing: XiaomiSessionError.timeout("等待设备接收表盘超时"))
                self.massContinuation = nil
                self.massToken = UUID()
            }
        }
        guard response.0 > 0 else {
            throw XiaomiSessionError.deviceRejected("设备没有返回可用的分片大小")
        }
        let sliceLength = min(max(response.0, 512), 8192)
        let fragmentLength = max(128, sliceLength - 6)
        let alreadySent = min(max(response.1, 0), data.count)
        let remaining = data.count - alreadySent

        var inner = Data([0x00, 0x10])
        inner.append(digest)
        inner.append(L1Packet.le32(UInt32(remaining)))
        inner.append(data.subdata(in: alreadySent..<data.count))
        let crc = L1Packet.crc32(inner)
        inner.append(L1Packet.le32(crc))

        let total = max(1, (inner.count + fragmentLength - 1) / fragmentLength)
        uploadingTotal = total
        sar.beginPartTracking(total)
        onPhase?(.uploading(0))
        for part in 0..<total {
            let start = part * fragmentLength
            let end = min(start + fragmentLength, inner.count)
            var payload = Data()
            payload.append(L1Packet.le16(UInt16(total)))
            payload.append(L1Packet.le16(UInt16(part + 1)))
            payload.append(inner.subdata(in: start..<end))
            var l2 = Data([L2Channel.mass.rawValue, L2OpCode.write.rawValue])
            l2.append(payload)
            _ = sar.enqueue(l2)
            if part % 8 == 7 {
                try? await Task.sleep(nanoseconds: 8_000_000)
            }
        }

        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            if sar.isIdle { break }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        if !sar.isIdle {
            throw XiaomiSessionError.timeout("表盘传输超时")
        }
        onPhase?(.uploading(1))
    }

    private func waitInstallResult() async throws -> Int {
        if let buffered = bufferedInstallCode {
            bufferedInstallCode = nil
            return buffered
        }
        return try await withCheckedThrowingContinuation { continuation in
            installContinuation = continuation
            let token = UUID()
            installToken = token
            DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
                guard let self, self.installToken == token else { return }
                self.installContinuation?.resume(throwing: XiaomiSessionError.timeout("设备安装超时"))
                self.installContinuation = nil
                self.installToken = UUID()
            }
        }
    }

    private func setCurrent(id: String) async throws -> Void {
        // Fire-and-forget; the face is already installed and selected by the
        // device in most firmware revisions.
        sendPacket(XiaomiPacket.watchFaceSetCurrent(id: id))
    }

    // MARK: - Helpers

    private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for index in 0..<lhs.count { diff |= lhs[index] ^ rhs[index] }
        return diff == 0
    }

    private func failAll(_ error: Error) {
        authContinuation?.resume(throwing: error); authContinuation = nil
        prepareContinuation?.resume(throwing: error); prepareContinuation = nil
        massContinuation?.resume(throwing: error); massContinuation = nil
        installContinuation?.resume(throwing: error); installContinuation = nil
        onPhase?(.failed(error.localizedDescription))
    }
}

private extension SarController {
    var isIdle: Bool { pendingCount == 0 && inFlightCount == 0 }
}

