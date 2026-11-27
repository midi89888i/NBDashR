import UIKit
import CoreGraphics

/// 超维引擎:曲速星流 · 反应堆速度环 · 随速旋转涡轮(原版副标题)
struct HyperdriveTheme: DashboardThemeRenderer {
    let id = "hyperdrive"
    let displayName = "超维引擎"
    let subtitle = "反应堆速度环 · 曲速星流"

    func draw(in ctx: CGContext, rect: CGRect, snapshot: TelemetrySnapshot, power: PowerReading) {
        // 深空底
        ctx.drawVerticalGradient(rect: rect, colors: [
            UIColor(red: 0.0, green: 0.0, blue: 0.06, alpha: 1),
            UIColor(red: 0.04, green: 0.0, blue: 0.14, alpha: 1),
        ])
        let plasma = UIColor(red: 0.4, green: 0.5, blue: 1, alpha: 1)
        let core = UIColor(red: 0.6, green: 0.9, blue: 1, alpha: 1)

        let cx = rect.midX, cy = rect.midY + 6
        // 反应堆多层环
        for (r, alpha) in [(170.0, 0.15), (150.0, 0.25)] as [(CGFloat, CGFloat)] {
            ctx.drawArc(center: CGPoint(x: cx, y: cy), radius: r, lineWidth: 2,
                        startDeg: 0, endDeg: 360, color: plasma.withAlphaComponent(alpha), lineCap: .butt)
        }
        // 速度环:满刻度 120
        let maxScale: Double = 120
        let speedFrac = min(1, snapshot.speedKmh / maxScale)
        ctx.drawArc(center: CGPoint(x: cx, y: cy), radius: 160, lineWidth: 12,
                    startDeg: -270, endDeg: 90, color: plasma.withAlphaComponent(0.2))
        if speedFrac > 0.005 {
            ctx.drawArc(center: CGPoint(x: cx, y: cy), radius: 160, lineWidth: 12,
                        startDeg: -270, endDeg: -270 + 360 * speedFrac, color: core)
        }
        // 功率能量轨(外圈)
        if power.outputFrac > 0.005 {
            ctx.drawArc(center: CGPoint(x: cx, y: cy), radius: 178, lineWidth: 5,
                        startDeg: -270, endDeg: -270 + 360 * power.outputFrac,
                        color: UIColor(red: 1, green: 0.4, blue: 0.7, alpha: 0.9))
        }
        if power.regenFrac > 0.005 {
            ctx.drawArc(center: CGPoint(x: cx, y: cy), radius: 178, lineWidth: 5,
                        startDeg: -270, endDeg: -270 + 360 * power.regenFrac,
                        color: .systemGreen)
        }

        // 中心车速
        ctx.drawText(String(format: "%.0f", snapshot.speedKmh), center: CGPoint(x: cx, y: cy - 14),
                     size: 110, weight: .heavy, color: .white, monoDigits: true)
        ctx.drawText("km/h · WARP", center: CGPoint(x: cx, y: cy + 52),
                     size: 15, weight: .semibold, color: plasma)

        // 曲速星流:速度驱动的放射线(视觉特效)
        if snapshot.speedKmh > 5 {
            ctx.setStrokeColor(core.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(1.5)
            let lineCount = min(24, Int(snapshot.speedKmh / 5))
            for i in 0..<lineCount {
                let angle = Double(i) * (2 * .pi / Double(lineCount)) + snapshot.tripDurationSec * speedFrac
                let r1: CGFloat = 195, r2 = r1 + 20 + 30 * speedFrac
                ctx.move(to: CGPoint(x: cx + cos(angle) * r1, y: cy + sin(angle) * r1))
                ctx.addLine(to: CGPoint(x: cx + cos(angle) * r2, y: cy + sin(angle) * r2))
            }
            ctx.strokePath()
        }

        // 左右舷窗数据
        drawPod(ctx, x: 30, y: 130, title: "能量输出", value: TelemetrySnapshot.formatPower(snapshot.powerWatts), color: core)
        drawPod(ctx, x: 30, y: 210, title: "输出峰值", value: TelemetrySnapshot.formatPower(snapshot.peakPowerWatts > 0 ? snapshot.peakPowerWatts : nil), color: .systemOrange)
        drawPod(ctx, x: rect.width - 220, y: 130, title: "回收功率", value: TelemetrySnapshot.formatPower(snapshot.powerWatts.map { $0 < 0 ? -$0 : 0 }), color: .systemGreen)
        drawPod(ctx, x: rect.width - 220, y: 210, title: "回收峰值", value: TelemetrySnapshot.formatPower(snapshot.peakRegenWatts > 0 ? snapshot.peakRegenWatts : nil), color: .systemGreen)

        // 底部行程面板
        let panelY = rect.height - 78
        ctx.fillRoundedRect(CGRect(x: rect.midX - 250, y: panelY, width: 500, height: 56),
                            radius: 14, color: plasma.withAlphaComponent(0.1))
        let cols: [(String, String)] = [
            ("航程", String(format: "%.1f km", snapshot.tripDistanceKm)),
            ("用时", snapshot.formattedDuration),
            ("极速", String(format: "%.0f", snapshot.maxSpeedKmh)),
            ("均速", String(format: "%.0f", snapshot.tripDurationSec > 10 ? snapshot.tripDistanceKm / (snapshot.tripDurationSec / 3600) : 0)),
        ]
        for (i, c) in cols.enumerated() {
            let x = rect.midX - 250 + 125 * CGFloat(i) + 62
            ctx.drawText(c.0, center: CGPoint(x: x, y: panelY + 16), size: 11, weight: .medium, color: plasma)
            ctx.drawText(c.1, center: CGPoint(x: x, y: panelY + 38), size: 16, weight: .bold, color: .white, monoDigits: true)
        }

        ctx.drawTopStatusBar(in: rect, snapshot: snapshot, bgColor: .black, textColor: .white, accent: core)
    }

    private func drawPod(_ ctx: CGContext, x: CGFloat, y: CGFloat, title: String, value: String, color: UIColor) {
        let r = CGRect(x: x, y: y, width: 190, height: 62)
        ctx.fillRoundedRect(r, radius: 12, color: UIColor.white.withAlphaComponent(0.06))
        ctx.drawText(title, center: CGPoint(x: r.midX, y: r.minY + 16), size: 12, weight: .medium,
                     color: UIColor(red: 0.4, green: 0.5, blue: 1, alpha: 1))
        ctx.drawText(value, center: CGPoint(x: r.midX, y: r.minY + 40), size: 20, weight: .bold, color: color, monoDigits: true)
    }
}
