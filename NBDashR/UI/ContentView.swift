import SwiftUI

struct ContentView: View {
    @EnvironmentObject var controller: AppController

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DashboardPreviewCard()
                    controlCard
                    themePicker
                    statusCard
                    NavigationLink {
                        NinebotVehiclePairingView(connection: controller.vehicleConnection, locked: false)
                    } label: {
                        Label("车辆配对(免九号出行)", systemImage: "link.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    NavigationLink {
                        ANTSettingsView(client: controller.antClient)
                    } label: {
                        Label("ANT 保护板设置", systemImage: "bolt.batteryblock")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    logCard
                }
                .padding()
            }
            .navigationTitle("NBDashR")
        }
    }

    private var controlCard: some View {
        VStack(spacing: 12) {
            Button {
                controller.toggleStreaming()
            } label: {
                Label(controller.isStreaming ? "停止仪表投屏" : "启动仪表投屏",
                      systemImage: controller.isStreaming ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(controller.isStreaming ? .red : .green)

            HStack {
                Toggle("打开 App 自动投屏", isOn: $controller.autoProjectionEnabled)
            }
            HStack {
                Toggle("演示模式(无车调试)", isOn: $controller.isDemoMode)
            }
            HStack {
                Text("仪表 IP")
                TextField("192.168.169.1", text: Binding(
                    get: { controller.targetIP },
                    set: { controller.targetIP = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)
                .frame(maxWidth: 160)
                Button("重置行程") { controller.resetTrip() }
            }
            .font(.callout)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("仪表主题").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ThemeRegistry.all, id: \.id) { theme in
                        Button {
                            controller.selectedThemeID = theme.id
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(theme.displayName).font(.subheadline.bold())
                                Text(theme.subtitle).font(.caption2).foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(10)
                            .frame(width: 150, alignment: .leading)
                            .background(controller.selectedThemeID == theme.id
                                        ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(controller.selectedThemeID == theme.id ? Color.accentColor : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("状态").font(.headline)
            statusRow("车辆会话", vehiclePhaseText)
            statusRow("ANT 保护板", controller.antClient.status != nil ? "已连接 · SOC \(Int(controller.antClient.status?.socPercent ?? 0))%" : "未连接")
            statusRow("GPS", controller.sensors.hasGPSFix ? "定位正常" : "等待定位")
            statusRow("推流", controller.isStreaming ? "进行中" : "已停止")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var vehiclePhaseText: String {
        switch controller.vehicleConnection.phase {
        case .active: return "已唤醒(导航中)"
        case .idle: return "空闲"
        case .scanning: return "扫描中"
        case .connecting: return "连接中"
        case .discovering: return "发现服务"
        case .preparing: return "读取认证参数"
        case .needsPairing: return "待配对"
        case .pairing: return "配对中"
        case .authenticating: return "认证中"
        case .starting: return "开启导航中"
        case .reconnecting: return "重连中"
        case .stopping: return "停止中"
        case .unavailable: return "不可用"
        case .failed: return "失败"
        }
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.callout)
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("日志").font(.headline)
            ForEach(Array(controller.logs.prefix(12).enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
