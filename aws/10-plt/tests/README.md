# Chatbot Testing Suite

This directory contains all testing code and configurations for the chatbot system.

## Directory Structure

```
tests/
├── integration/          # Integration tests
│   ├── test-chatbot-flow.sh
│   └── test-localstack.sh
├── docker/              # Docker and LocalStack configuration
│   └── docker-compose.localstack.yml
├── scripts/             # Test initialization scripts
│   └── localstack-init/
└── e2e/                 # End-to-End tests (future)
```

## Quick Start

### 1. Setup LocalStack Environment

Run AWS services locally for testing:

```bash
cd tests/docker
docker-compose -f docker-compose.localstack.yml up -d
```

#### If LocalStack container already exists

If the `chatbot-localstack` container was created previously, you can reuse it without recreating:

```bash
# Option A: Using Docker directly
docker start chatbot-localstack
docker logs -f chatbot-localstack

# Option B: Using Docker Compose (no recreation)
cd tests/docker
docker-compose -f docker-compose.localstack.yml start localstack
docker-compose -f docker-compose.localstack.yml ps
```

If you need to apply Compose changes but keep the existing container:

```bash
cd tests/docker
docker-compose -f docker-compose.localstack.yml up -d --no-recreate localstack
```

### 2. Run Integration Tests

Test EventBridge -> SQS flow:

```bash
cd tests/integration
./test-chatbot-flow.sh
```

## Test Types

### Integration Tests
Tests integration between AWS services:
- EventBridge event routing
- SQS message delivery
- Lambda function execution

Details: [integration/README.md](./integration/README.md)

### Docker/LocalStack
Provides local development and testing environment.

Details: [docker/README.md](./docker/README.md)

### E2E Tests (Planned)
Tests complete Slack workflow:
- Slack command -> Lambda -> SQS -> Worker

## Requirements

- AWS CLI v2
- Docker & Docker Compose
- jq (JSON processing)
- Bash 4.0+

## Environment Variables

Set these before running tests:

```bash
export AWS_REGION=ca-central-1
export AWS_PROFILE=laco-plt  # or your profile
```

## Test Execution Order

1. **Deploy Infrastructure** (terragrunt)
   ```bash
   cd ../chatbot-eventbridge
   terragrunt apply
   ```

2. **Start LocalStack** (for local testing)
   ```bash
   cd tests/docker
   docker-compose up -d
   ```

3. **Run Integration Tests**
   ```bash
   cd tests/integration
   ./test-chatbot-flow.sh
   ```

## Troubleshooting

### LocalStack Connection Failed
```bash
docker-compose logs -f localstack
```

### Container Name Conflict
If you see an error like:

```
Error response from daemon: Conflict. The container name "/chatbot-localstack" is already in use...
```

Resolve by either reusing or cleaning up the existing container:

```bash
# Reuse the existing container
docker start chatbot-localstack

# Or remove and recreate (if needed)
docker rm chatbot-localstack
cd tests/docker
docker-compose -f docker-compose.localstack.yml up -d

# For Compose-managed environments, gracefully reset
cd tests/docker
docker-compose -f docker-compose.localstack.yml down
docker-compose -f docker-compose.localstack.yml up -d
```

### Test Failures
Each test script provides detailed error messages.
Check:
- AWS resources deployed correctly
- Valid AWS credentials
- Correct region configuration

## Documentation

- [Architecture](../docs/architecture/SLACK-BOT-ARCHITECTURE.md)
- [Test Coverage](../docs/testing/TEST-COVERAGE.md)
- [Testing Guide](../docs/testing/TESTING.md)
