data "aws_ami" "eks-worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${aws_eks_cluster.astounding.version}-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}

data "aws_ami" "amzn-linux" {
  filter {
    name   = "name"
    values = ["amzn-ami-hvm*"]
  }

  most_recent = true
  owners      = ["137112412989"] # Amazon EKS AMI Account ID
}

data "aws_ami" "xilinx" {
  filter {
    name   = "name"
    values = ["inprog"]
  }

  most_recent = true
  owners      = ["260383856316"] # Amazon EKS AMI Account ID
}


data "aws_ami" "fpga-worker-node" {
  filter {
    name   = "name"
    values = ["amazon-eks-fpga-worker-node-*"]
  }

  most_recent = true
  owners      = ["898843949075"] # Amazon EKS AMI Account ID
}
