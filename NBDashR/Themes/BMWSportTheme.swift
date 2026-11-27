import UIKit
import CoreGraphics

/// 仿宝马 TFT 运动仪表:150pt 主车速,双弧功率表,全宽速度带(原版副标题:仿宝马 TFT 运动仪表 · 150pt 主车速 · 全宽速度带)
struct BMWSportTheme: DashboardThemeRenderer {
    let id = "bmwSport"
    let displayName = "运动仪表"
    let subtitle = "仿宝马 TFT · 功率双弧 · 全宽速度带"

    func draw(in ctx: CGContext, rect: CGRect, snapshot: TelemetrySnapshot, power: PowerReading) {
        // 深色底 + 顶部微渐变
        ctx.drawVerticalGradient(rect: rect, colors: [
            UIColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 1),
            UIColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1),
        ])

        // 中央大车速
        let cx = rect.midX, cy = rect.midY + 10
        let speedText = snapshot.speedKmh < 0.1 ? "0" : String(format: "%.0f", snapshot.speedKmh)
        ctx.drawText(speedText, center: CGPoint(x: cx, y: cy - 24),
                     size: 150, weight: .heavy, color: .white, monoDigits: true)
        ctx.drawText("km/h", center: CGPoint(x: cx, y: cy + 62),
                     size: 20, weight: .medium, color: .lightGray)

        // 功率双弧:左半输出(青色→红),右半回收(绿)
        let arcCenter = CGPoint(x: cx, y: cy - 10)
        let radius: CGFloat = 170
        // 背景弧
        ctx.drawArc(center: arcCenter, radius: radius, lineWidth: 14,
                    startDeg: -210, endDeg: 30, color: UIColor.darkGray.withAlphaComponent(0.5))
        // 输出弧
        if power.outputFrac > 0.005 {
            let endDeg = -210 + 240 * power.outputFrac
            let color: UIColor = power.outputFrac < 0.5 ? .systemCyan : power.outputFrac < 0.8 ? .systemOrange : .systemRed
            ctx.drawArc(center: arcCenter, radius: radius, lineWidth: 14,
                        startDeg: -210, endDeg: endDeg, color: color)
        }
        // 回收弧(内圈)
        ctx.drawArc(center: arcCenter, radius: radius - 22, lineWidth: 8,
                    startDeg: -210, endDeg: -30, color: UIColor.darkGray.withAlphaComponent(0.4))
        if power.regenFrac > 0.005 {
            ctx.drawArc(center: arcCenter, radius: radius - 22, lineWidth: 8,
                        startDeg: -210, endDeg: -210 + 180 * power.regenFrac, color: .systemGreen)
        }

        // 功率数值与等级
        let ptext = TelemetrySnapshot.formatPower(snapshot.powerWatts)
        ctx.drawText(ptext, center: CGPoint(x: cx, y: cy - 130),
                     size: 34, weight: .bold, color: power.level.color, monoDigits: true)
        ctx.drawText(power.level.tag, center: CGPoint(x: cx + 118, y: cy + 62),
                     size: 15, weight: .bold, color: power.level.color)

        // 左右数据胶囊
        drawCapsule(ctx, x: 26, y: rect.midY - 66, title: "峰值", value: TelemetrySnapshot.formatPower(snapshot.peakPowerWatts > 0 ? snapshot.peakPowerWatts : nil), color: .systemOrange)
        drawCapsule(ctx, x: 26, y: rect.midY + 2, title: "回收峰", value: TelemetrySnapshot.formatPower(snapshot.peakRegenWatts > 0 ? snapshot.peakRegenWatts : nil), color: .systemGreen)
        drawCapsule(ctx, x: rect.width - 152, y: rect.midY - 66, title: "极速", value: String(format: "%.0f", snapshot.maxSpeedKmh), color: .systemRed)
        drawCapsule(ctx, x: rect.width - 152, y: rect.midY + 2, title: "里程", value: String(format: "%.1f km", snapshot.tripDistanceKm), color: .systemTeal)

        // 底部全宽速度带
        let bandRect = CGRect(x: 0, y: rect.height - 54, width: rect.width, height: 54)
        ctx.fillRect(bandRect, color: UIColor.black.withAlphaComponent(0.55))
        let maxScale = max(60, ceil(snapshot.maxSpeedKmh / 10) * 10)
        // 刻度
        for v in stride(from: 0.0, through: maxScale, by: 10) {
            let x = bandRect.minX + CGFloat(v / maxScale) * bandRect.width
            ctx.drawLine(from: CGPoint(x: x, y: bandRect.minY), to: CGPoint(x: x, y: bandRect.minY + 10),
                         color: .darkGray, width: 2)
            ctx.drawText(String(format: "%.0f", v), center: CGPoint(x: x, y: bandRect.minY + 22),
                         size: 11, weight: .medium, color: .gray, monoDigits: true)
        }
        // 当前速度填充
        let frac = min(1, snapshot.speedKmh / maxScale)
        ctx.fillRect(CGRect(x: bandRect.minX, y: bandRect.maxY - 12, width: bandRect.width * frac, height: 12),
                     color: .systemCyan)
        // 速度历史曲线
        if snapshot.speedHistory.count > 2 {
            ctx.setStrokeColor(UIColor.systemCyan.withAlphaComponent(0.4).cgColor)
            ctx.setLineWidth(1.5)
            let n = snapshot.speedHistory.count
            for (i, v) in snapshot.speedHistory.enumerated() {
                let x = bandRect.maxX - CGFloat(n - 1 - i) * (bandRect.width / 60)
                let y = bandRect.maxY - 12 - min(1, v / maxScale) * 26
                if i == 0 { ctx.move(to: CGPoint(x: x, y: y)) } else { ctx.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.strokePath()
        }

        ctx.drawTopStatusBar(in: rect, snapshot: snapshot,
                             bgColor: .black, textColor: .white, accent: .systemCyan)
    }

    private func drawCapsule(_ ctx: CGContext, x: CGFloat, y: CGFloat, title: String, value: String, color: UIColor) {
        let r = CGRect(x: x, y: y, width: 126, height: 58)
        ctx.fillRoundedRect(r, radius: 12, color: UIColor.white.withAlphaComponent(0.08))
        ctx.drawText(title, center: CGPoint(x: r.midX, y: r.minY + 15), size: 12, weight: .medium, color: .gray)
        ctx.drawText(value, center: CGPoint(x: r.midX, y: r.minY + 38), size: 17, weight: .bold, color: color, monoDigits: true)
    }
}
