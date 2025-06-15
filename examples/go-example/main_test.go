package main

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestCreateGreeting(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "with name",
			input:    "Alice",
			expected: "Hello, Alice!",
		},
		{
			name:     "empty name defaults to World",
			input:    "",
			expected: "Hello, World!",
		},
		{
			name:     "with devcontainer",
			input:    "devcontainer.nvim",
			expected: "Hello, devcontainer.nvim!",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := CreateGreeting(tt.input)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestCalculateSum(t *testing.T) {
	tests := []struct {
		name     string
		numbers  []int
		expected int
	}{
		{
			name:     "positive numbers",
			numbers:  []int{1, 2, 3, 4, 5},
			expected: 15,
		},
		{
			name:     "mixed numbers",
			numbers:  []int{-1, 2, -3, 4},
			expected: 2,
		},
		{
			name:     "empty slice",
			numbers:  []int{},
			expected: 0,
		},
		{
			name:     "single number",
			numbers:  []int{42},
			expected: 42,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := CalculateSum(tt.numbers)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestCalculator(t *testing.T) {
	calc := NewCalculator()

	t.Run("Add operation", func(t *testing.T) {
		result := calc.Add(5, 3)
		assert.Equal(t, 8, result)
	})

	t.Run("Multiply operation", func(t *testing.T) {
		result := calc.Multiply(4, 6)
		assert.Equal(t, 24, result)
	})

	t.Run("History tracking", func(t *testing.T) {
		history := calc.GetHistory()
		assert.Len(t, history, 2)
		assert.Contains(t, history[0], "5 + 3 = 8")
		assert.Contains(t, history[1], "4 * 6 = 24")
	})

	t.Run("History independence", func(t *testing.T) {
		// Get history copy and verify it's independent
		history1 := calc.GetHistory()
		history2 := calc.GetHistory()
		
		// Modify one copy
		history1[0] = "modified"
		
		// Original should be unchanged
		assert.NotEqual(t, history1[0], history2[0])
	})
}

func TestCalculatorAdd(t *testing.T) {
	calc := NewCalculator()
	
	tests := []struct {
		name string
		a, b int
		want int
	}{
		{"positive numbers", 2, 3, 5},
		{"negative numbers", -2, -3, -5},
		{"mixed numbers", -2, 3, 1},
		{"zero", 0, 5, 5},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := calc.Add(tt.a, tt.b)
			assert.Equal(t, tt.want, result)
		})
	}
}

func TestCalculatorMultiply(t *testing.T) {
	calc := NewCalculator()
	
	tests := []struct {
		name string
		a, b int
		want int
	}{
		{"positive numbers", 2, 3, 6},
		{"negative numbers", -2, -3, 6},
		{"mixed numbers", -2, 3, -6},
		{"zero", 0, 5, 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := calc.Multiply(tt.a, tt.b)
			assert.Equal(t, tt.want, result)
		})
	}
}

// Benchmark tests for performance testing
func BenchmarkCalculateSum(b *testing.B) {
	numbers := make([]int, 1000)
	for i := range numbers {
		numbers[i] = i
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		CalculateSum(numbers)
	}
}

func BenchmarkCalculatorAdd(b *testing.B) {
	calc := NewCalculator()
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		calc.Add(i, i+1)
	}
}