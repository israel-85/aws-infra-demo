/**
 * Integration tests for API endpoints
 */

const request = require('supertest');

// Mock AWS SDK before importing the app
jest.mock('@aws-sdk/client-secrets-manager', () => {
  return {
    SecretsManagerClient: jest.fn().mockImplementation(() => ({
      send: jest.fn()
    })),
    GetSecretValueCommand: jest.fn()
  };
});

const { SecretsManagerClient } = require('@aws-sdk/client-secrets-manager');
const app = require('../../src/server');

describe('API Integration Tests', () => {
  let mockSend;

  beforeEach(() => {
    mockSend = jest.fn();
    SecretsManagerClient.mockImplementation(() => ({
      send: mockSend
    }));
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('GET /', () => {
    test('should return welcome message', async () => {
      const response = await request(app)
        .get('/')
        .expect(200);

      expect(response.body).toEqual({
        message: 'Welcome to AWS Infrastructure Demo',
        environment: 'test',
        version: '1.0.0-test',
        timestamp: expect.any(String)
      });
    });
  });

  describe('GET /health', () => {
    test('should return health status when secrets are accessible', async () => {
      const mockSecretData = {
        apiVersion: '1.0',
        features: ['auth', 'logging']
      };

      mockSend.mockResolvedValue({
        SecretString: JSON.stringify(mockSecretData)
      });

      const response = await request(app)
        .get('/health')
        .expect(200);

      expect(response.body).toEqual({
        status: 'healthy',
        timestamp: expect.any(String),
        environment: 'test',
        version: '1.0.0-test',
        uptime: expect.any(Number),
        requestCount: expect.any(Number),
        errorCount: expect.any(Number),
        services: {
          secrets: expect.objectContaining({
            status: 'healthy',
            service: 'secrets-manager'
          })
        }
      });
    });

    test('should return unhealthy status when secrets are not accessible', async () => {
      mockSend.mockRejectedValue(new Error('Access denied'));

      const response = await request(app)
        .get('/health')
        .expect(503);

      expect(response.body).toEqual({
        status: 'unhealthy',
        timestamp: expect.any(String),
        environment: 'test',
        version: '1.0.0-test',
        uptime: expect.any(Number),
        requestCount: expect.any(Number),
        errorCount: expect.any(Number),
        services: {
          secrets: expect.objectContaining({
            status: 'unhealthy',
            service: 'secrets-manager'
          })
        }
      });
    });

    test('should increment request count on each call', async () => {
      const mockSecretData = {
        apiVersion: '1.0',
        features: ['auth', 'logging']
      };

      mockSend.mockResolvedValue({
        SecretString: JSON.stringify(mockSecretData)
      });

      const response1 = await request(app).get('/health');
      const response2 = await request(app).get('/health');

      expect(response2.body.requestCount).toBeGreaterThan(response1.body.requestCount);
    });
  });

  describe('GET /ready', () => {
    test('should return ready status', async () => {
      const response = await request(app)
        .get('/ready')
        .expect(200);

      expect(response.body).toEqual({
        status: 'ready',
        timestamp: expect.any(String)
      });
    });
  });

  describe('GET /metrics', () => {
    test('should return application metrics', async () => {
      const response = await request(app)
        .get('/metrics')
        .expect(200);

      expect(response.body).toEqual({
        uptime: expect.any(Number),
        requestCount: expect.any(Number),
        errorCount: expect.any(Number),
        memoryUsage: expect.objectContaining({
          rss: expect.any(Number),
          heapTotal: expect.any(Number),
          heapUsed: expect.any(Number),
          external: expect.any(Number)
        }),
        cpuUsage: expect.objectContaining({
          user: expect.any(Number),
          system: expect.any(Number)
        }),
        environment: 'test',
        version: '1.0.0-test'
      });
    });
  });

  describe('GET /api/config', () => {
    test('should return configuration when secret is retrieved successfully', async () => {
      const mockSecretData = {
        apiVersion: '1.0',
        features: ['auth', 'logging'],
        database: {
          maxConnections: 150,
          timeout: 45
        },
        cache: {
          ttl: 600,
          enabled: true
        },
        dbPassword: 'secret-password' // This should not be returned
      };

      mockSend.mockResolvedValue({
        SecretString: JSON.stringify(mockSecretData)
      });

      const response = await request(app)
        .get('/api/config')
        .expect(200);

      expect(response.body).toEqual({
        message: 'Configuration retrieved successfully',
        config: {
          apiVersion: '1.0',
          features: ['auth', 'logging'],
          environment: 'test',
          cache: {
            enabled: true,
            ttl: 600
          },
          database: {
            maxConnections: 150,
            timeout: 45
          }
        }
      });

      // Verify sensitive data is not returned
      expect(response.body.config.dbPassword).toBeUndefined();
    });

    test('should handle secret retrieval errors', async () => {
      mockSend.mockRejectedValue(new Error('Secret not found'));

      const response = await request(app)
        .get('/api/config')
        .expect(500);

      expect(response.body).toEqual({
        error: 'Failed to retrieve configuration',
        message: 'Internal server error',
        timestamp: expect.any(String)
      });
    });
  });

  describe('GET /api/secrets/health', () => {
    test('should return healthy status when secrets are accessible', async () => {
      const mockSecretData = {
        apiVersion: '1.0',
        features: ['auth', 'logging']
      };

      mockSend.mockResolvedValue({
        SecretString: JSON.stringify(mockSecretData)
      });

      const response = await request(app)
        .get('/api/secrets/health')
        .expect(200);

      expect(response.body).toEqual({
        status: 'healthy',
        service: 'secrets-manager',
        cache: expect.objectContaining({
          totalEntries: expect.any(Number),
          validEntries: expect.any(Number),
          expiredEntries: expect.any(Number),
          cacheTimeout: expect.any(Number)
        }),
        timestamp: expect.any(String)
      });
    });

    test('should return unhealthy status when secrets are not accessible', async () => {
      mockSend.mockRejectedValue(new Error('Access denied'));

      const response = await request(app)
        .get('/api/secrets/health')
        .expect(503);

      expect(response.body).toEqual({
        status: 'unhealthy',
        service: 'secrets-manager',
        error: expect.any(String),
        timestamp: expect.any(String)
      });
    });
  });

  describe('GET /api/secrets/cache/stats', () => {
    test('should return cache statistics', async () => {
      const response = await request(app)
        .get('/api/secrets/cache/stats')
        .expect(200);

      expect(response.body).toEqual({
        message: 'Cache statistics retrieved successfully',
        stats: expect.objectContaining({
          totalEntries: expect.any(Number),
          validEntries: expect.any(Number),
          expiredEntries: expect.any(Number),
          cacheTimeout: expect.any(Number)
        }),
        timestamp: expect.any(String)
      });
    });
  });

  describe('POST /api/secrets/cache/refresh', () => {
    test('should refresh cache successfully', async () => {
      const mockSecretData = {
        apiVersion: '1.0',
        features: ['auth', 'logging']
      };

      mockSend.mockResolvedValue({
        SecretString: JSON.stringify(mockSecretData)
      });

      const response = await request(app)
        .post('/api/secrets/cache/refresh')
        .expect(200);

      expect(response.body).toEqual({
        message: 'Cache refreshed successfully',
        timestamp: expect.any(String)
      });
    });

    test('should handle refresh errors gracefully', async () => {
      mockSend.mockRejectedValue(new Error('Service unavailable'));

      const response = await request(app)
        .post('/api/secrets/cache/refresh')
        .expect(500);

      expect(response.body).toEqual({
        error: 'Failed to refresh cache',
        message: expect.any(String),
        timestamp: expect.any(String)
      });
    });
  });

  describe('DELETE /api/secrets/cache', () => {
    test('should clear cache successfully', async () => {
      const response = await request(app)
        .delete('/api/secrets/cache')
        .expect(200);

      expect(response.body).toEqual({
        message: 'Cache cleared successfully',
        timestamp: expect.any(String)
      });
    });
  });

  describe('404 Handler', () => {
    test('should return 404 for non-existent routes', async () => {
      const response = await request(app)
        .get('/non-existent-route')
        .expect(404);

      expect(response.body).toEqual({
        error: 'Not found',
        message: 'The requested resource was not found'
      });
    });
  });

  describe('Error Handling', () => {
    test('should handle JSON parsing errors', async () => {
      const response = await request(app)
        .post('/api/config')
        .send('invalid json')
        .set('Content-Type', 'application/json')
        .expect(400);

      expect(response.body.error).toBeDefined();
    });
  });

  describe('Security Headers', () => {
    test('should include security headers', async () => {
      const response = await request(app)
        .get('/')
        .expect(200);

      // Helmet adds various security headers
      expect(response.headers['x-content-type-options']).toBe('nosniff');
      expect(response.headers['x-frame-options']).toBe('DENY');
      expect(response.headers['x-xss-protection']).toBe('0');
    });
  });

  describe('CORS', () => {
    test('should handle CORS preflight requests', async () => {
      const response = await request(app)
        .options('/')
        .set('Origin', 'http://localhost:3000')
        .set('Access-Control-Request-Method', 'GET')
        .expect(204);

      expect(response.headers['access-control-allow-origin']).toBe('*');
    });
  });
});