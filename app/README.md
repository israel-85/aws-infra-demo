# AWS Infrastructure Demo Application

A sample Node.js Express application demonstrating best practices for AWS deployment with comprehensive testing, monitoring, and security features.

## Features

- **Health Checks**: `/health` and `/ready` endpoints for load balancer integration
- **Metrics**: `/metrics` endpoint for monitoring and observability
- **AWS Integration**: Secure integration with AWS Secrets Manager
- **Security**: Helmet.js security headers, CORS configuration
- **Logging**: Structured logging with Morgan and custom logger
- **Error Handling**: Comprehensive error handling and recovery
- **Testing**: Unit, integration, and smoke tests with high coverage

## Quick Start

### Prerequisites

- Node.js >= 18.0.0
- npm or yarn
- AWS credentials (for production deployment)

### Installation

```bash
# Install dependencies
npm install

# Copy environment configuration
cp .env.example .env

# Start development server
npm run dev
```

### Available Scripts

```bash
# Development
npm run dev          # Start with nodemon for development
npm start           # Start production server

# Testing
npm test            # Run unit and integration tests
npm run test:unit   # Run unit tests with coverage
npm run test:integration  # Run integration tests
npm run test:smoke  # Run smoke tests
npm run test:all    # Run all tests with custom runner
npm run validate    # Quick application validation

# Code Quality
npm run lint        # Check code style
npm run lint:fix    # Fix linting issues
npm run build       # Run tests and linting
```

## API Endpoints

### Health and Monitoring

- `GET /health` - Application health check with metrics
- `GET /ready` - Load balancer readiness check
- `GET /metrics` - Detailed application metrics

### Application

- `GET /` - Welcome message and basic info
- `GET /api/config` - Application configuration (from AWS Secrets Manager)

## Environment Variables

```bash
NODE_ENV=development        # Environment (development/staging/production)
PORT=3000                  # Server port
AWS_REGION=us-east-1       # AWS region
PROJECT_NAME=aws-infra-demo # Project identifier
APP_VERSION=1.0.0          # Application version
LOG_LEVEL=info             # Logging level
```

## AWS Integration

The application integrates with AWS Secrets Manager to retrieve configuration securely:

- **Primary secret**: `{PROJECT_NAME}/{NODE_ENV}/app-config` for application configuration
- **Database secret**: `{PROJECT_NAME}/{NODE_ENV}/database-credentials` for database access
- **API keys secret**: `{PROJECT_NAME}/{NODE_ENV}/api-keys` for external service credentials
- Automatic caching with 5-minute TTL
- Graceful error handling for AWS service failures
- Support for automatic secret rotation with Lambda functions

### Example Secret Structure

```json
{
  "apiVersion": "1.0",
  "features": ["authentication", "logging", "monitoring"],
  "database": {
    "maxConnections": 100,
    "timeout": 30
  },
  "cache": {
    "ttl": 300,
    "enabled": true
  },
  "logging": {
    "level": "info"
  }
}
```

### Multiple Secret Types

The infrastructure supports three types of secrets:

1. **Application Configuration** (`app-config`): Non-sensitive application settings
2. **Database Credentials** (`database-credentials`): Database connection details
3. **API Keys** (`api-keys`): External service credentials and API tokens

## Testing Strategy

### Unit Tests (`tests/unit/`)
- Configuration module testing
- Secrets service testing
- Error handler testing
- Logger utility testing

### Integration Tests (`tests/integration/`)
- API endpoint testing
- AWS service integration
- Security header validation
- Error handling workflows

### Smoke Tests (`tests/smoke/`)
- Deployment validation
- End-to-end user workflows
- Performance under load
- Security posture validation

## Security Features

- **Helmet.js**: Security headers (XSS protection, content type options, etc.)
- **CORS**: Cross-origin resource sharing configuration
- **Secret Management**: No plain text secrets in code or configuration
- **Error Sanitization**: Sensitive information filtered from error responses
- **Input Validation**: Request validation and sanitization

## Monitoring and Observability

### Health Checks
- Application health status
- Uptime tracking
- Request and error counting
- Memory and CPU usage

### Logging
- Structured JSON logging in production
- Human-readable logs in development
- Request/response logging with Morgan
- Error tracking and correlation

### Metrics
- Request count and error rate
- Memory usage and CPU utilization
- Application uptime
- Custom business metrics

## Deployment

### Local Development
```bash
npm run dev
```

### Production Deployment
```bash
# Build and test
npm run build

# Start production server
NODE_ENV=production npm start
```

### Docker Deployment
```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY src/ ./src/
EXPOSE 3000
CMD ["npm", "start"]
```

## Architecture

```
src/
├── server.js              # Main application entry point
├── config.js              # Configuration management
├── services/
│   └── secretsService.js  # AWS Secrets Manager integration
├── middleware/
│   └── errorHandler.js    # Error handling middleware
└── utils/
    └── logger.js          # Logging utility

tests/
├── setup.js               # Test configuration
├── unit/                  # Unit tests
├── integration/           # Integration tests
└── smoke/                 # End-to-end smoke tests
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Ensure all tests pass: `npm test`
5. Run linting: `npm run lint:fix`
6. Submit a pull request

## License

MIT License - see LICENSE file for details