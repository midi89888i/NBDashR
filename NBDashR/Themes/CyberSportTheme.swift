import Foundation
import UIKit
import CoreGraphics

/// 「赛博竞技」主题 —— 由 cyber.txt (996 条 ARM64 指令) 反汇编翻译还原。
/// 848×480 画布,深色网格背景 + 中央速度/功率组合仪表 + 底部纵向 G 条与遥测卡片。
struct CyberSportTheme: DashboardThemeRenderer {
    let id = "cyberSport"
    let displayName = "赛博竞技"
    let subtitle = "顶部转速条 · 实时功率 · 赛用遥测"

    // MARK: - 配色(cyber 青色系,分量取自反汇编 0-255 常量 / 255)
    private let cyan      = UIColor(red: 0/255.0,   green: 228/255.0, blue: 255/255.0, alpha: 1)  // 主青色 (0,228,255)
    private let cyanSoft  = UIColor(red: 145/255.0, green: 225/255.0, blue: 255/255.0, alpha: 1)  // 浅青 (145,225,255)
    private let deepBlue  = UIColor(red: 82/255.0,  green: 185/255.0, blue: 255/255.0, alpha: 1)  // 中段蓝 (82,185,255)
    private let warn      = UIColor(red: 255/255.0, green: 185/255.0, blue: 62/255.0,  alpha: 1)  // 高功率黄
    private let hot       = UIColor(red: 255/255.0, green: 82/255.0,  blue: 82/255.0,  alpha: 1)  // 极限红
    private let regenGrn  = UIColor(red: 80/255.0,  green: 255/255.0, blue: 160/255.0, alpha: 1)  // 回收绿
    private let gridLine  = UIColor(red: 120/255.0, green: 180/255.0, blue: 255/255.0, alpha: 0.10) // 网格线 (120,180,255) 低 alpha
    private let bg        = UIColor(red: 0.008, green: 0.014, blue: 0.024, alpha: 1)              // 近黑深蓝底
    private let white     = UIColor(white: 1, alpha: 0.96)
    private let muted     = UIColor(white: 1, alpha: 0.45)
    private let cardFill  = UIColor(red: 0.02, green: 0.05, blue: 0.09, alpha: 0.72)
    private let cardEdge  = UIColor(red: 0/255.0, green: 228/255.0, blue: 255/255.0, alpha: 0.28)

    // MARK: - 仪表几何(反汇编常量)
    // 表盘中心 (416,276);外弧半径 163..180;刻度半径 135;指针根 148 附近
    private let gaugeCenter = CGPoint(x: 416, y: 276)
    private let arcOuterR: CGFloat = 180    // 弧外半径(=180.0)
    private let arcInnerR: CGFloat = 163  // 弧内半径(=163.0)
    private let tickR:     CGFloat = 135  // 刻度半径(=135.0)
    private let needleLen: CGFloat = 125  // 指针长(148 为外端参考,略收)
    private let sweepStart: CGFloat = 145  // 扫描起点角度(=145.0,0=正上顺时针)
    private let sweepTotal: CGFloat = 250  // 扫描总角度(=250.0)
    private let segCount = 40  // 分段数(循环计数 40)

    func draw(in ctx: CGContext, rect: CGRect, snapshot: TelemetrySnapshot, power: PowerReading) {
        drawBackground(ctx, rect)
        // 顶部状态条(原版为独立状态胶囊:电量/电压/功率/连接)
        ctx.drawTopStatusBar(in: rect, snapshot: snapshot,
                             bgColor: bg, textColor: white, accent: cyan)
        drawPowerArc(ctx, power: power)
        drawSpeedTicks(ctx, snapshot: snapshot)
        drawNeedle(ctx, snapshot: snapshot)
        drawSpeedReadout(ctx, snapshot: snapshot)
        drawGForceBar(ctx, snapshot: snapshot)
        drawMetricCards(ctx, rect: rect, snapshot: snapshot, power: power)
    }

    // MARK: - 背景:近黑底 + 每 32px 的青色网格线(循环 13 次,y 64→448)
    private func drawBackground(_ ctx: CGContext, _ rect: CGRect) {
        ctx.fillBackground(bg, in: rect)
        var y: CGFloat = 64
        while y <= 448 {
            ctx.drawLine(from: CGPoint(x: 0, y: y), to: CGPoint(x: 848, y: y),
                         color: gridLine, width: 1)
            y += 32
        }
        var x: CGFloat = 64
        while x <= 848 {
            ctx.drawLine(from: CGPoint(x: x, y: 48), to: CGPoint(x: x, y: 480),
                         color: gridLine.withAlphaComponent(0.06), width: 1)
            x += 64
        }
    }

