# Tool: `run_shell_command`

**Icon:** `terminal`
**Display Name:** Bash
**Colour:** Orange
**Source:** `CodingToolExecutor.executeRunShell()`

---

## Purpose

Executes any shell command using `/bin/sh` and returns the combined stdout + stderr output. This is the most powerful and versatile tool — it handles building, testing, git operations, package installation, file manipulation, process inspection, and anything else that can be expressed as a shell command.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `command` | string | **Yes** | The shell command to execute. Runs via `/bin/sh -c`. Supports pipes, redirection, `&&`, `;`, etc. |
| `working_directory` | string | No | Override the working directory. Defaults to the workspace root if omitted. Relative paths are resolved from the workspace. |

---

## How It Works (Implementation)

```swift
// CodingToolExecutor.swift — executeRunShell()
let workDir = input.workingDirectory.map { resolvedURL($0) } ?? workspacePath

let (stdout, stderr, code) = try await runProcess(command: input.command, in: workDir)

// Combine and truncate output
var out = "$ \(input.command)"
let combined = (stdout + stderr).trimmingCharacters(in: .newlines)
if !combined.isEmpty {
    let maxChars = 6000
    let truncated = combined.count > maxChars
        ? String(combined.prefix(maxChars)) + "\n… [output truncated, N chars omitted]"
        : combined
    out += "\n" + truncated
}
if code != 0 { out += "\n[exit \(code)]" }
return out
```

### Process Execution (`runProcess`)

```swift
func runProcess(command: String, in directory: URL?) async throws -> (String, String, Int32) {
    try await withCheckedThrowingContinuation { continuation in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", command]
        p.currentDirectoryURL = directory
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.terminationHandler = { proc in
            let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            continuation.resume(returning: (stdout, stderr, proc.terminationStatus))
        }
        try p.run()
    }
}
```

Steps:
1. **Spawn `/bin/sh -c command`** in the working directory
2. **Capture stdout and stderr** separately via `Pipe`
3. **Wait for termination** via `terminationHandler` (async, non-blocking)
4. **Combine output** — stdout first, then stderr (stderr often has build errors)
5. **Truncate** at 6,000 characters with a message showing how many chars were omitted
6. **Append exit code** if non-zero: `[exit 1]`

---

## Output Format

```
$ swift build 2>&1
Build complete!
```

With errors:
```
$ swift build 2>&1
Sources/MyApp/Foo.swift:42:5: error: cannot find 'bar' in scope
    bar()
    ^~~
[exit 1]
```

With truncation:
```
$ xcodebuild build 2>&1
[... many lines ...]
… [output truncated, 2340 chars omitted]
```

---

## UI Display: `DiagnosticOutputView`

Unlike other tools that use plain `TerminalText`, `run_shell_command` output is rendered by `DiagnosticOutputView`, which parses each line and applies semantic colour coding:

| Pattern (regex, case-insensitive) | Colour | Background |
|-----------------------------------|--------|-----------|
| `error:`, `FAIL`, `FAILED`, `Traceback`, `SyntaxError`, `TypeError`, `[exit N≠0]` | Red | Red 7% |
| `warning:`, `WARN`, `deprecated` | Yellow | Yellow 5% |
| `note:`, `hint:` | Blue | Blue 5% |
| `passed`, `✓`, `BUILD SUCCEEDED`, `All tests passed` | Green | Green 5% |
| All other lines | Primary | Transparent |

Each highlighted line also has a 3px colour band on the left edge for quick scanning.

---

## Error Handling

| Situation | Response |
|-----------|----------|
| Command not found | Exit code 127, `"sh: command not found"` in output |
| Non-zero exit code | Output returned normally, `[exit N]` appended |
| Process launch fails | Swift `throws` → `"Tool error [run_shell_command]: …"` |
| Output exceeds 6000 chars | Truncated with omission notice |

The tool **does not throw** for non-zero exit codes — the agent sees the error output and can act on it.

---

## Common Use Cases

### Build the project
```json
{ "command": "swift build 2>&1" }
{ "command": "xcodebuild -scheme MyApp build 2>&1 | tail -50" }
{ "command": "cargo build 2>&1" }
{ "command": "npm run build 2>&1" }
```

### Run tests
```json
{ "command": "swift test 2>&1" }
{ "command": "python -m pytest -v 2>&1" }
{ "command": "go test ./... 2>&1" }
```

### Git operations
```json
{ "command": "git status" }
{ "command": "git diff HEAD" }
{ "command": "git log --oneline -10" }
```

### Find files
```json
{ "command": "find . -name '*.swift' -not -path '*/.build/*'" }
{ "command": "ls -la Sources/MyApp/" }
```

### Install dependencies
```json
{ "command": "pip install -r requirements.txt" }
{ "command": "npm install" }
```

### Check environment
```json
{ "command": "swift --version" }
{ "command": "python3 --version" }
{ "command": "which xcodebuild" }
```

### View logs or generated files
```json
{ "command": "cat .build/debug/output.log | tail -20" }
```

---

## Error Analysis Pattern

This tool is central to the error-analysis workflow. The agent runs:

```
Step 1: run_shell_command { "command": "swift build 2>&1" }
  → Sources/Foo.swift:42:5: error: cannot find 'bar'
  → [exit 1]

Step 2: read_file { "path": "Sources/Foo.swift", "start_line": 35, "end_line": 55 }

Step 3: edit_file { "path": "Sources/Foo.swift", ... }

Step 4: run_shell_command { "command": "swift build 2>&1" }
  → Build complete!
```

The `2>&1` redirect is important — it merges stderr (where Swift and many compilers write errors) into stdout so everything is captured in a single combined output.

---

## Shell Features Available

Since the command runs via `/bin/sh -c`, all standard shell features work:

| Feature | Example |
|---------|---------|
| Pipes | `swift build 2>&1 \| grep error` |
| Redirection | `swift build 2>&1 \| tail -30` |
| Chaining | `cd subdir && npm test` |
| Variable expansion | `echo $HOME` |
| Subshells | `$(git rev-parse HEAD)` |
| Glob expansion | `wc -l Sources/**/*.swift` |

---

## Important Notes

- **No timeout** — long-running commands (large builds, downloads) will run to completion. Use `| head -N` or `| tail -N` to limit output from verbose commands.
- **Working directory** defaults to workspace root — this is correct for most project commands
- **stderr is captured** — always use `2>&1` for build commands that write errors to stderr
- **Non-zero exit does not throw** — the agent sees all output regardless of success/failure
