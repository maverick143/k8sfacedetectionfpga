resource "aws_security_group" "astounding-redis" {
  name        = "${var.cluster-name}-redis-sg"
  description = "Security group for Redis"
  vpc_id      = aws_vpc.astounding.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = map(
     "Name", "${var.cluster-name}-redis-sg",
     "kubernetes.io/cluster/${var.cluster-name}", "owned",
    )
}

resource "aws_security_group_rule" "astounding-redis-ingress" {
  description              = "Allow nodes to communicate with redis"
  from_port                = aws_elasticache_cluster.astounding-redis.port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.astounding-redis.id
  source_security_group_id = aws_security_group.astounding-node.id
  to_port                  = aws_elasticache_cluster.astounding-redis.port
  type                     = "ingress"
}

resource "aws_elasticache_cluster" "astounding-redis" {
  cluster_id           = "astounding-redis-cluster"
  engine               = "redis"
  node_type            = "cache.m4.large"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis5.0"
  engine_version       = "5.0.4"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.astounding-redis-subnet-group.name
  security_group_ids   = [aws_security_group.astounding-redis.id]
}

resource "aws_elasticache_subnet_group" "astounding-redis-subnet-group" {
  name = "${var.cluster-name}-redis-cache-subnet"
  subnet_ids = aws_subnet.astounding[*].id
}