// Copyright © 2025 Apple Inc.

import Foundation
import MLXLMCommon

// MARK: - Coding Tool I/O Types

struct ReadFileInput: Codable {
    let path: String; let startLine: Int?; let endLine: Int?
    enum CodingKeys: String, CodingKey {
        case path; case startLine = "start_line"; case endLine = "end_line"
    }
}
struct WriteFileInput: Codable { let path: String; let content: String }
struct ListDirectoryInput: Codable { let path: String? }
struct EditFileInput: Codable {
    let path: String; let oldString: String; let newString: String
    enum CodingKeys: String, CodingKey {
        case path; case oldString = "old_string"; case newString = "new_string"
    }
}
struct RunShellInput: Codable {
    let command: String; let workingDirectory: String?
    enum CodingKeys: String, CodingKey {
        case command; case workingDirectory = "working_directory"
    }
}
struct SearchFilesInput: Codable {
    let pattern: String; let directory: String?; let filePattern: String?; let maxResults: Int?
    enum CodingKeys: String, CodingKey {
        case pattern; case directory; case filePattern = "file_pattern"; case maxResults = "max_results"
    }
}
struct CreateDirectoryInput: Codable { let path: String }
struct GetFileInfoInput: Codable { let path: String }
struct RunTestsInput: Codable {
    let testTarget: String?; let testFilter: String?
    enum CodingKeys: String, CodingKey {
        case testTarget = "test_target"; case testFilter = "test_filter"
    }
}

// MARK: - Project Info

struct ProjectInfo {
    var type: ProjectType
    var buildCommand: String
    var testCommand: String
    var runCommand: String?
    var language: String

    enum ProjectType: String {
        case swift = "Swift Package"
        case xcode = "Xcode Project"
        case python = "Python"
        case nodejs = "Node.js"
        case rust = "Rust"
        case go = "Go"
        case make = "Makefile"
        case unknown = "Unknown"
    }
}

// MARK: - Coding Tool Executor

@MainActor
class CodingToolExecutor {

    var workspacePath: URL?
    private(set) var projectInfo: ProjectInfo?

    init(workspacePath: URL?) {
        self.workspacePath = workspacePath
    }

    // MARK: - All Tool Schemas

    var allToolSchemas: [ToolSpec] {
        [
            readFileSchema, editFileSchema, writeFileSchema,
            listDirectorySchema, runShellSchema, runTestsSchema,
            searchFilesSchema, createDirectorySchema, getFileInfoSchema,
        ]
    }

    // MARK: - Schemas

