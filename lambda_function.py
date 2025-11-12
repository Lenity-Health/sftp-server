import json
import os
import boto3
import hashlib

def lambda_handler(event, context):
    """
    AWS Transfer Family Custom Identity Provider Lambda Function
    Handles username/password authentication for SFTP server using AWS Secrets Manager
    """
    
    # Extract username and password from the event
    username = event.get('username', '')
    password = event.get('password', '')
    
    if not username or not password:
        raise Exception('Unauthorized')
    
    try:
        # Get secret name from environment variable
        secret_name = os.environ.get('SECRETS_MANAGER_SECRET_NAME', 'sftp-users')
        # Get region from context or default to us-east-1
        region = context.invoked_function_arn.split(':')[3] if context else 'us-east-1'
        
        # Create Secrets Manager client
        secrets_client = boto3.client('secretsmanager', region_name=region)
        
        # Retrieve secret from Secrets Manager
        try:
            secret_response = secrets_client.get_secret_value(SecretId=secret_name)
            users_data = json.loads(secret_response['SecretString'])
        except secrets_client.exceptions.ResourceNotFoundException:
            raise Exception('Unauthorized')
        
        # Validate credentials
        if username not in users_data:
            raise Exception('Unauthorized')
        
        user_info = users_data[username]
        
        # Verify password (can be plain text or hashed)
        stored_password = user_info.get('password', '')
        
        # Support both plain text and hashed passwords
        # If password_hash is provided, use it; otherwise use plain password
        if 'password_hash' in user_info:
            # Hash the provided password and compare
            password_hash = hashlib.sha256(password.encode()).hexdigest()
            if password_hash != user_info['password_hash']:
                raise Exception('Unauthorized')
        else:
            # Plain text comparison
            if password != stored_password:
                raise Exception('Unauthorized')
        
        # Get user-specific role or use default
        role_arn = user_info.get('role_arn', os.environ.get('DEFAULT_ROLE_ARN'))
        s3_bucket = os.environ.get('S3_BUCKET_NAME', 'sftp-tcm-sunflower')
        
        # Get user-specific home directory or use default
        home_directory = user_info.get('home_directory', f'/{s3_bucket}/{username}')
        
        # Return success response
        response = {
            'Role': role_arn,
            'HomeDirectory': home_directory,
            'Policy': user_info.get('policy', ''),
            'PublicKeys': user_info.get('public_keys', [])
        }
        
        return response
        
    except Exception as e:
        # Log error for debugging
        print(f"Authentication error: {str(e)}")
        raise Exception('Unauthorized')
