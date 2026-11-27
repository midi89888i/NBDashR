import Foundation
import Combine

// MARK: - ANT 保护板功率/电量统一供给
//
// 目标:仪表上的 4 个值全部改由 ANT 保护板供给,不再依赖车辆 BLE 功率寄存器:
//
//   ┌──────────────┬────────────────────────────────────────────────┐
//   │ 仪表字段      │ 数据逻辑                                        │
//   ├──────────────┼────────────────────────────────────────────────┤
//   │ 当前功率      │ ANT powerWatts 直读(实时,放电为正)             │
//   │ 峰值功率      │ 本模块记录的放电正峰值(max(power>0))            │
//   │ 回收功率      │ 本模块记录的充电/回馈负峰值(min(power<0) 取绝对) │
//   │ 电量          │ ANT socPercent 库仑计直读                        │
//   └──────────────┴────────────────────────────────────────────────┘
//
// 峰值语义与原版一致:原版 peakPowerWatts/peakRegenWatts 本来就不是任何设备
// 下发的字段,而是 App 对 powerWatts 时间序列自行累积的正/负极值。
// 我们只把输入源从「车辆功率寄存器」换成「ANT 功率直读」,累积逻辑原样保留。
//
// 注意测量点差异(用户已知晓并接受):
//   车辆 VCU 功率 = 电机端;ANT 功率 = 电池端(含控制器损耗与车上其他用电)。
//   同一瞬间两者会有差值,峰值记录仍然自洽(同一来源内部比较)。

/// 功率供给快照,喂给 TelemetrySnapshot 的对应字段
public struct AntPowerSupply: Equatable, Sendable {
    /// 当前实时功率 W(放电为正,充电/回收为负);无数据为 nil
    public var powerWatts: Double?
    /// 放电峰值功率 W(正峰,本次骑行/会话内累计)
    public var peakPowerWatts: Double = 0
    /// 回收(充电/回馈)峰值功率 W(负峰的绝对值,显示用)
    public var peakRegenWatts: Double = 0
    /// 电量 %(库仑计直读)
    public var socPercent: Int?
    /// 真实电压 V
    public var voltageVolts: Double?
    /// 电流 A(正=充电方向依固件,此处仅透传参考)
    public var currentAmps: Double?
    /// 数据年龄(秒);过大则上层应视为失效
    public var ageSec: Double?
    /// 数据是否新鲜可用
    public var isFresh: Bool

    public init(powerWatts: Double?, peakPowerWatts: Double, peakRegenWatts: Double,
                socPercent: Int?, voltageVolts: Double?, currentAmps: Double?,
                ageSec: Double?, isFresh: Bool) {
        self.powerWatts = powerWatts
        self.peakPowerWatts = peakPowerWatts
        self.peakRegenWatts = peakRegenWatts
        self.socPercent = socPercent
        self.voltageVolts = voltageVolts
        self.currentAmps = currentAmps
        self.ageSec = ageSec
        self.isFresh = isFresh
    }
}

/// 峰值跟踪器:复刻原版「功率时间序列正/负极值累积」逻辑,输入改为 ANT。
/// 线程模型:与 AntBMSClient 同在 MainActor。
@MainActor
public final class AntBMSPowerTracker: ObservableObject {
    @Published public private(set) var supply = AntPowerSupply(
        powerWatts: nil, peakPowerWatts: 0, peakRegenWatts: 0,
        socPercent: nil, voltageVolts: nil, currentAmps: nil,
        ageSec: nil, isFresh: false)

    /// 数据新鲜阈值:超过视为保护板掉线,功率显示回落(与 resolver 的 staleTimeout 对齐)
    public var staleTimeoutSec: TimeInterval = 10

    /// 是否启用:关闭时 supply.isFresh 恒 false,不干扰车辆 BLE 原链路
    public private(set) var enabled = false

    private var lastUpdateAt: Date?
    private var cancellable: AnyCancellable?

    public init() {}

    /// 绑定 ANT 客户端的数据流
    public func bind(client: AntBMSClient) {
        cancellable = client.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, let status else { return }
                self.ingest(status)
            }
    }

    public func setEnabled(_ on: Bool) {
        enabled = on
        if !on {
            supply = AntPowerSupply(powerWatts: nil, peakPowerWatts: 0, peakRegenWatts: 0,
                                    socPercent: nil, voltageVolts: nil, currentAmps: nil,
                                    ageSec: nil, isFresh: false)
        }
    }

    /// 清零峰值(例如每次骑行开始/用户手动重置行程时调用)
    public func resetPeaks() {
        supply.peakPowerWatts = 0
        supply.peakRegenWatts = 0
    }

    private func ingest(_ st: AntBMSStatus) {
        guard enabled else { return }
        let now = Date()
        lastUpdateAt = now

        let p = st.powerWatts
        // 放电正峰:power > 0 取最大
        if p > supply.peakPowerWatts {
            supply.peakPowerWatts = p
        }
        // 回收负峰:power < 0 时 |power| 取最大(充电与动能回收在电池端同为负功率)
        if p < 0, -p > supply.peakRegenWatts {
            supply.peakRegenWatts = -p
        }

        supply.powerWatts = p
        supply.socPercent = Int(st.socPercent.rounded())
        supply.voltageVolts = st.totalVoltage
        supply.currentAmps = st.current
        supply.ageSec = 0
        supply.isFresh = true
    }

    /// 周期性调用(可挂在现有遥测 tick 上)刷新数据年龄
    public func tick(now: Date = Date()) {
        guard enabled, let last = lastUpdateAt else { return }
        let age = now.timeIntervalSince(last)
        supply.ageSec = age
        if age > staleTimeoutSec {
            supply.isFresh = false
            supply.powerWatts = nil   // 当前功率回落,但峰值保留(与原版掉线语义一致)
        }
    }
}

// MARK: - 接入 TelemetrySnapshot 的改法(对照原版字段)
//
// 原版: vehiclePowerWatts / peakPowerWatts / peakRegenWatts / vehicleBatteryPercent
//       都来自 VehicleBLETelemetry(车辆 BLE 寄存器)+ BatteryTelemetryResolver
//
// 改法:在组装 TelemetrySnapshot 的地方(符号上看是 DashboardController/
//       DisplayTelemetryAnimator 上游),加入 ANT 覆盖逻辑:
//
//   var snap = baseSnapshot   // 现有链路产出
//   if antTracker.supply.isFresh {
//       snap.vehiclePowerWatts   = antTracker.supply.powerWatts
//       snap.peakPowerWatts      = antTracker.supply.peakPowerWatts
//       snap.peakRegenWatts      = antTracker.supply.peakRegenWatts
//       snap.vehicleBatteryPercent = antTracker.supply.socPercent
//       snap.vehicleBatteryVoltage = antTracker.supply.voltageVolts
//       snap.batterySourceKind   = .antBMS
//       snap.batteryIsEstimated  = false
//   }
//   // isFresh == false(未启用或保护板掉线)→ 原链路原样,行为与现在完全一致
//
// 峰值清零时机(与原版对齐):原版峰值为会话级累积;
//   若原版在「车辆上电/行程开始」处有 clearLiveReadings(),
//   在同一处加 antTracker.resetPeaks() 即可保持语义一致。
