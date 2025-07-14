#!/bin/bash

# check_coverage.sh
# Script to check test coverage and fail if below threshold

set -e

COVERAGE_THRESHOLD=70
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Checking test coverage for container.nvim..."
echo "Coverage threshold: ${COVERAGE_THRESHOLD}%"
echo ""

# Change to project root
cd "${PROJECT_ROOT}"

# Run coverage measurement
echo "Running tests with coverage measurement..."
make test-coverage > /dev/null 2>&1 || {
    echo "Error: Failed to run coverage tests"
    exit 1
}

# Check if coverage report exists
if [ ! -f "luacov.report.out" ]; then
    echo "Error: Coverage report not found (luacov.report.out)"
    exit 1
fi

# Extract coverage percentage from the report
# luacov outputs the total coverage in the last line as "Total    X    Y    Z.ZZ%"
coverage_line=$(tail -1 luacov.report.out)
coverage_percent=$(echo "$coverage_line" | grep -o '[0-9]\+\.[0-9]\+%' | tail -1)

if [ -z "$coverage_percent" ]; then
    echo "Error: Could not parse coverage percentage from report"
    echo "Last line of report: $coverage_line"
    exit 1
fi

# Extract numeric value (remove % sign)
coverage_num=$(echo "$coverage_percent" | sed 's/%//')

echo "=== Coverage Check Result ==="
echo "Current coverage: $coverage_percent"
echo "Required threshold: ${COVERAGE_THRESHOLD}%"
echo ""

# Use bc for floating point comparison if available, otherwise use awk
if command -v bc >/dev/null 2>&1; then
    comparison_result=$(echo "$coverage_num >= $COVERAGE_THRESHOLD" | bc -l)
else
    comparison_result=$(awk "BEGIN { print ($coverage_num >= $COVERAGE_THRESHOLD) ? 1 : 0 }")
fi

if [ "$comparison_result" = "1" ]; then
    echo "✅ Coverage check PASSED: $coverage_percent meets the ${COVERAGE_THRESHOLD}% threshold"
    exit 0
else
    echo "❌ Coverage check FAILED: $coverage_percent is below the ${COVERAGE_THRESHOLD}% threshold"
    echo ""
    echo "To fix this issue:"
    echo "1. Add tests for uncovered code"
    echo "2. Review coverage report: luacov.report.out"
    echo "3. Focus on modules with low coverage"
    echo ""
    exit 1
fi
