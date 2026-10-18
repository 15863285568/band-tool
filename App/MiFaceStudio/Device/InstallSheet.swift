import SwiftUI

struct InstallSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let artifact: FaceArtifact

    @State private var keyText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SectionCard("表盘") {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(artifact.name).font(.headline)
                                Text(artifact.subtitle).font(.caption).foregroundStyle(.secondary)
                                if let id = artifact.watchfaceID {
                                    Text("ID \(id)").font(.caption2.monospaced()).foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Text(artifact.url.pathExtension.uppercased())
                                .font(.caption.monospaced())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.orange.opacity(0.15), in: Capsule())
                        }
                    }

                    SectionCard("设备") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Circle()
                                    .fill(model.bluetooth.isConnected ? Color.green : Color.orange.opacity(0.7))
                                    .frame(width: 8, height: 8)
                                Text(model.bluetooth.isConnected ? (model.bluetooth.connectedName.isEmpty ? "已连接" : model.bluetooth.connectedName) : "未连接")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                if model.bluetooth.isScanning {
                                    ProgressView().scaleEffect(0.7)
                                }
                            }
                            if model.bluetooth.phase != .idle {
                                PhaseBanner(phase: model.bluetooth.phase)
                            }
                            if !model.bluetooth.isConnected {
                                ForEach(model.bluetooth.devices) { device in
                                    Button {
                                        model.bluetooth.connect(device)
                                    } label: {
                                        HStack {
                                            Text(device.name).font(.subheadline)
                                            Spacer()
                                            Text("\(device.rssi) dBm").font(.caption2).foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 5)
                                    }
                                    .buttonStyle(.plain)
                                    Divider().opacity(0.3)
                                }
                                Button("重新搜索") { model.bluetooth.startScan() }
                                    .font(.footnote)
                                    .buttonStyle(.bordered)
                            }
                        }
                    }

                    if model.bluetooth.isConnected && !model.bluetooth.authReady {
                        SectionCard("AuthKey") {
                            KeyInputView(text: $keyText) {
                                saveKey()
                            }
                        }
                    }

                    Button {
                        model.bluetooth.install(artifact)
                    } label: {
                        Label(model.bluetooth.phase.isBusy ? "正在安装…" : "开始安装", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!model.bluetooth.isConnected || !model.bluetooth.authReady || model.bluetooth.phase.isBusy)

                    Text("安装过程中请保持手表靠近手机、屏幕亮起。传输完成后设备会自动应用表盘。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
            }
            .background {
                StudioBackground()
            }
            .navigationTitle("安装表盘")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                keyText = model.bluetooth.currentAuthKey()
                model.library.refresh()
                if !model.bluetooth.isConnected {
                    model.bluetooth.startScan()
                }
            }
            .onChange(of: model.bluetooth.isConnected) { connected in
                if connected { keyText = model.bluetooth.currentAuthKey() }
            }
        }
    }

    private func saveKey() {
        guard let id = model.bluetooth.currentPeripheralID else {
            model.showToast("请先连接设备")
            return
        }
        do {
            try model.devices.setAuthKey(keyText, for: id)
            model.bluetooth.retryAuthentication()
        } catch {
            model.showToast(error.localizedDescription)
        }
    }
}
