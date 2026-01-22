# Chatbot Build Locks DynamoDB Table

## Purpose

Distributed locking mechanism for preventing duplicate build and deployment operations.

## Problem Solved

When multiple users trigger the same build or deployment command simultaneously (e.g., `/build router plt`), without locking:
- GitHub Actions workflows are triggered multiple times
- CI/CD resources are wasted
- Potential race conditions in deployment

## How It Works

### Lock Acquisition
1. Worker attempts to create a lock record with conditional write
2. If lock doesn't exist or is expired → lock acquired
3. If lock exists and not expired → lock acquisition fails
4. Worker informs user if another build is in progress

### Lock Release
1. Build/deploy completes successfully → lock status set to `COMPLETED`
2. Build/deploy fails → lock status set to `FAILED`
3. Lock not released (Lambda timeout) → TTL auto-cleanup after expiration

### Lock Structure

```typescript
interface BuildLock {
  lockKey: string;          // PK: "build-router-plt" or "deploy-api-prod"
  lockedBy: string;         // User ID who acquired the lock
  lockedByName: string;     // User name (for display)
  lockedAt: string;         // ISO timestamp
  status: string;           // "IN_PROGRESS" | "COMPLETED" | "FAILED"
  ttl: number;              // Unix timestamp for auto-cleanup
  component: string;        // "router", "echo", "deploy", etc.
  environment: string;      // "plt", "dev", "prod"
  correlationId?: string;   // Request correlation ID
}
```

## Lock Scope

Locks are scoped by:
- **Command type**: build vs deploy
- **Component**: router, echo, status, deploy, all
- **Environment**: plt, dev, prod

Example lock keys:
- `build-router-plt` - Building router component for platform
- `build-all-prod` - Building all components for production
- `deploy-api-prod` - Deploying API to production

## TTL Configuration

| Lock Type | TTL | Reason |
|-----------|-----|--------|
| Build | 10 minutes | Builds typically complete in 2-3 minutes |
| Deploy | 30 minutes | Deployments can take longer |

Auto-cleanup ensures stale locks don't block operations indefinitely.

## Monitoring

Key metrics to monitor:
- Lock acquisition failures (indicates concurrent attempts)
- Lock expiration without completion (indicates Lambda timeouts)
- Average lock duration (build/deploy performance)

## Cost

DynamoDB Pay-Per-Request pricing:
- Write: $1.25 per million requests
- Read: $0.25 per million requests

Expected monthly cost: < $1 (for typical usage patterns)

## Access Pattern

### Write-Heavy Operations
- **PutItem** with `ConditionExpression` (lock acquisition)
- **UpdateItem** (lock status updates)
- **DeleteItem** (explicit lock release, optional)

### Read Operations
- **GetItem** (check lock status before user notification)

### Throughput
- Provisioned: Not used (unpredictable traffic)
- On-Demand: Auto-scales with demand

## Related Resources

- Build Worker Lambda: `chatbot-build-worker`
- Deploy Worker Lambda: `chatbot-deploy-worker`
- Application Code: `cloud-apps/applications/chatops/slack-bot/src/shared/build-lock.ts`
