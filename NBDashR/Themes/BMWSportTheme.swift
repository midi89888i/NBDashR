import Foundation
import UIKit
import CoreGraphics

// ============================================================================
// 运动仪表(仿宝马 TFT)— 由 bmw.txt / powerarc.txt / powerbar.txt 反汇编还原
//
// 反汇编证据摘要:
//  - 画布: 848×480 (bmw.txt =848.0/=480.0)
//  - 速度大字区域: x≈386-396, y≈190-232; 单位 "km/h" (396,232)
//  - 速度条件着色: fcsel 分支 (亮色 246/250/222, 暗色 230/228/255, 分量按 255 归一)
//  - 顶部信息胶囊: "里程"(x≈200,y≈74) / "续航" / "海拔"(x≈372,y≈73) /
//    "电压"(x≈502,y≈73) / "航向"(x≈602,y≈74), 标签行 y≈62-99, 单位 km/km/m/V/°
//  - "动态 PRO" 标题 (x≈62-72 区域)
//  - 状态文本: "GPS 定位中" / "GPS 已锁定" / "模拟骑行" / "BLE"/"ANT" 连接源
//  - 功率显示: "%.0f"/"%.1f" + "kW"/"W", 功率等级 IDLE/REGEN/ECO/SPORT/BOOST/MAX
//  - powerarc.txt: 双弧 — 输出弧(arc 参数 60/235/140, fcsel 分支)与
//    回收弧(0.875/159/110), 分段刻度循环 (×8.0 步进, subs+b.ne 回跳),
//    弧尽头帽点 (255 白色圆点), 刻度颜色插值 (255-x 渐变白化)
//  - 底部: 时间/连接状态
// 不确定项在文件末尾注释列出。
// ============================================================================

struct BMWSportTheme: DashboardThemeRenderer {
    let id = "bmwSport"
    let displayName = "运动仪表"
    let subtitle = "仿宝马 TFT · 功率双弧 · 全宽速度带"

    // MARK: - 色板 (参照 COLORS.md 与 BMWPalette: cyan/cyanSoft/lime/orange/crimson/white/muted/label)
    private struct Pal {
        static let bg0      = UIColor(red: 0.012, green: 0.016, blue: 0.024, alpha: 1)   // 近黑深蓝底
        static let bg1      = UIColor(red: 0.031, green: 0.043, blue: 0.063, alpha: 1)   // COLORS 0xcd80 系
        static let cyan     = UIColor(red: 0.071, green: 0.902, blue: 0.925, alpha: 1)   // 0xc588 青
        static let cyanSoft = UIColor(red: 0.667, green: 0.784, blue: 1.0,   alpha: 1)   // 0xceb8 柔青白
        static let lime     = UIColor(red: 0.647, green: 1.0,   blue: 0.22,  alpha: 1)   // 0xc288 青柠
        static let orange   = UIColor(red: 1.0,   green: 0.510, blue: 0.220, alpha: 1)
        static let crimson  = UIColor(red: 1.0,   green: 0.098, blue: 0.137, alpha: 1)   // 0xc628 红
        static let white    = UIColor(red: 0.886, green: 0.918, blue: 0.957, alpha: 1)   // 0xd450 主文字
        static let muted    = UIColor(red: 0.608, green: 0.725, blue: 1.0,   alpha: 0.73)// 0xc368 次要
        static let label    = UIColor(red: 0.769, green: 0.816, blue: 0.878, alpha: 0.85)// 0xc7a0 标签
        static let dimTrack = UIColor(white: 1.0, alpha: 0.10)                            // 弧底轨
        static let cardFill = UIColor(red: 0.0, green: 0.06, blue: 0.035, alpha: 0.55)    // 0x129b78 胶囊底
    }

    func draw(in ctx: CGContext, rect: CGRect, snapshot: TelemetrySnapshot, power: PowerReading) {
        // 0. 背景:垂直暗渐变 + 中央微光(对应 bl 0x1000ab928 fillLinearGradient 848×480)
        ctx.drawVerticalGradient(rect: rect, colors: [Pal.bg1, Pal.bg0, Pal.bg0])

        drawTopCapsules(in: ctx, rect: rect, snapshot: snapshot)
        drawSpeedCluster(in: ctx, snapshot: snapshot)
        drawPowerArcs(in: ctx, snapshot: snapshot, power: power)
        drawPowerReadout(in: ctx, power: power)
        drawBottomStrip(in: ctx, rect: rect, snapshot: snapshot)
    }

