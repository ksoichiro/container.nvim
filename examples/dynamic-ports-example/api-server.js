const express = require('express');
const app = express();

// API server (auto-allocated port 8080)
const PORT = 8080;

app.use(express.json());

app.get('/api', (req, res) => {
  res.json({
    message: 'Dynamic Ports Example - API Server',
    port: PORT,
    timestamp: new Date().toISOString(),
    info: 'This API server runs on port 8080 (auto-allocated host port)'
  });
});

app.get('/api/ports', (req, res) => {
  res.json({
    server: 'api',
    containerPort: PORT,
    description: 'API server with auto-allocated host port mapping',
    note: 'Host port is automatically allocated by container.nvim'
  });
});

app.post('/api/data', (req, res) => {
  res.json({
    received: req.body,
    processed: true,
    server: 'api',
    port: PORT
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 API server running on port ${PORT}`);
  console.log(`📊 This port uses auto-allocation (host port varies)`);
  console.log(`🔗 API endpoint: http://localhost:${PORT}/api`);
});
