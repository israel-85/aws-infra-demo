/**
 * AWS Secrets Manager service with enhanced error handling and retry logic
 */

const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');
const config = require('../config');
const logger = require('../utils/logger');

class SecretsService {
  constructor() {
    this.client = new SecretsManagerClient({
      region: config.awsRegion,
      maxAttempts: 3,
      retryMode: 'adaptive'
    });
    this.cache = new Map();
    this.cacheTimeout = 5 * 60 * 1000; // 5 minutes
    this.maxRetries = 3;
    this.retryDelay = 1000; // 1 second base delay
  }

  /**
   * Retrieve secret from AWS Secrets Manager with caching and retry logic
   * @param {string} secretName - Name of the secret
   * @param {Object} options - Options for secret retrieval
   * @param {boolean} options.useCache - Whether to use cache (default: true)
   * @param {boolean} options.throwOnError - Whether to throw on error (default: true)
   * @returns {Promise<Object>} - Parsed secret data
   */
  async getSecret(secretName, options = {}) {
    const { useCache = true, throwOnError = true } = options;

    // Check cache first if enabled
    if (useCache) {
      const cached = this.cache.get(secretName);
      if (cached && Date.now() - cached.timestamp < this.cacheTimeout) {
        logger.debug(`Retrieved secret ${secretName} from cache`);
        return cached.data;
      }
    }

    let lastError;
    
    for (let attempt = 1; attempt <= this.maxRetries; attempt++) {
      try {
        logger.debug(`Attempting to retrieve secret ${secretName} (attempt ${attempt}/${this.maxRetries})`);
        
        const command = new GetSecretValueCommand({ SecretId: secretName });
        const response = await this.client.send(command);
        
        if (!response.SecretString) {
          throw new Error('Secret value is empty or binary (not supported)');
        }

        const secretData = JSON.parse(response.SecretString);
        
        // Validate secret data structure
        if (typeof secretData !== 'object' || secretData === null) {
          throw new Error('Secret data must be a valid JSON object');
        }
        
        // Cache the result if caching is enabled
        if (useCache) {
          this.cache.set(secretName, {
            data: secretData,
            timestamp: Date.now()
          });
          logger.debug(`Cached secret ${secretName}`);
        }
        
        logger.info(`Successfully retrieved secret ${secretName}`);
        return secretData;
        
      } catch (error) {
        lastError = error;
        logger.warn(`Failed to retrieve secret ${secretName} on attempt ${attempt}: ${error.message}`);
        
        // Don't retry on certain errors
        if (this.isNonRetryableError(error)) {
          break;
        }
        
        // Wait before retrying (exponential backoff)
        if (attempt < this.maxRetries) {
          const delay = this.retryDelay * Math.pow(2, attempt - 1);
          logger.debug(`Waiting ${delay}ms before retry`);
          await this.sleep(delay);
        }
      }
    }

    const errorMessage = `Failed to retrieve secret ${secretName} after ${this.maxRetries} attempts: ${lastError.message}`;
    logger.error(errorMessage);
    
    if (throwOnError) {
      throw new Error(errorMessage);
    }
    
    return null;
  }

  /**
   * Get application configuration from secrets
   * @param {Object} options - Options for secret retrieval
   * @returns {Promise<Object>} - Application configuration
   */
  async getAppConfig(options = {}) {
    const secretName = config.getSecretName();
    
    try {
      const secretData = await this.getSecret(secretName, options);
      
      // Merge with default configuration
      const defaultConfig = {
        apiVersion: '1.0',
        features: ['health-checks', 'metrics', 'logging'],
        database: {
          maxConnections: 100,
          timeout: 30
        },
        cache: {
          ttl: 300,
          enabled: true
        },
        logging: {
          level: config.nodeEnv === 'production' ? 'info' : 'debug'
        }
      };
      
      return { ...defaultConfig, ...secretData };
      
    } catch (error) {
      logger.error(`Failed to get app config: ${error.message}`);
      throw error;
    }
  }

