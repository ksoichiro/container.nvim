/**
 * Example Node.js file to test LSP integration with devcontainer.nvim
 */

const express = require('express');

/**
 * Create a simple greeting message
 * @param {string} name - The name to greet
 * @returns {string} The greeting message
 */
function createGreeting(name = 'World') {
  return `Hello, ${name}!`;
}

/**
 * Calculate the sum of an array of numbers
 * @param {number[]} numbers - Array of numbers to sum
 * @returns {number} The sum of all numbers
 */
function calculateSum(numbers) {
  return numbers.reduce((sum, num) => sum + num, 0);
}

/**
 * Simple Calculator class
 */
class Calculator {
  constructor() {
    this.history = [];
  }

  /**
   * Add two numbers
   * @param {number} a - First number
   * @param {number} b - Second number
   * @returns {number} The sum
   */
  add(a, b) {
    const result = a + b;
    this.history.push(`${a} + ${b} = ${result}`);
    return result;
  }

  /**
   * Multiply two numbers
   * @param {number} a - First number
   * @param {number} b - Second number
   * @returns {number} The product
   */
  multiply(a, b) {
    const result = a * b;
    this.history.push(`${a} * ${b} = ${result}`);
    return result;
  }

  /**
   * Get calculation history
   * @returns {string[]} Array of calculation history
   */
  getHistory() {
    return [...this.history];
  }
}

// Create Express app
const app = express();
const port = process.env.PORT || 3000;

app.use(express.json());

// Routes
app.get('/', (req, res) => {
  res.json({
    message: createGreeting('devcontainer.nvim'),
    timestamp: new Date().toISOString()
  });
});

app.post('/calculate/sum', (req, res) => {
  const { numbers } = req.body;

  if (!Array.isArray(numbers)) {
    return res.status(400).json({ error: 'numbers must be an array' });
  }

  const sum = calculateSum(numbers);
  res.json({ numbers, sum });
});

app.post('/calculate/:operation', (req, res) => {
  const { operation } = req.params;
  const { a, b } = req.body;

  if (typeof a !== 'number' || typeof b !== 'number') {
    return res.status(400).json({ error: 'a and b must be numbers' });
  }

  const calc = new Calculator();
  let result;

  switch (operation) {
    case 'add':
      result = calc.add(a, b);
      break;
    case 'multiply':
      result = calc.multiply(a, b);
      break;
    default:
      return res.status(400).json({ error: 'Unsupported operation' });
  }

  res.json({
    operation,
    a,
    b,
    result,
    history: calc.getHistory()
  });
});

// Start server
app.listen(port, () => {
  console.log(`Server running on port ${port}`);
  console.log(createGreeting('devcontainer.nvim development server'));
});

module.exports = app;
