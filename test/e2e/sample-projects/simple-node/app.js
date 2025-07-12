// Simple Node.js app for E2E testing
const http = require('http');
const port = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('Hello from containerized Node.js app!\n');
});

if (require.main === module) {
  server.listen(port, () => {
    console.log(`Server running at http://localhost:${port}/`);
  });
}

module.exports = server;
