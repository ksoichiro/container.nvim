.PHONY: test test-verbose test-coverage bench clean help

# Default target
.DEFAULT_GOAL := help

## test: Run all tests
test:
	@go test ./...

## test-verbose: Run all tests with verbose output
test-verbose:
	@go test -v ./...

## test-coverage: Run tests with coverage report
test-coverage:
	@go test -cover ./...
	@go test -coverprofile=coverage.out ./...
	@go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report generated: coverage.html"

## bench: Run benchmark tests
bench:
	@go test -bench=. -benchmem ./...

## test-specific: Run specific test by name (usage: make test-specific TEST=TestCalculatorAdd)
test-specific:
	@go test -v -run $(TEST) ./...

## clean: Clean test artifacts
clean:
	@rm -f coverage.out coverage.html

## help: Show this help message
help:
	@echo "Available targets:"
	@grep -E '^##' $(MAKEFILE_LIST) | sed 's/## /  /'
