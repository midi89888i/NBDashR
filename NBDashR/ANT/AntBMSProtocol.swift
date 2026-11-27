import Foundation

// MARK: - ANT BMS BLE 协议(逆向自开源实现 syssi/esphome-ant-bms,与官方「蚂蚁兴能」App 行为一致)
//
// 帧格式(请求与响应同构):
//   0x7E 0xA1 | function(1) | address LE(2) | length/value(1) | payload(n) | crc16 LE(2) | 0xAA 0x55
//   crc16 为 Modbus CRC16(初值 0xFFFF,多项式 0xA001 反向),覆盖 function..payload(不含首尾标记)
// BLE 通道: 服务 0xFFE0,特征 0xFFE1(写 + Notify 同特征)
// 状态轮询: 发送 function=0x01, address=0x0000, value=0xBE(190 字节请求长度)
// 响应 function=0x11 为实时状态帧,0x12 设备信息,0x13 系统日志

public enum AntBMSError: Error, LocalizedError {
    case malformedFrame
    case crcMismatch
    case invalidLength
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .malformedFrame: return "ANT BMS 数据帧格式不正确"
        case .crcMismatch: return "ANT BMS 数据帧 CRC 校验失败"
        case .invalidLength: return "ANT BMS 数据帧长度无效"
        case .notConnected: return "ANT BMS 蓝牙未连接"
        }
    }
}

public enum AntBMSFrame {
    public static let startBytes: (UInt8, UInt8) = (0x7E, 0xA1)
    public static let endBytes: (UInt8, UInt8) = (0xAA, 0x55)

    public enum Function: UInt8 {
        case statusRequest = 0x01      // 主机 -> BMS:请求实时状态
        case deviceInfoRequest = 0x02  // 主机 -> BMS:读取寄存器/设备信息
        case statusResponse = 0x11     // BMS -> 主机:实时状态
        case deviceInfoResponse = 0x12 // BMS -> 主机:设备信息
        case systemLog = 0x13
        case writeRegister = 0x51      // 主机 -> BMS:写寄存器
    }

    /// Modbus CRC16(初值 0xFFFF,反向多项式 0xA001)
    public static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                if crc & 0x01 != 0 {
                    crc = (crc >> 1) ^ 0xA001
                } else {
                    crc >>= 1
                }
            }
        }
        return crc
    }

    /// 组装一条 10 字节命令帧:function + address(LE) + value + crc + tail
    /// 状态轮询: buildCommand(function: .statusRequest, address: 0x0000, value: 0xBE)
    public static func buildCommand(function: Function, address: UInt16, value: UInt8) -> Data {
        var frame = [UInt8]()
        frame.append(startBytes.0)
        frame.append(startBytes.1)
        frame.append(function.rawValue)
        frame.append(UInt8(truncatingIfNeeded: address))       // address low byte
        frame.append(UInt8(truncatingIfNeeded: address >> 8))  // address high byte
        frame.append(value)
        // CRC 覆盖 bytes[1..5](function, addr lo, addr hi, value)即索引 1..5
        let crc = crc16(Array(frame[1...5]))
        frame.append(UInt8(truncatingIfNeeded: crc))           // crc low byte
        frame.append(UInt8(truncatingIfNeeded: crc >> 8))      // crc high byte
        frame.append(endBytes.0)
        frame.append(endBytes.1)
        return Data(frame)
    }

    /// 状态轮询命令(0x7E 0xA1 0x01 0x00 0x00 0xBE crc lo hi 0xAA 0x55)
    public static var statusPollCommand: Data {
        buildCommand(function: .statusRequest, address: 0x0000, value: 0xBE)
    }
}

/// 分片重组器:BLE notify 会把一帧拆成多个 chunk,按 0xAA55 结尾判断完整帧
public final class AntBMSFrameAssembler {
    private var buffer = [UInt8]()
    private let maxBufferedBytes = 512

    public init() {}

    public func reset() { buffer.removeAll(keepingCapacity: true) }

    /// 输入一个 notify chunk,输出 0..n 个完整帧
    public func append(_ data: Data) -> [Data] {
        var frames = [Data]()
        let bytes = [UInt8](data)
        // 帧头到达时清空陈旧缓冲(与 esphome 实现一致)
        if bytes.count >= 2, bytes[0] == 0x7E, bytes[1] == 0xA1 {
            buffer.removeAll(keepingCapacity: true)
        }
        if buffer.count > maxBufferedBytes { buffer.removeAll() }
        buffer.append(contentsOf: bytes)

        while buffer.count >= 10 {
            guard buffer[buffer.count - 2] == 0xAA, buffer[buffer.count - 1] == 0x55 else { break }
            // 完整帧候选
            let function = buffer[2]
            let dataLen = Int(buffer[5])
            let frameLen = 6 + dataLen + 4
            // device info(0x12)帧 length 字段不可靠,放宽
            if frameLen != buffer.count, function != 0x12 {
                buffer.removeAll()
                break
            }
            if frameLen > buffer.count {
                buffer.removeAll()
                break
            }
            let raw = buffer
            let computed = AntBMSFrame.crc16(Array(raw[1..<(frameLen - 4)]))
            let remote = UInt16(raw[frameLen - 3]) << 8 | UInt16(raw[frameLen - 4])
            guard computed == remote else {
                buffer.removeAll()
                break
            }
            frames.append(Data(raw))
            buffer.removeAll()
        }
        return frames
    }
}

