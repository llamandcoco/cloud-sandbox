#!/bin/bash
# -----------------------------------------------------------------------------
# Chatbot Flow Test Script
# Tests EventBridge -> SQS integration locally
# -----------------------------------------------------------------------------

set -e

# Configuration
ORG_PREFIX="laco"
ENVIRONMENT="plt"
EVENT_BUS_NAME="${ORG_PREFIX}-${ENVIRONMENT}-chatbot"
QUEUE_NAME="${ORG_PREFIX}-${ENVIRONMENT}-chatbot-echo"
REGION="ca-central-1"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Chatbot EventBridge -> SQS Test ===${NC}\n"

# Step 1: Send test event to EventBridge
echo -e "${YELLOW}[1/4] Sending test event to EventBridge...${NC}"

# Use jq to properly construct the JSON payload
RESULT=$(aws events put-events \
  --region "$REGION" \
  --entries "$(jq -n \
    --arg detail '{"command":"/echo","text":"hello from local test","response_url":"https://hooks.slack.com/test","user_id":"U123TEST","channel_id":"C123TEST"}' \
    --arg bus "$EVENT_BUS_NAME" \
    '[{
      Source: "slack.command",
      DetailType: "Slack Command",
      Detail: $detail,
      EventBusName: $bus
    }]')" 2>&1)

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Event sent to EventBridge${NC}\n"
else
  echo -e "${YELLOW}✗ Failed to send event:${NC}"
  echo "$RESULT"
  exit 1
fi

# Step 2: Wait for EventBridge to route to SQS
echo -e "${YELLOW}[2/4] Waiting 3 seconds for EventBridge routing...${NC}"
sleep 3
echo -e "${GREEN}✓ Wait complete${NC}\n"

# Step 3: Get queue URL
echo -e "${YELLOW}[3/4] Getting SQS queue URL...${NC}"
QUEUE_URL=$(aws sqs get-queue-url \
  --region "$REGION" \
  --queue-name "$QUEUE_NAME" \
  --query 'QueueUrl' \
  --output text)

echo -e "${GREEN}✓ Queue URL: $QUEUE_URL${NC}\n"

# Step 4: Receive message from SQS
echo -e "${YELLOW}[4/4] Receiving message from SQS...${NC}"
MESSAGE=$(aws sqs receive-message \
  --region "$REGION" \
  --queue-url "$QUEUE_URL" \
  --max-number-of-messages 1 \
  --wait-time-seconds 10 \
  --query 'Messages[0]' \
  --output json)

if [ "$MESSAGE" != "null" ] && [ -n "$MESSAGE" ]; then
  echo -e "${GREEN}✓ Message received!${NC}\n"

  echo -e "${BLUE}Message Body:${NC}"
  echo "$MESSAGE" | jq -r '.Body' | jq

  # Delete message after reading
  RECEIPT_HANDLE=$(echo "$MESSAGE" | jq -r '.ReceiptHandle')
  aws sqs delete-message \
    --region "$REGION" \
    --queue-url "$QUEUE_URL" \
    --receipt-handle "$RECEIPT_HANDLE"

  echo -e "\n${GREEN}✓ Message deleted from queue${NC}"
  echo -e "\n${GREEN}=== TEST PASSED ===${NC}"
else
  echo -e "${YELLOW}⚠ No message received${NC}"
  echo -e "${YELLOW}Possible issues:${NC}"
  echo -e "  1. EventBridge rule not matching"
  echo -e "  2. SQS policy blocking EventBridge"
  echo -e "  3. EventBridge to SQS target not configured"
  echo -e "\n${YELLOW}=== TEST FAILED ===${NC}"
  exit 1
fi
