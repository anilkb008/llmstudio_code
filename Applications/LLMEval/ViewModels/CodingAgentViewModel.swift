// Copyright © 2025 Apple Inc.

import Hub
import MLX
import MLXLLM
import MLXLMCommon
import Metal
import SwiftUI

@Observable
@MainActor
class CodingAgentViewModel {

    // MARK: - UI State
    var messages: [AgentMessage] = []
    var running = false
    var modelInfo = ""
    var downloadProgress: Double?
    var totalSize: String?
    var workspacePath: URL?
    var detectedProject: ProjectInfo?

    // Session stats
    var totalToolCalls = 0
    var totalTokensGenerated = 0

    // MARK: - Model Config
    var modelConfiguration = LLMRegistry.qwen3_8b_4bit
    var generateParameters: GenerateParameters { GenerateParameters(maxTokens: 8192, temperature: 0.4) }

    // MARK: - Private State
    private var loadState = LoadState.idle
    private var generationTask: Task<Void, Error>?
    private(set) var toolExecutor: CodingToolExecutor
    private var llmHistory: [Chat.Message] = []

    // MARK: - System Prompt

    private static func makeSystemPrompt(workspace: String, project: ProjectInfo?) -> String {
        let projectSection: String
        if let p = project {
            projectSection = """
                ## Detected Project
                - Type: \(p.type.rawValue)
                - Language: \(p.language)
                - Build: `\(p.buildCommand)`
                - Test:  `\(p.testCommand)`
                \(p.runCommand.map { "- Run:   `\($0)`" } ?? "")
                """
        } else {
            projectSection = "## Project\nNo project detected yet. Run `list_directory` to explore."
        }

        return """
            You are an autonomous coding agent with full file system and shell access. You behave exactly like Claude Code.

            \(projectSection)

            ## Workspace
            \(workspace)

            ## How You Work

            ### For ANY task, follow this loop:
            1. **Explore** — Start with `list_directory` or `search_files` to understand structure
            2. **Read** — Call `read_file` before touching any existing file (always)
            3. **Act** — Use `edit_file` for changes (never rewrite whole files unless creating new)
            4. **Verify** — Run `run_shell_command` to build/test after every change
            5. **Iterate** — If the build still fails, read the error, fix it, verify again

            ### Error Analysis Workflow (CRITICAL)
            When given a build error, compiler error, test failure, or stack trace:

            **Step 1 — Get fresh errors:**
            Run the build command to capture current errors:
            ```
            \(project?.buildCommand ?? "swift build 2>&1")
            ```

            **Step 2 — Parse each error:**
            Look for patterns like:
            - Swift/Clang: `Sources/Foo/Bar.swift:42:10: error: cannot find 'baz'`
            - Python: `File "foo.py", line 42, in <function>` → `TypeError: ...`
            - Node/TS: `src/index.ts(42,10): error TS1234: ...`
            - Rust: `error[E0...]: ... --> src/main.rs:42:10`
            - Go: `./main.go:42:10: undefined: foo`

            **Step 3 — Read context around each error:**
            Use `read_file` with `start_line`/`end_line` (e.g. ±10 lines around the error line)

            **Step 4 — Fix with `edit_file`:**
            Make the minimal targeted change. Never rewrite the whole file.

            **Step 5 — Verify:**
            Run the build again. If errors remain, repeat from Step 2.

            ### Key Rules
            - NEVER skip reading a file before editing it
            - ALWAYS use `edit_file` for existing files (not `write_file`)
            - ALWAYS verify fixes by running the build/tests
            - Fix ALL errors in one pass before re-running (don't fix one at a time inefficiently)
            - If `edit_file` fails (old_string not found), re-read the file first to get exact content
            - Keep explanations short — one sentence before each tool call

            ### Tool Reference
            | Tool | Use for |
            |------|---------|
            | `read_file` | Read any file. Use `start_line`/`end_line` around error lines |
            | `edit_file` | Fix code — targeted find/replace, shows diff |
            | `write_file` | Create NEW files only |
            | `run_shell_command` | Build, test, git, grep, any bash |
            | `run_tests` | Run test suite, parse pass/fail |
            | `list_directory` | Explore project structure |
            | `search_files` | Find symbols, usages, TODO/FIXME |
            | `create_directory` | Make directories |
            | `get_file_info` | File size, line count |
            """
    }

