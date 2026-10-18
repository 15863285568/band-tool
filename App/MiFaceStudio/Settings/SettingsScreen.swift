import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @State private var confirmReset = false
    @State private var showKeyHelp = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    brandCard
                    appearanceCard
                    keysCard
                    workspaceCard
                    aboutCard
                }
                .padding(16)
            }
            .background { StudioBackground() }
            .navigationTitle("设置")
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showKeyHelp) {
                NavigationStack {
                    KeyHelpView()
                }
            }
            .alert("清空工作区？", isPresented: $confirmReset) {
                Button("清空", role: .destructive) { resetWorkspace() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("所有本地表盘工程、导出文件和缓存都会删除，AuthKey 不会删除。")
            }
        }
    }

    private var brandCard: some View {
        SectionCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [StudioTheme.accent, StudioTheme.magenta],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 54, height: 54)
                        .shadow(color: StudioTheme.accent.opacity(0.42), radius: 14, y: 6)
                    Image(systemName: "paintbrush.pointed.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("表盘工坊")
                        .font(.title3.weight(.bold))
                    Text("制作 · 安装，一条链路完成")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                GlassChip(text: "v1.0", icon: "sparkles")
            }
        }
    }

    private var appearanceCard: some View {
        SectionCard("外观") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $settings.softGlassEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Image(systemName: "circle.hexagongrid.fill")
                                .foregroundStyle(StudioTheme.accent)
                            Text("柔光玻璃")
                                .font(.subheadline.weight(.semibold))
                        }
                        Text("半透明磨砂卡片、边缘高光和背景柔光。关闭后使用纯色深色界面。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(StudioTheme.accent)

                HStack(spacing: 8) {
                    Text(settings.softGlassEnabled ? "当前：柔光玻璃" : "当前：纯色深色")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ZStack {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.34), .white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                    }
                    .frame(width: 74, height: 28)
                    .overlay(
                        Text("Aa")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                    )
                    .opacity(settings.softGlassEnabled ? 1 : 0.55)
                }
            }
        }
    }

    private var keysCard: some View {
        SectionCard("设备与密钥") {
            VStack(spacing: 0) {
                Button {
                    showKeyHelp = true
                } label: {
                    settingRow(
                        icon: "key.horizontal.fill",
                        title: "AuthKey 使用说明",
                        subtitle: "32 位密钥、保存位置和安全提示"
                    )
                }
                .buttonStyle(.plain)

                Divider().opacity(0.35).padding(.vertical, 2)

                NavigationLink {
                    KeyHelpView()
                } label: {
                    settingRow(
                        icon: "questionmark.circle.fill",
                        title: "如何获取 AuthKey",
                        subtitle: "从电脑版 AstroBox 或已有工具复制"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var workspaceCard: some View {
        SectionCard("工作区") {
            VStack(spacing: 0) {
                Button {
                    model.library.refresh()
                    model.showToast("已刷新表盘库")
                } label: {
                    settingRow(
                        icon: "arrow.clockwise",
                        title: "刷新表盘库",
                        subtitle: "重新扫描本地工程和导出文件"
                    )
                }
                .buttonStyle(.plain)

                Divider().opacity(0.35).padding(.vertical, 2)

                Button(role: .destructive) {
                    confirmReset = true
                } label: {
                    settingRow(
                        icon: "trash.fill",
                        title: "清空本地工作区",
                        subtitle: "删除工程、导出文件和缓存",
                        tint: .red
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var aboutCard: some View {
        SectionCard("关于") {
            VStack(spacing: 0) {
                infoRow(title: "版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                Divider().opacity(0.35).padding(.vertical, 8)
                infoRow(title: "编辑器", value: "Xiaomi Watchface Editor")
                Divider().opacity(0.35).padding(.vertical, 8)
                Link(destination: URL(string: "https://www.mi.com/")!) {
                    HStack {
                        Text("小米官网").font(.subheadline)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider().opacity(0.35).padding(.vertical, 8)
                Text("本应用仅用于个人表盘制作与设备管理。表盘编辑器的界面与资源来自小米官方 Web 版，版权归小米所有。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingRow(
        icon: String,
        title: String,
        subtitle: String,
        tint: Color = StudioTheme.accent
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.92))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 7)
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.medium))
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
        ZStack {
            StudioBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "key.horizontal.fill")
                                    .foregroundStyle(StudioTheme.accent)
                                Text("AuthKey 是什么")
                                    .font(.headline)
                            }
                            Text("AuthKey 是小米运动健康在绑定手表/手环时写入本机的 32 位十六进制密钥。蓝牙安装表盘时需要它来完成认证。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SectionCard("推荐方式") {
                        VStack(alignment: .leading, spacing: 12) {
                            helpStep("1", "在电脑上打开 AstroBox，连接一次设备后查看设备详情/日志中的 authkey。")
                            helpStep("2", "复制 32 位十六进制字符串（0-9、a-f）。")
                            helpStep("3", "回到本 App 的「设备」页，粘贴并保存，然后点「重新认证」。")
                        }
                    }

                    SectionCard("注意") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("AuthKey 等同于设备的绑定凭证，请不要发给别人，也不要上传到任何网站。本 App 只把它保存在 iOS Keychain 中。")
                            Text("如果设备已经绑定小米运动健康，请不要在官方 App 里解绑；本 App 只读取本地密钥，不会修改官方绑定。")
                            Text("不同型号/固件对第三方安装的开放程度不同。如果设备拒绝安装，请先确认它支持第三方表盘。")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("AuthKey 说明")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
    }

    private func helpStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(StudioTheme.accent, in: Circle())
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
