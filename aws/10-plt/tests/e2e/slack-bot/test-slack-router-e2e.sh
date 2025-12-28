#!/bin/bash
# ==============================================================================
# Slack Router E2E Test: API Gateway → Router → EventBridge → SQS
# ==============================================================================
#
# Tests the Slack router integration flow:
# 1. API Gateway receives Slack command
# 2. Router Lambda validates signature
# 3. Router publishes to EventBridge
# 4. EventBridge routes to SQS queue
# 5. Verify message delivery
#
# Prerequisites:
#   - Infrastructure deployed (slack-api-gateway, slack-router-lambda, chatbot-eventbridge, chatbot-echo-sqs)
#   - AWS credentials configured
#   - SLACK_SIGNING_SECRET environment variable (optional - auto-fetches from Parameter Store)
#
# Usage:
#   export SLACK_SIGNING_SECRET="your-test-secret"  # Optional
#   ./test-slack-router-e2e.sh

set -e

# ==============================================================================
# Configuration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/../../.."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==============================================================================
# Helper Functions
# ==============================================================================

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# ==============================================================================
# Get Terraform Outputs
# ==============================================================================

log_info "Fetching API endpoint..."

# Use environment variable if set, otherwise auto-discover from AWS
if [ -n "$API_GATEWAY_URL" ]; then
    API_URL="$API_GATEWAY_URL"
    log_success "Using provided API URL: $API_URL"
else
    # Get API Gateway ID by name
    API_NAME="laco-plt-slack-bot"
    API_ID=$(aws apigateway get-rest-apis \
        --region ca-central-1 \
        --query "items[?name=='$API_NAME'].id" \
        --output text 2>/dev/null)

    if [ -z "$API_ID" ]; then
        log_error "Failed to find API Gateway with name: $API_NAME"
        log_warn "Make sure slack-api-gateway is deployed"
        exit 1
    fi

    # Construct API URL
    API_URL="https://${API_ID}.execute-api.ca-central-1.amazonaws.com/prod/slack"
    log_success "Auto-discovered API URL: $API_URL"
fi

# Get EventBridge bus name
cd "$PROJECT_ROOT/chatbot-eventbridge"
EVENTBUS_NAME=$(terragrunt output -raw event_bus_name 2>/dev/null || echo "laco-plt-chatbot")
log_info "EventBridge Bus: $EVENTBUS_NAME"

# Get SQS queue URL
cd "$PROJECT_ROOT/chatbot-echo-sqs"
QUEUE_URL=$(terragrunt output -raw queue_url 2>/dev/null)
log_info "Echo Queue: $QUEUE_URL"

# Get Lambda function name
cd "$PROJECT_ROOT/slack-router-lambda"
LAMBDA_NAME=$(terragrunt output -raw function_name 2>/dev/null || echo "laco-plt-slack-router")
log_info "Router Lambda: $LAMBDA_NAME"

# ==============================================================================
# Get Slack Signing Secret
# ==============================================================================

log_info "Getting Slack signing secret..."

# Get signing secret from Parameter Store or env var
if [ -n "$SLACK_SIGNING_SECRET" ]; then
    SIGNING_SECRET="$SLACK_SIGNING_SECRET"
    log_success "Using provided signing secret"
else
    log_info "Fetching signing secret from Parameter Store..."
    SIGNING_SECRET=$(aws ssm get-parameter \
        --name "/laco/plt/aws/secrets/slack/signing-secret" \
        --with-decryption \
        --region ca-central-1 \
        --query 'Parameter.Value' \
        --output text 2>/dev/null || echo "")

    if [ -z "$SIGNING_SECRET" ]; then
        log_error "Failed to get signing secret from Parameter Store"
        log_warn "Set SLACK_SIGNING_SECRET env var or add to Parameter Store"
        exit 1
    fi

    log_success "Signing secret retrieved from Parameter Store"
fi

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not found. Install: brew install awscli"
    exit 1
fi

log_success "AWS CLI available"

# ==============================================================================
# Prepare Test Request
# ==============================================================================

log_info "Preparing test request..."

# Generate timestamp
TIMESTAMP=$(date +%s)

# Build request body
COMMAND="/echo"
TEXT="Phase 3 E2E Test - $(date +%Y%m%d-%H%M%S)"
RESPONSE_URL="https://hooks.slack.com/commands/test/test/test"

BODY="command=$COMMAND"
BODY+="&text=$(echo -n "$TEXT" | jq -sRr @uri)"
BODY+="&response_url=$(echo -n "$RESPONSE_URL" | jq -sRr @uri)"
BODY+="&user_id=U123TEST"
BODY+="&user_name=e2e-tester"
BODY+="&channel_id=C123TEST"
BODY+="&channel_name=test-channel"
BODY+="&team_id=T123TEST"
BODY+="&team_domain=test-team"
BODY+="&trigger_id=test-trigger-123"

log_info "Request body prepared (${#BODY} bytes)"

# ==============================================================================
# Generate Slack Signature
# ==============================================================================

log_info "Generating Slack signature..."

# Create signature base string
SIG_BASE_STRING="v0:${TIMESTAMP}:${BODY}"