    // MARK: - 顶部信息胶囊行(里程/续航/海拔/电压/航向 — 原版中文标签)
    // 反汇编坐标: 里程值 x≈200 y≈74 · 海拔 x≈372 y≈73 · 电压 x≈502 y≈73 · 航向 x≈602 y≈74
    // 标签行 y≈62-77, 数值行 y≈90-99, 单位 "km"/"m"/" km"/" m"/"°"/"km/h"
    private func drawTopCapsules(in ctx: CGContext, rect: CGRect, snapshot: TelemetrySnapshot) {
        struct Cap { let label: String; let value: String; let unit: String; let cx: CGFloat }
        // 续航:原版来自车辆 BLE 剩余续航;快照无此字段,用百分比近似(不确定项)
        let rangeText: String
        if let pct = snapshot.batteryPercent {
            rangeText = String(format: "%.0f", Double(pct) * 0.9)
        } else {
            rangeText = "--"
        }
        let voltText = snapshot.batteryVoltage.map { String(format: "%.1f", $0) } ?? "--"
        let caps: [Cap] = [
            Cap(label: "里程", value: String(format: "%.1f", snapshot.tripDistanceKm), unit: "km",  cx: 110),
            Cap(label: "续航", value: rangeText,                                       unit: " km", cx: 265),
            Cap(label: "海拔", value: String(format: "%.0f", snapshot.altitudeMeters), unit: " m",  cx: 420),
            Cap(label: "电压", value: voltText,                                        unit: "V",   cx: 575),
            Cap(label: "航向", value: snapshot.compassLabel,                           unit: "",     cx: 730),
        ]
        for c in caps {
            let card = CGRect(x: c.cx - 68, y: 46, width: 136, height: 62)
            ctx.fillRoundedRect(card, radius: 14, color: Pal.cardFill)
            ctx.strokePill(rect: card, color: Pal.cyan.withAlphaComponent(0.18), lineWidth: 1, cornerRadius: 14)
            // 标签(小字 muted)
            ctx.drawText(c.label, center: CGPoint(x: c.cx, y: card.minY + 16),
                         size: 13, weight: .medium, color: Pal.label)
            // 数值 + 单位(等宽数字)
            let valSize = ctx.drawText(c.value, center: CGPoint(x: c.cx - (c.unit.isEmpty ? 0 : 8), y: card.minY + 40),
                                       size: 21, weight: .bold, color: Pal.white, monoDigits: true)
            if !c.unit.isEmpty {
                ctx.drawText(c.unit, center: CGPoint(x: c.cx - 8 + valSize.width / 2 + 10, y: card.minY + 44),
                             size: 12, weight: .semibold, color: Pal.muted, align: .left)
            }
        }
    }

    // MARK: - 中央速度区(全宽速度带核心)
    // 原版:速度整数 "%.0f" 大字号于 (386,190) 附近,条件着色(fcsel: 高速亮 246/250/222, 低速 230/228/255);
    // "km/h" 于 (396,232) 小字
    private func drawSpeedCluster(in ctx: CGContext, snapshot: TelemetrySnapshot) {
        let speed = snapshot.speedKmh
        // 条件着色(还原 fcsel 分支):高速偏暖亮白,低速/静止偏冷白
        let bright = UIColor(red: 246/255.0, green: 250/255.0, blue: 222/255.0, alpha: 1)
        let calm   = UIColor(red: 230/255.0, green: 228/255.0, blue: 255/255.0, alpha: 1)
        let digitColor = speed >= 40 ? bright : calm

        let cx: CGFloat = 424   // 画布水平中点(原版略偏左,此处居中于 848 画布)
        // 大速度字
        ctx.drawText(String(format: "%.0f", speed), center: CGPoint(x: cx, y: 218),
                     size: 130, weight: .heavy, color: digitColor, monoDigits: true)
        // 单位 km/h
        ctx.drawText("km/h", center: CGPoint(x: cx, y: 296),
                     size: 22, weight: .semibold, color: Pal.muted)

        // 状态徽标:"GPS 定位中" / "GPS 已锁定" / "模拟骑行"(原版字符串)
        let status: String
        let statusColor: UIColor
        if snapshot.isDemo {
            status = "模拟骑行"; statusColor = Pal.orange
        } else if snapshot.hasGPSFix {
            status = "GPS 已锁定"; statusColor = Pal.lime
        } else {
            status = "GPS 定位中"; statusColor = Pal.muted
        }
        let pillRect = CGRect(x: cx - 62, y: 322, width: 124, height: 26)
        ctx.fillRoundedRect(pillRect, radius: 13, color: statusColor.withAlphaComponent(0.14))
        ctx.strokePill(rect: pillRect, color: statusColor.withAlphaComponent(0.45), lineWidth: 1)
        ctx.drawText(status, center: CGPoint(x: cx, y: pillRect.midY),
                     size: 14, weight: .semibold, color: statusColor)

        // 全宽速度带:底部横贯画布的渐变速度条(标题承诺的"全宽速度带")
        let bandRect = CGRect(x: 24, y: 396, width: 848 - 48, height: 34)
        ctx.fillRoundedRect(bandRect, radius: 17, color: UIColor(white: 1.0, alpha: 0.07))
        let frac = max(0, min(1, speed / max(60, snapshot.maxSpeedKmh > 0 ? snapshot.maxSpeedKmh : 60)))
        if frac > 0.003 {
            let fillRect = CGRect(x: bandRect.minX, y: bandRect.minY,
                                  width: bandRect.width * frac, height: bandRect.height)
            ctx.fillRoundedRect(fillRect, radius: 17, color: Pal.cyan.withAlphaComponent(0.85))
        }
        // 速度带刻度(循环刻度:subs+b 回跳,0/20/40/60 位置短线)
        ctx.drawText("速度", center: CGPoint(x: bandRect.minX + 26, y: bandRect.midY),
                     size: 13, weight: .medium, color: Pal.label)
        ctx.drawText(String(format: "%.0f km/h", speed), center: CGPoint(x: bandRect.maxX - 44, y: bandRect.midY),
                     size: 15, weight: .bold, color: Pal.white, monoDigits: true)
    }

