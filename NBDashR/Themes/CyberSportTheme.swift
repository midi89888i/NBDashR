import UIKit
import CoreGraphics

/// 赛博竞技:顶部转速条 · 实时功率 · 赛用遥测(原版副标题)
struct CyberSportTheme: DashboardThemeRenderer {
    let id = "cyberSport"
    let displayName = "赛博竞技"
    let subtitle = "顶部转速条 · 实时功率 · 赛用遥测"

    func draw(in ctx: CGContext, rect: CGRect, snapshot: TelemetrySnapshot, power: PowerReading) {
        ctx.drawVerticalGradient(rect: rect, colors: [
            UIColor(red: 0.03, green: 0.0, blue: 0.08, alpha: 1),
            UIColor(red: 0.08, green: 0.02, blue: 0.16, alpha: 1),
        ])
        let neonPink = UIColor(red: 1, green: 0.2, blue: 0.6, alpha: 1)
        let neonCyan = UIColor(red: 0.1, green: 0.9, blue: 1, alpha: 1)

        // 顶部转速条(功率输出占比,全宽)
        let barRect = CGRect(x: 20, y: 52, width: rect.width - 40, height: 16)
        ctx.fillRoundedRect(barRect, radius: 8, color: UIColor.white.withAlphaComponent(0.1))
        if power.outputFrac > 0.005 {
            let w = barRect.width * power.outputFrac
            ctx.fillRoundedRect(CGRect(x: barRect.minX, y: barRect.minY, width: w, height: barRect.height),
                                radius: 8, color: power.outputFrac > 0.75 ? neonPink : neonCyan)
        }
        // 转速条刻度
        for i in 0...10 {
            let x = barRect.minX + barRect.width * CGFloat(i) / 10
            ctx.drawLine(from: CGPoint(x: x, y: barRect.maxY + 2), to: CGPoint(x: x, y: barRect.maxY + 7),
                         color: .darkGray, width: 1.5)
        }

        // 左侧大车速(斜体感:用粗斜体字重近似)
        let speedText = String(format: "%.0f", snapshot.speedKmh)
        ctx.drawText(speedText, center: CGPoint(x: rect.minX + 170, y: rect.midY + 2),
                     size: 130, weight: .black, color: .white, monoDigits: true)
        ctx.drawText("KM/H", center: CGPoint(x: rect.minX + 170, y: rect.midY + 78),
                     size: 17, weight: .bold, color: neonCyan)

        // 右侧实时功率卡
        let cardRect = CGRect(x: rect.width - 300, y: 110, width: 270, height: 130)
        ctx.fillRoundedRect(cardRect, radius: 16, color: UIColor.white.withAlphaComponent(0.07))
        ctx.strokePill(rect: cardRect, color: neonCyan.withAlphaComponent(0.5), lineWidth: 1.5, cornerRadius: 16)
        ctx.drawText("实时功率", center: CGPoint(x: cardRect.midX, y: cardRect.minY + 22),
                     size: 14, weight: .semibold, color: .lightGray)
        let pw = snapshot.powerWatts
        let pwColor: UIColor = (pw ?? 0) < -5 ? .systemGreen : neonPink
        ctx.drawText(TelemetrySnapshot.formatPower(pw), center: CGPoint(x: cardRect.midX, y: cardRect.minY + 62),
                     size: 40, weight: .black, color: pwColor, monoDigits: true)
        ctx.drawText(power.level.tag, center: CGPoint(x: cardRect.midX, y: cardRect.minY + 102),
                     size: 15, weight: .bold, color: power.level.color)

        // 回收指示
        if power.isRegen {
            ctx.drawText("⚡ 能量回收", center: CGPoint(x: cardRect.midX, y: cardRect.maxY + 16),
                         size: 14, weight: .bold, color: .systemGreen)
        }

        // 底部赛用遥测行:峰值/回收峰/倾角/G值/极速/里程
        let statsY = rect.height - 92
        let items: [(String, String, UIColor)] = [
            ("峰值功率", TelemetrySnapshot.formatPower(snapshot.peakPowerWatts > 0 ? snapshot.peakPowerWatts : nil), neonPink),
            ("回收峰值", TelemetrySnapshot.formatPower(snapshot.peakRegenWatts > 0 ? snapshot.peakRegenWatts : nil), .systemGreen),
            ("倾角", String(format: "%.0f°", snapshot.leanAngleDeg), neonCyan),
            ("纵向G", String(format: "%.2f", snapshot.longitudinalG), .systemYellow),
            ("极速", String(format: "%.0f", snapshot.maxSpeedKmh), .systemRed),
            ("里程", String(format: "%.1fkm", snapshot.tripDistanceKm), .systemTeal),
        ]
        let cellW = (rect.width - 40) / 6
        for (i, item) in items.enumerated() {
            let x = 20 + cellW * CGFloat(i)
            ctx.drawText(item.0, center: CGPoint(x: x + cellW/2, y: statsY), size: 12, weight: .medium, color: .gray)
            ctx.drawText(item.1, center: CGPoint(x: x + cellW/2, y: statsY + 24), size: 17, weight: .bold,
                         color: item.2, monoDigits: true)
        }
        // 分隔线
        ctx.drawLine(from: CGPoint(x: 20, y: statsY - 22), to: CGPoint(x: rect.width - 20, y: statsY - 22),
                     color: neonCyan.withAlphaComponent(0.3), width: 1)

        ctx.drawTopStatusBar(in: rect, snapshot: snapshot, bgColor: .black, textColor: .white, accent: neonCyan)
    }
}
