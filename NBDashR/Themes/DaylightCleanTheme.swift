import Foundation
import UIKit
import CoreGraphics

/// 「极简高亮」主题 —— 由 daylight.txt (约 1600 条 ARM64 指令) 反汇编翻译还原。
/// 848×480 画布。大字号高对比黑白风格:浅色底,左侧超大车速 + 中部功率大字,
/// 右侧遥测卡片,顶部分段速度标尺条,底部 G 力横条(BRK/ACC)。
/// 反汇编中 RGB 分量以 0..255 双精度常量传入绘制原语,此处换算为 0..1。
struct DaylightCleanTheme: DashboardThemeRenderer {
    let id = "daylightClean"
    let displayName = "极简高亮"
    let subtitle = "超大高对比字号 · 强光直视清晰"

    // MARK: - 配色(0..255 常量取自反汇编;主题黑白高对比)
    // 整屏底色即高光浅蓝灰 (225,232,242),面板用更浅一档 (236,240,247),正文近黑
    private let bg        = UIColor(red: 225/255.0, green: 232/255.0, blue: 242/255.0, alpha: 1)  // 满屏浅蓝灰底
    private let ink       = UIColor(red: 0, green: 0, blue: 0, alpha: 1)              // 主文本黑
    private let inkSoft   = UIColor(white: 0, alpha: 0.55)                            // 次级标签
    private let bandBlue  = UIColor(red: 210/255.0, green: 218/255.0, blue: 230/255.0, alpha: 1)  // 高光带暗一档
    private let bandLight = UIColor(red: 236/255.0, green: 240/255.0, blue: 247/255.0, alpha: 1)  // 面板浅蓝灰
    private let bandLight2 = UIColor(red: 236/255.0, green: 240/255.0, blue: 247/255.0, alpha: 1) // 底部浅蓝灰
    private let regenGrn  = UIColor(red: 0/255.0, green: 145/255.0, blue: 72/255.0, alpha: 1)     // 回收绿
    private let hotRed    = UIColor(red: 255/255.0, green: 55/255.0, blue: 40/255.0, alpha: 1)    // 高功率/制动红
    private let divider   = UIColor(white: 0, alpha: 0.12)

    // 按速度/功率条件着色的三组分量(反汇编 fcsel 链条中出现):
    // 慢速/低量 → 深灰黑;高速/高量 → 提亮。映射为 ink / accent 两档。

    func draw(in ctx: CGContext, rect: CGRect, snapshot: TelemetrySnapshot, power: PowerReading) {
        ctx.fillBackground(bg, in: rect)
        drawHighlightBands(ctx)
        drawSpeedScaleStrip(ctx, snapshot: snapshot)
        drawHeroSpeed(ctx, snapshot: snapshot)
        drawPowerBlock(ctx, snapshot: snapshot, power: power)
        drawLeftRail(ctx, snapshot: snapshot)
        drawRightColumn(ctx, snapshot: snapshot)
        drawBottomStrip(ctx, snapshot: snapshot, power: power)
        drawGForceBar(ctx, snapshot: snapshot)
    }

    // MARK: - 高光带:y 49 附近的横向渐变带(=610 x 尺寸)与右下浅蓝块
    private func drawHighlightBands(_ ctx: CGContext) {
        // 顶部横向高光带:宽 610、起始 y≈49,色 (210,218,230)
        ctx.fillRoundedRect(CGRect(x: 0, y: 49, width: 610, height: 8),
                            radius: 4, color: bandBlue.withAlphaComponent(0.9))
        // 右上浅蓝面板(x 614..828,y 214..330,源自 614/274/214/116 常量)
        ctx.fillRoundedRect(CGRect(x: 614, y: 214, width: 214, height: 116),
                            radius: 16, color: bandLight)
        // 底部信息条底色(y≈404..442,x 60..808,源自 404/808/60/442)
        ctx.fillRoundedRect(CGRect(x: 60, y: 404, width: 748, height: 38),
                            radius: 16, color: bandLight2)
        // G 力条轨道底色(y≈442..480,源自 442/480/58/0.59375 常量)
        ctx.fillRoundedRect(CGRect(x: 385, y: 452, width: 190, height: 20),
                            radius: 10, color: bandLight2)
    }

