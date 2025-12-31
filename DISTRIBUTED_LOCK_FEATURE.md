# Distributed Lock Feature - Implementation Summary

## Branch: `feature/distributed-lock`

## Overview

This feature implements distributed locking for build and deploy operations to prevent duplicate executions when multiple users trigger the same command simultaneously.

## Changes Made

### cloud-sandbox Repository

#### 1. New DynamoDB Table: `chatbot-build-locks`
**Location:** `aws/10-plt/chatbot-build-locks/terragrunt.hcl`

**Purpose:** Distributed locking mechanism for build/deploy operations

**Table Structure:**
- Partition Key: `lockKey` (e.g., "build-router-plt", "deploy-api-prod")
- TTL: 10 minutes (builds), 30 minutes (deploys)
- Billing: PAY_PER_REQUEST

**Lock Record:**
```typescript
{
  lockKey: string;
  lockedBy: string;        // User ID
  lockedByName: string;    // User name
  lockedAt: string;        // ISO timestamp
  status: "IN_PROGRESS" | "COMPLETED" | "FAILED";
  ttl: number;             // Unix timestamp
  component: string;
  environment: string;
  correlationId?: string;
}
```

#### 2. Updated Lambda Permissions

**chatbot-build-worker** (`aws/10-plt/chatbot-build-worker/terragrunt.hcl`):
- Added DynamoDB permissions (PutItem, GetItem, UpdateItem, DeleteItem)
- Fixed SSM ARN wildcard: `*` → `${include.root.locals.account_id}`
- Updated Lambda timeout: `60s` → `45s`

**chatbot-build-sqs** (`aws/10-plt/chatbot-build-sqs/terragrunt.hcl`):
- Updated visibility timeout: `65s` → `240s` (4x Lambda timeout)

**Other Workers** (echo, status, deploy, slack-router):
- Fixed SSM ARN wildcards to use `${include.root.locals.account_id}`

### cloud-apps Repository

#### 1. New Shared Module: `build-lock.ts`
**Location:** `src/shared/build-lock.ts`

**Exports:**
- `BuildLockManager` class
- `buildLockManager` singleton

**Methods:**
- `acquireLock()` - Attempt to acquire lock with conditional write
- `releaseLock()` - Mark lock as COMPLETED or FAILED
- `getLock()` - Get current lock status
- `isLocked()` - Check if operation is in progress

#### 2. New Shared Module: `command-config.ts`
**Location:** `src/shared/command-config.ts`

**Purpose:** Centralized command configuration

**Config:**
```typescript
'/build': {
  requiresLock: true,
  lockScope: 'component-environment',
  lockTTL: 10  // minutes
}

'/deploy': {
  requiresLock: true,
  lockScope: 'component-environment',
  lockTTL: 30  // minutes
}
```

#### 3. Updated Build Worker
**Location:** `src/workers/build/index.ts`

**Changes:**
1. Import `buildLockManager`
2. Attempt lock acquisition after parsing command
3. If lock held → notify user and skip (no retry)
4. If lock acquired → proceed with build
5. Release lock on success/failure

**User Experience:**
- Lock acquired: "🔨 Building router..." (visible to channel)
- Lock held: "⚠️ Build already in progress" (ephemeral, only to requester)

## Problem Solved

### Before
```
10:00:00 - User A: /build router plt → GitHub Actions triggered
10:00:01 - User B: /build router plt → GitHub Actions triggered again
Result: 2 builds running, wasted CI/CD resources
```

### After
```
10:00:00 - User A: /build router plt → Lock acquired → GitHub Actions triggered
10:00:01 - User B: /build router plt → Lock held → User notified, skipped
Result: 1 build running, User B informed to wait
```

## Cost Impact

### DynamoDB
- Pay-per-request pricing
- Expected: < 1000 requests/month
- Cost: < $0.01/month

### Lambda
- Reduced timeout: 60s → 45s
- Savings: 25% execution time on timeouts
- Fewer duplicate builds → CI/CD cost savings

## Security Improvements

### SSM Parameter ARNs
**Before:**
```hcl
resources = [
  "arn:aws:ssm:ca-central-1:*:parameter/laco/plt/aws/secrets/slack/*"
]
```

**After:**
```hcl
resources = [
  "arn:aws:ssm:ca-central-1:${include.root.locals.account_id}:parameter/laco/plt/aws/secrets/slack/*"
]
```

**Impact:** Prevents cross-account access vulnerabilities

## Reliability Improvements

### SQS/Lambda Timeout Buffer
**Before:**
- Lambda: 60s
- SQS visibility: 65s
- Buffer: 5s (insufficient)
- Risk: High duplicate processing

**After:**
- Lambda: 45s
- SQS visibility: 240s
- Buffer: 195s (4.3x)
- Risk: Low duplicate processing

## Testing Checklist

### Manual Testing
- [ ] Single user builds successfully
- [ ] Concurrent users trigger lock notification
- [ ] Lock expires after TTL (wait 10min)
- [ ] Failed build releases lock with FAILED status
- [ ] Successful build releases lock with COMPLETED status

### Integration Testing
- [ ] DynamoDB table created successfully
- [ ] Lambda has DynamoDB permissions
- [ ] Lock acquisition works
- [ ] Lock release works
- [ ] TTL cleanup works (wait 10+ minutes)

### Deployment Order
1. Deploy DynamoDB table first: `terragrunt apply` in `chatbot-build-locks/`
2. Build and package Lambda code
3. Deploy Lambda infrastructure: `terragrunt apply` in `chatbot-build-worker/`
4. Deploy SQS changes: `terragrunt apply` in `chatbot-build-sqs/`

## Monitoring

### CloudWatch Metrics to Watch
- `buildLockManager.acquireLock.failed` - Lock acquisition failures
- `buildLockManager.acquireLock.success` - Lock acquisitions
- DynamoDB table metrics:
  - ConsumedReadCapacityUnits
  - ConsumedWriteCapacityUnits
  - SystemErrors

### Expected Metrics
- Lock acquisition failure rate: 5-10% (concurrent requests)
- Lock expiration rate: < 1% (Lambda timeouts)

## Rollback Plan

If issues occur:
1. Set environment variable: `ENABLE_DISTRIBUTED_LOCK=false`
2. Revert Lambda code deployment
3. Keep DynamoDB table (for future retry)
4. Revert SQS/Lambda timeout changes if needed

## Future Enhancements

1. **Lock Status Dashboard**
   - Show currently locked operations in Slack
   - Command: `/build status --locks`

2. **Force Unlock**
   - Admin command to release stuck locks
   - Command: `/build unlock router plt`

3. **Lock Queue**
   - Queue requests instead of rejecting
   - Auto-trigger when lock releases

4. **Metrics Dashboard**
   - Lock acquisition/failure rates
   - Average lock duration
   - Concurrent request patterns

## Related Documentation

- DynamoDB Table: `cloud-sandbox/aws/10-plt/chatbot-build-locks/README.md`
- Build Worker: `cloud-apps/applications/chatops/slack-bot/src/workers/build/index.ts`
- Lock Manager: `cloud-apps/applications/chatops/slack-bot/src/shared/build-lock.ts`
