import SwiftUI

struct ANTSettingsView: View {
    @ObservedObject var client: AntBMSClient
    @AppStorage("ant.bound.id") private var boundID: String = ""
    @AppStorage("ant.bound.name") private var boundName: String = ""

    var body: some View {
        Form {
            Section("绑定设备") {
                if !boundName.isEmpty {
                    HStack {
                        Text("已绑定")
                        Spacer()
                        Text(boundName).foregroundStyle(.secondary)
                        Button("解绑", role: .destructive) {
                            boundID = ""; boundName = ""
                            client.disconnect()
                        }
                    }
                }
                if client.discovered.isEmpty {
                    HStack {
                        ProgressView()
                        Text("扫描 ANT 保护板中…").foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(Array(client.discovered.keys), id: \.self) { id in
                        Button {
                            let name = client.discovered[id] ?? "ANT BMS"
                            boundID = id.uuidString
                            boundName = name
                            client.connect(id)
                        } label: {
                            HStack {
                                Text(client.discovered[id] ?? "ANT BMS")
                                Spacer()
                                if boundID == id.uuidString {
                                    Image(systemName: "checkmark").foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
                Button(client.state == .scanning ? "停止扫描" : "重新扫描") {
                    if client.state == .scanning { client.stopScan() } else { client.startScan() }
                }
            }

            if let st = client.status {
                Section("实时数据") {
                    row("电量 SOC", "\(Int(st.socPercent)) %")
                    row("总压", String(format: "%.2f V", st.totalVoltage))
                    row("电流", String(format: "%.1f A %@", st.current, st.isCharging ? "(充电)" : st.isDischarging ? "(放电)" : ""))
                    row("功率", String(format: "%.0f W", st.powerWatts))
                    row("剩余/总容量", String(format: "%.1f / %.1f Ah", st.remainingCapacityAh, st.totalCapacityAh))
                    row("单体", String(format: "%d 串 · %.3f–%.3f V", st.cellCount, st.minCellVoltage, st.maxCellVoltage))
                    row("压差", String(format: "%.0f mV", st.deltaCellVoltage * 1000))
                    if !st.temperatures.isEmpty {
                        row("温度", st.temperatures.map { String(format: "%.0f°", $0) }.joined(separator: " / "))
                    }
                    row("MOS 温度", String(format: "%.0f ℃", st.mosfetTemperature))
                }
            }

            Section {
                Text("ANT 为库仑计直读;严格只读,不写入任何电池配置。功率/电量/峰值/回收自动同步到仪表六主题。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("ANT 保护板")
        .onAppear {
            client.startScan()
            if !boundID.isEmpty, let id = UUID(uuidString: boundID), client.status == nil {
                client.connect(id)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }
}
