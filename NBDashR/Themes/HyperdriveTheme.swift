import Foundation
import UIKit
import CoreGraphics

/// 「超维引擎」主题 —— 由 hyper.txt(791 条 ARM64 指令)反汇编翻译还原。
/// 布局:深空渐变底,中央反应堆速度环(中心 (424,255)),双同心环刻度,
/// 曲速星流旋转放射线,左/右上渐变舷窗面板,底部全宽行程渐变带。
struct HyperdriveTheme: DashboardThemeRenderer {
    let id = "hyperdrive"
    let displayName = "超维引擎"
    let subtitle = "曲速星流 · 反应堆速度环 · 随速旋转涡轮"

    // MARK: - 原版配色(HyperPalette: cyan/violet/magenta/red/green/amber)
    // 分量取自 COLORS.md 原版的紫/品红/青色系
    private let cyan      = UIColor(red: 0.0706, green: 0.902,  blue: 0.9255, alpha: 1)  // (0.07,0.90,0.93) 青
    private let violet    = UIColor(red: 0.6275, green: 0.3725, blue: 1.0,    alpha: 1)  // 紫罗兰
    private let magenta   = UIColor(red: 0.9922, green: 0.0,    blue: 0.8824, alpha: 1)  // 品红
    private let plasma    = UIColor(red: 0.6667, green: 0.7529, blue: 1.0,    alpha: 1)  // 等离子蓝
    private let regenGrn  = UIColor(red: 0.28,   green: 1.0,    blue: 0.31,   alpha: 1)  // 回收绿
    private let amber     = UIColor(red: 1.0,    green: 0.75,   blue: 0.3,    alpha: 1)  // 琥珀
    private let hot       = UIColor(red: 1.0,    green: 0.098,  blue: 0.1373, alpha: 1)  // 极限红
    private let white     = UIColor(white: 1, alpha: 0.96)
    private let muted     = UIColor(white: 1, alpha: 0.45)
    private let bgTop     = UIColor(red: 0.0314, green: 0.0431, blue: 0.0627, alpha: 1)  // 深空蓝黑
    private let bgBottom  = UIColor(red: 0.0, green: 0.0, blue: 0.02, alpha: 1)

    // MARK: - 几何(反汇编常量)
    // 反应堆中心 (424,255);环半径 60/92/120/138/176/240;舷窗面板 (300,256,330)/(720,430,280)
    private let core = CGPoint(x: 424, y: 255)

    func draw(in ctx: CGContext, rect: CGRect, snapshot: TelemetrySnapshot, power: PowerReading) {
        // 1. 深空渐变底(原版 fillLinearGradient 全幅 848×480)
        ctx.drawVerticalGradient(rect: rect, colors: [bgTop, bgBottom])

        // 2. 曲速星流(速度驱动旋转放射线,在反应堆外围)
        drawWarpStreams(in: ctx, snapshot: snapshot)

        // 3. 反应堆速度环(同心多环 + 速度扫描弧 + 功率能量轨)
        drawReactor(in: ctx, snapshot: snapshot, power: power)

        // 4. 中央速度读数
        drawCoreReadout(in: ctx, snapshot: snapshot, power: power)

        // 5. 左/右舷窗面板(功率/峰值/回收/遥测)
        drawPods(in: ctx, snapshot: snapshot, power: power)

        // 6. 底部行程渐变带(原版:全宽渐变 848×60,y=420)
        drawBottomStrip(in: ctx, rect: rect, snapshot: snapshot)

        // 7. 顶部状态条
        ctx.drawTopStatusBar(in: rect, snapshot: snapshot,
                             bgColor: bgTop, textColor: white, accent: cyan)
    }

    // MARK: - 曲速星流:12-24 条放射线,随速度旋转,反应堆外围
    private func drawWarpStreams(in ctx: CGContext, snapshot: TelemetrySnapshot) {
        guard snapshot.speedKmh > 4 else { return }
        let frac = min(1.0, snapshot.speedKmh / 120.0)
        let count = min(24, 8 + Int(snapshot.speedKmh / 5))
        let rotation = snapshot.tripDurationSec * (0.4 + frac * 1.2)
        ctx.setStrokeColor(cyan.withAlphaComponent(0.25 + 0.35 * frac).cgColor)
        ctx.setLineWidth(1.5)
        for i in 0..<count {
            let base = Double(i) * (2 * .pi / Double(count)) + rotation
            // 长度随速度伸长(原版常量 0.6875/0.9375 为比例系数)
            let r1: CGFloat = 240
            let r2 = r1 + 20 + 90 * frac * CGFloat(0.6875 + 0.25 * sin(Double(i) * 2.7))
            ctx.move(to: CGPoint(x: core.x + cos(base) * r1, y: core.y + sin(base) * r1))
            ctx.addLine(to: CGPoint(x: core.x + cos(base) * r2, y: core.y + sin(base) * r2))
        }
        ctx.strokePath()
    }

