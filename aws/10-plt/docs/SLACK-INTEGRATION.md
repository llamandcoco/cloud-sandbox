# Slack Integration Guide

This guide explains how to integrate the deployed chatbot infrastructure with Slack for production use.

## Architecture Overview

```
Slack Workspace → API Gateway → Router Lambda → EventBridge → SQS → Worker Lambda → Slack API
```

**Components:**
- **API Gateway**: `https://{API_GATEWAY_ID}.execute-api.ca-central-1.amazonaws.com/prod/slack`
- **Router Lambda**: `laco-plt-slack-router`
- **EventBridge Bus**: `laco-plt-chatbot`
- **Worker Lambdas**: `echo-worker`, `deploy-worker`, `status-worker`

**Note:** Replace `{API_GATEWAY_ID}` with your deployed API Gateway ID (found via `aws apigateway get-rest-apis`)

---

## 1. Create Slack App

1. Navigate to https://api.slack.com/apps
2. Click **"Create New App"** → **"From scratch"**
3. **App Name**: `Platform Bot` (or your preferred name)
4. **Development Slack Workspace**: Select your workspace
5. Click **"Create App"**

---

## 2. Configure Slash Commands

### Add Slash Commands

Navigate to **"Slash Commands"** in the left sidebar, then create the following commands:

#### /echo Command
- **Command**: `/echo`
- **Request URL**: `https://{API_GATEWAY_ID}.execute-api.ca-central-1.amazonaws.com/prod/slack`
- **Short Description**: `Echo a message asynchronously`
- **Usage Hint**: `[your message]`
- Click **"Save"**

#### /deploy Command
- **Command**: `/deploy`
- **Request URL**: `https://{API_GATEWAY_ID}.execute-api.ca-central-1.amazonaws.com/prod/slack`
- **Short Description**: `Deploy application`
- **Usage Hint**: `[deployment target]`
- Click **"Save"**

#### /status Command
- **Command**: `/status`
- **Request URL**: `https://{API_GATEWAY_ID}.execute-api.ca-central-1.amazonaws.com/prod/slack`
- **Short Description**: `Check deployment status`
- **Usage Hint**: `[optional: deployment id]`
- Click **"Save"**

### Important Notes

- All three commands use the **same Request URL**
- The router Lambda routes each command to the appropriate queue
- Commands respond immediately (<3s) and process asynchronously

---

## 3. Configure OAuth & Permissions

### Add Bot Token Scopes

1. Navigate to **"OAuth & Permissions"** in the left sidebar
2. Scroll to **"Scopes"** → **"Bot Token Scopes"**
3. Add the following scopes:

   - `commands` - Required for slash commands
   - `chat:write` - Required for sending messages to channels

4. Click **"Save Changes"**

### Install App to Workspace

1. Scroll up to **"OAuth Tokens for Your Workspace"**
2. Click **"Install to Workspace"**
3. Review permissions and click **"Allow"**
4. Copy the **"Bot User OAuth Token"** (starts with `xoxb-`)

---

## 4. Store Slack Credentials in AWS

### Signing Secret

The signing secret is used by the router Lambda to verify requests are from Slack.

1. Navigate to **"Basic Information"** in Slack App settings
2. Scroll to **"App Credentials"**
3. Copy the **"Signing Secret"**
4. Store in AWS Parameter Store:

```bash
aws ssm put-parameter \
  --name "/laco/plt/aws/secrets/slack/signing-secret" \
  --value "YOUR_SIGNING_SECRET_HERE" \
  --type "SecureString" \
  --region ca-central-1 \
  --overwrite
```

### Bot Token

The bot token is used by worker Lambdas to send responses back to Slack.

```bash
aws ssm put-parameter \
  --name "/laco/plt/aws/secrets/slack/bot-token" \
  --value "xoxb-YOUR-BOT-TOKEN" \
  --type "SecureString" \
  --region ca-central-1 \
  --overwrite
```

### Verify Secrets

```bash
# Check signing secret exists
aws ssm get-parameter \
  --name "/laco/plt/aws/secrets/slack/signing-secret" \
  --region ca-central-1 \
  --query 'Parameter.Name'

# Check bot token exists
aws ssm get-parameter \
  --name "/laco/plt/aws/secrets/slack/bot-token" \
  --region ca-central-1 \
  --query 'Parameter.Name'
```

---

## 5. Test the Integration

### Test /echo Command

1. Open your Slack workspace
2. In any channel, type: `/echo Hello from production!`
3. Expected behavior:
   - **Immediate response** (< 3 seconds): `Processing your /echo command...`
   - **Async response** (after 2-5 seconds):
     ```
     ✅ Async Response
     Hello from production!
     Requested by @YourName
     ```

### Test Other Commands

```bash
# Test deploy command
/deploy staging

# Test status command
/status

# Test unknown command (should route to echo as fallback)
/test-unknown This should go to echo queue
```

---

## 6. Monitor the System

### CloudWatch Logs

**Router Lambda:**
```bash
aws logs tail /aws/lambda/laco-plt-slack-router \
  --follow \
  --region ca-central-1
```

**Echo Worker Lambda:**
```bash
aws logs tail /aws/lambda/laco-plt-chatbot-echo-worker \
  --follow \
  --region ca-central-1
```

### SQS Queue Metrics

