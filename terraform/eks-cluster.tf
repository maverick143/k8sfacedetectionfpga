#
# EKS Cluster Resources
#  * IAM Role to allow EKS service to manage other AWS services
#  * EC2 Security Group to allow networking traffic with EKS cluster
#  * EKS Cluster
#

resource "aws_iam_role" "astounding-cluster" {
  name = "${var.cluster-name}-cluster-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "astounding-cluster-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = "${aws_iam_role.astounding-cluster.name}"
}

resource "aws_iam_role_policy_attachment" "astounding-cluster-AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = "${aws_iam_role.astounding-cluster.name}"
}

resource "aws_security_group" "astounding-cluster" {
  name        = "${var.cluster-name}-cluster-sg"
  description = "Cluster communication with worker nodes"
  vpc_id      = "${aws_vpc.astounding.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = var.cluster-name
  }
}

resource "aws_security_group_rule" "astounding-cluster-ingress-node-https" {
  description              = "Allow pods to communicate with the cluster API Server"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.astounding-cluster.id}"
  source_security_group_id = "${aws_security_group.astounding-node.id}"
  to_port                  = 443
  type                     = "ingress"
}

resource "aws_eks_cluster" "astounding" {
  name     = "${var.cluster-name}"
  role_arn = "${aws_iam_role.astounding-cluster.arn}"
  version  = "1.14"

  vpc_config {
    security_group_ids = ["${aws_security_group.astounding-cluster.id}"]
    subnet_ids         = "${aws_subnet.astounding[*].id}"
  }

  depends_on = [
    "aws_iam_role_policy_attachment.astounding-cluster-AmazonEKSClusterPolicy",
    "aws_iam_role_policy_attachment.astounding-cluster-AmazonEKSServicePolicy",
  ]
}
