# Tool: `list_directory`

**Icon:** `folder`
**Display Name:** List Directory
**Colour:** Indigo
**Source:** `CodingToolExecutor.executeListDirectory()`

---

## Purpose

Lists the contents of a directory, showing files and subdirectories sorted with directories first (alphabetically within each group), along with file sizes. Used to explore project structure, understand where things are, and navigate before reading or editing files.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | string | No | Directory to list. Defaults to the workspace root if omitted. Relative paths are resolved from the workspace root. |

---

## How It Works (Implementation)

```swift
// CodingToolExecutor.swift — executeListDirectory()
let dirURL = input.path.map { resolvedURL($0) }
             ?? workspacePath
             ?? FileManager.default.homeDirectoryForCurrentUser

let contents = try FileManager.default.contentsOfDirectory(
    at: dirURL,
    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
    options: [.skipsHiddenFiles]          // hidden files (dot-files) are excluded
).sorted { a, b in
    let aIsDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    let bIsDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    if aIsDir != bIsDir { return aIsDir }  // directories first
    return a.lastPathComponent.lowercased() < b.lastPathComponent.lowercased()
}

for url in contents {
    let isDir = ...
    let size  = ...
    lines.append(isDir ? "  \(name)/" : "  \(name)  \(formatSize(size))")
}
lines.append("(\(contents.count) items)")
```

Steps:
1. **Resolve target directory** — workspace root if no path given
2. **Read directory** — using `FileManager.contentsOfDirectory` with resource keys for type and size
3. **Skip hidden files** — `.skipsHiddenFiles` option excludes dotfiles (`.git`, `.DS_Store`)
4. **Sort** — directories always appear before files; within each group, alphabetical order
5. **Format entries** — directories have `/` suffix; files show size (B/KB/MB/GB)
6. **Append item count** — last line shows total count

---

## Output Format

```
MyApp/
  Sources/
  Tests/
  docs/
  .gitignore        (not shown — hidden)
  Package.swift     2 KB
  Package.resolved  1 KB
  README.md         4 KB
(7 items)
```

- Directories appear first with a `/` suffix
- Files show their size formatted as B, KB, MB, or GB
- The header line shows the directory name with a `/` suffix
- Hidden files (starting with `.`) are excluded

---

## Error Handling

| Situation | Response |
|-----------|----------|
| Path does not exist | Swift `throws` → `"Tool error [list_directory]: …"` |
| Not a directory | Swift `throws` from `contentsOfDirectory` |
| No permission | Swift `throws` → `"Tool error [list_directory]: …"` |
| Empty directory | Lists header and `(0 items)` |

---

## Size Formatting

The `formatSize()` helper formats byte counts into human-readable strings:

| Bytes | Output |
|-------|--------|
| < 1024 | `512 B` |
| 1024 – 1 MB | `14 KB` |
| 1 MB – 1 GB | `2.4 MB` |
| ≥ 1 GB | `1.2 GB` |

---

## When the Agent Uses This Tool

1. **Project exploration** — called automatically when a workspace is opened
2. **Before reading files** — to confirm a file exists and find its location
3. **Navigating subdirectories** — drilling into `Sources/`, `Tests/`, etc.
4. **Understanding project structure** — before writing code in a new area
5. **Finding a file** — when the user mentions a filename but the agent doesn't know where it is

---

## Example Calls

### List workspace root (no argument needed)
```json
{}
```

### List a specific subdirectory
```json
{
  "path": "Sources/MyApp"
}
```

### List a nested directory
```json
{
  "path": "Sources/MyApp/ViewModels"
}
```

---

## Example Output

### Listing a Swift Package root
```
MyApp/
  Sources/
  Tests/
  Package.resolved  1 KB
  Package.swift     2 KB
  README.md         8 KB
(5 items)
```

### Listing the Sources directory
```
Sources/
  MyApp/
(1 item)
```

### Listing a view models directory
```
ViewModels/
  CodingAgentViewModel.swift  14 KB
  DeviceStat.swift             2 KB
  LLMEvaluator.swift          18 KB
(3 items)
```

---

## Relationship with Other Tools

| Goal | Recommended Tool |
|------|-----------------|
| Find all Swift files | `search_files` with `file_pattern: "*.swift"` |
| Know if a file exists | `list_directory` on its parent, or `get_file_info` |
| See file content | `read_file` |
| Navigate structure | `list_directory` (start broad, drill down) |

---

## Notes

- **Hidden files are excluded** — dotfiles like `.env`, `.gitignore`, `.git/` are not shown. Use `run_shell_command("ls -la")` to see hidden files.
- **Not recursive** — lists only one level deep. To see nested structure, call multiple times or use `search_files`.
- **Symlinks** — treated as files, size shown as 0.
