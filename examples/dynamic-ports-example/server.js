const express = require('express');
const app = express();

// Main development server (fixed port 3000)
const PORT = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.json({
    message: 'Dynamic Ports Example - Main Server',
    port: PORT,
    timestamp: new Date().toISOString(),
    info: 'This server runs on port 3000 (fixed port mapping)'
  });
});

app.get('/status', (req, res) => {
  res.json({
    server: 'main',
    port: PORT,
    uptime: process.uptime(),
    description: 'Main development server with fixed port mapping'
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ Main server running on port ${PORT}`);
  console.log(`📍 Access at: http://localhost:${PORT}`);
  console.log(`🔗 Status endpoint: http://localhost:${PORT}/status`);
});
