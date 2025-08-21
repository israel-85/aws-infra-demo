/**
 * Application configuration module
 */

const config = {
  port: process.env.PORT || 3000,
  nodeEnv: process.env.NODE_ENV || 'development',
  awsRegion: process.env.AWS_REGION || 'us-east-1',
  projectName: process.env.PROJECT_NAME || 'aws-infra-demo',
  appVersion: process.env.APP_VERSION || '1.0.0',
  
  // Secret configuration
  getSecretName: () => {
    return `${config.projectName}/${config.nodeEnv}/app-config`;
  },
  
  getDatabaseSecretName: () => {
    return `${config.projectName}/${config.nodeEnv}/database-credentials`;
  },
  
  getApiKeysSecretName: () => {
    return `${config.projectName}/${config.nodeEnv}/api-keys`;
  },
  
  // Health check configuration
  healthCheck: {
    timeout: 5000,
    interval: 30000
  },
  
  // Logging configuration
  logging: {
    level: process.env.LOG_LEVEL || 'info',
    format: process.env.NODE_ENV === 'production' ? 'combined' : 'dev'
  }
};

module.exports = config;