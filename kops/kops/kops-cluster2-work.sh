kops kubernetes installation

1. DNS NAME
2. S3 BUCKET
3. IAM ROLE AND ASSIGN IT TO EC2
4. CREATE A EC2 INSTANCE AND GENERATE SSH ROLE

Download Kops and Kubectl to /usr/local/bin and change permissions.
1. 

# Download Kubectl and give permissions.
# Edit .bashrc and add all the environment variables

export NAME=k8sdemo.hkdevops.store
export KOPS_STATE_STORE=s3://kops-hkabra-storage
export AWS_REGION=us-east-1
export CLUSTER_NAME=k8sdemo.hkdevops.store
export EDITOR='/usr/bin/nano'
#export K8S_VERSION=1.6.4

# After copying the above files to .bashrc, run: 
source .bashrc

# Create a Cluster using Kops and generate a cluster file.
# Save it carefully and do necessary changes.

kops create cluster --name=k8sdemo.hkdevops.store \
  --state=s3://kops-hkabra-storage \
  --zones=us-east-1a,us-east-1b \
  --node-count=2 --control-plane-count=1 --node-size=t3.medium \
  --control-plane-size=t3.medium --control-plane-zones=us-east-1a \
  --control-plane-volume-size=10 --node-volume-size=10 \
  --ssh-public-key ~/.ssh/id_ed25519.pub \
  --dns-zone=hkdevops.store --dry-run --output yaml


  #kops create -f cluster.yml

  #kops update cluster --name k8sdemo.hkdevops.store --yes --admin


