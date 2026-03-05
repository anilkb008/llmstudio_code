# Tool: `get_file_info`

**Icon:** `info.circle`
**Display Name:** File Info
**Colour:** Secondary (grey)
**Source:** `CodingToolExecutor.executeGetFileInfo()`

---

## Purpose

Returns metadata about a file or directory: its type (file or directory), size on disk, line count (for text files), and last modification date. Used when the agent needs to make decisions based on file characteristics — for example, checking whether a large file should be read in sections, or confirming that a file exists before attempting to use it.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | string | **Yes** | Path to the file or directory. Relative paths are resolved from the workspace root. |

---

## How It Works (Implementation)

```swift
// CodingToolExecutor.swift — executeGetFileInfo()
let url = resolvedURL(input.path)
let attrs = try FileManager.default.attributesOfItem(atPath: url.path)

let isDir = (attrs[.type] as? FileAttributeType) == .typeDirectory

var lines = [url.relativePath(from: workspacePath) ?? url.path]
lines.append("Type: \(isDir ? "directory" : "file")")

if !isDir, let size = attrs[.size] as? Int {
    lines.append("Size: \(formatSize(size))")
}

if let date = attrs[.modificationDate] as? Date {
    lines.append("Modified: \(date.formatted(date: .abbreviated, time: .shortened))")
}

// For text files: read and count lines
if !isDir, let content = try? String(contentsOf: url, encoding: .utf8) {
    lines.append("Lines: \(content.components(separatedBy: "\n").count)")
}

return lines.joined(separator: "\n")
```

Steps:
1. **Resolve path** — relative path resolved from workspace
2. **Read file attributes** — using `FileManager.attributesOfItem`
3. **Determine type** — file vs directory from `.type` attribute
4. **Collect metadata** — size, modification date, line count
5. **Line count** — attempts to read the file as UTF-8 and count newlines (only for files)
6. **Format output** — one attribute per line

---

## Output Format

### For a text file:
```
Sources/MyApp/CodingAgentViewModel.swift
Type: file
Size: 14 KB
Modified: Mar 5, 2025 at 10:23 AM
Lines: 354
```

### For a directory:
```
Sources/MyApp
Type: directory
Modified: Mar 5, 2025 at 10:23 AM
```

### For a binary file (no line count):
```
AppIcon.png
Type: file
Size: 2.4 MB
Modified: Jan 15, 2025 at 3:00 PM
```

---

## Error Handling

| Situation | Response |
|-----------|----------|
| File/directory does not exist | Swift `throws` → `"Tool error [get_file_info]: …"` |
| No permission to read attributes | Swift `throws` → `"Tool error [get_file_info]: …"` |
| Binary file (non-UTF-8) | Line count is omitted silently |

---

## Size Formatting

| Bytes | Display |
|-------|---------|
| < 1 KB | `512 B` |
| 1 KB – 1 MB | `14 KB` |
| 1 MB – 1 GB | `2.4 MB` |
| ≥ 1 GB | `1.2 GB` |

---

## When the Agent Uses This Tool

1. **Before reading a large file** — checks `Lines` to decide whether to read the whole file or use `start_line`/`end_line`
2. **Confirming a file exists** — before attempting `edit_file` on a path the agent isn't sure about
3. **Checking a file was modified** — comparing modification dates after an edit
4. **Understanding binary vs text** — a file with no line count is binary (image, compiled output)
5. **Reporting to the user** — "the file is 354 lines long and was last modified today"

---

## Example Calls

### Get info on a source file
```json
{
  "path": "Sources/MyApp/CodingAgentViewModel.swift"
}
```

### Check a directory
```json
{
  "path": "Sources/MyApp"
}
```

### Verify a generated file exists
```json
{
  "path": ".build/debug/MyApp"
}
```

---

## Decision-Making Pattern

A common use of `get_file_info` is deciding how to read a large file:

```
get_file_info("Sources/MyApp/LargeFile.swift")
  → Lines: 1250

// 1250 lines is too large to read all at once efficiently
// The agent will use read_file with start_line/end_line to read it in sections

read_file("Sources/MyApp/LargeFile.swift", start_line: 1, end_line: 80)
  → header, imports, class declaration...

read_file("Sources/MyApp/LargeFile.swift", start_line: 600, end_line: 650)
  → the specific section with the bug
```

---

## Relationship with Other Tools

| Need | Tool |
|------|------|
| Check file exists + get size | `get_file_info` |
| Read file contents | `read_file` |
| List all files in a directory | `list_directory` |
| Check if a path is a directory | `get_file_info` (Type: directory) |
| Find files matching a pattern | `search_files` |
