#!/bin/bash
set -e

echo "=========================================="
echo "Terraform-project-a AWS Cleanup Script"
echo "=========================================="
echo ""
echo "⚠️  WARNING: This will delete all resources in AWS"
echo "This includes: ALB, EC2, RDS, ElastiCache, S3, IAM roles, etc."
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Starting cleanup..."
echo ""

PROJECT_NAME="terraform-project-a"
ENVIRONMENT="dev"
AWS_REGION="eu-west-2"

# Function to delete resource if it exists
delete_if_exists() {
    local resource_type=$1
    local resource_name=$2
    local delete_command=$3
    
    echo "🔍 Checking $resource_type: $resource_name"
    if eval "$delete_command" 2>/dev/null; then
        echo "   ✅ Deleted"
    else
        echo "   ℹ️  Not found or already deleted"
    fi
}

# 1. Delete Load Balancer
echo ""
echo "1️⃣  Deleting Application Load Balancer..."
ALB_ARN=$(aws elbv2 describe-load-balancers \
    --names "${PROJECT_NAME}-${ENVIRONMENT}-alb" \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text \
    --region ${AWS_REGION} 2>/dev/null || echo "")

if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
    echo "   Found ALB: $ALB_ARN"
    aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" --region ${AWS_REGION}
    echo "   ✅ ALB deleted (waiting for deletion...)"
    sleep 10
else
    echo "   ℹ️  ALB not found"
fi

# 2. Delete Target Group
echo ""
echo "2️⃣  Deleting Target Group..."
TG_ARN=$(aws elbv2 describe-target-groups \
    --names "${PROJECT_NAME}-${ENVIRONMENT}-tg" \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text \
    --region ${AWS_REGION} 2>/dev/null || echo "")

if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
    sleep 5  # Wait a bit more for ALB to fully delete
    aws elbv2 delete-target-group --target-group-arn "$TG_ARN" --region ${AWS_REGION}
    echo "   ✅ Target Group deleted"
else
    echo "   ℹ️  Target Group not found"
fi

# 3. Delete Auto Scaling Group (if exists)
echo ""
echo "3️⃣  Deleting Auto Scaling Group..."
ASG_NAME="${PROJECT_NAME}-${ENVIRONMENT}-asg"
aws autoscaling delete-auto-scaling-group \
    --auto-scaling-group-name "$ASG_NAME" \
    --force-delete \
    --region ${AWS_REGION} 2>/dev/null && echo "   ✅ ASG deleted" || echo "   ℹ️  ASG not found"

# 4. Delete Launch Template (if exists)
echo ""
echo "4️⃣  Deleting Launch Template..."
aws ec2 delete-launch-template \
    --launch-template-name "${PROJECT_NAME}-${ENVIRONMENT}-lt" \
    --region ${AWS_REGION} 2>/dev/null && echo "   ✅ Launch Template deleted" || echo "   ℹ️  Launch Template not found"

# 5. Delete RDS Instance
echo ""
echo "5️⃣  Deleting RDS Database..."
aws rds delete-db-instance \
    --db-instance-identifier "${PROJECT_NAME}-${ENVIRONMENT}-db" \
    --skip-final-snapshot \
    --region ${AWS_REGION} 2>/dev/null && echo "   ✅ RDS deletion initiated" || echo "   ℹ️  RDS not found"

# 6. Delete ElastiCache Cluster
echo ""
echo "6️⃣  Deleting ElastiCache Redis..."
aws elasticache delete-cache-cluster \
    --cache-cluster-id "${PROJECT_NAME}-${ENVIRONMENT}-redis" \
    --region ${AWS_REGION} 2>/dev/null && echo "   ✅ ElastiCache deletion initiated" || echo "   ℹ️  ElastiCache not found"

# 7. Wait for resources to delete
echo ""
echo "⏳ Waiting 30 seconds for resources to start deleting..."
sleep 30

# 8. Delete RDS Subnet Group
echo ""
echo "7️⃣  Deleting RDS Subnet Group..."
aws rds delete-db-subnet-group \
    --db-subnet-group-name "${PROJECT_NAME}-${ENVIRONMENT}-db-subnet-group" \
    --region ${AWS_REGION} 2>/dev/null && echo "   ✅ RDS Subnet Group deleted" || echo "   ℹ️  Already deleted"

# 9. Delete RDS Parameter Group
echo ""
echo "8️⃣  Deleting RDS Parameter Group..."
aws rds delete-db-parameter-group \
    --db-parameter-group-name "${PROJECT_NAME}-${ENVIRONMENT}-postgres15" \
    --region ${AWS_REGION} 2>/dev/null && echo "   ✅ RDS Parameter Group deleted" || echo "   ℹ️  Already deleted"

# 10. Delete ElastiCache Subnet Group
echo ""
echo "9️⃣  Deleting ElastiCache Subnet Group..."
aws elasticache delete-cache-subnet-group \
    --cache-subnet-group-name "${PROJECT_NAME}-${ENVIRONMENT}-redis-subnet-group" \
    --region ${AWS_REGION} 2>/dev/null && echo "   ✅ ElastiCache Subnet Group deleted" || echo "   ℹ️  Already deleted"

