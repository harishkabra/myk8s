#!/bin/bash

# Set variables
export CLUSTER_NAME="myfirstcluster.hkdevops.store"
export KOPS_STATE_STORE="s3://kops-hkabra-storage"
export REGION="us-east-1"
export NODE_COUNT=2
export NODE_SIZE="t3.medium"
export CONTROL_PLANE_SIZE="t3.medium"
export CONTROL_PLANE_VOL=10
export NODE_VOL=10
export PARENT_DNS_ZONE="hkdevops.store"  # FIXED: Correct parent hosted zone
export SSH_KEY_PATH="$HOME/.ssh/kops-key.pub"

echo "===== 🚀 Updating System Packages ====="
sudo apt update -y

# Install dependencies if missing
if ! command -v aws &>/dev/null; then
    echo "❌ AWS CLI not found. Installing..."
    sudo apt install awscli -y
fi

if ! command -v kops &>/dev/null; then
    echo "❌ Kops not found. Installing..."
    curl -Lo kops https://github.com/kubernetes/kops/releases/latest/download/kops-linux-amd64
    chmod +x kops && sudo mv kops /usr/local/bin/kops
fi

if ! command -v kubectl &>/dev/null; then
    echo "❌ Kubectl not found. Installing..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl
fi

# Check if S3 bucket exists for Kops state
if aws s3 ls "$KOPS_STATE_STORE" 2>/dev/null; then
    echo "✅ S3 bucket exists: $KOPS_STATE_STORE"
else
    echo "❌ S3 bucket not found. Creating..."
    aws s3 mb "$KOPS_STATE_STORE" --region $REGION
    aws s3api put-bucket-versioning --bucket $(basename $KOPS_STATE_STORE) --versioning-configuration Status=Enabled
fi

# Generate SSH key if missing
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "🔑 Generating SSH key..."
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/kops-key -N ""
fi

# Determine Availability Zones
if [[ $NODE_COUNT -ge 4 ]]; then
    ZONE="us-east-1a,us-east-1b,us-east-1c"
elif [[ $NODE_COUNT -ge 2 ]]; then
    ZONE="us-east-1a,us-east-1b"
else
    ZONE="us-east-1a"
fi

# Verify Route 53 Hosted Zone
echo "===== 🔍 Checking Route 53 Hosted Zone ====="
DNS_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='$PARENT_DNS_ZONE.'].Id" --output text | cut -d'/' -f3)

if [ -z "$DNS_ZONE_ID" ]; then
    echo "❌ Route 53 DNS Zone '$PARENT_DNS_ZONE' does not exist. Exiting..."
    exit 1
else
    echo "✅ Route 53 DNS Zone exists: $PARENT_DNS_ZONE"
fi

# Check for existing cluster
echo "===== 🔍 Checking for Existing Kops Cluster ====="
if kops get cluster --state=$KOPS_STATE_STORE | grep -q "$CLUSTER_NAME"; then
    echo "✅ Cluster '$CLUSTER_NAME' found."
    echo "What do you want to do?"
    echo "1) Delete and recreate the cluster"
    echo "2) Update the cluster"
    echo "3) Exit"
    read -p "Enter your choice (1/2/3): " CHOICE

    case $CHOICE in
        1)
            echo "🛑 Deleting existing cluster..."
            kops delete cluster --name=$CLUSTER_NAME --state=$KOPS_STATE_STORE --yes
            echo "✅ Cluster deleted."
            ;;
        2)
            echo "🔄 Updating cluster..."
            kops update cluster --name=$CLUSTER_NAME --state=$KOPS_STATE_STORE --yes
            kops rolling-update cluster --name=$CLUSTER_NAME --state=$KOPS_STATE_STORE --yes
            echo "✅ Cluster updated."
            exit 0
            ;;
        3)
            echo "❌ Exiting."
            exit 0
            ;;
        *)
            echo "⚠️ Invalid option. Exiting."
            exit 1
            ;;
    esac
fi

# Create new cluster
echo "===== 🚀 Creating Kops Cluster ====="
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
  --yes

echo "✅ Cluster creation initiated. This may take a few minutes."

# Validate Cluster
echo "===== ⏳ Waiting for Cluster to Be Ready ====="
sleep 30
kops validate cluster --wait 10m --state=$KOPS_STATE_STORE

echo "🚀 Cluster is now ready!"

# Check if cluster is resolving DNS properly
echo "===== 🔍 Testing Cluster DNS ====="
dig $CLUSTER_NAME
