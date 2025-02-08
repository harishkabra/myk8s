#!/bin/bash

# Set variables
export KOPS_STATE_STORE="s3://kops-hkabra-storage"
export REGION="us-east-1"
export SSH_KEY_PATH="$HOME/.ssh/kops-key.pub"

echo "===== Updating System ====="
sudo apt update -y

# Create S3 Bucket for KOPS State
echo "===== Checking S3 Bucket for KOPS State Store ====="
if aws s3 ls "$KOPS_STATE_STORE" 2>/dev/null; then
    echo "✅ S3 bucket already exists: $KOPS_STATE_STORE"
else
    echo "❌ S3 bucket does not exist. Creating..."
    aws s3 mb "$KOPS_STATE_STORE" --region $REGION
    aws s3api put-bucket-versioning --bucket $(basename $KOPS_STATE_STORE) --versioning-configuration Status=Enabled
    echo "✅ S3 bucket created successfully!"
fi

# Generate SSH Key if not exists
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "🔑 Generating SSH key for KOPS..."
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/kops-key -N ""
else
    echo "✅ SSH key already exists: $SSH_KEY_PATH"
fi

echo "===== AWS Prerequisites Completed Successfully! ====="
