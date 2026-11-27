import Foundation
import UIKit
import CoreGraphics

/// 「流萤」主题 —— 由 firefly.txt (1200 条 ARM64 指令) 反汇编翻译还原。
/// 848×480 画布:萤火燃烧 · 速度反应堆。
///
/// 反汇编证据要点:
/// - 反应堆/粒子环中心 (468,248)(=468.0 / =248.0 多次出现,粒子环函数内成对加载)
/// - 6 颗萤火粒子,每颗间隔 60°(循环计数 6,ucvtf i × 60.0),半径 128 + anim×0.375(=128.0, fmul 0.375)
/// - 旋转虚线环:4 段,每段跨度 22°(90→112 / 166→188 / 242→264 / 318→340),随 animTime 旋转
/// - 燃烧丝带弧:中心 (468,248),扫描 205°→335°(=205.0 / =335.0,系数 1.75 弧度宽)
/// - 功率弧端点随 outputFrac 动态生长:56 + frac×199(=56.0/=199.0)、245 − frac×1.6875×…(=245.0/=-1.6875)、196 ∓ frac×88(=196.0/=88.0)
/// - 左侧速度读数区中心 (184,260)(=184.0/=260.0),大字号 92/96(=92.0/=96.0),小号 44/62 条件切换
/// - 底部停靠坞渐变带 x0→848、y 434→480(=434.0/=480.0/=848.0)
/// - 顶部状态条高 34;图片位 (90,151,84) 为 firefly_hsr_logo —— 版权素材,以抽象萤火光效替代
/// - FireflyFXState: combustion / wind / animTime / particleTravel / breathPhase —— 动画相位简化重建
struct FireflyTheme: DashboardThemeRenderer {
    let id = "firefly"
    let displayName = "流萤"
    let subtitle = "萤火燃烧 · 速度反应堆"

    // MARK: - 配色(FireflyPalette: emerald/mint/gold/flame/crimson/rose/white/muted/panelFill/panelStroke)
    // 分量参照 COLORS.md 翠绿/金色/玫瑰色系:[0.647,1.0,0.22] 翠萤绿、[1.0,0.92,0.41] 金、[1.0,0.29,0.35] 绯红
    private let emerald   = UIColor(red: 0.647, green: 1.0,  blue: 0.22,  alpha: 1)   // 翠萤绿(主色)
    private let mint      = UIColor(red: 0.78,  green: 1.0,  blue: 0.86,  alpha: 1)   // 薄荷亮绿
    private let gold      = UIColor(red: 1.0,   green: 0.92, blue: 0.41,  alpha: 1)   // 萤火金
    private let flame     = UIColor(red: 1.0,   green: 0.55, blue: 0.25,  alpha: 1)   // 燃烧橙
    private let crimson   = UIColor(red: 1.0,   green: 0.294, blue: 0.345, alpha: 1)  // 绯红(极限)
    private let rose      = UIColor(red: 1.0,   green: 0.824, blue: 0.855, alpha: 1)  // 玫瑰(回收)
    private let white     = UIColor(red: 0.95,  green: 1.0,  blue: 0.92,  alpha: 1)   // 萤白
    private let muted     = UIColor(red: 0.55,  green: 0.72, blue: 0.55,  alpha: 0.55)
    private let bgDeep    = UIColor(red: 0.012, green: 0.03, blue: 0.018, alpha: 1)   // 近黑深绿底
    private let bgLow     = UIColor(red: 0.02,  green: 0.055, blue: 0.03, alpha: 1)
    private let panelFill   = UIColor(red: 0.03, green: 0.07, blue: 0.04, alpha: 0.72)
    private let panelStroke = UIColor(red: 0.647, green: 1.0, blue: 0.22, alpha: 0.25)

    // MARK: - 几何常量(反汇编浮点常量)
    private let reactorCenter = CGPoint(x: 468, y: 248)   // 反应堆核心中心 (=468.0/=248.0)
    private let particleCount = 6                          // 萤火粒子数(循环计数 6)
    private let particleBaseR: CGFloat = 128               // 粒子轨道基础半径 (=128.0)
    private let speedCenter = CGPoint(x: 184, y: 260)      // 速度读数中心 (=184.0/=260.0)

