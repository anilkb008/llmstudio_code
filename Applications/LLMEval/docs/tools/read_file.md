# Tool: `read_file`

**Icon:** `doc.text`
**Display Name:** Read File
**Colour:** Teal
**Source:** `CodingToolExecutor.executeReadFile()`

---

## Purpose

Reads the content of any file and returns it with line numbers. This is the **most important tool** — the agent is required to call it before editing any existing file. It prevents the agent from guessing file content and ensures that `edit_file`'s `old_string` will match exactly.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | string | **Yes** | File path. Relative paths are resolved from the workspace root. Absolute paths (starting with `/`) are used as-is. |
| `start_line` | integer | No | First line to read (1-based). Omit to start from line 1. |
| `end_line` | integer | No | Last line to read (1-based). Omit to read to the end of the file. |

---

## How It Works (Implementation)

```swift
// CodingToolExecutor.swift — executeReadFile()
let url = resolvedURL(input.path)
let content = try String(contentsOf: url, encoding: .utf8)
let lines = content.components(separatedBy: "\n")

let s = max(1, input.startLine ?? 1)
let e = min(total, input.endLine ?? total)

// Format each line: "  42\tline content"
let numbered = lines[(s-1)...(e-1)].enumerated().map { i, line in
    String(format: "%4d\t%@", s + i, line)
}
```

Steps:
1. **Resolve path** — `resolvedURL()` prepends the workspace path for relative paths
2. **Read file** — `String(contentsOf:)` loads the full file as UTF-8
3. **Split into lines** — `components(separatedBy: "\n")`
4. **Apply range** — clamp `start_line` and `end_line` to valid bounds
5. **Number lines** — format each line as `"  42\tcontent"` (4-wide line number, tab, content)
6. **Build header** — first line of output shows filename, total line count, and visible range if partial

---

## Output Format

```
Sources/MyApp/Foo.swift (120 lines total) · showing lines 35–52
  35	    func doSomething() {
  36	        let value = compute()
  37	        if value > 0 {
  38	            return value
  ...
  52	    }
```

- **Header line:** relative path, total lines, and visible range (if reading a subset)
- **Body:** 4-digit line number, tab character, then the line content
- Line numbers are always 1-based

If reading the full file, the header shows just `(N lines total)` without a range.

---

## Error Handling

| Situation | Response |
|-----------|----------|
| File does not exist | Swift `throws` propagates as `"Tool error [read_file]: …"` |
| `start_line` > `end_line` | `"Error: line range S–E out of bounds (file has N lines)"` |
| Range out of bounds | Clamped silently: `max(1, start)` and `min(total, end)` |
| Non-UTF-8 file | Swift `throws` propagates |

---

## Path Resolution

```swift
func resolvedURL(_ path: String) -> URL {
    if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
    return workspacePath.appendingPathComponent(path)
}
```

- `"Sources/Foo.swift"` → `{workspace}/Sources/Foo.swift`
- `"/absolute/path/file.swift"` → `/absolute/path/file.swift`

---

## When the Agent Uses This Tool

1. **Before any edit** — reads the file to get exact content for `edit_file`'s `old_string`
2. **Error analysis** — reads the file around an error line (`start_line: errorLine - 10, end_line: errorLine + 10`)
3. **Code understanding** — reads files to understand architecture before responding
4. **After an edit** — occasionally re-reads to confirm the change is correct

---

## Example Calls

### Read an entire file
```json
{
  "path": "Sources/MyApp/ContentView.swift"
}
```

### Read around an error on line 42
```json
{
  "path": "Sources/MyApp/Foo.swift",
  "start_line": 32,
  "end_line": 55
}
```

### Read just the top of a file
```json
{
  "path": "Package.swift",
  "start_line": 1,
  "end_line": 20
}
```

---

## Example Output

```
Sources/MyApp/Foo.swift (85 lines total) · showing lines 32–55
  32
  33	    // MARK: - Helpers
  34
  35	    private func formatDate(_ date: Date) -> String {
  36	        let formatter = DateFormatter()
  37	        formatter.dateStyle = .medium
  38	        return formatter.string(from: date)
  39	    }
  40
  41	    func compute() -> Int {
  42	        return baz()   // error: cannot find 'baz' in scope
  43	    }
```

---

## Agent Behaviour Notes

- The system prompt states: **"NEVER skip reading a file before editing it"**
- If `edit_file` fails with "old_string not found", the agent's next step is always to re-read the file with `read_file` to get the current exact content
- The agent uses `start_line`/`end_line` efficiently when it knows which line has an error — it doesn't need to read hundreds of irrelevant lines
