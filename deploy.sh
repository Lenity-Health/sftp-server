#!/bin/bash

# Configuration variables - UPDATE THESE
LAMBDA_FUNCTION_NAME="sftp-custom-identity-provider"
LAMBDA_ROLE_NAME="sftp-lambda-execution-role"
SFTP_SERVER_ID="YOUR_SFTP_SERVER_ID"  # Get this from AWS Console
REGION="us-east-1"  # Change to your region
S3_BUCKET_NAME="sftp-tcm-sunflower"  # Your S3 bucket for SFTP files

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting SFTP Custom Identity Provider Setup...${NC}"

# Step 1: Create IAM role for Lambda
echo -e "${YELLOW}Step 1: Creating IAM role for Lambda...${NC}"
cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name $LAMBDA_ROLE_NAME \
  --assume-role-policy-document file:///tmp/trust-policy.json \
  --region $REGION 2>/dev/null || echo "Role may already exist"

aws iam put-role-policy \
  --role-name $LAMBDA_ROLE_NAME \
  --policy-name LambdaBasicExecution \
  --policy-document file://iam_role_policy.json \
  --region $REGION

LAMBDA_ROLE_ARN=$(aws iam get-role --role-name $LAMBDA_ROLE_NAME --query 'Role.Arn' --output text --region $REGION)
echo -e "${GREEN}Lambda Role ARN: $LAMBDA_ROLE_ARN${NC}"

# Step 2: Create deployment package
echo -e "${YELLOW}Step 2: Creating Lambda deployment package...${NC}"
zip -q lambda_function.zip lambda_function.py

# Step 3: Create or update Lambda function
echo -e "${YELLOW}Step 3: Creating/Updating Lambda function...${NC}"
aws lambda create-function \
  --function-name $LAMBDA_FUNCTION_NAME \
  --runtime python3.11 \
  --role $LAMBDA_ROLE_ARN \
  --handler lambda_function.lambda_handler \
  --zip-file fileb://lambda_function.zip \
  --timeout 30 \
  --region $REGION 2>/dev/null || \
aws lambda update-function-code \
  --function-name $LAMBDA_FUNCTION_NAME \
  --zip-file fileb://lambda_function.zip \
  --region $REGION

# Step 4: Set initial environment variable (will be updated after SFTP role is created)
echo -e "${YELLOW}Step 4: Setting Lambda environment variables...${NC}"
aws lambda update-function-configuration \
  --function-name $LAMBDA_FUNCTION_NAME \
  --environment "Variables={
    DEFAULT_ROLE_ARN=$LAMBDA_ROLE_ARN
  }" \
  --region $REGION

# Step 5: Create IAM role for SFTP users
echo -e "${YELLOW}Step 5: Creating IAM role for SFTP users...${NC}"
SFTP_USER_ROLE_NAME="sftp-user-role"
cat > /tmp/sftp-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "transfer.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Update S3 bucket name in policy
sed "s/YOUR_S3_BUCKET_NAME/$S3_BUCKET_NAME/g" sftp_user_policy.json > /tmp/sftp-user-policy.json

aws iam create-role \
  --role-name $SFTP_USER_ROLE_NAME \
  --assume-role-policy-document file:///tmp/sftp-trust-policy.json \
  --region $REGION 2>/dev/null || echo "SFTP user role may already exist"

aws iam put-role-policy \
  --role-name $SFTP_USER_ROLE_NAME \
  --policy-name S3AccessPolicy \
  --policy-document file:///tmp/sftp-user-policy.json \
  --region $REGION

SFTP_USER_ROLE_ARN=$(aws iam get-role --role-name $SFTP_USER_ROLE_NAME --query 'Role.Arn' --output text --region $REGION)
echo -e "${GREEN}SFTP User Role ARN: $SFTP_USER_ROLE_ARN${NC}"

# Step 6: Update Lambda to use SFTP user role
echo -e "${YELLOW}Step 6: Updating Lambda with SFTP user role...${NC}"
aws lambda update-function-configuration \
  --function-name $LAMBDA_FUNCTION_NAME \
  --environment "Variables={
    DEFAULT_ROLE_ARN=$SFTP_USER_ROLE_ARN
  }" \
  --region $REGION

# Step 7: Grant Transfer Family permission to invoke Lambda
echo -e "${YELLOW}Step 7: Granting Transfer Family permission to invoke Lambda...${NC}"
LAMBDA_ARN=$(aws lambda get-function --function-name $LAMBDA_FUNCTION_NAME --query 'Configuration.FunctionArn' --output text --region $REGION)

aws lambda add-permission \
  --function-name $LAMBDA_FUNCTION_NAME \
  --statement-id AllowTransferInvoke \
  --action lambda:InvokeFunction \
  --principal transfer.amazonaws.com \
  --source-arn "arn:aws:transfer:$REGION:$(aws sts get-caller-identity --query Account --output text):server/$SFTP_SERVER_ID" \
  --region $REGION 2>/dev/null || echo "Permission may already exist"

# Step 8: Update SFTP server to use custom identity provider
echo -e "${YELLOW}Step 8: Updating SFTP server identity provider...${NC}"
aws transfer update-server \
  --server-id $SFTP_SERVER_ID \
  --identity-provider-type AWS_LAMBDA \
  --identity-provider-details "{\"Function\":\"$LAMBDA_ARN\"}" \
  --region $REGION

echo -e "${GREEN}Setup complete!${NC}"
echo -e "${GREEN}Lambda Function ARN: $LAMBDA_ARN${NC}"
echo -e "${GREEN}SFTP User Role ARN: $SFTP_USER_ROLE_ARN${NC}"
echo -e "${GREEN}Credentials:${NC}"
echo -e "${GREEN}  Username: shivang-sftp${NC}"
echo -e "${GREEN}  Password: password${NC}"
