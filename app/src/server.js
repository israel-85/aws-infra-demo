const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
require('dotenv').config();

const config = require('./config');
const secretsService = require('./services/secretsService');
const { errorHandler, getErrorCount } = require('./middleware/errorHandler');

const app = express();

// Application metrics
let requestCount = 0;
const startTime = Date.now();

// Security middleware
app.use(helmet());
app.use(cors());
app.use(morgan(config.logging.format));
app.use(express.json());

// Request counting middleware
app.use((req, res, next) => {
  requestCount++;
  next();
});

// Health check endpoint
app.get('/health', async (req, res) => {
  try {
    // Check secrets service health
    const secretsHealth = await secretsService.healthCheck();
    const isHealthy = secretsHealth.status === 'healthy';
    
    res.status(isHealthy ? 200 : 503).json({
      status: isHealthy ? 'healthy' : 'unhealthy',
      timestamp: new Date().toISOString(),
      environment: config.nodeEnv,
      version: config.appVersion,
      uptime: Date.now() - startTime,
      requestCount,
      errorCount: getErrorCount(),
      services: {
        secrets: secretsHealth
      }
    });
  } catch (error) {
    console.error('Error in health check:', error);
    res.status(503).json({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      environment: config.nodeEnv,
      version: config.appVersion,
      uptime: Date.now() - startTime,
      requestCount,
      errorCount: getErrorCount(),
      error: error.message
    });
  }
});

// Ready check endpoint (for load balancer)
app.get('/ready', (req, res) => {
  res.status(200).json({
    status: 'ready',
    timestamp: new Date().toISOString()
  });
});

// Metrics endpoint for monitoring
app.get('/metrics', (req, res) => {
  res.status(200).json({
    uptime: Date.now() - startTime,
    requestCount,
    errorCount: getErrorCount(),
    memoryUsage: process.memoryUsage(),
    cpuUsage: process.cpuUsage(),
    environment: config.nodeEnv,
    version: config.appVersion
  });
});

// Main application endpoint
app.get('/', (req, res) => {
  res.json({
    message: 'Welcome to AWS Infrastructure Demo',
    environment: config.nodeEnv,
    version: config.appVersion,
    timestamp: new Date().toISOString()
  });
});

// API endpoint with secret retrieval
app.get('/api/config', async (req, res) => {
  try {
    const secretData = await secretsService.getAppConfig();
    
    res.json({
      message: 'Configuration retrieved successfully',
      config: {
        // Only return non-sensitive configuration
        apiVersion: secretData.apiVersion || '1.0',
        features: secretData.features || [],
        environment: config.nodeEnv,
        cache: {
          enabled: secretData.cache?.enabled || false,
          ttl: secretData.cache?.ttl || 300
        },
        database: {
          maxConnections: secretData.database?.maxConnections || 100,
          timeout: secretData.database?.timeout || 30
        }
      }
    });
  } catch (error) {
    console.error('Error retrieving secret:', error);
    res.status(500).json({
      error: 'Failed to retrieve configuration',
      message: 'Internal server error',
      timestamp: new Date().toISOString()
    });
  }
});

// Secrets health check endpoint
app.get('/api/secrets/health', async (req, res) => {
  try {
    const healthCheck = await secretsService.healthCheck();
    const statusCode = healthCheck.status === 'healthy' ? 200 : 503;
    
    res.status(statusCode).json(healthCheck);
  } catch (error) {
    console.error('Error checking secrets health:', error);
    res.status(503).json({
      status: 'unhealthy',
      service: 'secrets-manager',
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// Cache management endpoints (for admin/debugging)
app.get('/api/secrets/cache/stats', (req, res) => {
  try {
    const stats = secretsService.getCacheStats();
    res.json({
      message: 'Cache statistics retrieved successfully',
      stats,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('Error retrieving cache stats:', error);
    res.status(500).json({
      error: 'Failed to retrieve cache statistics',
      message: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

app.post('/api/secrets/cache/refresh', async (req, res) => {
  try {
    await secretsService.refreshAllSecrets();
    res.json({
      message: 'Cache refreshed successfully',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('Error refreshing cache:', error);
    res.status(500).json({
      error: 'Failed to refresh cache',
      message: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

app.delete('/api/secrets/cache', (req, res) => {
  try {
    secretsService.clearCache();
    res.json({
      message: 'Cache cleared successfully',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('Error clearing cache:', error);
    res.status(500).json({
      error: 'Failed to clear cache',
      message: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// Error handling middleware
app.use(errorHandler);

// 404 handler
app.use('*', (req, res) => {
  res.status(404).json({
    error: 'Not found',
    message: 'The requested resource was not found'
  });
});

// Only start server if this file is run directly (not imported)
if (require.main === module) {
  const server = app.listen(config.port, () => {
    console.log(`Server running on port ${config.port}`);
    console.log(`Environment: ${config.nodeEnv}`);
    console.log(`Version: ${config.appVersion}`);
  });

  // Graceful shutdown
  process.on('SIGTERM', () => {
    console.log('SIGTERM received, shutting down gracefully');
    server.close(() => {
      console.log('Process terminated');
    });
  });
}

module.exports = app;