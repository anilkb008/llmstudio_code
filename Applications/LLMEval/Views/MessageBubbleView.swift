// Copyright © 2025 Apple Inc.

import MarkdownUI
import SwiftUI

// MARK: - Message Bubble (top-level dispatcher)

struct MessageBubbleView: View {
    let message: AgentMessage

    var body: some View {
        switch message.role {
        case .user:
            UserBubble(content: message.content)
        case .assistant:
            AssistantBubble(message: message)
        case .system:
            EmptyView()
        }
    }
}

// MARK: - User Bubble

struct UserBubble: View {
    let content: String

    var body: some View {
        HStack(alignment: .top) {
            Spacer(minLength: 80)
            VStack(alignment: .trailing, spacing: 4) {
                Text(content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

// MARK: - Assistant Bubble

struct AssistantBubble: View {
    let message: AgentMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main text content (markdown)
            if !message.content.isEmpty {
                Markdown(message.content)
                    .markdownTheme(.docC)
                    .textSelection(.enabled)
                    .padding(.bottom, message.toolCalls.isEmpty ? 0 : 10)
            }

            // Tool calls — shown inline in order they were made
            if !message.toolCalls.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(message.toolCalls) { tc in
                        ToolCallRow(toolCall: tc)
                    }
                }
            }

            // Streaming cursor
            if message.isStreaming {
                StreamingCursor(hasContent: !message.content.isEmpty || !message.toolCalls.isEmpty)
                    .padding(.top, 6)
            }
        }
    }
}

// MARK: - Tool Call Row (Claude Code style)

struct ToolCallRow: View {
    let toolCall: AgentToolCall
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header row (always visible) ─────────────────────────────
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    // Status dot / spinner
                    if toolCall.isExecuting {
                        ProgressView().controlSize(.mini).frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                    }

                    // Tool icon
                    Image(systemName: toolCall.icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(toolCallColor)
                        .frame(width: 14)

                    // Tool name + key argument summary
                    Text(toolCall.displayName)
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundStyle(.primary)

                    Text(summaryText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    // Expand chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)

            // ── Expandable body ──────────────────────────────────────────
            if isExpanded {
                Divider().padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 8) {
                    // Arguments section
                    if let pretty = prettyArgs {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("Input", systemImage: "arrow.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            TerminalText(pretty)
                        }
                    }

                    // Result section
                    if let result = toolCall.result {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("Output", systemImage: "arrow.left")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            switch toolCall.name {
                            case "edit_file":
                                DiffView(content: result)
                            case "run_shell_command", "run_tests":
                                DiagnosticOutputView(content: result)
                            default:
                                TerminalText(result, maxLines: 30)
                            }
                        }
                    } else if toolCall.isExecuting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Running…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(toolCallColor.opacity(isExpanded ? 0.35 : 0.15), lineWidth: 1)
        )
    }

    // MARK: - Computed

    private var toolCallColor: Color {
        switch toolCall.name {
        case "run_shell_command": return .orange
        case "run_tests":         return .green
        case "edit_file":         return .purple
        case "write_file":        return .blue
        case "read_file":         return .teal
        case "search_files":      return .yellow
        case "list_directory":    return .indigo
        default:                  return .secondary
        }
    }

    private var summaryText: String {
        guard let data = toolCall.arguments.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "" }
        if let path = obj["path"] as? String { return path }
        if let cmd  = obj["command"] as? String { return String(cmd.prefix(60)) }
        if let pat  = obj["pattern"] as? String { return "'\(pat)'" }
        if let tgt  = obj["test_target"] as? String { return tgt }
        return ""
    }

    private var prettyArgs: String? {
        guard let data = toolCall.arguments.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
            let str = String(data: pretty, encoding: .utf8)
        else { return nil }
        // For edit_file, shorten long old/new strings
        return str.count > 1000 ? String(str.prefix(1000)) + "\n…" : str
    }
}

// MARK: - Terminal-style text view

struct TerminalText: View {
    let content: String
    let maxLines: Int

    init(_ content: String, maxLines: Int = 50) {
        self.content = content
        self.maxLines = maxLines
    }

