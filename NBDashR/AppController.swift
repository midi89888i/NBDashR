import Foundation
import Combine
import CoreMedia
import UIKit

/// 主控制器:编排 配对唤醒 → 渲染循环 → 推流 全链路 + 自动投屏。
@MainActor
final class AppController: ObservableObject {
    // 子系统
    let vehicleConnection = NinebotVehicleConnection()
    let antClient = AntBMSClient()
    let antPower = AntBMSPowerTracker()
    let sensors = SensorFusion()
    private(set) var streamer: Streamer?

    // 状态
    @Published var selectedThemeID: String {
        didSet { defaults.set(selectedThemeID, forKey: "theme.id") }
    }
    @Published private(set) var isStreaming = false
    @Published private(set) var targetIP: String {
        didSet { defaults.set(targetIP, forKey: "target.ip") }
    }
    @Published var isDemoMode = false
    @Published var autoProjectionEnabled: Bool {
        didSet { defaults.set(autoProjectionEnabled, forKey: "autoproj.enabled") }
    }
    @Published private(set) var logs: [String] = []
    @Published private(set) var snapshot = TelemetrySnapshot()
    @Published private(set) var powerReading = PowerReading(watts: nil)

    private let defaults = UserDefaults.standard
    private var renderTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var frameIndex: Int64 = 0
    private let fps = 30

    var theme: DashboardThemeRenderer {
        ThemeRegistry.all.first { $0.id == selectedThemeID } ?? ThemeRegistry.all[0]
    }

