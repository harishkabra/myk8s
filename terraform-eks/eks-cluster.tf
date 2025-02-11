provider "aws" {
  region = "us-east-1"
}

# ------------------------------
# VPC and Networking Resources
# ------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "hk-eks-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "hk-eks-vpc"
  }
}

# ------------------------------
# IAM Role for EKS Cluster
# ------------------------------
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# ------------------------------
# IAM Role for Worker Nodes
# ------------------------------
resource "aws_iam_role" "eks_node_role" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

# ------------------------------
# Security Group for EKS Cluster
# ------------------------------
resource "aws_security_group" "eks_security_group" {
  vpc_id = module.vpc.vpc_id
  name   = "eks-cluster-sg"

  # Allow inbound traffic on port 443 (HTTPS)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound traffic on port 80 (HTTP)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound traffic on port 22 (SSH)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-security-group"
  }
}

# ------------------------------
# Create EKS Cluster
# ------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.0.0"

  cluster_name    = "hk-eks-cluster"
  cluster_version = "1.28"

  iam_role_arn = aws_iam_role.eks_cluster_role.arn
  subnet_ids   = module.vpc.private_subnets
  vpc_id       = module.vpc.vpc_id

  enable_irsa               = true
  cluster_security_group_id = aws_security_group.eks_security_group.id

  # Managed Node Group Configuration
  eks_managed_node_groups = {
    eks-node-group = {
      desired_size = 1
      min_size     = 1
      max_size     = 3

      instance_types = ["t3.medium"]
      key_name       = "hk-aws1-admin" # Associate EC2 Key Pair

      iam_role_arn = aws_iam_role.eks_node_role.arn
    }
  }

  tags = {
    Environment = "dev"
    Name        = "hk-eks-cluster"
  }
}