# 11. Delete ElastiCache Parameter Group
echo ""
echo "🔟 Deleting ElastiCache Parameter Group..."
aws elasticache delete-cache-parameter-group \
    --cache-parameter-group-name "${PROJECT_NAME}-${ENVIRONMENT}-redis" \
    --region ${AWS_REGION} 2>/dev/null && echo "   ✅ ElastiCache Parameter Group deleted" || echo "   ℹ️  Already deleted"

# 12. Delete CloudWatch Log Groups
echo ""
echo "1️⃣1️⃣  Deleting CloudWatch Log Groups..."
aws logs delete-log-group --log-group-name "/aws/elasticache/${PROJECT_NAME}-${ENVIRONMENT}/slow-log" --region ${AWS_REGION} 2>/dev/null && echo "   ✅ Deleted slow-log" || echo "   ℹ️  slow-log not found"
aws logs delete-log-group --log-group-name "/aws/elasticache/${PROJECT_NAME}-${ENVIRONMENT}/engine-log" --region ${AWS_REGION} 2>/dev/null && echo "   ✅ Deleted engine-log" || echo "   ℹ️  engine-log not found"
aws logs delete-log-group --log-group-name "/aws/vpc/${PROJECT_NAME}-${ENVIRONMENT}" --region ${AWS_REGION} 2>/dev/null && echo "   ✅ Deleted vpc flow logs" || echo "   ℹ️  vpc flow logs not found"

# 13. Detach and Delete IAM Role Policies
echo ""
echo "1️⃣2️⃣  Deleting IAM Roles..."

# EC2 Role
ROLE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-ec2-role"
echo "   Detaching policies from $ROLE_NAME..."
aws iam list-attached-role-policies --role-name "$ROLE_NAME" --region ${AWS_REGION} 2>/dev/null | \
    jq -r '.AttachedPolicies[].PolicyArn' | \
    while read policy; do
        aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$policy" --region ${AWS_REGION} 2>/dev/null
    done

aws iam list-role-policies --role-name "$ROLE_NAME" --region ${AWS_REGION} 2>/dev/null | \
    jq -r '.PolicyNames[]' | \
    while read policy; do
        aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$policy" --region ${AWS_REGION} 2>/dev/null
    done

# Delete instance profiles
aws iam list-instance-profiles-for-role --role-name "$ROLE_NAME" --region ${AWS_REGION} 2>/dev/null | \
    jq -r '.InstanceProfiles[].InstanceProfileName' | \
    while read profile; do
        aws iam remove-role-from-instance-profile --instance-profile-name "$profile" --role-name "$ROLE_NAME" --region ${AWS_REGION} 2>/dev/null
        aws iam delete-instance-profile --instance-profile-name "$profile" --region ${AWS_REGION} 2>/dev/null
    done

aws iam delete-role --role-name "$ROLE_NAME" --region ${AWS_REGION} 2>/dev/null && echo "   ✅ Deleted EC2 role" || echo "   ℹ️  EC2 role not found"

# VPC Flow Logs Role
FLOW_ROLE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-vpc-flow-logs"
aws iam list-attached-role-policies --role-name "$FLOW_ROLE_NAME" --region ${AWS_REGION} 2>/dev/null | \
    jq -r '.AttachedPolicies[].PolicyArn' | \
    while read policy; do
        aws iam detach-role-policy --role-name "$FLOW_ROLE_NAME" --policy-arn "$policy" --region ${AWS_REGION} 2>/dev/null
    done

aws iam list-role-policies --role-name "$FLOW_ROLE_NAME" --region ${AWS_REGION} 2>/dev/null | \
    jq -r '.PolicyNames[]' | \
    while read policy; do
        aws iam delete-role-policy --role-name "$FLOW_ROLE_NAME" --policy-name "$policy" --region ${AWS_REGION} 2>/dev/null
    done

aws iam delete-role --role-name "$FLOW_ROLE_NAME" --region ${AWS_REGION} 2>/dev/null && echo "   ✅ Deleted VPC Flow Logs role" || echo "   ℹ️  Flow Logs role not found"

# 14. Empty and Delete S3 Bucket
echo ""
echo "1️⃣3️⃣  Deleting S3 Bucket..."
BUCKET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-attachments"

# Empty bucket first
echo "   Emptying bucket..."
aws s3 rm "s3://${BUCKET_NAME}" --recursive --region ${AWS_REGION} 2>/dev/null

# Delete all versions (if versioning enabled)
aws s3api list-object-versions \
    --bucket "${BUCKET_NAME}" \
    --region ${AWS_REGION} 2>/dev/null | \
    jq -r '.Versions[]? | .VersionId + " " + .Key' | \
    while read version key; do
        aws s3api delete-object \
            --bucket "${BUCKET_NAME}" \
            --key "$key" \
            --version-id "$version" \
            --region ${AWS_REGION} 2>/dev/null
    done

# Delete bucket
aws s3 rb "s3://${BUCKET_NAME}" --force --region ${AWS_REGION} 2>/dev/null && echo "   ✅ S3 bucket deleted" || echo "   ℹ️  S3 bucket not found"

echo ""
echo "=========================================="
echo "✅ Cleanup Complete!"
echo "=========================================="
echo ""
echo "Resources have been deleted. You can now run:"
echo "  terraform plan"
echo "  terraform apply"
echo ""
