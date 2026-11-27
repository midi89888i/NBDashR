import UIKit
import CoreGraphics

/// 极简高亮:超大高对比字号 · 强光直视清晰(原版副标题)
struct DaylightCleanTheme: DashboardThemeRenderer {
    let id = "daylightClean"
    let displayName = "极简高亮"
    let subtitle = "超大高对比字号 · 强光直视清晰"

    func draw(in ctx: CGContext, rect: CGRect, snapshot: TelemetrySnapshot, power: PowerReading) {
        // 纯黑底,超高对比
        ctx.fillBackground(.black, in: rect)

        // 巨大车速占主视觉
        ctx.drawText(String(format: "%.0f", snapshot.speedKmh),
                     center: CGPoint(x: rect.midX, y: rect.midY - 34),
                     size: 200, weight: .black, color: .white, monoDigits: true)
        ctx.drawText("km/h", center: CGPoint(x: rect.midX, y: rect.midY + 78),
                     size: 24, weight: .bold, color: .white)

        // 功率大字(放电白/回收绿)
        let pw = snapshot.powerWatts
        let pwColor: UIColor = (pw ?? 0) < -5 ? UIColor(red: 0.3, green: 1, blue: 0.4, alpha: 1) : .white
        ctx.drawText(TelemetrySnapshot.formatPower(pw),
                     center: CGPoint(x: rect.midX, y: rect.maxY - 92),
                     size: 44, weight: .black, color: pwColor, monoDigits: true)

        // 左上:电量超大
        let (pctText, _) = batteryText(snapshot)
        let pctColor: UIColor = {
            guard let p = snapshot.batteryPercent else { return .darkGray }
            return p > 20 ? .white : UIColor(red: 1, green: 0.25, blue: 0.2, alpha: 1)
        }()
        ctx.drawText(pctText, center: CGPoint(x: rect.minX + 130, y: 110),
                     size: 56, weight: .black, color: pctColor, monoDigits: true)
        if let volts = snapshot.batteryVoltage {
            ctx.drawText(String(format: "%.1f V", volts), center: CGPoint(x: rect.minX + 130, y: 152),
                         size: 22, weight: .bold, color: .lightGray, monoDigits: true)
        }

        // 右上:峰/回收
        ctx.drawText("峰 " + TelemetrySnapshot.formatPower(snapshot.peakPowerWatts > 0 ? snapshot.peakPowerWatts : nil),
                     center: CGPoint(x: rect.maxX - 160, y: 100), size: 24, weight: .bold, color: .white, monoDigits: true)
        ctx.drawText("回 " + TelemetrySnapshot.formatPower(snapshot.peakRegenWatts > 0 ? snapshot.peakRegenWatts : nil),
                     center: CGPoint(x: rect.maxX - 160, y: 140), size: 24, weight: .bold,
                     color: UIColor(red: 0.3, green: 1, blue: 0.4, alpha: 1), monoDigits: true)

        // 底部左右:里程 + 极速
        ctx.drawText(String(format: "%.1f km", snapshot.tripDistanceKm),
                     center: CGPoint(x: rect.minX + 140, y: rect.maxY - 40),
                     size: 28, weight: .black, color: .white, monoDigits: true)
        ctx.drawText("max " + String(format: "%.0f", snapshot.maxSpeedKmh),
                     center: CGPoint(x: rect.maxX - 140, y: rect.maxY - 40),
                     size: 28, weight: .black, color: .white, monoDigits: true)

        ctx.drawTopStatusBar(in: rect, snapshot: snapshot, bgColor: .black, textColor: .white, accent: .white)
    }
}
