# Simple Nginx App

This is a simplified nginx-based application that displays environment-specific messages.

## Structure
- `index.html`: Static HTML with environment placeholders
- `nginx.conf`: Nginx configuration with health check endpoints
- `package.json`: Minimal configuration for CI/CD compatibility
- `validate-html.js`: Simple HTML structure validation

## Deployment
The deployment process replaces placeholders in index.html:
- `__ENVIRONMENT__` → staging/production
- `__ENVIRONMENT_CLASS__` → staging/production (for CSS styling)
- `__TIMESTAMP__` → deployment timestamp

## Health Endpoints
- `/health` - Full health check with environment info
- `/ready` - Simple readiness check
- `/metrics` - Basic metrics endpoint