**Check queue depth:**
```bash
aws sqs get-queue-attributes \
  --queue-url https://sqs.ca-central-1.amazonaws.com/{AWS_ACCOUNT_ID}/laco-plt-chatbot-echo \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
  --region ca-central-1
```

### EventBridge Metrics

**Check rule invocations:**
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/Events \
  --metric-name Invocations \
  --dimensions Name=RuleName,Value=laco-plt-chatbot-echo \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --region ca-central-1
```

### API Gateway Metrics

**Check request count and latency:**
```bash
# View API Gateway logs
aws logs tail /aws/apigateway/laco-plt-slack-bot \
  --follow \
  --region ca-central-1
```

---

## 7. Troubleshooting

### Issue: Slack shows "operation_timeout"

**Cause:** Router Lambda took more than 3 seconds to respond

**Solution:**
- Check Lambda CloudWatch logs for errors
- Verify EventBridge is healthy
- Ensure Lambda has adequate memory/timeout settings

### Issue: Immediate response received, but no async response

**Cause:** Worker Lambda not processing SQS messages

**Check:**
```bash
# Verify event source mapping is enabled
aws lambda list-event-source-mappings \
  --function-name laco-plt-chatbot-echo-worker \
  --region ca-central-1

# Check SQS queue has messages
aws sqs receive-message \
  --queue-url https://sqs.ca-central-1.amazonaws.com/{AWS_ACCOUNT_ID}/laco-plt-chatbot-echo \
  --max-number-of-messages 1 \
  --region ca-central-1
```

### Issue: "Invalid signature" error

**Cause:** Signing secret mismatch

**Solution:**
1. Get the current signing secret from Slack App settings
2. Update Parameter Store:
```bash
aws ssm put-parameter \
  --name "/laco/plt/aws/secrets/slack/signing-secret" \
  --value "NEW_SIGNING_SECRET" \
  --type "SecureString" \
  --region ca-central-1 \
  --overwrite
```
3. Restart the router Lambda (or wait for cold start)

### Issue: Duplicate responses

**Cause:** EventBridge catch-all rule matching known commands

**Solution:** Ensure the `chatbot-unknown` rule excludes known commands:
```json
{
  "source": ["slack.command"],
  "detail-type": ["Slack Command"],
  "detail": {
    "command": [{"anything-but": ["/echo", "/deploy", "/status"]}]
  }
}
```

---

## 8. Security Considerations

### Signing Secret Validation

- Router Lambda validates all requests using Slack's signature verification
- Requests with invalid signatures are rejected with 401 Unauthorized
- Timestamp validation prevents replay attacks (5-minute window)

### Principle of Least Privilege

- Bot token only has `commands` and `chat:write` scopes
- Lambda execution roles follow least privilege
- SQS queues only accessible by EventBridge and Lambda

### Secrets Management

- All secrets stored in AWS Systems Manager Parameter Store (SecureString)
- Secrets encrypted at rest with AWS KMS
- Lambda functions retrieve secrets at runtime (not in environment variables)

---

## 9. Updating the API Gateway URL

If the API Gateway is redeployed and gets a new URL:

1. Get the new URL:
```bash
aws apigateway get-rest-apis \
  --region ca-central-1 \
  --query "items[?name=='laco-plt-slack-bot'].id" \
  --output text
```

2. Construct the URL:
```
https://{API_ID}.execute-api.ca-central-1.amazonaws.com/prod/slack
```

3. Update all slash commands in Slack App settings with the new URL

---

## 10. Next Steps

### Deploy Additional Workers

Currently only the echo worker is deployed. To add deploy and status workers:

```bash
# Deploy deploy worker
cd chatbot-deploy-lambda
terragrunt apply

# Deploy status worker
cd chatbot-status-lambda
terragrunt apply
```

### Add More Slash Commands

1. Create new SQS queue in `chatbot-{command}-sqs/`
2. Add EventBridge rule in `chatbot-eventbridge/`
3. Deploy worker Lambda in `chatbot-{command}-lambda/`
4. Add slash command in Slack App settings

### Set Up Alerts

Create CloudWatch Alarms for:
- API Gateway 5xx errors
- Lambda execution errors
- SQS DLQ depth
- EventBridge failed invocations

---

## Reference

### AWS Resources

| Resource | Name/ID | Purpose |
|----------|---------|---------|
| API Gateway | `laco-plt-slack-bot` | Receives Slack webhooks |
| Router Lambda | `laco-plt-slack-router` | Validates and routes commands |
| EventBridge Bus | `laco-plt-chatbot` | Routes events to queues |
| Echo Queue | `laco-plt-chatbot-echo` | Holds /echo commands |
| Echo Worker | `laco-plt-chatbot-echo-worker` | Processes /echo commands |

### Environment Variables

Router Lambda:
- `EVENT_BUS_NAME`: `laco-plt-chatbot`
- `SIGNING_SECRET_PARAM`: `/laco/plt/aws/secrets/slack/signing-secret`

Worker Lambdas:
- `BOT_TOKEN_PARAM`: `/laco/plt/aws/secrets/slack/bot-token`

### Slack App Info

- App ID: Find in "Basic Information"
- Client ID: Find in "Basic Information"
- Client Secret: Find in "Basic Information"
- Signing Secret: Find in "Basic Information"
- Bot Token: Find in "OAuth & Permissions" after installation
