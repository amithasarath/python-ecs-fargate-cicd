#!/bin/bash

# Create GitHub Actions IAM User

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

USER_NAME="github-actions-ecs"

print_info "Creating IAM user for GitHub Actions..."

if aws iam get-user --user-name $USER_NAME 2>/dev/null; then
    print_warn "User '$USER_NAME' already exists"

    read -p "Do you want to create new access keys? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
else
    print_info "Creating user..."
    aws iam create-user --user-name $USER_NAME

    print_info "Attaching policies..."
    aws iam attach-user-policy \
        --user-name $USER_NAME \
        --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess

    aws iam attach-user-policy \
        --user-name $USER_NAME \
        --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

    aws iam attach-user-policy \
        --user-name $USER_NAME \
        --policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess
fi

print_info "Creating access keys..."
CREDS=$(aws iam create-access-key --user-name $USER_NAME)

ACCESS_KEY=$(echo $CREDS | jq -r '.AccessKey.AccessKeyId')
SECRET_KEY=$(echo $CREDS | jq -r '.AccessKey.SecretAccessKey')

# Save to file
echo "$CREDS" > github-actions-credentials.json

echo ""
echo "=========================================="
print_info "GitHub Actions Credentials Created!"
echo "=========================================="
echo ""
print_warn "Add these secrets to your GitHub repository:"
echo ""
echo "Secret Name: AWS_ACCESS_KEY_ID"
echo "Secret Value: $ACCESS_KEY"
echo ""
echo "Secret Name: AWS_SECRET_ACCESS_KEY"
echo "Secret Value: $SECRET_KEY"
echo ""
print_warn "Credentials also saved to: github-actions-credentials.json"
print_warn "Delete this file after adding to GitHub!"
echo ""
print_info "To add secrets in GitHub:"
echo "1. Go to your repository"
echo "2. Click Settings > Secrets and variables > Actions"
echo "3. Click 'New repository secret'"
echo "4. Add both secrets above"
echo ""