  /**
   * Get database credentials from secrets
   * @param {Object} options - Options for secret retrieval
   * @returns {Promise<Object>} - Database credentials
   */
  async getDatabaseCredentials(options = {}) {
    const secretName = `${config.projectName}/${config.nodeEnv}/database-credentials`;
    
    try {
      const credentials = await this.getSecret(secretName, options);
      
      // Validate required fields
      const requiredFields = ['username', 'password', 'host', 'port', 'dbname'];
      for (const field of requiredFields) {
        if (!credentials[field]) {
          throw new Error(`Missing required database credential field: ${field}`);
        }
      }
      
      return credentials;
      
    } catch (error) {
      logger.error(`Failed to get database credentials: ${error.message}`);
      throw error;
    }
  }

  /**
   * Get API keys and external service credentials
   * @param {Object} options - Options for secret retrieval
   * @returns {Promise<Object>} - API keys and credentials
   */
  async getApiKeys(options = {}) {
    const secretName = `${config.projectName}/${config.nodeEnv}/api-keys`;
    
    try {
      return await this.getSecret(secretName, options);
    } catch (error) {
      logger.error(`Failed to get API keys: ${error.message}`);
      throw error;
    }
  }

  /**
   * Refresh a specific secret in cache
   * @param {string} secretName - Name of the secret to refresh
   * @returns {Promise<Object>} - Refreshed secret data
   */
  async refreshSecret(secretName) {
    logger.info(`Refreshing secret ${secretName}`);
    this.cache.delete(secretName);
    return await this.getSecret(secretName);
  }

  /**
   * Refresh all cached secrets
   * @returns {Promise<void>}
   */
  async refreshAllSecrets() {
    logger.info('Refreshing all cached secrets');
    const secretNames = Array.from(this.cache.keys());
    this.cache.clear();
    
    // Refresh each secret
    const refreshPromises = secretNames.map(secretName => 
      this.getSecret(secretName, { throwOnError: false })
    );
    
    await Promise.allSettled(refreshPromises);
    logger.info('Completed refreshing all secrets');
  }

  /**
   * Get cache statistics
   * @returns {Object} - Cache statistics
   */
  getCacheStats() {
    const now = Date.now();
    let validEntries = 0;
    let expiredEntries = 0;
    
    for (const [secretName, cached] of this.cache.entries()) {
      if (now - cached.timestamp < this.cacheTimeout) {
        validEntries++;
      } else {
        expiredEntries++;
      }
    }
    
    return {
      totalEntries: this.cache.size,
      validEntries,
      expiredEntries,
      cacheTimeout: this.cacheTimeout
    };
  }

  /**
   * Clear cache (useful for testing)
   * @param {string} secretName - Optional specific secret to clear
   */
  clearCache(secretName = null) {
    if (secretName) {
      this.cache.delete(secretName);
      logger.debug(`Cleared cache for secret ${secretName}`);
    } else {
      this.cache.clear();
      logger.debug('Cleared all secret cache');
    }
  }

  /**
   * Check if error is non-retryable
   * @param {Error} error - Error to check
   * @returns {boolean} - True if error should not be retried
   */
  isNonRetryableError(error) {
    const nonRetryableErrors = [
      'ResourceNotFoundException',
      'InvalidParameterException',
      'InvalidRequestException',
      'AccessDeniedException',
      'DecryptionFailureException'
    ];
    
    return nonRetryableErrors.some(errorType => 
      error.name === errorType || error.message.includes(errorType)
    );
  }

  /**
   * Sleep utility for retry delays
   * @param {number} ms - Milliseconds to sleep
   * @returns {Promise<void>}
   */
  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Health check for secrets service
   * @returns {Promise<Object>} - Health check result
   */
  async healthCheck() {
    try {
      // Try to retrieve app config as a health check
      await this.getAppConfig({ useCache: false, throwOnError: true });
      
      const cacheStats = this.getCacheStats();
      
      return {
        status: 'healthy',
        service: 'secrets-manager',
        cache: cacheStats,
        timestamp: new Date().toISOString()
      };
      
    } catch (error) {
      return {
        status: 'unhealthy',
        service: 'secrets-manager',
        error: error.message,
        timestamp: new Date().toISOString()
      };
    }
  }
}

module.exports = new SecretsService();