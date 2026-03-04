// Copyright © 2025 Apple Inc.

import Foundation
import MLXLMCommon

// MARK: - Coding Tool I/O Types

struct ReadFileInput: Codable {
    let path: String
    let startLine: Int?
    let endLine: Int?

    enum CodingKeys: String, CodingKey {
        case path
        case startLine = "start_line"
        case endLine = "end_line"
    }
}

struct WriteFileInput: Codable {
    let path: String
    let content: String
}

struct ListDirectoryInput: Codable {
    let path: String?
}

struct RunShellInput: Codable {
    let command: String
    let workingDirectory: String?

    enum CodingKeys: String, CodingKey {
        case command
        case workingDirectory = "working_directory"
    }
}

struct SearchFilesInput: Codable {
    let pattern: String
    let directory: String?
    let filePattern: String?
    let maxResults: Int?

    enum CodingKeys: String, CodingKey {
        case pattern
        case directory
        case filePattern = "file_pattern"
        case maxResults = "max_results"
    }
}

struct CreateDirectoryInput: Codable {
    let path: String
}

struct DeleteFileInput: Codable {
    let path: String
}

struct GetFileInfoInput: Codable {
    let path: String
}

// MARK: - Coding Tool Executor

@MainActor
class CodingToolExecutor {

    var workspacePath: URL?

    init(workspacePath: URL?) {
        self.workspacePath = workspacePath
    }

    // MARK: - Tool Schemas

    var allToolSchemas: [ToolSpec] {
        return [
            readFileSchema,
            writeFileSchema,
            listDirectorySchema,
            runShellSchema,
            searchFilesSchema,
            createDirectorySchema,
            getFileInfoSchema,
        ]
    }

