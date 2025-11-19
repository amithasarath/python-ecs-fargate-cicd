# Project Summary: FastAPI ECS Fargate CI/CD

## What This Project Does

This is a complete, production-ready setup for automatically deploying FastAPI applications to AWS ECS Fargate with GitHub Actions. When you push a branch starting with `feature-`, it automatically:

1. Builds a Docker container
2. Pushes it to Amazon ECR
3. Deploys it to ECS Fargate as a new service
4. Makes it accessible via an Application Load Balancer

## Project Structure

```
.
├── app/
│   ├── __init__.py
│   └── main.py                    # FastAPI application code
│
├── scripts/
│   ├── aws-setup.sh              # Creates all AWS infrastructure
│   ├── deploy-image.sh           # Builds and deploys Docker image
│   ├── create-github-user.sh     # Creates IAM user for GitHub Actions
│   └── cleanup.sh                # Deletes all AWS resources
│
├── .github/
│   └── workflows/
│       └── deploy-feature.yml    # GitHub Actions CI/CD workflow
│
├── Dockerfile                     # Container definition
├── requirements.txt               # Python dependencies
├── .dockerignore                  # Files to exclude from Docker
├── .gitignore                     # Files to exclude from Git
├── .env.example                   # Example environment variables
├── README.md                      # Comprehensive documentation
├── SETUP.md                       # Quick setup guide
└── PROJECT_SUMMARY.md            # This file
```

## Files Explained

### Application Files

**`app/main.py`**
- FastAPI application with sample CRUD endpoints
- Health check endpoint for ALB
- Environment-aware configuration
- CORS enabled
- Auto-generated OpenAPI docs

**`requirements.txt`**
- FastAPI web framework
- Uvicorn ASGI server
- Pydantic for data validation

**`Dockerfile`**
- Multi-stage build for smaller images
- Python 3.11 slim base
- Health check configured
- Runs on port 8000

### Infrastructure Scripts

**`scripts/aws-setup.sh`**
Creates complete AWS infrastructure:
- VPC with 2 public subnets across 2 AZs
- Internet Gateway and route tables
- Security groups for ALB and ECS tasks
- Application Load Balancer with target group
- ECR repository for Docker images
- ECS Fargate cluster
- IAM roles for ECS tasks
- CloudWatch log group
- ECS task definition
- Main ECS service

**`scripts/deploy-image.sh`**
- Builds Docker image locally
- Logs in to ECR
- Tags and pushes image
- Forces new ECS deployment
- Waits for deployment to complete

**`scripts/create-github-user.sh`**
- Creates IAM user: `github-actions-ecs`
- Attaches required policies (ECS, ECR, ELB)
- Generates access keys
- Outputs credentials for GitHub Secrets

**`scripts/cleanup.sh`**
Safely deletes all resources in order:
1. ECS services (main + feature branches)
2. Task definitions
3. ECS cluster
4. Load balancer and target groups
5. CloudWatch logs
6. ECR repository
7. Security groups
8. Network resources (IGW, subnets, route tables, VPC)
9. IAM roles

### CI/CD Files

**`.github/workflows/deploy-feature.yml`**
GitHub Actions workflow that triggers on `feature-*` branches:
1. Extracts branch name
2. Configures AWS credentials
3. Builds Docker image
4. Pushes to ECR with branch-specific tags
5. Gets base task definition
6. Registers new task definition with updated image
7. Creates/updates ECS service for the branch
8. Creates target group (if new service)
9. Waits for deployment to stabilize
10. Outputs deployment summary with endpoint URL

## How Feature Branch Deployment Works

### First Push to `feature-xyz`

1. GitHub Actions workflow triggers
2. Builds image tagged as `feature-xyz-{commit-sha}` and `feature-xyz-latest`
3. Pushes to ECR
4. Creates new target group: `tg-feature-xyz`
5. Creates new ECS service: `fastapi-feature-feature-xyz`
6. Registers service with target group
7. Task starts running
8. ALB health checks pass
9. Service is accessible via ALB DNS

### Subsequent Pushes

1. GitHub Actions workflow triggers
2. Builds new image with new commit SHA
3. Pushes to ECR
4. Updates existing task definition
5. Updates existing ECS service (forces new deployment)
6. ECS performs rolling update:
   - Starts new task with new image
   - Waits for health checks
   - Stops old task
7. Zero-downtime deployment complete

## AWS Resources Created

### Networking
- **VPC**: `10.0.0.0/16`
- **Subnet 1**: `10.0.1.0/24` (AZ 1)
- **Subnet 2**: `10.0.2.0/24` (AZ 2)
- **Internet Gateway**: For outbound internet access
- **Route Table**: Routes 0.0.0.0/0 to IGW

### Security
- **ALB Security Group**: Allows HTTP (80) from anywhere
- **ECS Security Group**: Allows 8000 from ALB only
- **IAM Execution Role**: For ECS to pull images and write logs
- **IAM Task Role**: For application to access AWS services

### Compute
- **ECS Cluster**: `fastapi-cluster` (Container Insights enabled)
- **Task Definition**: Fargate, 256 CPU, 512 MB memory
- **Main Service**: `fastapi-service` (1 task)
- **Feature Services**: One per feature branch

### Load Balancing
- **ALB**: `fastapi-ecs-alb` (Internet-facing)
- **Main Target Group**: `fastapi-ecs-tg-main` (port 8000)
- **Feature Target Groups**: One per feature branch
- **Listener**: HTTP port 80, forwards to target groups

### Container Registry
- **ECR Repository**: `fastapi-app`
- **Lifecycle Policy**: Keeps 10 recent images, removes untagged after 1 day

### Logging
- **CloudWatch Log Group**: `/ecs/fastapi-ecs`
- **Retention**: 7 days
- **Log Streams**: One per task