    // MARK: - 顶部转速/功率分段弧:40 段,145°→395°,按功率分级着色
    private func drawPowerArc(_ ctx: CGContext, power: PowerReading) {
        let litFrac: CGFloat
        let baseColor: UIColor
        if power.isRegen {
            litFrac = CGFloat(power.regenFrac)
            baseColor = regenGrn
        } else {
            litFrac = CGFloat(power.outputFrac)
            switch power.level {
            case .max:            baseColor = hot
            case .boost:          baseColor = warn
            case .sport:          baseColor = deepBlue
            case .eco:            baseColor = cyan
            case .regen:          baseColor = regenGrn
            case .idle, .unavailable: baseColor = cyanSoft
            }
        }
        let span = sweepTotal / CGFloat(segCount)   // 6.25°/段
        let mid = (arcInnerR + arcOuterR) / 2
        let lw = arcOuterR - arcInnerR - 2
        for i in 0..<segCount {
            let start = sweepStart + CGFloat(i) * span + 0.6
            let end = start + span - 1.2
            let lit = CGFloat(i) < litFrac * CGFloat(segCount)
            let color = lit ? baseColor : baseColor.withAlphaComponent(0.14)
            ctx.drawArc(center: gaugeCenter, radius: mid, lineWidth: lw,
                        startDeg: start, endDeg: end, color: color)
        }
        // 外圈细环
        ctx.drawArc(center: gaugeCenter, radius: arcOuterR + 4, lineWidth: 1.5,
                    startDeg: sweepStart, endDeg: sweepStart + sweepTotal,
                    color: cyan.withAlphaComponent(0.35))
    }

    // MARK: - 速度刻度:半径 135,每 5 km/h 一格,每 20 标数
    private func speedScale(_ snapshot: TelemetrySnapshot) -> Double {
        let vmax = max(60, snapshot.maxSpeedKmh, snapshot.speedKmh)
        return (vmax / 20).rounded(.up) * 20   // 向上取整到 20 的倍数
    }

    private func angleForSpeed(_ v: Double, scale: Double) -> CGFloat {
        let frac = min(max(v / scale, 0), 1)
        return sweepStart + CGFloat(frac) * sweepTotal
    }

    private func pointOn(_ center: CGPoint, _ r: CGFloat, _ deg: CGFloat) -> CGPoint {
        let a = (deg - 90) * .pi / 180
        return CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
    }

    private func drawSpeedTicks(_ ctx: CGContext, snapshot: TelemetrySnapshot) {
        let scale = speedScale(snapshot)
        let step = 5.0
        var v = 0.0
        while v <= scale + 0.01 {
            let deg = angleForSpeed(v, scale: scale)
            let major = Int(v) % 20 == 0
            let outer = pointOn(gaugeCenter, tickR, deg)
            let inner = pointOn(gaugeCenter, tickR - (major ? 12 : 7), deg)
            ctx.drawLine(from: inner, to: outer,
                         color: major ? cyan.withAlphaComponent(0.85) : cyan.withAlphaComponent(0.35),
                         width: major ? 2 : 1)
            if major {
                let lp = pointOn(gaugeCenter, tickR - 26, deg)
                ctx.drawText("\(Int(v))", center: lp, size: 13, weight: .semibold,
                             color: cyanSoft.withAlphaComponent(0.8), monoDigits: true)
            }
            v += step
        }
    }

    // MARK: - 指针:颜色随速度占比变化(青→蓝→红),尾端带配重
    private func drawNeedle(_ ctx: CGContext, snapshot: TelemetrySnapshot) {
        let scale = speedScale(snapshot)
        let frac = snapshot.speedKmh / scale
        let deg = angleForSpeed(snapshot.speedKmh, scale: scale)
        // 条件着色:低 (0,228,255),中 (82,185,255) 偏蓝,高段转红
        let color: UIColor
        if frac < 0.5 { color = cyan }
        else if frac < 0.8 { color = warn }
        else { color = hot }
        let tip = pointOn(gaugeCenter, needleLen, deg)
        let tail = pointOn(gaugeCenter, -22, deg)
        ctx.drawLine(from: tail, to: tip, color: color, width: 5)
        ctx.fillCircle(center: gaugeCenter, radius: 9, color: color)
        ctx.fillCircle(center: gaugeCenter, radius: 4, color: bg)
    }

