# Tool: `run_tests`

**Icon:** `checkmark.circle`
**Display Name:** Run Tests
**Colour:** Green
**Source:** `CodingToolExecutor.executeRunTests()`

---

## Purpose

A dedicated test runner that automatically selects the correct test framework for the project, runs the test suite, and parses the output to produce a clean pass/fail summary. Unlike `run_shell_command`, this tool requires no knowledge of which test command to use — it detects the framework from the workspace's `ProjectInfo` and constructs the right command automatically.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `test_target` | string | No | Run only a specific test target or file. E.g. `"MyAppTests"` for Swift, `"tests/test_foo.py"` for Python, `"AuthService"` for Node.js. |
| `test_filter` | string | No | Filter to run specific test cases within the target. E.g. `"testLogin"` for Swift, `"-k login"` for pytest. |

All parameters are optional — calling with `{}` runs the full test suite.

---

## How It Works (Implementation)

```swift
// CodingToolExecutor.swift — executeRunTests()

// 1. Get project info (from cache or re-detect)
let info = projectInfo ?? (await detectProject())
var cmd = info.testCommand   // e.g. "swift test 2>&1"

// 2. Apply test_target if provided
if let target = input.testTarget, !target.isEmpty {
    switch info.type {
    case .swift:   cmd = "swift test --filter \(target) 2>&1"
    case .python:  cmd = "python -m pytest \(target) -v 2>&1"
    case .nodejs:  cmd = "npm test -- --testPathPattern=\(target) 2>&1"
    case .rust:    cmd = "cargo test \(target) 2>&1"
    case .go:      cmd = "go test ./... -run \(target) 2>&1"
    default:       break
    }
}

// 3. Apply test_filter if provided
if let filter = input.testFilter, !filter.isEmpty {
    switch info.type {
    case .swift:   cmd += " --filter \(filter)"
    case .python:  cmd += " -k '\(filter)'"
    case .rust:    cmd += " \(filter)"
    default:       break
    }
}

// 4. Execute
let (stdout, stderr, code) = try await runProcess(command: cmd, in: workspacePath)
let raw = (stdout + stderr).trimmingCharacters(in: .newlines)

// 5. Parse summary
let summary = parseTestSummary(raw: raw, projectType: info.type)

// 6. Return full output + summary
return "$ \(cmd)\n\n\(raw)\n\n\(summary)"
```

---

## Framework-Specific Commands

### Swift Package (`swift test`)
| Scenario | Command Generated |
|----------|------------------|
| All tests | `swift test 2>&1` |
| Specific target | `swift test --filter MyTests 2>&1` |
| Specific test case | `swift test 2>&1 --filter testFoo` |

### Python (`pytest`)
| Scenario | Command Generated |
|----------|------------------|
| All tests | `python -m pytest -v 2>&1` |
| Specific file | `python -m pytest tests/test_foo.py -v 2>&1` |
| By name | `python -m pytest -v 2>&1 -k 'test_login'` |

### Node.js (`jest` via npm/yarn)
| Scenario | Command Generated |
|----------|------------------|
| All tests | `npm test 2>&1` |
| Specific pattern | `npm test -- --testPathPattern=AuthService 2>&1` |

### Rust (`cargo test`)
| Scenario | Command Generated |
|----------|------------------|
| All tests | `cargo test 2>&1` |
| Specific test | `cargo test auth_test 2>&1` |
| With filter | `cargo test 2>&1 login` |

### Go (`go test`)
| Scenario | Command Generated |
|----------|------------------|
| All tests | `go test ./... 2>&1` |
| Specific test | `go test ./... -run TestLogin 2>&1` |

---

## Test Summary Parsing

After running tests, `parseTestSummary()` scans the output for a human-readable summary line:

```swift
switch projectType {
case .swift:
    // Looks for: "Test Suite 'All tests' passed at …"
    // Falls back to: count of "passed"/"failed" Test Case lines
    → "Test Suite 'All tests' passed at 2025-03-01 · 14 tests, 0 failures"
    → "✓ 14 passed  ✗ 0 failed"

case .python:
    // Looks for the last line containing "passed" or "failed"
    → "5 passed in 0.23s"
    → "3 failed, 2 passed in 0.45s"

case .nodejs:
    // Looks for "Tests:" summary line from Jest
    → "Tests: 3 failed, 12 passed, 15 total"

case .rust:
    // Looks for "test result: …" line
    → "test result: FAILED. 1 passed; 1 failed; 0 ignored"
    → "test result: ok. 5 passed; 0 failed; 0 ignored"

case .go:
    // Checks for lines starting with "ok" or "FAIL"
    → "✓ All tests passed"
    → "✗ Tests failed"
}
```

The summary is appended to the end of the output, after a blank line.

---

## Output Format

```
$ swift test 2>&1

Test Suite 'All tests' started at 2025-03-01 10:24:01.
Test Suite 'MyAppTests.xctest' started at 2025-03-01 10:24:01.
Test Case '-[MyAppTests.FooTests testCompute]' started.
Test Case '-[MyAppTests.FooTests testCompute]' passed (0.003 seconds).
Test Suite 'MyAppTests.xctest' passed at 2025-03-01 10:24:01.

Test Suite 'All tests' passed at 2025-03-01 10:24:01.
Executed 1 test, with 0 failures (0 unexpected) in 0.003 (0.006) seconds

Test Suite 'All tests' passed at 2025-03-01 10:24:01.
```

With failures:
```
$ swift test 2>&1

Test Case '-[MyAppTests.FooTests testCompute]' started.
/Users/me/MyApp/Tests/FooTests.swift:15: error: -[FooTests testCompute] : XCTAssertEqual failed: ("5") is not equal to ("4")
Test Case '-[MyAppTests.FooTests testCompute]' failed (0.012 seconds).

✗ 0 passed  ✗ 1 failed
```

---

## Error Handling

| Situation | Response |
|-----------|----------|
| No project detected | Calls `detectProject()` on demand |
| Test framework not installed | Exit code from shell; error in output |
| Compilation errors | Build fails before tests run; error shown in output |
| Output > 5000 chars | Truncated with `…` |

---

## When the Agent Uses This Tool

1. **After fixing a bug** — verifies the fix didn't break other tests
2. **When asked "do tests pass?"** — runs the full suite and reports
3. **Debugging a test failure** — runs with `test_filter` to isolate a specific failing test
4. **After adding new functionality** — checks that existing tests still pass
5. **Before committing** — final verification step

---

## Example Calls

### Run all tests
```json
{}
```

### Run a specific Swift test target
```json
{
  "test_target": "MyAppTests"
}
```

### Run a specific Swift test case
```json
{
  "test_target": "FooTests",
  "test_filter": "testCompute"
}
```

### Run a specific Python test file
```json
{
  "test_target": "tests/test_foo.py"
}
```

### Run Python tests matching a keyword
```json
{
  "test_filter": "login"
}
```

### Run a specific Go test
```json
{
  "test_filter": "TestLogin"
}
```

---

## Relationship with `run_shell_command`

| Aspect | `run_tests` | `run_shell_command` |
|--------|-------------|---------------------|
| Command selection | Automatic (from project type) | Manual (agent must write it) |
| Output summary | Yes (parsed pass/fail count) | No (raw output only) |
| Test target / filter | Structured parameters | Must be in the command string |
| Output highlighting | `DiagnosticOutputView` | `DiagnosticOutputView` |
| Use when | Running tests | Building, git, custom commands |

Both tools render output with `DiagnosticOutputView`, so errors appear red and passes appear green.
