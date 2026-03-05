# Tool: `create_directory`

**Icon:** `folder.badge.plus`
**Display Name:** Create Directory
**Colour:** Secondary (grey)
**Source:** `CodingToolExecutor.executeCreateDirectory()`

---

## Purpose

Creates a directory at the specified path, including all intermediate parent directories that don't exist yet. Equivalent to the shell command `mkdir -p`. Used when the agent needs to create new directory structures for new source files, test targets, or project modules.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | string | **Yes** | The directory path to create. Relative paths are resolved from the workspace root. All missing parent directories are created automatically. |

---

## How It Works (Implementation)

```swift
// CodingToolExecutor.swift — executeCreateDirectory()
let url = resolvedURL(input.path)

try FileManager.default.createDirectory(
    at: url,
    withIntermediateDirectories: true,   // mkdir -p: creates parents
    attributes: nil
)

return "Created \(url.relativePath(from: workspacePath) ?? url.path)/"
```

Steps:
1. **Resolve path** — relative path prepended with workspace root
2. **Create with parents** — `withIntermediateDirectories: true` creates the full path chain
3. **No-op if exists** — calling on an existing directory does nothing (no error)
4. **Return confirmation** — shows the relative path with `/` suffix

---

## Output Format

```
Created Sources/MyApp/Networking/
```

Or for a deep path:
```
Created Sources/MyApp/Features/Authentication/ViewModels/
```

---

## Error Handling

| Situation | Response |
|-----------|----------|
| Directory already exists | Success (no error, no-op) |
| Permission denied | Swift `throws` → `"Tool error [create_directory]: …"` |
| Invalid path characters | Swift `throws` → `"Tool error [create_directory]: …"` |

---

## When the Agent Uses This Tool

1. **Before writing a new file** in a directory that doesn't exist yet
2. **Setting up a new module** — e.g. `Sources/MyApp/Networking/` for a new networking layer
3. **Creating a test directory** — e.g. `Tests/IntegrationTests/`
4. **Scaffolding a new feature** — creating the folder structure before creating source files

> **Note:** `write_file` also creates parent directories automatically via `createDirectory(withIntermediateDirectories: true)`. So for the common case of "create directory + write a file", you only need `write_file`. Use `create_directory` when you need the directory to exist before writing multiple files, or when setting up an empty directory.

---

## Example Calls

### Create a new source directory
```json
{
  "path": "Sources/MyApp/Networking"
}
```

### Create a nested directory structure
```json
{
  "path": "Sources/MyApp/Features/Authentication/Views"
}
```

### Create a test directory
```json
{
  "path": "Tests/IntegrationTests"
}
```

### Create a scripts directory
```json
{
  "path": "scripts"
}
```

---

## Example Patterns

### Scaffold a new feature

The agent often creates the directory first, then writes multiple files:

```
1. create_directory("Sources/MyApp/Features/Login")

2. write_file("Sources/MyApp/Features/Login/LoginView.swift", "...")

3. write_file("Sources/MyApp/Features/Login/LoginViewModel.swift", "...")

4. write_file("Sources/MyApp/Features/Login/LoginModel.swift", "...")
```

### Set up a new Swift Package target

```
1. create_directory("Sources/Utils")

2. write_file("Sources/Utils/StringExtensions.swift", "...")

3. edit_file("Package.swift", ...)   // add the new target
```

---

## Idempotency

`create_directory` is safe to call multiple times on the same path. If the directory already exists, the call succeeds silently. This makes it safe to call "just in case" before writing files.

---

## Relationship with Other Tools

| Tool | Directory Handling |
|------|-------------------|
| `create_directory` | Explicitly creates a directory |
| `write_file` | Auto-creates parent directories |
| `list_directory` | Lists contents of an existing directory |
| `run_shell_command` | Can run `mkdir -p` for more complex cases |
