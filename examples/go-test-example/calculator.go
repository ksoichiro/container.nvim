package main

import "fmt"

// Calculator provides basic arithmetic operations
type Calculator struct {
	memory float64
}

// NewCalculator creates a new calculator instance
func NewCalculator() *Calculator {
	return &Calculator{}
}

// Add performs addition
func (c *Calculator) Add(a, b float64) float64 {
	result := a + b
	c.memory = result
	return result
}

// Subtract performs subtraction
func (c *Calculator) Subtract(a, b float64) float64 {
	result := a - b
	c.memory = result
	return result
}

// Multiply performs multiplication
func (c *Calculator) Multiply(a, b float64) float64 {
	result := a * b
	c.memory = result
	return result
}

// Divide performs division
func (c *Calculator) Divide(a, b float64) (float64, error) {
	if b == 0 {
		return 0, fmt.Errorf("division by zero")
	}
	result := a / b
	c.memory = result
	return result, nil
}

// Memory returns the last calculated result
func (c *Calculator) Memory() float64 {
	return c.memory
}

// Clear resets the memory
func (c *Calculator) Clear() {
	c.memory = 0
}