    // MARK: - 功率双弧(powerarc.txt 还原)
    // 放电弧(output)与回收弧(regen)左右对称环抱速度区;
    // 原版弧段参数 fcsel 分支 (60/235/140) vs (0.875/159/110) → 角度制映射:
    //   输出弧:自 150° 顺时针扫至 30°(右侧);回收弧:自 210° 逆时针扫至 330°(左侧)
    // 分段刻度 ×8 步进,弧尽头白色帽点(powerarc 尾部 255/255/255 圆点)
    private func drawPowerArcs(in ctx: CGContext, snapshot: TelemetrySnapshot, power: PowerReading) {
        let center = CGPoint(x: 424, y: 240)
        let radius: CGFloat = 168
        let trackW: CGFloat = 10
        let arcW: CGFloat = 14

        // 底轨(双弧整段暗轨)
        ctx.drawArc(center: center, radius: radius, lineWidth: trackW,
                    startDeg: -150, endDeg: -30, color: Pal.dimTrack, lineCap: .round)   // 左侧(回收)
        ctx.drawArc(center: center, radius: radius, lineWidth: trackW,
                    startDeg: 30, endDeg: 150, color: Pal.dimTrack, lineCap: .round)     // 右侧(放电)

        // 刻度线(循环刻度:沿弧均布短刻度,powerarc.txt ×8.0 步进分段)
        for side in [-1, 1] {
            let startA: CGFloat = side < 0 ? -150 : 30
            let endA: CGFloat   = side < 0 ? -30  : 150
            let steps = 24
            for i in 0...steps {
                let fracI = CGFloat(i) / CGFloat(steps)
                let deg = startA + (endA - startA) * fracI
                let rad = (deg - 90) * .pi / 180
                let r1 = radius + 12, r2 = radius + (i % 4 == 0 ? 24 : 18)
                let p1 = CGPoint(x: center.x + r1 * cos(rad), y: center.y + r1 * sin(rad))
                let p2 = CGPoint(x: center.x + r2 * cos(rad), y: center.y + r2 * sin(rad))
                ctx.drawLine(from: p1, to: p2,
                             color: Pal.muted.withAlphaComponent(i % 4 == 0 ? 0.55 : 0.25),
                             width: i % 4 == 0 ? 2 : 1)
            }
        }

        // 放电弧(右侧,青→按功率等级着色)
        if power.outputFrac > 0.003 {
            let endDeg = 30 + 120 * CGFloat(min(1, power.outputFrac))
            let col = arcColor(for: power.level)
            ctx.drawArc(center: center, radius: radius, lineWidth: arcW,
                        startDeg: 30, endDeg: endDeg, color: col)
            drawArcCap(in: ctx, center: center, radius: radius, deg: endDeg, color: .white)
        }
        // 回收弧(左侧,青柠绿)
        if power.regenFrac > 0.003 {
            // 从左端 -150 向 -30 方向按比例填充
            let endDeg = -150 + 120 * CGFloat(min(1, power.regenFrac))
            ctx.drawArc(center: center, radius: radius, lineWidth: arcW,
                        startDeg: -150, endDeg: endDeg, color: Pal.lime)
            drawArcCap(in: ctx, center: center, radius: radius, deg: endDeg, color: .white)
        }
    }

    /// 弧尽头白色帽点(powerarc.txt 尾端 255,255,255 圆点)
    private func drawArcCap(in ctx: CGContext, center: CGPoint, radius: CGFloat, deg: CGFloat, color: UIColor) {
        let rad = (deg - 90) * .pi / 180
        let p = CGPoint(x: center.x + radius * cos(rad), y: center.y + radius * sin(rad))
        ctx.fillCircle(center: p, radius: 7, color: color)
    }

