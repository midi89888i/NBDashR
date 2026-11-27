import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

/// VideoToolbox H.264 硬编码器,输出 Annex-B(带 SPS/PPS 注入)。
/// 九号仪表协议要求 Baseline 3.1,848×480。
final class H264Encoder {
    private var session: VTCompressionSession?
    private var sps: Data?
    private var pps: Data?
    private var keyframeRequested = true

    let width: Int
    let height: Int
    var bitrate: Int
    var fps: Int
    var onEncoded: ((Data, Bool) -> Void)?   // (annexB frame, isKeyframe)

    init(width: Int, height: Int, bitrate: Int, fps: Int) {
        self.width = width
        self.height = height
        self.bitrate = bitrate
        self.fps = fps
    }

    func start() throws {
        var session: VTCompressionSession?
        let callback: VTCompressionOutputCallback = { refcon, _, status, _, sampleBuffer in
            guard status == noErr, let sampleBuffer, let refcon else { return }
            let encoder = Unmanaged<H264Encoder>.fromOpaque(refcon).takeUnretainedValue()
            encoder.handleEncoded(sampleBuffer)
        }
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width), height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: callback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        guard status == noErr, let session else {
            throw NSError(domain: "H264Encoder", code: Int(status))
        }
        self.session = session
        configure()
        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    private func configure() {
        guard let session else { return }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel,
                             value: kVTProfileLevel_H264_Baseline_3_1)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: bitrate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                             value: (fps * 2) as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
                             value: 2 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate,
                             value: fps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime,
                             value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering,
                             value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits,
                             value: [bitrate / 4, 0.2] as CFArray)
    }

    func updateBitrate(_ newBitrate: Int) {
        bitrate = newBitrate
        guard let session else { return }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: newBitrate as CFNumber)
    }

    func requestKeyframe() { keyframeRequested = true }

    func encode(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard let session else { return }
        var props: [CFString: Any] = [:]
        if keyframeRequested {
            props[kVTEncodeFrameOptionKey_ForceKeyFrame] = kCFBooleanTrue
            keyframeRequested = false
        }
        var flags: VTEncodeInfoFlags = []
        VTCompressionSessionEncodeFrame(session, imageBuffer: pixelBuffer,
                                        presentationTimeStamp: timestamp,
                                        duration: CMTime(value: 1, timescale: CMTimeScale(fps)),
                                        frameProperties: props as CFDictionary,
                                        infoFlagsOut: &flags, outputHandler: nil)
    }

    private func handleEncoded(_ sampleBuffer: CMSampleBuffer) {
        let isKeyframe: Bool = {
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
                  let first = attachments.first else { return false }
            return !(first[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
        }()
        if isKeyframe { extractParameterSets(sampleBuffer) }
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
              let pointer else { return }
        // AVCC → Annex-B 转换
        var annexB = Data()
        var offset = 0
        while offset < length - 4 {
            var naluLength: UInt32 = 0
            memcpy(&naluLength, pointer + offset, 4)
            naluLength = CFSwapInt32BigToHost(naluLength)
            guard naluLength > 0, offset + 4 + Int(naluLength) <= length else { break }
            annexB.append(contentsOf: [0, 0, 0, 1])
            annexB.append(Data(bytes: pointer + offset + 4, count: Int(naluLength)))
            offset += 4 + Int(naluLength)
        }
        if isKeyframe, let sps, let pps {
            var withParams = Data()
            withParams.append(contentsOf: [0, 0, 0, 1]); withParams.append(sps)
            withParams.append(contentsOf: [0, 0, 0, 1]); withParams.append(pps)
            withParams.append(annexB)
            annexB = withParams
        }
        onEncoded?(annexB, isKeyframe)
    }

    private func extractParameterSets(_ sampleBuffer: CMSampleBuffer) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        var count = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: 0,
            parameterSetPointerOut: nil, parameterSetSizeOut: nil,
            parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
        for i in 0..<count {
            var ptr: UnsafePointer<UInt8>?
            var size = 0
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: i,
                parameterSetPointerOut: &ptr, parameterSetSizeOut: &size,
                parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
            guard let ptr, size > 0 else { continue }
            let data = Data(bytes: ptr, count: size)
            if i == 0 { sps = data } else { pps = data }
        }
    }

    func invalidate() {
        if let session {
            VTCompressionSessionInvalidate(session)
        }
        session = nil
    }
}
