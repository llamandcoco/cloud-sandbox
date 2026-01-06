# Chatbot Response Cache DynamoDB Table

## Purpose

Response caching for read-only chatbot operations to reduce API calls and improve response times.

## Problem Solved

When multiple users query status or other read-only information:
- Without cache: Each request → GitHub API call → slower response + API quota usage
- With cache: First request → GitHub API, subsequent requests (within TTL) → cached response

## How It Works

### Cache Miss (First Request)
1. Worker checks cache for `cacheKey`
2. Cache miss → fetch from GitHub API
3. Store response in cache with TTL
4. Return response to user

### Cache Hit (Subsequent Requests)
1. Worker checks cache for `cacheKey`
2. Cache hit → validate TTL not expired
3. Return cached response (skip GitHub API)
4. Increment hit counter for metrics

### Cache Structure

```typescript
interface CacheEntry {
  cacheKey: string;          // PK: "status-router-plt" or "status-all"
  response: any;             // Cached response data (JSON)
  createdAt: string;         // ISO timestamp when cached
  ttl: number;               // Unix timestamp for auto-cleanup
  hitCount?: number;         // Number of cache hits (analytics)
  lastAccessedAt?: string;   // Last access time
  cacheStrategy?: string;    // "response-cache" | "request-dedup"
}
```

## Cache Scope

Caches are scoped by:
- **Command type**: status, list, etc.
- **Query parameters**: component, environment, filters

Example cache keys:
- `status-all` - All builds status
- `status-router-plt` - Router component status in platform
- `status-router-prod` - Router component status in production
- `list-components` - Component list

## TTL Configuration by Command

| Command | TTL | Strategy | Reason |
|---------|-----|----------|--------|
| `/status` | 30s | response-cache | Build status changes every 30-60s |
| `/status <component>` | 30s | response-cache | Component-specific status |
| `/list` | 5min | data-cache | Component list rarely changes |
| `/help` | 1hr | data-cache | Static content |

## Cache Invalidation

### Automatic (TTL-based)
- DynamoDB TTL automatically deletes expired entries
- No manual cleanup required

### Manual (Event-based)
Optionally invalidate cache on specific events:
- New build started → invalidate `status-*` cache
- Deployment completed → invalidate `status-<component>-<env>` cache
- Configuration changed → invalidate `list-*` cache

**Note:** Manual invalidation not implemented in initial version (rely on TTL)

## Performance Impact

### Before Caching
```
Scenario: 10 users query /status within 30 seconds
- GitHub API calls: 10
- Average response time: 2s
- API quota used: 10 requests
```

### After Caching (30s TTL)
```
Scenario: 10 users query /status within 30 seconds
- GitHub API calls: 1 (first request only)
- Cache hits: 9
- Average response time: 0.1s (cache) vs 2s (API)
- API quota used: 1 request
- Improvement: 90% API reduction, 20x faster response
```

## Cost Analysis

### DynamoDB Costs
- **Reads:** $0.25 per million requests
- **Writes:** $1.25 per million requests
- **Storage:** $0.25 per GB-month

### Expected Usage
- 1000 status queries/day
- Cache hit rate: 80%
- Reads: 1000/day = 30K/month
- Writes: 200/day = 6K/month (20% cache misses)

**Monthly Cost:** < $0.01 (negligible)

### Savings
- GitHub API calls reduced by 80%
- Faster user responses → better UX
- More API quota available for actual builds

## Access Pattern

### Read-Heavy Workload
- **GetItem:** 80% of operations (cache lookups)
- **PutItem:** 20% of operations (cache misses)
- **UpdateItem:** Occasional (hit counter updates)

### Throughput
- Provisioned: Not recommended (unpredictable read patterns)
- On-Demand: Auto-scales with user activity

## Cache Strategies

### 1. Request Deduplication (1-5s TTL)
Combine simultaneous identical requests

```
Time 0s: User A requests /status → API call → cache
Time 1s: User B requests /status → cache hit
Time 2s: User C requests /status → cache hit
```

### 2. Response Caching (30s-5min TTL)
Reuse recent results

```
Time 0:00 - User A: /status → API → cache
Time 0:30 - User B: /status → cache (30s old data, acceptable)
Time 1:00 - User C: /status → cache expired → API → new cache
```

### 3. Data Caching (5-60min TTL)
Cache rarely-changing data

```
/list components → cache for 5 minutes
/help → cache for 1 hour
```

## Monitoring

### Key Metrics
- **Cache Hit Rate:** Target > 70%
  - Formula: `cache_hits / total_requests`
- **Cache Miss Rate:** Target < 30%
- **Average Response Time:** Target < 200ms (cached)
- **API Call Reduction:** Target > 60%

### CloudWatch Metrics
- `ResponseCache.Hit` - Cache hits
- `ResponseCache.Miss` - Cache misses
- `ResponseCache.Put` - Cache writes
- `ResponseCache.Expired` - Expired cache accesses

### Alarms
- Cache hit rate < 50% (investigate cache strategy)
- DynamoDB errors > 1% (investigate permissions/quota)

## Related Resources

- Status Worker Lambda: `chatbot-status-worker`
- Application Code: `cloud-apps/applications/chatops/slack-bot/src/shared/response-cache.ts`
- Command Config: `cloud-apps/applications/chatops/slack-bot/src/shared/command-config.ts`

## Future Enhancements

1. **Smart Cache Invalidation**
   - Invalidate on GitHub webhook events
   - Build started → invalidate status cache
   - Build completed → invalidate component-specific cache

2. **Multi-level Caching**
   - L1: In-memory cache (Lambda)
   - L2: DynamoDB cache (shared)
   - Reduces DynamoDB reads

3. **Cache Warming**
   - Pre-populate cache for common queries
   - Scheduled Lambda to refresh popular caches

4. **Cache Analytics Dashboard**
   - Hit/miss rates by command
   - Response time improvements
   - Cost savings metrics
