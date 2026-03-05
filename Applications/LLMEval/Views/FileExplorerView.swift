// Copyright © 2025 Apple Inc.

import SwiftUI

struct FileExplorerView: View {
    @Binding var workspacePath: URL?
    var onFileSelected: (URL) -> Void

    @State private var fileEntries: [FileEntry] = []
    @State private var expandedDirectories: Set<URL> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                Text(workspacePath?.lastPathComponent ?? "No Workspace")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    openWorkspace()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("Open Workspace Folder")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            if workspacePath == nil {
                // Empty state
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No Workspace")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Open a folder to start coding")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Button("Open Folder") {
                        openWorkspace()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                // File tree
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(fileEntries) { entry in
                            FileEntryRow(
                                entry: entry,
                                depth: 0,
                                expandedDirectories: $expandedDirectories,
                                onFileSelected: onFileSelected,
                                loadChildren: loadChildren
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()

            // Footer: refresh button
            if workspacePath != nil {
                HStack {
                    Button {
                        refreshFileTree()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .onChange(of: workspacePath) { _, newPath in
            if let path = newPath {
                loadRootEntries(from: path)
            } else {
                fileEntries = []
            }
        }
        .onAppear {
            if let path = workspacePath {
                loadRootEntries(from: path)
            }
        }
    }

    // MARK: - Actions

    private func openWorkspace() {
        #if os(macOS)
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.title = "Open Workspace Folder"
            panel.prompt = "Open"
            if panel.runModal() == .OK, let url = panel.url {
                workspacePath = url
            }
        #endif
    }

    private func loadRootEntries(from url: URL) {
        fileEntries = loadEntries(from: url)
    }

    private func refreshFileTree() {
        if let url = workspacePath {
            loadRootEntries(from: url)
        }
    }

    private func loadEntries(from url: URL) -> [FileEntry] {
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        let sorted = contents.sorted { a, b in
            let aDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if aDir != bDir { return aDir }
            return a.lastPathComponent.lowercased() < b.lastPathComponent.lowercased()
        }

        return sorted.map { fileURL in
            let isDir =
                (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return FileEntry(name: fileURL.lastPathComponent, url: fileURL, isDirectory: isDir)
        }
    }

    private func loadChildren(for entry: FileEntry) -> [FileEntry] {
        guard entry.isDirectory else { return [] }
        return loadEntries(from: entry.url)
    }
}

// MARK: - File Entry Row

struct FileEntryRow: View {
    let entry: FileEntry
    let depth: Int
    @Binding var expandedDirectories: Set<URL>
    var onFileSelected: (URL) -> Void
    var loadChildren: (FileEntry) -> [FileEntry]

    @State private var children: [FileEntry] = []

    private var isExpanded: Bool {
        expandedDirectories.contains(entry.url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row
            Button {
                if entry.isDirectory {
                    toggleDirectory()
                } else {
                    onFileSelected(entry.url)
                }
            } label: {
                HStack(spacing: 4) {
                    // Indent
                    Spacer().frame(width: CGFloat(depth) * 16)

                    // Expand arrow for directories
                    if entry.isDirectory {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                    } else {
                        Spacer().frame(width: 12)
                    }

                    // Icon
                    Image(systemName: entry.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(entry.iconColor)
                        .frame(width: 16)

                    // Name
                    Text(entry.name)
                        .font(.system(size: 13))
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Children (when expanded)
            if isExpanded {
                ForEach(children) { child in
                    FileEntryRow(
                        entry: child,
                        depth: depth + 1,
                        expandedDirectories: $expandedDirectories,
                        onFileSelected: onFileSelected,
                        loadChildren: loadChildren
                    )
                }
            }
        }
    }

    private func toggleDirectory() {
        if isExpanded {
            expandedDirectories.remove(entry.url)
        } else {
            if children.isEmpty {
                children = loadChildren(entry)
            }
            expandedDirectories.insert(entry.url)
        }
    }
}
