# Read-only Caching Feature - Implementation Summary

## Branch: `feature/readonly-caching`

## Overview

This feature implements response caching for read-only chatbot operations to reduce external API calls, improve response times, and conserve API quota.

## Changes Made

### cloud-sandbox Repository

#### 1. New DynamoDB Table: `chatbot-response-cache`
**Location:** `aws/10-plt/chatbot-response-cache/terragrunt.hcl`

**Purpose:** Cache responses from read-only operations (status queries, etc.)

**Table Structure:**
- Partition Key: `cacheKey` (e.g., "status-workflows", "status-router-plt")
- TTL: 30 seconds (status), 5 minutes (data)
- Billing: PAY_PER_REQUEST

**Cache Entry:**
```typescript
{
  cacheKey: string;
  response: any;             // Cached response data
  createdAt: string;         // ISO timestamp
  ttl: number;               // Unix timestamp
  hitCount?: number;         // Analytics
  lastAccessedAt?: string;
  cacheStrategy?: string;    // "response-cache" | "request-dedup"
}
```

#### 2. Updated Lambda Permissions

**chatbot-status-worker** (`aws/10-plt/chatbot-status-worker/terragrunt.hcl`):
- Added DynamoDB permissions (GetItem, PutItem, UpdateItem)
- Added GitHub PAT access for fetching workflow status
- SSM ARN already fixed (using `${include.root.locals.account_id}`)

### cloud-apps Repository

#### 1. New Shared Module: `response-cache.ts`
**Location:** `src/shared/response-cache.ts`

**Exports:**
- `ResponseCacheManager` class
- `responseCacheManager` singleton
- `withCache()` helper function

**Methods:**
- `get<T>()` - Get cached response
- `set<T>()` - Store response in cache
- `getOrCompute<T>()` - Get from cache or compute and cache
- `invalidate()` - Manually invalidate cache entry
- `exists()` - Check if cache entry is valid
- `generateKey()` - Static method to create cache keys

#### 2. Updated Status Worker
**Location:** `src/workers/status/index.ts`

**Changes:**
1. Fetch GitHub Actions workflow status via GitHub API
2. Use `cacheManager.getOrCompute()` for automatic caching
3. Show cache indicator in Slack response:
   - "⚡ Cached 15s ago" (cache hit)
   - "🔄 Live data" (cache miss)
4. Log cache hits/misses with metrics

## Problem Solved

### Before
```
Scenario: 10 users query /status within 30 seconds
- GitHub API calls: 10
- Average response time: 2 seconds
- API quota used: 10 requests
```

### After (30s TTL)
```
Scenario: 10 users query /status within 30 seconds
- GitHub API calls: 1 (first request)
- Cache hits: 9
- Average response time: 0.1s (cached) vs 2s (API)
- API quota used: 1 request
- Improvement: 90% API reduction, 20x faster
```

## Cache Strategies

### 1. Request Deduplication (1-5s TTL)
Combine simultaneous identical requests
- Use case: Multiple users clicking at the same time
- TTL: 1-5 seconds

### 2. Response Caching (30s-5min TTL)
Reuse recent results
- Use case: Build status (changes every 30-60s)
- TTL: 30 seconds - 5 minutes
- **Implemented for `/status` command**

### 3. Data Caching (5-60min TTL)
Cache rarely-changing data
- Use case: Component lists, configuration
- TTL: 5-60 minutes
- Not yet implemented (future enhancement)

## Cost Impact

### DynamoDB
- Pay-per-request pricing
- Expected: 30K reads + 6K writes per month
- Cost: < $0.01/month

### Savings
- GitHub API calls: 80% reduction
- Lambda execution time: 95% reduction (0.1s vs 2s)
- Response time improvement: 20x faster for cached requests

## Performance Metrics

### Expected Cache Performance
- **Cache hit rate:** 70-90%
- **Cache miss rate:** 10-30%
- **Average response time (cached):** < 200ms
- **Average response time (uncached):** 1-3s
- **API call reduction:** > 60%

### Monitoring
CloudWatch metrics:
- `ResponseCache.Hit` - Cache hits
- `ResponseCache.Miss` - Cache misses
- `ResponseCache.Put` - Cache writes
- `ResponseCache.HitRate` - Hit rate percentage

## User Experience

