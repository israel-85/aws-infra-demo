/**
 * End-to-end user workflow tests
 * These tests simulate complete user journeys through the application
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

describe('User Workflow Tests', () => {
  let mockSend;

  beforeAll(() => {
    mockSend = jest.fn();
    SecretsManagerClient.mockImplementation(() => ({
      send: mockSend
    }));
  });

  beforeEach(() => {
    // Reset mock for each test
    mockSend.mockReset();
  });

  describe('New User Journey', () => {
    test('should complete full application discovery workflow', async () => {
      // Step 1: User discovers the application
      const welcomeResponse = await request(app)
        .get('/')
        .expect(200);

      expect(welcomeResponse.body.message).toContain('AWS Infrastructure Demo');
      expect(welcomeResponse.body.environment).toBeDefined();

      // Step 2: User checks application health
      const healthResponse = await request(app)
        .get('/health')
        .expect(200);

      expect(healthResponse.body.status).toBe('healthy');

      // Step 3: User accesses configuration (simulating authenticated request)
      mockSend.mockResolvedValue({
        SecretString: JSON.stringify({
          apiVersion: '1.0',
          features: ['authentication', 'logging', 'monitoring']
        })
      });

      const configResponse = await request(app)
        .get('/api/config')
        .expect(200);

      expect(configResponse.body.config.features).toContain('authentication');
      expect(configResponse.body.config.features).toContain('logging');
      expect(configResponse.body.config.features).toContain('monitoring');
    });
  });

  describe('Monitoring Workflow', () => {
    test('should complete monitoring and metrics collection workflow', async () => {
      // Step 1: Initial metrics collection
      const initialMetrics = await request(app)
        .get('/metrics')
        .expect(200);

      const initialRequestCount = initialMetrics.body.requestCount;

      // Step 2: Generate some application activity
      await request(app).get('/').expect(200);
      await request(app).get('/health').expect(200);
      await request(app).get('/ready').expect(200);

      // Step 3: Verify metrics have been updated
      const updatedMetrics = await request(app)
        .get('/metrics')
        .expect(200);

      expect(updatedMetrics.body.requestCount).toBeGreaterThan(initialRequestCount);
      expect(updatedMetrics.body.uptime).toBeGreaterThan(0);
      expect(updatedMetrics.body.memoryUsage.heapUsed).toBeGreaterThan(0);
    });
  });

  describe('Error Handling Workflow', () => {
    test('should handle and recover from service failures', async () => {
      // Step 1: Verify application is healthy
      await request(app)
        .get('/health')
        .expect(200);

      // Step 2: Simulate AWS service failure
      mockSend.mockRejectedValue(new Error('AWS service temporarily unavailable'));

      const errorResponse = await request(app)
        .get('/api/config')
        .expect(500);

      expect(errorResponse.body.error).toBe('Failed to retrieve configuration');

      // Step 3: Verify application continues to function
      const healthAfterError = await request(app)
        .get('/health')
        .expect(200);

      expect(healthAfterError.body.status).toBe('healthy');
      expect(healthAfterError.body.errorCount).toBeGreaterThan(0);

      // Step 4: Verify service recovery
      mockSend.mockResolvedValue({
        SecretString: JSON.stringify({
          apiVersion: '1.0',
          features: ['recovery-test']
        })
      });

      const recoveryResponse = await request(app)
        .get('/api/config')
        .expect(200);

      expect(recoveryResponse.body.config.features).toContain('recovery-test');
    });
  });

  describe('Load Balancer Health Check Workflow', () => {
    test('should consistently pass load balancer health checks', async () => {
      // Simulate multiple health checks from load balancer
      const healthChecks = Array(5).fill().map(() => 
        request(app).get('/ready').expect(200)
      );

      const responses = await Promise.all(healthChecks);

      responses.forEach(response => {
        expect(response.body.status).toBe('ready');
        expect(response.body.timestamp).toBeDefined();
      });
    });
  });

  describe('Configuration Management Workflow', () => {
    test('should handle different configuration scenarios', async () => {
      // Scenario 1: Full configuration available
      mockSend.mockResolvedValueOnce({
        SecretString: JSON.stringify({
          apiVersion: '2.0',
          features: ['feature1', 'feature2', 'feature3'],
          environment: 'production'
        })
      });

      const fullConfigResponse = await request(app)
        .get('/api/config')
        .expect(200);

      expect(fullConfigResponse.body.config.apiVersion).toBe('2.0');
      expect(fullConfigResponse.body.config.features).toHaveLength(3);

      // Scenario 2: Minimal configuration
      mockSend.mockResolvedValueOnce({
        SecretString: JSON.stringify({})
      });

      const minimalConfigResponse = await request(app)
        .get('/api/config')
        .expect(200);

      expect(minimalConfigResponse.body.config.apiVersion).toBe('1.0'); // Default value
      expect(minimalConfigResponse.body.config.features).toEqual([]); // Default empty array

      // Scenario 3: Configuration with extra fields (should be filtered)
      mockSend.mockResolvedValueOnce({
        SecretString: JSON.stringify({
          apiVersion: '1.5',
          features: ['public-feature'],
          secretKey: 'should-not-be-returned',
          password: 'also-secret'
        })
      });

      const filteredConfigResponse = await request(app)
        .get('/api/config')
        .expect(200);

      expect(filteredConfigResponse.body.config.apiVersion).toBe('1.5');
      expect(filteredConfigResponse.body.config.features).toContain('public-feature');
      expect(filteredConfigResponse.body.config.secretKey).toBeUndefined();
      expect(filteredConfigResponse.body.config.password).toBeUndefined();
    });
  });

  describe('Performance Under Load Workflow', () => {
    test('should maintain performance under concurrent load', async () => {
      const startTime = Date.now();

      // Simulate concurrent users
      const concurrentRequests = Array(20).fill().map(async (_, index) => {
        const responses = await Promise.all([
          request(app).get('/'),
          request(app).get('/health'),
          request(app).get('/ready')
        ]);

        return responses.every(response => response.status === 200);
      });

      const results = await Promise.all(concurrentRequests);
      const endTime = Date.now();

      // All requests should succeed
      expect(results.every(result => result === true)).toBe(true);

      // Should complete within reasonable time (adjust threshold as needed)
      expect(endTime - startTime).toBeLessThan(5000); // 5 seconds

      // Verify application is still responsive
      const finalHealthCheck = await request(app)
        .get('/health')
        .expect(200);

      expect(finalHealthCheck.body.status).toBe('healthy');
    });
  });

  describe('Security Workflow', () => {
    test('should maintain security posture throughout user interactions', async () => {
      // Test various endpoints for security headers
      const endpoints = ['/', '/health', '/ready', '/metrics'];
      
      for (const endpoint of endpoints) {
        const response = await request(app)
          .get(endpoint)
          .expect(200);

        // Verify security headers are present
        expect(response.headers['x-content-type-options']).toBe('nosniff');
        expect(response.headers['x-frame-options']).toBe('DENY');
      }

      // Test that sensitive information is not exposed in errors
      mockSend.mockRejectedValue(new Error('Database password: secret123'));

      const errorResponse = await request(app)
        .get('/api/config')
        .expect(500);

      expect(errorResponse.body.error).not.toContain('secret123');
      expect(errorResponse.body.message).toBe('Internal server error');
    });
  });
});