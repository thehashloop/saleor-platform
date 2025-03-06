#!/bin/bash

# Debug: Print current working directory and user
echo "Current directory: $(pwd)"
echo "Running as user: $(whoami)"

# Validate required environment variables
required_vars=("DO_SPACES_KEY" "DO_SPACES_SECRET" "DO_SPACES_NAME" "DO_SPACES_REGION" "ENVIRONMENT")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: Required environment variable $var is not set"
        exit 1
    fi
done

# Debug: Print environment variables (without secrets)
echo "Environment: $ENVIRONMENT"
echo "Spaces Name: $DO_SPACES_NAME"
echo "Spaces Region: $DO_SPACES_REGION"

# Validate environment
valid_environments=("dev" "staging" "prod")
if [[ ! " ${valid_environments[@]} " =~ " ${ENVIRONMENT} " ]]; then
    echo "Error: Invalid environment '${ENVIRONMENT}'"
    echo "Valid environments are: ${valid_environments[*]}"
    exit 1
fi

echo "Fetching environment files for: ${ENVIRONMENT}"

# Install s3cmd if not present
if ! command -v s3cmd &> /dev/null; then
    echo "Installing s3cmd..."
    sudo apt-get update
    sudo apt-get install -y s3cmd
fi

# Create temp directory for env files
mkdir -p .env-files
chmod 755 .env-files

# Configure s3cmd
echo "Configuring s3cmd..."
cat > ~/.s3cfg << EOL
[default]
access_key = ${DO_SPACES_KEY}
secret_key = ${DO_SPACES_SECRET}
host_base = ${DO_SPACES_REGION}.digitaloceanspaces.com
host_bucket = %(bucket)s.${DO_SPACES_REGION}.digitaloceanspaces.com
use_https = True
EOL
chmod 600 ~/.s3cfg

# Set the environment files path
ENV_FILES_PATH="env-files/${ENVIRONMENT}"

# Debug: List available buckets
echo "Listing available buckets:"
s3cmd ls

# Debug: Check if bucket exists
echo "Checking bucket ${DO_SPACES_NAME}:"
s3cmd ls s3://${DO_SPACES_NAME}/

# Debug: List all contents of the bucket recursively
echo "Listing all contents of bucket ${DO_SPACES_NAME}:"
s3cmd ls --recursive s3://${DO_SPACES_NAME}/

# Check if environment directory exists in Spaces
echo "Checking for environment directory: ${ENV_FILES_PATH}"
if ! s3cmd ls s3://${DO_SPACES_NAME}/${ENV_FILES_PATH}/ &>/dev/null; then
    echo "Error: Environment directory '${ENV_FILES_PATH}' not found in Spaces"
    echo "Available paths in bucket:"
    s3cmd ls s3://${DO_SPACES_NAME}/
    exit 1
fi

# Debug: List contents of environment directory
echo "Contents of ${ENV_FILES_PATH}:"
s3cmd ls s3://${DO_SPACES_NAME}/${ENV_FILES_PATH}/

# Download environment files from Spaces
echo "Downloading environment files from Spaces..."
required_files=("backend.env" "frontend.env" "common.env" "deployment.env")
for file in "${required_files[@]}"; do
    echo "Downloading ${file}..."
    s3cmd get s3://${DO_SPACES_NAME}/${ENV_FILES_PATH}/${file} .env-files/${file}
    if [ ! -f ".env-files/${file}" ]; then
        echo "Error: Failed to download ${file}"
        exit 1
    fi
    echo "Successfully downloaded ${file}"
done

# Debug: Show downloaded files
echo "Contents of .env-files directory after download:"
ls -la .env-files/

# Clean up environment files (remove carriage returns and trailing whitespace)
echo "Cleaning up environment files..."
for file in .env-files/*; do
    if [ -f "$file" ]; then
        # Remove carriage returns and trailing whitespace
        sed -i 's/\r$//' "$file"
        sed -i 's/[[:space:]]*$//' "$file"
        echo "Cleaned up $(basename "$file")"
    fi
done

# Move files to their correct locations
echo "Moving environment files to their locations..."
for file in .env-files/*; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        cp "$file" "./${filename}"
        chmod 644 "./${filename}"
        echo "Copied ${filename}"
    fi
done

# Create environment indicator file
echo "${ENVIRONMENT}" > ./.env_current
chmod 644 ./.env_current

# Clean up
rm -rf .env-files
rm -f ~/.s3cfg

echo "Successfully configured environment: ${ENVIRONMENT}" 