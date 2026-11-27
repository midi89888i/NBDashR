import Foundation
import CoreBluetooth
import Combine

// MARK: - ANT BMS BLE 客户端
// 仿照 App 现有 BLETransport 分层:本类是独立 CoreBluetooth 客户端,
// 与小哈(广播无连接解析)不同,ANT 需要 GATT 连接 + 主动轮询(默认 2 秒)。
// 产出 AntBMSStatus,经 AntBMSBatteryResolver 桥接进 ResolvedBatteryState。

@MainActor
public final class AntBMSClient: NSObject, ObservableObject {
    public enum State: Equatable {
        case idle, scanning, connecting, discovering, ready, disconnected, failed(String)
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var status: AntBMSStatus?
    @Published public private(set) var lastUpdateAt: Date?
    @Published public private(set) var deviceName: String?
    @Published public private(set) var discovered: [UUID: String] = [:]

    public var onLog: ((String) -> Void)?

    private static let serviceUUID = CBUUID(string: "FFE0")
    private static let charUUID = CBUUID(string: "FFE1")

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private let assembler = AntBMSFrameAssembler()
    private var pollTimer: Timer?
    private var targetID: UUID?
    private var pollInterval: TimeInterval = 2.0

    /// 扫描前缀:ANT 保护板广播名常见形态(蚂蚁兴能/ANT-BLE/ZZ-BMS 等)
    public static let namePrefixes = ["ANT", "ANT-BLE", "ANT@BLE", "ZZ-BMS", "BMS", "16ZM", "24BH", "22AA", "04DM"]

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    private func log(_ message: String) {
        onLog?("ANT BMS：\(message)")
    }

    // MARK: 扫描与连接

    public func startScan() {
        guard central.state == .poweredOn else { return }
        discovered.removeAll()
        central.scanForPeripherals(withServices: nil,
                                 options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        state = .scanning
        log("开始扫描 ANT 保护板")
    }

    public func stopScan() {
        central.stopScan()
        if case .scanning = state { state = .idle }
    }

    public func connect(_ id: UUID) {
        targetID = id
        guard let item = discovered.keys.contains(id)
                ? central.retrievePeripherals(withIdentifiers: [id]).first
                : central.retrievePeripherals(withIdentifiers: [id]).first else {
            // 扫描缓存里找
            guard let p = peripheral, p.identifier == id else {
                state = .failed("未找到设备,请先扫描")
                return
            }
            connectPeripheral(p)
            return
        }
        connectPeripheral(item)
    }

    public func connectPeripheral(_ p: CBPeripheral) {
        stopScan()
        peripheral = p
        targetID = p.identifier
        deviceName = p.name
        p.delegate = self
        state = .connecting
        central.connect(p, options: nil)
        log("连接 \(p.name ?? "ANT BMS")")
    }

    public func disconnect() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
        peripheral = nil
        characteristic = nil
        status = nil
        state = .disconnected
    }

    // MARK: 轮询

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollOnce() }
        }
        pollOnce()
    }

    private func pollOnce() {
        guard let peripheral, peripheral.state == .connected, let characteristic else { return }
        peripheral.writeValue(AntBMSFrame.statusPollCommand, for: characteristic, type: .withoutResponse)
    }

    /// 连接保活/数据年龄(秒);超过 10 秒无帧视为掉线数据
    public var dataAge: TimeInterval? {
        lastUpdateAt.map { Date().timeIntervalSince($0) }
    }
}

extension AntBMSClient: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            state = .failed("蓝牙未开启")
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                               advertisementData: [String: Any], rssi: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let matchesName = Self.namePrefixes.contains { name.uppercased().hasPrefix($0.uppercased()) }
        let matchesService = services.contains(Self.serviceUUID)
        guard matchesName || matchesService else { return }
        discovered[p.identifier] = name.isEmpty ? "ANT BMS" : name
        log("发现 \(name)(rssi=\(rssi))")
        // 若用户已绑定目标,自动连接
        if let target = targetID, target == p.identifier, peripheral == nil {
            connectPeripheral(p)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        state = .discovering
        p.discoverServices([Self.serviceUUID])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        state = .failed(error?.localizedDescription ?? "连接失败")
        peripheral = nil
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        pollTimer?.invalidate()
        pollTimer = nil
        state = .disconnected
        peripheral = nil
        characteristic = nil
        log("已断开\(error.map { "(\($0.localizedDescription))" } ?? "")")
        // 若仍绑定目标,重扫自动回连
        if targetID != nil {
            startScan()
        }
    }
}

extension AntBMSClient: CBPeripheralDelegate {
    public func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = p.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            state = .failed("未找到 FFE0 服务,不是 ANT 保护板或固件不兼容")
            return
        }
        p.discoverCharacteristics([Self.charUUID], for: service)
    }

    public func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let ch = service.characteristics?.first(where: { $0.uuid == Self.charUUID }) else {
            state = .failed("未找到 FFE1 特征")
            return
        }
        characteristic = ch
        p.setNotifyValue(true, for: ch)
    }

    public func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        guard error == nil, ch.isNotifying else {
            state = .failed("订阅通知失败")
            return
        }
        state = .ready
        log("已就绪,开始轮询")
        startPolling()
    }

    public func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard error == nil, let value = ch.value else { return }
        for frame in assembler.append(value) {
            guard frame.count >= 3 else { continue }
            let function = frame[2]
            if function == 0x11, let decoded = AntBMSStatus.decodeStatusFrame(frame) {
                status = decoded
                lastUpdateAt = Date()
            }
        }
    }
}
