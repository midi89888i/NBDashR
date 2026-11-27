import SwiftUI
import CoreGraphics
import VideoToolbox

/// 848×480 渲染预览:与推流画面同一渲染路径(同主题同数据)。
struct DashboardPreviewCard: View {
    @EnvironmentObject var controller: AppController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15)) { _ in
            Canvas { ctx, size in
                guard let image = renderPreview() else { return }
                ctx.draw(Image(decorative: image, scale: 1), in: CGRect(origin: .zero, size: size))
            }
            .aspectRatio(848.0 / 480.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary, lineWidth: 1))
        }
    }

    private func renderPreview() -> CGImage? {
        let canvas = DashCanvas(width: 848, height: 480)
        guard let (ctx, pixelBuffer) = canvas.begin() else { return nil }
        let rect = CGRect(x: 0, y: 0, width: 848, height: 480)
        controller.theme.draw(in: ctx, rect: rect,
                              snapshot: controller.snapshot, power: controller.powerReading)
        canvas.end()
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        return cgImage
    }
}

