# Makefile for devcontainer.nvim

.PHONY: help lint lint-fix format format-check test install-dev clean install-hooks help-tags

# Default target
help:
	@echo "devcontainer.nvim Development Commands"
	@echo ""
	@echo "Available targets:"
	@echo "  help         Show this help message"
	@echo "  lint         Run luacheck on all Lua files"
	@echo "  lint-fix     Run luacheck and attempt to fix some issues"
	@echo "  format       Format Lua code with stylua"
	@echo "  format-check Check if Lua code is properly formatted"
	@echo "  test         Run test suite"
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

# Run tests
test:
	@echo "Running test suite..."
	@echo "Found test files:"
	@ls test/test_*.lua | sed 's|test/||'
	@echo ""
	@failed=0; \
	for test_file in test/test_*.lua; do \
		test_name=$$(basename "$$test_file"); \
		echo "=== Running $$test_name ==="; \
		if lua "$$test_file"; then \
			echo "✓ $$test_name PASSED"; \
		else \
			echo "✗ $$test_name FAILED"; \
			failed=$$((failed + 1)); \
		fi; \
		echo ""; \
	done; \
	if [ $$failed -gt 0 ]; then \
		echo "=== Test Summary ==="; \
		echo "$$failed test(s) failed"; \
		exit 1; \
	else \
		echo "=== Test Summary ==="; \
		echo "All tests passed!"; \
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
pre-commit: lint format-check test
	@echo "Pre-commit checks passed!"
