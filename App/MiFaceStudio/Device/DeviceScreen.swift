import SwiftUI
import UIKit
import Combine

struct DeviceScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        DeviceContent(bluetooth: model.bluetooth, store: model.devices, library: model.library)
    }
}

private struct DeviceContent: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var bluetooth: XiaomiBluetoothManager
    @ObservedObject var store: DeviceStore
    @ObservedObject var library: FaceLibrary

    @State private var keyText = ""
    @State private var latestArtifact: FaceArtifact?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    connectionCard
                    if bluetooth.isConnected {
                        authCard
                    }
                    installCard
                    helpCard
                }
                .padding(16)
            }
            .background(Color.studioBackground.ignoresSafeArea())
            .navigationTitle("设备")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if bluetooth.isConnected {
                            bluetooth.disconnect()
                        } else if bluetooth.isScanning {
                            bluetooth.stopScan()
                        } else {
                            bluetooth.startScan()
                        }
                    } label: {
                        Image(systemName: bluetooth.isConnected ? "xmark.circle" : (bluetooth.isScanning ? "stop.circle" : "arrow.clockwise"))
                    }
                }
            }
            .onAppear {
                library.refresh()
                latestArtifact = library.artifacts.first
                if !bluetooth.isConnected && !bluetooth.isScanning {
                    bluetooth.startScan()
                }
                keyText = bluetooth.currentAuthKey()
            }
            .onReceive(library.objectWillChange) { _ in
                DispatchQueue.main.async {
                    latestArtifact = library.artifacts.first
                }
            }
            .onChange(of: bluetooth.isConnected) { connected in
                if connected {
                    keyText = bluetooth.currentAuthKey()
                }
            }
            .onChange(of: bluetooth.authReady) { ready in
                if ready { model.showToast("设备认证成功") }
            }
            .alert("提示", isPresented: Binding(
                get: { bluetooth.lastError != nil },
                set: { if !$0 { bluetooth.lastError = nil } }
            )) {
                Button("好") { bluetooth.lastError = nil }
            } message: {
                Text(bluetooth.lastError ?? "")
            }
        }
    }

    private var connectionCard: some View {
        SectionCard("连接") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(bluetooth.isConnected ? Color.green.opacity(0.18) : Color.orange.opacity(0.14))
                            .frame(width: 44, height: 44)
                        Image(systemName: bluetooth.isConnected ? "applewatch.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                            .foregroundStyle(bluetooth.isConnected ? .green : .orange)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bluetooth.isConnected ? (bluetooth.connectedName.isEmpty ? "已连接" : bluetooth.connectedName) : "未连接")
                            .font(.headline)
                        Text(bluetooth.isConnected ? (bluetooth.authReady ? "已认证，可以安装表盘" : "正在建立安全通道") : "打开手表/手环，靠近手机")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if bluetooth.isScanning {
                        ProgressView().tint(.orange)
                    }
                }

                if bluetooth.phase != .idle {
                    PhaseBanner(phase: bluetooth.phase)
                }

                if !bluetooth.isConnected {
                    if bluetooth.devices.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.7)
                            Text(bluetooth.isScanning ? "正在搜索小米设备…" : "暂无设备")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    } else {
                        ForEach(bluetooth.devices) { device in
                            Button {
                                bluetooth.connect(device)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name).font(.subheadline.weight(.medium))
                                        Text(String(device.id.prefix(8)) + "…")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(device.rssi) dBm")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            Divider().opacity(0.4)
                        }
                    }
                    Button {
                        bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.startScan()
                    } label: {
                        Text(bluetooth.isScanning ? "停止搜索" : "重新搜索")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var authCard: some View {
        SectionCard("AuthKey") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: bluetooth.authReady ? "lock.open.fill" : "lock.fill")
                        .foregroundStyle(bluetooth.authReady ? .green : .orange)
                    Text(bluetooth.authReady ? "认证已完成" : "需要 AuthKey 才能安装表盘")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                KeyInputView(text: $keyText) {
                    saveKey()
                }
                HStack(spacing: 10) {
                    Button {
                        if let text = UIPasteboard.general.string {
                            keyText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    Button {
                        bluetooth.retryAuthentication()
                    } label: {
                        Label("重新认证", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                .font(.footnote)
            }
        }
    }

    private var installCard: some View {
        SectionCard("安装表盘") {
            VStack(alignment: .leading, spacing: 12) {
                if let artifact = latestArtifact {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(artifact.name).font(.subheadline.weight(.semibold))
                            Text(artifact.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(artifact.url.pathExtension.uppercased())
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.orange.opacity(0.15), in: Capsule())
                    }
                    Button {
                        bluetooth.install(artifact)
                    } label: {
                        Label("安装到已连接设备", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!bluetooth.isConnected || !bluetooth.authReady || bluetooth.phase.isBusy)
                } else {
                    Text("还没有导出的表盘。先在「制作」里完成并导出。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if case .failed(let message) = bluetooth.phase {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var helpCard: some View {
        SectionCard("AuthKey 从哪里来") {
            VStack(alignment: .leading, spacing: 8) {
                Text("AuthKey 是小米运动健康在绑定设备时生成的 32 位密钥。它只保存在你的手机/电脑上，不会上传到本 App 的服务器。")
                Text("可以从电脑版 AstroBox 的设备记录中复制，或使用已有的密钥提取工具。首次使用建议先备份。")
                Text("本 App 直接通过蓝牙写入表盘，不经过小米云。安装失败不会影响官方表盘。")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func saveKey() {
        guard let id = bluetooth.currentPeripheralID else {
            model.showToast("请先连接设备")
            return
        }
        do {
            try store.setAuthKey(keyText, for: id)
            model.showToast("AuthKey 已保存")
            if bluetooth.isConnected {
                bluetooth.retryAuthentication()
            }
        } catch {
            model.showToast(error.localizedDescription)
        }
    }
}
