import SwiftUI

@main
struct MiFaceStudioApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .onAppear { model.start() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            EditorScreen()
                .tabItem { Label("制作", systemImage: "paintbrush.pointed") }
                .tag(0)

            LibraryView(selection: $selection, library: model.library)
                .tabItem { Label("表盘库", systemImage: "square.grid.2x2") }
                .tag(1)

            DeviceScreen()
                .tabItem { Label("设备", systemImage: "applewatch") }
                .tag(2)

            SettingsScreen()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(3)
        }
        .tint(.orange)
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Text(toast)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.12)))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.toast)
    }
}

struct EditorScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url = model.editorURL {
                EditorWebView(baseURL: url, route: $model.route) { event in
                    model.handleEditorEvent(event)
                }
                .background(Color.black)
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.orange)
                    Text("正在启动表盘编辑器…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { model.start() }
    }
}
