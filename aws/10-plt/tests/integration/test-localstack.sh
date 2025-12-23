#!/bin/bash
# Test EventBridge -> SQS flow on LocalStack

set -e

ENDPOINT="http://localhost:4566"
REGION="ca-central-1"

echo "=== LocalStack Test ==="
echo ""

# Send event to EventBridge
echo "[1/3] Sending event to EventBridge..."
awslocal events put-events \
  --region "$REGION" \
  --endpoint-url "$ENDPOINT" \
  --entries '[
    {
      "Source": "slack.command",
      "DetailType": "Slack Command",
      "Detail": "{\"command\":\"/echo\",\"text\":\"hello localstack\"}",
      "EventBusName": "laco-plt-chatbot"
    }
  ]'

echo "✓ Event sent"
echo ""

# Wait for routing
echo "[2/3] Waiting 2 seconds..."
sleep 2
echo "✓ Done"
echo ""

# Receive from SQS
echo "[3/3] Receiving from SQS..."
MESSAGE=$(awslocal sqs receive-message \
  --region "$REGION" \
  --endpoint-url "$ENDPOINT" \
  --queue-url http://localhost:4566/000000000000/laco-plt-chatbot-echo \
  --max-number-of-messages 1 \
  --wait-time-seconds 5 \
  --query 'Messages[0].Body' \
  --output text)

if [ -n "$MESSAGE" ] && [ "$MESSAGE" != "None" ]; then
  echo "✓ Message received:"
  echo "$MESSAGE" | jq
  echo ""
  echo "=== TEST PASSED ==="
else
  echo "⚠ No message received"
  echo "=== TEST FAILED ==="
  exit 1
fi
