#
# VPC Resources
#  * VPC
#  * Subnets
#  * Internet Gateway
#  * Route Table
#

# ${var.cluster-name}
resource "aws_vpc" "astounding" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = map(
      "Name", "${var.cluster-name}-vpc",
      "kubernetes.io/cluster/${var.cluster-name}", "shared",
    )
}

resource "aws_subnet" "astounding" {
  count = 2

  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  cidr_block        = "10.0.${count.index}.0/24"
  vpc_id            = "${aws_vpc.astounding.id}"

  tags = map(
      "Name", "${var.cluster-name}-subnet",
      "kubernetes.io/cluster/${var.cluster-name}", "shared",
      "kubernetes.io/role/internal-elb", "1",
    )
}

resource "aws_subnet" "elb" {
  count = 2

  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block        = "10.0.${count.index + 100}.0/24"
  vpc_id            = aws_vpc.astounding.id

  tags = map(
      "Name", "${var.cluster-name}-elb-subnet",
      "kubernetes.io/cluster/${var.cluster-name}", "shared",
      "kubernetes.io/role/elb", "1",
    )
}

resource "aws_internet_gateway" "astounding" {
  vpc_id = "${aws_vpc.astounding.id}"

  tags = {
    Name = var.cluster-name
  }
}

resource "aws_route_table" "astounding" {
  vpc_id = "${aws_vpc.astounding.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.astounding.id}"
  }
}

resource "aws_route_table_association" "astounding" {
  count = length(aws_subnet.astounding)

  subnet_id      = aws_subnet.astounding.*.id[count.index]
  route_table_id = aws_route_table.astounding.id
}

resource "aws_route_table_association" "elb" {
  count = length(aws_subnet.elb)

  subnet_id      = aws_subnet.elb.*.id[count.index]
  route_table_id = aws_route_table.astounding.id
}
