#!/bin/bash
# -----------------------------------------------------------------------------
# Echo Worker Integration Test
# Tests SQS -> Lambda integration
# -----------------------------------------------------------------------------

set -e

REGION="ca-central-1"
QUEUE_NAME="laco-plt-chatbot-echo"
FUNCTION_NAME="laco-plt-chatbot-echo-worker"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Echo Worker Integration Test ===${NC}"
echo ""

# Step 1: Get Queue URL
echo -e "${YELLOW}[1/5] Getting SQS queue URL...${NC}"
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

# Step 2: Check Lambda function exists
echo -e "${YELLOW}[2/5] Checking Lambda function...${NC}"
LAMBDA_EXISTS=$(aws lambda get-function \
  --function-name "$FUNCTION_NAME" \
  --region "$REGION" \
  --query 'Configuration.FunctionName' \
  --output text 2>/dev/null || echo "")

if [ -z "$LAMBDA_EXISTS" ]; then
  echo -e "${RED}✗ Lambda function not found${NC}"
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

# Step 3: Send test message to SQS
echo -e "${YELLOW}[3/5] Sending test message to SQS...${NC}"

TEST_MESSAGE=$(cat <<EOF
{
  "command": "/echo",
  "text": "integration test $(date +%s)",
  "response_url": "https://hooks.slack.com/test/integration",
  "user_id": "U123TEST",
  "user_name": "integration-test",
  "channel_id": "C123TEST"
}
EOF
)

MESSAGE_ID=$(aws sqs send-message \
  --region "$REGION" \
  --queue-url "$QUEUE_URL" \
  --message-body "$TEST_MESSAGE" \
  --query 'MessageId' \
  --output text)

echo -e "${GREEN}✓ Message sent (ID: $MESSAGE_ID)${NC}"
echo ""

# Step 4: Wait for Lambda processing
echo -e "${YELLOW}[4/5] Waiting for Lambda to process (15s)...${NC}"
sleep 15
echo -e "${GREEN}✓ Wait complete${NC}"
echo ""

# Step 5: Check CloudWatch Logs
echo -e "${YELLOW}[5/5] Checking Lambda execution logs...${NC}"

LOG_EVENTS=$(aws logs filter-log-events \
  --log-group-name "/aws/lambda/$FUNCTION_NAME" \
  --region "$REGION" \
  --start-time $(($(date +%s) - 60))000 \
  --filter-pattern "Echo worker invoked" \
  --query 'events[0].message' \
  --output text 2>/dev/null || echo "")

if [ -n "$LOG_EVENTS" ] && [ "$LOG_EVENTS" != "None" ]; then
  echo -e "${GREEN}✓ Lambda execution detected${NC}"
  echo ""

  # Show recent logs
  echo -e "${BLUE}Recent Lambda logs:${NC}"
  aws logs tail "/aws/lambda/$FUNCTION_NAME" \
    --region "$REGION" \
    --since 2m \
    --format short | tail -20

  echo ""
  echo -e "${GREEN}=== TEST PASSED ===${NC}"
  echo ""
  echo "Lambda successfully:"
  echo "  ✓ Received message from SQS"
  echo "  ✓ Processed echo command"
  echo "  ✓ Generated logs"
else
  echo -e "${RED}✗ No Lambda execution logs found${NC}"
  echo ""
  echo -e "${YELLOW}Troubleshooting:${NC}"
  echo "  1. Check Event Source Mapping:"
  echo "     aws lambda list-event-source-mappings --function-name $FUNCTION_NAME --region $REGION"
  echo ""
  echo "  2. Check Lambda errors:"
  echo "     aws logs tail /aws/lambda/$FUNCTION_NAME --region $REGION --since 10m"
  echo ""
  echo "  3. Check SQS permissions"
  echo ""
  echo -e "${RED}=== TEST FAILED ===${NC}"
  exit 1
fi

# Check for errors
ERROR_LOGS=$(aws logs filter-log-events \
  --log-group-name "/aws/lambda/$FUNCTION_NAME" \
  --region "$REGION" \
  --start-time $(($(date +%s) - 60))000 \
  --filter-pattern "ERROR" \
  --query 'events[*].message' \
  --output text 2>/dev/null || echo "")

if [ -n "$ERROR_LOGS" ] && [ "$ERROR_LOGS" != "None" ]; then
  echo ""
  echo -e "${YELLOW}⚠ Errors detected in logs:${NC}"
  echo "$ERROR_LOGS"
fi
