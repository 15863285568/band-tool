import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmReset = false
    @State private var showKeyHelp = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "paintbrush.pointed.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                            .frame(width: 44, height: 44)
                            .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("表盘工坊").font(.headline)
                            Text("制作 + 安装，一条链路完成").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("设备与密钥") {
                    Button {
                        showKeyHelp = true
                    } label: {
                        Label("AuthKey 使用说明", systemImage: "key.horizontal")
                    }
                    NavigationLink {
                        KeyHelpView()
                    } label: {
                        Label("如何获取 AuthKey", systemImage: "questionmark.circle")
                    }
                }

                Section("工作区") {
                    Button {
                        model.library.refresh()
                        model.showToast("已刷新表盘库")
                    } label: {
                        Label("刷新表盘库", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Label("清空本地工作区", systemImage: "trash")
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("编辑器", value: "Xiaomi Watchface Editor")
                    Link(destination: URL(string: "https://www.mi.com/")!) {
                        Label("小米官网", systemImage: "safari")
                    }
                    Text("本应用仅用于个人表盘制作与设备管理。表盘编辑器的界面与资源来自小米官方 Web 版，版权归小米所有。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.studioBackground.ignoresSafeArea())
            .navigationTitle("设置")
            .sheet(isPresented: $showKeyHelp) {
                NavigationStack { KeyHelpView() }
            }
            .alert("清空工作区？", isPresented: $confirmReset) {
                Button("清空", role: .destructive) { resetWorkspace() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("所有本地表盘工程、导出文件和缓存都会删除，AuthKey 不会删除。")
            }
        }
    }

    private func resetWorkspace() {
        model.server.stop()
        try? FileManager.default.removeItem(at: AppPaths.supportRoot)
        AppPaths.bootstrap()
        model.library.refresh()
        model.restartServer()
        model.showToast("工作区已清空")
    }
}

struct KeyHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("AuthKey 是小米运动健康在绑定手表/手环时写入本机的 32 位十六进制密钥。蓝牙安装表盘时需要它来完成认证。")
                Text("推荐方式")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    Label("在电脑上打开 AstroBox，连接一次设备后查看设备详情/日志中的 authkey。", systemImage: "1.circle")
                    Label("复制 32 位十六进制字符串（0-9、a-f）。", systemImage: "2.circle")
                    Label("回到本 App 的「设备」页，粘贴并保存，然后点「重新认证」。", systemImage: "3.circle")
                }
                .font(.subheadline)
                Text("注意")
                    .font(.headline)
                Text("AuthKey 等同于设备的绑定凭证，请不要发给别人，也不要上传到任何网站。本 App 只把它保存在 iOS Keychain 中。")
                    .foregroundStyle(.secondary)
                Text("如果设备已经绑定小米运动健康，请不要在官方 App 里解绑；本 App 只读取本地密钥，不会修改官方绑定。")
                    .foregroundStyle(.secondary)
                Text("不同型号/固件对第三方安装的开放程度不同。如果设备拒绝安装，请先确认它支持第三方表盘。")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
            .padding(20)
        }
        .background(Color.studioBackground.ignoresSafeArea())
        .navigationTitle("AuthKey 说明")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
    }
}
