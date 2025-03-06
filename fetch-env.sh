#!/bin/bash

# Validate required environment variables
required_vars=("DO_SPACES_KEY" "DO_SPACES_SECRET" "DO_SPACES_NAME" "DO_SPACES_REGION" "ENVIRONMENT")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: Required environment variable $var is not set"
        exit 1
    fi
done

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
    apt-get update && apt-get install -y s3cmd
fi

# Configure s3cmd
cat > ~/.s3cfg << EOL
[default]
access_key = ${DO_SPACES_KEY}
secret_key = ${DO_SPACES_SECRET}
host_base = ${DO_SPACES_REGION}.digitaloceanspaces.com
host_bucket = %(bucket)s.${DO_SPACES_REGION}.digitaloceanspaces.com
use_https = True
EOL

# Create temp directory for env files
mkdir -p .env-files

# Set the environment files path
ENV_FILES_PATH="env-files/${ENVIRONMENT}"

# Check if environment directory exists in Spaces
if ! s3cmd ls s3://${DO_SPACES_NAME}/${ENV_FILES_PATH}/ &>/dev/null; then
    echo "Error: Environment directory '${ENV_FILES_PATH}' not found in Spaces"
    exit 1
fi

# Download environment files from Spaces
echo "Downloading environment files from Spaces..."
s3cmd get --recursive s3://${DO_SPACES_NAME}/${ENV_FILES_PATH}/* .env-files/

# Check if required files exist
required_files=("backend.env" "frontend.env" "common.env" "deployment.env")
for file in "${required_files[@]}"; do
    if [ ! -f ".env-files/${file}" ]; then
        echo "Error: Required file '${file}' not found in ${ENV_FILES_PATH}"
        exit 1
    fi
done

# Move files to their correct locations
echo "Moving environment files to their locations..."
for file in .env-files/*; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        cp "$file" "./${filename}"
        echo "Copied ${filename}"
    fi
done

# Create environment indicator file
echo "${ENVIRONMENT}" > ./.env_current

# Clean up
rm -rf .env-files
rm -f ~/.s3cfg

echo "Successfully configured environment: ${ENVIRONMENT}" 