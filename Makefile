# Makefile for devcontainer.nvim

.PHONY: help lint lint-fix test install-dev clean install-hooks

# Default target
help:
	@echo "devcontainer.nvim Development Commands"
	@echo ""
	@echo "Available targets:"
	@echo "  help         Show this help message"
	@echo "  lint         Run luacheck on all Lua files"
	@echo "  lint-fix     Run luacheck and attempt to fix some issues"
	@echo "  test         Run test suite"
	@echo "  install-dev  Install development dependencies"
	@echo "  install-hooks Install pre-commit hooks"
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

# Run tests
test:
	@echo "Running test suite..."
	cd test && lua test_mock.lua

# Clean temporary files
clean:
	@echo "Cleaning temporary files..."
	find . -name "*.tmp" -delete
	find . -name "*.bak" -delete

# Lint before commit (git hook helper)
pre-commit: lint test
	@echo "Pre-commit checks passed!"