### Cache Hit (Subsequent Requests)
```
📊 Build Status Report

Recent Workflows:
✅ Build Slack Bot: completed (success)
🔄 Deploy to Platform: in_progress

Overall Status: 🔄 Builds in progress

⚡ Cached 15s ago | Requested by @user
```

### Cache Miss (First Request)
```
📊 Build Status Report

Recent Workflows:
✅ Build Slack Bot: completed (success)
🔄 Deploy to Platform: in_progress

Overall Status: 🔄 Builds in progress

🔄 Live data | Requested by @user
```

## Configuration

### Command-Specific TTL
Configured in `command-config.ts`:

```typescript
'/status': {
  enableCache: true,
  cacheTTL: 30,          // 30 seconds
  cacheStrategy: 'response-cache'
}
```

### Cache Keys
Generated dynamically:
- `status-workflows` - All workflows
- `status-<component>-<env>` - Component-specific (future)

## Testing Checklist

### Manual Testing
- [ ] First /status request shows "🔄 Live data"
- [ ] Second /status within 30s shows "⚡ Cached Xs ago"
- [ ] Cache expires after 30s, next request shows "🔄 Live data"
- [ ] GitHub API is called only on cache misses

### Integration Testing
- [ ] DynamoDB table created successfully
- [ ] Lambda has DynamoDB permissions
- [ ] Lambda has GitHub PAT permissions
- [ ] Cache entries have correct TTL
- [ ] Hit count increments on cache hits

### Load Testing
- [ ] 100 concurrent /status requests
- [ ] Verify only 1-5 GitHub API calls
- [ ] Verify cache hit rate > 80%

## Deployment Order

1. Deploy DynamoDB table: `terragrunt apply` in `chatbot-response-cache/`
2. Build and package Lambda code (with new dependencies)
3. Deploy Lambda infrastructure: `terragrunt apply` in `chatbot-status-worker/`
4. Test /status command

## Rollback Plan

If issues occur:
1. Set environment variable: `ENABLE_RESPONSE_CACHE=false`
2. Revert Lambda code deployment
3. Keep DynamoDB table (minimal cost, for future retry)

## Future Enhancements

### 1. Smart Cache Invalidation
Invalidate cache on GitHub webhook events:
- Build started → invalidate `status-*` cache
- Build completed → invalidate component-specific cache

### 2. Multi-level Caching
```
L1: Lambda memory cache (in-process, 60s TTL)
 ↓ miss
L2: DynamoDB cache (shared, 5min TTL)
 ↓ miss
L3: GitHub API (source of truth)
```

### 3. Cache Warming
Pre-populate cache for common queries:
- Scheduled Lambda every 30s
- Refresh popular caches before expiration

### 4. Cache Analytics Dashboard
- Hit/miss rates by command
- Response time improvements
- Cost savings metrics
- Cache efficiency trends

### 5. Additional Commands
Apply caching to more read-only commands:
- `/list` (component list, 5min TTL)
- `/help` (static content, 1hr TTL)
- `/config` (configuration, 10min TTL)

### 6. Conditional Caching
Cache based on request parameters:
- `/status all` → cache 30s
- `/status router plt` → cache 60s (component-specific)
- `/status --no-cache` → bypass cache

## Related Documentation

- DynamoDB Table: `cloud-sandbox/aws/10-plt/chatbot-response-cache/README.md`
- Status Worker: `cloud-apps/applications/chatops/slack-bot/src/workers/status/index.ts`
- Cache Manager: `cloud-apps/applications/chatops/slack-bot/src/shared/response-cache.ts`
- Command Config: `cloud-apps/applications/chatops/slack-bot/src/shared/command-config.ts`

## Comparison: Lock vs Cache

| Feature | Distributed Lock | Response Cache |
|---------|------------------|----------------|
| **Purpose** | Prevent duplicate execution | Improve performance |
| **Target** | Write operations | Read operations |
| **Commands** | /build, /deploy | /status, /list |
| **DynamoDB Table** | chatbot-build-locks | chatbot-response-cache |
| **TTL** | 10-30 minutes | 30s - 5 minutes |
| **Access Pattern** | Write-heavy (conditional) | Read-heavy |
| **Cost** | < $0.01/month | < $0.01/month |
| **Impact** | Resource savings | UX + API savings |
