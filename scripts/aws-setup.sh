#!/bin/bash

# AWS ECS Fargate Infrastructure Setup Script
# This script creates all required AWS infrastructure using AWS CLI

set -e

echo "=========================================="
echo "AWS ECS Fargate Infrastructure Setup"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Configuration
PROJECT_NAME="fastapi-ecs"
AWS_REGION=${AWS_REGION:-us-east-1}
ECR_REPOSITORY="fastapi-app"
ECS_CLUSTER="fastapi-cluster"
ECS_SERVICE="fastapi-service"
TASK_DEFINITION="fastapi-task-definition"
CONTAINER_NAME="fastapi-container"
VPC_CIDR="10.0.0.0/16"
SUBNET1_CIDR="10.0.1.0/24"
SUBNET2_CIDR="10.0.2.0/24"

# Check prerequisites
print_info "Checking prerequisites..."
command -v aws >/dev/null 2>&1 || { print_error "AWS CLI required but not installed."; exit 1; }
command -v jq >/dev/null 2>&1 || { print_error "jq required but not installed."; exit 1; }

# Check AWS credentials
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    print_error "AWS credentials not configured. Run 'aws configure' first."
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
print_info "AWS Account: $AWS_ACCOUNT_ID"
print_info "Region: $AWS_REGION"
echo ""

# Create ECR Repository
print_step "1/12: Creating ECR Repository..."
if aws ecr describe-repositories --repository-names $ECR_REPOSITORY --region $AWS_REGION 2>/dev/null; then
    print_warn "ECR repository already exists"
    ECR_URI=$(aws ecr describe-repositories --repository-names $ECR_REPOSITORY --region $AWS_REGION --query 'repositories[0].repositoryUri' --output text)
else
    ECR_URI=$(aws ecr create-repository \
        --repository-name $ECR_REPOSITORY \
        --region $AWS_REGION \
        --image-scanning-configuration scanOnPush=true \
        --query 'repository.repositoryUri' \
        --output text)
    print_info "Created ECR repository: $ECR_URI"
fi

# Create VPC
print_step "2/12: Creating VPC..."
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block $VPC_CIDR \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$PROJECT_NAME-vpc}]" \
    --region $AWS_REGION \
    --query 'Vpc.VpcId' \
    --output text)
print_info "Created VPC: $VPC_ID"

# Enable DNS
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames --region $AWS_REGION
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support --region $AWS_REGION

# Create Internet Gateway
print_step "3/12: Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$PROJECT_NAME-igw}]" \
    --region $AWS_REGION \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)
print_info "Created IGW: $IGW_ID"

aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID --region $AWS_REGION

# Get availability zones
AZ1=$(aws ec2 describe-availability-zones --region $AWS_REGION --query 'AvailabilityZones[0].ZoneName' --output text)
AZ2=$(aws ec2 describe-availability-zones --region $AWS_REGION --query 'AvailabilityZones[1].ZoneName' --output text)

# Create Subnets
print_step "4/12: Creating Subnets..."
SUBNET1_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block $SUBNET1_CIDR \
    --availability-zone $AZ1 \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$PROJECT_NAME-subnet-1}]" \
    --region $AWS_REGION \
    --query 'Subnet.SubnetId' \
    --output text)
print_info "Created Subnet 1: $SUBNET1_ID in $AZ1"

SUBNET2_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block $SUBNET2_CIDR \
    --availability-zone $AZ2 \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$PROJECT_NAME-subnet-2}]" \
    --region $AWS_REGION \
    --query 'Subnet.SubnetId' \
    --output text)
print_info "Created Subnet 2: $SUBNET2_ID in $AZ2"

# Enable auto-assign public IP
aws ec2 modify-subnet-attribute --subnet-id $SUBNET1_ID --map-public-ip-on-launch --region $AWS_REGION
aws ec2 modify-subnet-attribute --subnet-id $SUBNET2_ID --map-public-ip-on-launch --region $AWS_REGION

# Create Route Table
print_step "5/12: Creating Route Table..."
RTB_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$PROJECT_NAME-rtb}]" \
    --region $AWS_REGION \
    --query 'RouteTable.RouteTableId' \
    --output text)
print_info "Created Route Table: $RTB_ID"

