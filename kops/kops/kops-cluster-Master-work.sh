#!/bin/bash

# Set variables
export CLUSTER_NAME="myfirstcluster.hkdevops.store"
export KOPS_STATE_STORE="s3://kops-hkabra-storage"
export REGION="us-east-1"
export NODE_COUNT=2  # Change this to scale worker nodes
export NODE_SIZE="t3.medium"
export CONTROL_PLANE_SIZE="t3.medium"
export CONTROL_PLANE_VOL=20
export NODE_VOL=20
export PARENT_DNS_ZONE="hkdevops.store"
export SSH_KEY_PATH="$HOME/.ssh/kops-key.pub"

echo "===== Updating System ====="
sudo apt update -y

# Check if KOPS is installed
if ! command -v kops &>/dev/null; then
    echo "❌ KOPS not found. Installing..."
    curl -Lo kops https://github.com/kubernetes/kops/releases/latest/download/kops-linux-amd64
    chmod +x kops
    sudo mv kops /usr/local/bin/kops
    echo "✅ KOPS installed successfully: $(kops version)"
else
    echo "✅ KOPS is already installed: $(kops version)"
fi

# Check if Kubectl is installed
if ! command -v kubectl &>/dev/null; then
    echo "❌ Kubectl not found. Installing..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/kubectl
    echo "✅ Kubectl installed successfully: $(kubectl version --client --short)"
else
    echo "✅ Kubectl is already installed: $(kubectl version --client --short)"
fi

# Check if S3 bucket exists
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

# Determine Availability Zones Based on Node Count
if [[ $NODE_COUNT -ge 4 ]]; then
    ZONE="us-east-1a,us-east-1b,us-east-1c"
elif [[ $NODE_COUNT -ge 2 ]]; then
    ZONE="us-east-1a,us-east-1b"
else
    ZONE="us-east-1a"
fi

echo "===== Checking for Route 53 Hosted Zone ====="
DNS_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='$CLUSTER_NAME.'].Id" --output text | cut -d'/' -f3)

if [ -z "$DNS_ZONE_ID" ]; then
    echo "❌ Route 53 DNS zone '$CLUSTER_NAME' does not exist. Exiting..."
    exit 1
else
    echo "✅ Route 53 DNS Zone '$CLUSTER_NAME' already exists."
fi

echo "===== Checking for Existing Cluster ====="
if kops get cluster --state=$KOPS_STATE_STORE | grep -q "$CLUSTER_NAME"; then
    echo "✅ Cluster '$CLUSTER_NAME' already exists."
    echo "What would you like to do?"
    echo "1) Delete and recreate the cluster"
    echo "2) Update the cluster"
    echo "3) Exit"
    read -p "Enter your choice (1/2/3): " CHOICE

    case $CHOICE in
        1)
            echo "🛑 Deleting the existing cluster..."
            kops delete cluster --name=$CLUSTER_NAME --state=$KOPS_STATE_STORE --yes
            echo "✅ Cluster deleted successfully!"
            ;;
        2)
            echo "🔄 Updating the cluster..."
            kops update cluster --name=$CLUSTER_NAME --state=$KOPS_STATE_STORE --yes
            kops rolling-update cluster --name=$CLUSTER_NAME --state=$KOPS_STATE_STORE --yes
            echo "✅ Cluster updated successfully!"
            exit 0
            ;;
        3)
            echo "❌ Exiting without making changes."
            exit 0
            ;;
        *)
            echo "⚠️ Invalid option. Exiting."
            exit 1
            ;;
    esac
else
    echo "❌ No existing cluster found. Proceeding with dry-run configuration..."
fi

echo "===== Generating Dry Run Cluster Configuration ====="

kops create cluster \
--name=$CLUSTER_NAME \
--state=$KOPS_STATE_STORE \
--cloud=aws \
--zones=$ZONE \
--node-count=$NODE_COUNT \
--node-size=$NODE_SIZE \
--control-plane-size=$CONTROL_PLANE_SIZE \
--control-plane-volume-size=$CONTROL_PLANE_VOL \
--node-volume-size=$NODE_VOL \
--ssh-public-key $SSH_KEY_PATH \
--dns-zone=$PARENT_DNS_ZONE \
#--yes
--dry-run -o yaml > cluster-config.yaml

echo "✅ Dry-run completed. A configuration file 'cluster-config.yaml' has been created."
echo "🔹 Modify 'cluster-config.yaml' to adjust CIDR, subnets, networking, and instance types."
echo "🔹 Once ready, apply the configuration by running:"
echo "   kops create -f cluster-config.yaml --state=$KOPS_STATE_STORE --yes"
