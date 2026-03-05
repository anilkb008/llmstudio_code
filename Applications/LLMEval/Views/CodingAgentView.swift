// Copyright © 2025 Apple Inc.

import SwiftUI

struct CodingAgentView: View {
    @State private var agent = CodingAgentViewModel()
    @State private var inputText = ""
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showingClearConfirm = false
    @State private var showingLLMEval = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // SIDEBAR: File Explorer
            FileExplorerView(
                workspacePath: Binding(
                    get: { agent.workspacePath },
                    set: { url in
                        if let url { agent.setWorkspace(url) }
                    }
                ),
                onFileSelected: { url in
                    agent.sendMessage("Read the file `\(url.lastPathComponent)` at path: \(url.path)")
                }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            VStack(spacing: 0) {
                // Top bar
                topBar

                Divider()

                // Conversation
                ConversationView(messages: agent.messages, isRunning: agent.running)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Input
                AgentInputView(
                    inputText: $inputText,
                    isRunning: agent.running,
                    workspacePath: agent.workspacePath,
                    onSend: { agent.sendMessage(inputText); inputText = "" },
                    onCancel: { agent.cancelGeneration() }
                )
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    modelPill
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingLLMEval = true
                    } label: {
                        Label("LLM Eval", systemImage: "waveform")
                    }
                    .help("Open LLM Eval (single prompt mode)")

                    Button {
                        showingClearConfirm = true
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                    .help("Start a new conversation")
                    .disabled(agent.messages.isEmpty)
                }
            }
            .confirmationDialog(
                "Start New Chat?",
                isPresented: $showingClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear & Start New", role: .destructive) { agent.clearConversation() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will erase all messages and reset the conversation.")
            }
            .sheet(isPresented: $showingLLMEval) {
                NavigationStack {
                    ContentView()
                        .environment(DeviceStat())
                        .navigationTitle("LLM Eval")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { showingLLMEval = false }
                            }
                        }
                }
                .frame(minWidth: 700, minHeight: 500)
            }
        }
        .overlay {
            if agent.isLoading {
                AgentLoadingOverlay(
                    modelInfo: agent.modelInfo,
                    downloadProgress: agent.downloadProgress,
                    progressDescription: agent.totalSize
                )
            }
        }
        .task {
            do {
                _ = try await agent.load()
            } catch {
                agent.messages.append(
                    AgentMessage(
                        role: .assistant,
                        content: "⚠️ Failed to load model: \(error.localizedDescription)\n\nCheck your internet connection and try restarting the app."
                    ))
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            // Branding
            HStack(spacing: 7) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Coding Agent")
                    .font(.system(size: 14, weight: .semibold))
            }

            Divider().frame(height: 16)

            // Workspace chip
            if let ws = agent.workspacePath {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)
                    Text(ws.lastPathComponent)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.08), in: Capsule())
            }

            Spacer()

            // Session stats
            if agent.totalToolCalls > 0 {
                statsChip(
                    icon: "wrench.and.screwdriver",
                    label: "\(agent.totalToolCalls) tool\(agent.totalToolCalls == 1 ? "" : "s")"
                )
            }
            if agent.totalTokensGenerated > 0 {
                statsChip(
                    icon: "text.word.spacing",
                    label: "\(agent.totalTokensGenerated) tokens"
                )
            }

            // Running indicator
            if agent.running {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("Working…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private func statsChip(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label)
                .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.08), in: Capsule())
    }

    private var modelPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(agent.running ? Color.orange : Color.green)
                .frame(width: 6, height: 6)
            Text(agent.modelInfo.isEmpty ? "Loading model…" : agent.modelInfo)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Loading Overlay

struct AgentLoadingOverlay: View {
    let modelInfo: String
    let downloadProgress: Double?
    let progressDescription: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                        .frame(width: 80, height: 80)
                    if downloadProgress != nil {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.blue)
                    } else {
                        ProgressView()
                            .controlSize(.large)
                    }
                }

                VStack(spacing: 8) {
                    Text(modelInfo)
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    if let desc = progressDescription {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let progress = downloadProgress {
                        ProgressView(value: progress)
                            .frame(width: 240)
                    }
                }
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 20)
        }
    }
}