    var displayContent: String {
        let lines = content.components(separatedBy: "\n")
        if lines.count > maxLines {
            let shown = lines.prefix(maxLines).joined(separator: "\n")
            return shown + "\n… (\(lines.count - maxLines) more lines)"
        }
        return content
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(displayContent)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color.black.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Diff View (for edit_file results)

struct DiffView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines, id: \.offset) { item in
                HStack(spacing: 0) {
                    // Color band
                    Rectangle()
                        .fill(item.color)
                        .frame(width: 3)
                    Text(item.text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(item.textColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(item.background)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .textSelection(.enabled)
    }

    struct DiffLine {
        let offset: Int
        let text: String
        var color: Color
        var textColor: Color
        var background: Color
    }

    var lines: [DiffLine] {
        content.components(separatedBy: "\n").enumerated().map { i, line in
            if line.hasPrefix("- ") {
                return DiffLine(offset: i, text: line, color: .red,
                    textColor: .red, background: .red.opacity(0.08))
            } else if line.hasPrefix("+ ") {
                return DiffLine(offset: i, text: line, color: .green,
                    textColor: .green, background: .green.opacity(0.08))
            } else {
                return DiffLine(offset: i, text: line, color: .clear,
                    textColor: .secondary, background: .clear)
            }
        }
    }
}

// MARK: - Diagnostic Output View (shell / test output with error highlighting)

struct DiagnosticOutputView: View {
    let content: String

    private enum LineKind { case error, warning, note, passed, failed, normal }

    private struct DiagLine: Identifiable {
        let id: Int
        let text: String
        let kind: LineKind
    }

    private static let errorPattern   = try? NSRegularExpression(pattern: #"(?i)(error:|✗|FAIL|FAILED|fatal error|Assertion failed|assert|Exception|Traceback|SyntaxError|TypeError|NameError|KeyError|AttributeError|ModuleNotFoundError|\[exit [^0])"#)
    private static let warningPattern = try? NSRegularExpression(pattern: #"(?i)(warning:|WARN|deprecated)"#)
    private static let notePattern    = try? NSRegularExpression(pattern: #"(?i)(note:|hint:)"#)
    private static let passPattern    = try? NSRegularExpression(pattern: #"(?i)(passed|✓|✔|OK|Test Suite .+ passed|All tests passed|BUILD SUCCEEDED)"#)

    private func classify(_ line: String) -> LineKind {
        let r = NSRange(line.startIndex..., in: line)
        if Self.errorPattern?.firstMatch(in: line, range: r)   != nil { return .error }
        if Self.warningPattern?.firstMatch(in: line, range: r) != nil { return .warning }
        if Self.notePattern?.firstMatch(in: line, range: r)    != nil { return .note }
        if Self.passPattern?.firstMatch(in: line, range: r)    != nil { return .passed }
        return .normal
    }

    private var lines: [DiagLine] {
        let rawLines = content.components(separatedBy: "\n")
        let max = 120
        let shown = rawLines.count > max ? Array(rawLines.prefix(max)) : rawLines
        return shown.enumerated().map { i, l in DiagLine(id: i, text: l, kind: classify(l)) }
    }

    var body: some View {
        ScrollView([.vertical, .horizontal], showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    HStack(spacing: 0) {
                        // Color band
                        Rectangle()
                            .fill(bandColor(line.kind))
                            .frame(width: 3)
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(textColor(line.kind))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 0.5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(bgColor(line.kind))
                    }
                }
                if content.components(separatedBy: "\n").count > 120 {
                    Text("… (\(content.components(separatedBy: "\n").count - 120) more lines)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 9)
                }
            }
        }
        .frame(maxHeight: 320)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .textSelection(.enabled)
    }

    private func bandColor(_ k: LineKind) -> Color {
        switch k {
        case .error:   return .red
        case .warning: return .yellow
        case .note:    return .blue
        case .passed:  return .green
        case .failed:  return .red
        case .normal:  return .clear
        }
    }
    private func textColor(_ k: LineKind) -> Color {
        switch k {
        case .error:   return .red
        case .warning: return Color(red: 0.9, green: 0.7, blue: 0)
        case .note:    return .blue
        case .passed:  return .green
        case .failed:  return .red
        case .normal:  return .primary
        }
    }
    private func bgColor(_ k: LineKind) -> Color {
        switch k {
        case .error:   return .red.opacity(0.07)
        case .warning: return .yellow.opacity(0.05)
        case .note:    return .blue.opacity(0.05)
        case .passed:  return .green.opacity(0.05)
        case .failed:  return .red.opacity(0.07)
        case .normal:  return .clear
        }
    }
}

// MARK: - Streaming Cursor

struct StreamingCursor: View {
    let hasContent: Bool
    @State private var visible = true

    var body: some View {
        HStack(spacing: 6) {
            if !hasContent {
                Image(systemName: "cpu")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Thinking")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            // Blinking cursor
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2, height: 14)
                .opacity(visible ? 1 : 0)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: visible)
                .onAppear { visible = false }
        }
    }
}
