import Foundation
import CoreVideo
import CoreMedia
import Combine

/// 推流管线:CVPixelBuffer → H264 → 私有RTP → UDP 5012(视频)/5013(控制心跳)
@MainActor
final class Streamer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var framesSent: UInt64 = 0
    @Published private(set) var lastError: String?

    private var videoSocket: UDPSocket?
    private var controlSocket: UDPSocket?
    private var encoder: H264Encoder?
    private var sequence: UInt16 = 0
    private var heartbeatCounter: UInt32 = 0
    private var heartbeatTimer: Timer?
    private var startUptime: TimeInterval = 0
    private let ssrc: UInt32 = UInt32.random(in: 1...UInt32.max)

    let targetHost: String
    let bitrate: Int
    let fps: Int

    init(targetHost: String = "192.168.169.1", bitrate: Int = 1_500_000, fps: Int = 30) {
        self.targetHost = targetHost
        self.bitrate = bitrate
        self.fps = fps
    }

    func start(width: Int, height: Int) async {
        guard !isRunning else { return }
        let video = UDPSocket(host: targetHost, port: 5012)
        let control = UDPSocket(host: targetHost, port: 5013)
        video.start(); control.start()
        videoSocket = video; controlSocket = control
        async let v: Void = video.waitReady()
        async let c: Void = control.waitReady()
        _ = await (v, c)

        let enc = H264Encoder(width: width, height: height, bitrate: bitrate, fps: fps)
        enc.onEncoded = { [weak self] annexB, isKeyframe in
            guard let self else { return }
            Task { @MainActor in self.handleEncoded(annexB, isKeyframe: isKeyframe) }
        }
        do {
            try enc.start()
            encoder = enc
        } catch {
            lastError = "编码器启动失败"
            return
        }
        startUptime = ProcessInfo.processInfo.systemUptime
        sequence = 0
        heartbeatCounter = 0
        framesSent = 0
        startHeartbeat()
        isRunning = true
    }

    private func handleEncoded(_ annexB: Data, isKeyframe: Bool) {
        guard isRunning, let videoSocket else { return }
        let ts = UInt32((ProcessInfo.processInfo.systemUptime - startUptime) * 1000)
        var seq = sequence
        let packets = Packetizer.makeVideoPackets(annexB: annexB, timestampMs: ts,
                                                  isKeyframe: isKeyframe, ssrc: ssrc,
                                                  sequence: &seq)
        sequence = seq
        videoSocket.sendBatch(packets)
        framesSent += 1
    }

    func encode(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard isRunning else { return }
        encoder?.encode(pixelBuffer, timestamp: timestamp)
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sendHeartbeat() }
        }
    }

    private func sendHeartbeat() {
        guard let controlSocket else { return }
        heartbeatCounter &+= 1
        controlSocket.send(Packetizer.makeHeartbeat(index: heartbeatCounter, ssrc: ssrc))
    }

    func stop() async {
        guard isRunning else { return }
        heartbeatTimer?.invalidate(); heartbeatTimer = nil
        // BYE × 3 确保仪表收到
        if let controlSocket {
            let bye = Packetizer.makeBYE(ssrc: ssrc)
            controlSocket.send(bye); controlSocket.send(bye); controlSocket.send(bye)
        }
        encoder?.invalidate(); encoder = nil
        try? await Task.sleep(nanoseconds: 300_000_000)
        videoSocket?.stop(); controlSocket?.stop()
        videoSocket = nil; controlSocket = nil
        isRunning = false
    }
}
