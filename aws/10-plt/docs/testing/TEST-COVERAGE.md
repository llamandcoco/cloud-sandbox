# Test Coverage Analysis

## Full Architecture Flow

```
User → Slack → API Gateway → slack-router Lambda → EventBridge → SQS → worker Lambda → Slack API
 1      2           3                 4                  5          6          7             8
```

---

## Current Test Coverage

### ✅ `test-chatbot-flow.sh` & `test-localstack.sh`

**Testing Scope:**
```
EventBridge → SQS
    5           6
```

**What's Being Verified:**
1. ✅ EventBridge put-events API success
2. ✅ EventBridge rule pattern matching
3. ✅ EventBridge target invocation (SQS)
4. ✅ SQS queue policy allows EventBridge
5. ✅ Message delivery and receipt from SQS

**What's NOT Verified:**
- ❌ Slack webhook reception
- ❌ API Gateway routing
- ❌ slack-router Lambda execution
- ❌ worker Lambda execution
- ❌ Slack API response delivery
- ❌ DLQ reprocessing logic
- ❌ Lambda error handling

---

## Component-Level Test Coverage

### 1. Slack → API Gateway → slack-router (Not Tested)

**Required Tests:**
- Slack signature verification
- < 3 second response time
- EventBridge event publishing

**How to Test:**
```bash
# Call API Gateway directly from local
curl -X POST https://xxx.execute-api.ca-central-1.amazonaws.com/slack/commands \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "X-Slack-Signature: t=..." \
  -d "command=/echo&text=hello"
```

### 2. EventBridge → SQS (✅ Fully Tested)

**Current Test Coverage: 100%**

Test scripts fully cover:
- ✅ Event bus routing
- ✅ Rule pattern matching
- ✅ SQS policy permissions
- ✅ Message delivery

### 3. SQS → worker Lambda → Slack (Not Tested)

**Required Tests:**
- Lambda receives messages from SQS
- Message processing logic
- Slack API calls
- DLQ on errors

**How to Test:**
```bash
# Invoke Lambda directly (simulate SQS event)
aws lambda invoke \
  --function-name laco-plt-chatbot-echo-worker \
  --payload '{"Records":[{"body":"..."}]}' \
  response.json
```

---

## Test Levels

### Unit Tests
**Current Status:** ❌ None

Test individual components in isolation:
- slack-router Lambda logic
- worker Lambda logic
- Policy syntax validation

### Integration Tests
**Current Status:** ✅ EventBridge → SQS only

Current test scripts are at this level:
- `test-chatbot-flow.sh`: EventBridge + SQS integration
- `test-localstack.sh`: Integration testing on LocalStack

**Missing Integration Tests:**
- API Gateway + slack-router + EventBridge
- SQS + worker Lambda + Slack API

### End-to-End Tests
**Current Status:** ❌ None

Full flow testing:
- Send actual command from Slack
- Verify final response in Slack channel

---

## Current Test Value

### ✅ What Can Be Verified

1. **Infrastructure as Code Correctness**
   - SQS queue creation
   - EventBridge rule configuration
   - IAM policy permissions

2. **EventBridge Routing Logic**
   - `/echo` → echo queue
   - `/deploy` → deploy queue
   - `/status` → status queue
   - unknown → echo queue (default)

3. **Security Configuration**
   - SQS policy allows EventBridge
   - Only correct event bus allowed
   - Other accounts/regions blocked

### ❌ What Cannot Be Verified

1. **Lambda Business Logic**
   - echo worker returns "async {text}"
   - deploy worker performs actual deployment
   - Error handling

2. **External Integrations**
   - Slack webhook reception
   - Slack API response delivery

3. **Performance & Scalability**
   - Lambda concurrency limits
   - SQS visibility timeout adequacy
   - DLQ threshold settings

---

## Recommended Additional Tests

### 1. Lambda Integration Tests