    func draw(in ctx: CGContext, rect: CGRect, snapshot: TelemetrySnapshot, power: PowerReading) {
        // 动画相位:以行程时间驱动(原版 FireflyFXState.animTime / particleTravel 简化)
        let anim = snapshot.tripDurationSec
        drawBackground(ctx, rect)
        ctx.drawTopStatusBar(in: rect, snapshot: snapshot,
                             bgColor: bgDeep, textColor: white, accent: emerald)
        drawEmblem(ctx, anim: anim)                 // firefly_hsr_logo 替代光效
        drawBurningRibbon(ctx, power: power, anim: anim)
        drawPowerArcs(ctx, power: power)
        drawDashedOrbitRing(ctx, anim: anim)
        drawReactorCore(ctx, power: power, anim: anim)
        drawFireflyParticles(ctx, anim: anim, power: power)
        drawSpeedPanel(ctx, snapshot: snapshot)
        drawPowerReadout(ctx, power: power)
        drawBottomDock(ctx, snapshot: snapshot, power: power)
    }

    // MARK: - 背景:深绿近黑纵向渐变
    private func drawBackground(_ ctx: CGContext, _ rect: CGRect) {
        ctx.drawVerticalGradient(rect: rect, colors: [bgDeep, bgLow, bgDeep])
    }

    // MARK: - 左上萤火徽记(替代版权素材 firefly_hsr_logo,原版绘制位 ≈(90,151) 宽 84)
    private func drawEmblem(_ ctx: CGContext, anim: Double) {
        let c = CGPoint(x: 90, y: 96)
        let pulse = 0.5 + 0.5 * sin(anim * 2.2)          // breathPhase 简化
        // 光晕
        ctx.fillCircle(center: c, radius: 26 + CGFloat(pulse) * 4,
                       color: emerald.withAlphaComponent(0.08))
        ctx.fillCircle(center: c, radius: 15 + CGFloat(pulse) * 2,
                       color: emerald.withAlphaComponent(0.16))
        // 萤核
        ctx.fillCircle(center: c, radius: 6, color: gold.withAlphaComponent(0.9))
        ctx.fillCircle(center: c, radius: 2.5, color: white)
        // 两翼(抽象萤火)
        let wing = 0.5 + 0.5 * sin(anim * 5.0)           // wingPhase 简化
        ctx.drawArc(center: c, radius: 16, lineWidth: 2,
                    startDeg: 210, endDeg: 330,
                    color: mint.withAlphaComponent(0.35 + 0.3 * wing))
    }

    // MARK: - 燃烧丝带弧:中心 (468,248),基线扫描 205°→335°,随功率向两侧生长
    private func drawBurningRibbon(_ ctx: CGContext, power: PowerReading, anim: Double) {
        let frac = power.isRegen ? power.regenFrac : power.outputFrac
        // 原版:end = 56 + frac×199,start 在 205°→335° 骨架上随 frac 扩展
        let grow = CGFloat(min(max(frac, 0), 1))
        let baseColor = power.isRegen ? rose : (power.level == .max ? crimson : flame)
        // 丝带主体(反汇编 205→335 固定骨架)
        ctx.drawArc(center: reactorCenter, radius: 168, lineWidth: 3.5,
                    startDeg: 205, endDeg: 335,
                    color: gold.withAlphaComponent(0.28))
        // 燃烧段:随功率从中点向两端蔓延,末端收窄
        let mid: CGFloat = 270
        let spread = grow * 65 + 6
        ctx.drawArc(center: reactorCenter, radius: 168, lineWidth: 5,
                    startDeg: mid - spread, endDeg: mid + spread,
                    color: baseColor.withAlphaComponent(0.85))
        // 燃烧舌尖:动画摆动的小亮点(particleTravel 简化)
        let tongueDeg = mid + spread * CGFloat(sin(anim * 3.1)) * 0.9
        let p = pointOn(reactorCenter, 168, tongueDeg)
        ctx.fillCircle(center: p, radius: 4, color: gold)
        ctx.fillCircle(center: p, radius: 8, color: flame.withAlphaComponent(0.25))
    }

