import Foundation
import CoreGraphics
import CoreVideo
import UIKit

/// CoreGraphics 绘制原语封装(参照原版 Canvas 协议:drawText/drawArc/drawPill 等)。
/// 848×480 离屏位图上下文,产出 CVPixelBuffer 供编码器消费。
final class DashCanvas {
    let width: Int
    let height: Int
    private(set) var context: CGContext?
    private var pixelBuffer: CVPixelBuffer?

    init(width: Int = 848, height: Int = 480) {
        self.width = width
        self.height = height
    }

    func begin() -> (CGContext, CVPixelBuffer)? {
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
        guard let pixelBuffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let rgb = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: base, width: width, height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                  space: rgb,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        // UIKit 语义翻转:y 向下
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        self.context = ctx
        self.pixelBuffer = pixelBuffer
        return (ctx, pixelBuffer)
    }

    func end() {
        if let pixelBuffer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        context = nil
        pixelBuffer = nil
    }
}

extension CGContext {
    func fillBackground(_ color: UIColor, in rect: CGRect) {
        setFillColor(color.cgColor)
        fill(rect)
    }

    func drawPill(rect: CGRect, color: UIColor, cornerRadius: CGFloat? = nil) {
        let r = cornerRadius ?? rect.height / 2
        let path = UIBezierPath(roundedRect: rect, cornerRadius: r)
        setFillColor(color.cgColor)
        addPath(path.cgPath)
        fillPath()
    }

    func strokePill(rect: CGRect, color: UIColor, lineWidth: CGFloat, cornerRadius: CGFloat? = nil) {
        let r = cornerRadius ?? rect.height / 2
        let path = UIBezierPath(roundedRect: rect, cornerRadius: r)
        setStrokeColor(color.cgColor)
        setLineWidth(lineWidth)
        addPath(path.cgPath)
        strokePath()
    }

    /// 居中绘制文本,返回实际尺寸。monoDigits 用等宽数字字体。
    @discardableResult
    func drawText(_ string: String, center: CGPoint, size: CGFloat, weight: UIFont.Weight,
                  color: UIColor, monoDigits: Bool = false, align: NSTextAlignment = .center) -> CGSize {
        let font: UIFont = monoDigits
            ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : UIFont.systemFont(ofSize: size, weight: weight)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let str = NSAttributedString(string: string, attributes: attrs)
        let textSize = str.size()
        var x = center.x - textSize.width / 2
        if align == .left { x = center.x }
        if align == .right { x = center.x - textSize.width }
        str.draw(at: CGPoint(x: x, y: center.y - textSize.height / 2))
        return textSize
    }

    /// 圆弧:angle 单位为度,0=正上方,顺时针。
    func drawArc(center: CGPoint, radius: CGFloat, lineWidth: CGFloat,
                 startDeg: CGFloat, endDeg: CGFloat, color: UIColor, lineCap: CGLineCap = .round) {
        let start = (startDeg - 90) * .pi / 180
        let end = (endDeg - 90) * .pi / 180
        setStrokeColor(color.cgColor)
        setLineWidth(lineWidth)
        setLineCap(lineCap)
        addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        strokePath()
    }

    func drawLine(from: CGPoint, to: CGPoint, color: UIColor, width: CGFloat) {
        setStrokeColor(color.cgColor)
        setLineWidth(width)
        move(to: from)
        addLine(to: to)
        strokePath()
    }

    func fillCircle(center: CGPoint, radius: CGFloat, color: UIColor) {
        setFillColor(color.cgColor)
        fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius*2, height: radius*2))
    }

    func fillRoundedRect(_ rect: CGRect, radius: CGFloat, color: UIColor) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        setFillColor(color.cgColor)
        addPath(path.cgPath)
        fillPath()
    }

    func fillRect(_ rect: CGRect, color: UIColor) {
        setFillColor(color.cgColor)
        fill(rect)
    }

    func drawVerticalGradient(rect: CGRect, colors: [UIColor]) {
        guard colors.count >= 2 else {
            setFillColor((colors.first ?? .black).cgColor); fill(rect); return
        }
        let cgColors = colors.map { $0.cgColor } as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil) else { return }
        saveGState()
        clip(to: rect)
        drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY),
                           end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        restoreGState()
    }
}
