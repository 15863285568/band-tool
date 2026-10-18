import SwiftUI
import UIKit

@main
struct MiFaceStudioApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var settings = AppSettings()

    init() {
        // The app uses its own floating glass tab bar.
        UITabBar.appearance().isHidden = true
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
                .onAppear { model.start() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @State private var selection = 0
    @State private var tabBarCollapsed = false

    var body: some View {
        ZStack {
            StudioBackground()

            TabView(selection: $selection) {
                EditorScreen()
                    .tag(0)

                LibraryView(selection: $selection, library: model.library)
                    .tag(1)

                DeviceScreen()
                    .tag(2)

                SettingsScreen()
                    .tag(3)
            }
            .background(Color.clear)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StudioTabBar(selection: $selection, collapsed: $tabBarCollapsed)
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Text(toast)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule().stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.32), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                    )
                    .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: model.toast)
        .tint(StudioTheme.accent)
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
                    ProgressView().tint(StudioTheme.accent)
                    Text("正在启动表盘编辑器…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { model.start() }
    }
}