    // MARK: - 功率弧:端点随 outputFrac 生长(56+frac×199 / 245−frac×… 反汇编公式近似)
    private func drawPowerArcs(_ ctx: CGContext, power: PowerReading) {
        // 放电弧:输出比例驱动,颜色按 PowerLevel 分级
        let outFrac = CGFloat(power.outputFrac)
        let outColor: UIColor
        switch power.level {
        case .max:   outColor = crimson
        case .boost: outColor = flame
        case .sport: outColor = gold
        case .eco:   outColor = emerald
        default:     outColor = mint
        }
        // 底弧(未点亮部分)245° 起点骨架
        ctx.drawArc(center: reactorCenter, radius: 146, lineWidth: 7,
                    startDeg: 140, endDeg: 400,
                    color: emerald.withAlphaComponent(0.12))
        if outFrac > 0.01 {
            // 点亮弧:start 245° 附近,end = 140 + outFrac×260(对应 56+frac×199 的生长式)
            let endDeg = 140 + outFrac * 260
            ctx.drawArc(center: reactorCenter, radius: 146, lineWidth: 7,
                        startDeg: 140, endDeg: endDeg, color: outColor)
            // 弧头亮点
            let tip = pointOn(reactorCenter, 146, endDeg)
            ctx.fillCircle(center: tip, radius: 5, color: outColor)
            ctx.fillCircle(center: tip, radius: 10, color: outColor.withAlphaComponent(0.25))
        }
        // 回收弧:内侧,玫瑰/薄荷色,反方向生长
        let rFrac = CGFloat(power.regenFrac)
        if rFrac > 0.01 {
            let endDeg = 140 - rFrac * 120
            ctx.drawArc(center: reactorCenter, radius: 132, lineWidth: 5,
                        startDeg: endDeg, endDeg: 140,
                        color: rose.withAlphaComponent(0.9))
        }
    }

    // MARK: - 旋转虚线环:4 段 ×22° 跨度,76° 间距,随 animTime 旋转(反汇编 90→112 等)
    private func drawDashedOrbitRing(_ ctx: CGContext, anim: Double) {
        let rotation = anim * 360.0 / 18.0      // 原版 anim×360/180 系数简化:缓慢旋转
        for i in 0..<4 {
            let base = rotation + Double(i) * 76.0
            let start = CGFloat(base.truncatingRemainder(dividingBy: 360))
            ctx.drawArc(center: reactorCenter, radius: 116, lineWidth: 2,
                        startDeg: start, endDeg: start + 22,
                        color: emerald.withAlphaComponent(0.45))
        }
    }

    // MARK: - 反应堆核心:同心翠绿环 + 金色核心,呼吸脉动
    private func drawReactorCore(_ ctx: CGContext, power: PowerReading, anim: Double) {
        let pulse = 0.5 + 0.5 * sin(anim * 2.0)          // breathPhase
        let loadFrac = CGFloat(max(power.outputFrac, power.regenFrac))
        // 外晕
        ctx.fillCircle(center: reactorCenter, radius: 96,
                       color: emerald.withAlphaComponent(0.05))
        // 中环
        ctx.drawArc(center: reactorCenter, radius: 92, lineWidth: 1.5,
                    startDeg: 0, endDeg: 360,
                    color: emerald.withAlphaComponent(0.3))
        // 核心光球:半径随功率与呼吸放大
        let coreR = 44 + loadFrac * 18 + CGFloat(pulse) * 4
        ctx.fillCircle(center: reactorCenter, radius: coreR + 12,
                       color: emerald.withAlphaComponent(0.10))
        ctx.fillCircle(center: reactorCenter, radius: coreR,
                       color: emerald.withAlphaComponent(0.28))
        ctx.fillCircle(center: reactorCenter, radius: coreR * 0.62,
                       color: gold.withAlphaComponent(0.55))
        ctx.fillCircle(center: reactorCenter, radius: coreR * 0.3,
                       color: white.withAlphaComponent(0.9))
        // 核心功率文本
        let pw = TelemetrySnapshot.formatPower(power.watts)
        ctx.drawText(pw, center: CGPoint(x: reactorCenter.x, y: reactorCenter.y + coreR + 22),
                     size: 20, weight: .bold, color: gold, monoDigits: true)
        ctx.drawText(power.level.tag, center: CGPoint(x: reactorCenter.x, y: reactorCenter.y + coreR + 44),
                     size: 13, weight: .semibold, color: power.level == .max ? crimson : muted)
    }

