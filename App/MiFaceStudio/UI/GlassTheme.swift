import SwiftUI
import UIKit

enum StudioTheme {
    static let accent = Color(red: 1.0, green: 0.50, blue: 0.20)
    static let accentSoft = Color(red: 1.0, green: 0.68, blue: 0.36)
    static let magenta = Color(red: 0.95, green: 0.18, blue: 0.48)
    static let blue = Color(red: 0.22, green: 0.48, blue: 1.0)
    static let ink = Color(red: 0.035, green: 0.035, blue: 0.045)
}

/// A calm, warm glow behind the translucent surfaces.  This is the part that
/// gives the glass something to refract; when the effect is disabled the app
/// falls back to a flat dark canvas.
struct StudioBackground: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 320)
            let height = max(proxy.size.height, 480)
            ZStack {
                StudioTheme.ink

                if settings.softGlassEnabled {
                    Circle()
                        .fill(StudioTheme.accent.opacity(0.42))
                        .frame(width: width * 0.88)
                        .blur(radius: 82)
                        .offset(x: -width * 0.30, y: -height * 0.33)
                    Circle()
                        .fill(StudioTheme.magenta.opacity(0.26))
                        .frame(width: width * 0.72)
                        .blur(radius: 96)
                        .offset(x: width * 0.38, y: -height * 0.10)
                    Circle()
                        .fill(StudioTheme.blue.opacity(0.20))
                        .frame(width: width * 0.82)
                        .blur(radius: 110)
                        .offset(x: width * 0.18, y: height * 0.42)

                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.02),
                            Color.black.opacity(0.12),
                            Color.black.opacity(0.54),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    LinearGradient(
                        colors: [Color(white: 0.075), Color(white: 0.035)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

struct GlassSurface: ViewModifier {
    @EnvironmentObject private var settings: AppSettings
    var cornerRadius: CGFloat = 20
    var emphasized: Bool = false

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if settings.softGlassEnabled {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(emphasized ? 0.16 : 0.10),
                                        Color.white.opacity(0.015),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.34),
                                        Color.white.opacity(0.06),
                                        StudioTheme.accent.opacity(0.10),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.9
                            )
                        // A soft specular line along the top edge.
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.50), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                ),
                                lineWidth: 0.6
                            )
                            .blendMode(.plusLighter)
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color(white: 0.105))
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 0.8)
                    }
                }
            }
            .shadow(
                color: .black.opacity(settings.softGlassEnabled ? 0.28 : 0.18),
                radius: settings.softGlassEnabled ? 22 : 12,
                x: 0,
                y: settings.softGlassEnabled ? 12 : 6
            )
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = 20, emphasized: Bool = false) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, emphasized: emphasized))
    }
}

struct StudioTabBar: View {
    @Binding var selection: Int
    @Binding var collapsed: Bool
    @EnvironmentObject private var settings: AppSettings

    private let items: [(title: String, icon: String)] = [
        ("制作", "paintbrush.pointed.fill"),
        ("表盘库", "square.grid.2x2.fill"),
        ("设备", "antenna.radiowaves.left.and.right"),
        ("设置", "gearshape.fill"),
    ]

    var body: some View {
        Group {
            if collapsed {
                collapsedBar
            } else {
                expandedBar
            }
        }
        .shadow(color: .black.opacity(0.35), radius: collapsed ? 12 : 24, y: collapsed ? 4 : 12)
        .padding(.horizontal, collapsed ? 0 : 16)
        .padding(.top, collapsed ? 0 : 6)
        .padding(.bottom, collapsed ? 0 : 4)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var collapsedBar: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                collapsed = false
            }
        } label: {
            Label("菜单", systemImage: "chevron.up")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 12)
        .padding(.bottom, 2)
    }

    private var expandedBar: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selection = index
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: items[index].icon)
                            .font(.system(size: 17, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                        Text(items[index].title)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(selection == index ? Color.white : Color.white.opacity(0.52))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if selection == index {
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            StudioTheme.accent.opacity(settings.softGlassEnabled ? 0.34 : 0.85),
                                            StudioTheme.magenta.opacity(settings.softGlassEnabled ? 0.20 : 0.55),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.24), lineWidth: 0.7)
                                )
                                .shadow(color: StudioTheme.accent.opacity(0.36), radius: 12, y: 4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(items[index].title)
            }

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    collapsed = true
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                    Text("收起")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.52))
                .frame(width: 52)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("隐藏底部栏")
        }
        .padding(6)
        .background {
            ZStack {
                if settings.softGlassEnabled {
                    Capsule(style: .continuous).fill(.ultraThinMaterial)
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.14), Color.white.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Capsule(style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.38), Color.white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                } else {
                    Capsule(style: .continuous).fill(Color(white: 0.11))
                    Capsule(style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                }
            }
        }
    }
}

/// Small decorative status chip used in headers.
struct GlassChip: View {
    let text: String
    var icon: String? = nil
    var tint: Color = StudioTheme.accent

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.20), lineWidth: 0.7))
    }
}
