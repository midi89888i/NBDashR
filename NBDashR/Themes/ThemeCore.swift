import Foundation
import UIKit
import CoreGraphics

/// 功率分级(原版 PowerLevel: idle/regen/eco/sport/boost/max)
enum PowerLevel: String {
    case unavailable, idle, regen, eco, sport, boost, max
    var tag: String {
        switch self {
        case .unavailable: return "--"
        case .idle: return "IDLE"
        case .regen: return "REGEN"
        case .eco: return "ECO"
        case .sport: return "SPORT"
        case .boost: return "BOOST"
        case .max: return "MAX"
        }
    }
    var color: UIColor {
        switch self {
        case .unavailable, .idle: return .systemGray
        case .regen: return .systemGreen
        case .eco: return .systemTeal
        case .sport: return .systemYellow
        case .boost: return .systemOrange
        case .max: return .systemRed
        }
    }
}

/// 由当前功率计算分级与弧比例(输入电池端功率,阈值按电机功率近似)
struct PowerReading {
    var watts: Double?
    var level: PowerLevel
    var outputFrac: Double   // 放电弧比例 0-1
    var regenFrac: Double    // 回收弧比例 0-1
    var isRegen: Bool { (watts ?? 0) < -5 }

    static let maxOutputWatts: Double = 6000   // 弧满刻度,适配大功率车型
    static let maxRegenWatts: Double = 1500

    init(watts: Double?) {
        self.watts = watts
        guard let watts else {
            level = .unavailable; outputFrac = 0; regenFrac = 0; return
        }
        if watts < -5 {
            level = .regen
            regenFrac = min(1, -watts / Self.maxRegenWatts)
            outputFrac = 0
        } else {
            regenFrac = 0
            outputFrac = min(1, watts / Self.maxOutputWatts)
            switch watts {
            case ..<5: level = .idle
            case ..<800: level = .eco
            case ..<2200: level = .sport
            case ..<4000: level = .boost
            default: level = .max
            }
        }
    }
}

protocol DashboardThemeRenderer {
    var id: String { get }
    var displayName: String { get }
    var subtitle: String { get }
    func draw(in ctx: CGContext, rect: CGRect, snapshot: TelemetrySnapshot, power: PowerReading)
}

enum ThemeRegistry {
    static let all: [DashboardThemeRenderer] = [
        BMWSportTheme(), CyberSportTheme(), HyperdriveTheme(),
        TrackProTheme(), DaylightCleanTheme(), FireflyTheme(),
    ]
}

// 公共绘制辅助
extension CGContext {
    /// 电量显示文本与颜色
    func batteryText(_ snapshot: TelemetrySnapshot) -> (String, UIColor) {
        guard let pct = snapshot.batteryPercent else { return ("--", .systemGray) }
        let color: UIColor = pct > 50 ? .systemGreen : pct > 20 ? .systemYellow : .systemRed
        return ("\(pct)%", color)
    }

    /// 顶部状态条:电量 + 电压 + 时间(各主题通用)
    func drawTopStatusBar(in rect: CGRect, snapshot: TelemetrySnapshot,
                          bgColor: UIColor, textColor: UIColor, accent: UIColor) {
        let barH: CGFloat = 34
        fillRoundedRect(CGRect(x: rect.minX + 8, y: rect.minY + 6, width: rect.width - 16, height: barH),
                        radius: barH / 2, color: bgColor.withAlphaComponent(0.55))
        // 电量
        let (pctText, pctColor) = batteryText(snapshot)
        drawText("⚡\(pctText)", center: CGPoint(x: rect.minX + 66, y: rect.minY + 6 + barH/2),
                 size: 17, weight: .bold, color: pctColor, monoDigits: true, align: .center)
        // 电压
        if let volts = snapshot.batteryVoltage {
            drawText(String(format: "%.1fV", volts),
                     center: CGPoint(x: rect.minX + 148, y: rect.minY + 6 + barH/2),
                     size: 15, weight: .semibold, color: textColor.withAlphaComponent(0.85), monoDigits: true)
        }
        // 功率
        let pw = TelemetrySnapshot.formatPower(snapshot.powerWatts)
        drawText(pw, center: CGPoint(x: rect.midX, y: rect.minY + 6 + barH/2),
                 size: 17, weight: .bold, color: accent, monoDigits: true)
        // 右侧:连接状态 + 时间
        let connText = snapshot.antConnected ? "ANT" : (snapshot.bleConnected ? "BLE" : "--")
        let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
        drawText("\(connText) \(fmt.string(from: Date()))",
                 center: CGPoint(x: rect.maxX - 82, y: rect.minY + 6 + barH/2),
                 size: 15, weight: .semibold, color: textColor.withAlphaComponent(0.75), monoDigits: true)
    }
}
