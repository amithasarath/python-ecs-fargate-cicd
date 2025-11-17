# Quick Setup Guide

Complete setup in 6 steps. Takes about 15 minutes.

## Prerequisites

Install these tools:

```bash
# macOS
brew install awscli jq
brew install --cask docker

# Verify installations
aws --version
jq --version
docker --version
```

## Step 1: AWS Configuration (2 min)

```bash
aws configure
```

Enter:
- AWS Access Key ID: (from AWS Console → IAM)
- AWS Secret Access Key: (from AWS Console)
- Region: `us-east-1`
- Output format: `json`

Verify:
```bash
aws sts get-caller-identity
```

## Step 2: Deploy Infrastructure (5 min)

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Run setup
./scripts/aws-setup.sh
```

**What this creates:**
- VPC (10.0.0.0/16)
- 2 Public Subnets
- Internet Gateway
- Security Groups
- Application Load Balancer
- ECR Repository
- ECS Cluster (Fargate)
- IAM Roles
- CloudWatch Logs

**Save the output!** You'll see:
```
ECR Repository: 123456789.dkr.ecr.us-east-1.amazonaws.com/fastapi-app
ALB URL: http://fastapi-ecs-alb-xyz.us-east-1.elb.amazonaws.com
```

Configuration is saved to `aws-config.sh`.

## Step 3: Build and Deploy (3 min)

```bash
./scripts/deploy-image.sh
```

This script:
1. Builds Docker image
2. Logs in to ECR
3. Pushes image
4. Updates ECS service
5. Waits for deployment

**Test it:**
```bash
source aws-config.sh
curl "http://$ALB_DNS/health"
# Should return: {"status":"healthy",...}

# Open in browser
open "http://$ALB_DNS/docs"
```

## Step 4: GitHub Setup (2 min)

### Create IAM User for GitHub Actions

```bash
./scripts/create-github-user.sh
```

Copy the output - you'll need:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

### Add to GitHub

1. Go to your repo: `https://github.com/YOUR_USERNAME/YOUR_REPO`
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add both secrets:

| Secret Name | Value |
|------------|-------|
| `AWS_ACCESS_KEY_ID` | (from script output) |
| `AWS_SECRET_ACCESS_KEY` | (from script output) |

**Important:** Delete `github-actions-credentials.json` after adding secrets!

```bash
rm github-actions-credentials.json
```

## Step 5: Push to GitHub (1 min)

```bash
# Initialize git (if not already done)
git init
git add .
git commit -m "Initial commit: FastAPI ECS Fargate setup"

# Add remote (replace with your repo URL)
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git

# Push to GitHub
git branch -M main
git push -u origin main
```

## Step 6: Test Feature Branch (2 min)

```bash
# Create feature branch
git checkout -b feature-test

# Make a change
echo "# Test Feature" > test.md
git add test.md
git commit -m "Test feature branch deployment"

# Push to trigger CI/CD
git push origin feature-test
```

**Watch the magic happen:**
1. Go to GitHub → Actions tab
2. Watch the deployment workflow
3. After ~3 minutes, check deployment summary
4. Your feature branch is now running on ECS!

## Verification Checklist

✅ Infrastructure deployed
```bash
source aws-config.sh
aws ecs describe-clusters --clusters $ECS_CLUSTER --region $AWS_REGION
```

✅ Main service running
```bash
aws ecs describe-services --cluster $ECS_CLUSTER --services fastapi-service --region $AWS_REGION | jq '.services[0].runningCount'
# Should show: 1
```

✅ Application accessible
```bash
curl "http://$ALB_DNS/health"
# Should return healthy status
```

✅ GitHub Actions configured
- Check: Settings → Secrets shows 2 secrets
- Check: Actions tab shows workflows

✅ Feature branch deployed
- Check: GitHub Actions shows successful deployment
- Check: ECS shows multiple services

## Quick Reference Commands

### View All Services
```bash
source aws-config.sh
aws ecs list-services --cluster $ECS_CLUSTER --region $AWS_REGION
```

### Watch Logs
```bash
aws logs tail /ecs/fastapi-ecs --follow --region us-east-1
```

