# Tool: `search_files`

**Icon:** `magnifyingglass`
**Display Name:** Search
**Colour:** Yellow
**Source:** `CodingToolExecutor.executeSearchFiles()`

---

## Purpose

Searches for a text pattern across all files in the workspace (or a subdirectory) using `grep`. Supports regex patterns and glob-based file filtering. Used to find symbol definitions, locate all usages of a function, search for TODO/FIXME comments, or find which file contains a specific string.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `pattern` | string | **Yes** | Search pattern. Regular expressions are supported (e.g. `"func.*Error"`, `"import.*Foundation"`). |
| `directory` | string | No | Directory to search in. Defaults to workspace root. Relative paths are resolved from workspace. |
| `file_pattern` | string | No | Glob to filter which files are searched. E.g. `"*.swift"`, `"*.py"`, `"*.{ts,tsx}"`. Defaults to all files (`"*"`). |
| `max_results` | integer | No | Maximum number of matching lines to return. Defaults to 50. |

---

## How It Works (Implementation)

```swift
// CodingToolExecutor.swift — executeSearchFiles()
let dir = input.directory.map { resolvedURL($0) } ?? workspacePath
let max = input.maxResults ?? 50

// Escape single quotes in pattern for shell safety
let pat = input.pattern.replacingOccurrences(of: "'", with: "'\"'\"'")

// Build grep command
let cmd = "grep -rn --include='\(input.filePattern ?? "*")' -m \(max) '\(pat)' '\(dir.path)' 2>/dev/null | head -\(max)"

let (stdout, _, _) = try await runProcess(command: cmd, in: nil)

// Strip the workspace prefix from all paths for readability
let relative = stdout.replacingOccurrences(of: dir.path + "/", with: "")

return "grep '\(input.pattern)'\n\(relative)"
```

The underlying command uses:
- `grep -r` — recursive search through all subdirectories
- `-n` — include line numbers in output
- `--include=GLOB` — only search files matching the glob pattern
- `-m MAX` — stop after MAX matches per file
- `| head -MAX` — limit total output lines

Single quotes in the pattern are shell-escaped using the `'"'"'` technique to handle them safely.

---

## Output Format

```
grep 'func.*Error'
Sources/MyApp/NetworkClient.swift:23:    func handleNetworkError(_ error: Error) {
Sources/MyApp/Parser.swift:87:    func parseError(from data: Data) throws -> AppError {
Tests/MyAppTests/ErrorTests.swift:12:    func testNetworkError() throws {
```

Each result line is formatted as:
```
relative/path/to/file.swift:LINE_NUMBER:    matching line content
```

The workspace path prefix is stripped from all results so they show relative paths.

If no matches are found:
```
No matches for 'func.*Error'
```

---

## Error Handling

| Situation | Response |
|-----------|----------|
| No matches | `"No matches for 'pattern'"` |
| Directory doesn't exist | `grep` returns nothing; `"No matches for …"` |
| Invalid regex | `grep` error is suppressed by `2>/dev/null` |
| Too many results | Truncated to `max_results` (default 50) |

---

## Regex Support

Since this uses `grep`, standard POSIX extended regular expressions are supported:

| Pattern | Matches |
|---------|---------|
| `func foo` | Exact string |
| `func.*Error` | "func" followed by anything then "Error" |
| `^import` | Lines starting with "import" |
| `(Error\|Warning)` | Lines containing "Error" or "Warning" |
| `\bfoo\b` | Whole word "foo" |
| `func\s+\w+.*async` | Async functions |

---

## When the Agent Uses This Tool

1. **Finding a symbol definition** — `search_files("class UserRepository", "*.swift")`
2. **Finding all usages** — `search_files("\.foo\(", "*.swift")` to find all calls to `.foo()`
3. **Locating an error** — searching for the symbol name mentioned in a compiler error
4. **Finding TODO/FIXME** — `search_files("TODO|FIXME")`
5. **Finding imports** — `search_files("import Foundation", "*.swift")`
6. **Checking for a pattern** — `search_files("force_unwrap|!", "*.swift")`
7. **Navigating unfamiliar code** — instead of reading every file, search for the relevant function name

---

## Example Calls

### Find where a class is defined
```json
{
  "pattern": "class UserRepository",
  "file_pattern": "*.swift"
}
```

### Find all usages of a method
```json
{
  "pattern": "fetchUser(",
  "file_pattern": "*.swift"
}
```

### Find TODO comments
```json
{
  "pattern": "TODO|FIXME|HACK",
  "file_pattern": "*.swift"
}
```

### Find async functions
```json
{
  "pattern": "func.*async",
  "file_pattern": "*.swift"
}
```

### Search only in tests
```json
{
  "pattern": "XCTAssertEqual",
  "directory": "Tests",
  "file_pattern": "*.swift"
}
```

### Find Python function definitions
```json
{
  "pattern": "def test_",
  "file_pattern": "*.py"
}
```

### Search with more results
```json
{
  "pattern": "import",
  "file_pattern": "*.swift",
  "max_results": 100
}
```

---

## Example Output

### Searching for a function
```
grep 'func compute'
Sources/MyApp/Calculator.swift:45:    func compute() -> Int {
Sources/MyApp/Calculator.swift:89:    func computeSum(_ values: [Int]) -> Int {
Tests/CalculatorTests.swift:12:    func testCompute() {
```

### Searching for TODOs
```
grep 'TODO|FIXME'
Sources/MyApp/NetworkClient.swift:34:    // TODO: add retry logic
Sources/MyApp/Parser.swift:102:    // FIXME: handle edge case for empty data
```

### No matches
```
No matches for 'class Foobar'
```

---

## Compared to Other Discovery Tools

| Goal | Best Tool |
|------|-----------|
| Find all files of a type | `list_directory` + recursive calls |
| Find symbol by name | `search_files` (fastest) |
| Find code near line N | `read_file` with `start_line`/`end_line` |
| Understand file structure | `read_file` on the whole file |
| Run a complex find | `run_shell_command("find . -name '*.swift'")`|

---

## Notes

- **Case-sensitive by default** — `grep` is case-sensitive. For case-insensitive search, use `run_shell_command("grep -ri 'pattern' . | head -50")`.
- **Hidden directories are searched** — unlike `list_directory`, `grep -r` will enter `.build/`, `.git/`, etc. Use a subdirectory or file pattern to avoid noise.
- **Binary files** — `grep` skips binary files automatically.
