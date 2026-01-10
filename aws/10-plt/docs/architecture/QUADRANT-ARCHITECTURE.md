# Quadrant-Based Architecture for ChatOps Platform

## Overview

The ChatOps platform uses a **quadrant-based architecture** to optimize Lambda workers and SQS queues based on command characteristics. This approach improves security, performance, and resource efficiency by tailoring infrastructure to specific command requirements.

## Command Classification Matrix

Commands are classified along two dimensions:

### 1. Execution Time
- **Short**: < 30 seconds (instant response)
- **Long**: > 30 seconds (background processing)

### 2. Side Effects
- **Read**: Query-only operations (no state changes)
- **Write**: Mutating operations (state changes, deployments, builds)

### Four Quadrants

```
                    SHORT (<30s)              LONG (>30s)
                    ┌──────────────────┬──────────────────┐
                    │                  │                  │
     READ           │  Short + Read    │   Long + Read    │
  (query-only)      │  Q1: Fast Reads  │  Q3: Analytics   │
                    │                  │                  │
                    ├──────────────────┼──────────────────┤
                    │                  │                  │
     WRITE          │  Short + Write   │   Long + Write   │
  (mutating)        │  Q2: Commands    │  Q4: Deployments │
                    │                  │                  │
                    └──────────────────┴──────────────────┘
```

## Infrastructure Mapping

| Quadrant | Commands | Timeout | Concurrency | IAM Permissions | Message Retention | Max Retries |
|----------|----------|---------|-------------|-----------------|-------------------|-------------|
| **Q1: Short + Read** | `/echo`, `/status` | 10s | 100 | Read-only (SSM, SQS) | 12 hours | 2 |
| **Q2: Short + Write** | `/scale`, `/restart` | 30s | 20 | Scoped write (specific resources) | 1 day | 1 |
| **Q3: Long + Read** | `/analyze`, `/report` | 15min | 10 | Read-only + S3 read | 2 days | 2 |
| **Q4: Long + Write** | `/build`, `/deploy` | 120s-15min | 1-2 | Restricted write (S3, GitHub) | 2 days | 1 |

## Detailed Configuration

### Q1: Short + Read (Echo, Status)

**Use Case**: Fast, high-volume queries that don't modify state

**Lambda Configuration**:
```hcl
memory_size                    = 256
timeout                        = 10   # Fast response
reserved_concurrent_executions = 100  # High throughput
```

**SQS Configuration**:
```hcl
visibility_timeout_seconds = 15     # 10s timeout + 5s buffer
message_retention_seconds  = 43200  # 12 hours
max_receive_count          = 2      # Quick failure for reads
```

**IAM Permissions**:
- ✅ SSM: GetParameter (Slack secrets)
- ✅ SQS: ReceiveMessage, DeleteMessage
- ✅ X-Ray: PutTraceSegments
- ❌ S3: Write operations
- ❌ EC2/ECS: Any mutations

**Rationale**:
- Low timeout prevents resource waste on hanging queries
- High concurrency supports burst traffic
- Read-only permissions prevent accidental mutations
- Short retention reduces storage costs
- Minimal retries (queries can be re-run by user)

**SLO**: p99 < 500ms

---

### Q4: Long + Write (Build, Deploy)

**Use Case**: Long-running operations that modify infrastructure or trigger builds

**Lambda Configuration**:
```hcl
memory_size                    = 512-1024  # More resources
timeout                        = 120-900    # Extended timeout
reserved_concurrent_executions = 1-2        # Limited concurrency
```

**SQS Configuration**:
```hcl
visibility_timeout_seconds = 180-960 # Timeout + 60s buffer
message_retention_seconds  = 172800  # 2 days
max_receive_count          = 1       # No automatic retries
delay_seconds              = 0       # No queue-level delay; rate limiting handled by Lambda concurrency
```

**IAM Permissions**:
- ✅ SSM: GetParameter (Slack secrets, GitHub PAT)
- ✅ SQS: ReceiveMessage, DeleteMessage
- ✅ S3: PutObject (scoped to specific paths)
- ✅ GitHub API: repository_dispatch (via PAT)
- ✅ X-Ray: PutTraceSegments
- ❌ S3: DeleteObject (prevent accidental deletion)
- ❌ Broad resource access

**Rationale**:
- Extended timeout supports GitHub API calls and builds
- Low concurrency prevents resource exhaustion
- Scoped write permissions follow least privilege
- No retries prevent duplicate builds/deployments
- Delay provides basic rate limiting
- Longer retention for audit trail

