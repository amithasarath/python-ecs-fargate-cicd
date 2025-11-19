#!/bin/bash

echo "=== Checking ECS Deployment Status ==="
echo ""

# Check ECR Images
echo "📦 ECR Images in healthcare-app:"
aws ecr describe-images \
  --repository-name healthcare-app \
  --region ap-south-1 \
  --query 'imageDetails[*].[imageTags[0], imagePushedAt]' \
  --output table 2>&1 || echo "No images found or repository doesn't exist"

echo ""

# Check ECS Services
echo "🚀 ECS Services in healthcare-cluster:"
aws ecs list-services \
  --cluster healthcare-cluster \
  --region ap-south-1 \
  --query 'serviceArns[*]' \
  --output table

echo ""

# Check Task Definitions
echo "📋 Task Definitions (healthcare-task family):"
aws ecs list-task-definitions \
  --family-prefix healthcare-task \
  --region ap-south-1 \
  --sort DESC \
  --max-items 5 \
  --output table

echo ""

# Check for feature service
echo "🔍 Looking for feature branch service:"
aws ecs describe-services \
  --cluster healthcare-cluster \
  --services healthcare-feature-feature-cicd-testing \
  --region ap-south-1 \
  --query 'services[0].[serviceName, status, desiredCount, runningCount]' \
  --output table 2>&1 || echo "Feature service not yet created"

echo ""
echo "✅ Check complete!"