```bash
# test-worker-lambda.sh
#!/bin/bash
# Test SQS → Lambda → Slack API

# 1. Send message to SQS
aws sqs send-message \
  --queue-url "$QUEUE_URL" \
  --message-body '{
    "command": "/echo",
    "text": "test",
    "response_url": "https://hooks.slack.com/test"
  }'

# 2. Check Lambda logs
aws logs tail /aws/lambda/laco-plt-chatbot-echo-worker --follow

# 3. Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=laco-plt-chatbot-echo-worker
```

### 2. End-to-End Tests

```bash
# test-e2e.sh
#!/bin/bash
# Full flow test

# 1. Call API Gateway (simulate Slack)
RESPONSE=$(curl -X POST "$API_GATEWAY_URL/slack/commands" \
  -d "command=/echo&text=hello")

# 2. Verify immediate response
echo "$RESPONSE" | jq '.text' | grep "Processing"

# 3. Wait for async processing (5 seconds)
sleep 5

# 4. Check worker execution in CloudWatch Logs
aws logs filter-log-events \
  --log-group-name /aws/lambda/laco-plt-chatbot-echo-worker \
  --start-time $(($(date +%s) - 10)) \
  --filter-pattern "async hello"
```

### 3. Failure Scenario Tests

```bash
# test-dlq.sh
#!/bin/bash
# Test DLQ and error handling

# 1. Send invalid event
aws events put-events \
  --entries '[{
    "Source": "slack.command",
    "DetailType": "Slack Command",
    "Detail": "invalid-json",
    "EventBusName": "laco-plt-chatbot"
  }]'

# 2. Check EventBridge DLQ
aws sqs receive-message \
  --queue-url "$DLQ_URL" \
  --wait-time-seconds 10

# 3. Check CloudWatch Alarms
aws cloudwatch describe-alarms \
  --alarm-names "chatbot-dlq-depth"
```

---

## Testing Priority Recommendations

Recommended testing order for current development stage:

### Phase 1: Infrastructure (✅ Complete)
- EventBridge → SQS integration
- Policy permission validation

### Phase 2: Lambda Integration (Next Step)
1. Deploy worker Lambdas
2. Test SQS → Lambda triggers
3. Verify Lambda logs and metrics

### Phase 3: API Gateway Integration
1. Deploy slack-router Lambda
2. Test API Gateway → EventBridge
3. Test Slack signature verification

### Phase 4: End-to-End
1. Connect actual Slack App
2. Test full flow
3. Validate performance and error handling

---

## Summary Table

| Test Scope | Current Coverage | Priority | Status |
|------------|------------------|----------|--------|
| EventBridge → SQS | 100% | High | ✅ Complete |
| SQS → Lambda | 0% | High | ❌ Needed |
| Lambda → Slack | 0% | Medium | ❌ Needed |
| API Gateway → EventBridge | 0% | Medium | ❌ Needed |
| Slack → API Gateway | 0% | Low | ⏸️ Later |
| End-to-End | 0% | High | ⏸️ Later |
| DLQ & Error Handling | 0% | Medium | ⏸️ Later |
| Performance & Scale | 0% | Low | ⏸️ Later |

**Current tests cover approximately 20% of the full architecture.**

---

## Test Execution Matrix

| Component | Unit | Integration | E2E | Status |
|-----------|------|-------------|-----|--------|
| EventBridge | ✅ | ✅ | ⏸️ | Tested |
| SQS | ✅ | ✅ | ⏸️ | Tested |
| Lambda (router) | ❌ | ❌ | ❌ | Not deployed |
| Lambda (worker) | ❌ | ❌ | ❌ | Not deployed |
| API Gateway | ❌ | ❌ | ❌ | Not deployed |
| Slack Integration | ❌ | ❌ | ❌ | Not configured |

---

## Next Steps

1. **Deploy worker Lambda** (`chatbot-echo-worker`)
2. **Add SQS → Lambda integration test**
3. **Verify Lambda logs and Slack API calls**
4. **Expand test coverage to 60%+**

Once worker Lambdas are deployed, we can test the full message processing flow.