# Create route to Internet Gateway
aws ec2 create-route --route-table-id $RTB_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --region $AWS_REGION

# Associate subnets with route table
aws ec2 associate-route-table --subnet-id $SUBNET1_ID --route-table-id $RTB_ID --region $AWS_REGION
aws ec2 associate-route-table --subnet-id $SUBNET2_ID --route-table-id $RTB_ID --region $AWS_REGION

# Create Security Group for ALB
print_step "6/12: Creating Security Groups..."
ALB_SG_ID=$(aws ec2 create-security-group \
    --group-name "$PROJECT_NAME-alb-sg" \
    --description "Security group for ALB" \
    --vpc-id $VPC_ID \
    --region $AWS_REGION \
    --query 'GroupId' \
    --output text)
print_info "Created ALB Security Group: $ALB_SG_ID"

aws ec2 authorize-security-group-ingress \
    --group-id $ALB_SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION

# Create Security Group for ECS Tasks
ECS_SG_ID=$(aws ec2 create-security-group \
    --group-name "$PROJECT_NAME-ecs-sg" \
    --description "Security group for ECS tasks" \
    --vpc-id $VPC_ID \
    --region $AWS_REGION \
    --query 'GroupId' \
    --output text)
print_info "Created ECS Security Group: $ECS_SG_ID"

aws ec2 authorize-security-group-ingress \
    --group-id $ECS_SG_ID \
    --protocol tcp \
    --port 8000 \
    --source-group $ALB_SG_ID \
    --region $AWS_REGION

# Create Application Load Balancer
print_step "7/12: Creating Application Load Balancer..."
ALB_ARN=$(aws elbv2 create-load-balancer \
    --name "$PROJECT_NAME-alb" \
    --subnets $SUBNET1_ID $SUBNET2_ID \
    --security-groups $ALB_SG_ID \
    --region $AWS_REGION \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text)
print_info "Created ALB: $ALB_ARN"

ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN --region $AWS_REGION --query 'LoadBalancers[0].DNSName' --output text)
print_info "ALB DNS: $ALB_DNS"

# Create Target Group
print_step "8/12: Creating Target Group..."
TG_ARN=$(aws elbv2 create-target-group \
    --name "$PROJECT_NAME-tg" \
    --protocol HTTP \
    --port 8000 \
    --vpc-id $VPC_ID \
    --target-type ip \
    --health-check-enabled \
    --health-check-path /health \
    --health-check-interval-seconds 30 \
    --health-check-timeout-seconds 5 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 3 \
    --region $AWS_REGION \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)
print_info "Created Target Group: $TG_ARN"

# Create ALB Listener
print_step "9/12: Creating ALB Listener..."
LISTENER_ARN=$(aws elbv2 create-listener \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=$TG_ARN \
    --region $AWS_REGION \
    --query 'Listeners[0].ListenerArn' \
    --output text)
print_info "Created Listener: $LISTENER_ARN"

# Create ECS Cluster
print_step "10/12: Creating ECS Cluster..."
aws ecs create-cluster \
    --cluster-name $ECS_CLUSTER \
    --region $AWS_REGION \
    --settings name=containerInsights,value=enabled >/dev/null
print_info "Created ECS Cluster: $ECS_CLUSTER"

# Create CloudWatch Log Group
print_step "11/12: Creating CloudWatch Log Group..."
aws logs create-log-group --log-group-name "/ecs/$PROJECT_NAME" --region $AWS_REGION 2>/dev/null || true
aws logs put-retention-policy --log-group-name "/ecs/$PROJECT_NAME" --retention-in-days 7 --region $AWS_REGION
print_info "Created Log Group: /ecs/$PROJECT_NAME"

# Create IAM Roles
print_step "12/12: Creating IAM Roles..."

# Task Execution Role
EXEC_ROLE_NAME="$PROJECT_NAME-task-execution-role"
if aws iam get-role --role-name $EXEC_ROLE_NAME 2>/dev/null; then
    print_warn "Execution role already exists"
    EXEC_ROLE_ARN=$(aws iam get-role --role-name $EXEC_ROLE_NAME --query 'Role.Arn' --output text)