// MARK: - 状态帧解码

public struct AntBMSStatus: Equatable, Sendable {
    public var batteryStatusCode: UInt8 = 0      // 0未知 1空闲 2充电 3放电 4待机 5错误
    public var cellCount: UInt8 = 0
    public var temperatureSensorCount: UInt8 = 0
    public var cellVoltages: [Double] = []       // 每串电压 V(0.001 精度)
    public var temperatures: [Double] = []       // 温度 ℃(int16)
    public var mosfetTemperature: Double = 0
    public var balancerTemperature: Double = 0
    public var totalVoltage: Double = 0          // 总压 V(0.01)
    public var current: Double = 0               // 电流 A(0.1, int16,正=充电方向依固件)
    public var socPercent: Double = 0            // SOC %
    public var sohPercent: Double = 0            // SOH %
    public var chargeMosfetStatus: UInt8 = 0
    public var dischargeMosfetStatus: UInt8 = 0
    public var balancerStatus: UInt8 = 0
    public var totalCapacityAh: Double = 0       // 标称容量 Ah(µAh → Ah)
    public var remainingCapacityAh: Double = 0   // 剩余容量 Ah
    public var cycleCapacityAh: Double = 0       // 循环容量 Ah(mAh → Ah)
    public var powerWatts: Double = 0            // 功率 W(int32)
    public var totalRuntimeSec: UInt32 = 0
    public var maxCellVoltage: Double = 0
    public var maxVoltageCell: Int = 0
    public var minCellVoltage: Double = 0
    public var minVoltageCell: Int = 0
    public var deltaCellVoltage: Double = 0
    public var averageCellVoltage: Double = 0

    public var isCharging: Bool { batteryStatusCode == 2 || current > 0.05 }
    public var isDischarging: Bool { batteryStatusCode == 3 || current < -0.05 }

    public static func decodeStatusFrame(_ frame: Data) -> AntBMSStatus? {
        let data = [UInt8](frame)
        guard data.count >= 6, data[0] == 0x7E, data[1] == 0xA1, data[2] == 0x11 else { return nil }
        // length 一致性已由 assembler 校验;此处按字段偏移解码
        func u16(_ i: Int) -> UInt16 {
            guard i + 1 < data.count else { return 0 }
            return UInt16(data[i + 1]) << 8 | UInt16(data[i])
        }
        func i16(_ i: Int) -> Int16 { Int16(bitPattern: u16(i)) }
        func u32(_ i: Int) -> UInt32 {
            // 按 esphome 实现:32bit 由两个 LE 读取的 16bit 以「高字在后」拼接
            UInt32(u16(i + 2)) << 16 | UInt32(u16(i))
        }
        func i32(_ i: Int) -> Int32 { Int32(bitPattern: u32(i)) }

        var s = AntBMSStatus()
        guard data.count > 10 else { return nil }
        s.batteryStatusCode = data[7]
        s.temperatureSensorCount = data[8]
        s.cellCount = data[9]

        let cells = Int(s.cellCount)
        guard cells <= 32 else { return nil }
        var volts = [Double]()
        for i in 0..<cells {
            volts.append(Double(u16(i * 2 + 34)) * 0.001)
        }
        s.cellVoltages = volts

        var offset = cells * 2
        let temps = Int(s.temperatureSensorCount)
        var tempValues = [Double]()
        for i in 0..<temps {
            tempValues.append(Double(i16(i * 2 + 34 + offset)))
        }
        s.temperatures = tempValues
        s.mosfetTemperature = Double(i16(34 + offset))
        s.balancerTemperature = Double(i16(36 + offset))

        s.totalVoltage = Double(u16(38 + offset)) * 0.01
        s.current = Double(i16(40 + offset)) * 0.1
        s.socPercent = Double(u16(42 + offset))
        s.sohPercent = Double(u16(44 + offset))
        s.chargeMosfetStatus = data[46 + offset]
        s.dischargeMosfetStatus = data[47 + offset]
        s.balancerStatus = data[48 + offset]

        s.totalCapacityAh = Double(u32(50 + offset)) * 0.000001
        s.remainingCapacityAh = Double(u32(54 + offset)) * 0.000001
        s.cycleCapacityAh = Double(u32(58 + offset)) * 0.001
        s.powerWatts = Double(i32(62 + offset))
        s.totalRuntimeSec = u32(66 + offset)
        s.maxCellVoltage = Double(u16(74 + offset)) * 0.001
        s.maxVoltageCell = Int(u16(76 + offset))
        s.minCellVoltage = Double(u16(78 + offset)) * 0.001
        s.minVoltageCell = Int(u16(80 + offset))
        s.deltaCellVoltage = Double(u16(82 + offset)) * 0.001
        s.averageCellVoltage = Double(u16(84 + offset)) * 0.001
        return s
    }
}