    // MARK: - 萤火粒子:6 颗绕反应堆旋转,间隔 60°,相邻粒子以丝带相连(反汇编循环重建)
    private func drawFireflyParticles(_ ctx: CGContext, anim: Double, power: PowerReading) {
        // 原版:angle = anim×180/… + i×60;radius = 128 + anim×0.375(取周期化近似)
        let travel = anim.truncatingRemainder(dividingBy: 24.0) / 24.0   // particleTravel 0..1 循环
        let orbitR = particleBaseR + CGFloat(sin(anim * 0.8) * 10)       // 轨道呼吸
        var pts: [CGPoint] = []
        for i in 0..<particleCount {
            let deg = anim * 20.0 + Double(i) * 60.0                     // 60° 间隔(=60.0)
            pts.append(pointOn(reactorCenter, orbitR, CGFloat(deg)))
        }
        // 丝带连线:相邻粒子插值连线(反汇编中对相邻粒子位置做 fsub/fmul/fadd 插值)
        for i in 0..<particleCount {
            let a = pts[i]
            let b = pts[(i + 1) % particleCount]
            ctx.drawLine(from: a, to: b,
                         color: gold.withAlphaComponent(0.10), width: 1)
        }
        // 粒子本体:金心翠晕,明暗随相位错开
        for (i, p) in pts.enumerated() {
            let tw = 0.5 + 0.5 * sin(anim * 4.0 + Double(i) * 1.7)       // 闪烁相位
            let glowA = 0.18 + 0.30 * tw
            ctx.fillCircle(center: p, radius: 7, color: emerald.withAlphaComponent(CGFloat(glowA) * 0.5))
            ctx.fillCircle(center: p, radius: 3.2, color: gold.withAlphaComponent(0.5 + 0.5 * CGFloat(tw)))
            ctx.fillCircle(center: p, radius: 1.4, color: white)
        }
        // 自由飘萤:3 颗小幅漂移的远粒子(featherTravel 简化)
        for j in 0..<3 {
            let fx = reactorCenter.x - 150 + CGFloat(sin(anim * 0.6 + Double(j) * 2.1)) * 60
            let fy = reactorCenter.y - 120 + CGFloat(cos(anim * 0.45 + Double(j) * 1.3)) * 50 + CGFloat(j) * 80
            let tw = 0.4 + 0.6 * (0.5 + 0.5 * sin(anim * 3.0 + Double(j) * 2.4))
            ctx.fillCircle(center: CGPoint(x: fx, y: fy), radius: 2.2,
                           color: mint.withAlphaComponent(CGFloat(tw) * 0.7))
        }
    }

    // MARK: - 左侧速度面板:中心 (184,260),大号速度 + km/h + 极速(原版 92/96 大字号,44/62 条件档)
    private func drawSpeedPanel(_ ctx: CGContext, snapshot: TelemetrySnapshot) {
        // 面板卡(栖息舱风格)
        let card = CGRect(x: speedCenter.x - 128, y: speedCenter.y - 108, width: 256, height: 216)
        ctx.fillRoundedRect(card, radius: 18, color: panelFill)
        ctx.strokePill(rect: card, color: panelStroke, lineWidth: 1, cornerRadius: 18)
        // 顶部装饰芽条
        ctx.fillRoundedRect(CGRect(x: card.midX - 20, y: card.minY + 10, width: 40, height: 3),
                            radius: 1.5, color: emerald.withAlphaComponent(0.7))
        // 速度大数字(原版条件字号:低位 96,高位收窄 —— 这里按位数简化)
        let v = Int(snapshot.speedKmh.rounded())
        let fontSize: CGFloat = v >= 100 ? 62 : 92       // =62.0/=92.0 条件档
        ctx.drawText("\(v)", center: CGPoint(x: speedCenter.x, y: speedCenter.y - 14),
                     size: fontSize, weight: .bold, color: white, monoDigits: true)
        ctx.drawText("km/h", center: CGPoint(x: speedCenter.x, y: speedCenter.y + 48),
                     size: 20, weight: .semibold, color: emerald)
        // 极速小行
        ctx.drawText(String(format: "极速 %.0f", snapshot.maxSpeedKmh),
                     center: CGPoint(x: speedCenter.x, y: speedCenter.y + 82),
                     size: 14, weight: .medium, color: muted, monoDigits: true)
    }

