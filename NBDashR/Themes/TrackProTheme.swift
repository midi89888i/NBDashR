import Foundation
import UIKit
import CoreGraphics

/// 赛道遥测(trackPro)主题 — 由 ARM64 反汇编 trackpro.txt / powerarc.txt 翻译还原。
/// 布局:左侧双弧速度表(外弧车速 + 内弧功率),顶部速度曲线,
/// 中部 G 值横杆(BRK/ACC),右侧功率遥测列,底部遥测行。
struct TrackProTheme: DashboardThemeRenderer {
    let id = "trackPro"
    let displayName = "赛道遥测"
    let subtitle = "双弧速度表 · 电机功率 · 速度曲线"

    // MARK: - 原版配色(参照 COLORS.md 提取分量)
    /// 深空蓝黑背景
    private let bgTop    = UIColor(red: 0.031, green: 0.043, blue: 0.063, alpha: 1.0)
    private let bgBottom = UIColor(red: 0.0,   green: 0.0,   blue: 0.0,   alpha: 1.0)
    /// 主青色(速度弧/高亮)≈ (0.07, 0.90, 0.93)
    private let cyan     = UIColor(red: 0.07,  green: 0.90,  blue: 0.93,  alpha: 1.0)
    /// 次要蓝灰文本 ≈ (155,170,192)/255
    private let dimBlue  = UIColor(red: 155/255.0, green: 170/255.0, blue: 192/255.0, alpha: 1.0)
    /// 回收绿
    private let regenGreen = UIColor(red: 0.28, green: 1.0, blue: 0.31, alpha: 1.0)
    /// 卡片底色
    private let cardBg   = UIColor(white: 1.0, alpha: 0.06)
    private let trackBg  = UIColor(white: 1.0, alpha: 0.14)

    // MARK: - 功率等级中文文案(原版字符串:待命/经济/运动/全力/回收)
    private func levelLabel(_ level: PowerLevel) -> String {
        switch level {
        case .unavailable: return "--"
        case .idle:        return "待命"
        case .regen:       return "回收"
        case .eco:         return "经济"
        case .sport:       return "运动"
        case .boost, .max: return "全力"
        }
    }

    // MARK: - 主绘制入口
    func draw(in ctx: CGContext, rect: CGRect, snapshot: TelemetrySnapshot, power: PowerReading) {
        // 1. 背景:近黑垂直渐变(原版 fillLinearGradient 全画布 848×480)
        ctx.drawVerticalGradient(rect: rect, colors: [bgTop, bgBottom])

        // 2. 顶部速度曲线(原版循环:x = 1.375 + frac × 571,横跨上部)
        drawSpeedCurve(in: ctx, snapshot: snapshot)

        // 3. 双弧速度表(外弧车速 + 内弧功率/回收,圆心左侧)
        let gaugeCenter = CGPoint(x: 352, y: 268)
        drawDualArcGauge(in: ctx, center: gaugeCenter, snapshot: snapshot, power: power)

        // 4. 中央大速度数字(原版坐标 (352,234),大号白色等宽数字)
        let speedInt = Int(snapshot.speedKmh.rounded())
        ctx.drawText(String(format: "%02d", speedInt),
                     center: CGPoint(x: 352, y: 254),
                     size: 76, weight: .bold, color: .white, monoDigits: true)
        // KM/H 单位(原版字符串 "KM/H",蓝灰色)
        ctx.drawText("KM/H",
                     center: CGPoint(x: 352, y: 306),
                     size: 16, weight: .semibold, color: dimBlue)

        // 5. 功率等级文字(原版:待命/经济/运动/全力/回收,按功率分级着色)
        let lvText = levelLabel(power.level)
        ctx.drawText(lvText,
                     center: CGPoint(x: 352, y: 336),
                     size: 15, weight: .bold, color: levelColor(power))

        // 6. G 值横杆(BRK ←→ ACC,原版 y≈328,中心 x=310)
        drawGForceBar(in: ctx, snapshot: snapshot)

        // 7. 右侧功率遥测列(原版 x≈570-680:实时功率/峰值/回收)
        drawPowerColumn(in: ctx, snapshot: snapshot, power: power)

        // 8. 底部遥测行(行程/时间/最高/平均/海拔/电量)
        drawTelemetryRow(in: ctx, rect: rect, snapshot: snapshot)
    }

