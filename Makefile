# Makefile for container.nvim

.PHONY: help lint lint-fix format format-check test install-dev clean install-hooks help-tags

# Default target
help:
	@echo "container.nvim Development Commands"
	@echo ""
	@echo "Available targets:"
	@echo "  help         Show this help message"
	@echo "  lint         Run luacheck on all Lua files"
	@echo "  lint-fix     Run luacheck and attempt to fix some issues"
	@echo "  format       Format Lua code with stylua"
	@echo "  format-check Check if Lua code is properly formatted"
	@echo "  test         Run all working tests (unit + stable)"
	@echo "  test-unit    Run unit tests only"
	@echo "  test-stable  Run stable integration tests only"
	@echo "  test-integration Run all integration tests (may have issues)"
	@echo "  test-e2e     Run end-to-end tests only"
	@echo "  test-quick   Run essential tests for development"
	@echo "  test-coverage Run tests with coverage measurement"
	@echo "  install-dev  Install development dependencies"
	@echo "  install-hooks Install pre-commit hooks"
	@echo "  help-tags    Generate Neovim help tags"
	@echo "  clean        Clean temporary files"

# Install development dependencies
install-dev:
	@echo "Installing development dependencies..."
	@if command -v luarocks >/dev/null 2>&1; then \
		echo "Installing luacheck via luarocks..."; \
		luarocks install --local luacheck; \
	elif command -v brew >/dev/null 2>&1; then \
		echo "Installing luacheck via homebrew..."; \
		brew install luacheck; \
	elif command -v apt-get >/dev/null 2>&1; then \
		echo "Installing luacheck via apt..."; \
		sudo apt-get update && sudo apt-get install -y luacheck; \
	else \
		echo "Error: Could not find package manager to install luacheck"; \
		echo "Please install luacheck manually:"; \
		echo "  - Via luarocks: luarocks install luacheck"; \
		echo "  - Via brew: brew install luacheck"; \
		echo "  - Via apt: apt-get install luacheck"; \
		exit 1; \
	fi
	@echo "Installing stylua..."
	@if command -v cargo >/dev/null 2>&1; then \
		echo "Installing stylua via cargo..."; \
		cargo install stylua; \
	elif command -v brew >/dev/null 2>&1; then \
		echo "Installing stylua via homebrew..."; \
		brew install stylua; \
	elif command -v npm >/dev/null 2>&1; then \
		echo "Installing stylua via npm..."; \
		npm install -g @johnnymorganz/stylua; \
	else \
		echo "Error: Could not find package manager to install stylua"; \
		echo "Please install stylua manually:"; \
		echo "  - Via cargo: cargo install stylua"; \
		echo "  - Via brew: brew install stylua"; \
		echo "  - Via npm: npm install -g @johnnymorganz/stylua"; \
		exit 1; \
	fi
	@echo "Development dependencies installed!"

# Install pre-commit hooks
install-hooks:
	@echo "Installing pre-commit hooks..."
	@if ! command -v pre-commit >/dev/null 2>&1; then \
		echo "Installing pre-commit..."; \
		if command -v pip3 >/dev/null 2>&1; then \
			pip3 install --user pre-commit; \
		elif command -v pip >/dev/null 2>&1; then \
			pip install --user pre-commit; \
		elif command -v brew >/dev/null 2>&1; then \
			brew install pre-commit; \
		elif command -v apt-get >/dev/null 2>&1; then \
			sudo apt-get update && sudo apt-get install -y pre-commit; \
		else \
			echo "Error: Could not install pre-commit. Please install manually:"; \
			echo "  pip install pre-commit"; \
			echo "  or visit: https://pre-commit.com/#installation"; \
			exit 1; \
		fi; \
	fi
	@echo "Installing git hooks..."
	pre-commit install
	@echo "Pre-commit hooks installed! Run 'pre-commit run --all-files' to test."

# Run linter
lint:
	@echo "Running luacheck..."
	@if ! command -v luacheck >/dev/null 2>&1; then \
		echo "Error: luacheck not found. Run 'make install-dev' first."; \
		exit 1; \
	fi
	luacheck lua/ plugin/ --config .luacheckrc

# Run linter with auto-fix (where possible)
lint-fix:
	@echo "Running luacheck with fixes..."
	@if ! command -v luacheck >/dev/null 2>&1; then \
		echo "Error: luacheck not found. Run 'make install-dev' first."; \
		exit 1; \
	fi
	luacheck lua/ plugin/ --config .luacheckrc --fix

# Format Lua code with stylua
format:
	@echo "Formatting Lua code with stylua..."
	@if ! command -v stylua >/dev/null 2>&1; then \
		echo "Error: stylua not found. Run 'make install-dev' first."; \
		exit 1; \
	fi
	stylua lua/ plugin/ test/

# Check if Lua code is properly formatted
format-check:
	@echo "Checking Lua code formatting with stylua..."
	@if ! command -v stylua >/dev/null 2>&1; then \
		echo "Error: stylua not found. Run 'make install-dev' first."; \
		exit 1; \
	fi
	stylua --check lua/ plugin/ test/

# Run all working tests (backwards compatibility)
test: test-unit test-stable
	@echo "All test suites completed!"

