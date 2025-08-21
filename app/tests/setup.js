/**
 * Jest test setup file
 */

// Set test environment variables
process.env.NODE_ENV = 'test';
process.env.PORT = '3001';
process.env.AWS_REGION = 'us-east-1';
process.env.PROJECT_NAME = 'aws-infra-demo';
process.env.APP_VERSION = '1.0.0-test';

// Global test timeout
jest.setTimeout(10000);