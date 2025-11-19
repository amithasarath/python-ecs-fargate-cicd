#!/bin/bash

SERVICE_NAME=${1:-healthcare-feature-feature-cicd-testing}
CLUSTER=healthcare-cluster
REGION=ap-south-1

echo "🔍 Getting endpoint for service: $SERVICE_NAME"
echo ""

# Get service info
SERVICE_INFO=$(aws ecs describe-services \
  --cluster $CLUSTER \
  --services $SERVICE_NAME \
  --region $REGION 2>&1)

if echo "$SERVICE_INFO" | grep -q "ServiceNotFoundException"; then
  echo "❌ Service '$SERVICE_NAME' not found!"
  echo ""
  echo "Available services in cluster:"
  aws ecs list-services --cluster $CLUSTER --region $REGION --query 'serviceArns[*]' --output text | xargs -n1 basename
  exit 1
fi

# Get target group ARN
TG_ARN=$(echo "$SERVICE_INFO" | grep -oE 'arn:aws:elasticloadbalancing:[^"]+' | head -1)

if [ -z "$TG_ARN" ]; then
  echo "⚠️  Service exists but no load balancer configured yet"
  echo "Service may still be starting up..."
  exit 1
fi

echo "✅ Service found!"
echo "Target Group: $TG_ARN"
echo ""

# Get load balancer info
LB_ARN=$(aws elbv2 describe-target-groups \
  --target-group-arns $TG_ARN \
  --region $REGION \
  --query 'TargetGroups[0].LoadBalancerArns[0]' \
  --output text)

LB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns $LB_ARN \
  --region $REGION \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

echo "🌐 Application Endpoints:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Main URL:       http://$LB_DNS"
echo "Health Check:   http://$LB_DNS/health"
echo "API Docs:       http://$LB_DNS/docs"
echo "Items API:      http://$LB_DNS/items"
echo ""
echo "🧪 Test the endpoint:"
echo "curl http://$LB_DNS/health"
