package main

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestReverse(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{"empty string", "", ""},
		{"single character", "a", "a"},
		{"simple word", "hello", "olleh"},
		{"with spaces", "hello world", "dlrow olleh"},
		{"unicode", "Hello, 世界", "界世 ,olleH"},
		{"palindrome", "level", "level"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := Reverse(tt.input)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestIsPalindrome(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected bool
	}{
		{"empty string", "", true},
		{"single character", "a", true},
		{"simple palindrome", "level", true},
		{"case insensitive", "Level", true},
		{"with spaces", "A man a plan a canal Panama", true},
		{"with punctuation", "race a car", false},
		{"not palindrome", "hello", false},
		{"numeric palindrome", "12321", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := IsPalindrome(tt.input)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestCountWords(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected int
	}{
		{"empty string", "", 0},
		{"single word", "hello", 1},
		{"multiple words", "hello world", 2},
		{"extra spaces", "  hello   world  ", 2},
		{"tabs and newlines", "hello\tworld\nfoo", 3},
		{"punctuation", "Hello, world! How are you?", 5},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := CountWords(tt.input)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestTitleCase(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{"empty string", "", ""},
		{"single word", "hello", "Hello"},
		{"multiple words", "hello world", "Hello World"},
		{"already title case", "Hello World", "Hello World"},
		{"all caps", "HELLO WORLD", "Hello World"},
		{"mixed case", "heLLo WoRLd", "Hello World"},
		{"with numbers", "hello 123 world", "Hello 123 World"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := TitleCase(tt.input)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestContains(t *testing.T) {
	tests := []struct {
		name     string
		str      string
		substr   string
		expected bool
	}{
		{"empty strings", "", "", true},
		{"empty substring", "hello", "", true},
		{"simple contains", "hello world", "world", true},
		{"case insensitive", "Hello World", "WORLD", true},
		{"not contains", "hello world", "foo", false},
		{"partial match", "hello world", "lo wo", true},
		{"case mix", "HeLLo WoRLd", "hello", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := Contains(tt.str, tt.substr)
			assert.Equal(t, tt.expected, result)
		})
	}
}

// Benchmark tests
func BenchmarkReverse(b *testing.B) {
	s := "The quick brown fox jumps over the lazy dog"
	for i := 0; i < b.N; i++ {
		Reverse(s)
	}
}

func BenchmarkIsPalindrome(b *testing.B) {
	s := "A man a plan a canal Panama"
	for i := 0; i < b.N; i++ {
		IsPalindrome(s)
	}
}
