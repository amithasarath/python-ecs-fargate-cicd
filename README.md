# FastAPI ECS Fargate CI/CD

Automatically deploy FastAPI applications to AWS ECS Fargate when you push feature branches. Each `feature-*` branch gets its own container in ECR and ECS service.

## Architecture

- **Application**: FastAPI REST API
- **Container Registry**: Amazon ECR
- **Container Orchestration**: Amazon ECS Fargate
- **Load Balancer**: Application Load Balancer (ALB)
- **CI/CD**: GitHub Actions
- **Infrastructure**: AWS CLI scripts

## Features

- Automatic deployment of feature branches starting with `feature-*`
- Each feature branch gets its own ECS service and target group
- Docker images automatically pushed to ECR with branch-specific tags
- Health checks configured for all services
- CloudWatch logging enabled
- Simple setup using AWS CLI scripts

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **GitHub Repository** with this code
3. **AWS CLI** installed locally (v2 recommended)
4. **Docker** installed locally
5. **jq** installed (`brew install jq` on macOS)

## Quick Start

### 1. Configure AWS Credentials

```bash
aws configure
# Enter AWS Access Key ID
# Enter AWS Secret Access Key
# Enter region: us-east-1
# Enter output format: json
```

### 2. Deploy Infrastructure

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Run the setup script
./scripts/aws-setup.sh
```

This creates:
- VPC with 2 public subnets
- Internet Gateway and Route Tables
- Security Groups for ALB and ECS
- Application Load Balancer
- ECR Repository
- ECS Cluster
- IAM Roles for ECS tasks
- CloudWatch Log Group

**IMPORTANT**: Save the output! You'll need the ECR URL and ALB DNS.

### 3. Build and Deploy Initial Image

```bash
# The config is automatically saved during setup
./scripts/deploy-image.sh
```

Wait for deployment to complete (2-3 minutes).

### 4. Set Up GitHub Actions

Create GitHub Actions IAM user:

```bash
./scripts/create-github-user.sh
```

Add the credentials to GitHub:
1. Go to your repository → Settings → Secrets and variables → Actions
2. Add `AWS_ACCESS_KEY_ID` (from script output)
3. Add `AWS_SECRET_ACCESS_KEY` (from script output)

### 5. Push to GitHub

```bash
git add .
git commit -m "Initial setup"
git branch -M main
git push origin main
```

### 6. Test Feature Branch Deployment

```bash
# Create and push a feature branch
git checkout -b feature-test
echo "# Test" >> test.txt
git add test.txt
git commit -m "Test feature branch deployment"
git push origin feature-test
```

Go to GitHub Actions tab to watch the automatic deployment!

## Testing Locally

```bash
# Install dependencies
pip install -r requirements.txt

# Run the application
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Visit http://localhost:8000/docs for API documentation
```

## API Endpoints

All endpoints are accessible at your ALB URL (e.g., `http://fastapi-ecs-alb-123456789.us-east-1.elb.amazonaws.com`):

- `GET /` - Welcome message
- `GET /health` - Health check endpoint (used by ALB)
- `GET /docs` - Interactive Swagger UI documentation
- `GET /redoc` - ReDoc documentation
- `GET /items` - List all items
- `POST /items` - Create a new item
- `GET /items/{item_id}` - Get a specific item
- `PUT /items/{item_id}` - Update an item
- `DELETE /items/{item_id}` - Delete an item

## How It Works

### Feature Branch Workflow

1. You push a branch starting with `feature-` (e.g., `feature-new-endpoint`)
2. GitHub Actions workflow triggers automatically
3. Builds Docker image and tags it with branch name and commit SHA
4. Pushes image to ECR
5. Creates new ECS service (if first push) or updates existing service
6. Creates dedicated target group for the feature branch
7. Deploys container to ECS Fargate
8. Provides deployment summary with endpoint URL

### Infrastructure

```
GitHub Push (feature-*)
       ↓
GitHub Actions
       ↓
   Build Docker Image
       ↓
   Push to ECR
       ↓
   Deploy to ECS
       ↓
   ┌─────────────────────┐
   │   Load Balancer     │
   └─────────────────────┘
           │
      ┌────┴────┐
      │         │
   Main    Feature-Branch
   Service   Service(s)
```

## Configuration Files

The setup script creates `aws-config.sh` with all your infrastructure IDs:

```bash
# Load configuration in any script
source aws-config.sh
echo $ECR_URI
echo $ALB_DNS
```

## Monitoring and Management

### View Logs

```bash
# Tail logs for all services
aws logs tail /ecs/fastapi-ecs --follow --region us-east-1

# View specific service logs
aws ecs list-tasks --cluster fastapi-cluster --service-name fastapi-service --region us-east-1
```

### Check Service Status

```bash
source aws-config.sh

# List all services
aws ecs list-services --cluster $ECS_CLUSTER --region $AWS_REGION

# Describe main service
aws ecs describe-services --cluster $ECS_CLUSTER --services fastapi-service --region $AWS_REGION

# Check running tasks
aws ecs list-tasks --cluster $ECS_CLUSTER --region $AWS_REGION
```

### Access Application

```bash
source aws-config.sh

# Open in browser
open "http://$ALB_DNS"
open "http://$ALB_DNS/docs"

# Test health endpoint
curl "http://$ALB_DNS/health"
```

## Cleanup

