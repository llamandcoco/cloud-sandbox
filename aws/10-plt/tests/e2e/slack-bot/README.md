# Slack Bot E2E Tests

End-to-end tests for the Slack bot application, validating the complete flow from API Gateway to Worker Lambdas.

## Architecture Flow

```
Slack → API Gateway → Router Lambda → EventBridge → SQS → Worker Lambda → Slack API
  1          2              3               4          5          6            7
```

## Test Coverage

### Slack Router E2E: API Gateway → SQS (✅ Complete)
- **Script**: `test-slack-router-e2e.sh`
- **Coverage**: Steps 2 → 3 → 4 → 5
- **Validates**:
  - ✅ API Gateway receives Slack requests
  - ✅ Router Lambda validates Slack signatures
  - ✅ Response time < 3 seconds (Slack requirement)
  - ✅ EventBridge publishes events
  - ✅ SQS receives routed messages

### Worker Processing E2E (⏸️ Pending)
- **Script**: `test-slack-worker-e2e.sh` (future)
- **Coverage**: Steps 5 → 6 → 7
- **Validates**:
  - SQS → Worker Lambda invocation
  - Worker processes commands
  - Slack API responses delivered

### Full Integration E2E (⏸️ Pending)
- **Script**: `test-slack-full-e2e.sh` (future)
- **Coverage**: Steps 1 → 2 → 3 → 4 → 5 → 6 → 7
- **Validates**:
  - Real Slack app integration
  - Complete end-to-end flow

---

## Prerequisites

### 1. AWS Credentials

Configure AWS CLI with valid credentials:

```bash
# Check current credentials
aws sts get-caller-identity

# If needed, configure
aws configure
# or
export AWS_PROFILE=your-profile
```

### 2. Terraform Deployment

Deploy required infrastructure:

```bash
cd /Users/lama/workspace/llamandcoco/cloud-sandbox/aws/10-plt

# Deploy in order
cd chatbot-eventbridge && terragrunt apply
cd ../chatbot-echo-sqs && terragrunt apply
cd ../slack-router-lambda && terragrunt apply
cd ../slack-api-gateway && terragrunt apply
cd ../chatbot-echo-worker && terragrunt apply
```

### 3. Slack Signing Secret

Get the signing secret from Parameter Store:

```bash
export SLACK_SIGNING_SECRET=$(aws ssm get-parameter \
  --name /laco/plt/aws/secrets/slack/signing-secret \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text)
```

Or use a test secret for development:

```bash
export SLACK_SIGNING_SECRET="test-signing-secret-for-development"
```

---

## Running Slack Router E2E Test

### Quick Start

```bash
cd /Users/lama/workspace/llamandcoco/cloud-sandbox/aws/10-plt/tests/e2e/slack-bot

# Set signing secret (optional - auto-fetches from Parameter Store if not set)
export SLACK_SIGNING_SECRET="your-secret-here"

# Run test
./test-slack-router-e2e.sh
```

### Expected Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📤 SENDING TEST REQUEST
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ℹ Endpoint: POST https://abc123.execute-api.ca-central-1.amazonaws.com/slack/commands
ℹ Command: /echo
ℹ Text: Phase 3 E2E Test - 20241225-152030

Response:
{
  "response_type": "ephemeral",
  "text": "Processing your `/echo` command..."
}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 VERIFICATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✓ HTTP Status: 200 (OK)
✓ Response time: 0.285s (< 3s requirement)
✓ Response contains 'Processing' acknowledgment
✓ Lambda execution logged
✓ Message received in SQS queue!
✓ Message contains correct command
✓ Message contains test text

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ SLACK ROUTER E2E TEST PASSED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Troubleshooting

### AWS Credentials Invalid

```bash
# Error: InvalidClientTokenId
aws sts get-caller-identity

# Fix: Configure credentials
aws configure
# or
export AWS_PROFILE=your-profile
```

### Terraform Not Deployed

```bash
# Error: Failed to get API endpoint from Terraform

# Fix: Deploy infrastructure
cd /Users/lama/workspace/llamandcoco/cloud-sandbox/aws/10-plt/slack-router-lambda
terragrunt apply
cd ../slack-api-gateway
terragrunt apply
```

### No Messages in SQS

Possible causes:
1. EventBridge rules not configured
2. SQS policy doesn't allow EventBridge
3. EventBridge bus name mismatch

```bash
# Check EventBridge rules
aws events list-rules --event-bus-name laco-plt-chatbot

# Check SQS queue policy
aws sqs get-queue-attributes \
  --queue-url YOUR_QUEUE_URL \
  --attribute-names Policy
```

### Response Time > 3 Seconds

Slack requires responses within 3 seconds. If Lambda is slow:

1. Check Lambda cold start time
2. Optimize Lambda configuration (memory, architecture)
3. Consider provisioned concurrency

```bash
# Check Lambda metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=laco-plt-slack-router \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average,Maximum
```

---

## Next Steps

### After Router E2E Success

1. **Update TEST-COVERAGE.md**
   ```bash
   cd /Users/lama/workspace/llamandcoco/cloud-sandbox/aws/10-plt/docs/testing
   # Document test coverage updates
   ```

2. **Add Worker E2E Tests**
   - Test SQS → Worker Lambda → Slack API flow
   - Add `test-slack-worker-e2e.sh`
   - Validate deploy/status workers

3. **Full Integration E2E**
   - Connect real Slack app
   - Test `/echo`, `/deploy`, `/status` commands
   - Validate complete async response flow

---

## Reference

- **TEST-COVERAGE.md**: `/Users/lama/workspace/llamandcoco/cloud-sandbox/aws/10-plt/docs/testing/TEST-COVERAGE.md`
- **cloud-apps source**: `/Users/lama/workspace/llamandcoco/cloud-apps/applications/chatops/slack-bot/src/`
- **Terraform configs**: `/Users/lama/workspace/llamandcoco/cloud-sandbox/aws/10-plt/`