    // MARK: - 功率分级颜色(覆盖原版 level.color,回收绿/待命灰)
    private func levelColor(_ power: PowerReading) -> UIColor {
        switch power.level {
        case .unavailable, .idle: return dimBlue
        case .regen:              return regenGreen
        case .eco:                return cyan
        case .sport:              return .systemYellow
        case .boost:              return .systemOrange
        case .max:                return .systemRed
        }
    }

    // MARK: - 双弧速度表
    /// 外弧:车速(满刻度按 maxSpeedKmh,缺省 120);内弧:功率输出或回收。
    /// 弧线角度规约:0 = 正上方,顺时针;表盘采用 135°→405° 共 270° 开口向下。
    private func drawDualArcGauge(in ctx: CGContext, center: CGPoint,
                                  snapshot: TelemetrySnapshot, power: PowerReading) {
        let startDeg: CGFloat = 135
        let endDeg: CGFloat = 405
        let sweep = endDeg - startDeg

        let outerR: CGFloat = 118   // 外弧车速半径
        let innerR: CGFloat = 96    // 内弧功率半径

        // 外弧底轨
        ctx.drawArc(center: center, radius: outerR, lineWidth: 10,
                    startDeg: startDeg, endDeg: endDeg, color: trackBg)
        // 外弧车速值
        let fullScale = max(snapshot.maxSpeedKmh, 120)
        let speedFrac = CGFloat(min(1.0, max(0.0, snapshot.speedKmh / fullScale)))
        if speedFrac > 0.005 {
            ctx.drawArc(center: center, radius: outerR, lineWidth: 10,
                        startDeg: startDeg, endDeg: startDeg + sweep * speedFrac,
                        color: cyan)
        }

        // 内弧底轨
        ctx.drawArc(center: center, radius: innerR, lineWidth: 7,
                    startDeg: startDeg, endDeg: endDeg, color: trackBg.withAlphaComponent(0.6))
        // 内弧功率:放电磁顺时针(青色→等级色),回收弧逆时针(绿色)
        if power.outputFrac > 0.005 {
            let frac = CGFloat(min(1.0, power.outputFrac))
            ctx.drawArc(center: center, radius: innerR, lineWidth: 7,
                        startDeg: startDeg, endDeg: startDeg + sweep * frac,
                        color: levelColor(power))
        } else if power.regenFrac > 0.005 {
            let frac = CGFloat(min(1.0, power.regenFrac))
            // 回收弧自起点反向延伸(视觉对称,动画简化)
            ctx.drawArc(center: center, radius: innerR, lineWidth: 7,
                        startDeg: endDeg - sweep * frac, endDeg: endDeg,
                        color: regenGreen)
        }

        // 刻度点:270° 分 9 格小圆点(原版循环重复元素,动画简化)
        for i in 0...9 {
            let deg = startDeg + sweep * CGFloat(i) / 9.0
            let rad = (deg - 90) * .pi / 180
            let dotR = outerR + 16
            let p = CGPoint(x: center.x + cos(rad) * dotR,
                            y: center.y + sin(rad) * dotR)
            let lit = CGFloat(i) / 9.0 <= speedFrac
            ctx.fillCircle(center: p, radius: 2.2,
                           color: lit ? cyan : UIColor(white: 1.0, alpha: 0.18))
        }
    }

