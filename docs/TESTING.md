# Testing Guide for container.nvim

This document describes the testing strategy and how to run different types of tests for container.nvim.

## Test Categories

### 1. Unit Tests (`test/unit/`)
Test individual components in isolation without external dependencies.

- **test_config.lua** - Configuration parsing and validation
- **test_parser.lua** - DevContainer.json parsing logic
- **test_environment.lua** - Environment variable handling
- **test_log_utils.lua** - Logging utilities
- **test_port_utils.lua** - Port allocation logic
- **test_api.lua** - Public API surface
- **test_docker_operations.lua** - Docker command building and validation

**Run unit tests:**
```bash
make test-unit
```

### 2. Integration Tests (`test/integration/`)
Test components working together, may require external dependencies.

- **test_parser_integration.lua** - Parser with real devcontainer.json files
- **real_container_test.lua** - **NEW** Real Docker container creation and verification

**Run all integration tests:**
```bash
make test-integration
```

**Run only real container tests:**
```bash
make test-real-containers
```

### 3. End-to-End Tests (`test/e2e/`)
Test complete workflows using the full plugin.

- **test_full_workflow.lua** - Complete devcontainer lifecycle

**Run E2E tests:**
```bash
make test-e2e
```

## Real Container Testing

### Overview
The new `test/integration/real_container_test.lua` provides comprehensive testing of actual Docker container creation and management.

### What it Tests
1. **Complete Container Lifecycle**
   - Plugin setup and configuration loading
   - Image preparation (pull/build)
   - Container creation with proper naming
   - Container startup and status verification
   - Command execution inside containers
   - File system mounting verification
   - Container cleanup

2. **Docker Operations Verification**
   - Docker availability checking
   - Image existence and pulling
   - Container command argument building
   - Container status monitoring

3. **Error Handling**
   - Invalid configuration handling
   - Docker daemon connectivity issues
   - Container creation failures

### Prerequisites
- Docker installed and daemon running
- Network access for image pulling
- Sufficient disk space for test containers

### Test Execution
```bash
# Run real container tests only
make test-real-containers

# Run all tests including real containers  
make test-integration
```

### Test Artifacts
The test creates temporary containers with names like:
- `container-nvim-test-*`
- `simple-test-*`

These are automatically cleaned up after tests complete.

## Previous Testing Issues

### Why E2E Tests Don't Create Containers
The existing E2E tests (`test/e2e/test_full_workflow.lua`) have several limitations:

1. **Insufficient Waiting Time**: Only waits 10 seconds for container creation, but real workflows including image pulling can take minutes.

2. **Error Suppression**: Uses `pcall()` to catch errors but doesn't verify actual execution results.

3. **Missing Project Structure**: Tests rely on example projects that may not exist in test environments.

4. **Async Handling**: Doesn't properly wait for async operations to complete.

### Improvements in Real Container Tests

The new real container tests address these issues:

1. **Extended Timeouts**: Waits up to 3 minutes for container operations.

2. **Actual Verification**: Checks `docker ps` output to verify container creation.

3. **Self-Contained**: Creates its own test project with valid devcontainer.json.

4. **Comprehensive Cleanup**: Ensures no test artifacts remain after execution.

5. **Progressive Verification**: Tests each step of the workflow independently.

## Running Tests in CI/CD

### Recommended Test Sequence
```bash
# Fast tests for development
make test-quick

# Complete verification (requires Docker)
make test-unit
make test-real-containers
make test-e2e
```

### CI Environment Considerations
- Ensure Docker daemon is available
- Allow sufficient time for image pulls (first run)
- Monitor disk space usage
- Clean up containers between test runs

## Debugging Test Failures

### Unit Test Failures
- Check Lua syntax and require paths
- Verify mock setup is correct
- Review error messages for missing dependencies

### Integration Test Failures  
- Verify Docker is installed and running: `docker ps`
- Check network connectivity: `docker pull alpine:latest`
- Review test output for timeout issues
- Check available disk space: `df -h`

### E2E Test Failures
- Ensure valid devcontainer.json exists in test project
- Check Docker image availability
- Verify container naming conventions
- Review async operation timing

## Test Development Guidelines

### Adding New Unit Tests
1. Create test file in `test/unit/`
2. Use helper functions from `test/helpers/init.lua`
3. Mock external dependencies
4. Test both success and failure cases

### Adding New Integration Tests
1. Create test file in `test/integration/`
2. Include cleanup procedures
3. Use realistic test data
4. Handle Docker availability gracefully

### Adding New E2E Tests
1. Create complete test scenarios
2. Include proper async handling
3. Verify actual outcomes, not just completion
4. Clean up all test artifacts

## Performance Considerations

### Test Execution Times
- Unit tests: < 1 second each
- Integration tests: 10-60 seconds each
- Real container tests: 1-5 minutes
- E2E tests: 2-10 minutes

### Resource Usage
- Unit tests: Minimal
- Integration tests: May pull Docker images (100MB+)
- Real container tests: Creates temporary containers
- E2E tests: Full workflow resource usage

## Conclusion

The new real container testing provides confidence that container.nvim actually creates and manages Docker containers correctly. This addresses the gap between unit tests (which mock everything) and E2E tests (which had verification issues).

For development, use `make test-quick` for rapid feedback. For release verification, use `make test-real-containers` to ensure Docker integration works correctly.
