import UIKit
import CoreGraphics

/// 赛道遥测:双弧速度表 · 电机功率 · 速度曲线(原版副标题)
struct TrackProTheme: DashboardThemeRenderer {
    let id = "trackPro"
    let displayName = "赛道遥测"
    let subtitle = "双弧速度表 · 电机功率 · 速度曲线"

    func draw(in ctx: CGContext, rect: CGRect, snapshot: TelemetrySnapshot, power: PowerReading) {
        ctx.fillBackground(UIColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1), in: rect)
        let amber = UIColor(red: 1, green: 0.7, blue: 0.1, alpha: 1)

        // 左侧双弧速度表
        let cx = rect.minX + 240, cy = rect.midY + 10
        let maxScale: Double = max(80, ceil(snapshot.maxSpeedKmh / 20) * 20)
        // 外弧底
        ctx.drawArc(center: CGPoint(x: cx, y: cy), radius: 150, lineWidth: 18,
                    startDeg: -225, endDeg: 45, color: UIColor.darkGray.withAlphaComponent(0.5))
        let frac = min(1, snapshot.speedKmh / maxScale)
        if frac > 0.005 {
            let color: UIColor = frac < 0.6 ? amber : frac < 0.85 ? .systemOrange : .systemRed
            ctx.drawArc(center: CGPoint(x: cx, y: cy), radius: 150, lineWidth: 18,
                        startDeg: -225, endDeg: -225 + 270 * frac, color: color)
        }
        // 刻度数字
        for v in stride(from: 0.0, through: maxScale, by: maxScale / 6) {
            let angle = (-225 + 270 * v / maxScale - 90) * .pi / 180
            let tx = cx + cos(angle) * 118, ty = cy + sin(angle) * 118
            ctx.drawText(String(format: "%.0f", v), center: CGPoint(x: tx, y: ty),
                         size: 13, weight: .semibold, color: .gray, monoDigits: true)
        }
        // 内弧:功率
        ctx.drawArc(center: CGPoint(x: cx, y: cy), radius: 92, lineWidth: 10,
                    startDeg: -225, endDeg: 45, color: UIColor.darkGray.withAlphaComponent(0.4))
        if power.outputFrac > 0.005 {
            ctx.drawArc(center: CGPoint(x: cx, y: cy), radius: 92, lineWidth: 10,
                        startDeg: -225, endDeg: -225 + 270 * power.outputFrac, color: .systemCyan)
        }
        if power.regenFrac > 0.005 {
            ctx.drawArc(center: CGPoint(x: cx, y: cy), radius: 92, lineWidth: 10,
                        startDeg: -225, endDeg: -225 + 270 * power.regenFrac, color: .systemGreen)
        }

        ctx.drawText(String(format: "%.0f", snapshot.speedKmh), center: CGPoint(x: cx, y: cy - 8),
                     size: 92, weight: .black, color: .white, monoDigits: true)
        ctx.drawText("km/h", center: CGPoint(x: cx, y: cy + 46), size: 16, weight: .medium, color: .lightGray)
        ctx.drawText(power.level.tag, center: CGPoint(x: cx, y: cy + 76),
                     size: 14, weight: .bold, color: power.level.color)

        // 右侧遥测列
        let tx = rect.width - 360
        var ty: CGFloat = 100
        telemetryRow(ctx, x: tx, y: ty, label: "实时功率", value: TelemetrySnapshot.formatPower(snapshot.powerWatts), color: .systemCyan); ty += 62
        telemetryRow(ctx, x: tx, y: ty, label: "峰值功率", value: TelemetrySnapshot.formatPower(snapshot.peakPowerWatts > 0 ? snapshot.peakPowerWatts : nil), color: .systemOrange); ty += 62
        telemetryRow(ctx, x: tx, y: ty, label: "回收峰值", value: TelemetrySnapshot.formatPower(snapshot.peakRegenWatts > 0 ? snapshot.peakRegenWatts : nil), color: .systemGreen); ty += 62
        telemetryRow(ctx, x: tx, y: ty, label: "极速 / 里程", value: String(format: "%.0f · %.1fkm", snapshot.maxSpeedKmh, snapshot.tripDistanceKm), color: amber); ty += 62
        telemetryRow(ctx, x: tx, y: ty, label: "倾角 L/R", value: String(format: "%.0f°/%.0f°", snapshot.maxLeftLeanDeg, snapshot.maxRightLeanDeg), color: .systemTeal)

        // 底部速度曲线
        let chartRect = CGRect(x: 30, y: rect.height - 88, width: rect.width - 60, height: 56)
        ctx.fillRoundedRect(chartRect, radius: 10, color: UIColor.white.withAlphaComponent(0.05))
        if snapshot.speedHistory.count > 2 {
            ctx.saveGState()
            ctx.clip(to: chartRect.insetBy(dx: 4, dy: 4))
            ctx.setStrokeColor(amber.cgColor)
            ctx.setLineWidth(2)
            let n = snapshot.speedHistory.count
            let maxV = max(20, snapshot.speedHistory.max() ?? 20)
            for (i, v) in snapshot.speedHistory.enumerated() {
                let x = chartRect.minX + 4 + CGFloat(i) / CGFloat(max(1, n - 1)) * (chartRect.width - 8)
                let y = chartRect.maxY - 4 - (v / maxV) * (chartRect.height - 12)
                if i == 0 { ctx.move(to: CGPoint(x: x, y: y)) } else { ctx.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
        ctx.drawText("速度曲线 · 60s", center: CGPoint(x: chartRect.minX + 60, y: chartRect.minY - 10),
                     size: 11, weight: .medium, color: .gray)

        ctx.drawTopStatusBar(in: rect, snapshot: snapshot, bgColor: .black, textColor: .white, accent: amber)
    }

    private func telemetryRow(_ ctx: CGContext, x: CGFloat, y: CGFloat, label: String, value: String, color: UIColor) {
        ctx.fillRoundedRect(CGRect(x: x, y: y, width: 330, height: 52), radius: 10,
                            color: UIColor.white.withAlphaComponent(0.06))
        ctx.drawText(label, center: CGPoint(x: x + 14, y: y + 26), size: 13, weight: .medium, color: .gray, align: .left)
        ctx.drawText(value, center: CGPoint(x: x + 316, y: y + 26), size: 21, weight: .bold, color: color, monoDigits: true, align: .right)
    }
}
