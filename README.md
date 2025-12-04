# AWS SFTP Server with Custom Identity Provider

This project sets up a custom identity provider using AWS Lambda for username/password authentication with AWS Transfer Family SFTP server.

## Architecture

- **AWS Transfer Family**: SFTP server (already created)
- **AWS Lambda**: Custom identity provider that validates username/password
- **AWS Secrets Manager**: Stores user credentials and configuration
- **IAM Roles**: 
  - Lambda execution role (with Secrets Manager access)
  - SFTP user role (for S3 access)
- **S3 Bucket**: Storage for SFTP files

## Prerequisites

1. AWS CLI installed and configured
2. AWS Transfer Family SFTP server already created
3. S3 bucket for file storage
4. Python 3.11+ (for local testing)
5. `zip` command available

## Setup Instructions

### 1. Update Configuration

Edit `deploy.sh` and update these variables:
- `SFTP_SERVER_ID`: Your existing SFTP server ID (found in AWS Console)
- `REGION`: Your AWS region
- `S3_BUCKET_NAME`: Your S3 bucket name for SFTP files

### 2. Deploy Lambda Function

Make the deploy script executable and run it:

```bash
chmod +x deploy.sh
./deploy.sh
```

### 3. Manage Users

Users are stored in AWS Secrets Manager. Use the management script:

**List all users:**
```bash
./manage_users.sh list
```

**Add a new user:**
```bash
./manage_users.sh add <username> <password> [home_directory]
```

**Update a user's password:**
```bash
./manage_users.sh update <username> <password> [home_directory]
```

**Delete a user:**
```bash
./manage_users.sh delete <username>
```

**Example:**
```bash
./manage_users.sh add john mypassword123 /sftp-tcm-sunflower/john
```

### 4. Test Connection

Connect to your SFTP server using:
- **Host**: Your SFTP server endpoint (from AWS Console)
- **Port**: 22
- **Username**: One of the configured usernames
- **Password**: Corresponding password
- **Protocol**: SFTP

Example using `sftp` command:
```bash
sftp admin@your-sftp-server-endpoint.amazonaws.com
```

## File Structure

- `lambda_function.py`: Lambda function that handles authentication
- `requirements.txt`: Python dependencies
- `iam_role_policy.json`: IAM policy for Lambda execution
- `sftp_user_policy.json`: IAM policy for SFTP users (S3 access)
- `deploy.sh`: Deployment script
- `README.md`: This file

## Security Best Practices

1. **Use AWS Secrets Manager**: For production, store credentials in AWS Secrets Manager instead of environment variables
2. **Rotate Passwords**: Regularly update passwords in Lambda environment variables
3. **Least Privilege**: Ensure IAM roles have minimal required permissions
4. **Enable Logging**: Monitor CloudWatch Logs for authentication attempts
5. **Use VPC**: Consider placing Lambda in VPC if accessing private resources

## User Management

The system uses **AWS Secrets Manager** to store user credentials. The secret `sftp-users` contains a JSON object with all user configurations.

**Secret Structure:**
```json
{
  "username": {
    "password": "user_password",
    "role_arn": "arn:aws:iam::ACCOUNT:role/TransferFamilyS3AccessRoleSFTP",
    "home_directory": "/sftp-tcm-sunflower",
    "policy": "",
    "public_keys": []
  }
}
```

**Manual Secret Update:**
```bash
# Get current secret
aws secretsmanager get-secret-value --secret-id sftp-users --region us-east-1

# Update secret (use the management script instead)
./manage_users.sh add newuser newpassword
```

## Current Users

The following users are configured on the SFTP server:

| Username | Password | Home Directory |
|----------|----------|----------------|
| `shivang-sftp` | `password` | `/sftp-tcm-sunflower` |
| `lenity-cn` | `LenitySftp2025` | `/sftp-tcm-sunflower` |
| `shivam-aima` | `7mCi6jXXF` | `/sftp-tcm-sunflower` |
| `anugya-kanswal` | `LNUsIpqij` | `/sftp-tcm-sunflower` |

**Server Endpoint:**
```
s-8a3bf9037eef44828.server.transfer.us-east-1.amazonaws.com
```

**Connection Example:**
```bash
sftp shivang-sftp@s-8a3bf9037eef44828.server.transfer.us-east-1.amazonaws.com
```

> **Note:** All users share access to the same S3 bucket (`sftp-tcm-sunflower`) and use the same home directory.

## Advanced Configuration

### Using DynamoDB

Store user credentials in DynamoDB for better scalability:

```python
import boto3

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('sftp-users')

def validate_user(username, password):
    response = table.get_item(Key={'username': username})
    if 'Item' in response:
        return response['Item']['password'] == password
    return False
```

## Troubleshooting

### Lambda not being invoked
- Check Lambda permissions for Transfer Family
- Verify server identity provider is set to `AWS_LAMBDA`
- Check CloudWatch Logs for Lambda errors

### Authentication failing
- Verify user exists in Secrets Manager: `./manage_users.sh list`
- Check Lambda logs in CloudWatch for detailed errors
- Ensure username/password match exactly (case-sensitive)
- Verify Lambda has Secrets Manager permissions

### S3 access issues
- Verify SFTP user role has correct S3 permissions
- Check bucket policy allows the role
- Ensure home directory path is correct

## Cleanup

To remove all resources:

```bash
# Delete Lambda function
aws lambda delete-function --function-name sftp-custom-identity-provider

# Delete IAM roles
aws iam delete-role-policy --role-name sftp-lambda-execution-role --policy-name LambdaBasicExecution
aws iam delete-role --role-name sftp-lambda-execution-role

aws iam delete-role-policy --role-name sftp-user-role --policy-name S3AccessPolicy
aws iam delete-role --role-name sftp-user-role
```

## Support

For issues or questions, refer to:
- [AWS Transfer Family Documentation](https://docs.aws.amazon.com/transfer/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
