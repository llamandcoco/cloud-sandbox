# Docker & LocalStack Configuration

This directory contains Docker configurations for local development and testing using LocalStack.

## What is LocalStack?

LocalStack is a fully functional local AWS cloud stack that allows you to develop and test AWS applications offline without connecting to actual AWS services.

## Quick Start

### Start LocalStack

```bash
docker-compose up -d
```

### Check Status

```bash
docker-compose ps
docker-compose logs -f localstack
```

### Stop LocalStack

```bash
docker-compose down
```

## Configuration

### docker-compose.localstack.yml

Main configuration for LocalStack container:

**Ports:**
- `4566`: LocalStack gateway (unified endpoint for all services)
- `4510-4559`: External services port range

**Services Enabled:**
- SQS (Simple Queue Service)
- EventBridge (Events)
- Lambda (Functions)

**Environment Variables:**
- `DEBUG=1`: Enable verbose logging
- `PERSISTENCE=0`: Disable persistence (fresh state on restart)
- `LAMBDA_EXECUTOR=docker`: Run Lambda functions in Docker containers

**Volumes:**
- `/var/run/docker.sock`: Allows LocalStack to spawn Lambda containers
- `../scripts/localstack-init`: Initialization scripts

## Auto-Initialization

When LocalStack starts, it automatically runs scripts from `../scripts/localstack-init/setup.sh`.

**What gets created:**

1. **SQS Queues:**
   - `laco-plt-chatbot-echo-dlq` (Dead Letter Queue)
   - `laco-plt-chatbot-echo` (Main queue)

2. **EventBridge Resources:**
   - Event bus: `laco-plt-chatbot`
   - Rule: `laco-plt-chatbot-echo` (matches `/echo` commands)
   - Target: Routes events to SQS queue

## Using LocalStack

### AWS CLI with LocalStack

Use `awslocal` wrapper or configure AWS CLI:

**Option 1: awslocal (Recommended)**
```bash
pip install awscli-local
awslocal sqs list-queues
```

**Option 2: AWS CLI with endpoint**
```bash
aws --endpoint-url=http://localhost:4566 sqs list-queues
```

### Common Operations

**List queues:**
```bash
awslocal sqs list-queues
```

**Send test event:**
```bash
awslocal events put-events \
  --entries '[{
    "Source": "slack.command",
    "DetailType": "Slack Command",
    "Detail": "{\"command\":\"/echo\",\"text\":\"test\"}",
    "EventBusName": "laco-plt-chatbot"
  }]'
```

**Receive SQS message:**
```bash
awslocal sqs receive-message \
  --queue-url http://localhost:4566/000000000000/laco-plt-chatbot-echo
```

**List EventBridge rules:**
```bash
awslocal events list-rules --event-bus-name laco-plt-chatbot
```

## Testing Workflow

1. **Start LocalStack:**
   ```bash
   docker-compose up -d
   ```

2. **Wait for initialization:**
   ```bash
   docker-compose logs -f localstack
   # Wait for "✓ LocalStack setup complete!"
   ```

3. **Run tests:**
   ```bash
   cd ../integration
   ./test-localstack.sh
   ./test-chatbot-flow.sh
   ```

## Troubleshooting

### Container won't start

**Check Docker is running:**
```bash
docker ps
```

**Check logs:**
```bash
docker-compose logs localstack
```

### Services not available

**Verify services are running:**
```bash
curl http://localhost:4566/_localstack/health | jq
```

Expected output:
```json
{
  "services": {
    "sqs": "running",
    "events": "running",
    "lambda": "running"
  }
}
```

### Initialization script failed

**Check initialization logs:**
```bash
docker-compose logs localstack | grep "Setting up"
```

**Manually re-run setup:**
```bash
docker exec chatbot-localstack bash /etc/localstack/init/ready.d/setup.sh
```

### Lambda functions not executing

**Check Lambda executor:**
```bash
docker-compose logs localstack | grep -i lambda
```

Ensure `LAMBDA_EXECUTOR=docker` and Docker socket is mounted.

### Port conflicts

If port 4566 is already in use:

```yaml
# Edit docker-compose.localstack.yml
ports:
  - "14566:4566"  # Use different host port
```

Then update tests to use `http://localhost:14566`.

## Clean State

To start with fresh state:

```bash
docker-compose down -v  # Remove volumes
docker-compose up -d
```

## Resource Limits

LocalStack uses these limits by default:
- Memory: Uses Docker daemon defaults
- CPU: No limit

To set limits:

```yaml
services:
  localstack:
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 2G
```

## Advanced Configuration

### Enable Persistence

To persist data across restarts:

```yaml
environment:
  - PERSISTENCE=1
volumes:
  - ./localstack-data:/tmp/localstack
```

### Add More Services

```yaml
environment:
  - SERVICES=sqs,events,lambda,s3,dynamodb
```

### Custom Initialization

Add more scripts to `../scripts/localstack-init/`:
- Scripts run in alphabetical order
- Must be executable (`chmod +x`)
- Use `awslocal` command

## LocalStack vs Real AWS

**Differences to be aware of:**
- No actual IAM permissions enforced
- Some API behaviors may differ slightly
- CloudFormation support is limited in free tier
- Lambda execution environment may differ

**Best Practices:**
- Use LocalStack for quick iteration
- Test against real AWS before production
- Keep LocalStack version up to date

## Further Reading

- [LocalStack Documentation](https://docs.localstack.cloud)
- [LocalStack AWS CLI](https://docs.localstack.cloud/user-guide/integrations/aws-cli/)
- [Supported Services](https://docs.localstack.cloud/user-guide/aws/feature-coverage/)
