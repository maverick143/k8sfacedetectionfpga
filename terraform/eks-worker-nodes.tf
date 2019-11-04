#
# EKS Worker Nodes Resources
#  * IAM role allowing Kubernetes actions to access other AWS services
#  * EC2 Security Group to allow networking traffic
#  * Data source to fetch latest EKS worker AMI
#  * AutoScaling Launch Configuration to configure worker instances
#  * AutoScaling Group to launch worker instances
#

resource "aws_iam_role" "astounding-node" {
  name = "${var.cluster-name}-node-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy" "astounding-node-policy" {
  name = "${var.cluster-name}-node-role-policy"
  role = aws_iam_role.astounding-node.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ec2:ModifyInstanceAttribute",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "astounding-node-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = "${aws_iam_role.astounding-node.name}"
}

resource "aws_iam_role_policy_attachment" "astounding-node-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = "${aws_iam_role.astounding-node.name}"
}

resource "aws_iam_role_policy_attachment" "astounding-node-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = "${aws_iam_role.astounding-node.name}"
}

resource "aws_iam_role_policy_attachment" "astounding-node-ALBPolicy" {
  policy_arn = aws_iam_policy.alb-policy.arn
  role       = aws_iam_role.astounding-node.name
}

resource "aws_iam_instance_profile" "astounding-node" {
  name = var.cluster-name
  role = "${aws_iam_role.astounding-node.name}"
}

resource "aws_security_group" "astounding-node" {
  name        = "${var.cluster-name}-node"
  description = "Security group for all nodes in the cluster"
  vpc_id      = "${aws_vpc.astounding.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = map(
     "Name", "${var.cluster-name}-node",
     "kubernetes.io/cluster/${var.cluster-name}", "owned",
    )
}

resource "aws_security_group_rule" "astounding-node-ingress-self" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = "${aws_security_group.astounding-node.id}"
  source_security_group_id = "${aws_security_group.astounding-node.id}"
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "astounding-node-ingress-cluster" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = aws_security_group.astounding-node.id
  source_security_group_id = aws_security_group.astounding-cluster.id
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "astounding-node-ssh-bastion" {
  description              = "Allow SSH bastion to ssh"
  from_port                = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.astounding-node.id
  source_security_group_id = aws_security_group.bastion-sg.id
  to_port                  = 22
  type                     = "ingress"
}

# EKS currently documents this required userdata for EKS worker nodes to
# properly configure Kubernetes applications on the EC2 instance.
# We utilize a Terraform local here to simplify Base64 encoding this
# information into the AutoScaling Launch Configuration.
# More information: https://docs.aws.amazon.com/eks/latest/userguide/launch-workers.html
locals {
  astounding-node-userdata = <<USERDATA
#!/bin/bash
set -eo xtrace
INSTANCEID=`curl -s http://169.254.169.254/latest/meta-data/instance-id`
aws ec2 modify-instance-attribute --instance-id $INSTANCEID --no-source-dest-check --region ${data.aws_region.current.name}
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.astounding.endpoint}' --b64-cluster-ca '${aws_eks_cluster.astounding.certificate_authority.0.data}' '${var.cluster-name}'
USERDATA
}

locals {
  fpga-node-userdata = <<FGPAUSERDATA
#!/bin/bash
set -eo xtrace
INSTANCEID=`curl -s http://169.254.169.254/latest/meta-data/instance-id`
aws ec2 modify-instance-attribute --instance-id $INSTANCEID --no-source-dest-check --region ${data.aws_region.current.name}
/etc/eks/bootstrap.sh --kubelet-extra-args '--node-labels=nodeType=xilinx' --apiserver-endpoint '${aws_eks_cluster.astounding.endpoint}' --b64-cluster-ca '${aws_eks_cluster.astounding.certificate_authority.0.data}' '${var.cluster-name}'
FGPAUSERDATA
}

resource "aws_launch_configuration" "standard" {
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.astounding-node.name
  image_id                    = data.aws_ami.eks-worker.id
  instance_type               = "m4.large"
  key_name                    = "xu1"
  name_prefix                 = var.cluster-name
  security_groups             = [aws_security_group.astounding-node.id]
  user_data_base64            = base64encode(local.astounding-node-userdata)

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "standard" {
  desired_capacity     = 1
  launch_configuration = aws_launch_configuration.standard.id
  max_size             = 2
  min_size             = 0
  name                 = "${var.cluster-name}-standard-asg"
  vpc_zone_identifier  = aws_subnet.astounding[*].id

  tag {
    key                 = "Name"
    value               = "${var.cluster-name}-standard-node"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster-name}"
    value               = "owned"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "fpga" {
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.astounding-node.name
  image_id                    = data.aws_ami.fpga-worker-node.id
  instance_type               = "f1.2xlarge"
  key_name                    = "xu1"
  name_prefix                 = var.cluster-name
  security_groups             = [
    aws_security_group.astounding-node.id]
  user_data_base64            = base64encode(local.fpga-node-userdata)
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "fpga" {
  desired_capacity     = 1
  launch_configuration = aws_launch_configuration.fpga.id
  max_size             = 10
  min_size             = 0
  name                 = "${var.cluster-name}-fpga-asg"
  vpc_zone_identifier  = aws_subnet.astounding[*].id

  tag {
    key                 = "Name"
    value               = "${var.cluster-name}-fpga-node"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster-name}"
    value               = "owned"
    propagate_at_launch = true
  }
}
