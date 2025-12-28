# Integration Tests

Integration tests verify that AWS services work together correctly in the chatbot system.

## Available Tests

### test-echo-worker.sh

Tests the SQS → Lambda integration with the echo worker.

**What it tests:**
1. Gets the SQS queue URL
2. Checks Lambda function configuration
3. Sends a test message to SQS
4. Waits for Lambda to process the message
5. Verifies Lambda execution in CloudWatch Logs

**Usage:**
```bash
./test-echo-worker.sh
```

**Expected output:**
```
=== Echo Worker Integration Test ===

[1/5] Getting SQS queue URL...
✓ Queue URL: https://sqs.ca-central-1.amazonaws.com/...

[2/5] Checking Lambda function...
✓ Lambda function exists

[3/5] Sending test message to SQS...
✓ Message sent

[4/5] Waiting for Lambda to process...
✓ Wait complete

[5/5] Checking Lambda execution logs...
✓ Lambda processed message successfully

=== TEST PASSED ===
```

### test-chatbot-flow.sh

Tests the complete EventBridge -> SQS integration flow.

**What it tests:**
1. Sends a Slack command event to EventBridge
2. Verifies EventBridge routes the event to SQS
3. Receives and validates the message from SQS
4. Cleans up by deleting the test message

**Usage:**
```bash
./test-chatbot-flow.sh
```

**Expected output:**
```
=== Chatbot EventBridge -> SQS Test ===

[1/4] Sending test event to EventBridge...
✓ Event sent to EventBridge

[2/4] Waiting 3 seconds for EventBridge routing...
✓ Wait complete

[3/4] Getting SQS queue URL...
✓ Queue URL: https://sqs.ca-central-1.amazonaws.com/...

[4/4] Receiving message from SQS...
✓ Message received!

Message Body:
{
  "command": "/echo",
  "text": "hello from local test",
  ...
}

✓ Message deleted from queue

=== TEST PASSED ===
```

### test-localstack.sh

Tests LocalStack environment setup and connectivity.

**What it tests:**
- LocalStack is running and accessible
- Required AWS services are available (SQS, EventBridge, Lambda)
- Basic service operations work

**Usage:**
```bash
./test-localstack.sh
```

## Prerequisites

### AWS Resources
Ensure these resources are deployed:
- EventBridge: `laco-plt-chatbot` event bus
- SQS Queue: `laco-plt-chatbot-echo`
- EventBridge Rule: Routes `slack.command` events to SQS

Deploy with:
```bash
cd ../../chatbot-eventbridge
terragrunt apply
```

### Environment Variables
```bash
export AWS_REGION=ca-central-1
export AWS_PROFILE=laco-plt
```

### Required Tools
- AWS CLI v2
- jq (for JSON processing)

## Configuration

Tests use these default values (configurable in scripts):

```bash
ORG_PREFIX="laco"
ENVIRONMENT="plt"
EVENT_BUS_NAME="${ORG_PREFIX}-${ENVIRONMENT}-chatbot"
QUEUE_NAME="${ORG_PREFIX}-${ENVIRONMENT}-chatbot-echo"
REGION="ca-central-1"
```

To customize, edit the variables at the top of each test script.

## Test Event Structure

The test sends this event to EventBridge:

```json
{
  "Source": "slack.command",
  "DetailType": "Slack Command",
  "Detail": {
    "command": "/echo",
    "text": "hello from local test",
    "response_url": "https://hooks.slack.com/test",
    "user_id": "U123TEST",
    "channel_id": "C123TEST"
  },
  "EventBusName": "laco-plt-chatbot"
}
```

## Troubleshooting

### No message received

**Possible causes:**
1. EventBridge rule not matching the event pattern
2. SQS policy blocking EventBridge
3. EventBridge target not configured

**Debug:**
```bash
# Check EventBridge rule
aws events list-rules --event-bus-name laco-plt-chatbot

# Check rule targets
aws events list-targets-by-rule \
  --rule <rule-name> \
  --event-bus-name laco-plt-chatbot

# Check SQS queue policy
aws sqs get-queue-attributes \
  --queue-url <queue-url> \
  --attribute-names Policy
```

### Event sent but routing takes too long

Increase wait time in the script:
```bash
# Change from 3 to 10 seconds
sleep 10
```

### Permission denied errors

Verify AWS credentials:
```bash
aws sts get-caller-identity
```

Ensure your IAM role/user has permissions for:
- `events:PutEvents`
- `sqs:GetQueueUrl`
- `sqs:ReceiveMessage`
- `sqs:DeleteMessage`

## Adding New Tests

To add a new integration test:

1. Create new test script:
   ```bash
   touch test-new-feature.sh
   chmod +x test-new-feature.sh
   ```

2. Use this template:
   ```bash
   #!/bin/bash
   set -e

   # Configuration
   REGION="ca-central-1"

   # Colors
   GREEN='\033[0;32m'
   BLUE='\033[0;34m'
   YELLOW='\033[1;33m'
   NC='\033[0m'

   echo -e "${BLUE}=== Your Test Name ===${NC}\n"

   # Test steps...
   ```

3. Document the test in this README

## CI/CD Integration

These tests can be integrated into CI/CD pipelines:

```yaml
# GitHub Actions example
- name: Run Integration Tests
  run: |
    cd tests/integration
    ./test-chatbot-flow.sh
```

For CI environments, consider:
- Using AWS credentials from secrets
- Running against dedicated test environment
- Capturing test artifacts/logs
