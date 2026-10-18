import SwiftUI

/// Edits the 9/12-character watch-face id embedded in a `.face`, `.bin` or
/// `.mwz` file.  The heavy lifting (raw field rewrite vs. zip repack) lives in
/// FacePackage so this sheet only handles validation and persistence.
struct FaceIDEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let artifact: FaceArtifact
    @ObservedObject var library: FaceLibrary

    @State private var id: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(artifact: FaceArtifact, library: FaceLibrary) {
        self.artifact = artifact
        self.library = library
        let data = (try? Data(contentsOf: artifact.url)) ?? Data()
        let current = FacePackage.metadata(for: data).identifier
        _id = State(initialValue: current ?? FacePackage.makeID())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionCard("表盘 ID") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("修改后会直接写回这个文件；已安装到手表上的旧 ID 不会自动删除。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            TextField("9 位或 12 位字母数字", text: $id)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .font(.system(.body, design: .monospaced))
                                .padding(12)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(.white.opacity(0.12), lineWidth: 1)
                                }

                            HStack(spacing: 10) {
                                Button {
                                    id = FacePackage.makeID(length: 9)
                                } label: {
                                    Label("随机 9 位", systemImage: "dice")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    id = FacePackage.makeID(length: 12)
                                } label: {
                                    Label("随机 12 位", systemImage: "dice.fill")
                                }
                                .buttonStyle(.bordered)
                            }
                            .font(.footnote)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    SectionCard("文件") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(artifact.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            Text(artifact.url.pathExtension.uppercased())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
            }
            .background { StudioBackground() }
            .navigationTitle("修改表盘 ID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") { save() }
                        .disabled(isSaving)
                }
            }
            .alert("修改失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        guard let cleaned = FacePackage.sanitizeID(id) else {
            errorMessage = "ID 必须是 9 位或 12 位字母数字。"
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let data = try Data(contentsOf: artifact.url)
            let result = try FacePackage.prepareForInstall(data, preferredID: cleaned)
            try result.data.write(to: artifact.url, options: .atomic)
            library.refresh()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
