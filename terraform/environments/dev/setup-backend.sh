#!/bin/bash
set -e

echo "=========================================="
echo "terraform-project-A - Dev Environment Backend Setup"
echo "=========================================="
echo ""

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="eu-west-2"
PROJECT_NAME="terraform-project-a"

if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo "❌ Error: Could not retrieve AWS Account ID"
    echo "   Please run: aws configure"
    exit 1
fi

echo "✅ AWS Account ID: $AWS_ACCOUNT_ID"
echo "✅ Region: $AWS_REGION"
echo ""

# S3 bucket name
BUCKET_NAME="${PROJECT_NAME}-terraform-state-${AWS_ACCOUNT_ID}"
TABLE_NAME="${PROJECT_NAME}-terraform-locks"

echo "Creating backend resources..."
echo ""

# Create S3 bucket
echo "1️⃣  Creating S3 bucket: $BUCKET_NAME"
if aws s3 ls "s3://${BUCKET_NAME}" 2>&1 | grep -q 'NoSuchBucket'; then
    aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"
    echo "   ✅ Bucket created"
else
    echo "   ℹ️  Bucket already exists"
fi

# Enable versioning
echo "2️⃣  Enabling versioning..."
aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled
echo "   ✅ Versioning enabled"

# Enable encryption
echo "3️⃣  Enabling encryption..."
aws s3api put-bucket-encryption \
    --bucket "${BUCKET_NAME}" \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }]
    }'
echo "   ✅ Encryption enabled"

# Block public access
echo "4️⃣  Blocking public access..."
aws s3api put-public-access-block \
    --bucket "${BUCKET_NAME}" \
    --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
echo "   ✅ Public access blocked"

# Create DynamoDB table
echo "5️⃣  Creating DynamoDB table: $TABLE_NAME"
if aws dynamodb describe-table --table-name "${TABLE_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    echo "   ℹ️  Table already exists"
else
    aws dynamodb create-table \
        --table-name "${TABLE_NAME}" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "${AWS_REGION}" \
        --tags Key=Project,Value=ServiceHub Key=ManagedBy,Value=Terraform \
        >/dev/null
    
    echo "   ⏳ Waiting for table to be active..."
    aws dynamodb wait table-exists --table-name "${TABLE_NAME}" --region "${AWS_REGION}"
    echo "   ✅ Table created"
fi

echo ""
echo "=========================================="
echo "✅ Backend Setup Complete!"
echo "=========================================="
echo ""
echo "📋 Configuration Details:"
echo "   S3 Bucket: ${BUCKET_NAME}"
echo "   DynamoDB Table: ${TABLE_NAME}"
echo "   Region: ${AWS_REGION}"
echo ""
echo "📝 Update your main.tf backend configuration:"
echo ""
echo "terraform {"
echo "  backend \"s3\" {"
echo "    bucket         = \"${BUCKET_NAME}\""
echo "    key            = \"dev/terraform.tfstate\""
echo "    region         = \"${AWS_REGION}\""
echo "    dynamodb_table = \"${TABLE_NAME}\""
echo "    encrypt        = true"
echo "  }"
echo "}"
echo ""
echo "🚀 Next steps:"
echo "   1. Update main.tf with the backend config above"
echo "   2. Run: terraform init"
echo "   3. Run: terraform plan"
echo "   4. Run: terraform apply"
echo ""
