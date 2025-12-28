#!/bin/bash
# -----------------------------------------------------------------------------
# Router Lambda Integration Test
# Tests Lambda -> EventBridge -> SQS integration
# -----------------------------------------------------------------------------

set -e

REGION="ca-central-1"
FUNCTION_NAME="laco-plt-slack-router"
EVENTBUS_NAME="laco-plt-chatbot"
QUEUE_NAME="laco-plt-chatbot-echo"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Router Lambda Integration Test ===${NC}"
echo ""

# Step 1: Check Lambda function exists
echo -e "${YELLOW}[1/5] Checking Lambda function...${NC}"
LAMBDA_EXISTS=$(aws lambda get-function \
  --function-name "$FUNCTION_NAME" \
  --region "$REGION" \
  --query 'Configuration.FunctionName' \
  --output text 2>/dev/null || echo "")

if [ -z "$LAMBDA_EXISTS" ]; then
  echo -e "${RED}✗ Lambda function not found${NC}"
  echo "Deploy with: make deploy-router"
  exit 1
fi

echo -e "${GREEN}✓ Lambda function exists${NC}"

# Show Lambda config
LAMBDA_CONFIG=$(aws lambda get-function-configuration \
  --function-name "$FUNCTION_NAME" \
  --region "$REGION" \
  --query '{Runtime:Runtime,Memory:MemorySize,Timeout:Timeout,LastModified:LastModified}' \
  --output json)

echo "$LAMBDA_CONFIG" | jq
echo ""

# Step 2: Get SQS Queue URL for verification
echo -e "${YELLOW}[2/5] Getting SQS queue URL...${NC}"
QUEUE_URL=$(aws sqs get-queue-url \
  --queue-name "$QUEUE_NAME" \
  --region "$REGION" \
  --query 'QueueUrl' \
  --output text)

if [ -z "$QUEUE_URL" ]; then
  echo -e "${RED}✗ Queue not found${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Queue URL: $QUEUE_URL${NC}"
echo ""

# Step 3: Purge queue to start clean
echo -e "${YELLOW}[3/5] Purging queue for clean test...${NC}"
aws sqs purge-queue \
  --queue-url "$QUEUE_URL" \
  --region "$REGION" 2>/dev/null || true
sleep 2
echo -e "${GREEN}✓ Queue purged${NC}"
echo ""

# Step 4: Prepare test event with valid signature
echo -e "${YELLOW}[4/5] Preparing test event...${NC}"

# Get signing secret from Parameter Store or env var
if [ -n "$SLACK_SIGNING_SECRET" ]; then
  SIGNING_SECRET="$SLACK_SIGNING_SECRET"