    private func arcColor(for level: PowerLevel) -> UIColor {
        switch level {
        case .regen:             return Pal.lime
        case .eco:               return Pal.cyan
        case .sport:             return Pal.cyanSoft
        case .boost:             return Pal.orange
        case .max:               return Pal.crimson
        case .idle, .unavailable: return Pal.cyan
        }
    }

    // MARK: - 功率读数(右侧,"动态 PRO" 标题 + %.1fkW/%.0fW + 等级标签)
    // 原版: "%.1f"+"kW"(>=1000W)或 "%.0f"+"W";等级字 IDLE/REGEN/ECO/SPORT/BOOST/MAX
    private func drawPowerReadout(in ctx: CGContext, power: PowerReading) {
        // "动态 PRO" 角标(原版字符串,左上 x≈62-72 区域)
        ctx.drawText("动态 PRO", center: CGPoint(x: 92, y: 132),
                     size: 17, weight: .bold, color: Pal.cyan, align: .left)

        // 功率大数字(右侧弧旁)
        let wattsText: String
        let unit: String
        if let w = power.watts {
            if abs(w) >= 1000 {
                wattsText = String(format: "%.1f", w / 1000); unit = "kW"
            } else {
                wattsText = String(format: "%.0f", w); unit = "W"
            }
        } else {
            wattsText = "--"; unit = ""
        }
        let px: CGFloat = 700, py: CGFloat = 220
        let accent = power.isRegen ? Pal.lime : arcColor(for: power.level)
        ctx.drawText(wattsText, center: CGPoint(x: px, y: py),
                     size: 46, weight: .heavy, color: accent, monoDigits: true)
        if !unit.isEmpty {
            ctx.drawText(unit, center: CGPoint(x: px, y: py + 34),
                         size: 17, weight: .semibold, color: Pal.muted)
        }
        // 功率等级标签
        ctx.drawText(power.level.tag, center: CGPoint(x: px, y: py + 60),
                     size: 15, weight: .bold, color: accent.withAlphaComponent(0.9))

        // 峰值功率/回收小行(底部右侧,数据来自 snapshot)
        if snapshot.peakPowerWatts > 0 || snapshot.peakRegenWatts > 0 {
            let peakLine = String(format: "峰值 %.0fW · 回收 %.0fW",
                                  snapshot.peakPowerWatts, abs(snapshot.peakRegenWatts))
            ctx.drawText(peakLine, center: CGPoint(x: 700, y: 470 - 14),
                         size: 12, weight: .medium, color: Pal.muted)
        }
    }

    // MARK: - 底部状态条(连接源 BLE/ANT + 时长 + 时间)
    private func drawBottomStrip(in ctx: CGContext, rect: CGRect, snapshot: TelemetrySnapshot) {
        let y = rect.maxY - 16
        // 连接源(原版 "vehicle_ble"/"gps_imu"/"demo" 数据源 → 显示 BLE/ANT)
        let conn = snapshot.antConnected ? "ANT" : (snapshot.bleConnected ? "BLE" : "--")
        ctx.drawText(conn, center: CGPoint(x: 48, y: y),
                     size: 13, weight: .semibold, color: Pal.muted, monoDigits: true)
        // 骑行时长
        ctx.drawText(snapshot.formattedDuration, center: CGPoint(x: 150, y: y),
                     size: 13, weight: .medium, color: Pal.muted, monoDigits: true, align: .left)
        // 时间
        let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
        ctx.drawText(fmt.string(from: Date()), center: CGPoint(x: rect.maxX - 52, y: y),
                     size: 14, weight: .semibold, color: Pal.label, monoDigits: true)
    }
}

// ============================================================================
// 不确定项(还原时的解释性决策):
// 1. 反汇编高度混淆(Swift runtime + 见证表间接调用 + 死代码),逐指令坐标不可全部
//    复原;布局结构依据可解码字符串、浮点常量聚类与子标题"功率双弧·全宽速度带"重建。
// 2. "续航"原版来自车辆 BLE 剩余续航寄存器,TelemetrySnapshot 无此字段,
//    现用 batteryPercent×0.9 近似 — 与原版语义不同。
// 3. 速度大字的条件着色阈值(fcmp d9/d10 与 speed×12/×14 的关系)无法确证,
//    采用 speed>=40 切换亮/冷白;原版 RGB (246,250,222)/(230,228,255) 分量已按 255 归一采用。
// 4. 功率双弧的精确扫掠角度(fcsel 常数 60/235/140 vs 0.875/159/110 单位不明)
//    映射为 0=正上顺时针角度制:右弧 30°→150°,左弧 -150°→-30°。
// 5. 速度带的最大刻度参照(maxSpeedKmh 或 60)是近似选择。
// 6. "动态 PRO" 的位置按常量聚类(x≈62-72, y≈72-98 区)放在左上;也可能原本是标题栏元素。
// ============================================================================
