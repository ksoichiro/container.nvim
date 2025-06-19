# Go Example for container.nvim

This is a Go example project for testing container.nvim functionality, particularly useful for testing external plugin integration like nvim-test.

## Features

- **HTTP Server**: Simple REST API using Gin framework
- **Calculator Logic**: Basic math operations with history tracking
- **Comprehensive Tests**: Unit tests, table-driven tests, and benchmarks
- **LSP Integration**: Demonstrates Go LSP (gopls) working in container
- **Debugging Ready**: Includes Delve debugger installation

## Project Structure

```
go-example/
├── .devcontainer/
│   └── devcontainer.json     # Container configuration
├── main.go                   # Main application code
├── main_test.go             # Comprehensive test suite
├── go.mod                   # Go module definition
└── README.md               # This file
```

## devcontainer.json Features

- **Base Image**: Official Go devcontainer (Go 1.23)
- **Tools Installation**:
  - `gopls` (Go LSP server)
  - `dlv` (Delve debugger)
- **Port Forwarding**: 8080 (HTTP server), 2345 (debugger)
- **Extensions**: Go extension recommendations for VSCode compatibility

## Testing with nvim-test Integration

This example is designed to test the planned nvim-test integration:

### Current Manual Testing
```bash
# Run all tests
go test ./...

# Run specific test
go test -run TestCreateGreeting

# Run benchmarks
go test -bench=.

# Verbose output
go test -v
```

### Future nvim-test Integration
Once the external plugin integration is implemented, you'll be able to:

```vim
" Run nearest test (cursor on test function)
:TestNearest

" Run current file tests
:TestFile

" Run all tests in project
:TestSuite

" Run last test again
:TestLast
```

These commands will automatically execute inside the devcontainer.

## API Endpoints

The HTTP server provides several endpoints for testing:

- `GET /` - Welcome message with timestamp
- `POST /calculate/sum` - Calculate sum of numbers array
- `POST /calculate/add` - Add two numbers
- `POST /calculate/multiply` - Multiply two numbers
- `GET /users/:id` - Demo user endpoint

## LSP Features to Test

1. **Go to Definition**: Click on function calls
2. **Auto-completion**: Type `calc.` to see methods
3. **Hover Information**: Hover over functions for documentation
4. **Error Detection**: Syntax and type errors are highlighted
5. **Code Actions**: Refactoring and quick fixes

## Development Workflow

1. Open project in container:
   ```vim
   :ContainerOpen
   :ContainerStart
   ```

2. LSP should automatically start with gopls

3. Test the server:
   ```bash
   go run main.go
   # Server starts on :8080
   ```

4. Run tests:
   ```bash
   go test -v
   ```

5. Test LSP integration:
   - Open `main.go`
   - Try completion, go-to-definition, hover
   - Open `main_test.go` and run individual tests

## Debugging Setup

The container includes Delve debugger. For future DAP integration:

```vim
" Set breakpoint (future DAP integration)
:DapToggleBreakpoint

" Start debugging (future DAP integration)
:DapContinue
```

## nvim-test Integration Testing

This project provides various test scenarios for testing nvim-test integration:

1. **Single Function Tests**: `TestCreateGreeting`
2. **Table-Driven Tests**: `TestCalculateSum`
3. **Subtests**: Tests with `t.Run()`
4. **Method Tests**: `TestCalculatorAdd`
5. **Benchmark Tests**: `BenchmarkCalculateSum`

Perfect for verifying that `:TestNearest`, `:TestFile`, and `:TestSuite` work correctly in the container environment.
