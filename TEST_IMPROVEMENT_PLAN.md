# Test Improvement Plan for container.nvim

## Executive Summary

This document outlines a comprehensive plan to improve the testing infrastructure and coverage for container.nvim. The current manual testing workflow after Claude Code implementation is highly inefficient and poses risks to code quality and development velocity.

## Current State Analysis

### Test Coverage Assessment

| Module | Current Coverage | Missing Critical Features |
|--------|------------------|---------------------------|
| `lua/container/init.lua` (Main API) | ~30% | `setup()`, `open()`, `build()`, `start()`, `stop()`, state management |
| `lua/container/docker/init.lua` (Docker Integration) | ~10% | All core Docker operations, async commands, error handling |
| `lua/container/lsp/init.lua` (LSP Integration) | ~50% | Server detection, client creation, strategy system |
| `lua/container/terminal/init.lua` (Terminal Integration) | ~60% | Process management, error handling, cleanup |
| `lua/container/parser.lua` (Configuration Parser) | ~45% | JSON parsing, validation, variable expansion |

### Key Problems Identified

1. **Architectural Issues**
   - Over-reliance on mocking vs. real Neovim environment testing
   - Lack of integration tests for core functionality
   - Manual testing dependency creating development bottlenecks

2. **Critical Coverage Gaps**
   - Docker integration (most important feature) severely undertested
   - Asynchronous operations largely untested
   - Error handling and recovery scenarios missing
   - Complete container lifecycle flows untested

3. **Development Efficiency Impact**
   - Manual verification required after every Claude Code implementation
   - High risk of regressions
   - Difficult to ensure quality when adding new features

## Improvement Strategy

### Test Architecture Redesign

```
test/
├── unit/           # Unit tests (pure Lua functions, minimal mocking)
├── integration/    # Integration tests (headless Neovim, real components)
├── e2e/           # End-to-end tests (actual Docker containers)
├── fixtures/      # Test data and configurations
└── helpers/       # Common test utilities and helpers
```

### Testing Methodology Framework

1. **Unit Tests**: Pure function testing with minimal mocking
2. **Integration Tests**: Real Neovim environment with controlled dependencies
3. **E2E Tests**: Full workflow testing with actual Docker containers
4. **Local-First Approach**: Optimize for local development workflow

## Implementation Plan

### Phase 1: Foundation (2 weeks) - HIGHEST PRIORITY

#### 1.1 Test Infrastructure Setup
- Create new directory structure
- Implement test helpers and utilities
- Update Makefile with new test targets

#### 1.2 Docker Integration Testing (Critical Gap)
```lua
-- test/integration/test_docker_integration.lua
-- Test actual Docker command execution and container lifecycle
local tests = {
  test_docker_availability_check = function()
    local result = require('container.docker').check_docker_availability()
    assert(type(result) == 'boolean')
  end,

  test_container_lifecycle = function()
    -- Create → Start → Stop → Remove full cycle
    local docker = require('container.docker')
    local container_id = docker.create_container_async(test_config)
    assert(container_id ~= nil)

    local started = docker.start_container_async(container_id)
    assert(started == true)

    local stopped = docker.stop_container_async(container_id)
    assert(stopped == true)
  end
}
```

#### 1.3 Main API Integration Testing
```lua
-- test/integration/test_main_api.lua
-- Test public API workflows
local tests = {
  test_full_startup_flow = function()
    -- setup → open → build → start complete flow
    require('container').setup()
    require('container').open()
    require('container').build()
    local result = require('container').start()
    assert(result.success == true)
  end,

  test_error_handling = function()
    -- Invalid configuration handling
    local success, err = pcall(function()
      require('container').open('/invalid/path')
    end)
    assert(success == false)
    assert(err:match("devcontainer.json not found"))
  end
}
```

**Expected Impact**: Coverage increase from 30% to 70% for critical modules

### Phase 2: Enhanced Testing (1 month) - HIGH PRIORITY

#### 2.1 LSP Integration Testing
```lua
-- test/integration/test_lsp_real.lua
-- Real LSP server integration tests
local tests = {
  test_lsp_auto_detection = function()
    local lsp = require('container.lsp')
    local servers = lsp.detect_language_servers()
    assert(#servers > 0)
  end,

  test_lsp_client_creation = function()
    local client = lsp.create_lsp_client('pylsp', test_config)
    assert(client ~= nil)
    assert(client.is_ready() == true)
  end
}
```

#### 2.2 Asynchronous Operations Testing
```lua
-- Test async workflows with proper timing and callback verification
local async = require('container.utils.async')
local completed = false
async.run(function()
  -- Test async operations
  completed = true
end)
vim.wait(1000, function() return completed end)
assert(completed == true)
```

