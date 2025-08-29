# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a comprehensive AWS Infrastructure Demo that showcases a complete CI/CD pipeline with Infrastructure as Code (IaC) using Terraform, GitHub Actions, and a Nginx application. The project demonstrates production-ready AWS deployment patterns with multi-environment support, comprehensive testing, security scanning, and automated rollback capabilities.

## Implementation Best Practices

### 0 — Purpose  

These rules ensure maintainability, safety, and developer velocity. 
**MUST** rules are enforced by CI; **SHOULD** rules are strongly recommended.

---

### 1 — Before Coding

- **BP-1 (MUST)** Ask the user clarifying questions.
- **BP-2 (SHOULD)** Draft and confirm an approach for complex work.  
- **BP-3 (SHOULD)** If ≥ 2 approaches exist, list clear pros and cons.

---

### 2 — While Coding

- **C-1 (MUST)** Follow TDD: scaffold stub -> write failing test -> implement.
- **C-2 (MUST)** Name functions with existing domain vocabulary for consistency.  
- **C-3 (SHOULD NOT)** Introduce classes when small testable functions suffice.  
- **C-4 (SHOULD)** Prefer simple, composable, testable functions.
- **C-5 (MUST)** Prefer branded `type`s for IDs

  ```ts
  type UserId = Brand<string, 'UserId'>   // ✅ Good
  type UserId = string                    // ❌ Bad
  ```  

- **C-6 (MUST)** Use `import type { … }` for type-only imports.
- **C-7 (SHOULD NOT)** Add comments except for critical caveats; rely on self‑explanatory code.
- **C-8 (SHOULD)** Default to `type`; use `interface` only when more readable or interface merging is required. 
- **C-9 (SHOULD NOT)** Extract a new function unless it will be reused elsewhere, is the only way to unit-test otherwise untestable logic, or drastically improves readability of an opaque block.

---

### 3 — Testing

- **T-1 (MUST)** For a simple function, colocate unit tests in `*.spec.ts` in same directory as source file.
- **T-2 (MUST)** For any API change, add/extend integration tests in `packages/api/test/*.spec.ts`.
- **T-3 (MUST)** ALWAYS separate pure-logic unit tests from DB-touching integration tests.
- **T-4 (SHOULD)** Prefer integration tests over heavy mocking.  
- **T-5 (SHOULD)** Unit-test complex algorithms thoroughly.
- **T-6 (SHOULD)** Test the entire structure in one assertion if possible

  ```ts
  expect(result).toBe([value]) // Good

  expect(result).toHaveLength(1); // Bad
  expect(result[0]).toBe(value); // Bad
  ```

---

### 7 - Git

- **GH-1 (MUST**) Use Conventional Commits format when writing commit messages: <https://www.conventionalcommits.org/en/v1.0.0>
- **GH-2 (SHOULD NOT**) Refer to Claude or Anthropic in commit messages.

---

## Key Components and Patterns

### Application Architecture (`app/`)

- **Nginx static web server** serving HTML content
- **Health check endpoints** (`/health`, `/ready`, `/metrics`) built into nginx configuration
- **Environment-based deployment** with template processing for staging/production
- **Static file optimization** with gzip compression and caching headers
- **Security headers** including X-Frame-Options, X-Content-Type-Options, and XSS protection

### CI/CD Pipeline Features

- **OIDC Authentication**: JWT-based AWS access without long-lived credentials
- **Branch-based deployment**: `develop` → staging, `main` → production
- **Security scanning**: tfsec for Terraform, npm audit for dependencies
- **Deployment metadata**: Comprehensive tracking with status updates and artifact management
- **Automatic rollback**: Failed deployments trigger immediate rollback workflows
- **Environment protection**: Manual approval gates for production deployments

### Infrastructure Modules (`infrastructure/modules/`)

- **Networking**: VPC with multi-AZ public/private subnets, NAT gateways, and security groups
- **Compute**: ALB + EC2 Auto Scaling Groups with health checks
- **Security**: IAM roles, security groups with least privilege principles
- **Storage**: S3 buckets with lifecycle policies for artifacts and state
- **GitHub OIDC**: JWT-based authentication for secure CI/CD pipeline access

### Infrastructure Configuration

- **`infrastructure/bootstrap/main.tf`**: OIDC provider and Terraform state backend setup
- **`infrastructure/environments/*/backend.hcl.template`**: Dynamic backend configuration templates
- **`infrastructure/shared/`**: Common variables and locals for consistent configuration

## Critical Configuration Files

### Deployment Configuration

- **`.github/workflows/`**: CI/CD pipeline definitions with security scanning and deployment automation
- **`scripts/deployment-metadata.sh`**: Metadata management for rollback capabilities
- **`scripts/rollback.sh`**: Comprehensive rollback automation with validation

## Development Workflow

### Code Changes

1. Create feature branch from `develop`
2. Make changes and add tests
3. Submit PR with CI/CD validation
4. Merge to `develop` triggers staging deployment
5. Merge to `main` triggers production deployment (with approval)

### Infrastructure Changes

1. Modify Terraform modules or environment configurations
2. Run `terraform plan` in relevant environment directory
3. Test in staging environment first
4. Use CI/CD pipeline for production deployment with approval gates

### Testing and Validation

- Validate deployment with smoke tests after deployment
- Use health check endpoints to verify application status
- Monitor deployment metadata for rollback capabilities

## Security and Best Practices

### Static Content Management

- No sensitive configuration stored in code or static files
- Environment-specific content processing during deployment
- Template-based HTML generation with environment variables
- Secure deployment artifact distribution via S3

### Authentication and Authorization

- GitHub OIDC for CI/CD pipeline authentication
- IAM roles with least privilege access patterns
- Account-specific resource naming to prevent conflicts

### Deployment Security

- Branch-based access control through OIDC conditions
- Environment protection rules with manual approval for production
- Immutable deployment artifacts with SHA-based versioning
- Comprehensive audit logging through deployment metadata

## Monitoring and Observability

### Application Endpoints

- **`GET /health`**: Basic health check with service status and timestamp
- **`GET /ready`**: Lightweight readiness check for load balancer health checks  
- **`GET /metrics`**: Basic service metrics with nginx status and timestamp
- **`GET /`**: Main application serving environment-specific HTML content

### Deployment Tracking

- Deployment metadata with status tracking (pending/success/failed)
- Artifact versioning and rollback capability
- Comprehensive logging through scripts and CI/CD pipeline

## Common Troubleshooting

### Application Issues

```bash
# Check application health
curl https://your-alb-dns/health
curl https://your-alb-dns/metrics

# Check deployment status
./scripts/deployment-metadata.sh list -e production

# View application logs
aws logs tail /aws/ec2/aws-infra-demo/production --follow
```

### Infrastructure Issues

```bash
# Check Terraform state
cd infrastructure/environments/production
terraform plan

# Force unlock state if needed (use carefully)
terraform force-unlock <lock-id>

# Re-initialize backend configuration
./scripts/init-terraform.sh production
```

## Key Dependencies and Versions

### Application Stack

- **Node.js**: >= 18.0.0 (for build and validation tooling)
- **Nginx**: Latest stable for static file serving
- **HTML/CSS/JavaScript**: Static web technologies
- **Testing**: Basic HTML validation and smoke tests
- **Deployment**: Bash-based deployment scripts with nginx configuration

### CI/CD Tools

- **tfsec**: Terraform security scanning
- **npm audit**: Dependency vulnerability scanning (high severity threshold)
- **GitHub Environment Protection**: Manual approval gates for production deployments
- Always use repo <https://github.com/israel-85/aws-infra-demo.git> as origin