# Go Test Integration Example

This example demonstrates how to run tests in devcontainers using devcontainer.nvim's test integration features.

## Features

- Calculator with comprehensive tests
- String utilities with various test cases
- Benchmark tests for performance testing
- Table-driven tests following Go best practices
- Integration with testify assertion library

## Setup

1. Open this directory in Neovim
2. Start the devcontainer:
   ```vim
   :DevcontainerOpen
   :DevcontainerStart
   ```

3. Wait for the container to start and test integration to be set up automatically

## Running Tests

### Using vim-test (if installed)

```vim
" Place cursor on a test function and run:
:TestNearest    " Runs the test under cursor

" Or run all tests in current file:
:TestFile

" Run all tests in the project:
:TestSuite
```

### Using devcontainer.nvim commands

These commands work even without vim-test installed:

```vim
" Run test under cursor (output in buffer)
:DevcontainerTestNearest

" Run all tests in current file (output in buffer)
:DevcontainerTestFile

" Run all tests in the project (output in buffer)
:DevcontainerTestSuite

" Run tests in terminal for interactive output
:DevcontainerTestNearestTerminal
:DevcontainerTestFileTerminal
:DevcontainerTestSuiteTerminal
```

**Output modes:**
- Default commands show output in Neovim's buffer with clear container indicators (🐳 Running test in container: xxx)
- Terminal commands open the container terminal and run tests interactively with real-time output

### Manual test execution

You can also run tests manually in the container:

```vim
" Open container terminal
:DevcontainerTerminal

" In the terminal, run:
go test -v ./...

" Run specific test
go test -v -run TestCalculatorAdd

" Run benchmarks
go test -bench=.
```

## Test Structure

- `calculator_test.go` - Tests for Calculator type
  - Table-driven tests
  - Error handling tests
  - Integration tests
  - Benchmark tests

- `string_utils_test.go` - Tests for string utilities
  - Unicode handling
  - Edge cases
  - Performance benchmarks

## How It Works

1. When you run a test command, devcontainer.nvim:
   - Detects the test at cursor position (for TestNearest)
   - Builds the appropriate `go test` command
   - Executes it inside the container using Docker exec
   - Displays results in Neovim buffer or terminal

2. **Buffer mode** (default commands):
   - Runs tests asynchronously in the background
   - Shows output in Neovim's message area with container indicators (🐳 Running test in container: xxx)
   - Non-interactive but integrated with Neovim's UI

3. **Terminal mode** (Terminal-suffixed commands):
   - Opens or reuses a dedicated test terminal window split
   - Runs tests interactively in the container terminal
   - Silent execution - no messages in Neovim, all output appears in terminal
   - Real-time output and interaction capabilities  
   - Reuses the same terminal session for repeated test runs
   - Useful for debugging and interactive testing

4. Test integration automatically:
   - Sets up vim-test strategy to use container
   - Configures environment variables
   - Uses the correct user context

## Debugging Tests

To debug why a test might be failing:

```vim
" Check container status
:DevcontainerStatus

" View container logs
:DevcontainerLogs

" Check test integration setup
:DevcontainerTestSetup
```

## Tips

- Use `:DevcontainerTestNearest` while developing to quickly run single tests
- Use `:DevcontainerTestFile` to verify all tests in current file pass
- Use `:DevcontainerTestSuite` before committing to ensure everything works
