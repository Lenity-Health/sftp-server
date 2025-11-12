#!/bin/bash

# Script to manage SFTP users in AWS Secrets Manager
# Usage: ./manage_users.sh [add|list|update|delete] [username] [password] [home_directory]

SECRET_NAME="sftp-users"
REGION="us-east-1"
DEFAULT_ROLE_ARN="arn:aws:iam::211125733224:role/TransferFamilyS3AccessRoleSFTP"
S3_BUCKET="sftp-tcm-sunflower"

ACTION=${1:-list}
USERNAME=$2
PASSWORD=$3
HOME_DIR=$4

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

case $ACTION in
  list)
    echo -e "${GREEN}Current SFTP users:${NC}"
    aws secretsmanager get-secret-value --secret-id $SECRET_NAME --region $REGION \
      --query 'SecretString' --output text | python3 -m json.tool
    ;;
    
  add)
    if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
      echo -e "${RED}Error: Username and password are required${NC}"
      echo "Usage: ./manage_users.sh add <username> <password> [home_directory]"
      exit 1
    fi
    
    HOME_DIRECTORY=${HOME_DIR:-"/$S3_BUCKET/$USERNAME"}
    
    echo -e "${YELLOW}Adding user: $USERNAME${NC}"
    
    # Get current secret
    CURRENT_SECRET=$(aws secretsmanager get-secret-value --secret-id $SECRET_NAME --region $REGION \
      --query 'SecretString' --output text)
    
    # Parse and add new user
    NEW_USER_JSON=$(cat <<EOF
{
  "password": "$PASSWORD",
  "role_arn": "$DEFAULT_ROLE_ARN",
  "home_directory": "$HOME_DIRECTORY",
  "policy": "",
  "public_keys": []
}
EOF
)
    
    # Update secret using Python for proper JSON handling
    python3 <<PYTHON
import json
import subprocess
import sys

try:
    # Get current secret
    result = subprocess.run(
        ['aws', 'secretsmanager', 'get-secret-value', 
         '--secret-id', '$SECRET_NAME', '--region', '$REGION',
         '--query', 'SecretString', '--output', 'text'],
        capture_output=True, text=True, check=True
    )
    users = json.loads(result.stdout)
    
    # Check if user already exists
    if '$USERNAME' in users:
        print("Error: User already exists", file=sys.stderr)
        sys.exit(1)
    
    # Add new user
    users['$USERNAME'] = {
        "password": "$PASSWORD",
        "role_arn": "$DEFAULT_ROLE_ARN",
        "home_directory": "$HOME_DIRECTORY",
        "policy": "",
        "public_keys": []
    }
    
    # Update secret
    subprocess.run(
        ['aws', 'secretsmanager', 'update-secret',
         '--secret-id', '$SECRET_NAME', '--region', '$REGION',
         '--secret-string', json.dumps(users)],
        check=True
    )
    print("User added successfully!")
except subprocess.CalledProcessError as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON
    ;;
    
  update)
    if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
      echo -e "${RED}Error: Username and password are required${NC}"
      echo "Usage: ./manage_users.sh update <username> <password> [home_directory]"
      exit 1
    fi
    
    HOME_DIRECTORY=${HOME_DIR:-"/$S3_BUCKET/$USERNAME"}
    
    echo -e "${YELLOW}Updating user: $USERNAME${NC}"
    
    python3 <<PYTHON
import json
import subprocess
import sys

try:
    # Get current secret
    result = subprocess.run(
        ['aws', 'secretsmanager', 'get-secret-value',
         '--secret-id', '$SECRET_NAME', '--region', '$REGION',
         '--query', 'SecretString', '--output', 'text'],
        capture_output=True, text=True, check=True
    )
    users = json.loads(result.stdout)
    
    # Check if user exists
    if '$USERNAME' not in users:
        print("Error: User does not exist", file=sys.stderr)
        sys.exit(1)
    
    # Update user
    users['$USERNAME']['password'] = "$PASSWORD"
    if '$HOME_DIRECTORY':
        users['$USERNAME']['home_directory'] = "$HOME_DIRECTORY"
    
    # Update secret
    subprocess.run(
        ['aws', 'secretsmanager', 'update-secret',
         '--secret-id', '$SECRET_NAME', '--region', '$REGION',
         '--secret-string', json.dumps(users)],
        check=True
    )
    print("User updated successfully!")
except subprocess.CalledProcessError as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON
    ;;
    
  delete)
    if [ -z "$USERNAME" ]; then
      echo -e "${RED}Error: Username is required${NC}"
      echo "Usage: ./manage_users.sh delete <username>"
      exit 1
    fi
    
    echo -e "${YELLOW}Deleting user: $USERNAME${NC}"
    
    python3 <<PYTHON
import json
import subprocess
import sys

try:
    # Get current secret
    result = subprocess.run(
        ['aws', 'secretsmanager', 'get-secret-value',
         '--secret-id', '$SECRET_NAME', '--region', '$REGION',
         '--query', 'SecretString', '--output', 'text'],
        capture_output=True, text=True, check=True
    )
    users = json.loads(result.stdout)
    
    # Check if user exists
    if '$USERNAME' not in users:
        print("Error: User does not exist", file=sys.stderr)
        sys.exit(1)
    
    # Delete user
    del users['$USERNAME']
    
    # Update secret
    subprocess.run(
        ['aws', 'secretsmanager', 'update-secret',
         '--secret-id', '$SECRET_NAME', '--region', '$REGION',
         '--secret-string', json.dumps(users)],
        check=True
    )
    print("User deleted successfully!")
except subprocess.CalledProcessError as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON
    ;;
    
  *)
    echo -e "${RED}Invalid action: $ACTION${NC}"
    echo "Usage: ./manage_users.sh [list|add|update|delete] [username] [password] [home_directory]"
    exit 1
    ;;
esac
