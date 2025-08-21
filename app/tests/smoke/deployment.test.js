/**
 * Smoke tests for deployment validation
 * These tests verify basic functionality after deployment
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

describe('Deployment Smoke Tests', () => {
  let mockSend;

  beforeAll(() => {
    mockSend = jest.fn();
    SecretsManagerClient.mockImplementation(() => ({
      send: mockSend
    }));
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('Critical Path Tests', () => {
    test('application should start and respond to health checks', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      expect(response.body.status).toBe('healthy');
      expect(response.body.environment).toBeDefined();
      expect(response.body.version).toBeDefined();
    });

    test('load balancer health check endpoint should work', async () => {
      const response = await request(app)
        .get('/ready')
        .expect(200);

      expect(response.body.status).toBe('ready');
    });

    test('main application endpoint should be accessible', async () => {
      const response = await request(app)
        .get('/')
        .expect(200);

      expect(response.body.message).toContain('AWS Infrastructure Demo');
    });
  });

  describe('AWS Integration Tests', () => {
    test('should handle AWS Secrets Manager integration', async () => {
      // Mock successful secret retrieval
      mockSend.mockResolvedValue({
        SecretString: JSON.stringify({
          apiVersion: '1.0',
          features: ['test-feature']
        })
      });

      const response = await request(app)
        .get('/api/config')
        .expect(200);

      expect(response.body.message).toContain('Configuration retrieved successfully');
      expect(response.body.config).toBeDefined();
    });

    test('should gracefully handle AWS service failures', async () => {
      // Mock AWS service failure
      mockSend.mockRejectedValue(new Error('AWS service unavailable'));

      const response = await request(app)
        .get('/api/config')
        .expect(500);

      expect(response.body.error).toBe('Failed to retrieve configuration');
    });
  });

  describe('Performance and Reliability Tests', () => {
    test('should handle multiple concurrent requests', async () => {
      const requests = Array(10).fill().map(() => 
        request(app).get('/health').expect(200)
      );

      const responses = await Promise.all(requests);
      
      responses.forEach(response => {
        expect(response.body.status).toBe('healthy');
      });
    });

    test('should maintain metrics across requests', async () => {
      // Make several requests
      await request(app).get('/');
      await request(app).get('/health');
      await request(app).get('/ready');

      const metricsResponse = await request(app)
        .get('/metrics')
        .expect(200);

      expect(metricsResponse.body.requestCount).toBeGreaterThan(0);
      expect(metricsResponse.body.uptime).toBeGreaterThan(0);
      expect(metricsResponse.body.memoryUsage).toBeDefined();
    });
  });

  describe('Error Recovery Tests', () => {
    test('should recover from errors and continue serving requests', async () => {
      // Trigger an error
      mockSend.mockRejectedValueOnce(new Error('Temporary failure'));
      await request(app).get('/api/config').expect(500);

      // Verify the app still works
      const healthResponse = await request(app)
        .get('/health')
        .expect(200);

      expect(healthResponse.body.status).toBe('healthy');
    });

    test('should handle malformed requests gracefully', async () => {
      const response = await request(app)
        .post('/api/config')
        .send('not-json')
        .set('Content-Type', 'application/json');

      // Should not crash the application
      expect(response.status).toBeGreaterThanOrEqual(400);
      
      // Verify app is still responsive
      await request(app).get('/health').expect(200);
    });
  });

  describe('Security Validation', () => {
    test('should not expose sensitive information in error responses', async () => {
      mockSend.mockRejectedValue(new Error('Secret contains: password123'));

      const response = await request(app)
        .get('/api/config')
        .expect(500);

      // Should not expose the actual error message with sensitive data
      expect(response.body.error).toBe('Failed to retrieve configuration');
      expect(response.body.message).toBe('Internal server error');
    });

    test('should include security headers', async () => {
      const response = await request(app)
        .get('/')
        .expect(200);

      expect(response.headers['x-content-type-options']).toBe('nosniff');
      expect(response.headers['x-frame-options']).toBe('DENY');
    });

    test('should handle CORS properly', async () => {
      const response = await request(app)
        .get('/')
        .set('Origin', 'http://example.com')
        .expect(200);

      expect(response.headers['access-control-allow-origin']).toBe('*');
    });
  });

  describe('Monitoring and Observability', () => {
    test('should provide comprehensive health information', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      expect(response.body).toHaveProperty('status');
      expect(response.body).toHaveProperty('timestamp');
      expect(response.body).toHaveProperty('environment');
      expect(response.body).toHaveProperty('version');
      expect(response.body).toHaveProperty('uptime');
      expect(response.body).toHaveProperty('requestCount');
      expect(response.body).toHaveProperty('errorCount');
    });

    test('should provide detailed metrics for monitoring', async () => {
      const response = await request(app)
        .get('/metrics')
        .expect(200);

      expect(response.body).toHaveProperty('uptime');
      expect(response.body).toHaveProperty('requestCount');
      expect(response.body).toHaveProperty('errorCount');
      expect(response.body).toHaveProperty('memoryUsage');
      expect(response.body).toHaveProperty('cpuUsage');
      expect(response.body).toHaveProperty('environment');
      expect(response.body).toHaveProperty('version');
    });
  });
});