// Copyright © 2025 Apple Inc.

import Foundation
import MLXLMCommon

// MARK: - Coding Tool I/O Types

struct ReadFileInput: Codable {
    let path: String
    let startLine: Int?
    let endLine: Int?
    enum CodingKeys: String, CodingKey {
        case path; case startLine = "start_line"; case endLine = "end_line"
    }
}

struct WriteFileInput: Codable { let path: String; let content: String }
struct ListDirectoryInput: Codable { let path: String? }

struct EditFileInput: Codable {
    let path: String
    let oldString: String
    let newString: String
    enum CodingKeys: String, CodingKey {
        case path; case oldString = "old_string"; case newString = "new_string"
    }
}

struct RunShellInput: Codable {
    let command: String
    let workingDirectory: String?
    enum CodingKeys: String, CodingKey {
        case command; case workingDirectory = "working_directory"
    }
}

struct SearchFilesInput: Codable {
    let pattern: String
    let directory: String?
    let filePattern: String?
    let maxResults: Int?
    enum CodingKeys: String, CodingKey {
        case pattern; case directory; case filePattern = "file_pattern"; case maxResults = "max_results"
    }
}

struct CreateDirectoryInput: Codable { let path: String }
struct GetFileInfoInput: Codable { let path: String }

// MARK: - Coding Tool Executor

@MainActor
class CodingToolExecutor {

    var workspacePath: URL?

    init(workspacePath: URL?) {
        self.workspacePath = workspacePath
    }

    // MARK: - All Tool Schemas

    var allToolSchemas: [ToolSpec] {
        [
            readFileSchema, editFileSchema, writeFileSchema,
            listDirectorySchema, runShellSchema, searchFilesSchema,
            createDirectorySchema, getFileInfoSchema,
        ]
    }

    // MARK: - Schemas

