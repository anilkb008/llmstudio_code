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
                        if let url {
                            agent.setWorkspace(url)
                        }
                    }
                ),
                onFileSelected: { url in
                    agent.sendMessage("Read the file at: \(url.path)")
                }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        } detail: {
            // DETAIL: Chat + Input
            VStack(spacing: 0) {
                // Top toolbar
                agentToolbar

                Divider()

                // Conversation
                ConversationView(
                    messages: agent.messages,
                    isRunning: agent.running
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Input area
                AgentInputView(
                    inputText: $inputText,
                    isRunning: agent.running,
                    workspacePath: agent.workspacePath,
                    onSend: {
                        agent.sendMessage(inputText)
                        inputText = ""
                    },
                    onCancel: {
                        agent.cancelGeneration()
                    }
                )
            }
            .navigationTitle("")
            .toolbar {
                // Model info in toolbar center
                ToolbarItem(placement: .principal) {
                    modelStatusView
                }

                // Right toolbar items
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingLLMEval = true
                    } label: {
                        Label("LLM Eval", systemImage: "waveform")
                    }
                    .help("Open LLM Eval view")

                    Button {
                        showingClearConfirm = true
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .help("Clear conversation")
                    .disabled(agent.messages.isEmpty)
                }
            }
            .confirmationDialog(
                "Clear Conversation",
                isPresented: $showingClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear", role: .destructive) {
                    agent.clearConversation()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will erase all messages and start a new conversation.")
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
                        content: "⚠️ Failed to load model: \(error.localizedDescription)"
                    )
                )
            }
        }
    }

    // MARK: - Subviews

    private var agentToolbar: some View {
        HStack(spacing: 10) {
            // Agent branding
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "cpu")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                Text("Coding Agent")
                    .font(.headline)
            }

            Spacer()

            // Running indicator
            if agent.running {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var modelStatusView: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(agent.running ? Color.orange : Color.green)
                .frame(width: 7, height: 7)
            Text(agent.modelInfo.isEmpty ? "Loading…" : agent.modelInfo)
                .font(.caption)
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