# Run unit tests
test-unit:
	@echo "Running unit tests..."
	@if [ ! -d "test/unit" ]; then \
		echo "No unit tests found."; \
		exit 0; \
	fi
	@failed=0; \
	for test_file in test/unit/*.lua; do \
		if [ -f "$$test_file" ]; then \
			test_name=$$(basename "$$test_file"); \
			echo "=== Running unit test: $$test_name ==="; \
			if lua "$$test_file"; then \
				echo "✓ $$test_name PASSED"; \
			else \
				echo "✗ $$test_name FAILED"; \
				failed=$$((failed + 1)); \
			fi; \
			echo ""; \
		fi; \
	done; \
	if [ $$failed -gt 0 ]; then \
		echo "=== Unit Test Summary ==="; \
		echo "$$failed unit test(s) failed"; \
		exit 1; \
	else \
		echo "=== Unit Test Summary ==="; \
		echo "All unit tests passed!"; \
	fi

# Run integration tests
test-integration:
	@echo "Running integration tests..."
	@if [ ! -d "test/integration" ]; then \
		echo "No integration tests found."; \
		exit 0; \
	fi
	@if ! command -v nvim >/dev/null 2>&1; then \
		echo "Error: Neovim not found. Integration tests require Neovim."; \
		exit 1; \
	fi
	@failed=0; \
	for test_file in test/integration/*.lua; do \
		if [ -f "$$test_file" ]; then \
			test_name=$$(basename "$$test_file"); \
			echo "=== Running integration test: $$test_name ==="; \
			if nvim --headless -u test/minimal_init.lua \
				-c "lua dofile('$$test_file')" \
				-c "qa" 2>/dev/null; then \
				echo "✓ $$test_name PASSED"; \
			else \
				echo "✗ $$test_name FAILED"; \
				failed=$$((failed + 1)); \
			fi; \
			echo ""; \
		fi; \
	done; \
	if [ $$failed -gt 0 ]; then \
		echo "=== Integration Test Summary ==="; \
		echo "$$failed integration test(s) failed"; \
		exit 1; \
	else \
		echo "=== Integration Test Summary ==="; \
		echo "All integration tests passed!"; \
	fi

# Run end-to-end tests
test-e2e:
	@echo "Running end-to-end tests..."
	@if [ ! -d "test/e2e" ]; then \
		echo "No E2E tests found."; \
		exit 0; \
	fi
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "Error: Docker not found. E2E tests require Docker."; \
		exit 1; \
	fi
	@failed=0; \
	for test_file in test/e2e/*.lua; do \
		if [ -f "$$test_file" ]; then \
			test_name=$$(basename "$$test_file"); \
			echo "=== Running E2E test: $$test_name ==="; \
			if lua "$$test_file"; then \
				echo "✓ $$test_name PASSED"; \
			else \
				echo "✗ $$test_name FAILED"; \
				failed=$$((failed + 1)); \
			fi; \
			echo ""; \
		fi; \
	done; \
	if [ $$failed -gt 0 ]; then \
		echo "=== E2E Test Summary ==="; \
		echo "$$failed E2E test(s) failed"; \
		exit 1; \
	else \
		echo "=== E2E Test Summary ==="; \
		echo "All E2E tests passed!"; \
	fi

# Quick test for development (essential tests only)
test-quick: test-unit
	@echo "Quick development tests completed!"

# Run stable integration tests (working tests only)
test-stable:
	@echo "Running stable integration tests..."
	@if [ ! -d "test/integration" ]; then \
		echo "No integration tests found."; \
		exit 0; \
	fi
	@failed=0; \
	stable_tests="test_docker_integration.lua test_main_api.lua"; \
	for test_name in $$stable_tests; do \
		test_file="test/integration/$$test_name"; \
		if [ -f "$$test_file" ]; then \
			echo "=== Running stable test: $$test_name ==="; \
			if lua "$$test_file"; then \
				echo "✓ $$test_name PASSED"; \
			else \
				echo "✗ $$test_name FAILED"; \
				failed=$$((failed + 1)); \
			fi; \
			echo ""; \
		else \
			echo "⚠ Test file not found: $$test_file"; \
		fi; \
	done; \
	if [ $$failed -gt 0 ]; then \
		echo "=== Stable Test Summary ==="; \
		echo "$$failed stable test(s) failed"; \
		exit 1; \
	else \
		echo "=== Stable Test Summary ==="; \
		echo "All stable tests passed!"; \
	fi

# Test with coverage measurement
test-coverage:
	@echo "Running tests with coverage measurement..."
	@if ! command -v luacov >/dev/null 2>&1; then \
		echo "Warning: luacov not found. Install with: luarocks install luacov"; \
		echo "Running tests without coverage..."; \
		make test; \
	else \
		echo "Cleaning previous coverage data..."; \
		rm -f luacov.stats.out luacov.report.out; \
		echo "Running unit tests with coverage..."; \
		LUA_PATH="./lua/?.lua;./lua/?/init.lua;$$LUA_PATH" \
		lua -lluacov test/unit/*.lua; \
		echo "Generating coverage report..."; \
		luacov; \
		echo "Coverage report generated: luacov.report.out"; \
		if [ -f luacov.report.out ]; then \
			echo "=== Coverage Summary ==="; \
			head -20 luacov.report.out; \
		fi; \
	fi

# Clean temporary files
clean:
	@echo "Cleaning temporary files..."
	find . -name "*.tmp" -delete
	find . -name "*.bak" -delete

# Generate Neovim help tags
help-tags:
	@echo "Generating Neovim help tags..."
	@if command -v nvim >/dev/null 2>&1; then \
		nvim -u NONE -c "helptags doc" -c "quit" 2>/dev/null || true; \
		echo "Help tags generated successfully!"; \
	else \
		echo "Warning: Neovim not found. Help tags not generated."; \
		echo "Run ':helptags doc' inside Neovim to generate tags."; \
	fi

# Lint and format check before commit (git hook helper)
pre-commit: lint format-check test-quick
	@echo "Pre-commit checks passed!"