## Environment Variables

The application receives these environment variables:

### Main Service
- `ENVIRONMENT=production`
- `BRANCH_NAME=main`

### Feature Services
- `ENVIRONMENT=feature`
- `BRANCH_NAME=feature-xyz` (actual branch name)

## API Endpoints

All services expose these endpoints:

- `GET /` - Welcome message
- `GET /health` - Health check (returns status, timestamp, environment, branch)
- `GET /docs` - Swagger UI documentation
- `GET /redoc` - ReDoc documentation
- `GET /items` - List all items
- `POST /items` - Create item
- `GET /items/{id}` - Get item
- `PUT /items/{id}` - Update item
- `DELETE /items/{id}` - Delete item

## GitHub Secrets Required

Add these to your repository:

| Secret Name | Description | How to Get |
|------------|-------------|------------|
| `AWS_ACCESS_KEY_ID` | AWS access key | Run `./scripts/create-github-user.sh` |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key | Run `./scripts/create-github-user.sh` |

## Configuration File

**`aws-config.sh`** (auto-generated, not in git)

After running `./scripts/aws-setup.sh`, this file contains:
```bash
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID="123456789012"
export ECR_REPOSITORY="fastapi-app"
export ECR_URI="123456789012.dkr.ecr.us-east-1.amazonaws.com/fastapi-app"
export ECS_CLUSTER="fastapi-cluster"
export ECS_SERVICE="fastapi-service"
export VPC_ID="vpc-xxx"
export SUBNET1_ID="subnet-xxx"
export SUBNET2_ID="subnet-xxx"
export ALB_DNS="fastapi-ecs-alb-xxx.us-east-1.elb.amazonaws.com"
# ... and more
```

Source this file in scripts or terminal:
```bash
source aws-config.sh
echo "App URL: http://$ALB_DNS"
```

## Workflow for Common Tasks

### Initial Setup
```bash
./scripts/aws-setup.sh          # Create infrastructure (once)
./scripts/deploy-image.sh       # Deploy first image (once)
./scripts/create-github-user.sh # Create GitHub IAM user (once)
# Add secrets to GitHub (once)
git push origin main            # Push to GitHub (once)
```

### Daily Development
```bash
# Local development
git checkout -b feature-my-feature
# Edit app/main.py
python -m uvicorn app.main:app --reload  # Test locally

# Deploy to AWS
git add .
git commit -m "Add new feature"
git push origin feature-my-feature  # Automatic deployment!
```

### Update Main Service
```bash
git checkout main
# Edit app/main.py
git commit -am "Update API"
./scripts/deploy-image.sh  # Or push to trigger GitHub Actions
```

### Clean Up Feature Branch
```bash
source aws-config.sh
BRANCH="feature-my-feature"
aws ecs update-service --cluster $ECS_CLUSTER \
  --service fastapi-feature-$BRANCH --desired-count 0
aws ecs delete-service --cluster $ECS_CLUSTER \
  --service fastapi-feature-$BRANCH
```

### Destroy Everything
```bash
./scripts/cleanup.sh  # Deletes ALL resources
```

## Customization Points

### Change AWS Region
Edit `scripts/aws-setup.sh`:
```bash
AWS_REGION="us-west-2"
```

### Change Task Resources
Edit `scripts/aws-setup.sh`, in task definition:
```json
"cpu": "512",
"memory": "1024"
```

### Add Database
1. Create RDS instance
2. Add to ECS security group ingress
3. Add `DATABASE_URL` to task definition environment
4. Update `app/main.py` to connect

### Add HTTPS
1. Request ACM certificate
2. Add HTTPS listener to ALB
3. Update ALB security group for port 443

### Change Branch Pattern
Edit `.github/workflows/deploy-feature.yml`:
```yaml
on:
  push:
    branches:
      - 'dev-*'  # Change pattern
```

## Cost Breakdown

### Fixed Costs (Monthly)
- ALB: ~$16/month
- ECR storage (<10 GB): ~$1/month

### Variable Costs (Per Running Service)
- Fargate (0.25 vCPU, 512 MB): ~$7/month
- Data transfer: ~$1-5/month

### Example Scenarios
- **Main only**: $25/month
- **Main + 2 features**: $39/month
- **Main + 5 features**: $60/month

## Security Features

- VPC isolation
- Security groups with minimal permissions
- IAM roles (no hardcoded credentials in containers)
- ECR image scanning enabled
- Container Insights for monitoring
- CloudWatch logs retention
- Health checks configured

## Monitoring

### View Logs
```bash
aws logs tail /ecs/fastapi-ecs --follow
```

### Check Service Health
```bash
curl http://$ALB_DNS/health
```

### View ECS Console
```
https://console.aws.amazon.com/ecs/home?region=us-east-1#/clusters/fastapi-cluster
```

### View CloudWatch Logs
```
https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups/log-group/$252Fecs$252Ffastapi-ecs
```

## Limitations & Future Enhancements

### Current Limitations
- HTTP only (no HTTPS)
- No custom domain
- No auto-scaling
- No database
- No secrets management
- Feature branches share same ALB (no path-based routing)

### Possible Enhancements
- Add HTTPS with ACM
- Add Route 53 custom domain
- Implement auto-scaling
- Add RDS database
- Use AWS Secrets Manager
- Add path-based routing for feature branches
- Add automated tests in CI/CD
- Add Slack/email notifications
- Implement blue-green deployments
- Add monitoring dashboards

## Troubleshooting

See SETUP.md for common issues and solutions.

## Support & Documentation

- **Quick Start**: SETUP.md
- **Full Documentation**: README.md
- **This Summary**: PROJECT_SUMMARY.md

## License

MIT License - Free to use and modify for your projects!
