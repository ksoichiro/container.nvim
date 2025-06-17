package main

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCalculatorAdd(t *testing.T) {
	calc := NewCalculator()

	tests := []struct {
		name     string
		a, b     float64
		expected float64
	}{
		{"positive numbers", 2, 3, 5},
		{"negative numbers", -2, -3, -5},
		{"mixed numbers", -2, 3, 1},
		{"zero", 0, 5, 5},
		{"decimals", 1.5, 2.5, 4.0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := calc.Add(tt.a, tt.b)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestCalculatorSubtract(t *testing.T) {
	calc := NewCalculator()

	tests := []struct {
		name     string
		a, b     float64
		expected float64
	}{
		{"positive numbers", 5, 3, 2},
		{"negative result", 3, 5, -2},
		{"negative numbers", -5, -3, -2},
		{"zero", 5, 5, 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := calc.Subtract(tt.a, tt.b)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestCalculatorMultiply(t *testing.T) {
	calc := NewCalculator()

	tests := []struct {
		name     string
		a, b     float64
		expected float64
	}{
		{"positive numbers", 2, 3, 6},
		{"negative numbers", -2, -3, 6},
		{"mixed numbers", -2, 3, -6},
		{"zero", 0, 5, 0},
		{"decimals", 2.5, 4, 10.0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := calc.Multiply(tt.a, tt.b)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestCalculatorDivide(t *testing.T) {
	calc := NewCalculator()

	t.Run("normal division", func(t *testing.T) {
		result, err := calc.Divide(10, 2)
		require.NoError(t, err)
		assert.Equal(t, 5.0, result)
	})

	t.Run("division by zero", func(t *testing.T) {
		result, err := calc.Divide(10, 0)
		assert.Error(t, err)
		assert.Equal(t, 0.0, result)
		assert.Contains(t, err.Error(), "division by zero")
	})

	t.Run("negative division", func(t *testing.T) {
		result, err := calc.Divide(-10, 2)
		require.NoError(t, err)
		assert.Equal(t, -5.0, result)
	})

	t.Run("decimal division", func(t *testing.T) {
		result, err := calc.Divide(7, 2)
		require.NoError(t, err)
		assert.Equal(t, 3.5, result)
	})
}

func TestCalculatorMemory(t *testing.T) {
	calc := NewCalculator()

	// Initially memory should be 0
	assert.Equal(t, 0.0, calc.Memory())

	// After addition, memory should store result
	calc.Add(5, 3)
	assert.Equal(t, 8.0, calc.Memory())

	// After subtraction, memory should update
	calc.Subtract(10, 4)
	assert.Equal(t, 6.0, calc.Memory())

	// Clear should reset memory
	calc.Clear()
	assert.Equal(t, 0.0, calc.Memory())
}

func TestCalculatorIntegration(t *testing.T) {
	calc := NewCalculator()

	// Complex calculation: (5 + 3) * 2 - 6 / 2
	result1 := calc.Add(5, 3)       // 8
	result2 := calc.Multiply(result1, 2) // 16
	result3, _ := calc.Divide(6, 2)     // 3
	result4 := calc.Subtract(result2, result3) // 13

	assert.Equal(t, 13.0, result4)
	assert.Equal(t, 13.0, calc.Memory())
}

// Benchmark tests
func BenchmarkCalculatorAdd(b *testing.B) {
	calc := NewCalculator()
	for i := 0; i < b.N; i++ {
		calc.Add(float64(i), float64(i+1))
	}
}

func BenchmarkCalculatorMultiply(b *testing.B) {
	calc := NewCalculator()
	for i := 0; i < b.N; i++ {
		calc.Multiply(float64(i), 2.5)
	}
}