    // MARK: - 反应堆速度环
    private func drawReactor(in ctx: CGContext, snapshot: TelemetrySnapshot, power: PowerReading) {
        // 外圈静态装饰环(半径 176/240,暗淡)
        ctx.drawArc(center: core, radius: 176, lineWidth: 2,
                    startDeg: 0, endDeg: 360, color: violet.withAlphaComponent(0.25), lineCap: .butt)
        ctx.drawArc(center: core, radius: 120, lineWidth: 1.5,
                    startDeg: 0, endDeg: 360, color: plasma.withAlphaComponent(0.18), lineCap: .butt)

        // 主速度环:半径 138,270° 扫描(-225°→45°,开口向下),满刻度随 maxSpeed
        let maxScale = max(120.0, ceil(snapshot.maxSpeedKmh / 20.0) * 20.0)
        let speedFrac = min(1.0, snapshot.speedKmh / maxScale)
        ctx.drawArc(center: core, radius: 138, lineWidth: 10,
                    startDeg: -225, endDeg: 45, color: UIColor.white.withAlphaComponent(0.10))
        if speedFrac > 0.004 {
            let col = speedFrac < 0.6 ? cyan : speedFrac < 0.85 ? amber : hot
            ctx.drawArc(center: core, radius: 138, lineWidth: 10,
                        startDeg: -225, endDeg: -225 + 270 * speedFrac, color: col)
        }

        // 速度环刻度:小刻每 10,主刻每 1/6(半径 92 内圈读数)
        for i in 0...Int(maxScale / 10) {
            let v = Double(i) * 10.0
            let frac = v / maxScale
            let deg = -225 + 270 * frac
            let isMajor = i % Int(max(1, maxScale / 60)) == 0
            let a = (deg - 90) * .pi / 180
            let r1: CGFloat = 138 + (isMajor ? 10 : 5)
            let r2: CGFloat = 138 + (isMajor ? 20 : 10)
            ctx.drawLine(from: CGPoint(x: core.x + cos(a) * r1, y: core.y + sin(a) * r1),
                         to: CGPoint(x: core.x + cos(a) * r2, y: core.y + sin(a) * r2),
                         color: isMajor ? plasma.withAlphaComponent(0.7) : plasma.withAlphaComponent(0.3),
                         width: isMajor ? 2 : 1)
            if isMajor {
                let tr = r2 + 13
                ctx.drawText(String(format: "%.0f", v),
                             center: CGPoint(x: core.x + cos(a) * tr, y: core.y + sin(a) * tr),
                             size: 12, weight: .medium, color: muted, monoDigits: true)
            }
        }

        // 功率能量轨(半径 92 内圈):放电紫→品红,回收绿
        if power.isRegen {
            if power.regenFrac > 0.004 {
                ctx.drawArc(center: core, radius: 92, lineWidth: 8,
                            startDeg: -225, endDeg: -225 + 270 * power.regenFrac, color: regenGrn)
            }
        } else if power.outputFrac > 0.004 {
            let col = power.level == .max ? hot : power.level == .boost ? magenta : violet
            ctx.drawArc(center: core, radius: 92, lineWidth: 8,
                        startDeg: -225, endDeg: -225 + 270 * power.outputFrac, color: col)
        }
        // 能量轨底
        ctx.drawArc(center: core, radius: 92, lineWidth: 8,
                    startDeg: -225, endDeg: 45, color: UIColor.white.withAlphaComponent(0.06))
    }

