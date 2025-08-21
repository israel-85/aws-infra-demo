/**
 * Unit tests for configuration module
 */

const config = require('../../src/config');

describe('Config Module', () => {
  beforeEach(() => {
    // Reset environment variables
    delete process.env.PORT;
    delete process.env.NODE_ENV;
    delete process.env.AWS_REGION;
    delete process.env.PROJECT_NAME;
    delete process.env.APP_VERSION;
  });

  afterEach(() => {
    // Restore test environment
    process.env.NODE_ENV = 'test';
    process.env.PORT = '3001';
    process.env.AWS_REGION = 'us-east-1';
    process.env.PROJECT_NAME = 'aws-infra-demo';
    process.env.APP_VERSION = '1.0.0-test';
  });

  test('should have default values', () => {
    expect(config.port).toBe(3000);
    expect(config.nodeEnv).toBe('development');
    expect(config.awsRegion).toBe('us-east-1');
    expect(config.projectName).toBe('aws-infra-demo');
    expect(config.appVersion).toBe('1.0.0');
  });

  test('should use environment variables when provided', () => {
    process.env.PORT = '8080';
    process.env.NODE_ENV = 'production';
    process.env.AWS_REGION = 'us-west-2';
    process.env.PROJECT_NAME = 'test-project';
    process.env.APP_VERSION = '2.0.0';

    // Re-require to get updated config
    delete require.cache[require.resolve('../../src/config')];
    const updatedConfig = require('../../src/config');

    expect(updatedConfig.port).toBe('8080');
    expect(updatedConfig.nodeEnv).toBe('production');
    expect(updatedConfig.awsRegion).toBe('us-west-2');
    expect(updatedConfig.projectName).toBe('test-project');
    expect(updatedConfig.appVersion).toBe('2.0.0');
  });

  test('should generate correct secret name', () => {
    const secretName = config.getSecretName();
    expect(secretName).toBe('aws-infra-demo/test/app-config');
  });

  test('should have health check configuration', () => {
    expect(config.healthCheck).toBeDefined();
    expect(config.healthCheck.timeout).toBe(5000);
    expect(config.healthCheck.interval).toBe(30000);
  });

  test('should have logging configuration', () => {
    expect(config.logging).toBeDefined();
    expect(config.logging.level).toBe('info');
    expect(config.logging.format).toBe('dev');
  });
});