    enum LoadState { case idle, loading, loaded(ModelContainer) }

    var isLoading: Bool { if case .loading = loadState { return true }; return false }

    // MARK: - Init
    init() {
        self.toolExecutor = CodingToolExecutor(workspacePath: nil)
        resetHistory(project: nil)
    }

    // MARK: - Workspace

    func setWorkspace(_ url: URL) {
        workspacePath = url
        toolExecutor.workspacePath = url

        messages.append(AgentMessage(role: .assistant,
            content: "Opening **\(url.lastPathComponent)**…"))

        // Detect project type then auto-explore
        Task {
            let project = await toolExecutor.detectProject()
            detectedProject = project
            resetHistory(project: project)

            // Post project-detected message
            let projectMsg = """
                Detected **\(project.type.rawValue)** project (\(project.language))

                Build: `\(project.buildCommand)`
                Test:  `\(project.testCommand)`

                Exploring workspace…
                """
            messages.append(AgentMessage(role: .assistant, content: projectMsg))

            // Auto-send exploration request
            sendMessage("List the workspace directory structure and give a brief overview of the project.")
        }
    }

    private func resetHistory(project: ProjectInfo?) {
        let ws = workspacePath?.path ?? "not set"
        llmHistory = [.system(Self.makeSystemPrompt(workspace: ws, project: project))]
    }

    func clearConversation() {
        messages.removeAll()
        totalToolCalls = 0
        totalTokensGenerated = 0
        resetHistory(project: detectedProject)
    }

    // MARK: - Send Message

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !running else { return }

        let userMsg = AgentMessage(role: .user, content: trimmed)
        messages.append(userMsg)
        llmHistory.append(.user(trimmed))

        generationTask = Task {
            running = true
            await runAgentTurn()
            running = false
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        running = false
        if let idx = messages.indices.last, messages[idx].isStreaming {
            messages[idx].isStreaming = false
            if messages[idx].content.isEmpty { messages[idx].content = "*[cancelled]*" }
        }
    }

    // MARK: - Agentic Loop

    private func runAgentTurn() async {
        do {
            let container = try await load()
            var msg = AgentMessage(role: .assistant, isStreaming: true)
            messages.append(msg)
            let msgId = msg.id

            var loop = true
            while loop {
                if Task.isCancelled { break }
                loop = await streamSegment(container: container, msgId: msgId)
            }

            if let idx = messages.firstIndex(where: { $0.id == msgId }) {
                messages[idx].isStreaming = false
            }
        } catch {
            messages.append(AgentMessage(role: .assistant,
                content: "⚠️ \(error.localizedDescription)"))
        }
    }

    /// Returns `true` if a tool call was made and the loop should continue.
    private func streamSegment(container: ModelContainer, msgId: UUID) async -> Bool {
        let userInput = UserInput(
            chat: llmHistory,
            tools: toolExecutor.allToolSchemas,
            additionalContext: [:]
        )
        do {
            MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))
            let lmInput = try await container.prepare(input: userInput)
            let stream = try await container.generate(input: lmInput, parameters: generateParameters)

            var segText = ""
            var pendingTool: ToolCall?
            var iter = stream.makeAsyncIterator()

            while let token = await iter.next() {
                if Task.isCancelled { return false }
                if let tc = token.toolCall { pendingTool = tc; break }
                if let chunk = token.chunk, !chunk.isEmpty {
                    segText += chunk
                    totalTokensGenerated += 1
                    if let idx = messages.firstIndex(where: { $0.id == msgId }) {
                        messages[idx].content += chunk
                    }
                }
            }

