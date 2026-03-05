# Tool: `edit_file`

**Icon:** `pencil.and.list.clipboard`
**Display Name:** Edit File
**Colour:** Purple
**Source:** `CodingToolExecutor.executeEditFile()`

---

## Purpose

Makes a targeted, surgical edit to an existing file by finding an exact string and replacing it. This is the **preferred tool for all code changes** — it never rewrites files unnecessarily and provides a clear diff of what changed. The agent uses it for fixing bugs, refactoring, updating imports, changing function signatures, and any other code modification.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | string | **Yes** | Path to the file to edit (relative or absolute) |
| `old_string` | string | **Yes** | Exact text to find and replace. Must match the file character-for-character including all whitespace and indentation. |
| `new_string` | string | **Yes** | Replacement text. Can be empty string `""` to delete `old_string`. |

---

## How It Works (Implementation)

```swift
// CodingToolExecutor.swift — executeEditFile()
let url = resolvedURL(input.path)
let original = try String(contentsOf: url, encoding: .utf8)

// 1. Verify old_string exists exactly
guard original.contains(input.oldString) else {
    let preview = String(original.prefix(300))...
    return "Error: old_string not found..."
}

// 2. Replace only the FIRST occurrence
let updated = original.replacingFirstOccurrence(of: input.oldString, with: input.newString)

// 3. Write atomically
try updated.write(to: url, atomically: true, encoding: .utf8)

// 4. Return a diff
var diff = "Edited \(filename)\n"
diff += oldLines.map { "- \($0)" }.joined(separator: "\n")
diff += "\n" + newLines.map { "+ \($0)" }.joined(separator: "\n")
```

Steps:
1. **Load file** — reads current content as UTF-8
2. **Verify match** — checks `old_string` exists; fails fast with a helpful error if not
3. **Replace first occurrence** — uses `replacingFirstOccurrence(of:with:)` (not `replaceAll`) so the agent makes one precise change at a time
4. **Atomic write** — writes via a temp file to avoid data loss on crash
5. **Return diff** — formats removed lines with `-` prefix and added lines with `+` prefix

The diff is displayed by `DiffView` in the UI with red/green highlighting.

---

## Output Format

On success, returns a diff-style view:
```
Edited Sources/MyApp/Foo.swift
- return baz()
+ return baz2()
```

For multi-line changes:
```
Edited Sources/MyApp/ContentView.swift
- var items: [String] = []
- var count = 0
+ var items: [Item] = []
+ var count: Int { items.count }
```

For deletions (`new_string = ""`):
```
Edited Sources/MyApp/Foo.swift
- // TODO: remove this
```

---

## Error Handling

| Situation | Response |
|-----------|----------|
| `old_string` not in file | `"Error: old_string not found in Foo.swift. Match must be exact (whitespace matters).\nFile preview: …"` |
| File does not exist | Swift `throws` → `"Tool error [edit_file]: …"` |
| `old_string` appears multiple times | First occurrence is replaced (intentional — agent makes one change at a time) |

---

## Critical Constraint: Exact Matching

`old_string` **must match exactly** — every space, tab, newline, and character counts. This is why the agent must always call `read_file` first:

```
❌ Wrong (leading spaces missing):
{
  "old_string": "func compute() -> Int {"
}

✓ Correct (matches file exactly):
{
  "old_string": "    func compute() -> Int {"
}
```

If `edit_file` returns `"Error: old_string not found"`, the agent re-reads the file and tries again with the exact content.

---

## When the Agent Uses This Tool

- **Bug fixes** — replacing a wrong function call, wrong variable name, wrong type
- **Import additions** — adding `import Foundation` at the top of a file
- **Signature changes** — updating function parameter types or return types
- **Logic corrections** — changing an `if` condition, fixing an off-by-one error
- **Configuration updates** — changing values in `Package.swift`, `package.json`, etc.
- **Any edit to an existing file** — always preferred over `write_file` for existing files

---

## Example Calls

### Fix a function call
```json
{
  "path": "Sources/MyApp/Foo.swift",
  "old_string": "        return baz()",
  "new_string": "        return bar()"
}
```

### Add a missing import
```json
{
  "path": "Sources/MyApp/ContentView.swift",
  "old_string": "import SwiftUI\n",
  "new_string": "import SwiftUI\nimport Foundation\n"
}
```

### Delete a line
```json
{
  "path": "Sources/MyApp/Foo.swift",
  "old_string": "        // TODO: fix this\n",
  "new_string": ""
}
```

### Multi-line replacement
```json
{
  "path": "Package.swift",
  "old_string": "    targets: [\n        .target(name: \"MyApp\"),\n    ]",
  "new_string": "    targets: [\n        .target(name: \"MyApp\", dependencies: [\"Utils\"]),\n    ]"
}
```

---

## Relationship with `read_file`

The typical pattern for every edit:

```
1. read_file("Sources/Foo.swift")
   → see exact content including whitespace/indentation

2. edit_file("Sources/Foo.swift",
             old_string="    return wrongValue()",
             new_string="    return correctValue()")
   → Edited Sources/Foo.swift
     - return wrongValue()
     + return correctValue()

3. run_shell_command("swift build 2>&1")
   → Verify fix worked
```

---

## UI Display

In `MessageBubbleView`, `edit_file` results are rendered by `DiffView`, which:
- Shows lines prefixed with `-` in **red** (removed)
- Shows lines prefixed with `+` in **green** (added)
- Uses monospaced font for code clarity