    // MARK: - 右上输出/回收读数(原版 (507,66) 附近有小号状态文本,=246/=255/=252 近白分量)
    private func drawPowerReadout(_ ctx: CGContext, power: PowerReading) {
        let x: CGFloat = 640
        let y: CGFloat = 66
        ctx.drawText("输出", center: CGPoint(x: x - 36, y: y),
                     size: 13, weight: .medium, color: muted, align: .left)
        ctx.drawText(String(format: "%.0f%%", power.outputFrac * 100),
                     center: CGPoint(x: x + 30, y: y),
                     size: 16, weight: .bold, color: emerald, monoDigits: true, align: .left)
        ctx.drawText("回收", center: CGPoint(x: x - 36, y: y + 24),
                     size: 13, weight: .medium, color: muted, align: .left)
        ctx.drawText(String(format: "%.0f%%", power.regenFrac * 100),
                     center: CGPoint(x: x + 30, y: y + 24),
                     size: 16, weight: .bold, color: rose, monoDigits: true, align: .left)
    }

    // MARK: - 底部停靠坞:y 434→480 渐变带(=434.0/=480.0)+ FireflyDockCell 五格数据卡
    private struct DockCell {
        let label: String
        let value: String
        let unit: String
        let color: UIColor
    }

    private func drawBottomDock(_ ctx: CGContext, snapshot: TelemetrySnapshot, power: PowerReading) {
        // 底部渐变带(原版 fillLinearGradient x0→848,y434→480)
        let band = CGRect(x: 0, y: 434, width: 848, height: 46)
        ctx.drawVerticalGradient(rect: band, colors: [
            bgDeep.withAlphaComponent(0.0),
            UIColor(red: 0.02, green: 0.08, blue: 0.04, alpha: 0.85),
        ])
        let cells: [DockCell] = [
            DockCell(label: "行程", value: String(format: "%.1f", snapshot.tripDistanceKm), unit: "km", color: emerald),
            DockCell(label: "时长", value: snapshot.formattedDuration, unit: "", color: mint),
            DockCell(label: "均速", value: String(format: "%.0f", snapshot.avgSpeedKmh), unit: "km/h", color: gold),
            DockCell(label: "峰值", value: TelemetrySnapshot.formatPower(snapshot.peakPowerWatts), unit: "", color: flame),
            DockCell(label: "倾角", value: String(format: "%.0f", abs(snapshot.leanAngleDeg)), unit: "°", color: rose),
        ]
        let cellW: CGFloat = 150
        let spacing: CGFloat = 164
        let startX: CGFloat = 424 - spacing * 2      // 五格居中于画布中线 424
        for (i, cell) in cells.enumerated() {
            let cx = startX + CGFloat(i) * spacing
            // 萤火格点光斑
            ctx.fillCircle(center: CGPoint(x: cx - cellW/2 + 8, y: 452), radius: 2,
                           color: cell.color.withAlphaComponent(0.8))
            ctx.drawText(cell.label, center: CGPoint(x: cx - cellW/2 + 18, y: 452),
                         size: 12, weight: .medium, color: muted, align: .left)
            let valText = cell.unit.isEmpty ? cell.value : "\(cell.value)\(cell.unit)"
            ctx.drawText(valText, center: CGPoint(x: cx, y: 470),
                         size: 15, weight: .bold, color: cell.color, monoDigits: true)
        }
    }

    // MARK: - 工具:角度(0=正上顺时针)→ 圆周点
    private func pointOn(_ center: CGPoint, _ r: CGFloat, _ deg: CGFloat) -> CGPoint {
        let a = (deg - 90) * .pi / 180
        return CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
    }
}
