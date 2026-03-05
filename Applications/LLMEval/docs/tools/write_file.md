# Tool: `write_file`

**Icon:** `doc.badge.plus`
**Display Name:** Write File
**Colour:** Blue
**Source:** `CodingToolExecutor.executeWriteFile()`

---

## Purpose

Writes the complete content of a file to disk. Intended for **creating new files** — for example, adding a new Swift source file, creating a test file, generating a configuration file, or writing a shell script. For **existing files**, the agent uses `edit_file` instead to make precise targeted changes.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | string | **Yes** | Path for the file (relative to workspace or absolute). Parent directories are created automatically if they don't exist. |
| `content` | string | **Yes** | The complete content to write. Overwrites any existing file at this path. |

---

## How It Works (Implementation)

```swift
// CodingToolExecutor.swift — executeWriteFile()
let url = resolvedURL(input.path)

// 1. Create parent directories if needed
try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

// 2. Check if file already existed (for the return message)
let existed = FileManager.default.fileExists(atPath: url.path)

// 3. Write content atomically
try input.content.write(to: url, atomically: true, encoding: .utf8)

// 4. Return confirmation
let lines = input.content.components(separatedBy: "\n").count
return "\(existed ? "Updated" : "Created") \(relativePath) (\(lines) lines)"
```

Steps:
1. **Resolve path** — relative paths are resolved from the workspace root
2. **Create parent directories** — `mkdir -p` equivalent using `withIntermediateDirectories: true`
3. **Record whether file existed** — used to say "Created" vs "Updated" in the response
4. **Atomic write** — writes via a temporary file; on success, renames atomically (no partial writes on crash)
5. **Count lines** — for display in the confirmation message

---

## Output Format

When creating a new file:
```
Created Sources/MyApp/NewFeature.swift (45 lines)
```

When overwriting an existing file:
```
Updated Sources/MyApp/NewFeature.swift (48 lines)
```

---

## Error Handling

| Situation | Response |
|-----------|----------|
| Parent directory cannot be created | Swift `throws` → `"Tool error [write_file]: …"` |
| Write fails (permission, disk full) | Swift `throws` → `"Tool error [write_file]: …"` |

---

## When the Agent Uses This Tool

- Creating a **new Swift source file** (new class, struct, view, view model)
- Creating a **new test file** (`*Tests.swift`)
- Writing a **configuration file** (`Package.swift` if it doesn't exist, `.gitignore`, `Makefile`)
- Generating a **script** (`build.sh`, `run_tests.sh`)
- Creating a **new Python module** or Node.js module
- Writing **documentation files** (`README.md` for a new module)

### What It Should NOT Be Used For

The system prompt explicitly states: **"For existing files use `edit_file` instead."**

The reason is safety and precision — `write_file` with a wrong `content` value overwrites the entire file, destroying all existing code. `edit_file` is always safer for modifications.

---

## Example Calls

### Create a new Swift source file
```json
{
  "path": "Sources/MyApp/UserRepository.swift",
  "content": "// Copyright © 2025 Apple Inc.\n\nimport Foundation\n\nstruct UserRepository {\n    func fetchUser(id: String) async throws -> User {\n        // TODO: implement\n        fatalError(\"Not implemented\")\n    }\n}\n"
}
```

### Create a new test file
```json
{
  "path": "Tests/MyAppTests/UserRepositoryTests.swift",
  "content": "import XCTest\n@testable import MyApp\n\nfinal class UserRepositoryTests: XCTestCase {\n    func testFetchUser() async throws {\n        let repo = UserRepository()\n        // TODO: add assertions\n    }\n}\n"
}
```

### Create a shell script
```json
{
  "path": "scripts/build.sh",
  "content": "#!/bin/bash\nset -e\nswift build -c release\necho 'Build succeeded'\n"
}
```

### Create a new directory structure with a file
```json
{
  "path": "Sources/MyApp/Networking/APIClient.swift",
  "content": "import Foundation\n\nclass APIClient {\n    ...\n}\n"
}
```
> Note: The `Sources/MyApp/Networking/` directory will be created automatically.

---

## Relationship with Other Tools

| Scenario | Use |
|----------|-----|
| File does not exist | `write_file` |
| File exists, small change | `edit_file` |
| File exists, complete rewrite needed | `write_file` (but rare — agent prefers `edit_file`) |
| Need to see current content | `read_file` first, then decide |

---

## Atomic Write Safety

The write uses `atomically: true` which means:
1. Content is written to a temporary file
2. On success, the temp file is renamed to the target path (atomic on POSIX)
3. If the write fails midway, the original file is untouched

This prevents the common failure mode of truncating a file and then crashing before writing all the content.
