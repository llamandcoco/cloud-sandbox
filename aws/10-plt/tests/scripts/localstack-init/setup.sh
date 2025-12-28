#!/bin/bash
# LocalStack initialization script
# Runs when LocalStack is ready

echo "Setting up chatbot infrastructure in LocalStack..."

REGION="ca-central-1"

# Create SQS queues
awslocal sqs create-queue --queue-name laco-plt-chatbot-echo-dlq --region $REGION
awslocal sqs create-queue --queue-name laco-plt-chatbot-echo --region $REGION \
  --attributes '{
    "VisibilityTimeout": "35",
    "MessageRetentionPeriod": "86400",
    "ReceiveMessageWaitTimeSeconds": "20"
  }'

# Create EventBridge event bus
awslocal events create-event-bus --name laco-plt-chatbot --region $REGION

# Get queue ARN
QUEUE_ARN=$(awslocal sqs get-queue-attributes \
  --region $REGION \
  --queue-url http://localhost:4566/000000000000/laco-plt-chatbot-echo \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' \
  --output text)

# Create EventBridge rule
awslocal events put-rule \
  --region $REGION \
  --name laco-plt-chatbot-echo \
  --event-bus-name laco-plt-chatbot \
  --event-pattern '{
    "source": ["slack.command"],
    "detail-type": ["Slack Command"],
    "detail": {
      "command": ["/echo"]
    }
  }' \
  --state ENABLED

# Add SQS as target
awslocal events put-targets \
  --region $REGION \
  --rule laco-plt-chatbot-echo \
  --event-bus-name laco-plt-chatbot \
  --targets "Id"="1","Arn"="$QUEUE_ARN"

echo "✓ LocalStack setup complete!"
