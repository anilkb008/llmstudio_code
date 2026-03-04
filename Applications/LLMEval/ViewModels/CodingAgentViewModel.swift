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

    // Session stats for the status bar
    var totalToolCalls = 0
    var totalTokensGenerated = 0

    // MARK: - Model Config

    var modelConfiguration = LLMRegistry.qwen3_8b_4bit

    var generateParameters: GenerateParameters {
        GenerateParameters(maxTokens: 8192, temperature: 0.5)
    }

    // MARK: - Private State

    private var loadState = LoadState.idle
    private var generationTask: Task<Void, Error>?
    private var toolExecutor: CodingToolExecutor
    private var llmHistory: [Chat.Message] = []

    // MARK: - System Prompt (Claude Code style)

    private static let systemPromptTemplate = """
        You are a highly skilled autonomous coding agent, similar to Claude Code. You have direct access to the file system and shell, and you help users complete software engineering tasks end-to-end.

        ## Core Behaviors

        1. **Be autonomous** — Don't ask clarifying questions when you can use tools to find the answer yourself. Explore the codebase, read files, and act.
        2. **Read before writing** — Always call `read_file` before modifying an existing file. Never assume you know the content.
        3. **Prefer `edit_file` over `write_file`** — For existing files, use `edit_file` with exact text replacement. Only use `write_file` to create brand-new files.
        4. **Verify your work** — After making code changes, run `run_shell_command` to build or test (e.g. `swift build`, `npm test`, `python -m pytest`).
        5. **Minimal changes** — Make the smallest change that solves the problem. Don't refactor unrelated code unless asked.
        6. **Explain briefly** — Before using a tool, say what you're about to do in one short sentence.

        ## Available Tools

        | Tool | When to use |
        |------|-------------|
        | `read_file` | Read file content. Use `start_line`/`end_line` for large files. |
        | `edit_file` | Replace exact text in a file. `old_string` must match exactly (whitespace included). |
        | `write_file` | Create a new file or completely overwrite (use sparingly on existing files). |
        | `run_shell_command` | Run bash: build, test, git, grep, find, ls, etc. |
        | `list_directory` | List directory contents. Good first step when exploring. |
        | `search_files` | grep across files. Find functions, usages, imports, etc. |
        | `create_directory` | Create a directory tree. |
        | `get_file_info` | File metadata: size, line count, modification date. |

        ## Workflow

        For any coding task:
        1. Explore first — `list_directory` or `search_files` to understand the codebase
        2. Read relevant files — understand context before changing anything
        3. Plan the change — think about what exactly needs to change
        4. Implement — use `edit_file` for precise edits, or `write_file` for new files
        5. Verify — build/test to confirm nothing broke
        6. Summarize — tell the user what you changed and why

        ## Session Context

        Workspace: {workspace}
        Platform: macOS
        Shell: /bin/sh
        """

    enum LoadState {
        case idle, loading, loaded(ModelContainer)
    }

    var isLoading: Bool {
        if case .loading = loadState { return true }
        return false
    }

    // MARK: - Init

    init() {
        self.toolExecutor = CodingToolExecutor(workspacePath: nil)
        resetHistory()
    }

    // MARK: - Workspace

    func setWorkspace(_ url: URL) {
        workspacePath = url
        toolExecutor.workspacePath = url
        resetHistory()

        // Auto-explore: immediately list the workspace like Claude Code does
        let notice = AgentMessage(
            role: .assistant,
            content: "Workspace: **\(url.path)**"
        )
        messages.append(notice)

        sendMessage("List the workspace directory and give me a brief overview of the project structure.")
    }

    private func resetHistory() {
        let ws = workspacePath?.path ?? "not set — user has not opened a folder yet"
        llmHistory = [.system(Self.systemPromptTemplate.replacingOccurrences(of: "{workspace}", with: ws))]
    }

    func clearConversation() {
        messages.removeAll()
        totalToolCalls = 0
        totalTokensGenerated = 0
        resetHistory()
    }

    // MARK: - Send Message

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !running else { return }

        let userMessage = AgentMessage(role: .user, content: trimmed)
        messages.append(userMessage)
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
            if messages[idx].content.isEmpty {
                messages[idx].content = "*[cancelled]*"
            }
        }
    }

    // MARK: - Agent Turn (agentic loop)

    private func runAgentTurn() async {
        do {
            let modelContainer = try await load()

            var assistantMessage = AgentMessage(role: .assistant, isStreaming: true)
            messages.append(assistantMessage)
            let assistantId = assistantMessage.id

            // Loop: generate → tool call → continue, until model gives final answer
            var continueLoop = true
            while continueLoop {
                if Task.isCancelled { break }
                continueLoop = await streamSegment(
                    modelContainer: modelContainer,
                    assistantMessageId: assistantId
                )
            }

            // Mark streaming complete
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                messages[idx].isStreaming = false
            }

        } catch {
            let errMsg = AgentMessage(
                role: .assistant,
                content: "⚠️ \(error.localizedDescription)"
            )
            messages.append(errMsg)
        }
    }

    /// Stream one generation segment. Returns `true` if a tool call was made (loop should continue).
    /// Each call adds its output to `llmHistory` before returning.
    private func streamSegment(modelContainer: ModelContainer, assistantMessageId: UUID) async -> Bool {
        let userInput = UserInput(
            chat: llmHistory,
            tools: toolExecutor.allToolSchemas,
            additionalContext: [:]
        )

        do {
            MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))
            let lmInput = try await modelContainer.prepare(input: userInput)
            let stream = try await modelContainer.generate(input: lmInput, parameters: generateParameters)

            var segmentText = ""
            var pendingToolCall: ToolCall?

            var iter = stream.makeAsyncIterator()
            while let token = await iter.next() {
                if Task.isCancelled { return false }

                if let toolCall = token.toolCall {
                    pendingToolCall = toolCall
                    break
                }
                if let chunk = token.chunk, !chunk.isEmpty {
                    segmentText += chunk
                    totalTokensGenerated += 1
                    // Append to the UI message (cumulative across all segments)
                    if let idx = messages.firstIndex(where: { $0.id == assistantMessageId }) {
                        messages[idx].content += chunk
                    }
                }
            }

            // Add this segment's text to LLM history
            if !segmentText.isEmpty {
                llmHistory.append(.assistant(segmentText))
            }

            // Handle tool call
            if let toolCall = pendingToolCall {
                await executeToolCall(toolCall, assistantMessageId: assistantMessageId)
                return true
            }
            return false

        } catch {
            if let idx = messages.firstIndex(where: { $0.id == assistantMessageId }) {
                messages[idx].content += "\n\n⚠️ \(error.localizedDescription)"
            }
            return false
        }
    }

    private func executeToolCall(_ toolCall: ToolCall, assistantMessageId: UUID) async {
        let name = toolCall.function.name
        let args = toolCall.function.arguments ?? "{}"

        totalToolCalls += 1

        // Show tool call in UI
        let record = AgentToolCall(name: name, arguments: args, isExecuting: true)
        if let idx = messages.firstIndex(where: { $0.id == assistantMessageId }) {
            messages[idx].toolCalls.append(record)
        }

        // Execute
        let result = await toolExecutor.execute(name: name, arguments: args)

        // Update UI with result
        if let msgIdx = messages.firstIndex(where: { $0.id == assistantMessageId }),
            let toolIdx = messages[msgIdx].toolCalls.firstIndex(where: { $0.id == record.id })
        {
            messages[msgIdx].toolCalls[toolIdx].result = result
            messages[msgIdx].toolCalls[toolIdx].isExecuting = false
        }

        // Add tool result to LLM context
        llmHistory.append(.tool(result))
    }

    // MARK: - Model Loading

    func load() async throws -> ModelContainer {
        while true {
            switch loadState {
            case .idle: return try await performLoad()
            case .loading: try await Task.sleep(for: .milliseconds(100))
            case .loaded(let c): return c
            }
        }
    }

    private func performLoad() async throws -> ModelContainer {
        loadState = .loading
        modelInfo = "Preparing…"
        downloadProgress = 0.0
        Memory.cacheLimit = 20 * 1024 * 1024

        let hub = HubApi(
            downloadBase: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)

        do {
            let modelDir = try await downloadModel(hub: hub, configuration: modelConfiguration) {
                [weak self] p in
                Task { @MainActor in self?.updateProgress(p) }
            }

            // Validate download
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: modelDir.path)) ?? []
            guard contents.contains(where: { $0.hasSuffix(".safetensors") }) else {
                throw NSError(domain: "CodingAgent", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Model download incomplete."])
            }

            modelInfo = "Loading weights…"
            downloadProgress = nil; totalSize = nil

            let container = try await LLMModelFactory.shared.loadContainer(
                hub: hub, configuration: modelConfiguration) { _ in }

            let n = await container.perform { $0.model.numParameters() }
            let shortName = modelConfiguration.name.components(separatedBy: "/").last ?? modelConfiguration.name
            let pm = n / (1024 * 1024)
            modelInfo = "\(shortName) · \(pm >= 1000 ? String(format: "%.1fB", Double(pm)/1000) : "\(pm)M") params"

            loadState = .loaded(container)

            messages.append(AgentMessage(
                role: .assistant,
                content: "**\(shortName)** ready. Open a workspace folder to start coding, or ask me anything."
            ))
            return container

        } catch {
            loadState = .idle; downloadProgress = nil; totalSize = nil
            throw error
        }
    }

    private func updateProgress(_ p: Progress) {
        let name = modelConfiguration.name.components(separatedBy: "/").last ?? modelConfiguration.name
        modelInfo = "Downloading \(name) (\(Int(p.fractionCompleted * 100))%)"
        downloadProgress = p.fractionCompleted
        if p.totalUnitCount > 0 && p.totalUnitCount < 100 {
            totalSize = "File \(p.completedUnitCount + 1) of \(p.totalUnitCount)"
        } else if p.totalUnitCount > 0 {
            let f = ByteCountFormatter()
            f.allowedUnits = [.useMB, .useGB]; f.countStyle = .file
            totalSize = "\(f.string(fromByteCount: p.completedUnitCount)) of \(f.string(fromByteCount: p.totalUnitCount))"
        }
    }
}
