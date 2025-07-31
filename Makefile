# Makefile for container.nvim

.PHONY: help lint lint-fix format format-check test test-unit test-integration test-e2e test-e2e-sequential test-quick test-coverage test-coverage-check install-dev clean install-hooks help-tags pre-commit coverage-report coverage-quick coverage-detailed

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
	@echo "  test         Run all tests (unit + integration + e2e)"
	@echo "  test-unit    Run unit tests only"
	@echo "  test-integration Run integration tests only (includes async operations and error scenarios)"
	@echo "  test-e2e     Run end-to-end tests in parallel (requires Docker)"
	@echo "  test-e2e-sequential Run end-to-end tests sequentially (slower)"
	@echo "  test-quick   Run essential tests for development"
	@echo "  test-coverage Run tests with coverage measurement"
	@echo "  test-coverage-check Run tests with coverage and fail if below 70%"
	@echo "  coverage-detailed Generate detailed line-by-line coverage analysis"
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

# Run all tests
test: test-unit test-integration test-e2e
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
			if LUA_PATH="./lua/?.lua;./lua/?/init.lua;$$LUA_PATH" lua "$$test_file"; then \
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

# Run integration tests (lightweight, no real containers)
test-integration:
	@echo "Running integration tests..."
	@if [ ! -d "test/integration" ]; then \
		echo "No integration tests found."; \
		exit 0; \
	fi
	@failed=0; \
	integration_tests="test_docker_integration.lua test_main_api.lua test_lsp_real.lua test_async_operations_simplified.lua test_error_scenarios_simplified.lua"; \
	for test_name in $$integration_tests; do \
		test_file="test/integration/$$test_name"; \
		if [ -f "$$test_file" ]; then \
			echo "=== Running integration test: $$test_name ==="; \
			if [ "$$test_name" = "test_lsp_real.lua" ] || [ "$$test_name" = "test_async_operations_simplified.lua" ] || [ "$$test_name" = "test_error_scenarios_simplified.lua" ]; then \
				if nvim --headless -u NONE -c "lua dofile('$$test_file')" -c "qa" 2>/dev/null; then \
					echo "✓ $$test_name PASSED"; \
				else \
					echo "✗ $$test_name FAILED"; \
					failed=$$((failed + 1)); \
				fi; \
			else \
				if lua "$$test_file"; then \
					echo "✓ $$test_name PASSED"; \
				else \
					echo "✗ $$test_name FAILED"; \
					failed=$$((failed + 1)); \
				fi; \
			fi; \
			echo ""; \
		else \
			echo "⚠ Test file not found: $$test_file"; \
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

# Run end-to-end tests (real Neovim commands with actual containers)
test-e2e:
	@echo "Running end-to-end tests with real Neovim commands..."
	@if [ ! -d "test/e2e" ]; then \
		echo "No E2E tests found."; \
		exit 0; \
	fi
	@if [ ! -f "test/e2e/run_test.lua" ]; then \
		echo "Error: E2E test runner not found (test/e2e/run_test.lua)."; \
		exit 1; \
	fi
	@echo "Starting E2E test runner..."
	lua test/e2e/run_test.lua

# Run end-to-end tests sequentially (slower but available as fallback)
test-e2e-sequential:
	@echo "Running end-to-end tests sequentially..."
	@if [ ! -d "test/e2e" ]; then \
		echo "No E2E tests found."; \
		exit 0; \
	fi
	@if [ ! -f "test/e2e/run_test_sequential.lua" ]; then \
		echo "Error: Sequential E2E test runner not found (test/e2e/run_test_sequential.lua)."; \
		exit 1; \
	fi
	@echo "Starting sequential E2E test runner..."
	lua test/e2e/run_test_sequential.lua

# Quick test for development (essential tests only)
test-quick: test-unit test-integration
	@echo "Quick development tests completed!"