    // MARK: - 速度曲线(顶部横贯,使用 speedHistory)
    private func drawSpeedCurve(in ctx: CGContext, snapshot: TelemetrySnapshot) {
        // 原版曲线区:x 自 ~14 起横跨 571pt,基线 y≈114,上界 y≈46
        let area = CGRect(x: 20, y: 48, width: 571, height: 66)
        let history = snapshot.speedHistory
        guard history.count >= 2 else {
            // 无历史时绘制底框与提示虚线感(动画简化:静态 baseline)
            ctx.drawLine(from: CGPoint(x: area.minX, y: area.maxY),
                         to: CGPoint(x: area.maxX, y: area.maxY),
                         color: trackBg, width: 1)
            return
        }
        let maxV = max(history.max() ?? 1, 1)
        let stepX = area.width / CGFloat(history.count - 1)

        // 基线
        ctx.drawLine(from: CGPoint(x: area.minX, y: area.maxY),
                     to: CGPoint(x: area.maxX, y: area.maxY),
                     color: trackBg, width: 1)

        // 折线(原版逐段 drawLine,颜色青)
        var prev = CGPoint(x: area.minX,
                           y: area.maxY - CGFloat(history[0] / maxV) * area.height)
        for i in 1..<history.count {
            let x = area.minX + stepX * CGFloat(i)
            let y = area.maxY - CGFloat(history[i] / maxV) * area.height
            let pt = CGPoint(x: x, y: y)
            ctx.drawLine(from: prev, to: pt, color: cyan.withAlphaComponent(0.9), width: 2)
            prev = pt
        }
        // 末端当前点高亮
        ctx.fillCircle(center: prev, radius: 3, color: cyan)
    }

    // MARK: - G 值横杆(BRK/ACC)
    private func drawGForceBar(in ctx: CGContext, snapshot: TelemetrySnapshot) {
        let barY: CGFloat = 392
        let leftX: CGFloat = 84     // 原版 BRK 文本 x=84
        let rightX: CGFloat = 536   // 原版 ACC 文本 x=536
        let centerX: CGFloat = 310  // 原版中心常量 310/320

        // 标签(原版字符串)
        ctx.drawText("BRK", center: CGPoint(x: leftX, y: barY - 18),
                     size: 13, weight: .semibold, color: regenGreen)
        ctx.drawText("ACC", center: CGPoint(x: rightX, y: barY - 18),
                     size: 13, weight: .semibold, color: .systemOrange)

        // 横杆轨道(中心 x=310,左右各 160)
        let trackRect = CGRect(x: centerX - 160, y: barY - 4, width: 320, height: 8)
        ctx.fillRoundedRect(trackRect, radius: 4, color: trackBg)
        // 中心刻点
        ctx.fillCircle(center: CGPoint(x: centerX, y: barY), radius: 3,
                       color: UIColor(white: 1.0, alpha: 0.5))

        // G 值标记:-1g(全刹车)..+1g(全加速),颜色随方向(回收绿/加速橙)
        let g = max(-1.0, min(1.0, snapshot.longitudinalG))
        let markerX = centerX + CGFloat(g) * 160
        let markerColor: UIColor = g < -0.05 ? regenGreen : (g > 0.05 ? .systemOrange : .white)
        // 从中心到标记的填充条
        let fillMinX = min(centerX, markerX)
        let fillWidth = abs(markerX - centerX)
        if fillWidth > 2 {
            ctx.fillRoundedRect(CGRect(x: fillMinX, y: barY - 4, width: fillWidth, height: 8),
                                radius: 4, color: markerColor.withAlphaComponent(0.7))
        }
        ctx.fillCircle(center: CGPoint(x: markerX, y: barY), radius: 7, color: markerColor)

        // 倾角小字(原版 lean 角度参与标记着色,此处简化为数值显示)
        ctx.drawText(String(format: "%.1f°", snapshot.leanAngleDeg),
                     center: CGPoint(x: centerX, y: barY + 22),
                     size: 12, weight: .medium, color: dimBlue, monoDigits: true)
    }