else
  echo "  Getting signing secret from Parameter Store..."
  SIGNING_SECRET=$(aws ssm get-parameter \
    --name "/laco/plt/aws/secrets/slack/signing-secret" \
    --with-decryption \
    --region "$REGION" \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")
fi

if [ -z "$SIGNING_SECRET" ]; then
  echo -e "${YELLOW}⚠ No signing secret available${NC}"
  echo "  Set SLACK_SIGNING_SECRET env var or add to Parameter Store"
  echo "  Using test mode without signature validation..."
  TIMESTAMP="0"
  SIGNATURE="test"
else
  echo -e "${GREEN}✓ Signing secret retrieved${NC}"

  # Generate valid Slack signature
  TIMESTAMP=$(date +%s)
  BODY="command=/echo&text=integration test $TIMESTAMP&response_url=https://hooks.slack.com/test&user_id=U123TEST&user_name=integration-test&channel_id=C123TEST&team_id=T123TEST"
  SIG_BASE_STRING="v0:${TIMESTAMP}:${BODY}"
  SIGNATURE=$(echo -n "$SIG_BASE_STRING" | openssl dgst -sha256 -hmac "$SIGNING_SECRET" -hex | awk '{print $2}')
fi

TEST_EVENT=$(cat <<EOF
{
  "version": "2.0",
  "routeKey": "POST /slack/commands",
  "rawPath": "/slack/commands",
  "headers": {
    "content-type": "application/x-www-form-urlencoded",
    "x-slack-request-timestamp": "$TIMESTAMP",
    "x-slack-signature": "v0=$SIGNATURE"
  },
  "body": "command=/echo&text=integration test $(date +%s)&response_url=https://hooks.slack.com/test&user_id=U123TEST&user_name=integration-test&channel_id=C123TEST&team_id=T123TEST"
}
EOF
)

echo "$TEST_EVENT" > /tmp/router-test-event.json

echo "  Invoking Lambda..."
INVOKE_RESULT=$(aws lambda invoke \
  --function-name "$FUNCTION_NAME" \
  --region "$REGION" \
  --payload file:///tmp/router-test-event.json \
  --cli-binary-format raw-in-base64-out \
  /tmp/router-test-response.json 2>&1)

INVOKE_STATUS=$?

if [ $INVOKE_STATUS -ne 0 ]; then
  echo -e "${RED}✗ Lambda invocation failed${NC}"
  echo "$INVOKE_RESULT"
  exit 1
fi

echo -e "${GREEN}✓ Lambda invoked successfully${NC}"

# Show response
echo ""
echo -e "${BLUE}Lambda response:${NC}"
cat /tmp/router-test-response.json | jq '.' 2>/dev/null || cat /tmp/router-test-response.json
echo ""

# Step 5: Verify message in SQS queue
echo -e "${YELLOW}[5/5] Verifying EventBridge -> SQS routing...${NC}"
sleep 5  # Wait for EventBridge routing

MESSAGES=$(aws sqs receive-message \
  --queue-url "$QUEUE_URL" \
  --region "$REGION" \
  --max-number-of-messages 1 \
  --wait-time-seconds 10 \
  --output json 2>/dev/null)

MESSAGE_COUNT=$(echo "$MESSAGES" | jq '.Messages | length' 2>/dev/null || echo "0")

# Ensure MESSAGE_COUNT is a number
MESSAGE_COUNT=${MESSAGE_COUNT:-0}

if [ "$MESSAGE_COUNT" -gt 0 ] 2>/dev/null; then
  echo -e "${GREEN}✓ Message received in SQS queue${NC}"
  echo ""

  # Show message content
  MESSAGE_BODY=$(echo "$MESSAGES" | jq -r '.Messages[0].Body')
  echo -e "${BLUE}Message content:${NC}"
  echo "$MESSAGE_BODY" | jq '.'

  # Verify message contains expected command
  if echo "$MESSAGE_BODY" | jq -e '.command == "/echo"' > /dev/null; then
    echo ""
    echo -e "${GREEN}✓ Message contains correct command${NC}"
  fi

  # Clean up - delete test message
  RECEIPT_HANDLE=$(echo "$MESSAGES" | jq -r '.Messages[0].ReceiptHandle')
  aws sqs delete-message \
    --queue-url "$QUEUE_URL" \
    --region "$REGION" \
    --receipt-handle "$RECEIPT_HANDLE"

  echo ""
  echo -e "${GREEN}=== TEST PASSED ===${NC}"
  echo ""
  echo "Router Lambda successfully:"
  echo "  ✓ Received Slack command"
  echo "  ✓ Published to EventBridge"
  echo "  ✓ Routed to SQS queue"

else
  echo -e "${RED}✗ No message in SQS queue${NC}"
  echo ""
  echo -e "${YELLOW}Troubleshooting:${NC}"
  echo "  1. Check Lambda logs:"
  echo "     aws logs tail /aws/lambda/$FUNCTION_NAME --region $REGION --since 5m"
  echo ""
  echo "  2. Check EventBridge rules:"
  echo "     aws events list-rules --event-bus-name $EVENTBUS_NAME --region $REGION"
  echo ""
  echo "  3. Check SQS permissions for EventBridge"
  echo ""
  echo -e "${RED}=== TEST FAILED ===${NC}"
  exit 1
fi

# Check for errors in logs
echo ""
echo -e "${BLUE}Checking Lambda logs...${NC}"
RECENT_LOGS=$(aws logs tail "/aws/lambda/$FUNCTION_NAME" \
  --region "$REGION" \
  --since 2m \
  --format short 2>/dev/null | tail -20)

if [ -n "$RECENT_LOGS" ]; then
  echo "$RECENT_LOGS"
else
  echo -e "${YELLOW}No recent logs found${NC}"
fi

# Clean up
rm -f /tmp/router-test-event.json /tmp/router-test-response.json

echo ""
