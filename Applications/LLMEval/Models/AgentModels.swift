// Copyright © 2025 Apple Inc.

import Foundation
import SwiftUI

// MARK: - Agent Message

struct AgentMessage: Identifiable {
    let id: UUID
    var role: AgentRole
    var content: String
    var toolCalls: [AgentToolCall]
    var isStreaming: Bool
    let timestamp: Date

    init(
        id: UUID = UUID(),
        role: AgentRole,
        content: String = "",
        toolCalls: [AgentToolCall] = [],
        isStreaming: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.isStreaming = isStreaming
        self.timestamp = timestamp
    }
}

enum AgentRole: Equatable {
    case user
    case assistant
    case system
}

// MARK: - Tool Call Record

struct AgentToolCall: Identifiable {
    let id: UUID
    let name: String
    let arguments: String
    var result: String?
    var isExecuting: Bool
    var isExpanded: Bool

    init(
        id: UUID = UUID(),
        name: String,
        arguments: String,
        result: String? = nil,
        isExecuting: Bool = false,
        isExpanded: Bool = true
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.result = result
        self.isExecuting = isExecuting
        self.isExpanded = isExpanded
    }

    var displayName: String {
        switch name {
        case "read_file": return "Read File"
        case "write_file": return "Write File"
        case "list_directory": return "List Directory"
        case "run_shell_command": return "Run Shell Command"
        case "search_files": return "Search Files"
        case "create_directory": return "Create Directory"
        case "delete_file": return "Delete File"
        case "get_file_info": return "Get File Info"
        default: return name.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var icon: String {
        switch name {
        case "read_file": return "doc.text"
        case "write_file": return "square.and.pencil"
        case "list_directory": return "folder"
        case "run_shell_command": return "terminal"
        case "search_files": return "magnifyingglass"
        case "create_directory": return "folder.badge.plus"
        case "delete_file": return "trash"
        case "get_file_info": return "info.circle"
        default: return "wrench.and.screwdriver"
        }
    }

    var statusColor: Color {
        if isExecuting { return .orange }
        if result != nil { return .green }
        return .secondary
    }
}

// MARK: - File Entry (File Explorer)

struct FileEntry: Identifiable, Hashable {
    let id: UUID
    let name: String
    let url: URL
    var isDirectory: Bool
    var children: [FileEntry]?
    var isExpanded: Bool

    init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        isDirectory: Bool,
        children: [FileEntry]? = nil,
        isExpanded: Bool = false
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
        self.isExpanded = isExpanded
    }

    static func == (lhs: FileEntry, rhs: FileEntry) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    var icon: String {
        if isDirectory { return "folder.fill" }
        switch url.pathExtension.lowercased() {
        case "swift": return "swift"
        case "py": return "doc.text"
        case "js", "ts", "jsx", "tsx": return "doc.text"
        case "json": return "curlybraces"
        case "md": return "doc.richtext"
        case "txt": return "doc.plaintext"
        case "png", "jpg", "jpeg", "gif", "svg", "webp": return "photo"
        case "sh", "bash", "zsh": return "terminal"
        case "xcodeproj", "xcworkspace": return "hammer"
        case "gitignore", "gitmodules": return "arrow.triangle.branch"
        default: return "doc"
        }
    }

    var iconColor: Color {
        if isDirectory { return .blue }
        switch url.pathExtension.lowercased() {
        case "swift": return .orange
        case "py": return .yellow
        case "js", "ts", "jsx", "tsx": return .yellow
        case "json": return .green
        case "md": return .blue
        case "sh", "bash", "zsh": return .green
        default: return .secondary
        }
    }
}