    // MARK: - 中央核心读数
    private func drawCoreReadout(in ctx: CGContext, snapshot: TelemetrySnapshot, power: PowerReading) {
        // 核心光晕(随功率脉动)
        let pulse = 1 + 0.08 * sin(snapshot.tripDurationSec * 2.4) * CGFloat(power.outputFrac + 0.15)
        ctx.fillCircle(center: core, radius: 84 * pulse, color: violet.withAlphaComponent(0.08))
        ctx.fillCircle(center: core, radius: 60 * pulse, color: cyan.withAlphaComponent(0.07))

        // 大速度
        ctx.drawText(String(format: "%.0f", snapshot.speedKmh),
                     center: CGPoint(x: core.x, y: core.y - 14),
                     size: 96, weight: .heavy, color: white, monoDigits: true)
        // KM/H · WARP(原版 hyper 副标题元素)
        ctx.drawText("KM/H · WARP", center: CGPoint(x: core.x, y: core.y + 44),
                     size: 15, weight: .semibold, color: plasma)
        // 功率等级
        ctx.drawText(power.level.tag, center: CGPoint(x: core.x, y: core.y + 72),
                     size: 14, weight: .bold, color: power.level.color)
    }

    // MARK: - 左右舷窗面板(渐变卡片:左功率/右回收峰值,遥测行)
    private func drawPods(in ctx: CGContext, snapshot: TelemetrySnapshot, power: PowerReading) {
        // 左上面板(原版位置 (60,120) 区域,渐变 300×256 → 330 宽)
        drawPod(ctx, x: 60, y: 120, w: 250, title: "能量输出",
                value: TelemetrySnapshot.formatPower(snapshot.powerWatts),
                color: power.isRegen ? regenGrn : magenta)
        drawPod(ctx, x: 60, y: 212, w: 250, title: "输出峰值",
                value: TelemetrySnapshot.formatPower(snapshot.peakPowerWatts > 0 ? snapshot.peakPowerWatts : nil),
                color: amber)
        // 右上面板
        drawPod(ctx, x: 848 - 60 - 250, y: 120, w: 250, title: "回收功率",
                value: TelemetrySnapshot.formatPower(snapshot.powerWatts.map { $0 < 0 ? -$0 : 0 }),
                color: regenGrn)
        drawPod(ctx, x: 848 - 60 - 250, y: 212, w: 250, title: "回收峰值",
                value: TelemetrySnapshot.formatPower(snapshot.peakRegenWatts > 0 ? snapshot.peakRegenWatts : nil),
                color: regenGrn)
    }

    private func drawPod(_ ctx: CGContext, x: CGFloat, y: CGFloat, w: CGFloat, title: String, value: String, color: UIColor) {
        let r = CGRect(x: x, y: y, width: w, height: 76)
        ctx.fillRoundedRect(r, radius: 14, color: UIColor.white.withAlphaComponent(0.06))
        ctx.strokePill(rect: r, color: color.withAlphaComponent(0.35), lineWidth: 1.2, cornerRadius: 14)
        ctx.drawText(title, center: CGPoint(x: r.midX, y: r.minY + 18), size: 13, weight: .medium, color: plasma)
        ctx.drawText(value, center: CGPoint(x: r.midX, y: r.minY + 48), size: 26, weight: .bold, color: color, monoDigits: true)
    }

    // MARK: - 底部全宽行程渐变带(原版 y=420,高 60)
    private func drawBottomStrip(in ctx: CGContext, rect: CGRect, snapshot: TelemetrySnapshot) {
        let bandRect = CGRect(x: 0, y: 420, width: 848, height: 60)
        ctx.fillRect(bandRect, color: UIColor.black.withAlphaComponent(0.45))
        let cols: [(String, String, UIColor)] = [
            ("航程", String(format: "%.1f km", snapshot.tripDistanceKm), cyan),
            ("用时", snapshot.formattedDuration, white),
            ("均速", String(format: "%.0f km/h", snapshot.avgSpeedKmh), plasma),
            ("极速", String(format: "%.0f km/h", snapshot.maxSpeedKmh), hot),
            ("倾角", String(format: "%.0f°", snapshot.leanAngleDeg), violet),
        ]
        let cw: CGFloat = 848 / CGFloat(cols.count)
        for (i, c) in cols.enumerated() {
            let x = cw * CGFloat(i) + cw / 2
            ctx.drawText(c.0, center: CGPoint(x: x, y: 438), size: 12, weight: .medium, color: muted)
            ctx.drawText(c.1, center: CGPoint(x: x, y: 462), size: 17, weight: .bold, color: c.2, monoDigits: true)
        }
    }
}
