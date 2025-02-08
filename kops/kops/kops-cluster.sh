#!/bin/bash

# Set variables
export CLUSTER_NAME="k8sdemo.hkdevops.store"
export KOPS_STATE_STORE="s3://kops-hkabra-storage"
export REGION="us-east-1"
export ZONE="us-east-1a"
export NODE_COUNT=1
export NODE_SIZE="t2.micro"
export CONTROL_PLANE_SIZE="t2.micro"
export CONTROL_PLANE_VOL=8
export NODE_VOL=8

echo "----- Updating System -----"
sudo apt update -y

echo "----- Installing Dependencies -----"
# Install AWS CLI
if ! command -v aws &> /dev/null; then
    echo "Installing AWS CLI..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    sudo apt install unzip -y
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf awscliv2.zip aws/
fi
aws --version

# Install Kubectl
if ! command -v kubectl &> /dev/null; then
    echo "Installing Kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
fi
kubectl version --client

# Install KOPS
if ! command -v kops &> /dev/null; then
    echo "Installing KOPS..."
    curl -LO https://github.com/kubernetes/kops/releases/latest/download/kops-linux-amd64
    chmod +x kops-linux-amd64
    sudo mv kops-linux-amd64 /usr/local/bin/kops
fi
kops version

echo "----- Configuring AWS CLI -----"
aws configure

echo "----- Creating S3 Bucket for KOPS State Store -----"
aws s3 mb $KOPS_STATE_STORE --region $REGION || true
aws s3api put-bucket-versioning --bucket kops-hkabra-storage --versioning-configuration Status=Enabled

echo "----- Creating Kubernetes Cluster with KOPS -----"
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
--yes

echo "----- Validating Cluster -----"
sleep 600  # Give time for cluster creation
kops validate cluster --state=$KOPS_STATE_STORE --name=$CLUSTER_NAME

echo "----- Deploying Test Application -----"
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=LoadBalancer
kubectl get svc

echo "----- Cluster Created Successfully -----"
echo "Use 'kubectl get nodes' to see the nodes."

# -----------------
# Remove Cluster
# -----------------
echo "Do you want to delete the cluster? (yes/no)"
read CONFIRM
if [[ $CONFIRM == "yes" ]]; then
    echo "----- Deleting Kubernetes Cluster -----"
    kops delete cluster --name=$CLUSTER_NAME --state=$KOPS_STATE_STORE --yes
    echo "Cluster deleted successfully!"
else
    echo "Cluster retained!"
fi
