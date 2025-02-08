#!/bin/bash

# Set variables
export CLUSTER_NAME="k8sdemo.hkdevops.store"
export KOPS_STATE_STORE="s3://kops-hkabra-storage"
export REGION="us-east-1"
export ZONE="us-east-1a"
export NODE_COUNT=1
export NODE_SIZE="t3.medium"
export CONTROL_PLANE_SIZE="t3.medium"
export CONTROL_PLANE_VOL=20
export NODE_VOL=20
export PARENT_DNS_ZONE="hkdevops.store"  # Parent Hosted Zone in Route 53

echo "===== Updating System ====="
sudo apt update -y

echo "===== Checking for Route 53 Hosted Zone ====="
DNS_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='$CLUSTER_NAME.'].Id" --output text | cut -d'/' -f3)

if [ -z "$DNS_ZONE_ID" ]; then
    echo "❌ Route 53 DNS zone '$CLUSTER_NAME' does not exist. Creating..."
    DNS_ZONE_ID=$(aws route53 create-hosted-zone --name $CLUSTER_NAME --caller-reference $(date +%s) --query "HostedZone.Id" --output text | cut -d'/' -f3)
    echo "✅ Created Route 53 DNS Zone with ID: $DNS_ZONE_ID"
else
    echo "✅ Route 53 DNS Zone '$CLUSTER_NAME' already exists."
fi

echo "===== Ensuring DNS Delegation in Parent Zone ====="
PARENT_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='$PARENT_DNS_ZONE.'].Id" --output text | cut -d'/' -f3)

if [ -n "$PARENT_ZONE_ID" ]; then
    NS_SERVERS=$(aws route53 get-hosted-zone --id $DNS_ZONE_ID --query "DelegationSet.NameServers" --output json)
    CHANGE_BATCH=$(cat <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$CLUSTER_NAME.",
        "Type": "NS",
        "TTL": 300,
        "ResourceRecords": $(echo $NS_SERVERS | jq -c 'map({ "Value": . })')
      }
    }
  ]
}
EOF
)
    aws route53 change-resource-record-sets --hosted-zone-id $PARENT_ZONE_ID --change-batch "$CHANGE_BATCH"
    echo "✅ NS Records Updated in Parent Domain ($PARENT_DNS_ZONE)"
else
    echo "⚠️ Parent Hosted Zone ($PARENT_DNS_ZONE) not found! You may need to add NS records manually."
fi

echo "===== Waiting for Route 53 DNS to Propagate ====="
while ! nslookup $CLUSTER_NAME; do
    echo "⏳ Waiting for DNS propagation... Retrying in 30 seconds"
    sleep 30
done
echo "✅ DNS is now resolvable. Proceeding with cluster setup."

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
    echo "❌ No existing cluster found. Proceeding with creation..."
fi

echo "===== Creating Kubernetes Cluster with KOPS ====="
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
--dns-zone=$CLUSTER_NAME \
--yes

echo "===== Exporting Kubeconfig (Fix CA Certificate Issue) ====="
kops export kubecfg --name=$CLUSTER_NAME --state=$KOPS_STATE_STORE

echo "===== Waiting for Cluster to be Ready ====="
sleep 60
while ! kops validate cluster --state=$KOPS_STATE_STORE --name=$CLUSTER_NAME | grep -q 'is ready'; do
    echo "⏳ Waiting for cluster to become ready..."
    sleep 30
done

echo "===== Deploying Test Application (NGINX) ====="
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=LoadBalancer
sleep 5
kubectl get svc

echo "===== Opening Security Groups for LoadBalancer ====="
SEC_GROUP_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=${CLUSTER_NAME}-* --query "SecurityGroups[0].GroupId" --output text)
aws ec2 authorize-security-group-ingress --group-id $SEC_GROUP_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SEC_GROUP_ID --protocol tcp --port 443 --cidr 0.0.0.0/0

echo "✅ Cluster Created Successfully!"
kubectl get nodes