### Remove a Feature Branch Deployment

```bash
source aws-config.sh

# Replace with your actual branch name
BRANCH_NAME="feature-test"
SERVICE_NAME="fastapi-feature-$BRANCH_NAME"
TG_NAME="tg-$BRANCH_NAME"

# Stop and delete service
aws ecs update-service --cluster $ECS_CLUSTER --service $SERVICE_NAME --desired-count 0 --region $AWS_REGION
aws ecs delete-service --cluster $ECS_CLUSTER --service $SERVICE_NAME --region $AWS_REGION

# Delete target group
TG_ARN=$(aws elbv2 describe-target-groups --names $TG_NAME --region $AWS_REGION --query 'TargetGroups[0].TargetGroupArn' --output text)
aws elbv2 delete-target-group --target-group-arn $TG_ARN --region $AWS_REGION
```

### Destroy All Infrastructure

**WARNING: This deletes everything!**

```bash
./scripts/cleanup.sh
```

## Cost Optimization

**Estimated monthly costs** (us-east-1):
- 1 Fargate task (0.25 vCPU, 0.5 GB): ~$7/month
- Application Load Balancer: ~$16/month
- ECR storage (<10 GB): ~$1/month
- Data transfer: ~$1-5/month
- **Total**: ~$25-30/month for main service

Each feature branch adds ~$7/month. Remember to delete feature services when done!

## Troubleshooting

### Service Won't Start

```bash
# Check recent logs
aws logs tail /ecs/fastapi-ecs --since 10m --region us-east-1

# Check task stopped reason
aws ecs list-tasks --cluster fastapi-cluster --desired-status STOPPED --region us-east-1
aws ecs describe-tasks --cluster fastapi-cluster --tasks <task-arn> --region us-east-1
```

### Health Checks Failing

```bash
# Get task details and public IP
aws ecs list-tasks --cluster fastapi-cluster --service-name fastapi-service --region us-east-1
aws ecs describe-tasks --cluster fastapi-cluster --tasks <task-arn> --region us-east-1

# Test health endpoint directly (get IP from above)
curl http://<task-ip>:8000/health
```

### Cannot Push to ECR

```bash
# Re-authenticate
source aws-config.sh
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_URI
```

### GitHub Actions Fails

1. Check GitHub Secrets are set correctly
2. Verify IAM user has required permissions
3. Ensure main infrastructure exists
4. Check workflow logs in GitHub Actions tab

## Security Best Practices

1. **Use Secrets Manager** - Store sensitive data in AWS Secrets Manager
2. **Enable HTTPS** - Add ACM certificate and HTTPS listener to ALB
3. **Restrict Security Groups** - Limit ALB ingress to specific IPs if needed
4. **Enable VPC Flow Logs** - Monitor network traffic
5. **Rotate Credentials** - Regularly rotate IAM access keys
6. **Use IAM Roles** - Prefer IAM roles over access keys when possible
7. **Enable GuardDuty** - AWS threat detection service
8. **Enable Container Insights** - Already enabled in ECS cluster

## Customization

### Change Region

Edit `scripts/aws-setup.sh`:
```bash
AWS_REGION="us-west-2"  # Change this
```

### Adjust Task Resources

Edit `scripts/aws-setup.sh`:
```bash
# In the task definition section, change:
"cpu": "512",      # 0.5 vCPU
"memory": "1024"   # 1 GB
```

Valid combinations:
- 256 CPU / 512, 1024, 2048 MB
- 512 CPU / 1024-4096 MB
- 1024 CPU / 2048-8192 MB
- 2048 CPU / 4096-16384 MB
- 4096 CPU / 8192-30720 MB

### Add Environment Variables

Edit your task definition or GitHub Actions workflow to add environment variables:
```json
{
  "name": "DATABASE_URL",
  "value": "your-db-url"
}
```

## Advanced Features

### Auto-Scaling

Add auto-scaling to handle traffic spikes:

```bash
# Register scalable target
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/fastapi-cluster/fastapi-service \
  --min-capacity 1 \
  --max-capacity 5 \
  --region us-east-1

# Create scaling policy
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/fastapi-cluster/fastapi-service \
  --policy-name cpu-scaling \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration file://scaling-policy.json \
  --region us-east-1
```

### Add HTTPS

1. Request ACM certificate for your domain
2. Add HTTPS listener to ALB
3. Update security group to allow port 443

### Custom Domain

1. Create Route 53 hosted zone
2. Create A record pointing to ALB
3. Update ACM certificate with domain name

## Project Structure

```
.
├── app/
│   ├── __init__.py
│   └── main.py              # FastAPI application
├── scripts/
│   ├── aws-setup.sh         # Infrastructure setup
│   ├── deploy-image.sh      # Build and deploy
│   ├── create-github-user.sh # IAM user for GitHub
│   └── cleanup.sh           # Delete all resources
├── .github/
│   └── workflows/
│       └── deploy-feature.yml # GitHub Actions workflow
├── Dockerfile               # Container definition
├── requirements.txt         # Python dependencies
├── .dockerignore
├── .gitignore
├── .env.example
└── README.md
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature-amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature-amazing-feature`)
5. Open a Pull Request

## Support

- **Issues**: https://github.com/your-username/your-repo/issues
- **Documentation**: This README and SETUP.md

## License

MIT License - feel free to use this project for your own applications!
