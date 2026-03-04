// Copyright © 2025 Apple Inc.

import SwiftUI

struct AgentInputView: View {
    @Binding var inputText: String
    let isRunning: Bool
    let workspacePath: URL?
    var onSend: () -> Void
    var onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            // Workspace indicator
            if let workspace = workspacePath {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.blue)
                    Text(workspace.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            // Input row
            HStack(alignment: .bottom, spacing: 10) {
                // Text editor
                ZStack(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("Ask me to read files, fix bugs, write code…")
                            .foregroundStyle(.tertiary)
                            .font(.body)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $inputText)
                        .focused($isFocused)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 38, maxHeight: 160)
                        .fixedSize(horizontal: false, vertical: true)
                        .onKeyPress(.return, phases: .down) { press in
                            if press.modifiers.contains(.command) {
                                sendIfPossible()
                                return .handled
                            }
                            return .ignored
                        }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Send / Stop button
                Button {
                    if isRunning {
                        onCancel()
                    } else {
                        sendIfPossible()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(isRunning ? Color.red : Color.accentColor)
                            .frame(width: 36, height: 36)
                        Image(systemName: isRunning ? "stop.fill" : "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!isRunning && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(isRunning ? "Stop generation (⌘.)" : "Send message (⌘↩)")
                .keyboardShortcut(".", modifiers: .command)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(.bar)
        .onAppear { isFocused = true }
    }

    private func sendIfPossible() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }
        onSend()
        inputText = ""
    }
}