    private var readFileSchema: ToolSpec {[
        "type": "function",
        "function": [
            "name": "read_file",
            "description": "Read file contents with line numbers. Always read a file before modifying it. Use start_line/end_line to read around an error line.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "File path (relative to workspace or absolute)"] as ToolSpec,
                    "start_line": ["type": "integer", "description": "First line (1-based). Omit to read from start."] as ToolSpec,
                    "end_line": ["type": "integer", "description": "Last line (1-based). Omit to read to end."] as ToolSpec,
                ] as ToolSpec,
                "required": ["path"],
            ] as ToolSpec,
        ] as ToolSpec,
    ]}

    private var editFileSchema: ToolSpec {[
        "type": "function",
        "function": [
            "name": "edit_file",
            "description": "Make a targeted edit to an existing file by replacing exact text. PREFERRED over write_file for fixes. old_string must match exactly (whitespace, indentation). Shows a diff of what changed.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to the file"] as ToolSpec,
                    "old_string": ["type": "string", "description": "Exact text to replace (must match file content exactly)"] as ToolSpec,
                    "new_string": ["type": "string", "description": "Replacement text"] as ToolSpec,
                ] as ToolSpec,
                "required": ["path", "old_string", "new_string"],
            ] as ToolSpec,
        ] as ToolSpec,
    ]}

    private var writeFileSchema: ToolSpec {[
        "type": "function",
        "function": [
            "name": "write_file",
            "description": "Write complete content to a file. Use for NEW files only. For existing files use edit_file instead.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "File path (relative to workspace)"] as ToolSpec,
                    "content": ["type": "string", "description": "Complete file content"] as ToolSpec,
                ] as ToolSpec,
                "required": ["path", "content"],
            ] as ToolSpec,
        ] as ToolSpec,
    ]}

    private var listDirectorySchema: ToolSpec {[
        "type": "function",
        "function": [
            "name": "list_directory",
            "description": "List directory contents. Use to explore project structure.",
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
            "description": "Execute a shell command. Use for: builds (swift build, xcodebuild, npm run build), tests, git commands, installing packages, viewing logs. Output is truncated at 6000 chars.",
            "parameters": [
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "Shell command to run"] as ToolSpec,
                    "working_directory": ["type": "string", "description": "Override working directory. Default: workspace root."] as ToolSpec,
                ] as ToolSpec,
                "required": ["command"],
            ] as ToolSpec,
        ] as ToolSpec,
    ]}

    private var runTestsSchema: ToolSpec {[
        "type": "function",
        "function": [
            "name": "run_tests",
            "description": "Run the project's test suite and parse results. Automatically detects the test framework (swift test, pytest, jest, cargo test, go test). Shows pass/fail summary and details of failures.",
            "parameters": [
                "type": "object",
                "properties": [
                    "test_target": ["type": "string", "description": "Specific test target or file to run (optional). E.g. 'MyTests' for Swift, 'tests/test_foo.py' for Python."] as ToolSpec,
                    "test_filter": ["type": "string", "description": "Filter to run specific test cases. E.g. 'testFoo' for Swift, '-k foo' for pytest."] as ToolSpec,
                ] as ToolSpec,
                "required": [] as [String],
            ] as ToolSpec,
        ] as ToolSpec,
    ]}

    private var searchFilesSchema: ToolSpec {[
        "type": "function",
        "function": [
            "name": "search_files",
            "description": "Search for a text pattern across files. Great for finding where a symbol is defined, finding all usages, or locating error-related code.",
            "parameters": [
                "type": "object",
                "properties": [
                    "pattern": ["type": "string", "description": "Search pattern (regex supported)"] as ToolSpec,
                    "directory": ["type": "string", "description": "Directory to search. Defaults to workspace root."] as ToolSpec,
                    "file_pattern": ["type": "string", "description": "File glob: '*.swift', '*.py'. Default: all files."] as ToolSpec,
                    "max_results": ["type": "integer", "description": "Max matches. Default: 50."] as ToolSpec,
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
            "description": "Get metadata about a file: size, line count, modification date.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to the file"] as ToolSpec,
                ] as ToolSpec,
                "required": ["path"],
            ] as ToolSpec,
        ] as ToolSpec,
    ]}

    // MARK: - Tool Dispatch

    func execute(name: String, arguments: String) async -> String {
        guard let argsData = arguments.data(using: .utf8) else { return "Error: invalid JSON" }
        let d = JSONDecoder()
        do {
            switch name {
            case "read_file":       return try await executeReadFile(d.decode(ReadFileInput.self, from: argsData))
            case "edit_file":       return try await executeEditFile(d.decode(EditFileInput.self, from: argsData))
            case "write_file":      return try await executeWriteFile(d.decode(WriteFileInput.self, from: argsData))
            case "list_directory":  return try await executeListDirectory(d.decode(ListDirectoryInput.self, from: argsData))
            case "run_shell_command": return try await executeRunShell(d.decode(RunShellInput.self, from: argsData))
            case "run_tests":       return try await executeRunTests(d.decode(RunTestsInput.self, from: argsData))
            case "search_files":    return try await executeSearchFiles(d.decode(SearchFilesInput.self, from: argsData))
            case "create_directory":return try await executeCreateDirectory(d.decode(CreateDirectoryInput.self, from: argsData))
            case "get_file_info":   return try await executeGetFileInfo(d.decode(GetFileInfoInput.self, from: argsData))
            default:                return "Unknown tool: \(name)"
            }
        } catch { return "Tool error [\(name)]: \(error.localizedDescription)" }
    }

    // MARK: - Project Detection

    func detectProject() async -> ProjectInfo {
        guard let ws = workspacePath else {
            return ProjectInfo(type: .unknown, buildCommand: "make", testCommand: "make test", language: "Unknown")
        }

        let fm = FileManager.default
        let at: (String) -> Bool = { fm.fileExists(atPath: ws.appendingPathComponent($0).path) }
        let glob: (String) -> Bool = {
            (try? fm.contentsOfDirectory(atPath: ws.path))?.contains(where: { $0.hasSuffix($0) }) ?? false
        }

        let info: ProjectInfo
        if at("Package.swift") {
            info = ProjectInfo(type: .swift, buildCommand: "swift build 2>&1", testCommand: "swift test 2>&1", runCommand: "swift run 2>&1", language: "Swift")
        } else if (try? fm.contentsOfDirectory(atPath: ws.path))?.contains(where: { $0.hasSuffix(".xcodeproj") }) == true {
            let proj = (try? fm.contentsOfDirectory(atPath: ws.path))?.first(where: { $0.hasSuffix(".xcodeproj") }) ?? "Project.xcodeproj"
            let scheme = String(proj.dropLast(".xcodeproj".count))
            info = ProjectInfo(type: .xcode, buildCommand: "xcodebuild -scheme \(scheme) build 2>&1 | tail -50", testCommand: "xcodebuild -scheme \(scheme) test 2>&1 | tail -80", language: "Swift")
        } else if at("Cargo.toml") {
            info = ProjectInfo(type: .rust, buildCommand: "cargo build 2>&1", testCommand: "cargo test 2>&1", runCommand: "cargo run 2>&1", language: "Rust")
        } else if at("go.mod") {
            info = ProjectInfo(type: .go, buildCommand: "go build ./... 2>&1", testCommand: "go test ./... 2>&1", language: "Go")
        } else if at("package.json") {
            let hasYarn = at("yarn.lock")
            let pm = hasYarn ? "yarn" : "npm"
            info = ProjectInfo(type: .nodejs, buildCommand: "\(pm) run build 2>&1", testCommand: "\(pm) test 2>&1", language: "JavaScript/TypeScript")
        } else if at("pyproject.toml") || at("setup.py") || at("requirements.txt") {
            info = ProjectInfo(type: .python, buildCommand: "python -m py_compile **/*.py 2>&1", testCommand: "python -m pytest -v 2>&1", language: "Python")
        } else if at("Makefile") {
            info = ProjectInfo(type: .make, buildCommand: "make 2>&1", testCommand: "make test 2>&1", language: "Unknown")
        } else {
            info = ProjectInfo(type: .unknown, buildCommand: "echo 'No build system detected'", testCommand: "echo 'No test runner detected'", language: "Unknown")
        }

        projectInfo = info
        return info
    }

    // MARK: - Path Resolution

    func resolvedURL(_ path: String) -> URL {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return (workspacePath ?? FileManager.default.homeDirectoryForCurrentUser).appendingPathComponent(path)
    }

    // MARK: - Tool Implementations

    private func executeReadFile(_ input: ReadFileInput) async throws -> String {
        let url = resolvedURL(input.path)
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")
        let total = lines.count
        let s = max(1, input.startLine ?? 1)
        let e = min(total, input.endLine ?? total)
        guard s <= e else { return "Error: line range \(s)–\(e) out of bounds (file has \(total) lines)" }
        let numbered = lines[(s-1)...(e-1)].enumerated().map { i, line in
            String(format: "%4d\t%@", s + i, line)
        }
        var out = "\(url.relativePath(from: workspacePath)) (\(total) lines total)"
        if s > 1 || e < total { out += " · showing lines \(s)–\(e)" }
        return out + "\n" + numbered.joined(separator: "\n")
    }

    private func executeEditFile(_ input: EditFileInput) async throws -> String {
        let url = resolvedURL(input.path)
        let original = try String(contentsOf: url, encoding: .utf8)
        guard original.contains(input.oldString) else {
            let preview = String(original.prefix(300)).replacingOccurrences(of: "\n", with: "↵")
            return "Error: old_string not found in \(url.lastPathComponent). Match must be exact (whitespace matters).\nFile preview: \(preview)"
        }
        let updated = original.replacingFirstOccurrence(of: input.oldString, with: input.newString)
        try updated.write(to: url, atomically: true, encoding: .utf8)
        let oldLines = input.oldString.components(separatedBy: "\n")
        let newLines = input.newString.components(separatedBy: "\n")
        var diff = "Edited \(url.relativePath(from: workspacePath))\n"
        diff += oldLines.map { "- \($0)" }.joined(separator: "\n")
        if !input.newString.isEmpty { diff += "\n" + newLines.map { "+ \($0)" }.joined(separator: "\n") }
        return diff
    }

    private func executeWriteFile(_ input: WriteFileInput) async throws -> String {
        let url = resolvedURL(input.path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existed = FileManager.default.fileExists(atPath: url.path)
        try input.content.write(to: url, atomically: true, encoding: .utf8)
        let lines = input.content.components(separatedBy: "\n").count
        return "\(existed ? "Updated" : "Created") \(url.relativePath(from: workspacePath)) (\(lines) lines)"
    }

    private func executeListDirectory(_ input: ListDirectoryInput) async throws -> String {
        let dirURL = input.path.map { resolvedURL($0) } ?? workspacePath ?? FileManager.default.homeDirectoryForCurrentUser
        let contents = try FileManager.default.contentsOfDirectory(
            at: dirURL, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]
        ).sorted { a, b in
            let aD = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bD = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if aD != bD { return aD }
            return a.lastPathComponent.lowercased() < b.lastPathComponent.lowercased()
        }
        var lines = ["\(dirURL.relativePath(from: workspacePath?.deletingLastPathComponent()) ?? dirURL.lastPathComponent)/"]
        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            lines.append(isDir ? "  \(url.lastPathComponent)/" : "  \(url.lastPathComponent)  \(formatSize(size))")
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
            let maxChars = 6000
            let truncated = combined.count > maxChars
                ? String(combined.prefix(maxChars)) + "\n… [output truncated, \(combined.count - maxChars) chars omitted]"
                : combined
            out += "\n" + truncated
        }
        if code != 0 { out += "\n[exit \(code)]" }
        return out
    }

    private func executeRunTests(_ input: RunTestsInput) async throws -> String {
        let info = projectInfo ?? (await detectProject())
        var cmd = info.testCommand

        // Append target/filter if provided
        if let target = input.testTarget, !target.isEmpty {
            switch info.type {
            case .swift:   cmd = "swift test --filter \(target) 2>&1"
            case .python:  cmd = "python -m pytest \(target) -v 2>&1"
            case .nodejs:  cmd = "\(cmd.hasPrefix("yarn") ? "yarn" : "npm") test -- --testPathPattern=\(target) 2>&1"
            case .rust:    cmd = "cargo test \(target) 2>&1"
            case .go:      cmd = "go test ./... -run \(target) 2>&1"
            default:       break
            }
        }
        if let filter = input.testFilter, !filter.isEmpty {
            switch info.type {
            case .swift:   cmd += " --filter \(filter)"
            case .python:  cmd += " -k '\(filter)'"
            case .rust:    cmd += " \(filter)"
            default:       break
            }
        }

        let (stdout, stderr, code) = try await runProcess(command: cmd, in: workspacePath)
        let raw = (stdout + stderr).trimmingCharacters(in: .newlines)

        // Parse summary
        let summary = parseTestSummary(raw: raw, projectType: info.type)
        let truncated = raw.count > 5000 ? String(raw.prefix(5000)) + "\n…" : raw
        return "$ \(cmd)\n\n\(truncated)\n\n\(summary)"
    }

    private func executeSearchFiles(_ input: SearchFilesInput) async throws -> String {
        let dir = input.directory.map { resolvedURL($0) } ?? workspacePath ?? FileManager.default.homeDirectoryForCurrentUser
        let max = input.maxResults ?? 50
        let pat = input.pattern.replacingOccurrences(of: "'", with: "'\"'\"'")
        let cmd = "grep -rn --include='\(input.filePattern ?? "*")' -m \(max) '\(pat)' '\(dir.path)' 2>/dev/null | head -\(max)"
        let (stdout, _, _) = try await runProcess(command: cmd, in: nil)
        if stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No matches for '\(input.pattern)'"
        }
        let relative = stdout.replacingOccurrences(of: dir.path + "/", with: "")
        return "grep '\(input.pattern)'\n\(relative.trimmingCharacters(in: .newlines))"
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
        var lines = [url.relativePath(from: workspacePath) ?? url.path]
        lines.append("Type: \(isDir ? "directory" : "file")")
        if !isDir, let size = attrs[.size] as? Int { lines.append("Size: \(formatSize(size))") }
        if let date = attrs[.modificationDate] as? Date {
            lines.append("Modified: \(date.formatted(date: .abbreviated, time: .shortened))")
        }
        if !isDir, let content = try? String(contentsOf: url, encoding: .utf8) {
            lines.append("Lines: \(content.components(separatedBy: "\n").count)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Test Summary Parser

    private func parseTestSummary(raw: String, projectType: ProjectInfo.ProjectType) -> String {
        let lines = raw.components(separatedBy: "\n")
        switch projectType {
        case .swift:
            if let summary = lines.first(where: { $0.contains("Test Suite") && ($0.contains("passed") || $0.contains("failed")) }) {
                return summary
            }
            let passed = lines.filter { $0.contains("Test Case") && $0.contains("passed") }.count
            let failed = lines.filter { $0.contains("Test Case") && $0.contains("failed") }.count
            if passed + failed > 0 { return "✓ \(passed) passed  ✗ \(failed) failed" }
        case .python:
            if let summary = lines.last(where: { $0.contains("passed") || $0.contains("failed") || $0.contains("error") }) {
                return summary
            }
        case .nodejs:
            if let summary = lines.first(where: { $0.contains("Tests:") }) { return summary }
        case .rust:
            if let summary = lines.first(where: { $0.contains("test result") }) { return summary }
        case .go:
            let ok = lines.contains(where: { $0.hasPrefix("ok") })
            let fail = lines.contains(where: { $0.hasPrefix("FAIL") })
            return ok && !fail ? "✓ All tests passed" : fail ? "✗ Tests failed" : ""
        default: break
        }
        return ""
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

// MARK: - URL / String helpers

extension URL {
    func relativePath(from base: URL?) -> String {
        guard let base else { return lastPathComponent }
        let my = pathComponents, b = base.pathComponents
        guard my.starts(with: b) else { return lastPathComponent }
        let rel = my.dropFirst(b.count).joined(separator: "/")
        return rel.isEmpty ? lastPathComponent : rel
    }
}

extension String {
    func replacingFirstOccurrence(of target: String, with replacement: String) -> String {
        guard let range = self.range(of: target) else { return self }
        return self.replacingCharacters(in: range, with: replacement)
    }
}
