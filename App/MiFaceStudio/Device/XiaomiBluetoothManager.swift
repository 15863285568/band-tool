import Foundation
import CoreBluetooth
import Combine

struct DiscoveredDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let rssi: Int
}

@MainActor
final class XiaomiBluetoothManager: NSObject, ObservableObject {
    static let serviceUUID = CBUUID(string: "FE95")
    static let notifyUUID = CBUUID(string: "0000005E-0000-1000-8000-00805F9B34FB")
    static let writeUUID = CBUUID(string: "0000005F-0000-1000-8000-00805F9B34FB")

    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isConnected = false
    @Published private(set) var connectedName = ""
    @Published private(set) var authReady = false
    @Published var phase: InstallPhase = .idle
    @Published var lastError: String?
    @Published var bluetoothState: CBManagerState = .unknown

    private var central: CBCentralManager!
    private var peripherals: [String: CBPeripheral] = [:]
    private var selected: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var session: XiaomiSession?
    private let store: DeviceStore
    private var rxBuffer = Data()
    private var writeQueue: [Data] = []
    private var writing = false
    private var canWrite = true

    init(store: DeviceStore) {
        self.store = store
        super.init()
        central = CBCentralManager(delegate: self, queue: .main, options: [
            CBCentralManagerOptionShowPowerAlertKey: true
        ])
    }

    func startScan() {
        guard central.state == .poweredOn else {
            lastError = "蓝牙不可用，请检查系统蓝牙开关和权限。"
            return
        }
        devices.removeAll()
        peripherals.removeAll()
        isScanning = true
        central.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    func connect(_ device: DiscoveredDevice) {
        guard let peripheral = peripherals[device.id] else { return }
        stopScan()
        selected = peripheral
        connectedName = device.name
        phase = .connecting
        lastError = nil
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let selected { central.cancelPeripheralConnection(selected) }
        session?.stop()
        session = nil
        selected = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        isConnected = false
        authReady = false
        phase = .idle
        writeQueue.removeAll()
        writing = false
        rxBuffer.removeAll()
    }

    func install(_ artifact: FaceArtifact) {
        guard isConnected, authReady, let session else {
            lastError = "请先连接设备并完成认证。"
            return
        }
        phase = .preparing
        lastError = nil
        Task { @MainActor in
            do {
                try await session.install(fileURL: artifact.url) { fraction in
                    Task { @MainActor in self.phase = .uploading(fraction) }
                }
                phase = .done
            } catch {
                phase = .failed(error.localizedDescription)
                lastError = error.localizedDescription
            }
        }
    }

    func currentAuthKey() -> String {
        guard let id = selected?.identifier.uuidString else { return "" }
        return store.authKey(for: id)
    }

    var currentPeripheralID: String? {
        selected?.identifier.uuidString
    }

    func retryAuthentication() {
        guard let peripheral = selected else { return }
        let key = store.authKey(for: peripheral.identifier.uuidString)
        guard !key.isEmpty else {
            lastError = "请先填写 AuthKey"
            phase = .failed("缺少 AuthKey")
            return
        }
        session?.stop()
        session = nil
        authReady = false
        rxBuffer.removeAll()
        let newSession = makeSession()
        session = newSession
        newSession.start(authKey: key)
    }

    private func makeSession() -> XiaomiSession {
        let session = XiaomiSession(bluetooth: self)
        session.onPhase = { [weak self] phase in self?.phase = phase }
        session.onAuthReady = { [weak self] in
            self?.authReady = true
            self?.phase = .idle
        }
        session.onLog = { message in
            NSLog("[MiFace][Xiaomi] \(message)")
        }
        return session
    }
}

extension XiaomiBluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        if central.state != .poweredOn {
            isScanning = false
            if central.state == .unauthorized {
                lastError = "没有蓝牙权限，请在系统设置中允许。"
            }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let id = peripheral.identifier.uuidString
        let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertised ?? peripheral.name ?? "小米设备"
        peripherals[id] = peripheral
        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index] = DiscoveredDevice(id: id, name: name, rssi: RSSI.intValue)
        } else {
            devices.append(DiscoveredDevice(id: id, name: name, rssi: RSSI.intValue))
            devices.sort { $0.rssi > $1.rssi }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        phase = .handshake
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        phase = .failed(error?.localizedDescription ?? "连接失败")
        lastError = error?.localizedDescription ?? "连接失败"
        isConnected = false
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        isConnected = false
        authReady = false
        phase = error == nil ? .idle : .failed(error?.localizedDescription ?? "连接已断开")
        session?.stop()
        session = nil
    }
}

extension XiaomiBluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            phase = .failed(error?.localizedDescription ?? "无法发现小米服务")
            return
        }
        for service in services where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil, let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == Self.writeUUID ||
                characteristic.uuid.uuidString.uppercased().hasSuffix("005F-0000-1000-8000-00805F9B34FB") {
                writeCharacteristic = characteristic
            }
            if characteristic.uuid == Self.notifyUUID ||
                characteristic.uuid.uuidString.uppercased().hasSuffix("005E-0000-1000-8000-00805F9B34FB") {
                notifyCharacteristic = characteristic
            }
        }
        guard let notifyCharacteristic else {
            phase = .failed("设备不支持小米表盘通知通道")
            return
        }
        peripheral.setNotifyValue(true, for: notifyCharacteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, characteristic.isNotifying else {
            phase = .failed(error?.localizedDescription ?? "无法订阅设备数据")
            return
        }
        guard session == nil else { return }
        let key = store.authKey(for: peripheral.identifier.uuidString)
        let session = makeSession()
        self.session = session
        if key.isEmpty {
            phase = .failed("设备已连接，但还没有 AuthKey。请填写 AuthKey 后重试。")
            lastError = "缺少 AuthKey"
        } else {
            session.start(authKey: key)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let data = characteristic.value else { return }
        rxBuffer.append(data)
        drainFrames()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        canWrite = true
        pumpWrites()
    }

    private func drainFrames() {
        while rxBuffer.count >= 8 {
            guard rxBuffer[0] == 0xA5, rxBuffer[1] == 0xA5 else {
                if let range = rxBuffer.range(of: Data([0xA5, 0xA5])) {
                    rxBuffer.removeSubrange(0..<range.lowerBound)
                } else {
                    rxBuffer.removeAll()
                }
                continue
            }
            let length = Int(rxBuffer[4]) | (Int(rxBuffer[5]) << 8)
            let total = 8 + length
            guard rxBuffer.count >= total else { return }
            let frame = rxBuffer.prefix(total)
            rxBuffer.removeSubrange(0..<total)
            if let packet = L1Packet(data: Data(frame)) {
                session?.sar.receive(packet)
            }
        }
    }
}

extension XiaomiBluetoothManager: SarTransport {
    func sendFrames(_ frames: [Data]) {
        send(frames: frames)
    }

    func send(frames: [Data]) {
        let maxLength = max(20, selected?.maximumWriteValueLength(for: .withoutResponse) ?? 182)
        for frame in frames {
            var offset = 0
            while offset < frame.count {
                let end = min(offset + maxLength, frame.count)
                writeQueue.append(frame.subdata(in: offset..<end))
                offset = end
            }
        }
        pumpWrites()
    }

    private func pumpWrites() {
        guard !writing, let peripheral = selected, let characteristic = writeCharacteristic else { return }
        guard !writeQueue.isEmpty else { return }
        guard canWrite else { return }
        writing = true
        let chunk = writeQueue.removeFirst()
        peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
        canWrite = peripheral.canSendWriteWithoutResponse
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.004) { [weak self] in
            self?.writing = false
            self?.pumpWrites()
        }
    }
}
