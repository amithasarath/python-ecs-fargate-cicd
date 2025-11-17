#!/bin/bash

# Cleanup AWS Resources

set -e

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load configuration
if [ -f "aws-config.sh" ]; then
    source aws-config.sh
else
    print_error "Configuration file not found."
    exit 1
fi

echo ""
print_warn "This will DELETE all AWS resources created by this project!"
print_warn "Region: $AWS_REGION"
print_warn "VPC: $VPC_ID"
print_warn "ECS Cluster: $ECS_CLUSTER"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm) " -r
echo ""
if [[ ! $REPLY == "yes" ]]; then
    print_info "Cleanup cancelled"
    exit 0
fi

# Delete ECS Service
print_info "Deleting ECS services..."
aws ecs update-service \
    --cluster $ECS_CLUSTER \
    --service $ECS_SERVICE \
    --desired-count 0 \
    --region $AWS_REGION >/dev/null 2>&1 || true

sleep 5

aws ecs delete-service \
    --cluster $ECS_CLUSTER \
    --service $ECS_SERVICE \
    --region $AWS_REGION >/dev/null 2>&1 || true

# Delete any feature branch services
print_info "Checking for feature branch services..."
FEATURE_SERVICES=$(aws ecs list-services --cluster $ECS_CLUSTER --region $AWS_REGION --query 'serviceArns[*]' --output text | grep -o 'fastapi-feature-[^ ]*' || true)
for SERVICE in $FEATURE_SERVICES; do
    print_info "Deleting service: $SERVICE"
    aws ecs update-service --cluster $ECS_CLUSTER --service $SERVICE --desired-count 0 --region $AWS_REGION >/dev/null 2>&1 || true
    sleep 5
    aws ecs delete-service --cluster $ECS_CLUSTER --service $SERVICE --region $AWS_REGION >/dev/null 2>&1 || true
done

sleep 10

# Deregister task definitions
print_info "Deregistering task definitions..."
TASK_DEFS=$(aws ecs list-task-definitions --family-prefix $TASK_DEFINITION --region $AWS_REGION --query 'taskDefinitionArns[*]' --output text)
for TD in $TASK_DEFS; do
    aws ecs deregister-task-definition --task-definition $TD --region $AWS_REGION >/dev/null 2>&1 || true
done

# Delete ECS Cluster
print_info "Deleting ECS cluster..."
aws ecs delete-cluster --cluster $ECS_CLUSTER --region $AWS_REGION >/dev/null 2>&1 || true

# Delete ALB
print_info "Deleting Application Load Balancer..."
aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN --region $AWS_REGION 2>/dev/null || true

sleep 10

# Delete Target Groups
print_info "Deleting target groups..."
aws elbv2 delete-target-group --target-group-arn $TG_ARN --region $AWS_REGION 2>/dev/null || true

# Delete feature branch target groups
FEATURE_TGS=$(aws elbv2 describe-target-groups --region $AWS_REGION --query "TargetGroups[?starts_with(TargetGroupName, 'tg-feature-')].TargetGroupArn" --output text || true)
for TG in $FEATURE_TGS; do
    print_info "Deleting target group: $TG"
    aws elbv2 delete-target-group --target-group-arn $TG --region $AWS_REGION 2>/dev/null || true
done

# Delete CloudWatch Log Group
print_info "Deleting CloudWatch log group..."
aws logs delete-log-group --log-group-name "/ecs/$PROJECT_NAME" --region $AWS_REGION 2>/dev/null || true

# Delete ECR Repository
print_info "Deleting ECR repository..."
aws ecr delete-repository --repository-name $ECR_REPOSITORY --force --region $AWS_REGION 2>/dev/null || true

# Delete Security Groups
sleep 30  # Wait for ENIs to be released
print_info "Deleting security groups..."
aws ec2 delete-security-group --group-id $ECS_SG_ID --region $AWS_REGION 2>/dev/null || true
aws ec2 delete-security-group --group-id $ALB_SG_ID --region $AWS_REGION 2>/dev/null || true

# Detach and delete Internet Gateway
print_info "Deleting Internet Gateway..."
IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --region $AWS_REGION --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || true)
if [ ! -z "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
    aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $AWS_REGION 2>/dev/null || true
    aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID --region $AWS_REGION 2>/dev/null || true
fi

# Delete Subnets
print_info "Deleting subnets..."
aws ec2 delete-subnet --subnet-id $SUBNET1_ID --region $AWS_REGION 2>/dev/null || true
aws ec2 delete-subnet --subnet-id $SUBNET2_ID --region $AWS_REGION 2>/dev/null || true

# Delete Route Table
print_info "Deleting route tables..."
ROUTE_TABLES=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --region $AWS_REGION --query 'RouteTables[?Associations[0].Main==`false`].RouteTableId' --output text)
for RTB in $ROUTE_TABLES; do
    aws ec2 delete-route-table --route-table-id $RTB --region $AWS_REGION 2>/dev/null || true
done

# Delete VPC
print_info "Deleting VPC..."
aws ec2 delete-vpc --vpc-id $VPC_ID --region $AWS_REGION 2>/dev/null || true

# Delete IAM Roles
print_info "Deleting IAM roles..."
aws iam detach-role-policy --role-name $EXEC_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy 2>/dev/null || true
aws iam delete-role --role-name $EXEC_ROLE_NAME 2>/dev/null || true
aws iam delete-role --role-name $TASK_ROLE_NAME 2>/dev/null || true

# Clean up local config
print_info "Removing local configuration..."
rm -f aws-config.sh

echo ""
print_info "Cleanup complete!"
print_warn "Note: GitHub Actions IAM user was NOT deleted. To delete it manually:"
echo "  aws iam delete-access-key --user-name github-actions-ecs --access-key-id <key-id>"
echo "  aws iam detach-user-policy --user-name github-actions-ecs --policy-arn <policy-arn>"
echo "  aws iam delete-user --user-name github-actions-ecs"
echo ""
