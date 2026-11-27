import Foundation

/// 九号 5 寸仪表私有 RTP 分包(移植自 OpenNinebot cast_protocol.cpp, MIT)。
///
/// 视频包(非 pro 模式,匹配原版 NinebotDash 5 寸行为):
///   byte 0    : 0x90
///   byte 1    : 0x20 | (last ? 0x80 : 0)     — payload type + marker
///   byte 2-3  : sequence number BE (uint16, 递增跨帧连续)
///   byte 4-7  : timestamp BE (uint32, ms)
///   byte 8-11 : ssrc BE
///   byte 12-15: 1 BE(固定)
///   byte 16-19: keyframe ? 0x00010000 : 0x00020000 BE
///   byte 20+  : annexB 分片载荷,每片 ≤ 1400 字节
///   关键帧重复发送 2 遍(repeat=true 时)
///
/// 心跳(非 pro,发往 5013):
///   0x85 0xCC 00 03 | ssrc BE(4) | 'mpv' | index LE(4)   共 16 字节
///
/// BYE 停止:80 cb 00 00(RTCP BYE 头,原版日志佐证)

enum Packetizer {
    static let payloadLimit = 1400

    private static func be16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(truncatingIfNeeded: v)] }
    private static func be32(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24), UInt8(truncatingIfNeeded: v >> 16),
         UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v)]
    }
    private static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8),
         UInt8(truncatingIfNeeded: v >> 16), UInt8(v >> 24)]
    }

    /// 把一帧 annexB 打成 RTP 包序列。sequence 跨调用保持连续。
    static func makeVideoPackets(annexB: Data, timestampMs: UInt32, isKeyframe: Bool,
                                 ssrc: UInt32, sequence: inout UInt16,
                                 repeatKeyframe: Bool = true) -> [Data] {
        let bytes = [UInt8](annexB)
        guard !bytes.isEmpty else { return [] }
        let copies = (isKeyframe && repeatKeyframe) ? 2 : 1
        var out: [Data] = []
        for _ in 0..<copies {
            var p = 0
            while p < bytes.count {
                let n = min(payloadLimit, bytes.count - p)
                let last = (p + n == bytes.count)
                var pkt = Data()
                pkt.reserveCapacity(20 + n)
                pkt.append(0x90)
                pkt.append(0x20 | (last ? 0x80 : 0))
                pkt.append(contentsOf: be16(sequence)); sequence &+= 1
                pkt.append(contentsOf: be32(timestampMs))
                pkt.append(contentsOf: be32(ssrc))
                pkt.append(contentsOf: be32(1))
                pkt.append(contentsOf: be32(isKeyframe ? 0x00010000 : 0x00020000))
                pkt.append(contentsOf: bytes[p..<(p + n)])
                out.append(pkt)
                p += n
            }
        }
        return out
    }

    static func makeHeartbeat(index: UInt32, ssrc: UInt32) -> Data {
        var b = Data()
        b.append(contentsOf: [0x85, 0xCC, 0x00, 0x03])
        b.append(contentsOf: be32(ssrc))
        b.append(contentsOf: [UInt8(ascii: "m"), UInt8(ascii: "p"), UInt8(ascii: "v")])
        b.append(contentsOf: le32(index))
        return b
    }

    /// RTCP BYE:停止信号(原版日志: 80 cb 00 00)
    static func makeBYE(ssrc: UInt32) -> Data {
        var b = Data([0x80, 0xcb, 0x00, 0x01])
        b.append(contentsOf: be32(ssrc))
        return b
    }
}