#### 2.3 Error Scenario Testing
```lua
-- Simulate various failure conditions
mock_docker_unavailable()
local success, err = container.start()
assert(success == false)
assert(err:match("Docker not available"))
```

### Phase 3: Quality Assurance (2 months) - MEDIUM PRIORITY

#### 3.1 End-to-End Testing
```bash
# test/e2e/test_full_workflow.sh
cd examples/python-example
nvim --headless -u NONE \
  -c "lua require('container').setup()" \
  -c "ContainerStart" \
  -c "sleep 5" \
  -c "ContainerStop" \
  -c "qa"
```

#### 3.2 Test Coverage Measurement
```lua
-- .luacov configuration
return {
  statsfile = "luacov.stats.out",
  reportfile = "luacov.report.out",
  include = {"lua/container"},
  exclude = {"test/", "examples/"},
  runreport = true,
}
```

#### 3.3 Performance and Stress Testing
```lua
-- test/performance/test_stress.lua
local function test_multiple_containers()
  local containers = {}
  for i = 1, 5 do
    containers[i] = require('container').start_async()
  end

  for i, container in ipairs(containers) do
    assert(container:wait(10000) == true)
  end
end
```

### Phase 4: Advanced Testing (3 months) - LOW PRIORITY

#### 4.1 Benchmark and Metrics
- Startup time benchmarking
- Memory usage monitoring
- Error rate measurement

#### 4.2 Compatibility Testing
- Multiple Neovim versions
- Different OS environments
- Various Docker configurations

## Local Development Focus

### Enhanced Makefile Targets
```makefile
# Local development optimized test commands
test-unit:
	@echo "Running unit tests..."
	@for test in test/unit/*.lua; do lua $$test; done

test-integration:
	@echo "Running integration tests..."
	@for test in test/integration/*.lua; do \
		nvim --headless -u NONE \
		-c "lua dofile('$$test')" \
		-c "qa"; \
	done

test-quick:
	@echo "Running essential tests for development..."
	@make test-unit
	@make test-integration

test-coverage:
	@echo "Generating coverage report..."
	@luacov && cat luacov.report.out

test-e2e:
	@echo "Running E2E tests..."
	@cd examples/$(EXAMPLE) && \
	nvim --headless -u NONE \
	-c "lua require('container').setup()" \
	-c "ContainerStart" \
	-c "sleep 5" \
	-c "ContainerStop" \
	-c "qa"
```

### Development Workflow Integration
1. **Pre-commit Testing**: `make test-quick` before commits
2. **Feature Testing**: `make test-integration` for new features
3. **Release Testing**: `make test-coverage && make test-e2e` before releases

## Success Metrics

### Quantitative Goals
- **Test Coverage**: 30% → 85%
- **Manual Testing Time**: 20 hours/week → 4 hours/week (80% reduction)
- **Regression Detection**: Reactive → Proactive

### Qualitative Improvements
- Confident refactoring capabilities
- Safe feature addition process
- Reduced bug reports from users
- Improved development velocity

## CI/CD Considerations (Future)

While GitHub Actions are low priority for the current single-developer workflow, the test structure should be designed to be CI/CD ready:

```yaml
# Future .github/workflows/test.yml structure
name: Tests
on: [push, pull_request]
jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run unit tests
        run: make test-unit

  integration-tests:
    runs-on: ubuntu-latest
    services:
      docker:
        image: docker:dind
    steps:
      - name: Setup Neovim
        uses: rhysd/action-setup-vim@v1
        with:
          neovim: true
      - name: Run integration tests
        run: make test-integration
```

## Implementation Priority Matrix

| Item | Priority | Implementation Cost | Expected Impact | ROI |
|------|----------|-------------------|-----------------|-----|
| Docker Integration Tests | Highest | Medium | High | High |
| Main API Tests | Highest | Medium | High | High |
| Test Infrastructure | High | Medium | High | High |
| LSP Integration Tests | High | High | Medium | Medium |
| Coverage Measurement | Medium | Low | Medium | High |
| E2E Tests | Medium | High | Medium | Medium |
| GitHub Actions | Low | High | Low | Low |

## Next Steps

1. **Immediate Action**: Implement Phase 1 Docker integration and Main API tests
2. **Short-term**: Complete test infrastructure and coverage measurement
3. **Medium-term**: Add comprehensive error handling and performance tests
4. **Long-term**: Evaluate CI/CD implementation based on team growth

This plan transforms the current inefficient manual testing workflow into a robust, automated quality assurance system optimized for local development.
