# LLMEval — On-Device Coding Agent

A macOS coding agent powered entirely by a local large language model running via [MLX](https://github.com/ml-explore/mlx-swift). No network calls, no API keys — all inference happens on Apple Silicon using the Neural Engine and GPU.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Component Map](#component-map)
3. [The Agentic Loop — Deep Dive](#the-agentic-loop--deep-dive)
4. [Project Auto-Detection](#project-auto-detection)
5. [System Prompt Design](#system-prompt-design)
6. [Error Analysis Workflow](#error-analysis-workflow)
7. [UI Architecture](#ui-architecture)
8. [Data Flow Diagram](#data-flow-diagram)
9. [Tools Reference](#tools-reference)
10. [Model & Inference](#model--inference)
11. [File Structure](#file-structure)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        macOS App (SwiftUI)                       │
│                                                                   │
│  ┌─────────────────┐    ┌──────────────────────────────────────┐ │
│  │  CodingAgentView│    │       CodingAgentViewModel           │ │
│  │   (UI layer)    │◄──►│  (@Observable, @MainActor)           │ │
│  │                 │    │                                       │ │
│  │  MessageBubble  │    │  ┌─────────────────────────────────┐ │ │
│  │  FileExplorer   │    │  │       Agentic Loop              │ │ │
│  │  DiagnosticView │    │  │  sendMessage()                  │ │ │
│  └─────────────────┘    │  │    └─► runAgentTurn()           │ │ │
│                          │  │          └─► streamSegment()    │ │ │
│                          │  │                └─► doToolCall() │ │ │
│                          │  │                    └─► [loop]   │ │ │
│                          │  └─────────────────────────────────┘ │ │
│                          │                                       │ │
│                          │  llmHistory: [Chat.Message]           │ │
│                          │  (system + user + assistant + tool)   │ │
│                          └──────────────────────────────────────┘ │
│                                    │                              │
│                          ┌─────────▼────────────────────────────┐ │
│                          │        MLX LLM Stack                  │ │
│                          │  ModelContainer (Qwen3-8B 4-bit)      │ │
│                          │  LLMModelFactory  · Hub download      │ │
│                          └─────────┬────────────────────────────┘ │
│                                    │                              │
│                          ┌─────────▼────────────────────────────┐ │
│                          │      CodingToolExecutor               │ │
│                          │  9 tools · project detection          │ │
│                          │  file I/O · shell execution           │ │
│                          └───────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## Component Map

| File | Layer | Responsibility |
|------|-------|----------------|
| `ViewModels/CodingAgentViewModel.swift` | ViewModel | Agentic loop, LLM loading, message history, workspace management |
| `Services/CodingToolExecutor.swift` | Service | All 9 tool implementations, project detection, shell execution |
| `Models/AgentModels.swift` | Model | `AgentMessage`, `AgentToolCall`, `FileEntry` data types |
| `Views/CodingAgentView.swift` | View | Root layout: sidebar + chat + file explorer |
| `Views/MessageBubbleView.swift` | View | Chat bubbles, tool call cards, diff view, diagnostic output |
| `Views/FileExplorerView.swift` | View | Sidebar file tree |
| `Views/AgentInputView.swift` | View | Text input bar + send/cancel controls |

---

## The Agentic Loop — Deep Dive

The agentic loop is the engine that drives autonomous behaviour. It allows the model to take multiple actions — reading files, running commands, editing code — in a single response, without waiting for user input between steps.

### Entry Point: `sendMessage()`

```
User types message
        │
        ▼
CodingAgentViewModel.sendMessage(text)
  1. Append user message to messages[]     (UI display)
  2. Append .user(text) to llmHistory[]    (LLM context window)
  3. Spawn Task { running = true; await runAgentTurn() }
```

### Core Loop: `runAgentTurn()` + `streamSegment()`

```
runAgentTurn()
  │
  ├─ await load()   ← ensures model is loaded (downloads if needed)
  │
  ├─ Create new AgentMessage(isStreaming: true) in messages[]
  │
  └─ while loop {
       if Task.isCancelled → break
       loop = await streamSegment(container, msgId)
              ┌── returns true  → a tool was called, run the loop again
              └── returns false → no tool call, response is complete
     }
```

### What `streamSegment()` Does (Step by Step)

```
streamSegment()
  │
  ├─ 1. Build UserInput:
  │       chat:  llmHistory          ← full conversation history
  │       tools: allToolSchemas      ← 9 JSON tool definitions
  │
  ├─ 2. container.prepare(input)     ← tokenise + format prompt for the model
  │
  ├─ 3. container.generate(input)    ← begin streaming tokens from the LLM
  │
  ├─ 4. Consume async token stream:
  │       ┌─ token.chunk != nil     → append text to message (live streaming UI)
  │       └─ token.toolCall != nil  → capture tool call, break the stream
  │
  ├─ 5. If text was generated:
  │       llmHistory.append(.assistant(segText))    ← persist to history
  │
  ├─ 6a. If tool call found:
  │       await doToolCall(tc, msgId)   ← execute the tool (see below)
  │       return true                   ← signal: loop should continue
  │
  └─ 6b. No tool call:
          return false                  ← signal: response is complete
```

### Tool Call Execution: `doToolCall()`

```
doToolCall(toolCall, msgId)
  │
  ├─ 1. Decode tc.function.name  (e.g. "edit_file")
  │      Decode tc.function.arguments as JSON string
  │
  ├─ 2. Create AgentToolCall(isExecuting: true)
  │      Append to messages[msgId].toolCalls  → shows spinner in UI
  │
  ├─ 3. await toolExecutor.execute(name, arguments)
  │           │
  │           └─ switch name {
  │                "read_file"       → executeReadFile()
  │                "edit_file"       → executeEditFile()
  │                "write_file"      → executeWriteFile()
  │                "list_directory"  → executeListDirectory()
  │                "run_shell_command" → executeRunShell()
  │                "run_tests"       → executeRunTests()
  │                "search_files"    → executeSearchFiles()
  │                "create_directory"→ executeCreateDirectory()
  │                "get_file_info"   → executeGetFileInfo()
  │              }
  │              Returns: formatted String result
  │
  ├─ 4. Update AgentToolCall.result = output
  │      Set AgentToolCall.isExecuting = false  → UI shows result
  │
  └─ 5. llmHistory.append(.tool(result))  ← feed tool result back to LLM
```

### Why the Loop Continues

After a tool executes, its result is appended to `llmHistory` and `streamSegment()` is called again. The LLM receives the complete conversation including the tool result, and decides the next action:

```
[system]       You are an autonomous coding agent…
[user]         Fix the build error
[assistant]    Let me run the build first.
[tool_call]    run_shell_command { "command": "swift build 2>&1" }
[tool_result]  Sources/Foo/Bar.swift:42:5: error: cannot find 'bar'
[assistant]    ← LLM generates next response: read the file, then fix it
```

This continues until the model produces a response with **no tool call** — meaning it considers the task complete.

### Loop Termination Conditions

| Condition | What Happens |
|-----------|--------------|
| Model emits text without a tool call | `streamSegment()` returns `false`, loop exits normally |
| User presses Stop | `Task.isCancelled` is true, loop exits immediately |
| Model hits `maxTokens` (8192) | Generation ends, stream closes, loop exits |
| Tool throws an error | Error is appended to message content, loop exits |

### Cancellation

```swift
func cancelGeneration() {
    generationTask?.cancel()     // Swift structured concurrency cancellation
    running = false
    // Last message is marked not-streaming
}
```

The `streamSegment()` function checks `Task.isCancelled` before processing each token and at the top of each loop iteration, so cancellation is near-instant.

---

## Project Auto-Detection

When a workspace folder is opened via `setWorkspace(url)`, `detectProject()` checks for well-known marker files in the workspace root to determine the project type:

```
workspace/
  Package.swift      → Swift Package  { swift build, swift test, swift run }
  *.xcodeproj        → Xcode Project  { xcodebuild -scheme X build/test }
  Cargo.toml         → Rust           { cargo build, cargo test, cargo run }
  go.mod             → Go             { go build ./..., go test ./... }
  package.json       → Node.js        { npm/yarn build, npm/yarn test }
  pyproject.toml     → Python         { pytest -v }
  setup.py           → Python         { pytest -v }
  requirements.txt   → Python         { pytest -v }
  Makefile           → Make           { make, make test }
  (nothing matched)  → Unknown        { echo 'No build system' }
```

Detection priority is top-to-bottom: if both `Package.swift` and `Makefile` exist, Swift Package wins.

For Node.js projects, the presence of `yarn.lock` determines whether `yarn` or `npm` is used.
For Xcode projects, the `.xcodeproj` filename is parsed to derive the scheme name automatically.

The result is stored as `ProjectInfo` and injected into the system prompt, so the LLM uses the correct commands without guessing.

---

## System Prompt Design

The system prompt is **rebuilt each time a workspace is opened**, embedding the detected project info at position 0 of `llmHistory`:

```
You are an autonomous coding agent with full file system and shell access.

## Detected Project
- Type: Swift Package
- Language: Swift
- Build: `swift build 2>&1`
- Test:  `swift test 2>&1`
- Run:   `swift run 2>&1`

## Workspace
/Users/me/Projects/MyApp

## How You Work
### For ANY task, follow this loop:
1. Explore — list_directory or search_files
2. Read    — read_file before any edit
3. Act     — edit_file for changes
4. Verify  — run_shell_command to build/test
5. Iterate — fix remaining errors, verify again

## Error Analysis Workflow (CRITICAL)
[5-step error-fix procedure with language-specific patterns]

## Key Rules
- NEVER skip reading a file before editing it
- ALWAYS use edit_file for existing files (not write_file)
- Fix ALL errors in one pass before re-running
- If edit_file fails (old_string not found), re-read the file first

## Tool Reference Table
[one-line summary per tool]
```

The temperature is set to **0.4** — low enough for deterministic code edits, but not so low that the model gets stuck.

---

## Error Analysis Workflow

The system prompt encodes a 5-step error-fix procedure. The LLM follows this for any compiler error, test failure, or stack trace:

```
Step 1 — Get fresh errors
  run_shell_command("swift build 2>&1")
  → Sources/Foo/Bar.swift:42:10: error: cannot find 'baz' in scope

Step 2 — Parse the error
  File:    Sources/Foo/Bar.swift
  Line:    42
  Column:  10
  Message: cannot find 'baz' in scope

Step 3 — Read context around the error line
  read_file("Sources/Foo/Bar.swift", start_line=35, end_line=52)
  → Shows exactly what's at and around line 42

Step 4 — Fix with a targeted edit
  edit_file("Sources/Foo/Bar.swift", old="baz()", new="baz2()")
  → Returns diff: - baz() / + baz2()

Step 5 — Verify the fix
  run_shell_command("swift build 2>&1")
  → "Build complete!" or new errors → repeat from Step 2
```

The system prompt includes error pattern templates for each supported language:

| Language | Error Pattern |
|----------|--------------|
| Swift/Clang | `file.swift:LINE:COL: error: message` |
| Python | `File "file.py", line LINE, in func` → `ErrorType: message` |
| TypeScript | `file.ts(LINE,COL): error TSXXX: message` |
| Rust | `error[EXXX]: message --> file.rs:LINE:COL` |
| Go | `./file.go:LINE:COL: undefined: symbol` |

---

## UI Architecture

```
CodingAgentView
  └─ NavigationSplitView
       ├─ Sidebar: FileExplorerView
       │    └─ Collapsible file tree from workspacePath
       │
       └─ Detail: VStack
            ├─ Header bar
            │    ├─ Model name + param count
            │    ├─ Workspace folder name
            │    └─ Session stats (tool calls, tokens)
            │
            ├─ ScrollView (message list)
            │    └─ ForEach messages → MessageBubbleView
            │         ├─ UserBubbleView
            │         │    └─ Blue rounded bubble, trailing alignment
            │         │
            │         └─ AssistantBubbleView
            │              ├─ Markdown text content (streaming)
            │              ├─ StreamingCursor (blinking while running)
            │              └─ ForEach toolCalls → ToolCallCardView
            │                   ├─ Header row (collapsible)
            │                   │    ├─ SF Symbol icon (colour-coded)
            │                   │    ├─ Tool display name
            │                   │    ├─ Summary text (path/command/pattern)
            │                   │    └─ Status dot (orange=running, green=done)
            │                   └─ Expanded body
            │                        ├─ Input: TerminalText (pretty JSON)
            │                        └─ Output (by tool type):
            │                             edit_file     → DiffView
            │                             run_shell /   → DiagnosticOutputView
            │                             run_tests       (coloured by severity)
            │                             others        → TerminalText
            │
            └─ AgentInputView
                 ├─ NSTextView-backed multi-line input
                 └─ Send / Stop button
```

### Diagnostic Output Colour Coding

`DiagnosticOutputView` parses shell and test output line-by-line:

| Regex Match | Text Colour | Background |
|-------------|-------------|-----------|
| `error:`, `FAIL`, `Traceback`, `SyntaxError`, `[exit N≠0]` | Red | Red 7% |
| `warning:`, `WARN`, `deprecated` | Yellow | Yellow 5% |
| `note:`, `hint:` | Blue | Blue 5% |
| `passed`, `✓`, `BUILD SUCCEEDED` | Green | Green 5% |
| Everything else | Primary | Transparent |

---

## Data Flow Diagram

```
User Input (text)
        │
        ▼
  messages[] ◄────────────────────────────────── AgentMessage(role:.user)
  llmHistory[] ◄──────────────────────────────── Chat.Message.user(text)
        │
        ▼
  streamSegment()
        │
        ├──► MLX token stream ─────────────────► message.content (live UI)
        │
        └──► ToolCall detected
                    │
                    ├──► messages[].toolCalls[] ◄─ AgentToolCall(executing)
                    │
                    ├──► toolExecutor.execute()
                    │           │
                    │           └──► File I/O / Process / Grep
                    │                       │
                    │                       └──► String result
                    │
                    ├──► messages[].toolCalls[] ◄─ .result = output
                    │
                    └──► llmHistory[] ◄─────────── Chat.Message.tool(result)
                                │
                                └──► [loop: streamSegment() again]
```

---

## Tools Reference

Individual tool documentation is in `docs/tools/`:

| Tool | Description | Docs |
|------|-------------|------|
| `read_file` | Read file with line numbers, supports range | [read_file.md](docs/tools/read_file.md) |
| `edit_file` | Targeted find-and-replace with diff output | [edit_file.md](docs/tools/edit_file.md) |
| `write_file` | Create a new file or fully overwrite | [write_file.md](docs/tools/write_file.md) |
| `list_directory` | Directory listing sorted dirs-first | [list_directory.md](docs/tools/list_directory.md) |
| `run_shell_command` | Execute any `/bin/sh` command | [run_shell_command.md](docs/tools/run_shell_command.md) |
| `run_tests` | Framework-aware test runner with summary | [run_tests.md](docs/tools/run_tests.md) |
| `search_files` | Regex grep across files with glob filter | [search_files.md](docs/tools/search_files.md) |
| `create_directory` | `mkdir -p` equivalent | [create_directory.md](docs/tools/create_directory.md) |
| `get_file_info` | Size, line count, modification date | [get_file_info.md](docs/tools/get_file_info.md) |

---

## Model & Inference

| Setting | Value |
|---------|-------|
| Default model | `Qwen3-8B-4bit` (via `LLMRegistry.qwen3_8b_4bit`) |
| Max tokens per response | 8,192 |
| Temperature | 0.4 |
| Context | Full `llmHistory` every call |
| Runtime | MLX on Apple Silicon (Neural Engine + GPU) |
| Memory cache limit | 20 MB (`Memory.cacheLimit`) |
| Model storage | `~/Library/Caches/` (HuggingFace Hub) |
| Seed | `Date.timeIntervalSinceReferenceDate * 1000` (varies per call) |

---

## File Structure

```
Applications/LLMEval/
├── README.md                           ← This file
├── docs/
│   └── tools/
│       ├── read_file.md
│       ├── edit_file.md
│       ├── write_file.md
│       ├── list_directory.md
│       ├── run_shell_command.md
│       ├── run_tests.md
│       ├── search_files.md
│       ├── create_directory.md
│       └── get_file_info.md
├── Models/
│   ├── AgentModels.swift               ← AgentMessage, AgentToolCall, FileEntry
│   └── PresetPrompts.swift
├── Services/
│   ├── CodingToolExecutor.swift        ← All 9 tools + project detection
│   └── FormatUtilities.swift
├── ViewModels/
│   └── CodingAgentViewModel.swift      ← Agentic loop + LLM management
└── Views/
    ├── CodingAgentView.swift           ← Root split-view layout
    ├── MessageBubbleView.swift         ← Chat + tool cards + diff + diagnostic
    ├── FileExplorerView.swift          ← Sidebar file tree
    └── AgentInputView.swift            ← Input bar
```
