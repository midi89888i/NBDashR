import Foundation

/// 仪表渲染统一数据快照(参照原版 TelemetrySnapshot 结构)。
struct TelemetrySnapshot {
    // 车速/行程
    var speedKmh: Double = 0
    var maxSpeedKmh: Double = 0
    var avgSpeedKmh: Double = 0
    var tripDistanceKm: Double = 0
    var tripDurationSec: Double = 0
    var altitudeMeters: Double = 0
    var headingDegrees: Double = 0
    var hasGPSFix: Bool = false
    var leanAngleDeg: Double = 0
    var maxLeftLeanDeg: Double = 0
    var maxRightLeanDeg: Double = 0
    var longitudinalG: Double = 0
    var speedHistory: [Double] = []

    // 功率/电量(由 ANT BMS 或演示填充)
    var powerWatts: Double? = nil
    var peakPowerWatts: Double = 0
    var peakRegenWatts: Double = 0
    var batteryPercent: Int? = nil
    var batteryVoltage: Double? = nil
    var batteryCurrent: Double? = nil
    var batteryIsEstimated: Bool = true
    var batterySourceTag: String = "--"

    // 状态
    var bleConnected: Bool = false
    var antConnected: Bool = false
    var isStreaming: Bool = false
    var timestamp: Date = Date()
    var isDemo: Bool = false

    var compassLabel: String {
        let dirs = ["北","东北","东","东南","南","西南","西","西北"]
        let idx = Int((headingDegrees + 22.5) / 45.0) % 8
        return dirs[idx]
    }
    var formattedDuration: String {
        let t = Int(tripDurationSec)
        return String(format: "%d:%02d:%02d", t/3600, (t%3600)/60, t%60)
    }
    static func formatPower(_ watts: Double?) -> String {
        guard let watts else { return "--" }
        if abs(watts) >= 1000 { return String(format: "%.1fkW", watts/1000) }
        return String(format: "%.0fW", watts)
    }
}
