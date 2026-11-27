import Foundation
import Network

/// 轻量 UDP 发送 socket,基于 Network.framework。
/// 九号 5 寸仪表:视频帧 → 5012,控制/心跳 → 5013(依 xmz28/ninebot_pro 协议)。
final class UDPSocket {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "udp.socket", qos: .userInteractive)
    private var ready = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    let host: String
    let port: UInt16

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
        connection = NWConnection(host: NWEndpoint.Host(host),
                                  port: NWEndpoint.Port(rawValue: port)!,
                                  parameters: .udp)
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.ready = true
                let pending = self.continuations
                self.continuations.removeAll()
                pending.forEach { $0.resume() }
            case .failed, .cancelled:
                self.ready = false
                let pending = self.continuations
                self.continuations.removeAll()
                pending.forEach { $0.resume() }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func waitReady() async {
        if ready { return }
        await withCheckedContinuation { c in
            queue.async { [weak self] in
                guard let self else { c.resume(); return }
                if self.ready { c.resume() } else { self.continuations.append(c) }
            }
        }
    }

    func send(_ data: Data) {
        guard ready else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    func sendBatch(_ datagrams: [Data]) {
        guard ready else { return }
        for d in datagrams {
            connection.send(content: d, completion: .contentProcessed { _ in })
        }
    }

    func stop() {
        connection.stateUpdateHandler = nil
        connection.cancel()
        ready = false
    }

    deinit { stop() }
}
