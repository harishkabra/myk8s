kops kubernetes installation

1. DNS NAME
2. S3 BUCKET
3. IAM ROLE AND ASSIGN IT TO EC2
4. CREATE A EC2 INSTANCE AND GENERATE SSH ROLE
5. Download Kops and Kubectl to /usr/local/bin and change permissions.
SSH KEY 
ssh-keygen -t rsa -b 4096 -f ~/.ssh/kops-key


====kops===============
sudo apt update && sudo apt upgrade -y

sudo curl -LO https://github.com/kubernetes/kops/releases/latest/download/kops-linux-amd64
sudo chmod +x kops-linux-amd64
sudo mv kops-linux-amd64 /usr/local/bin/kops

kops version
======================================
============aws cli========================



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
  --ssh-public-key ~/.ssh/kops-key.pub\
  --dns-zone=hkdevops.store --dry-run --output yaml


  #kops create -f cluster.yml

  #kops update cluster --name k8sdemo.hkdevops.store --yes --admin


  kops create -f cluster.yml

  kops update cluster --name hkdevops.store --yes --admin

  kops validate cluster --wait 10m

  kops delete -f cluster.yml --yes
  
  kubectl cluster-info
  
  kubectl get ns

  kubectl get pods -n kube-system -o wide | grep -i api
  kubectl get pods -n kube-system -o wide | grep -i etcd
  kubectl get pods -n kube-system -o wide | grep -i control
  kubectl get pods -n kube-system -o wide | grep -i scheduler


  kubectl run testpod1 --image nginx:latest --dry-run -o yaml

  kubectl create deployment testpod --image hkabra/gymapp:v1 --replicas 6 --dry-run -o yaml

  ## update cluster 

  kops get ig
  kops delete ig nodes-us-east-1b --yes
   kops update cluster --yes


   # kubectl api-resources --namespaced=true

   echo ' <commond> ' | kubectl apply -f 

   kubens look into it


   ### Lens
   cd ~/.kobe/ then check ls -al copy the config file contect to your local systerm and then copy this to lens
   ## imp commonds
   #kubectl api-resources --namespaced=true 