    init() {
        let d = UserDefaults.standard
        selectedThemeID = d.string(forKey: "theme.id") ?? ThemeRegistry.all[0].id
        targetIP = d.string(forKey: "target.ip") ?? "192.168.169.1"
        autoProjectionEnabled = d.object(forKey: "autoproj.enabled") == nil ? true : d.bool(forKey: "autoproj.enabled")

        sensors.start()
        antPower.bind(client: antClient)
        antPower.setEnabled(true)
        observeSubsystems()
        startRenderLoop()

        // 自动投屏:冷启动即发起(若已配对)
        if autoProjectionEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.requestAutoProjection()
            }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.requestAutoProjection() }
        }
    }

    // MARK: 子系统状态聚合

    private func observeSubsystems() {
        vehicleConnection.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in self?.handleVehiclePhase(phase) }
            .store(in: &cancellables)
    }

    private func handleVehiclePhase(_ phase: NinebotVehicleConnection.Phase) {
        switch phase {
        case .active:
            log("仪表已确认导航(0x71 ACK),启动推流")
            startStreaming()
        case .idle, .stopping:
            if isStreaming {
                log("导航会话结束,停止推流")
                stopStreaming()
            }
        case .failed:
            if isStreaming { stopStreaming() }
        default:
            break
        }
    }

    // MARK: 自动投屏

    func requestAutoProjection() {
        guard autoProjectionEnabled else { return }
        guard vehicleConnection.garage.selected != nil else { return }
        switch vehicleConnection.phase {
        case .active, .starting, .authenticating, .preparing, .connecting, .discovering, .reconnecting:
            return
        default:
            log("自动投屏:连接并唤醒车辆")
            vehicleConnection.startProjection()
        }
    }

    // MARK: 推流控制

    func toggleStreaming() {
        if isStreaming {
            stopStreaming()
            vehicleConnection.stopProjection()
        } else {
            // 手动启动:若未认证,走完整唤醒链;已激活直接推流
            if vehicleConnection.phase == .active {
                startStreaming()
            } else {
                vehicleConnection.startProjection()
                log("正在唤醒车辆投屏,认证成功后自动开始推流…")
            }
        }
    }

    func startStreaming() {
        guard !isStreaming else { return }
        let streamer = Streamer(targetHost: targetIP, bitrate: 1_500_000, fps: fps)
        self.streamer = streamer
        Task {
            await streamer.start(width: 848, height: 480)
            await MainActor.run {
                self.isStreaming = streamer.isRunning
                if streamer.isRunning { self.log("推流已启动 → \(self.targetIP) (UDP 5012/5013)") }
            }
        }
    }

    func stopStreaming() {
        guard isStreaming else { return }
        let streamer = self.streamer
        self.streamer = nil
        isStreaming = false
        Task { await streamer?.stop() }
        log("推流已停止")
    }

    // MARK: 渲染循环

    private func startRenderLoop() {
        renderTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / Double(fps), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.renderFrame() }
        }
    }

    private func renderFrame() {
        frameIndex += 1
        antPower.tick()
        updateSnapshot()
        powerReading = PowerReading(watts: snapshot.powerWatts)
        // 每秒 1 帧就够推流(降低负载:推流 fps=30 可全推;这里先全帧)
        let canvas = DashCanvas(width: 848, height: 480)
        guard let (ctx, pixelBuffer) = canvas.begin() else { return }
        let rect = CGRect(x: 0, y: 0, width: 848, height: 480)
        theme.draw(in: ctx, rect: rect, snapshot: snapshot, power: powerReading)
        canvas.end()
        if isStreaming {
            let ts = CMTime(value: frameIndex, timescale: CMTimeScale(fps))
            streamer?.encode(pixelBuffer, timestamp: ts)
        }
    }

    private func updateSnapshot() {
        var snap = TelemetrySnapshot()
        snap.speedKmh = sensors.speedKmh
        snap.maxSpeedKmh = sensors.maxSpeedKmh
        snap.tripDistanceKm = sensors.tripDistanceKm
        snap.tripDurationSec = sensors.tripStartAt.map { Date().timeIntervalSince($0) } ?? 0
        snap.altitudeMeters = sensors.altitudeMeters
        snap.headingDegrees = sensors.headingDegrees
        snap.hasGPSFix = sensors.hasGPSFix
        snap.leanAngleDeg = sensors.leanAngleDeg
        snap.maxLeftLeanDeg = sensors.maxLeftLeanDeg
        snap.maxRightLeanDeg = sensors.maxRightLeanDeg
        snap.longitudinalG = sensors.longitudinalG
        snap.speedHistory = sensors.speedHistory
        snap.avgSpeedKmh = snap.tripDurationSec > 10 ? snap.tripDistanceKm / (snap.tripDurationSec / 3600) : 0

        // ANT 功率/电量(新鲜才覆盖)
        let supply = antPower.supply
        if supply.isFresh {
            snap.powerWatts = supply.powerWatts
            snap.batteryPercent = supply.socPercent
            snap.batteryVoltage = supply.voltageVolts
            snap.batteryCurrent = supply.currentAmps
            snap.batteryIsEstimated = false
            snap.batterySourceTag = "ANT"
        } else {
            snap.powerWatts = nil
            snap.batteryPercent = nil
            snap.batteryVoltage = nil
            snap.batterySourceTag = "--"
        }
        snap.peakPowerWatts = supply.peakPowerWatts
        snap.peakRegenWatts = supply.peakRegenWatts
        snap.antConnected = supply.isFresh
        snap.bleConnected = vehicleConnection.phase == .active || vehicleConnection.phase == .starting
        snap.isStreaming = isStreaming
        snap.timestamp = Date()
        snap.isDemo = isDemoMode
        if isDemoMode { applyDemoData(&snap) }
        snapshot = snap
    }

    // 演示数据:无车时调试用
    private func applyDemoData(_ snap: inout TelemetrySnapshot) {
        let t = Date().timeIntervalSince1970
        snap.speedKmh = max(0, 35 + 20 * sin(t / 5))
        snap.powerWatts = 1500 + 1800 * sin(t / 3)
        snap.batteryPercent = 76
        snap.batteryVoltage = 72.4
        snap.peakPowerWatts = 3400
        snap.peakRegenWatts = 800
        snap.batterySourceTag = "ANT"
        snap.antConnected = true
    }

    func resetTrip() {
        sensors.resetTrip()
        antPower.resetPeaks()
    }

    private func log(_ message: String) {
        let fmt = DateFormatter(); fmt.dateFormat = "HH:mm:ss"
        logs.insert("\(fmt.string(from: Date())) \(message)", at: 0)
        if logs.count > 60 { logs.removeLast(logs.count - 60) }
    }
}
