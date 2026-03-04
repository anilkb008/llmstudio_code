// Copyright © 2025 Apple Inc.

import SwiftUI

struct ConversationView: View {
    let messages: [AgentMessage]
    let isRunning: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if messages.isEmpty {
                        WelcomeView()
                            .padding(.top, 60)
                    } else {
                        ForEach(messages) { message in
                            if message.role != .system {
                                MessageRow(message: message)
                                    .id(message.id)
                            }
                        }
                        // Anchor for auto-scroll
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: messages.last?.content.count) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: messages.last?.toolCalls.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }
}

// MARK: - Message Row (separator + bubble)

struct MessageRow: View {
    let message: AgentMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch message.role {
            case .user:
                // User messages: right-aligned bubble, full width row
                UserBubble(content: message.content)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

            case .assistant:
                // Assistant messages: left-aligned, no bubble background
                VStack(alignment: .leading, spacing: 6) {
                    // Small agent label
                    HStack(spacing: 5) {
                        Image(systemName: "cpu.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text("Agent")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                    }
                    AssistantBubble(message: message)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            case .system:
                EmptyView()
            }

            Divider()
                .padding(.horizontal, 20)
                .opacity(0.4)
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    let tips: [(icon: String, title: String, subtitle: String)] = [
        ("folder.fill.badge.plus", "Open a workspace",
         "Click the folder icon in the sidebar to open your project"),
        ("square.and.pencil", "Edit files precisely",
         "The agent uses targeted edits — showing diffs of every change"),
        ("terminal.fill", "Run shell commands",
         "Build, test, grep, git — any bash command works"),
        ("magnifyingglass", "Search your codebase",
         "Ask the agent to find functions, patterns, or TODOs"),
    ]

    var body: some View {
        VStack(spacing: 28) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 72, height: 72)
                Image(systemName: "cpu.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 6) {
                Text("Coding Agent")
                    .font(.system(size: 22, weight: .bold))
                Text("Local LLM · Full file system access · No internet required")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Tips grid
            VStack(alignment: .leading, spacing: 10) {
                ForEach(tips, id: \.title) { tip in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: tip.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tip.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(tip.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: 380)
            .padding(16)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.bottom, 40)
    }
}
