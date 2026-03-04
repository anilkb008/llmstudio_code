// Copyright © 2025 Apple Inc.

import SwiftUI

struct AgentInputView: View {
    @Binding var inputText: String
    let isRunning: Bool
    let workspacePath: URL?
    var onSend: () -> Void
    var onCancel: () -> Void

    @FocusState private var focused: Bool
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: 8) {
                // Workspace breadcrumb
                if let ws = workspacePath {
                    HStack(spacing: 5) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(ws.lastPathComponent)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("›")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 11))
                        Spacer()
                    }
                }

                // Input row
                HStack(alignment: .bottom, spacing: 10) {
                    // Expandable text editor
                    ZStack(alignment: .topLeading) {
                        if inputText.isEmpty && !focused {
                            Text(placeholderText)
                                .foregroundStyle(.tertiary)
                                .font(.system(size: 13))
                                .padding(.top, 7)
                                .padding(.leading, 3)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $inputText)
                            .focused($focused)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 32, maxHeight: 180)
                            .fixedSize(horizontal: false, vertical: true)
                            .onKeyPress(.return, phases: .down) { press in
                                guard press.modifiers.contains(.command) else { return .ignored }
                                submitIfPossible()
                                return .handled
                            }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.secondary.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(
                                        focused ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.15),
                                        lineWidth: 1)
                            )
                    )
                    .animation(.easeInOut(duration: 0.15), value: focused)

                    // Send / Stop button
                    Button {
                        if isRunning { onCancel() } else { submitIfPossible() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(buttonColor)
                                .frame(width: 34, height: 34)
                            Image(systemName: isRunning ? "stop.fill" : "arrow.up")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!isRunning && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(".", modifiers: .command)
                    .help(isRunning ? "Stop (⌘.)" : "Send (⌘↩)")
                    .animation(.easeInOut(duration: 0.1), value: isRunning)
                }

                // Hint row
                HStack {
                    Text(isRunning ? "Generating… ⌘. to stop" : "⌘↩ to send")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .onAppear { focused = true }
    }

    private var buttonColor: Color {
        if isRunning { return .red }
        let empty = inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return empty ? Color.secondary.opacity(0.3) : Color.accentColor
    }

    private var placeholderText: String {
        if workspacePath == nil { return "Open a workspace folder, then ask me to read files, fix bugs, write code…" }
        return "Ask me to read files, fix bugs, add features, run tests…"
    }

    private func submitIfPossible() {
        let t = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !isRunning else { return }
        onSend()
        inputText = ""
    }
}
