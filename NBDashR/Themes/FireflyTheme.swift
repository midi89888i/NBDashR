import UIKit
import CoreGraphics

/// 流萤 · 萨姆:萤火燃烧特效 + 速度反应堆(致敬原版崩铁彩蛋,无版权素材的抽象重绘)
struct FireflyTheme: DashboardThemeRenderer {
    let id = "firefly"
    let displayName = "流萤"
    let subtitle = "萤火燃烧 · 速度反应堆"

    func draw(in ctx: CGContext, rect: CGRect, snapshot: TelemetrySnapshot, power: PowerReading) {
        // 萤火绿渐变底
        ctx.drawVerticalGradient(rect: rect, colors: [
            UIColor(red: 0.0, green: 0.05, blue: 0.03, alpha: 1),
            UIColor(red: 0.0, green: 0.12, blue: 0.07, alpha: 1),
        ])
        let firefly = UIColor(red: 0.5, green: 1, blue: 0.6, alpha: 1)
        let ember = UIColor(red: 1, green: 0.75, blue: 0.3, alpha: 1)

        let cx = rect.midX, cy = rect.midY + 4
        // 反应堆核心:发光同心圆(随功率脉动)
        let pulse = 1 + 0.06 * sin(snapshot.tripDurationSec * 3) * CGFloat(min(1, power.outputFrac + 0.2))
        for (r, a) in [(110.0, 0.08), (85.0, 0.14), (60.0, 0.2)] as [(CGFloat, CGFloat)] {
            ctx.fillCircle(center: CGPoint(x: cx, y: cy), radius: r * pulse, color: firefly.withAlphaComponent(a))
        }
        // 中心车速
        ctx.drawText(String(format: "%.0f", snapshot.speedKmh), center: CGPoint(x: cx, y: cy - 8),
                     size: 96, weight: .heavy, color: .white, monoDigits: true)
        ctx.drawText("FIREFLY", center: CGPoint(x: cx, y: cy + 44), size: 14, weight: .bold, color: firefly)

        // 萤火粒子:数量随速度,绕反应堆旋转漂浮
        let particleCount = min(28, 6 + Int(snapshot.speedKmh / 4))
        ctx.setFillColor(firefly.withAlphaComponent(0.75).cgColor)
        for i in 0..<particleCount {
            let seed = Double(i * 137 % 97) / 97.0
            let angle = seed * 2 * .pi + snapshot.tripDurationSec * (0.3 + seed * 0.5)
            let r = 140 + 60 * sin(seed * 10 + snapshot.tripDurationSec * 0.8)
            let x = cx + cos(angle) * r * 1.3
            let y = cy + sin(angle) * r * 0.75
            let size: CGFloat = 2.5 + 2.5 * sin(seed * 20 + snapshot.tripDurationSec * 2)
            ctx.fillCircle(center: CGPoint(x: x, y: y), radius: max(1, size), color: firefly.withAlphaComponent(0.6))
        }

        // 燃烧丝带:功率驱动的弧
        if power.outputFrac > 0.005 {
            for i in 0..<3 {
                let offset = CGFloat(i) * 8
                ctx.drawArc(center: CGPoint(x: cx, y: cy), radius: 130 + offset, lineWidth: 3,
                            startDeg: -200 + CGFloat(i) * 20,
                            endDeg: -200 + CGFloat(i) * 20 + 240 * power.outputFrac,
                            color: ember.withAlphaComponent(0.8 - Double(i) * 0.2))
            }
        }
        if power.regenFrac > 0.005 {
            ctx.drawArc(center: CGPoint(x: cx, y: cy), radius: 145, lineWidth: 4,
                        startDeg: -270, endDeg: -270 + 360 * power.regenFrac, color: firefly)
        }

        // 左侧栖息舱:功率数值
        let podL = CGRect(x: 30, y: 140, width: 190, height: 130)
        ctx.fillRoundedRect(podL, radius: 16, color: firefly.withAlphaComponent(0.08))
        ctx.drawText("输出功率", center: CGPoint(x: podL.midX, y: podL.minY + 20), size: 13, weight: .medium, color: firefly)
        ctx.drawText(TelemetrySnapshot.formatPower(snapshot.powerWatts),
                     center: CGPoint(x: podL.midX, y: podL.minY + 58), size: 32, weight: .bold, color: .white, monoDigits: true)
        ctx.drawText(power.level.tag, center: CGPoint(x: podL.midX, y: podL.minY + 96), size: 14, weight: .bold, color: power.level.color)

        // 右侧栖息舱:峰值/回收
        let podR = CGRect(x: rect.width - 220, y: 140, width: 190, height: 130)
        ctx.fillRoundedRect(podR, radius: 16, color: ember.withAlphaComponent(0.08))
        ctx.drawText("峰值 / 回收", center: CGPoint(x: podR.midX, y: podR.minY + 20), size: 13, weight: .medium, color: ember)
        ctx.drawText(TelemetrySnapshot.formatPower(snapshot.peakPowerWatts > 0 ? snapshot.peakPowerWatts : nil),
                     center: CGPoint(x: podR.midX, y: podR.minY + 56), size: 22, weight: .bold, color: .white, monoDigits: true)
        ctx.drawText(TelemetrySnapshot.formatPower(snapshot.peakRegenWatts > 0 ? snapshot.peakRegenWatts : nil),
                     center: CGPoint(x: podR.midX, y: podR.minY + 94), size: 22, weight: .bold, color: firefly, monoDigits: true)

        // 底部停靠坞:遥测格
        let dockY = rect.height - 84
        let cells: [(String, String)] = [
            ("航程", String(format: "%.1fkm", snapshot.tripDistanceKm)),
            ("极速", String(format: "%.0f", snapshot.maxSpeedKmh)),
            ("倾角", String(format: "%.0f°", snapshot.leanAngleDeg)),
            ("用时", snapshot.formattedDuration),
        ]
        let cw: CGFloat = 150
        for (i, c) in cells.enumerated() {
            let x = rect.midX - cw * 2 + cw * CGFloat(i)
            ctx.fillRoundedRect(CGRect(x: x + 4, y: dockY, width: cw - 8, height: 56), radius: 12,
                                color: firefly.withAlphaComponent(0.07))
            ctx.drawText(c.0, center: CGPoint(x: x + cw/2, y: dockY + 16), size: 11, weight: .medium, color: firefly)
            ctx.drawText(c.1, center: CGPoint(x: x + cw/2, y: dockY + 38), size: 16, weight: .bold, color: .white, monoDigits: true)
        }

        ctx.drawTopStatusBar(in: rect, snapshot: snapshot, bgColor: .black, textColor: .white, accent: firefly)
    }
}
