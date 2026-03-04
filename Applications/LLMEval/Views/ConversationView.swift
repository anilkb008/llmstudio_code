// Copyright © 2025 Apple Inc.

import SwiftUI

struct ConversationView: View {
    let messages: [AgentMessage]
    let isRunning: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if messages.isEmpty {
                        WelcomePromptView()
                    } else {
                        ForEach(messages) { message in
                            if message.role != .system {
                                MessageBubbleView(message: message)
                                    .id(message.id)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                    }

                    // Scroll anchor at bottom
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .animation(.easeOut(duration: 0.2), value: messages.count)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: messages.last?.content.count) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: messages.last?.toolCalls.count) { _, _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Welcome View

struct WelcomePromptView: View {
    let suggestions = [
        ("Explore the codebase", "List the directory structure and summarize the project"),
        ("Find & fix a bug", "Search for a specific function and help debug it"),
        ("Add a new feature", "Implement a new capability with tests"),
        ("Run the tests", "Execute the test suite and analyze results"),
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 40)

            // Hero icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "cpu.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 8) {
                Text("Coding Agent")
                    .font(.largeTitle.bold())
                Text("Powered by a local LLM running on-device via MLX")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Suggestion chips
            VStack(alignment: .leading, spacing: 10) {
                Text("Try asking:")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ForEach(suggestions, id: \.0) { title, subtitle in
                    SuggestionCard(title: title, subtitle: subtitle)
                }
            }
            .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
    }
}

struct SuggestionCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.right.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