    private var readFileSchema: ToolSpec {[
        "type": "function",
        "function": [
            "name": "read_file",
            "description": "Read the contents of a file with line numbers. Always read a file before modifying it.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "File path relative to workspace or absolute"] as ToolSpec,
                    "start_line": ["type": "integer", "description": "First line to read (1-based). Omit to read from start."] as ToolSpec,
                    "end_line": ["type": "integer", "description": "Last line to read (1-based). Omit to read to end."] as ToolSpec,
                ] as ToolSpec,
                "required": ["path"],
            ] as ToolSpec,
        ] as ToolSpec,
    ]}

    private var editFileSchema: ToolSpec {[
        "type": "function",
        "function": [
            "name": "edit_file",
            "description": "Make a targeted edit to an existing file by replacing exact text. Preferred over write_file for modifying existing files. The old_string must match exactly (including whitespace and indentation). If the string appears multiple times, only the first occurrence is replaced.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to the file to edit"] as ToolSpec,
                    "old_string": ["type": "string", "description": "The exact text to find and replace. Must match the file content exactly including whitespace."] as ToolSpec,
                    "new_string": ["type": "string", "description": "The replacement text. Can be empty string to delete the old_string."] as ToolSpec,
                ] as ToolSpec,
                "required": ["path", "old_string", "new_string"],
            ] as ToolSpec,
        ] as ToolSpec,
    ]}

    private var writeFileSchema: ToolSpec {[
        "type": "function",
        "function": [
            "name": "write_file",
            "description": "Write complete content to a file. Use for creating NEW files. For modifying existing files, prefer edit_file instead.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "File path relative to workspace or absolute"] as ToolSpec,
                    "content": ["type": "string", "description": "Complete file content to write"] as ToolSpec,
                ] as ToolSpec,
                "required": ["path", "content"],
            ] as ToolSpec,
        ] as ToolSpec,
    ]}

    private var listDirectorySchema: ToolSpec {[
        "type": "function",
        "function": [
            "name": "list_directory",
            "description": "List contents of a directory. Use to explore project structure.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Directory path. Defaults to workspace root."] as ToolSpec,
                ] as ToolSpec,
                "required": [] as [String],
            ] as ToolSpec,
        ] as ToolSpec,
    ]}

    private var runShellSchema: ToolSpec {[
        "type": "function",
        "function": [
            "name": "run_shell_command",
            "description": "Execute a shell command. Use for: swift build/test, git commands, ls, cat, find, grep, npm, etc. The working directory defaults to the workspace root.",
            "parameters": [
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "Shell command to run"] as ToolSpec,
                    "working_directory": ["type": "string", "description": "Override working directory (relative or absolute). Default: workspace root."] as ToolSpec,
                ] as ToolSpec,
                "required": ["command"],
            ] as ToolSpec,
        ] as ToolSpec,
    ]}

    private var searchFilesSchema: ToolSpec {[
        "type": "function",
        "function": [
            "name": "search_files",
            "description": "Search for a text pattern across files using grep. Returns matching lines with file:line format.",
            "parameters": [
                "type": "object",
                "properties": [
                    "pattern": ["type": "string", "description": "Search pattern (regex supported)"] as ToolSpec,
                    "directory": ["type": "string", "description": "Directory to search. Defaults to workspace root."] as ToolSpec,
                    "file_pattern": ["type": "string", "description": "Glob for file types, e.g. '*.swift', '*.py'. Default: all files."] as ToolSpec,
                    "max_results": ["type": "integer", "description": "Max matching lines to return. Default: 50."] as ToolSpec,
                ] as ToolSpec,
                "required": ["pattern"],
            ] as ToolSpec,
        ] as ToolSpec,
    ]}

    private var createDirectorySchema: ToolSpec {[
        "type": "function",
        "function": [
            "name": "create_directory",
            "description": "Create a directory (including all parent directories).",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Directory path to create"] as ToolSpec,
                ] as ToolSpec,
                "required": ["path"],
            ] as ToolSpec,
        ] as ToolSpec,
    ]}

    private var getFileInfoSchema: ToolSpec {[
        "type": "function",
        "function": [
            "name": "get_file_info",
            "description": "Get metadata about a file or directory: size, modification date, line count.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to the file or directory"] as ToolSpec,
                ] as ToolSpec,
                "required": ["path"],
            ] as ToolSpec,
        ] as ToolSpec,
    ]}

    // MARK: - Tool Dispatch

    func execute(name: String, arguments: String) async -> String {
        guard let argsData = arguments.data(using: .utf8) else {
            return "Error: invalid JSON arguments"
        }
        let decoder = JSONDecoder()
        do {
            switch name {
            case "read_file":
                return try await executeReadFile(decoder.decode(ReadFileInput.self, from: argsData))
            case "edit_file":
                return try await executeEditFile(decoder.decode(EditFileInput.self, from: argsData))
            case "write_file":
                return try await executeWriteFile(decoder.decode(WriteFileInput.self, from: argsData))
            case "list_directory":
                return try await executeListDirectory(decoder.decode(ListDirectoryInput.self, from: argsData))
            case "run_shell_command":
                return try await executeRunShell(decoder.decode(RunShellInput.self, from: argsData))
            case "search_files":
                return try await executeSearchFiles(decoder.decode(SearchFilesInput.self, from: argsData))
            case "create_directory":
                return try await executeCreateDirectory(decoder.decode(CreateDirectoryInput.self, from: argsData))
            case "get_file_info":
                return try await executeGetFileInfo(decoder.decode(GetFileInfoInput.self, from: argsData))
            default:
                return "Unknown tool: \(name)"
            }
        } catch {
            return "Tool error [\(name)]: \(error.localizedDescription)"
        }
    }

    // MARK: - Path Resolution

    func resolvedURL(_ path: String) -> URL {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        let base = workspacePath ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent(path)
    }

    // MARK: - Implementations

    private func executeReadFile(_ input: ReadFileInput) async throws -> String {
        let url = resolvedURL(input.path)
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")
        let total = lines.count
        let s = max(1, input.startLine ?? 1)
        let e = min(total, input.endLine ?? total)
        guard s <= e else {
            return "Error: line range \(s)-\(e) out of bounds (file has \(total) lines)"
        }
        let numbered = lines[(s - 1)...(e - 1)].enumerated().map { i, line in
            String(format: "%4d\t%@", s + i, line)
        }
        var out = "File: \(url.relativePath(from: workspacePath)) (\(total) lines)"
        if s > 1 || e < total { out += " · lines \(s)–\(e)" }
        out += "\n" + numbered.joined(separator: "\n")
        return out
    }

    private func executeEditFile(_ input: EditFileInput) async throws -> String {
        let url = resolvedURL(input.path)
        let original = try String(contentsOf: url, encoding: .utf8)

        guard original.contains(input.oldString) else {
            // Give a helpful error with context
            let preview = String(original.prefix(200)).replacingOccurrences(of: "\n", with: "↵")
            return """
                Error: old_string not found in \(url.lastPathComponent).
                Make sure the text matches exactly including whitespace and indentation.
                File preview (first 200 chars): \(preview)
                """
        }

        let updated = original.replacingFirstOccurrence(of: input.oldString, with: input.newString)
        try updated.write(to: url, atomically: true, encoding: .utf8)

        // Build a diff-like summary
        let oldLines = input.oldString.components(separatedBy: "\n")
        let newLines = input.newString.components(separatedBy: "\n")
        var diff = "Edited \(url.relativePath(from: workspacePath))\n"
        diff += oldLines.map { "- \($0)" }.joined(separator: "\n")
        if !input.newString.isEmpty {
            diff += "\n" + newLines.map { "+ \($0)" }.joined(separator: "\n")
        }
        return diff
    }

    private func executeWriteFile(_ input: WriteFileInput) async throws -> String {
        let url = resolvedURL(input.path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existed = FileManager.default.fileExists(atPath: url.path)
        try input.content.write(to: url, atomically: true, encoding: .utf8)
        let lines = input.content.components(separatedBy: "\n").count
        let action = existed ? "Updated" : "Created"
        return "\(action) \(url.relativePath(from: workspacePath)) (\(lines) lines)"
    }

    private func executeListDirectory(_ input: ListDirectoryInput) async throws -> String {
        let dirURL = input.path.map { resolvedURL($0) }
            ?? workspacePath
            ?? FileManager.default.homeDirectoryForCurrentUser

        let contents = try FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ).sorted { a, b in
            let aD = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bD = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if aD != bD { return aD }
            return a.lastPathComponent.lowercased() < b.lastPathComponent.lowercased()
        }

        let header = dirURL.relativePath(from: workspacePath?.deletingLastPathComponent()) ?? dirURL.path
        var lines = [header + "/"]
        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if isDir {
                lines.append("  \(url.lastPathComponent)/")
            } else {
                lines.append("  \(url.lastPathComponent)  \(formatSize(size))")
            }
        }
        lines.append("(\(contents.count) items)")
        return lines.joined(separator: "\n")
    }

    private func executeRunShell(_ input: RunShellInput) async throws -> String {
        let workDir = input.workingDirectory.map { resolvedURL($0) } ?? workspacePath
        let (stdout, stderr, code) = try await runProcess(command: input.command, in: workDir)

        var out = "$ \(input.command)"
        let combined = (stdout + stderr).trimmingCharacters(in: .newlines)
        if !combined.isEmpty {
            // Truncate very long outputs
            let maxChars = 4000
            let truncated = combined.count > maxChars
                ? String(combined.prefix(maxChars)) + "\n… (output truncated)"
                : combined
            out += "\n" + truncated
        }
        if code != 0 { out += "\n[exit \(code)]" }
        return out
    }

    private func executeSearchFiles(_ input: SearchFilesInput) async throws -> String {
        let dir = input.directory.map { resolvedURL($0) }
            ?? workspacePath
            ?? FileManager.default.homeDirectoryForCurrentUser
        let max = input.maxResults ?? 50
        let pattern = input.pattern.replacingOccurrences(of: "'", with: "'\"'\"'")
        var cmd = "grep -rn --include='\(input.filePattern ?? "*")' -m \(max) '\(pattern)' '\(dir.path)' 2>/dev/null | head -\(max)"
        let (stdout, _, _) = try await runProcess(command: cmd, in: nil)
        if stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No matches for '\(input.pattern)'"
        }
        // Make paths relative
        let relative = stdout.replacingOccurrences(of: dir.path + "/", with: "")
        return "grep '\(input.pattern)' in \(dir.relativePath(from: workspacePath) ?? dir.lastPathComponent)/\n\(relative.trimmingCharacters(in: .newlines))"
    }

    private func executeCreateDirectory(_ input: CreateDirectoryInput) async throws -> String {
        let url = resolvedURL(input.path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return "Created \(url.relativePath(from: workspacePath) ?? url.path)/"
    }

    private func executeGetFileInfo(_ input: GetFileInfoInput) async throws -> String {
        let url = resolvedURL(input.path)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let isDir = (attrs[.type] as? FileAttributeType) == .typeDirectory
        var lines = ["\(url.relativePath(from: workspacePath) ?? url.path)"]
        lines.append("Type: \(isDir ? "directory" : "file")")
        if !isDir, let size = attrs[.size] as? Int { lines.append("Size: \(formatSize(size))") }
        if let date = attrs[.modificationDate] as? Date {
            lines.append("Modified: \(date.formatted(date: .abbreviated, time: .shortened))")
        }
        if !isDir {
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            lines.append("Lines: \(content.components(separatedBy: "\n").count)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    func runProcess(command: String, in directory: URL?) async throws -> (String, String, Int32) {
        try await withCheckedThrowingContinuation { continuation in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", command]
            p.currentDirectoryURL = directory
            let out = Pipe(), err = Pipe()
            p.standardOutput = out; p.standardError = err
            p.terminationHandler = { proc in
                let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: (o, e, proc.terminationStatus))
            }
            do { try p.run() } catch { continuation.resume(throwing: error) }
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        let kb = 1024, mb = kb * 1024, gb = mb * 1024
        if bytes >= gb { return String(format: "%.1f GB", Double(bytes) / Double(gb)) }
        if bytes >= mb { return String(format: "%.1f MB", Double(bytes) / Double(mb)) }
        if bytes >= kb { return String(format: "%d KB", bytes / kb) }
        return "\(bytes) B"
    }
}

// MARK: - URL helpers

extension URL {
    func relativePath(from base: URL?) -> String? {
        guard let base else { return lastPathComponent }
        let myParts = pathComponents
        let baseParts = base.pathComponents
        guard myParts.starts(with: baseParts) else { return lastPathComponent }
        return myParts.dropFirst(baseParts.count).joined(separator: "/")
    }
}

// MARK: - String helpers

extension String {
    func replacingFirstOccurrence(of target: String, with replacement: String) -> String {
        guard let range = self.range(of: target) else { return self }
        return self.replacingCharacters(in: range, with: replacement)
    }
}