    // MARK: - 中央读数:大号速度 (416,270) + "KM / H" (416,338)
    private func drawSpeedReadout(_ ctx: CGContext, snapshot: TelemetrySnapshot) {
        let v = Int(snapshot.speedKmh.rounded())
        ctx.drawText("\(v)", center: CGPoint(x: 416, y: 262),
                     size: 96, weight: .bold, color: white, monoDigits: true)
        ctx.drawText("KM / H", center: CGPoint(x: 416, y: 338),
                     size: 22, weight: .semibold, color: cyan, monoDigits: false)
    }

    // MARK: - 纵向 G 条:y≈375 居中 x=416,加速青 / 制动红,两端 BRK / ACC 标签
    private func drawGForceBar(_ ctx: CGContext, snapshot: TelemetrySnapshot) {
        let cy: CGFloat = 375
        let cx: CGFloat = 416
        let halfW: CGFloat = 86      // 86 px/G(=86.0 比例系数)
        // 基线
        ctx.drawLine(from: CGPoint(x: cx - halfW - 24, y: cy),
                     to: CGPoint(x: cx + halfW + 24, y: cy),
                     color: cyan.withAlphaComponent(0.25), width: 3)
        let g = snapshot.longitudinalG
        let mag = CGFloat(min(abs(g), 1.0)) * halfW
        if mag > 2 {
            // 正 = 加速(青色 145,225,255),负 = 制动(红)
            let accel = g > 0
            let color = accel ? cyanSoft : hot
            let x0 = accel ? cx : cx - mag
            ctx.fillRoundedRect(CGRect(x: x0, y: cy - 5, width: mag, height: 10),
                                radius: 5, color: color)
        }
        ctx.fillCircle(center: CGPoint(x: cx, y: cy), radius: 4, color: white)
        ctx.drawText("BRK", center: CGPoint(x: 324, y: 380),
                     size: 16, weight: .bold, color: hot.withAlphaComponent(0.9), monoDigits: true)
        ctx.drawText("ACC", center: CGPoint(x: 508, y: 380),
                     size: 16, weight: .bold, color: cyanSoft.withAlphaComponent(0.9), monoDigits: true)
    }

    // MARK: - 底部三张遥测卡片(CyberMetricRow: label/value/color)
    private struct Row {
        let label: String
        let value: String
        let color: UIColor
    }

    private func drawMetricCards(_ ctx: CGContext, rect: CGRect,
                                 snapshot: TelemetrySnapshot, power: PowerReading) {
        let rows: [Row] = [
            Row(label: "行程", value: String(format: "%.1f km", snapshot.tripDistanceKm), color: cyanSoft),
            Row(label: "实时功率", value: TelemetrySnapshot.formatPower(power.watts), color: power.isRegen ? regenGrn : cyan),
            Row(label: "峰值 / 回收", value: peakText(snapshot), color: warn),
        ]
        let cardW: CGFloat = 204
        let cardH: CGFloat = 90
        let y: CGFloat = 404
        let centers: [CGFloat] = [150, 424, 698]
        for (i, row) in rows.enumerated() {
            let cx = centers[i]
            let card = CGRect(x: cx - cardW/2, y: y, width: cardW, height: cardH)
            ctx.fillRoundedRect(card, radius: 12, color: cardFill)
            ctx.strokePill(rect: card, color: cardEdge, lineWidth: 1, cornerRadius: 12)
            // 顶部小色条
            ctx.fillRoundedRect(CGRect(x: card.minX + 12, y: card.minY + 8, width: 28, height: 3),
                                radius: 1.5, color: row.color)
            ctx.drawText(row.label, center: CGPoint(x: card.minX + 14, y: card.minY + 28),
                         size: 13, weight: .medium, color: muted, align: .left)
            ctx.drawText(row.value, center: CGPoint(x: card.midX, y: card.minY + 58),
                         size: 24, weight: .bold, color: row.color, monoDigits: true)
        }
    }

    private func peakText(_ snapshot: TelemetrySnapshot) -> String {
        if snapshot.peakPowerWatts >= 1000 || snapshot.peakRegenWatts >= 1000 {
            return String(format: "%.1f/%.1fkW", snapshot.peakPowerWatts/1000, snapshot.peakRegenWatts/1000)
        }
        return String(format: "%.0f/%.0fW", snapshot.peakPowerWatts, snapshot.peakRegenWatts)
    }
}