### Rebuild and Deploy
```bash
./scripts/deploy-image.sh
```

### Delete Feature Service
```bash
source aws-config.sh
BRANCH="feature-test"
SERVICE="fastapi-feature-$BRANCH"

aws ecs update-service --cluster $ECS_CLUSTER --service $SERVICE --desired-count 0 --region $AWS_REGION
aws ecs delete-service --cluster $ECS_CLUSTER --service $SERVICE --region $AWS_REGION
```

### Cleanup Everything
```bash
./scripts/cleanup.sh
```

## Common Issues

### Issue: "Unable to locate credentials"
**Solution:**
```bash
aws configure
```

### Issue: "Repository does not exist"
**Solution:**
```bash
# Re-run setup script
./scripts/aws-setup.sh
```

### Issue: Service won't start
**Solution:**
```bash
# Check logs
aws logs tail /ecs/fastapi-ecs --since 5m --region us-east-1

# Check task status
aws ecs list-tasks --cluster fastapi-cluster --desired-status STOPPED --region us-east-1
```

### Issue: GitHub Actions fails
**Check:**
1. Secrets are set correctly in GitHub
2. Main infrastructure exists:
   ```bash
   aws ecs describe-clusters --clusters fastapi-cluster --region us-east-1
   ```
3. ECR repository exists:
   ```bash
   aws ecr describe-repositories --repository-names fastapi-app --region us-east-1
   ```

### Issue: Can't access ALB URL
**Wait:**
- Initial deployment takes 2-3 minutes
- Health checks take 30 seconds

**Check:**
```bash
source aws-config.sh
aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --region $AWS_REGION
```

## Cost Breakdown

**Monthly costs** (us-east-1):

| Resource | Cost |
|----------|------|
| Fargate (0.25 vCPU, 512 MB) | ~$7 |
| Application Load Balancer | ~$16 |
| ECR Storage (<10 GB) | ~$1 |
| Data Transfer | ~$1-5 |
| **Total (main service)** | **~$25-30** |
| **Each feature branch** | **+$7** |

**Cost-saving tips:**
1. Delete feature branches when done
2. Use smaller task size (already at minimum)
3. Use Fargate Spot for dev environments
4. Delete entire setup when not needed

## Next Steps

### Customize Your App

Edit `app/main.py`:
```python
@app.get("/your-endpoint")
async def your_function():
    return {"message": "Your custom logic"}
```

Then deploy:
```bash
./scripts/deploy-image.sh
```

### Add Database

1. Create RDS instance
2. Update security groups
3. Add connection string to task definition
4. Update application code

### Add HTTPS

1. Request ACM certificate
2. Add HTTPS listener to ALB
3. Update security group for port 443

### Add Auto-Scaling

See README.md → Advanced Features

### Monitor with CloudWatch

```bash
# View dashboards
open "https://console.aws.amazon.com/cloudwatch/home?region=us-east-1"

# View logs
aws logs tail /ecs/fastapi-ecs --follow
```

## File Structure

```
aws-config.sh          # Auto-generated config (don't commit!)
app/
  main.py             # Your FastAPI app
scripts/
  aws-setup.sh        # Run once: creates infrastructure
  deploy-image.sh     # Run often: builds & deploys
  create-github-user.sh  # Run once: creates GitHub IAM user
  cleanup.sh          # Run once: deletes everything
.github/workflows/
  deploy-feature.yml  # Auto-runs on feature-* branches
```

## Getting Help

1. Check logs:
   ```bash
   aws logs tail /ecs/fastapi-ecs --follow
   ```

2. Check service status:
   ```bash
   aws ecs describe-services --cluster fastapi-cluster --services fastapi-service --region us-east-1
   ```

3. See detailed documentation in README.md

## Success!

You now have:
- ✅ FastAPI app running on ECS Fargate
- ✅ Automatic deployment on feature branches
- ✅ Load balancer with health checks
- ✅ Centralized logging
- ✅ Production-ready infrastructure

Your app is live at: `http://$ALB_DNS`

**Try the API:** `http://$ALB_DNS/docs`