    private var readFileSchema: ToolSpec {
        [
            "type": "function",
            "function": [
                "name": "read_file",
                "description": "Read the contents of a file. Returns file content with line numbers. Use this before modifying any file.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "Path to the file (relative to workspace or absolute)",
                        ] as ToolSpec,
                        "start_line": [
                            "type": "integer",
                            "description": "Starting line number (1-based). Omit to read from beginning.",
                        ] as ToolSpec,
                        "end_line": [
                            "type": "integer",
                            "description": "Ending line number (1-based). Omit to read to end.",
                        ] as ToolSpec,
                    ] as ToolSpec,
                    "required": ["path"],
                ] as ToolSpec,
            ] as ToolSpec,
        ]
    }

    private var writeFileSchema: ToolSpec {
        [
            "type": "function",
            "function": [
                "name": "write_file",
                "description": "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Always read the file first if it exists.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "Path to the file (relative to workspace or absolute)",
                        ] as ToolSpec,
                        "content": [
                            "type": "string",
                            "description": "The complete content to write to the file",
                        ] as ToolSpec,
                    ] as ToolSpec,
                    "required": ["path", "content"],
                ] as ToolSpec,
            ] as ToolSpec,
        ]
    }

    private var listDirectorySchema: ToolSpec {
        [
            "type": "function",
            "function": [
                "name": "list_directory",
                "description": "List the contents of a directory. Returns files and subdirectories. Use to explore the workspace structure.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "Directory path. Defaults to workspace root if omitted.",
                        ] as ToolSpec,
                    ] as ToolSpec,
                    "required": [] as [String],
                ] as ToolSpec,
            ] as ToolSpec,
        ]
    }

    private var runShellSchema: ToolSpec {
        [
            "type": "function",
            "function": [
                "name": "run_shell_command",
                "description": "Execute a shell command and return stdout/stderr. Use for running tests, builds, git commands, installing packages, etc.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "command": [
                            "type": "string",
                            "description": "The shell command to execute",
                        ] as ToolSpec,
                        "working_directory": [
                            "type": "string",
                            "description": "Working directory for the command. Defaults to workspace root.",
                        ] as ToolSpec,
                    ] as ToolSpec,
                    "required": ["command"],
                ] as ToolSpec,
            ] as ToolSpec,
        ]
    }

    private var searchFilesSchema: ToolSpec {
        [
            "type": "function",
            "function": [
                "name": "search_files",
                "description": "Search for a text pattern across files in the workspace. Returns matching lines with file paths and line numbers.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "pattern": [
                            "type": "string",
                            "description": "Search pattern (supports basic regex)",
                        ] as ToolSpec,
                        "directory": [
                            "type": "string",
                            "description": "Directory to search in. Defaults to workspace root.",
                        ] as ToolSpec,
                        "file_pattern": [
                            "type": "string",
                            "description": "Glob pattern for files to include, e.g. '*.swift', '*.py'. Defaults to all files.",
                        ] as ToolSpec,
                        "max_results": [
                            "type": "integer",
                            "description": "Maximum number of matching lines to return. Defaults to 50.",
                        ] as ToolSpec,
                    ] as ToolSpec,
                    "required": ["pattern"],
                ] as ToolSpec,
            ] as ToolSpec,
        ]
    }

    private var createDirectorySchema: ToolSpec {
        [
            "type": "function",
            "function": [
                "name": "create_directory",
                "description": "Create a new directory, including all intermediate parent directories.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "Path of the directory to create",
                        ] as ToolSpec,
                    ] as ToolSpec,
                    "required": ["path"],
                ] as ToolSpec,
            ] as ToolSpec,
        ]
    }

    private var getFileInfoSchema: ToolSpec {
        [
            "type": "function",
            "function": [
                "name": "get_file_info",
                "description": "Get metadata about a file or directory: size, modification date, type, permissions.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "Path to the file or directory",
                        ] as ToolSpec,
                    ] as ToolSpec,
                    "required": ["path"],
                ] as ToolSpec,
            ] as ToolSpec,
        ]
    }

    // MARK: - Tool Execution

    func execute(name: String, arguments: String) async -> String {
        guard let argsData = arguments.data(using: .utf8) else {
            return "Error: Invalid tool arguments JSON"
        }
        let decoder = JSONDecoder()

        do {
            switch name {
            case "read_file":
                let input = try decoder.decode(ReadFileInput.self, from: argsData)
                return try await executeReadFile(input)
            case "write_file":
                let input = try decoder.decode(WriteFileInput.self, from: argsData)
                return try await executeWriteFile(input)
            case "list_directory":
                let input = try decoder.decode(ListDirectoryInput.self, from: argsData)
                return try await executeListDirectory(input)
            case "run_shell_command":
                let input = try decoder.decode(RunShellInput.self, from: argsData)
                return try await executeRunShell(input)
            case "search_files":
                let input = try decoder.decode(SearchFilesInput.self, from: argsData)
                return try await executeSearchFiles(input)
            case "create_directory":
                let input = try decoder.decode(CreateDirectoryInput.self, from: argsData)
                return try await executeCreateDirectory(input)
            case "get_file_info":
                let input = try decoder.decode(GetFileInfoInput.self, from: argsData)
                return try await executeGetFileInfo(input)
            default:
                return "Unknown tool: \(name)"
            }
        } catch {
            return "Tool error [\(name)]: \(error.localizedDescription)"
        }
    }

    // MARK: - Path Resolution

    private func resolvedURL(_ path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        let base = workspacePath ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent(path)
    }

    // MARK: - Tool Implementations

    private func executeReadFile(_ input: ReadFileInput) async throws -> String {
        let url = resolvedURL(input.path)
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")
        let totalLines = lines.count

        let startLine = max(1, input.startLine ?? 1)
        let endLine = min(totalLines, input.endLine ?? totalLines)

        guard startLine <= endLine, startLine <= totalLines else {
            return "File has \(totalLines) lines. Requested range \(startLine)-\(endLine) is out of bounds."
        }

        let selectedLines = Array(lines[(startLine - 1)...(endLine - 1)])
        let numberedLines = selectedLines.enumerated().map { i, line in
            "\(startLine + i): \(line)"
        }

        var result = "File: \(url.lastPathComponent) (\(totalLines) lines total)"
        if startLine > 1 || endLine < totalLines {
            result += " [showing lines \(startLine)-\(endLine)]"
        }
        result += "\n\n" + numberedLines.joined(separator: "\n")
        return result
    }

    private func executeWriteFile(_ input: WriteFileInput) async throws -> String {
        let url = resolvedURL(input.path)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try input.content.write(to: url, atomically: true, encoding: .utf8)
        let lineCount = input.content.components(separatedBy: "\n").count
        return "Successfully wrote \(lineCount) lines to \(url.path)"
    }

    private func executeListDirectory(_ input: ListDirectoryInput) async throws -> String {
        let dirURL: URL
        if let path = input.path {
            dirURL = resolvedURL(path)
        } else {
            dirURL = workspacePath ?? FileManager.default.homeDirectoryForCurrentUser
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let sorted = contents.sorted { a, b in
            let aIsDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bIsDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if aIsDir != bIsDir { return aIsDir }
            return a.lastPathComponent.lowercased() < b.lastPathComponent.lowercased()
        }

        var lines = ["Directory: \(dirURL.path)", ""]
        for url in sorted {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if isDir {
                lines.append("📁  \(url.lastPathComponent)/")
            } else {
                let sizeStr = formatFileSize(size)
                lines.append("📄  \(url.lastPathComponent)  (\(sizeStr))")
            }
        }
        lines.append("")
        lines.append("\(sorted.count) items")
        return lines.joined(separator: "\n")
    }

    private func executeRunShell(_ input: RunShellInput) async throws -> String {
        let workDir: URL?
        if let wd = input.workingDirectory {
            workDir = resolvedURL(wd)
        } else {
            workDir = workspacePath
        }

        let (stdout, stderr, exitCode) = try await runProcess(
            command: input.command,
            workingDirectory: workDir
        )

        var result = "$ \(input.command)\n"
        if !stdout.isEmpty {
            result += stdout
        }
        if !stderr.isEmpty {
            result += stderr.hasPrefix("\n") ? stderr : "\n" + stderr
        }
        if exitCode != 0 {
            result += "\n[Exit code: \(exitCode)]"
        }
        return result.trimmingCharacters(in: .newlines)
    }

    private func executeSearchFiles(_ input: SearchFilesInput) async throws -> String {
        let searchDir: URL
        if let dir = input.directory {
            searchDir = resolvedURL(dir)
        } else {
            searchDir = workspacePath ?? FileManager.default.homeDirectoryForCurrentUser
        }

        let maxResults = input.maxResults ?? 50
        let filePattern = input.filePattern ?? "*"

        // Build grep command
        var grepCmd = "grep -rn --include='\(filePattern)' -m \(maxResults)"
        grepCmd += " '\(input.pattern.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
        grepCmd += " '\(searchDir.path)'"
        grepCmd += " 2>/dev/null | head -\(maxResults)"

        let (stdout, _, _) = try await runProcess(command: grepCmd, workingDirectory: nil)

        if stdout.isEmpty {
            return "No matches found for '\(input.pattern)' in \(searchDir.lastPathComponent)"
        }

        let matches = stdout.components(separatedBy: "\n").filter { !$0.isEmpty }
        var result = "Search results for '\(input.pattern)' in \(searchDir.path):\n\n"
        result += matches.joined(separator: "\n")
        if matches.count >= maxResults {
            result += "\n\n[Results limited to \(maxResults) matches]"
        }
        return result
    }

    private func executeCreateDirectory(_ input: CreateDirectoryInput) async throws -> String {
        let url = resolvedURL(input.path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return "Created directory: \(url.path)"
    }

    private func executeGetFileInfo(_ input: GetFileInfoInput) async throws -> String {
        let url = resolvedURL(input.path)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)

        let isDir = (attrs[.type] as? FileAttributeType) == .typeDirectory
        let size = (attrs[.size] as? Int) ?? 0
        let modDate = attrs[.modificationDate] as? Date

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        var info = ["Path: \(url.path)"]
        info.append("Type: \(isDir ? "Directory" : "File")")
        if !isDir { info.append("Size: \(formatFileSize(size))") }
        if let date = modDate { info.append("Modified: \(formatter.string(from: date))") }
        info.append("Extension: \(url.pathExtension.isEmpty ? "none" : url.pathExtension)")

        return info.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func runProcess(command: String, workingDirectory: URL?) async throws -> (String, String, Int32) {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = workingDirectory

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { proc in
                let stdout = String(
                    data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8) ?? ""
                let stderr = String(
                    data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8) ?? ""
                continuation.resume(returning: (stdout, stderr, proc.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let kb = 1024
        let mb = kb * 1024
        let gb = mb * 1024
        if bytes >= gb { return String(format: "%.2f GB", Double(bytes) / Double(gb)) }
        if bytes >= mb { return String(format: "%.1f MB", Double(bytes) / Double(mb)) }
        if bytes >= kb { return String(format: "%.0f KB", Double(bytes) / Double(kb)) }
        return "\(bytes) B"
    }
}