**SLO**: p95 < 10 minutes

---

## Security Benefits

### Permission Boundaries

**Before (One-size-fits-all)**:
```hcl
# All workers had same permissions
policy_statements = [
  {
    actions   = ["s3:*", "ssm:*", "sqs:*"]  # Too broad
    resources = ["*"]
  }
]
```

**After (Quadrant-based)**:
```hcl
# Read workers - minimal permissions
policy_statements = [
  {
    actions   = ["ssm:GetParameter"]  # Read-only
    resources = ["arn:aws:ssm:*:*:parameter/laco/plt/aws/secrets/slack/*"]
  }
]

# Write workers - scoped permissions
policy_statements = [
  {
    actions   = ["s3:PutObject"]  # Specific action
    resources = ["arn:aws:s3:::laco-plt-lambda-artifacts/plt/*/builds/*"]  # Scoped path
  }
]
```

### Attack Surface Reduction

| Scenario | Before | After |
|----------|--------|-------|
| Compromised Echo worker | Could write to S3 | ❌ AccessDenied |
| Compromised Build worker | Could write anywhere | ✅ Scoped to /builds/* |
| Accidental deletion | No protection | ❌ No Delete permissions |

---

## Performance Benefits

### Resource Optimization

**Before**:
- All workers: 30s timeout, 5 concurrency
- Total waste: 25s × 1000 echo commands = 25,000s = $0.42

**After**:
- Echo workers: 10s timeout, 100 concurrency
- Total runtime: 10s × 1000 commands (parallel) = 100s = $0.017
- **Savings**: 99.6% reduction

### Isolation

**Before**:
```
Queue: [echo, build, echo, build, echo]
Workers: [w1, w2, w3, w4, w5] all busy with builds
Result: Echo commands wait 60s+ for build to complete
```

**After**:
```
Echo Queue:  [echo, echo, echo]  → [w1-100] dedicated
Build Queue: [build, build]      → [w1-2]   dedicated
Result: Echo responses in <500ms, builds don't block reads
```

---

## Cost Impact

### Lambda Costs

| Worker | Before | After | Change |
|--------|--------|-------|--------|
| Echo (1000 invokes/day) | 30s × 5 = 150s | 10s × 100 = 10s (parallel) | -93% |
| Build (50 invokes/day) | 60s × 5 = 300s | 120s × 2 = 240s | -20% |
| **Total** | 450s | 250s | **-44%** |

### SQS Costs

| Queue | Before | After | Change |
|-------|--------|-------|--------|
| Echo retention | 1 day × 1000 msgs | 12 hours × 1000 msgs | -50% |
| Build retention | 1 day × 50 msgs | 2 days × 50 msgs | +100% |
| **Net Impact** | Baseline | **-24%** | |

---

## Implementation Strategy

### Phase 1: Core Quadrants (Current)
- ✅ Q1: Echo (short-read)
- ✅ Q4: Build (long-write)
- Router: COMMAND_CATEGORIES mapping

### Phase 2: Additional Commands (Future)
- Q1: `/status` (short-read)
- Q2: `/scale`, `/restart` (short-write)
- Q3: `/analyze`, `/report` (long-read)
- Q4: `/deploy` (long-write)

### Phase 3: Dynamic Routing (Future)
- EventBridge rule per quadrant
- Automatic queue selection based on category
- Unified worker per quadrant (vs per command)

---

## Testing Permissions

### Echo Worker (Should Fail)
```bash
# Test: Echo worker CANNOT write to S3
aws lambda invoke \
  --function-name laco-plt-chatbot-echo-worker \
  --payload '{"action":"test-s3-write"}' \
  response.json

# Expected: AccessDenied error
```

### Build Worker (Should Succeed)
```bash
# Test: Build worker CAN write to S3 (scoped path)
aws lambda invoke \
  --function-name laco-plt-chatbot-build-worker \
  --payload '{"action":"test-s3-write","path":"plt/echo/builds/test.txt"}' \
  response.json

# Expected: Success
```

### Build Worker (Should Fail)
```bash
# Test: Build worker CANNOT write outside scoped path
aws lambda invoke \
  --function-name laco-plt-chatbot-build-worker \
  --payload '{"action":"test-s3-write","path":"plt/production/config.json"}' \
  response.json

# Expected: AccessDenied error
```

---

## Monitoring & Observability

### CloudWatch Metrics

**By Quadrant**:
```
Metric: custom/chatops/quadrant_duration
Dimensions: CommandCategory, Command
Values: Q1=10ms, Q2=100ms, Q3=5s, Q4=60s
```

**Tags for Filtering**:
```hcl
tags = {
  CommandCategory = "short-read"   # Q1
  SLOTarget       = "p99-500ms"
}
```

### Alarms

```hcl
# Q1: Fast reads should never timeout
alarm {
  metric_name = "Duration"
  threshold   = 5000  # 5s (way above 500ms target)
  dimensions  = { CommandCategory = "short-read" }
}

# Q4: Builds hitting timeout limit
alarm {
  metric_name = "Duration"
  threshold   = 110000  # 110s (approaching 120s limit)
  dimensions  = { CommandCategory = "long-write" }
}
```

---

## SLO Targets

| Quadrant | Latency (p99) | Availability | Error Budget |
|----------|---------------|--------------|--------------|
| Q1: Short + Read | < 500ms | 99.9% | 43 min/month |
| Q2: Short + Write | < 2s | 99.5% | 3.6 hours/month |
| Q3: Long + Read | < 30s | 99.0% | 7.2 hours/month |
| Q4: Long + Write | < 10min | 95.0% | 36 hours/month |

---

## Troubleshooting

### Q1 Commands Timing Out

**Symptoms**: Echo commands taking > 5s

**Checks**:
1. CloudWatch Logs: Check for cold starts
2. Increase memory (256 → 512 MB) to improve cold start
3. Check SQS queue depth (backlog?)
4. Verify concurrency not throttled

### Q4 Commands Failing with AccessDenied

**Symptoms**: Build worker can't write to S3

**Checks**:
1. Verify IAM policy includes correct S3 path
2. Check S3 bucket policy allows Lambda role
3. Verify path matches pattern: `plt/*/builds/*`
4. Check CloudWatch Logs for exact S3 ARN attempted

### High DLQ Depth

**Q1 Queues** (max_receive_count=2):
- Indicates persistent failures
- Check Lambda errors in CloudWatch
- Consider if external service (Slack API) is down

**Q4 Queues** (max_receive_count=1):
- Expected for transient GitHub API issues
- Review DLQ messages for patterns
- May need manual retry after fixing root cause

---

## Migration Guide

### Existing Deployments

**Step 1: Update Terragrunt Configs**
```bash
cd aws/10-plt
git pull origin main
```

**Step 2: Plan Changes**
```bash
# Review Echo worker changes
cd chatbot-echo-worker
terragrunt plan

# Review Build worker changes
cd ../chatbot-build-worker
terragrunt plan
```

**Step 3: Apply (Blue-Green)**
```bash
# Deploy new configs (Lambda versioning handles rollback)
terragrunt apply
```

**Step 4: Monitor**
```bash
# Watch CloudWatch Logs for errors
aws logs tail /aws/lambda/laco-plt-chatbot-echo-worker --follow

# Check SQS DLQ depth
aws sqs get-queue-attributes \
  --queue-url $(aws sqs get-queue-url --queue-name laco-plt-chatbot-echo-dlq --query 'QueueUrl' --output text) \
  --attribute-names ApproximateNumberOfMessages
```

**Step 5: Rollback (if needed)**
```bash
git revert <commit>
terragrunt apply
```

---

## Future Enhancements

### Dynamic Concurrency

Auto-scale based on queue depth:
```hcl
scaling_config = {
  maximum_concurrency = 100
  target_utilization  = 0.7  # Scale at 70% capacity
}
```

### Per-Command Queues → Per-Quadrant Queues

```
Before: echo-queue, build-queue, status-queue, deploy-queue
After:  short-read-queue, short-write-queue, long-read-queue, long-write-queue
```

Benefits:
- Simplified infrastructure
- Better resource sharing within quadrant
- Easier to add new commands

### Cost-Based Routing

Route expensive commands to Spot instances:
```hcl
# Q4 workers run on Fargate Spot (70% cheaper)
compute_platform = "fargate-spot"
```

---

## References

- [AWS Lambda Concurrency Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html)
- [SQS Visibility Timeout](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html)
- [IAM Policy Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [SLACK-BOT-ARCHITECTURE.md](./SLACK-BOT-ARCHITECTURE.md)

---

**Last Updated**: 2025-12-31  
**Status**: Phase 1 Complete (Q1, Q4)  
**Next**: Add Q2 (short-write), Q3 (long-read) commands
