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

    // MARK: - Model Config

    var modelConfiguration = LLMRegistry.qwen3_8b_4bit

    var generateParameters: GenerateParameters {
        GenerateParameters(maxTokens: 4096, temperature: 0.6)
    }

    // MARK: - Private State

    private var loadState = LoadState.idle
    private var generationTask: Task<Void, Error>?
    private var toolExecutor: CodingToolExecutor
    private var llmHistory: [Chat.Message] = []

    private static let systemPromptTemplate = """
        You are a highly capable coding agent, similar to Claude Code. You help users with software engineering tasks by reading, writing, and modifying files, running shell commands, searching code, and providing expert analysis.

        You have access to these tools:
        - read_file: Read file contents (always read before modifying!)
        - write_file: Create or overwrite files
        - list_directory: Explore directory structure
        - run_shell_command: Execute shell commands (build, test, git, etc.)
        - search_files: Search for patterns across files
        - create_directory: Create directories
        - get_file_info: Get file metadata

        Guidelines:
        1. Always read existing files before modifying them
        2. Make targeted, minimal changes that solve the problem
        3. Run tests or builds after making changes when appropriate
        4. Explain what you're doing and why at each step
        5. If a tool call fails, try an alternative approach
        6. For complex tasks, break them into smaller steps

        WORKSPACE: {workspace}
        """

    enum LoadState {
        case idle
        case loading
        case loaded(ModelContainer)
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
        let notice = AgentMessage(
            role: .assistant,
            content: "Workspace set to `\(url.lastPathComponent)`. I can now read and write files in this directory. What would you like to work on?"
        )
        messages.append(notice)
    }

    private func resetHistory() {
        let workspace = workspacePath?.path ?? "No workspace selected — ask user to open a folder"
        let systemPrompt = Self.systemPromptTemplate.replacingOccurrences(of: "{workspace}", with: workspace)
        llmHistory = [.system(systemPrompt)]
    }

    func clearConversation() {
        messages.removeAll()
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
            messages[idx].content += "\n\n*[Generation cancelled]*"
        }
    }

    // MARK: - Agent Turn

    private func runAgentTurn() async {
        do {
            let modelContainer = try await load()
            var assistantMessage = AgentMessage(role: .assistant, isStreaming: true)
            messages.append(assistantMessage)
            let assistantId = assistantMessage.id

            // Agentic loop: generate → tool call → continue until no more tool calls
            var continueLoop = true
            while continueLoop {
                continueLoop = await streamResponse(
                    modelContainer: modelContainer,
                    assistantMessageId: assistantId
                )
            }

            // Mark streaming done
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                messages[idx].isStreaming = false
                // Append final assistant text to LLM history
                let finalText = messages[idx].content
                if !finalText.isEmpty {
                    llmHistory.append(.assistant(finalText))
                }
            }

        } catch {
            let errorMsg = AgentMessage(
                role: .assistant,
                content: "⚠️ Error: \(error.localizedDescription)"
            )
            messages.append(errorMsg)
        }
    }

    /// Streams tokens into the assistant message. Returns `true` if a tool call was made
    /// (meaning caller should loop again), `false` when done.
    private func streamResponse(modelContainer: ModelContainer, assistantMessageId: UUID) async -> Bool {
        let userInput = UserInput(
            chat: llmHistory,
            tools: toolExecutor.allToolSchemas,
            additionalContext: [:]
        )

        do {
            MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))
            let lmInput = try await modelContainer.prepare(input: userInput)
            let stream = try await modelContainer.generate(
                input: lmInput, parameters: generateParameters)

            var accumulatedText = ""
            var pendingToolCall: ToolCall?

            var iterator = stream.makeAsyncIterator()
            while let token = await iterator.next() {
                if Task.isCancelled { return false }

                if let toolCall = token.toolCall {
                    pendingToolCall = toolCall
                    break
                }
                if let chunk = token.chunk, !chunk.isEmpty {
                    accumulatedText += chunk
                    if let idx = messages.firstIndex(where: { $0.id == assistantMessageId }) {
                        messages[idx].content = accumulatedText
                    }
                }
            }

            if let toolCall = pendingToolCall {
                await handleToolCall(toolCall, assistantMessageId: assistantMessageId)
                return true  // loop again after tool call
            }
            return false  // no tool call, done

        } catch {
            if let idx = messages.firstIndex(where: { $0.id == assistantMessageId }) {
                messages[idx].content += "\n\n⚠️ Generation error: \(error.localizedDescription)"
            }
            return false
        }
    }

    private func handleToolCall(_ toolCall: ToolCall, assistantMessageId: UUID) async {
        let toolName = toolCall.function.name
        let toolArgs = toolCall.function.arguments ?? "{}"

        // Add tool call record to the assistant message in UI
        var toolCallRecord = AgentToolCall(
            name: toolName,
            arguments: toolArgs,
            isExecuting: true
        )

        if let idx = messages.firstIndex(where: { $0.id == assistantMessageId }) {
            messages[idx].toolCalls.append(toolCallRecord)
        }

        // Execute the tool
        let result = await toolExecutor.execute(name: toolName, arguments: toolArgs)

        // Update tool call record with result
        if let msgIdx = messages.firstIndex(where: { $0.id == assistantMessageId }),
            let toolIdx = messages[msgIdx].toolCalls.firstIndex(where: { $0.id == toolCallRecord.id })
        {
            messages[msgIdx].toolCalls[toolIdx].result = result
            messages[msgIdx].toolCalls[toolIdx].isExecuting = false
        }

        // Add tool result to LLM history so model can continue with context
        llmHistory.append(.tool(result))
    }

    // MARK: - Model Loading

    func load() async throws -> ModelContainer {
        while true {
            switch loadState {
            case .idle:
                return try await performLoad()
            case .loading:
                try await Task.sleep(for: .milliseconds(100))
            case .loaded(let container):
                return container
            }
        }
    }

    private func performLoad() async throws -> ModelContainer {
        loadState = .loading
        modelInfo = "Preparing model..."
        downloadProgress = 0.0

        Memory.cacheLimit = 20 * 1024 * 1024

        let hub = HubApi(
            downloadBase: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        )

        do {
            let modelDirectory = try await downloadModel(
                hub: hub,
                configuration: modelConfiguration
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.updateDownloadProgress(progress)
                }
            }

            let fileManager = FileManager.default
            let contents = (try? fileManager.contentsOfDirectory(atPath: modelDirectory.path)) ?? []
            guard fileManager.fileExists(atPath: modelDirectory.path),
                contents.contains(where: { $0.hasSuffix(".safetensors") })
            else {
                throw NSError(
                    domain: "CodingAgent", code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Model download failed. Check network connection."
                    ])
            }

            modelInfo = "Loading model into memory..."
            downloadProgress = nil
            totalSize = nil

            let modelContainer = try await LLMModelFactory.shared.loadContainer(
                hub: hub,
                configuration: modelConfiguration
            ) { _ in }

            let numParams = await modelContainer.perform { $0.model.numParameters() }
            let shortName =
                modelConfiguration.name.components(separatedBy: "/").last
                ?? modelConfiguration.name
            let paramM = numParams / (1024 * 1024)
            let paramStr =
                paramM >= 1000
                ? String(format: "%.1fB params", Double(paramM) / 1000.0) : "\(paramM)M params"
            modelInfo = "\(shortName) · \(paramStr)"

            loadState = .loaded(modelContainer)

            // Welcome message once model is ready
            let welcome = AgentMessage(
                role: .assistant,
                content: "Model ready! I'm your coding agent powered by **\(shortName)**.\n\nOpen a workspace folder to get started, then describe what you'd like to build or fix."
            )
            messages.append(welcome)

            return modelContainer

        } catch {
            loadState = .idle
            downloadProgress = nil
            totalSize = nil
            throw error
        }
    }

    private func updateDownloadProgress(_ progress: Progress) {
        let name =
            modelConfiguration.name.components(separatedBy: "/").last ?? modelConfiguration.name
        modelInfo = "Downloading \(name) (\(Int(progress.fractionCompleted * 100))%)"
        downloadProgress = progress.fractionCompleted

        if progress.totalUnitCount > 0 && progress.totalUnitCount < 100 {
            totalSize = "File \(progress.completedUnitCount + 1) of \(progress.totalUnitCount)"
        } else if progress.totalUnitCount > 0 {
            let fmt = ByteCountFormatter()
            fmt.allowedUnits = [.useMB, .useGB]
            fmt.countStyle = .file
            totalSize =
                "\(fmt.string(fromByteCount: progress.completedUnitCount)) of \(fmt.string(fromByteCount: progress.totalUnitCount))"
        }
    }

    // MARK: - File Explorer

    func loadFileTree(from url: URL) -> [FileEntry] {
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
            return FileEntry(
                name: fileURL.lastPathComponent,
                url: fileURL,
                isDirectory: isDir
            )
        }
    }
}