else
    EXEC_ROLE_ARN=$(aws iam create-role \
        --role-name $EXEC_ROLE_NAME \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "ecs-tasks.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' \
        --query 'Role.Arn' \
        --output text)

    aws iam attach-role-policy \
        --role-name $EXEC_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

    print_info "Created Task Execution Role: $EXEC_ROLE_ARN"
fi

# Task Role
TASK_ROLE_NAME="$PROJECT_NAME-task-role"
if aws iam get-role --role-name $TASK_ROLE_NAME 2>/dev/null; then
    print_warn "Task role already exists"
    TASK_ROLE_ARN=$(aws iam get-role --role-name $TASK_ROLE_NAME --query 'Role.Arn' --output text)
else
    TASK_ROLE_ARN=$(aws iam create-role \
        --role-name $TASK_ROLE_NAME \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "ecs-tasks.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' \
        --query 'Role.Arn' \
        --output text)

    print_info "Created Task Role: $TASK_ROLE_ARN"
fi

# Wait for IAM roles to propagate
print_info "Waiting for IAM roles to propagate..."
sleep 10

# Register Task Definition
print_info "Registering ECS Task Definition..."
cat > /tmp/task-def.json <<EOF
{
  "family": "$TASK_DEFINITION",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "$EXEC_ROLE_ARN",
  "taskRoleArn": "$TASK_ROLE_ARN",
  "containerDefinitions": [
    {
      "name": "$CONTAINER_NAME",
      "image": "$ECR_URI:latest",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {"name": "ENVIRONMENT", "value": "production"},
        {"name": "BRANCH_NAME", "value": "main"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/$PROJECT_NAME",
          "awslogs-region": "$AWS_REGION",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
EOF

aws ecs register-task-definition \
    --cli-input-json file:///tmp/task-def.json \
    --region $AWS_REGION >/dev/null

print_info "Registered Task Definition: $TASK_DEFINITION"

# Create ECS Service
print_info "Creating ECS Service..."
aws ecs create-service \
    --cluster $ECS_CLUSTER \
    --service-name $ECS_SERVICE \
    --task-definition $TASK_DEFINITION \
    --desired-count 1 \
    --launch-type FARGATE \
    --platform-version LATEST \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET1_ID,$SUBNET2_ID],securityGroups=[$ECS_SG_ID],assignPublicIp=ENABLED}" \
    --load-balancers "targetGroupArn=$TG_ARN,containerName=$CONTAINER_NAME,containerPort=8000" \
    --region $AWS_REGION >/dev/null

print_info "Created ECS Service: $ECS_SERVICE"

# Save configuration
print_info "Saving configuration..."
cat > aws-config.sh <<EOF
#!/bin/bash
# AWS Infrastructure Configuration
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export ECR_REPOSITORY="$ECR_REPOSITORY"
export ECR_URI="$ECR_URI"
export ECS_CLUSTER="$ECS_CLUSTER"
export ECS_SERVICE="$ECS_SERVICE"
export TASK_DEFINITION="$TASK_DEFINITION"
export CONTAINER_NAME="$CONTAINER_NAME"
export VPC_ID="$VPC_ID"
export SUBNET1_ID="$SUBNET1_ID"
export SUBNET2_ID="$SUBNET2_ID"
export ALB_SG_ID="$ALB_SG_ID"
export ECS_SG_ID="$ECS_SG_ID"
export ALB_ARN="$ALB_ARN"
export ALB_DNS="$ALB_DNS"
export TG_ARN="$TG_ARN"
export EXEC_ROLE_ARN="$EXEC_ROLE_ARN"
export TASK_ROLE_ARN="$TASK_ROLE_ARN"
EOF

chmod +x aws-config.sh

echo ""
echo "=========================================="
print_info "Infrastructure Setup Complete!"
echo "=========================================="
echo ""
print_info "Configuration saved to: aws-config.sh"
echo ""
print_info "ECR Repository: $ECR_URI"
print_info "ECS Cluster: $ECS_CLUSTER"
print_info "ALB URL: http://$ALB_DNS"
echo ""
print_warn "Next steps:"
echo "1. Build and push Docker image to ECR"
echo "2. Update ECS service to deploy the image"
echo "3. Set up GitHub Actions secrets"
echo ""
print_info "Run './scripts/deploy-image.sh' to build and deploy your first image"
echo ""
