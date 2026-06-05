#!/bin/bash
# Setup script for Terraform S3 backend and DynamoDB locking
# Run this ONCE before terraform init

set -e

AWS_REGION=${AWS_REGION:-af-south-1}
STATE_BUCKET="rewards-dev-terraform-state"
LOCKS_TABLE="terraform-locks"

echo "🔧 Setting up Terraform backend..."
echo "Region: $AWS_REGION"

# 1. Create S3 bucket
echo "📦 Creating S3 bucket for state..."
aws s3api create-bucket \
  --bucket "$STATE_BUCKET" \
  --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION" \
  2>/dev/null || echo "   (Bucket already exists or in us-east-1)"

# 2. Enable versioning
echo "📋 Enabling S3 versioning..."
aws s3api put-bucket-versioning \
  --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled

# 3. Enable encryption
echo "🔒 Enabling S3 encryption..."
aws s3api put-bucket-encryption \
  --bucket "$STATE_BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }'

# 4. Block public access
echo "🚫 Blocking public S3 access..."
aws s3api put-public-access-block \
  --bucket "$STATE_BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# 5. Create DynamoDB table
echo "🔐 Creating DynamoDB locks table..."
aws dynamodb create-table \
  --table-name "$LOCKS_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region "$AWS_REGION" \
  2>/dev/null || echo "   (Table already exists)"

echo ""
echo "✅ Backend setup complete!"
echo ""
echo "Next steps:"
echo "1. cd terraform"
echo "2. terraform init"
echo "3. terraform plan"
echo "4. terraform apply"