    // MARK: - 顶部分段速度标尺:x 256→572, y 316/338,段数随速度量程变化
    /// 反汇编循环:段中心 x = 256 + i/count*316,数字文本 y=370,字号随速度 ≥60 切换 45/55
    private func drawSpeedScaleStrip(_ ctx: CGContext, snapshot: TelemetrySnapshot) {
        let v = snapshot.speedKmh
        let scale = speedScale(snapshot)
        let count = Int(scale / 10)            // 每 10 km/h 一格
        guard count > 0 else { return }
        // 横轨
        ctx.fillRoundedRect(CGRect(x: 256, y: 330, width: 316, height: 8),
                            radius: 4, color: divider)
        let litFrac = min(max(v / scale, 0), 1)
        let litColor = v >= 60 ? hotRed : ink
        for i in 0...count {
            let frac = CGFloat(i) / CGFloat(count)
            let cx = 256 + frac * 316
            let lit = frac <= CGFloat(litFrac)
            let tickH: CGFloat = (i % 5 == 0) ? 20 : 12
            ctx.fillRoundedRect(CGRect(x: cx - 2, y: 328 - tickH / 2 + 4, width: 4, height: tickH),
                                radius: 2, color: lit ? litColor : divider)
            if i % 5 == 0 {
                // 数字标签 y=370 区域,字号 =110/125/148 为条宽相关常量,标签用 16
                ctx.drawText("\(i * 10)", center: CGPoint(x: cx, y: 370),
                             size: 16, weight: .semibold,
                             color: lit ? ink : inkSoft, monoDigits: true)
            }
        }
        // 当前速度游标
        let curX = 256 + CGFloat(litFrac) * 316
        ctx.fillRoundedRect(CGRect(x: curX - 4, y: 320, width: 8, height: 28),
                            radius: 4, color: litColor)
    }

    private func speedScale(_ snapshot: TelemetrySnapshot) -> Double {
        let vmax = max(60, snapshot.maxSpeedKmh, snapshot.speedKmh, 1)
        return (vmax / 10).rounded(.up) * 10
    }

    // MARK: - 超大车速:x 居中于左区(≈157..233 区段),字号 ≥60km/h 时 196,否则 233;颜色按速度条件
    /// 反汇编:速度 ≥60 字号取 196、否则 233(或反向);文本 "km/h" 紧邻其下
    private func drawHeroSpeed(_ ctx: CGContext, snapshot: TelemetrySnapshot) {
        let v = snapshot.speedKmh
        let big = v >= 60
        // 速度数字:字号 196(高速) / 233(低速),居中 x≈255,y≈160
        let fontSize: CGFloat = big ? 196 : 233
        let color = v >= 60 ? hotRed : ink
        ctx.drawText("\(Int(v.rounded()))", center: CGPoint(x: 255, y: 168),
                     size: fontSize, weight: .heavy, color: color, monoDigits: true)
        // 单位 "km/h",y≈302,字号 38(=38 常量),下方 min:sec 时长标签
        ctx.drawText("km/h", center: CGPoint(x: 255, y: 302),
                     size: 38, weight: .bold, color: inkSoft, monoDigits: true)
    }

    // MARK: - 功率大字区:y 316..370 右侧段,实时功率 + 峰值/回收
    /// 反汇编:功率等级文本 idle/eco/sport/boost/max/regen/unavailable 全中文映射:
    /// idle=待命 eco=经济 sport=运动 boost=推背 max=全力 regen=回收 unavailable=--
    private func levelLabel(_ level: PowerLevel) -> String {
        switch level {
        case .unavailable: return "--"
        case .idle: return "待命"
        case .regen: return "回收"
        case .eco: return "经济"
        case .sport: return "运动"
        case .boost: return "推背"
        case .max: return "全力"
        }
    }

