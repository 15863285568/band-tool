import SwiftUI

struct SectionCard<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)
            }
            content
                .padding(16)
                .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.06))
                )
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                LinearGradient(colors: [.orange, .pink.opacity(0.85)], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.orange)
            Text(title).font(.headline)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

struct PhaseBanner: View {
    let phase: InstallPhase

    var body: some View {
        HStack(spacing: 10) {
            icon
            Text(phase.label)
                .font(.footnote.weight(.medium))
                .lineLimit(2)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder private var icon: some View {
        switch phase {
        case .uploading(_):
            ProgressView().tint(color).scaleEffect(0.8)
        case .done:
            Image(systemName: "checkmark.circle.fill")
        case .failed(_):
            Image(systemName: "exclamationmark.triangle.fill")
        case .idle:
            Image(systemName: "circle.dotted")
        default:
            ProgressView().tint(color).scaleEffect(0.8)
        }
    }

    private var color: Color {
        switch phase {
        case .done: return .green
        case .failed(_): return .red
        default: return .orange
        }
    }
}

struct KeyInputView: View {
    @Binding var text: String
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SecureField("32 位 AuthKey", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
                Button("保存", action: onSave)
                    .font(.footnote.weight(.semibold))
                    .disabled(text.trimmingCharacters(in: .whitespaces).count != 32)
            }
            Text("AuthKey 会保存在本机 Keychain，不会上传。可在设备页粘贴已有的 32 位十六进制密钥。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

extension Color {
    static let studioBackground = Color(white: 0.055)
    static let studioCard = Color(white: 0.10)
}
