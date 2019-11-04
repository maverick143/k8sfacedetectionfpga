# SSH bastion
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amzn-linux.id
  key_name                    = "xu1"
  instance_type               = "t2.micro"
  vpc_security_group_ids = [aws_security_group.bastion-sg.id]
  subnet_id = aws_subnet.astounding[0].id
  associate_public_ip_address = true

  tags = map(
   "Name", "${var.cluster-name}-ssh-bastion",
  )
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

resource "aws_security_group" "bastion-sg" {
  name   = "${var.cluster-name}-bastion-sg"
  vpc_id = aws_vpc.astounding.id

  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}
