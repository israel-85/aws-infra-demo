/**
 * Unit tests for secrets service
 */

// Mock AWS SDK before importing
jest.mock('@aws-sdk/client-secrets-manager', () => {
  return {
    SecretsManagerClient: jest.fn().mockImplementation(() => ({
      send: jest.fn()
    })),
    GetSecretValueCommand: jest.fn()
  };
});

// Mock logger
jest.mock('../../src/utils/logger', () => ({
  debug: jest.fn(),
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn()
}));

const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');
const secretsService = require('../../src/services/secretsService');
const logger = require('../../src/utils/logger');

describe('SecretsService', () => {
  let mockSend;

  beforeEach(() => {
    mockSend = jest.fn();
    SecretsManagerClient.mockImplementation(() => ({
      send: mockSend
    }));
    GetSecretValueCommand.mockImplementation((params) => params);
    
    // Clear cache before each test
    secretsService.clearCache();
    jest.clearAllMocks();
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('getSecret', () => {
    test('should retrieve secret successfully', async () => {
      const mockSecretData = {
        apiVersion: '1.0',
        features: ['feature1', 'feature2']
      };

      mockSend.mockResolvedValue({
        SecretString: JSON.stringify(mockSecretData)
      });

      const result = await secretsService.getSecret('test-secret');

      expect(result).toEqual(mockSecretData);
      expect(GetSecretValueCommand).toHaveBeenCalledWith({
        SecretId: 'test-secret'
      });
      expect(mockSend).toHaveBeenCalledTimes(1);
      expect(logger.info).toHaveBeenCalledWith('Successfully retrieved secret test-secret');
    });

    test('should cache secrets and reuse cached values', async () => {
      const mockSecretData = {
        apiVersion: '1.0',
        features: ['feature1']
      };

      mockSend.mockResolvedValue({
        SecretString: JSON.stringify(mockSecretData)
      });

      // First call
      const result1 = await secretsService.getSecret('test-secret');
      // Second call (should use cache)
      const result2 = await secretsService.getSecret('test-secret');

      expect(result1).toEqual(mockSecretData);
      expect(result2).toEqual(mockSecretData);
      expect(mockSend).toHaveBeenCalledTimes(1); // Only called once due to caching
      expect(logger.debug).toHaveBeenCalledWith('Retrieved secret test-secret from cache');
    });

    test('should bypass cache when useCache is false', async () => {
      const mockSecretData = {
        apiVersion: '1.0',
        features: ['feature1']
      };

      mockSend.mockResolvedValue({
        SecretString: JSON.stringify(mockSecretData)
      });

      // First call with cache
      await secretsService.getSecret('test-secret');
      // Second call without cache
      await secretsService.getSecret('test-secret', { useCache: false });

      expect(mockSend).toHaveBeenCalledTimes(2);
    });

    test('should retry on transient errors', async () => {
      const mockSecretData = {
        apiVersion: '1.0',
        features: ['feature1']
      };

      // First two calls fail, third succeeds
      mockSend
        .mockRejectedValueOnce(new Error('Throttling'))
        .mockRejectedValueOnce(new Error('ServiceUnavailable'))
        .mockResolvedValueOnce({
          SecretString: JSON.stringify(mockSecretData)
        });

      const result = await secretsService.getSecret('test-secret');

      expect(result).toEqual(mockSecretData);
      expect(mockSend).toHaveBeenCalledTimes(3);
      expect(logger.warn).toHaveBeenCalledTimes(2);
    });

    test('should not retry on non-retryable errors', async () => {
      const error = new Error('ResourceNotFoundException');
      error.name = 'ResourceNotFoundException';
      mockSend.mockRejectedValue(error);

      await expect(secretsService.getSecret('non-existent-secret'))
        .rejects
        .toThrow('Failed to retrieve secret non-existent-secret after 3 attempts');

      expect(mockSend).toHaveBeenCalledTimes(1); // No retries
    });

    test('should return null when throwOnError is false', async () => {
      mockSend.mockRejectedValue(new Error('Secret not found'));

      const result = await secretsService.getSecret('non-existent-secret', { throwOnError: false });

      expect(result).toBeNull();
      expect(logger.error).toHaveBeenCalled();
    });

    test('should validate secret data structure', async () => {
      mockSend.mockResolvedValue({
        SecretString: 'invalid-json'
      });

      await expect(secretsService.getSecret('test-secret'))
        .rejects
        .toThrow('Failed to retrieve secret test-secret after 3 attempts');
    });

    test('should handle empty secret string', async () => {
      mockSend.mockResolvedValue({
        SecretString: null
      });

      await expect(secretsService.getSecret('test-secret'))
        .rejects
        .toThrow('Secret value is empty or binary');
    });
  });

  describe('getAppConfig', () => {
    test('should get app config with default values', async () => {
      const mockSecretData = {
        apiVersion: '2.0',
        features: ['custom-feature']
      };

      mockSend.mockResolvedValue({
        SecretString: JSON.stringify(mockSecretData)
      });

      const result = await secretsService.getAppConfig();

      expect(result).toEqual(expect.objectContaining({
        apiVersion: '2.0',
        features: ['custom-feature'],
        database: {
          maxConnections: 100,
          timeout: 30
        },
        cache: {
          ttl: 300,
          enabled: true
        }
      }));
    });

    test('should merge with default configuration', async () => {
      const mockSecretData = {
        database: {
          maxConnections: 200
        }
      };

      mockSend.mockResolvedValue({
        SecretString: JSON.stringify(mockSecretData)
      });

      const result = await secretsService.getAppConfig();

      expect(result.database.maxConnections).toBe(200);
      expect(result.database.timeout).toBe(30); // Default value
      expect(result.apiVersion).toBe('1.0'); // Default value
    });
  });

  describe('getDatabaseCredentials', () => {
    test('should get database credentials successfully', async () => {
      const mockCredentials = {
        username: 'testuser',
        password: 'testpass',
        host: 'localhost',
        port: 3306,
        dbname: 'testdb'
      };

      mockSend.mockResolvedValue({
        SecretString: JSON.stringify(mockCredentials)
      });

      const result = await secretsService.getDatabaseCredentials();

      expect(result).toEqual(mockCredentials);
      expect(GetSecretValueCommand).toHaveBeenCalledWith({
        SecretId: 'aws-infra-demo/test/database-credentials'
      });
    });

    test('should validate required database credential fields', async () => {
      const mockCredentials = {
        username: 'testuser',
        password: 'testpass'
        // Missing host, port, dbname
      };

      mockSend.mockResolvedValue({
        SecretString: JSON.stringify(mockCredentials)
      });

      await expect(secretsService.getDatabaseCredentials())
        .rejects
        .toThrow('Missing required database credential field: host');
    });
  });

  describe('getApiKeys', () => {
    test('should get API keys successfully', async () => {
      const mockApiKeys = {
        externalApi: 'key123',
        thirdPartyService: 'secret456'
      };

      mockSend.mockResolvedValue({
        SecretString: JSON.stringify(mockApiKeys)
      });

      const result = await secretsService.getApiKeys();

      expect(result).toEqual(mockApiKeys);
      expect(GetSecretValueCommand).toHaveBeenCalledWith({
        SecretId: 'aws-infra-demo/test/api-keys'
      });
    });
  });

  describe('cache management', () => {
    test('should refresh specific secret', async () => {
      const mockSecretData = { apiVersion: '1.0' };

      mockSend.mockResolvedValue({
        SecretString: JSON.stringify(mockSecretData)
      });

      // First call to populate cache
      await secretsService.getSecret('test-secret');
      
      // Refresh should clear cache and fetch again
      await secretsService.refreshSecret('test-secret');

      expect(mockSend).toHaveBeenCalledTimes(2);
    });

    test('should refresh all secrets', async () => {
      const mockSecretData = { apiVersion: '1.0' };

      mockSend.mockResolvedValue({
        SecretString: JSON.stringify(mockSecretData)
      });

      // Populate cache with multiple secrets
      await secretsService.getSecret('secret1');
      await secretsService.getSecret('secret2');

      // Refresh all
      await secretsService.refreshAllSecrets();

      expect(mockSend).toHaveBeenCalledTimes(4); // 2 initial + 2 refresh
    });

    test('should get cache statistics', async () => {
      const mockSecretData = { apiVersion: '1.0' };

      mockSend.mockResolvedValue({
        SecretString: JSON.stringify(mockSecretData)
      });

      await secretsService.getSecret('test-secret');

      const stats = secretsService.getCacheStats();

      expect(stats).toEqual({
        totalEntries: 1,
        validEntries: 1,
        expiredEntries: 0,
        cacheTimeout: 5 * 60 * 1000
      });
    });

    test('should clear specific secret from cache', async () => {
      const mockSecretData = { apiVersion: '1.0' };

      mockSend.mockResolvedValue({
        SecretString: JSON.stringify(mockSecretData)
      });

      await secretsService.getSecret('test-secret');
      secretsService.clearCache('test-secret');

      const stats = secretsService.getCacheStats();
      expect(stats.totalEntries).toBe(0);
    });

    test('should clear all cache', async () => {
      const mockSecretData = { apiVersion: '1.0' };

      mockSend.mockResolvedValue({
        SecretString: JSON.stringify(mockSecretData)
      });

      await secretsService.getSecret('secret1');
      await secretsService.getSecret('secret2');
      
      secretsService.clearCache();

      const stats = secretsService.getCacheStats();
      expect(stats.totalEntries).toBe(0);
    });
  });

  describe('healthCheck', () => {
    test('should return healthy status when secrets are accessible', async () => {
      const mockSecretData = { apiVersion: '1.0' };

      mockSend.mockResolvedValue({
        SecretString: JSON.stringify(mockSecretData)
      });

      const result = await secretsService.healthCheck();

      expect(result.status).toBe('healthy');
      expect(result.service).toBe('secrets-manager');
      expect(result.cache).toBeDefined();
    });

    test('should return unhealthy status when secrets are not accessible', async () => {
      mockSend.mockRejectedValue(new Error('Access denied'));

      const result = await secretsService.healthCheck();

      expect(result.status).toBe('unhealthy');
      expect(result.service).toBe('secrets-manager');
      expect(result.error).toBe('Access denied');
    });
  });

  describe('error handling', () => {
    test('should identify non-retryable errors correctly', () => {
      const retryableError = new Error('Throttling');
      const nonRetryableError = new Error('ResourceNotFoundException');
      nonRetryableError.name = 'ResourceNotFoundException';

      expect(secretsService.isNonRetryableError(retryableError)).toBe(false);
      expect(secretsService.isNonRetryableError(nonRetryableError)).toBe(true);
    });

    test('should sleep for specified duration', async () => {
      const start = Date.now();
      await secretsService.sleep(100);
      const end = Date.now();

      expect(end - start).toBeGreaterThanOrEqual(100);
    });
  });
});