# Test with coverage measurement
test-coverage:
	@echo "Running tests with coverage measurement..."
	@export PATH="$$HOME/.luarocks/bin:$$PATH"; \
	if [ ! -f "$$HOME/.luarocks/bin/luacov" ] && ! command -v luacov >/dev/null 2>&1; then \
		echo "Warning: luacov not found. Install with: luarocks install --local luacov"; \
		echo "Running tests without coverage..."; \
		make test; \
	else \
		echo "Cleaning previous coverage data..."; \
		rm -f luacov.stats.out luacov.report.out; \
		echo "Setting up Lua path for coverage..."; \
		export LUA_PATH="./lua/?.lua;./lua/?/init.lua;$$(luarocks path --lr-path)"; \
		export LUA_CPATH="$$(luarocks path --lr-cpath)"; \
		echo "Running unit tests with coverage..."; \
		if [ -d "test/unit" ] && [ -n "$$(ls test/unit/*.lua 2>/dev/null)" ]; then \
			for test_file in test/unit/*.lua; do \
				echo "  Coverage testing: $$(basename $$test_file)"; \
				lua -lluacov "$$test_file" || echo "  Warning: Test failed but continuing coverage"; \
			done; \
		fi; \
		echo "Running integration tests with coverage..."; \
		integration_tests="test_docker_integration.lua test_main_api.lua"; \
		for test_name in $$integration_tests; do \
			test_file="test/integration/$$test_name"; \
			if [ -f "$$test_file" ]; then \
				echo "  Coverage testing: $$test_name"; \
				lua -lluacov "$$test_file" || echo "  Warning: Test failed but continuing coverage"; \
			fi; \
		done; \
		echo "Generating coverage report..."; \
		if [ -f "$$HOME/.luarocks/bin/luacov" ]; then \
			$$HOME/.luarocks/bin/luacov; \
		elif command -v luacov >/dev/null 2>&1; then \
			luacov; \
		else \
			echo "Error: luacov command not found"; \
			exit 1; \
		fi; \
		echo "Coverage report generated: luacov.report.out"; \
		if [ -f luacov.report.out ]; then \
			echo "=== Coverage Summary ==="; \
			echo "Coverage Report for container.nvim"; \
			echo "===================================="; \
			echo ""; \
			echo "Overall Coverage Statistics:"; \
			tail -15 luacov.report.out | grep -A 20 "Summary" || tail -15 luacov.report.out; \
			echo ""; \
			echo "📊 Key Modules Coverage:"; \
			grep "lua/container" luacov.report.out | grep -E "\.[0-9]+%" | head -8; \
			echo ""; \
			echo "📁 Full report: luacov.report.out"; \
			echo "📈 Raw data: luacov.stats.out"; \
			echo ""; \
			total_coverage=$$(tail -1 luacov.report.out | grep -o '[0-9]*\.[0-9]*%' | tail -1); \
			if [ -n "$$total_coverage" ]; then \
				coverage_num=$$(echo $$total_coverage | sed 's/%//'); \
				if [ "$$(echo "$$coverage_num >= 80" | bc -l 2>/dev/null || echo 0)" = "1" ]; then \
					echo "🎉 Excellent coverage: $$total_coverage"; \
				elif [ "$$(echo "$$coverage_num >= 70" | bc -l 2>/dev/null || echo 0)" = "1" ]; then \
					echo "✅ Good coverage: $$total_coverage"; \
				elif [ "$$(echo "$$coverage_num >= 50" | bc -l 2>/dev/null || echo 0)" = "1" ]; then \
					echo "⚠️  Moderate coverage: $$total_coverage"; \
				else \
					echo "❌ Low coverage: $$total_coverage - improvement needed"; \
				fi; \
			fi; \
		else \
			echo "Warning: Coverage report not generated"; \
		fi; \
	fi

# Test with coverage and fail if below threshold
test-coverage-check:
	@echo "Running tests with coverage check (threshold: 70%)..."
	@./scripts/check_coverage.sh

# Clean temporary files
clean:
	@echo "Cleaning temporary files..."
	find . -name "*.tmp" -delete
	find . -name "*.bak" -delete
	rm -f luacov.stats.out luacov.report.out
	@echo "Temporary files and coverage data cleaned!"

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

# Generate coverage report from existing luacov.stats.out
coverage-report:
	@echo "Generating coverage report..."
	@if [ ! -f "luacov.stats.out" ]; then \
		echo "Error: luacov.stats.out not found. Run 'make test-coverage' first."; \
		exit 1; \
	fi
	@export LUA_PATH="./lua/?.lua;./lua/?/init.lua;$$HOME/.luarocks/share/lua/5.4/?.lua;$$HOME/.luarocks/share/lua/5.4/?/init.lua" && \
	export LUA_CPATH="$$HOME/.luarocks/lib/lua/5.4/?.so" && \
	$$HOME/.luarocks/bin/luacov
	@if [ -f "luacov.report.out" ]; then \
		echo "Coverage report generated successfully:"; \
		echo ""; \
		tail -1 luacov.report.out | grep "Total"; \
		echo ""; \
		echo "Full report: luacov.report.out"; \
	else \
		echo "Error: Failed to generate coverage report"; \
		exit 1; \
	fi

# Quick coverage check - run essential tests and generate report
coverage-quick:
	@echo "Running quick tests with coverage..."
	@export LUA_PATH="./lua/?.lua;./lua/?/init.lua;$$HOME/.luarocks/share/lua/5.4/?.lua;$$HOME/.luarocks/share/lua/5.4/?/init.lua" && \
	export LUA_CPATH="$$HOME/.luarocks/lib/lua/5.4/?.so" && \
	rm -f luacov.stats.out luacov.report.out && \
	lua -lluacov test/unit/test_config_core.lua && \
	lua -lluacov test/unit/test_basic.lua && \
	lua -lluacov test/unit/test_fs_comprehensive.lua && \
	lua -lluacov test/unit/test_environment_comprehensive.lua && \
	lua -lluacov test/unit/test_stage1_immediate.lua && \
	lua -lluacov test/unit/test_stage2_docker_basics.lua && \
	lua -lluacov test/unit/test_stage3_lsp_basics.lua && \
	lua -lluacov test/unit/test_docker_comprehensive_boost.lua && \
	lua -lluacov test/unit/test_init_comprehensive_boost.lua && \
	$$HOME/.luarocks/bin/luacov
	@if [ -f "luacov.report.out" ]; then \
		echo ""; \
		echo "=== Quick Coverage Report ==="; \
		tail -1 luacov.report.out | grep "Total"; \
		echo "Full report: luacov.report.out"; \
	else \
		echo "Error: Failed to generate quick coverage report"; \
		exit 1; \
	fi

# Generate HTML coverage report with line-by-line visualization
coverage-detailed:
	@echo "Generating detailed line-by-line coverage analysis..."
	@echo "Running complete test suite for accurate coverage measurement..."
	@$(MAKE) test-coverage
	@echo ""
	@echo "📊 Detailed Coverage Analysis Generated:"
	@echo "   • Line-by-line report: luacov.report.out"
	@echo "     - Numbers show execution count per line"
	@echo "     - Blank lines were not executed (need testing)"
	@echo "   • Raw coverage data: luacov.stats.out"
	@echo ""
	@echo "🔍 Quick analysis commands:"
	@echo "   • View specific file: grep -A 50 'lua/container/[filename]' luacov.report.out"
	@echo "   • Find untested lines: grep -n '^[ ]*$$' luacov.report.out"
	@echo "   • Coverage summary: make coverage-quick"