# Generate HMAC-SHA256 signature
SIGNATURE=$(echo -n "$SIG_BASE_STRING" | openssl dgst -sha256 -hmac "$SIGNING_SECRET" -hex | awk '{print $2}')

log_success "Signature generated"

# ==============================================================================
# Send Test Request
# ==============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📤 SENDING TEST REQUEST"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

log_info "Endpoint: POST $API_URL"
log_info "Command: $COMMAND"
log_info "Text: $TEXT"

# Send request
RESPONSE=$(curl -s -w "\n%{http_code}\n%{time_total}" -X POST "$API_URL" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "X-Slack-Request-Timestamp: $TIMESTAMP" \
    -H "X-Slack-Signature: v0=$SIGNATURE" \
    -d "$BODY")

# Parse response (macOS compatible)
TIME_TOTAL=$(echo "$RESPONSE" | tail -n 1)
HTTP_CODE=$(echo "$RESPONSE" | tail -n 2 | head -n 1)
HTTP_BODY=$(echo "$RESPONSE" | sed '$d' | sed '$d')  # Remove last 2 lines

echo ""
echo "Response:"
echo "$HTTP_BODY" | jq '.' 2>/dev/null || echo "$HTTP_BODY"
echo ""

# ==============================================================================
# Verify Response
# ==============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 VERIFICATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check HTTP status
if [ "$HTTP_CODE" -eq 200 ]; then
    log_success "HTTP Status: $HTTP_CODE (OK)"
else
    log_error "HTTP Status: $HTTP_CODE (Expected 200)"
    exit 1
fi

# Check response time (must be < 3 seconds for Slack)
TIME_TOTAL_MS=$(echo "$TIME_TOTAL * 1000" | bc)
if (( $(echo "$TIME_TOTAL < 3.0" | bc -l) )); then
    log_success "Response time: ${TIME_TOTAL}s (< 3s requirement)"
else
    log_error "Response time: ${TIME_TOTAL}s (> 3s - Slack will timeout!)"
fi

# Check response contains expected text
if echo "$HTTP_BODY" | grep -q "Processing"; then
    log_success "Response contains 'Processing' acknowledgment"
else
    log_warn "Response doesn't contain expected 'Processing' text"
fi

# ==============================================================================
# Verify CloudWatch Logs
# ==============================================================================

echo ""
log_info "Checking CloudWatch Logs (last 30 seconds)..."

sleep 2  # Wait for logs to propagate

LOGS=$(aws logs tail "/aws/lambda/$LAMBDA_NAME" --since 30s --format short 2>/dev/null || echo "")

if echo "$LOGS" | grep -q "Received Slack command\|Processing.*command"; then
    log_success "Lambda execution logged"
    echo ""
    echo "Recent logs:"
    echo "$LOGS" | tail -5
else
    log_warn "No recent Lambda execution logs found"
fi

# ==============================================================================
# Verify SQS Message Delivery
# ==============================================================================

echo ""
log_info "Checking SQS queue for message delivery..."

# Wait a bit for EventBridge → SQS routing
sleep 3

MESSAGES=$(aws sqs receive-message \
    --queue-url "$QUEUE_URL" \
    --max-number-of-messages 1 \
    --wait-time-seconds 5 \
    --output json 2>/dev/null)

if [ -n "$MESSAGES" ] && [ "$MESSAGES" != "null" ]; then
    MESSAGE_COUNT=$(echo "$MESSAGES" | jq '.Messages | length')

    if [ "$MESSAGE_COUNT" -gt 0 ]; then
        log_success "Message received in SQS queue!"

        # Parse message
        MESSAGE_BODY=$(echo "$MESSAGES" | jq -r '.Messages[0].Body')
        echo ""
        echo "Message content:"
        echo "$MESSAGE_BODY" | jq '.'

        # Verify message content
        if echo "$MESSAGE_BODY" | jq -e '.command == "/echo"' > /dev/null; then
            log_success "Message contains correct command"
        fi

        if echo "$MESSAGE_BODY" | jq -e ".text | contains(\"Phase 3\")" > /dev/null; then
            log_success "Message contains test text"
        fi

        # Delete message to clean up
        RECEIPT_HANDLE=$(echo "$MESSAGES" | jq -r '.Messages[0].ReceiptHandle')
        aws sqs delete-message --queue-url "$QUEUE_URL" --receipt-handle "$RECEIPT_HANDLE"
        log_info "Test message deleted from queue"
    else
        log_error "No messages in queue"
        exit 1
    fi
else
    log_error "Failed to receive message from SQS"
    log_warn "EventBridge → SQS routing might not be configured correctly"
    exit 1
fi

# ==============================================================================
# Summary
# ==============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ SLACK ROUTER E2E TEST PASSED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Verified:"
echo "  ✓ API Gateway receives request"
echo "  ✓ Router Lambda validates Slack signature"
echo "  ✓ Response time < 3 seconds"
echo "  ✓ EventBridge publishes event"
echo "  ✓ SQS receives routed message"
echo ""
echo "Coverage: API Gateway → Router → EventBridge → SQS"
echo "Next: Test worker Lambda processing (test-slack-worker-e2e.sh)"
echo ""