            if !segText.isEmpty { llmHistory.append(.assistant(segText)) }

            if let tc = pendingTool {
                await doToolCall(tc, msgId: msgId)
                return true
            }
            return false
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == msgId }) {
                messages[idx].content += "\n\n⚠️ \(error.localizedDescription)"
            }
            return false
        }
    }

    private func doToolCall(_ tc: ToolCall, msgId: UUID) async {
        let name = tc.function.name
        let args: String
        if let data = try? JSONEncoder().encode(tc.function.arguments),
           let str = String(data: data, encoding: .utf8) {
            args = str
        } else {
            args = "{}"
        }
        totalToolCalls += 1

        let record = AgentToolCall(name: name, arguments: args, isExecuting: true)
        if let idx = messages.firstIndex(where: { $0.id == msgId }) {
            messages[idx].toolCalls.append(record)
        }

        let result = await toolExecutor.execute(name: name, arguments: args)

        if let mi = messages.firstIndex(where: { $0.id == msgId }),
           let ti = messages[mi].toolCalls.firstIndex(where: { $0.id == record.id }) {
            messages[mi].toolCalls[ti].result = result
            messages[mi].toolCalls[ti].isExecuting = false
        }
        llmHistory.append(.tool(result))
    }

    // MARK: - Model Loading

    func load() async throws -> ModelContainer {
        while true {
            switch loadState {
            case .idle:    return try await performLoad()
            case .loading: try await Task.sleep(for: .milliseconds(100))
            case .loaded(let c): return c
            }
        }
    }

    private func performLoad() async throws -> ModelContainer {
        loadState = .loading
        modelInfo = "Preparing…"; downloadProgress = 0.0
        Memory.cacheLimit = 20 * 1024 * 1024

        let hub = HubApi(
            downloadBase: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        do {
            let dir = try await downloadModel(hub: hub, configuration: modelConfiguration) {
                [weak self] p in Task { @MainActor in self?.updateProgress(p) }
            }
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            guard contents.contains(where: { $0.hasSuffix(".safetensors") }) else {
                throw NSError(domain: "CodingAgent", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Model download incomplete."])
            }
            modelInfo = "Loading weights…"; downloadProgress = nil; totalSize = nil

            let container = try await LLMModelFactory.shared.loadContainer(
                hub: hub, configuration: modelConfiguration) { _ in }

            let n = await container.perform { $0.model.numParameters() }
            let short = modelConfiguration.name.components(separatedBy: "/").last ?? modelConfiguration.name
            let pm = n / (1024 * 1024)
            modelInfo = "\(short) · \(pm >= 1000 ? String(format: "%.1fB", Double(pm)/1000) : "\(pm)M") params"
            loadState = .loaded(container)

            messages.append(AgentMessage(role: .assistant, content: """
                **\(short)** ready — running on-device via MLX.

                Open a workspace folder to start, or paste a build error and I'll fix it.
                """))
            return container
        } catch {
            loadState = .idle; downloadProgress = nil; totalSize = nil; throw error
        }
    }

    private func updateProgress(_ p: Progress) {
        let name = modelConfiguration.name.components(separatedBy: "/").last ?? modelConfiguration.name
        modelInfo = "Downloading \(name) (\(Int(p.fractionCompleted * 100))%)"
        downloadProgress = p.fractionCompleted
        if p.totalUnitCount > 0 && p.totalUnitCount < 100 {
            totalSize = "File \(p.completedUnitCount + 1) of \(p.totalUnitCount)"
        } else if p.totalUnitCount > 0 {
            let f = ByteCountFormatter(); f.allowedUnits = [.useMB, .useGB]; f.countStyle = .file
            totalSize = "\(f.string(fromByteCount: p.completedUnitCount)) of \(f.string(fromByteCount: p.totalUnitCount))"
        }
    }
}
