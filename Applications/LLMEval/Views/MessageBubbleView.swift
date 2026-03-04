// Copyright © 2025 Apple Inc.

import MarkdownUI
import SwiftUI

// MARK: - Message Bubble

struct MessageBubbleView: View {
    let message: AgentMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch message.role {
            case .user:
                UserMessageView(content: message.content)
            case .assistant:
                AssistantMessageView(message: message)
            case .system:
                EmptyView()
            }
        }
    }
}

// MARK: - User Message

struct UserMessageView: View {
    let content: String

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            Text(content)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Assistant Message

struct AssistantMessageView: View {
    let message: AgentMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Agent avatar
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "cpu")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                // Main content (markdown rendered)
                if !message.content.isEmpty {
                    Markdown(message.content)
                        .markdownTheme(.docC)
                        .textSelection(.enabled)
                }

                // Streaming indicator
                if message.isStreaming && message.content.isEmpty && message.toolCalls.isEmpty {
                    ThinkingIndicator()
                }

                // Tool calls
                ForEach(message.toolCalls) { toolCall in
                    ToolCallView(toolCall: toolCall)
                }

                // Streaming dots (while still generating after text)
                if message.isStreaming && !message.content.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(Color.secondary.opacity(0.5))
                                .frame(width: 5, height: 5)
                                .modifier(PulseModifier(delay: Double(i) * 0.15))
                        }
                    }
                }
            }

            Spacer(minLength: 20)
        }
    }
}

// MARK: - Tool Call View

struct ToolCallView: View {
    let toolCall: AgentToolCall
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    if toolCall.isExecuting {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: toolCall.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(toolCall.statusColor)
                    }

                    Text(toolCall.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    if toolCall.isExecuting {
                        Text("Running…")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if toolCall.result != nil {
                        Text("Done")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            // Expandable details
            if isExpanded {
                Divider()

                // Arguments
                VStack(alignment: .leading, spacing: 4) {
                    Text("Arguments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)

                    Text(formatJSON(toolCall.arguments))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

                // Result
                if let result = toolCall.result {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Result")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)

                        ScrollView {
                            Text(result)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func formatJSON(_ jsonString: String) -> String {
        guard let data = jsonString.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
            let str = String(data: pretty, encoding: .utf8)
        else {
            return jsonString
        }
        return str
    }
}

// MARK: - Thinking Indicator

struct ThinkingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "cpu")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Thinking…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 5, height: 5)
                        .modifier(PulseModifier(delay: Double(i) * 0.15))
                }
            }
        }
    }
}

// MARK: - Pulse Animation Modifier

struct PulseModifier: ViewModifier {
    let delay: Double
    @State private var opacity: Double = 0.3

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(delay)
                ) {
                    opacity = 1.0
                }
            }
    }
}