    // MARK: - 右侧功率遥测列
    private func drawPowerColumn(in ctx: CGContext, snapshot: TelemetrySnapshot, power: PowerReading) {
        let colX: CGFloat = 570   // 原版列基准 x=570
        let valueX: CGFloat = 680 // 右对齐值列

        // 实时功率(原版字符串"实时功率")
        ctx.drawText("实时功率", center: CGPoint(x: colX, y: 150),
                     size: 13, weight: .medium, color: dimBlue, align: .left)
        let powerText = TelemetrySnapshot.formatPower(snapshot.powerWatts)
        ctx.drawText(powerText, center: CGPoint(x: valueX, y: 172),
                     size: 30, weight: .bold, color: levelColor(power),
                     monoDigits: true, align: .right)

        // 峰值功率(原版字符串"峰值")
        ctx.drawText("峰值", center: CGPoint(x: colX, y: 214),
                     size: 13, weight: .medium, color: dimBlue, align: .left)
        ctx.drawText(TelemetrySnapshot.formatPower(snapshot.peakPowerWatts),
                     center: CGPoint(x: valueX, y: 214),
                     size: 17, weight: .semibold, color: .white, monoDigits: true, align: .right)

        // 回收峰值(原版字符串"回收")
        ctx.drawText("回收", center: CGPoint(x: colX, y: 244),
                     size: 13, weight: .medium, color: dimBlue, align: .left)
        ctx.drawText(TelemetrySnapshot.formatPower(snapshot.peakRegenWatts),
                     center: CGPoint(x: valueX, y: 244),
                     size: 17, weight: .semibold, color: regenGreen, monoDigits: true, align: .right)

        // 最高速度(原版遥测项)
        ctx.drawText("最高速度", center: CGPoint(x: colX, y: 274),
                     size: 13, weight: .medium, color: dimBlue, align: .left)
        ctx.drawText(String(format: "%.0f km/h", snapshot.maxSpeedKmh),
                     center: CGPoint(x: valueX, y: 274),
                     size: 17, weight: .semibold, color: .white, monoDigits: true, align: .right)

        // 分隔线
        ctx.drawLine(from: CGPoint(x: colX, y: 296), to: CGPoint(x: valueX, y: 296),
                     color: trackBg, width: 1)

        // 倾角(左/右峰值,原版 maxLeftLean/maxRightLean)
        ctx.drawText("倾角 L/R", center: CGPoint(x: colX, y: 318),
                     size: 13, weight: .medium, color: dimBlue, align: .left)
        ctx.drawText(String(format: "%.0f°/%.0f°", snapshot.maxLeftLeanDeg, snapshot.maxRightLeanDeg),
                     center: CGPoint(x: valueX, y: 318),
                     size: 15, weight: .semibold, color: cyan, monoDigits: true, align: .right)

        // 当前功率等级英文 tag(原版 IDLE/ECO/SPORT/BOOST/MAX/REGEN)
        ctx.drawText(power.level.tag, center: CGPoint(x: colX + 30, y: 352),
                     size: 15, weight: .bold, color: levelColor(power), align: .left)
    }

    // MARK: - 底部遥测行(TrackCellSpec: title/value/color 三要素)
    private func drawTelemetryRow(in ctx: CGContext, rect: CGRect, snapshot: TelemetrySnapshot) {
        struct Cell {
            let title: String
            let value: String
            let color: UIColor
        }
        let (pctText, pctColor) = ctx.batteryText(snapshot)
        let cells: [Cell] = [
            Cell(title: "本次骑行", value: String(format: "%.1f km", snapshot.tripDistanceKm), color: cyan),
            Cell(title: "骑行时间", value: snapshot.formattedDuration, color: .white),
            Cell(title: "平均速度", value: String(format: "%.0f km/h", snapshot.avgSpeedKmh), color: .white),
            Cell(title: "海拔", value: String(format: "%.0f m", snapshot.altitudeMeters), color: .white),
            Cell(title: "电量", value: pctText, color: pctColor),
        ]

        let rowY: CGFloat = rect.height - 58   // 底部行区域 y≈422
        let margin: CGFloat = 16
        let spacing: CGFloat = 8
        let totalW = rect.width - margin * 2
        let cellW = (totalW - spacing * CGFloat(cells.count - 1)) / CGFloat(cells.count)
        let cellH: CGFloat = 46

        for (i, cell) in cells.enumerated() {
            let x = margin + (cellW + spacing) * CGFloat(i)
            let cardRect = CGRect(x: x, y: rowY, width: cellW, height: cellH)
            // 卡片底(原版 drawSolidCard)
            ctx.fillRoundedRect(cardRect, radius: 10, color: cardBg)
            // 标题(小字蓝灰)
            ctx.drawText(cell.title, center: CGPoint(x: x + cellW / 2, y: rowY + 13),
                         size: 11, weight: .medium, color: dimBlue)
            // 数值(等宽数字)
            ctx.drawText(cell.value, center: CGPoint(x: x + cellW / 2, y: rowY + 32),
                         size: 15, weight: .bold, color: cell.color, monoDigits: true)
        }
    }
}

/// ThemeCore.swift 中 ThemeRegistry 引用名为 TrackProTheme,保留别名保证可编译。
