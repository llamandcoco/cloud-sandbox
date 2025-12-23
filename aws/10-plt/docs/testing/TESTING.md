# Chatbot Local Testing Guide

Local testing methods for EventBridge → SQS integration.

## Method 1: Test with Real AWS Resources (Recommended)

Test deployed resources from your local terminal using AWS CLI.

### Prerequisites
```bash
# Verify AWS CLI installation
aws --version

# Install jq (for JSON parsing)
brew install jq  # macOS
```

### 1. Deploy Resources
```bash
# Deploy SQS
cd chatbot-echo-sqs
terragrunt apply

# Deploy EventBridge
cd ../chatbot-eventbridge
terragrunt apply
```

### 2. Run Test
```bash
cd /Users/lama/workspace/llamandcoco/cloud-sandbox/aws/10-plt
./test-chatbot-flow.sh
```

### 3. Expected Output
```
=== Chatbot EventBridge -> SQS Test ===

[1/4] Sending test event to EventBridge...
✓ Event sent to EventBridge

[2/4] Waiting 3 seconds for EventBridge routing...
✓ Wait complete

[3/4] Getting SQS queue URL...
✓ Queue URL: https://sqs.ca-central-1.amazonaws.com/.../laco-plt-chatbot-echo

[4/4] Receiving message from SQS...
✓ Message received!

Message Body:
{
  "command": "/echo",
  "text": "hello from local test",
  "response_url": "https://hooks.slack.com/test",
  "user_id": "U123TEST",
  "channel_id": "C123TEST"
}

✓ Message deleted from queue

=== TEST PASSED ===
```

### Manual Testing

Test manually without using the script:

```bash
# 1. Send event to EventBridge
aws events put-events \
  --region ca-central-1 \
  --entries '[
    {
      "Source": "slack.command",
      "DetailType": "Slack Command",
      "Detail": "{\"command\":\"/echo\",\"text\":\"test\"}",
      "EventBusName": "laco-plt-chatbot"
    }
  ]'

# 2. Check SQS for message (wait 3 seconds)
aws sqs receive-message \
  --region ca-central-1 \
  --queue-url https://sqs.ca-central-1.amazonaws.com/.../laco-plt-chatbot-echo \
  --max-number-of-messages 1 \
  --wait-time-seconds 10

# 3. Check DLQ (if message failed)
aws sqs receive-message \
  --region ca-central-1 \
  --queue-url https://sqs.ca-central-1.amazonaws.com/.../laco-plt-chatbot-echo-dlq \
  --max-number-of-messages 1
```

---

## Method 2: LocalStack (Fully Local Testing)

Test in local Docker environment without AWS.

### Prerequisites
```bash
# Install Docker Desktop
# Install awslocal CLI
brew install awscli-local  # macOS
pip install awscli-local    # Python
```

### 1. Start LocalStack
```bash
cd /Users/lama/workspace/llamandcoco/cloud-sandbox/aws/10-plt
docker-compose -f docker-compose.localstack.yml up -d

# Check logs
docker-compose -f docker-compose.localstack.yml logs -f
```

### 2. Verify Initialization
```bash
# Verify LocalStack created resources
awslocal sqs list-queues
awslocal events list-event-buses
awslocal events list-rules --event-bus-name laco-plt-chatbot
```

### 3. Run Test
```bash
./test-localstack.sh
```

### 4. Expected Output
```
=== LocalStack Test ===

[1/3] Sending event to EventBridge...
✓ Event sent

[2/3] Waiting 2 seconds...
✓ Done

[3/3] Receiving from SQS...
✓ Message received:
{
  "command": "/echo",
  "text": "hello localstack"
}

=== TEST PASSED ===
```

### Cleanup LocalStack
```bash
docker-compose -f docker-compose.localstack.yml down
```

---

## Method 3: Pre-deployment Validation with Terragrunt Plan

Validate configuration before deployment:

```bash
# Syntax validation
cd chatbot-echo-sqs
terragrunt validate

# Preview changes (no actual apply)
terragrunt plan

# Validate policy JSON
terragrunt show -json | jq '.values.root_module.resources[] | select(.type == "aws_sqs_queue_policy")'
```

---

## Troubleshooting

### Messages Not Arriving in SQS

1. **Check EventBridge Rules**
   ```bash
   aws events list-rules --event-bus-name laco-plt-chatbot
   aws events list-targets-by-rule --rule laco-plt-chatbot-echo --event-bus-name laco-plt-chatbot
   ```

2. **Check SQS Policy**
   ```bash
   QUEUE_URL=$(aws sqs get-queue-url --queue-name laco-plt-chatbot-echo --query 'QueueUrl' --output text)
   aws sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names Policy | jq -r '.Attributes.Policy' | jq
   ```

3. **Check EventBridge Failed Invocations**
   ```bash
   aws cloudwatch get-metric-statistics \
     --namespace AWS/Events \
     --metric-name FailedInvocations \
     --dimensions Name=RuleName,Value=laco-plt-chatbot-echo \
     --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 300 \
     --statistics Sum
   ```

4. **Check DLQ**
   ```bash
   # EventBridge DLQ (failed events)
   aws sqs receive-message \
     --queue-url https://sqs.ca-central-1.amazonaws.com/.../laco-plt-chatbot-echo-dlq \
     --max-number-of-messages 10
   ```

### CloudWatch Logs

EventBridge doesn't create CloudWatch Logs by default, but you can check archives:

```bash
# Check EventBridge archive (configured in chatbot-eventbridge)
aws events list-archives
aws events describe-archive --archive-name laco-plt-chatbot-archive
```

---

## Recommended Testing Workflow

1. **Development**: Use LocalStack (fast iteration)
2. **Pre-deployment**: Run `terragrunt plan` + `validate`
3. **Post-deployment**: Run AWS test scripts
4. **CI/CD**: Integrate test scripts into GitHub Actions

---

## Additional Test Cases

### Test Unknown Command (routes to echo queue)
```bash
aws events put-events \
  --region ca-central-1 \
  --entries '[
    {
      "Source": "slack.command",
      "DetailType": "Slack Command",
      "Detail": "{\"command\":\"/unknown\",\"text\":\"test\"}",
      "EventBusName": "laco-plt-chatbot"
    }
  ]'
```

### Test Deploy Command
```bash
aws events put-events \
  --region ca-central-1 \
  --entries '[
    {
      "Source": "slack.command",
      "DetailType": "Slack Command",
      "Detail": "{\"command\":\"/deploy\",\"text\":\"production\"}",
      "EventBusName": "laco-plt-chatbot"
    }
  ]'

# Check deploy queue
aws sqs receive-message \
  --region ca-central-1 \
  --queue-url https://sqs.ca-central-1.amazonaws.com/.../laco-plt-chatbot-deploy
```

---

## Cost Optimization

- **LocalStack**: Free for development (no AWS costs)
- **AWS Testing**: Minimal cost
  - EventBridge: Free tier (14M events/month)
  - SQS: Free tier (1M requests/month)
  - Estimated cost: < $0.01 per test run

---

## Integration with CI/CD

Example GitHub Actions workflow:

```yaml
name: Test Chatbot Infrastructure

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: ${{ secrets.AWS_ROLE }}
          aws-region: ca-central-1

      - name: Install dependencies
        run: |
          sudo apt-get install -y jq

      - name: Run integration tests
        run: |
          cd cloud-sandbox/aws/10-plt
          ./test-chatbot-flow.sh
```