    private func drawPowerBlock(_ ctx: CGContext, snapshot: TelemetrySnapshot, power: PowerReading) {
        // 等级标签(x≈630,y≈296,字号随等级长短在 75/88/108 中选)
        let tag = levelLabel(power.level)
        let tagColor = power.isRegen ? regenGrn : (power.level == .max || power.level == .boost ? hotRed : ink)
        let tagSize: CGFloat = tag.count >= 2 ? 88 : 108
        ctx.drawText(tag, center: CGPoint(x: 630, y: 296),
                     size: tagSize, weight: .heavy, color: tagColor)
        // 功率数值(x≈630,y≈336,字号随功率大小在 0.875/90/104/159/110/128 级联中选,取 110)
        let pw = TelemetrySnapshot.formatPower(power.watts)
        ctx.drawText(pw, center: CGPoint(x: 630, y: 356),
                     size: 110, weight: .bold, color: tagColor, monoDigits: true)
        // 峰值标签 "极速"(x≈812 右对齐,y≈296,字号 75-108 级联,取 44);下方紧跟 " km/h" 单位
        ctx.drawText("极速", center: CGPoint(x: 812, y: 252),
                     size: 40, weight: .semibold, color: inkSoft)
        ctx.drawText(String(format: "%.0f", snapshot.maxSpeedKmh),
                     center: CGPoint(x: 812, y: 292),
                     size: 56, weight: .bold, color: ink, monoDigits: true)
        ctx.drawText(" km/h", center: CGPoint(x: 812, y: 322),
                     size: 22, weight: .semibold, color: inkSoft, monoDigits: true)
    }

    // MARK: - 左侧信息栏:本次里程 / 骑行时长 / 海拔 / 续航
    /// 反汇编字符串:"本次里程" "骑行时长" "海拔 " "续航 " "km" "m"
    private func drawLeftRail(_ ctx: CGContext, snapshot: TelemetrySnapshot) {
        // 里程大字 x≈118 左对齐,y≈150;min:sec 时长 x≈118 y≈368(=368 常量)
        ctx.drawText("本次里程", center: CGPoint(x: 40, y: 118),
                     size: 22, weight: .medium, color: inkSoft, align: .left)
        ctx.drawText(String(format: "%.1f", snapshot.tripDistanceKm),
                     center: CGPoint(x: 40, y: 150),
                     size: 46, weight: .bold, color: ink, monoDigits: true, align: .left)
        ctx.drawText("km", center: CGPoint(x: 40, y: 197),
                     size: 26, weight: .semibold, color: inkSoft, monoDigits: true, align: .left)
        ctx.drawText("骑行时长", center: CGPoint(x: 40, y: 330),
                     size: 22, weight: .medium, color: inkSoft, align: .left)
        ctx.drawText(snapshot.formattedDuration, center: CGPoint(x: 40, y: 362),
                     size: 38, weight: .bold, color: ink, monoDigits: true, align: .left)
    }

    // MARK: - 右列遥测:海拔 / 续航 / 均速 / 电压(右上浅蓝面板内)
    /// 反汇编字符串:"海拔 " "续航 " "均速 " "电压";单位 "m" "km"
    private func drawRightColumn(_ ctx: CGContext, snapshot: TelemetrySnapshot) {
        let x: CGFloat = 640
        var y: CGFloat = 235
        let rows: [(String, String)] = [
            ("海拔", String(format: "%.0f m", snapshot.altitudeMeters)),
            ("均速", String(format: "%.1f km/h", snapshot.avgSpeedKmh)),
        ]
        for (label, value) in rows {
            ctx.drawText(label, center: CGPoint(x: x, y: y),
                         size: 22, weight: .medium, color: inkSoft, align: .left)
            ctx.drawText(value, center: CGPoint(x: x + 96, y: y),
                         size: 26, weight: .bold, color: ink, monoDigits: true, align: .right)
            y += 42
        }
    }

