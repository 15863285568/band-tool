import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var library: FaceLibrary
    @Binding var selection: Int

    @State private var tab = 0
    @State private var showImporter = false
    @State private var selectedArtifact: FaceArtifact?
    @State private var pendingDeleteProject: FaceProject?
    @State private var pendingDeleteArtifact: FaceArtifact?

    init(selection: Binding<Int>, library: FaceLibrary) {
        self._selection = selection
        self.library = library
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("类型", selection: $tab) {
                        Text("工程").tag(0)
                        Text("表盘文件").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    if tab == 0 {
                        projectGrid
                    } else {
                        artifactGrid
                    }
                }
                .padding(.vertical, 12)
            }
            .background { StudioBackground() }
            .navigationTitle("表盘库")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        library.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result { library.importFiles(urls) }
            }
            .sheet(item: $selectedArtifact) { artifact in
                InstallSheet(artifact: artifact)
                    .environmentObject(model)
            }
            .alert("删除工程？", isPresented: Binding(
                get: { pendingDeleteProject != nil },
                set: { if !$0 { pendingDeleteProject = nil } }
            )) {
                Button("删除", role: .destructive) {
                    if let project = pendingDeleteProject { try? library.delete(project: project) }
                    pendingDeleteProject = nil
                }
                Button("取消", role: .cancel) { pendingDeleteProject = nil }
            }
            .alert("删除表盘文件？", isPresented: Binding(
                get: { pendingDeleteArtifact != nil },
                set: { if !$0 { pendingDeleteArtifact = nil } }
            )) {
                Button("删除", role: .destructive) {
                    if let artifact = pendingDeleteArtifact { try? library.delete(artifact: artifact) }
                    pendingDeleteArtifact = nil
                }
                Button("取消", role: .cancel) { pendingDeleteArtifact = nil }
            }
        }
        .onAppear { library.refresh() }
    }

    @ViewBuilder private var projectGrid: some View {
        if library.projects.isEmpty {
            EmptyStateView(
                icon: "square.stack.3d.up",
                title: "还没有表盘工程",
                subtitle: "去「制作」新建一个表盘，保存后会出现在这里。"
            )
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(library.projects) { project in
                    Button {
                        model.openProject(project)
                        selection = 0
                    } label: {
                        ProjectCard(project: project)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { pendingDeleteProject = project } label: {
                            Label("删除工程", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder private var artifactGrid: some View {
        if library.artifacts.isEmpty {
            EmptyStateView(
                icon: "dial.medium",
                title: "还没有导出的表盘",
                subtitle: "在编辑器里点「导出」，生成的 .face / .bin 会自动出现在这里。"
            )
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(library.artifacts) { artifact in
                    Button {
                        selectedArtifact = artifact
                    } label: {
                        ArtifactCard(artifact: artifact)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { pendingDeleteArtifact = artifact } label: {
                            Label("删除文件", systemImage: "trash")
                        }
                        ShareLink(item: artifact.url) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

private struct ProjectCard: View {
    let project: FaceProject

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.7)
                    )
                if let preview = project.preview, let image = UIImage(contentsOfFile: preview.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    Image(systemName: "paintbrush.pointed")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.orange.opacity(0.8))
                }
            }
            .frame(height: 170)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(project.subtitle.isEmpty ? "表盘工程" : project.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .padding(10)
        .glassSurface(cornerRadius: 22)
    }
}

private struct ArtifactCard: View {
    let artifact: FaceArtifact

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.7)
                    )
                VStack(spacing: 6) {
                    Image(systemName: "checkerboard.rectangle")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.orange.opacity(0.9))
                    Text(artifact.url.pathExtension.lowercased())
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 140)
            VStack(alignment: .leading, spacing: 3) {
                Text(artifact.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(artifact.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
            HStack(spacing: 6) {
                Image(systemName: "bolt.horizontal.circle")
                Text("点按安装")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.orange.opacity(0.12), in: Capsule())
        }
        .padding(10)
        .glassSurface(cornerRadius: 22)
    }
}
