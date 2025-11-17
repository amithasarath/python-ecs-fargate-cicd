#!/bin/bash

# Build and Deploy Docker Image Script

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load configuration
if [ -f "aws-config.sh" ]; then
    source aws-config.sh
else
    print_error "Configuration file not found. Run aws-setup.sh first."
    exit 1
fi

print_info "Building Docker image..."
docker build -t $ECR_REPOSITORY .

print_info "Logging in to ECR..."
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin $ECR_URI

print_info "Tagging image..."
docker tag $ECR_REPOSITORY:latest $ECR_URI:latest

print_info "Pushing to ECR..."
docker push $ECR_URI:latest

print_info "Updating ECS service..."
aws ecs update-service \
    --cluster $ECS_CLUSTER \
    --service $ECS_SERVICE \
    --force-new-deployment \
    --region $AWS_REGION >/dev/null

print_info "Waiting for deployment to complete..."
aws ecs wait services-stable \
    --cluster $ECS_CLUSTER \
    --services $ECS_SERVICE \
    --region $AWS_REGION

echo ""
print_info "Deployment successful!"
print_info "Application URL: http://$ALB_DNS"
print_info "API Docs: http://$ALB_DNS/docs"
print_info "Health Check: http://$ALB_DNS/health"
echo ""