    // MARK: - 底部信息条:电量 / 电压 / 峰值功率 / 峰值回收(y 404..442,x 60..808)
    /// 反汇编底部段:"功率" "回收" 标签,功率文本后缀 " km/h  · "(组合字符串拼接),
    /// 字号 40/55/35 常量;电量条件着色(>20% 黑,否则红)
    private func drawBottomStrip(_ ctx: CGContext, snapshot: TelemetrySnapshot, power: PowerReading) {
        let cy: CGFloat = 423
        // 电量
        let (pctText, _) = ctx.batteryText(snapshot)
        let pct = snapshot.batteryPercent ?? 0
        let pctColor: UIColor = pct > 20 ? ink : hotRed
        ctx.drawText("⚡\(pctText)", center: CGPoint(x: 120, y: cy),
                     size: 30, weight: .bold, color: pctColor, monoDigits: true)
        // 电压
        if let volts = snapshot.batteryVoltage {
            ctx.drawText("电压", center: CGPoint(x: 252, y: cy - 8),
                         size: 18, weight: .medium, color: inkSoft)
            ctx.drawText(String(format: "%.1fV", volts), center: CGPoint(x: 252, y: cy + 8),
                         size: 24, weight: .bold, color: ink, monoDigits: true)
        }
        // 峰值功率
        ctx.drawText("功率", center: CGPoint(x: 470, y: cy - 8),
                     size: 18, weight: .medium, color: inkSoft)
        ctx.drawText(TelemetrySnapshot.formatPower(snapshot.peakPowerWatts),
                     center: CGPoint(x: 470, y: cy + 8),
                     size: 24, weight: .bold, color: ink, monoDigits: true)
        // 峰值回收
        ctx.drawText("回收", center: CGPoint(x: 640, y: cy - 8),
                     size: 18, weight: .medium, color: inkSoft)
        ctx.drawText(TelemetrySnapshot.formatPower(snapshot.peakRegenWatts),
                     center: CGPoint(x: 640, y: cy + 8),
                     size: 24, weight: .bold, color: regenGrn, monoDigits: true)
        // 连接状态(右端)
        let conn = snapshot.antConnected ? "ANT" : (snapshot.bleConnected ? "BLE" : "--")
        ctx.drawText(conn, center: CGPoint(x: 770, y: cy),
                     size: 22, weight: .semibold, color: inkSoft, monoDigits: true)
    }

    // MARK: - 底部 G 力横条:y≈426..442,x 391..812 区段,加速黑 / 制动红,BRK / ACC 端标签
    /// 反汇编:|g|×89 像素比例;g 超界时颜色分量 (145,225,..) 加速 / (78,72,..) 制动;
    /// "BRK"(x≈385) "ACC"(x≈575) 字号 16.5,中轴 (480,429)
    private func drawGForceBar(_ ctx: CGContext, snapshot: TelemetrySnapshot) {
        let cy: CGFloat = 462
        let cx: CGFloat = 480
        let halfW: CGFloat = 89          // =89.0 比例系数(px/G)
        // 基线轨道(x 385..575 中心段,±1G 位置)
        ctx.fillRoundedRect(CGRect(x: cx - halfW, y: cy - 3, width: halfW * 2, height: 6),
                            radius: 3, color: divider)
        let g = snapshot.longitudinalG
        let mag = CGFloat(min(abs(g), 1.0)) * halfW
        if mag > 2 {
            let accel = g > 0
            let color = accel ? ink : hotRed   // 加速黑,制动红(高对比)
            let x0 = accel ? cx : cx - mag
            ctx.fillRoundedRect(CGRect(x: x0, y: cy - 7, width: mag, height: 14),
                                radius: 7, color: color)
        }
        ctx.fillCircle(center: CGPoint(x: cx, y: cy), radius: 5, color: ink)
        ctx.drawText("BRK", center: CGPoint(x: 385, y: cy),
                     size: 16.5, weight: .bold, color: hotRed, monoDigits: true, align: .right)
        ctx.drawText("ACC", center: CGPoint(x: 575, y: cy),
                     size: 16.5, weight: .bold, color: ink, monoDigits: true, align: .left)
    }
}
